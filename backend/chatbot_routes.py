import uuid
import hashlib
from dataclasses import dataclass, field
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from sqlalchemy import text as sqltext
from datetime import date, datetime, timedelta
from pydantic import BaseModel, Field
from statistics import mean
import re
import ollama

from database import get_db
import models
import aoun_rag

router = APIRouter(prefix="/patient/{patient_id}/chat", tags=["chatbot"])

OLLAMA_MODEL      = "mistral:7b-instruct"
MAX_HISTORY_TURNS = 6
SEMANTIC_TOP_K    = 3

_conversation_history: dict[int, list[dict]] = {}
_message_sources: dict[str, list[dict]] = {}

aoun_rag.init()


# ── Schemas ────────────────────────────────────────────────────

class ChatMessage(BaseModel):
    message: str = Field(..., min_length=1, max_length=500)

class Source(BaseModel):
    source_id:   str
    title:       str
    snippet:     str
    source_type: str
    page:        int | None = None
    category:    str | None = None

class ChatReply(BaseModel):
    reply:        str
    intent:       str
    message_id:   str = ""
    suggestions:  list[str] = []
    needs_doctor: bool = False
    sources:      list[Source] = []

class FeedbackInput(BaseModel):
    message_id: str = Field(..., min_length=1, max_length=64)
    rating:     int = Field(..., ge=-1, le=1)

class FeedbackAck(BaseModel):
    status: str; message_id: str; rating: int; sources_updated: int


# ── Response Cache ─────────────────────────────────────────────
# Bypasses the RAG + LLM pipeline for repeated or similar questions.
#
# Two tiers:
#   _general_cache  — educational / factual questions (same answer for every
#                     patient).  TTL = 60 minutes.
#   _personal_cache — questions about THIS patient's own data ("how am I
#                     doing?", "my risk").  TTL = 5 minutes so fresh DB data
#                     still shows up after a new symptom log.
#
# Every cache hit gets a brand-new message_id so thumbs feedback still works.

@dataclass
class _CacheEntry:
    reply_data: dict
    created_at: datetime = field(default_factory=datetime.utcnow)

_general_cache: dict[str, _CacheEntry] = {}
_personal_cache: dict[str, _CacheEntry] = {}

_GENERAL_TTL  = timedelta(hours=1)
_PERSONAL_TTL = timedelta(minutes=5)

_PERSONAL_SIGNALS = [
    "my ", "how am i", "am i doing", "my risk", "my symptom",
    "my cancer", "my doctor", "this week", "my log", "my alert",
    "my lifestyle", "how have i", "my water", "my sleep",
    "my fatigue", "my pain", "my result",
]

def _is_personal(msg: str) -> bool:
    t = msg.lower()
    return any(s in t for s in _PERSONAL_SIGNALS)

def _cache_key(patient_id: int, msg: str, personal: bool) -> str:
    h = hashlib.md5(msg.lower().strip().encode()).hexdigest()
    return f"{patient_id}:{h}" if personal else h

def _get_cached(patient_id: int, msg: str) -> ChatReply | None:
    personal = _is_personal(msg)
    key      = _cache_key(patient_id, msg, personal)
    cache    = _personal_cache if personal else _general_cache
    ttl      = _PERSONAL_TTL   if personal else _GENERAL_TTL

    entry = cache.get(key)
    if not entry:
        return None
    if datetime.utcnow() - entry.created_at > ttl:
        del cache[key]
        return None

    # Fresh message_id on every hit so feedback attribution still works
    d = dict(entry.reply_data)
    d["message_id"] = uuid.uuid4().hex
    return ChatReply(**d)

def _put_cache(patient_id: int, msg: str, reply: ChatReply) -> None:
    personal = _is_personal(msg)
    key      = _cache_key(patient_id, msg, personal)
    cache    = _personal_cache if personal else _general_cache
    cache[key] = _CacheEntry(reply_data=reply.dict())


# ── Safety Guardrails ──────────────────────────────────────────

EMERGENCY_PHRASES = [
    "cant breathe", "can't breathe", "cannot breathe",
    "severe pain", "crushing pain", "passing out", "unconscious",
    "suicide", "kill myself", "want to die", "end it all",
    "coughing blood", "coughing up blood", "vomiting blood",
]

MEDICATION_PHRASES = [
    "dose", "dosage", "how much medicine", "how many pills",
    "should i take", "can i take", "safe to take", "ok to take",
    "safe with", "safe to use", "ok to use",
    "stop taking", "increase my", "decrease my", "skip my",
    "double my dose", "missed dose", "combine with", "mix with",
    "drug interaction", "interact with", "together with",
    "instead of", "replace my", "substitute",
]

MEDICATION_NAMES = [
    "ibuprofen", "advil", "motrin", "naproxen", "aleve",
    "aspirin", "acetaminophen", "paracetamol", "tylenol", "panadol",
    "diclofenac", "voltaren", "mefenamic",
    "morphine", "codeine", "tramadol", "oxycodone", "oxycontin",
    "fentanyl", "hydrocodone", "percocet", "vicodin",
    "chemo", "chemotherapy", "cisplatin", "carboplatin", "paclitaxel",
    "doxorubicin", "tamoxifen", "methotrexate", "5-fu", "fluorouracil",
    "gemcitabine", "pembrolizumab", "keytruda", "nivolumab", "opdivo",
    "radiation", "radiotherapy",
    "ondansetron", "zofran", "metoclopramide", "reglan",
    "dexamethasone", "prednisone", "prednisolone", "cortisone",
    "antibiotic", "antibiotics", "amoxicillin", "azithromycin",
    "metformin", "insulin", "warfarin", "heparin",
    "xanax", "valium", "ativan", "lorazepam", "diazepam", "alprazolam",
    "zoloft", "prozac", "lexapro", "sertraline", "fluoxetine",
    "vitamin c", "vitamin e", "st john's wort", "st johns wort",
]

EDUCATIONAL_PATTERNS = [
    "side effect", "side-effect", "side effects", "side-effects",
    "what is", "what are", "what's", "whats",
    "how does", "how do", "how will", "how can",
    "tell me about", "explain", "describe",
    "symptoms of", "symptoms from", "symptoms caused",
    "expect from", "expect during", "expect after", "to expect",
    "caused by", "because of", "due to",
    "after treatment", "during treatment", "before treatment",
    "long term effect", "long-term effect", "long term effects",
    "common symptoms", "feel like", "feels like",
    "help me understand", "learn about",
]


def is_emergency(msg: str) -> bool:
    return any(phrase in msg.lower().strip() for phrase in EMERGENCY_PHRASES)


def is_medication_question(msg: str) -> bool:
    text = msg.lower().strip()
    if any(pattern in text for pattern in EDUCATIONAL_PATTERNS):
        return False
    if any(phrase in text for phrase in MEDICATION_PHRASES):
        return True
    for drug in MEDICATION_NAMES:
        if re.search(rf"\b{re.escape(drug)}\b", text):
            return len(text.split()) <= 3
    return False


# ── Database Query Helpers ─────────────────────────────────────

def _patient(db, pid):
    p = db.query(models.Patient).filter(models.Patient.id == pid).first()
    if not p:
        raise HTTPException(404, "Patient not found")
    return p

def _latest_symptom(db, pid):
    return (db.query(models.SymptomRecord)
            .filter(models.SymptomRecord.patient_id == pid)
            .order_by(models.SymptomRecord.log_date.desc()).first())

def _week_symptoms(db, pid):
    cutoff = date.today() - timedelta(days=7)
    return (db.query(models.SymptomRecord)
            .filter(models.SymptomRecord.patient_id == pid,
                    models.SymptomRecord.log_date >= cutoff)
            .order_by(models.SymptomRecord.log_date.asc()).all())

def _week_lifestyle(db, pid):
    cutoff = date.today() - timedelta(days=7)
    return (db.query(models.ActivityLog)
            .filter(models.ActivityLog.patient_id == pid,
                    models.ActivityLog.log_date >= cutoff).all())

def _unread_alerts(db, pid):
    return (db.query(models.Alert)
            .filter(models.Alert.patient_id == pid, models.Alert.acknowledged == False)
            .order_by(models.Alert.created_at.desc()).limit(5).all())

def _treatment_days(p):
    if not p.treatment_start:
        return None
    d = (date.today() - p.treatment_start).days
    return d if d >= 0 else None

def _first_name(p):
    return p.full_name.split()[0] if p.full_name else "there"

def _time_greeting():
    h = datetime.now().hour
    return "morning" if h < 12 else ("afternoon" if h < 17 else "evening")


# ── Feedback Helpers ───────────────────────────────────────────

def load_feedback_map(db: Session) -> dict:
    """Return {source_id: net_rating} aggregated across all patients."""
    try:
        result = db.execute(sqltext(
            "SELECT source_id, SUM(rating)::int AS net FROM chat_feedback GROUP BY source_id"
        )).fetchall()
        return {row[0]: row[1] for row in result}
    except Exception as e:
        print(f"[FEEDBACK] No feedback map available: {e}")
        return {}


def record_feedback(db: Session, patient_id: int, message_id: str, rating: int) -> int:
    sources = _message_sources.get(message_id)
    if not sources:
        raise HTTPException(404, f"Unknown message_id: {message_id}")
    written = 0
    for src in sources:
        try:
            db.execute(sqltext(
                "INSERT INTO chat_feedback (patient_id, message_id, source_id, source_type, rating) "
                "VALUES (:pid, :mid, :sid, :stype, :r)"
            ), {"pid": patient_id, "mid": message_id,
                "sid": src["source_id"], "stype": src["source_type"], "r": rating})
            written += 1
        except Exception as e:
            print(f"[FEEDBACK] Insert failed for {src['source_id']}: {e}")
    db.commit()
    return written


# ── Structured Patient Context ─────────────────────────────────

def build_patient_context(db, p) -> str:
    lines = ["=== PATIENT PROFILE ===",
             f"Name: {p.full_name}",
             f"Cancer type: {p.cancer_type or 'Unknown'}",
             f"Cancer stage: {p.cancer_stage or 'Unknown'}",
             f"Treatment type: {p.treatment_type or 'Unknown'}",
             f"Diagnosis confirmed: {'Yes' if p.diagnosis_confirmed else 'No'}"]
    td = _treatment_days(p)
    if td is not None:
        lines.append(f"Days in treatment: {td}")

    latest = _latest_symptom(db, p.id)
    if latest:
        lines.append(f"\n=== LATEST SYMPTOM LOG ({latest.log_date}) ===")
        lines.append(f"Predicted risk: {latest.predicted_risk or 'N/A'}")
        if latest.risk_confidence:
            lines.append(f"Risk confidence: {float(latest.risk_confidence)*100:.0f}%")
        sym_map = {
            "Fatigue": latest.fatigue, "Chest pain": latest.chest_pain,
            "Shortness of breath": latest.shortness_of_breath, "Dry cough": latest.dry_cough,
            "Weight loss": latest.weight_loss, "Coughing of blood": latest.coughing_of_blood,
            "Wheezing": latest.wheezing, "Swallowing difficulty": latest.swallowing_difficulty,
        }
        for name, val in sym_map.items():
            if val is not None:
                lines.append(f"  {name}: {val}/10")
    else:
        lines.append("\n(No symptom logs yet)")

    week = _week_symptoms(db, p.id)
    if len(week) >= 2:
        first, last = week[0], week[-1]
        lines.append(f"\n=== 7-DAY TREND ({len(week)} logs) ===")
        for name, a, b in [("Fatigue", first.fatigue, last.fatigue),
                            ("Chest pain", first.chest_pain, last.chest_pain),
                            ("Breath", first.shortness_of_breath, last.shortness_of_breath)]:
            if a is not None and b is not None:
                diff  = float(b) - float(a)
                arrow = "up" if diff > 0 else ("down" if diff < 0 else "stable")
                lines.append(f"  {name}: {a}->{b} ({arrow})")

    logs = _week_lifestyle(db, p.id)
    if logs:
        def _avg(field):
            vals = [float(getattr(l, field)) for l in logs if getattr(l, field) is not None]
            return mean(vals) if vals else None
        sleep, water, ex, diet = _avg("sleep_hours"), _avg("water_intake_l"), _avg("exercise_mins"), _avg("diet_quality")
        lines.append("\n=== 7-DAY LIFESTYLE AVERAGES ===")
        if sleep is not None: lines.append(f"  Sleep: {sleep:.1f} hrs/night (target 7+)")
        if water is not None: lines.append(f"  Water: {water:.1f} L/day (target 2+)")
        if ex    is not None: lines.append(f"  Exercise: {ex:.0f} min/day (target 20+)")
        if diet  is not None: lines.append(f"  Diet quality: {diet:.1f}/10 (target 6+)")

    alerts = _unread_alerts(db, p.id)
    if alerts:
        lines.append(f"\n=== UNREAD ALERTS ({len(alerts)}) ===")
        for a in alerts[:3]:
            lines.append(f"  [{a.risk_level}] {a.message}")

    return "\n".join(lines)


# ── Semantic RAG with Feedback Re-ranking ─────────────────────

def gather_semantic_rag(query: str, patient_id: int, db: Session):
    feedback_map   = load_feedback_map(db)
    knowledge_hits = aoun_rag.search_knowledge(query, top_k=SEMANTIC_TOP_K, feedback_map=feedback_map)
    conv_hits      = aoun_rag.search_conversations(query, patient_id, top_k=SEMANTIC_TOP_K, feedback_map=feedback_map)

    sections = []
    if knowledge_hits:
        sections.append("=== RELEVANT MEDICAL KNOWLEDGE ===")
        for i, hit in enumerate(knowledge_hits, 1):
            page_str = f" (p.{hit.get('page')})" if hit.get("page") else ""
            sections.append(f"[{i}] From {hit.get('source_title', 'Knowledge')}{page_str}:\n{hit['text']}")
    if conv_hits:
        sections.append("\n=== RELEVANT PAST CONVERSATIONS WITH THIS PATIENT ===")
        for i, hit in enumerate(conv_hits, 1):
            sections.append(f"[{i}] {hit['text']}")

    context_text   = "\n".join(sections) if sections else ""
    sources        = []
    source_records = []

    for hit in knowledge_hits:
        snippet = re.sub(r"^\[[A-Z ]+\]\s*", "", hit["text"])
        if len(snippet) > 220:
            snippet = snippet[:220].rsplit(" ", 1)[0] + "..."
        sources.append({"source_id": hit.get("source_id", ""), "title": hit.get("source_title", "Knowledge"),
                        "snippet": snippet, "source_type": hit.get("source_type", "knowledge"),
                        "page": hit.get("page"), "category": hit.get("category")})
        source_records.append({"source_id": hit.get("source_id", ""), "source_type": hit.get("source_type", "knowledge")})

    for hit in conv_hits:
        snippet = hit["text"]
        if len(snippet) > 220:
            snippet = snippet[:220].rsplit(" ", 1)[0] + "..."
        sources.append({"source_id": hit.get("source_id", ""), "title": "Past conversation",
                        "snippet": snippet, "source_type": "conversation", "page": None, "category": None})
        source_records.append({"source_id": hit.get("source_id", ""), "source_type": "conversation"})

    return context_text, sources, source_records


# ── System Prompt & LLM ────────────────────────────────────────

def build_system_prompt(patient_context: str, semantic_context: str, time_of_day: str) -> str:
    semantic_block = f"\n\nRETRIEVED CONTEXT (use when relevant):\n{semantic_context}" if semantic_context else ""
    return f"""You are Aoun (عون), a supportive cancer-care assistant integrated into a patient monitoring app.

YOUR ROLE:
- Help cancer patients understand their symptoms, lifestyle, and progress.
- Provide evidence-based wellness tips and emotional support.
- Use the patient's logged data AND the retrieved context below to give grounded, personalized answers.

HARD RULES (NEVER BREAK):
- You are NOT a doctor. Never diagnose, never prescribe.
- Never recommend specific medication doses, stopping/starting medications, or changing treatment.
- NEVER say it is "safe" or "okay" to take any medication, even over-the-counter.
- For serious medical questions, always tell the patient to contact their oncologist.
- If the patient mentions severe symptoms (can't breathe, blood in cough, chest pain 9+/10), tell them to seek immediate medical care.
- Keep responses under 150 words. Be warm but concise.
- Do not invent numbers. Only use numbers from the data below.
- Current time of day: {time_of_day}. Greet appropriately.

PATIENT DATA (retrieved fresh from database):
{patient_context}{semantic_block}

Respond naturally and supportively, grounded in the data and retrieved context above."""


def call_llm(system_prompt: str, history: list, user_message: str) -> str:
    messages = [{"role": "system", "content": system_prompt}]
    messages.extend(history)
    messages.append({"role": "user", "content": user_message})
    try:
        response = ollama.chat(model=OLLAMA_MODEL, messages=messages,
                               options={"temperature": 0.7, "num_predict": 300})
        return response["message"]["content"].strip()
    except Exception as e:
        return (f"I'm having trouble reaching my reasoning engine right now ({type(e).__name__}). "
                "Please try again in a moment, or contact support if this persists.")


# ── Endpoints ──────────────────────────────────────────────────

@router.post("", response_model=ChatReply)
def chat(patient_id: int, payload: ChatMessage, db: Session = Depends(get_db)):
    p          = _patient(db, patient_id)
    msg        = payload.message
    message_id = uuid.uuid4().hex

    # Safety check 1: hard-block emergency phrases — no LLM call
    if is_emergency(msg):
        return ChatReply(
            reply="[URGENT] This sounds urgent. If you're experiencing severe symptoms — "
                  "trouble breathing, chest pain, uncontrolled bleeding, or loss of "
                  "consciousness — call emergency services or go to the nearest hospital RIGHT NOW. "
                  "I'm flagging this for your medical team.",
            intent="emergency", message_id=message_id, needs_doctor=True,
            suggestions=["Call my doctor"], sources=[],
        )

    # Safety check 2: block medication advice requests — no LLM call
    if is_medication_question(msg):
        return ChatReply(
            reply="I can't give medication advice — even for over-the-counter drugs. "
                  "Cancer treatments can interact unpredictably with many medications. "
                  "Please contact your oncologist or pharmacist before taking anything new.",
            intent="medication", message_id=message_id, needs_doctor=True,
            suggestions=["Log a side effect", "Contact my doctor"], sources=[],
        )

    # Cache check — skip the entire RAG + LLM pipeline on a hit
    cached = _get_cached(patient_id, msg)
    if cached:
        return cached

    # Build structured patient context + semantic RAG with feedback re-ranking
    patient_context  = build_patient_context(db, p)
    semantic_context, sources, source_records = gather_semantic_rag(msg, patient_id, db)
    system_prompt    = build_system_prompt(patient_context, semantic_context, _time_greeting())

    history    = _conversation_history.get(patient_id, [])
    reply_text = call_llm(system_prompt, history, msg)

    # Update rolling conversation history
    history.append({"role": "user", "content": msg})
    history.append({"role": "assistant", "content": reply_text})
    _conversation_history[patient_id] = history[-(MAX_HISTORY_TURNS * 2):]

    # Save turn to ChromaDB + register sources for feedback attribution
    aoun_rag.save_conversation_turn(patient_id, msg, reply_text)
    _message_sources[message_id] = source_records

    needs_doctor = any(word in reply_text.lower() for word in
                       ["see your doctor", "contact your oncologist",
                        "medical team", "seek immediate", "emergency"])

    final_reply = ChatReply(
        reply=reply_text, intent="llm_response", message_id=message_id,
        suggestions=["How am I doing this week?", "Show today's tips", "Review my lifestyle"],
        needs_doctor=needs_doctor, sources=[Source(**s) for s in sources],
    )

    # Store in cache for future identical/similar questions
    _put_cache(patient_id, msg, final_reply)

    return final_reply


@router.get("/welcome", response_model=ChatReply)
def welcome(patient_id: int, db: Session = Depends(get_db)):
    p      = _patient(db, patient_id)
    latest = _latest_symptom(db, p.id)
    _conversation_history[patient_id] = []
    greeting = f"Good {_time_greeting()}, {_first_name(p)}! I'm Aoun, your cancer-care assistant."
    if latest and latest.predicted_risk:
        greeting += f" Your latest risk level is {latest.predicted_risk}."
    else:
        greeting += " I don't have a recent symptom log from you yet — log your symptoms when you can."
    greeting += " How can I help today?"
    return ChatReply(
        reply=greeting, intent="greeting", message_id=uuid.uuid4().hex,
        suggestions=["How am I doing this week?", "Show today's tips",
                     "Review my lifestyle", "Any new alerts?"], sources=[],
    )


@router.post("/feedback", response_model=FeedbackAck)
def feedback(patient_id: int, payload: FeedbackInput, db: Session = Depends(get_db)):
    if payload.rating not in (-1, 1):
        raise HTTPException(400, "Rating must be +1 or -1")
    _patient(db, patient_id)
    written = record_feedback(db, patient_id, payload.message_id, payload.rating)
    return FeedbackAck(status="ok", message_id=payload.message_id,
                       rating=payload.rating, sources_updated=written)


@router.get("/rag-stats")
def rag_stats(patient_id: int, db: Session = Depends(get_db)):
    s = aoun_rag.stats()
    b = aoun_rag.breakdown()
    feedback_summary = {"total": 0, "positive": 0, "negative": 0, "blocked": 0}
    try:
        row = db.execute(sqltext(
            "SELECT COUNT(*) AS total, "
            "SUM(CASE WHEN rating=1 THEN 1 ELSE 0 END) AS positive, "
            "SUM(CASE WHEN rating=-1 THEN 1 ELSE 0 END) AS negative FROM chat_feedback"
        )).fetchone()
        if row:
            feedback_summary.update({"total": int(row[0] or 0),
                                     "positive": int(row[1] or 0),
                                     "negative": int(row[2] or 0)})
        fmap = load_feedback_map(db)
        feedback_summary["blocked"] = sum(1 for net in fmap.values() if net <= aoun_rag.BLOCK_THRESHOLD)
    except Exception as e:
        print(f"[FEEDBACK] stats error: {e}")
    return {
        "total_knowledge_entries": s["knowledge_entries"],
        "total_conversation_turns": s["conversation_turns"],
        "faq_entries": b["faq"], "pdf_chunks": b["pdf_chunks"], "pdf_files": b["pdf_files"],
        "feedback": feedback_summary,
        "cache_stats": {
            "general_cached": len(_general_cache),
            "personal_cached": len(_personal_cache),
        },
    }
