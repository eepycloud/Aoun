import os
import uuid
from datetime import datetime

import chromadb
from chromadb.config import Settings
from sentence_transformers import SentenceTransformer

from knowledge_base import get_all_entries, get_entry_text

# ---- Configuration ----
EMBED_MODEL_NAME = "all-MiniLM-L6-v2"
CHROMA_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                          "chroma_store")
KNOWLEDGE_COLLECTION = "knowledge"
CONVERSATIONS_COLLECTION = "conversations"

# Feedback weighting parameters
FEEDBACK_BOOST_PER_POSITIVE = 0.05   # each thumbs-up adds 5% score
FEEDBACK_PENALTY_PER_NEGATIVE = 0.10 # each thumbs-down subtracts 10%
BLOCK_THRESHOLD = -3                 # net rating <= -3 drops the source entirely
OVER_FETCH_MULTIPLIER = 3            # fetch 3x top_k so feedback filtering has room

# ---- Lazy globals ----
_embedder = None
_client = None
_knowledge_col = None
_conversations_col = None
_initialized = False


def _get_embedder():
    global _embedder
    if _embedder is None:
        print(f"[RAG] Loading embedding model: {EMBED_MODEL_NAME}")
        _embedder = SentenceTransformer(EMBED_MODEL_NAME)
        print("[RAG] Embedding model ready")
    return _embedder


def _get_client():
    global _client
    if _client is None:
        os.makedirs(CHROMA_DIR, exist_ok=True)
        _client = chromadb.PersistentClient(
            path=CHROMA_DIR,
            settings=Settings(anonymized_telemetry=False),
        )
    return _client


def _embed(texts):
    model = _get_embedder()
    if isinstance(texts, str):
        texts = [texts]
    return model.encode(texts, show_progress_bar=False).tolist()


def _seed_knowledge():
    global _knowledge_col
    entries = get_all_entries()
    existing = _knowledge_col.get(where={"source_type": "faq"}, include=[])
    existing_ids = set(existing.get("ids", []))

    new_entries = [e for e in entries if e["id"] not in existing_ids]
    if not new_entries:
        print(f"[RAG] FAQ knowledge already seeded ({len(entries)} entries)")
        return

    print(f"[RAG] Seeding {len(new_entries)} new FAQ entries...")
    texts = [get_entry_text(e) for e in new_entries]
    embeddings = _embed(texts)
    metadatas = [{
        "source_type": "faq",
        "source_file": "builtin_faq",
        "source_title": "Aoun FAQ",
        "category": e["category"],
        "question": e["question"],
    } for e in new_entries]

    _knowledge_col.add(
        ids=[e["id"] for e in new_entries],
        documents=texts,
        embeddings=embeddings,
        metadatas=metadatas,
    )
    print(f"[RAG] FAQ seeded ({len(entries)} total entries)")


def init():
    global _knowledge_col, _conversations_col, _initialized
    if _initialized:
        return

    client = _get_client()
    _knowledge_col = client.get_or_create_collection(
        name=KNOWLEDGE_COLLECTION,
        metadata={"description": "FAQ + ingested PDF content"},
    )
    _conversations_col = client.get_or_create_collection(
        name=CONVERSATIONS_COLLECTION,
        metadata={"description": "Per-patient chat history for retrieval"},
    )

    _seed_knowledge()
    _initialized = True
    print("[RAG] Initialization complete")


# ---- Feedback-weighted scoring ----

def apply_feedback_weights(hits: list, feedback_map: dict) -> list:
    """Adjust the order of a hit list using a feedback_map.

    feedback_map: {source_id: net_rating} where net_rating is the sum of
                  +1 and -1 ratings for that source.

    Returns a NEW list, re-sorted, with heavily-downvoted sources removed.
    Each hit is expected to have 'source_id' and 'distance' keys.
    Lower 'distance' = more relevant (ChromaDB convention).
    """
    weighted = []
    for hit in hits:
        sid = hit.get("source_id", "")
        net = feedback_map.get(sid, 0)

        if net <= BLOCK_THRESHOLD:
            # Hard-block repeatedly downvoted sources
            continue

        # Effective score: lower is better.
        # Positive feedback reduces distance (makes it rank higher).
        # Negative feedback increases distance.
        base = hit.get("distance", 0.0) or 0.0
        if net > 0:
            adjusted = base * (1.0 - FEEDBACK_BOOST_PER_POSITIVE * net)
        elif net < 0:
            adjusted = base * (1.0 + FEEDBACK_PENALTY_PER_NEGATIVE * abs(net))
        else:
            adjusted = base

        hit_copy = dict(hit)
        hit_copy["distance_adjusted"] = max(0.0, adjusted)
        hit_copy["feedback_net"] = net
        weighted.append(hit_copy)

    weighted.sort(key=lambda h: h["distance_adjusted"])
    return weighted


# ---- Retrieval ----

def search_knowledge(query: str, top_k: int = 3,
                     feedback_map: dict | None = None) -> list:
    """Search the knowledge collection, optionally re-ranked by feedback.

    Returns list of dicts with keys:
      text, source_id, source_type, source_file, source_title,
      category, page, question, distance, distance_adjusted (if weighted),
      feedback_net (if weighted)
    """
    init()
    try:
        # Over-fetch when we have feedback to rerank from
        over_fetch = top_k * OVER_FETCH_MULTIPLIER if feedback_map else top_k

        q_emb = _embed(query)[0]
        results = _knowledge_col.query(
            query_embeddings=[q_emb],
            n_results=over_fetch,
        )
        ids   = results.get("ids",       [[]])[0]
        docs  = results.get("documents", [[]])[0]
        metas = results.get("metadatas", [[]])[0]
        dists = results.get("distances", [[]])[0]

        out = []
        for i, (doc, meta, dist) in enumerate(zip(docs, metas, dists)):
            meta = meta or {}
            out.append({
                "source_id":    ids[i] if i < len(ids) else "",
                "text":         doc,
                "source_type":  meta.get("source_type", "unknown"),
                "source_file":  meta.get("source_file", ""),
                "source_title": meta.get("source_title", "Knowledge"),
                "category":     meta.get("category"),
                "page":         meta.get("page"),
                "question":     meta.get("question"),
                "distance":     dist,
            })

        if feedback_map:
            out = apply_feedback_weights(out, feedback_map)

        return out[:top_k]
    except Exception as e:
        print(f"[RAG] Knowledge search error: {e}")
        return []


def search_conversations(query: str, patient_id: int, top_k: int = 3,
                         feedback_map: dict | None = None) -> list:
    init()
    try:
        over_fetch = top_k * OVER_FETCH_MULTIPLIER if feedback_map else top_k

        q_emb = _embed(query)[0]
        results = _conversations_col.query(
            query_embeddings=[q_emb],
            n_results=over_fetch,
            where={"patient_id": patient_id},
        )
        ids   = results.get("ids",       [[]])[0]
        docs  = results.get("documents", [[]])[0]
        metas = results.get("metadatas", [[]])[0]
        dists = results.get("distances", [[]])[0]

        out = []
        for i, (doc, meta, dist) in enumerate(zip(docs, metas, dists)):
            meta = meta or {}
            out.append({
                "source_id":    ids[i] if i < len(ids) else "",
                "text":         doc,
                "source_type":  "conversation",
                "source_title": "Past conversation",
                "timestamp":    meta.get("timestamp", ""),
                "user_message": meta.get("user_message", ""),
                "distance":     dist,
            })

        if feedback_map:
            out = apply_feedback_weights(out, feedback_map)

        return out[:top_k]
    except Exception as e:
        print(f"[RAG] Conversation search error: {e}")
        return []


# ---- Persistence ----

def save_conversation_turn(patient_id: int, user_msg: str,
                           assistant_msg: str) -> str:
    """Save a turn. Returns the generated source_id for future reference."""
    init()
    try:
        combined = (f"Patient asked: {user_msg}\n"
                    f"Aoun replied: {assistant_msg}")
        emb = _embed(combined)[0]
        turn_id = f"conv_{patient_id}_{uuid.uuid4().hex[:12]}"

        _conversations_col.add(
            ids=[turn_id],
            documents=[combined],
            embeddings=[emb],
            metadatas=[{
                "patient_id": patient_id,
                "timestamp": datetime.utcnow().isoformat(),
                "user_message": user_msg[:200],
            }],
        )
        return turn_id
    except Exception as e:
        print(f"[RAG] Save conversation error: {e}")
        return ""


# ---- Diagnostic ----

def stats() -> dict:
    init()
    return {
        "knowledge_entries": _knowledge_col.count(),
        "conversation_turns": _conversations_col.count(),
    }


def breakdown() -> dict:
    init()
    out = {"faq": 0, "pdf_chunks": 0, "pdf_files": set()}
    try:
        all_meta = _knowledge_col.get(include=["metadatas"])
        for m in (all_meta.get("metadatas") or []):
            if not m:
                continue
            if m.get("source_type") == "faq":
                out["faq"] += 1
            elif m.get("source_type") == "pdf":
                out["pdf_chunks"] += 1
                sf = m.get("source_file")
                if sf:
                    out["pdf_files"].add(sf)
        out["pdf_files"] = sorted(out["pdf_files"])
    except Exception as e:
        print(f"[RAG] Breakdown error: {e}")
    return out
