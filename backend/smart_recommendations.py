from datetime import date, timedelta
from sqlalchemy.orm import Session
from statistics import mean
import models


# ── Symptom thresholds (scale 0-10) ──────────────────────────
SYMPTOM_HIGH = 7
SYMPTOM_MED  = 5


def _avg(values, default=None):
    clean = [v for v in values if v is not None]
    return mean(clean) if clean else default


def generate_recommendations(db: Session, patient_id: int) -> dict:
    """
    Returns {
      current_risk: str,
      confidence_hint: str,     # user-friendly
      recommendations: list[dict],
      personalization_reasons: list[str]  # what triggered each tip
    }
    """
    patient = db.query(models.Patient).filter(
        models.Patient.id == patient_id).first()
    if not patient:
        return _default_bundle("Patient not found")

    # ── Pull context ────────────────────────────────────────
    latest = (db.query(models.SymptomRecord)
              .filter(models.SymptomRecord.patient_id == patient_id)
              .order_by(models.SymptomRecord.log_date.desc())
              .first())

    week_ago = date.today() - timedelta(days=7)
    week_symptoms = (db.query(models.SymptomRecord)
                     .filter(models.SymptomRecord.patient_id == patient_id,
                             models.SymptomRecord.log_date >= week_ago)
                     .all())
    week_lifestyle = (db.query(models.ActivityLog)
                      .filter(models.ActivityLog.patient_id == patient_id,
                              models.ActivityLog.log_date >= week_ago)
                      .all())

    if not latest:
        return _default_bundle("No symptom logs yet")

    risk = latest.predicted_risk or "Not assessed"

    # ── Aggregate lifestyle averages ────────────────────────
    avg_sleep  = _avg([l.sleep_hours   for l in week_lifestyle])
    avg_ex     = _avg([l.exercise_mins for l in week_lifestyle])
    avg_diet   = _avg([l.diet_quality  for l in week_lifestyle])
    avg_water  = _avg([float(l.water_intake_l) if l.water_intake_l else None
                       for l in week_lifestyle])

    # ── Build the tip list ──────────────────────────────────
    tips = []
    reasons = []

    # PRIORITY 1 — Risk-level tips (always include)
    tips.extend(_risk_tier_tips(risk))

    # PRIORITY 2 — Symptom-specific tips (uses actual values)
    if latest:
        for tip in _symptom_specific_tips(latest):
            tips.append(tip)
            reasons.append(tip["_trigger"])

    # PRIORITY 3 — Lifestyle gap tips
    lifestyle_tips = _lifestyle_gap_tips(
        avg_sleep, avg_ex, avg_diet, avg_water)
    for tip in lifestyle_tips:
        tips.append(tip)
        reasons.append(tip["_trigger"])

    # PRIORITY 4 — Cancer-type-specific tips
    for tip in _cancer_type_tips(patient.cancer_type):
        tips.append(tip)

    # PRIORITY 5 — Treatment phase tips
    for tip in _treatment_phase_tips(patient.treatment_start):
        tips.append(tip)

    # PRIORITY 6 — Consistency nudge
    consistency_tip = _consistency_tip(week_symptoms)
    if consistency_tip:
        tips.append(consistency_tip)

    # Deduplicate by title and cap at 10
    seen = set()
    unique = []
    for t in tips:
        if t["title"] not in seen:
            # strip internal _trigger field before returning
            t.pop("_trigger", None)
            unique.append(t)
            seen.add(t["title"])
    unique = unique[:10]

    return {
        "current_risk": risk,
        "confidence_hint": _confidence_text(latest),
        "recommendations": unique,
        "personalization_reasons": list(dict.fromkeys(reasons))[:5],
    }


# ── TIP BUILDERS ─────────────────────────────────────────────

def _risk_tier_tips(risk: str) -> list:
    if risk == "High":
        return [
            {"category": "general", "priority": "urgent",
             "title": "Contact your oncologist today",
             "body": "Your latest risk assessment is High. Please call "
                     "your medical team and describe how you're feeling."},
            {"category": "general", "priority": "high",
             "title": "Rest is your main job today",
             "body": "Put non-essential activities on hold. Sleep, hydrate, "
                     "and avoid crowds and physical strain."},
        ]
    if risk == "Medium":
        return [
            {"category": "general", "priority": "medium",
             "title": "Keep a close eye on symptoms",
             "body": "Log every day this week so we can catch any changes "
                     "early and give you sharper guidance."},
        ]
    if risk == "Low":
        return [
            {"category": "general", "priority": "low",
             "title": "You're doing well — keep it up",
             "body": "Your current risk is Low. Stay consistent with your "
                     "routine and daily logs."},
        ]
    return []


def _symptom_specific_tips(rec) -> list:
    """Tips triggered by specific high symptom values on latest log."""
    out = []

    # Fatigue
    fat = rec.fatigue or 0
    if fat >= SYMPTOM_HIGH:
        out.append({
            "category": "sleep", "priority": "high",
            "title": "Pace yourself — energy budgeting",
            "body": "Your fatigue is high. Try the 50/10 rule: 50 min of "
                    "activity, 10 min of rest. Short 20-min naps after lunch "
                    "help without hurting night sleep.",
            "_trigger": f"Fatigue is {fat}/10",
        })

    # Nausea (via weight_loss / appetite proxy)
    nau = rec.weight_loss or 0
    if nau >= SYMPTOM_MED:
        out.append({
            "category": "diet", "priority": "medium",
            "title": "Settle your stomach with small meals",
            "body": "Eat 5–6 tiny meals instead of 3 big ones. Ginger tea, "
                    "plain crackers, and cold bland foods (like yogurt) are "
                    "gentler when appetite is low.",
            "_trigger": f"Weight loss concern is {nau}/10",
        })

    # Shortness of breath
    sob = rec.shortness_of_breath or 0
    if sob >= SYMPTOM_MED:
        out.append({
            "category": "exercise", "priority": "high",
            "title": "Breathing exercise: pursed-lip breathing",
            "body": "Inhale through the nose 2 sec, exhale through pursed "
                    "lips 4 sec. Do 5 rounds whenever you feel short of breath. "
                    "If it persists at rest, contact your doctor.",
            "_trigger": f"Shortness of breath is {sob}/10",
        })

    # Chest pain
    cp = rec.chest_pain or 0
    if cp >= SYMPTOM_HIGH:
        out.append({
            "category": "general", "priority": "urgent",
            "title": "Chest pain needs a same-day call",
            "body": "High chest pain should always be checked with your "
                    "oncologist today. If it's crushing, sudden, or with "
                    "arm pain — go to emergency immediately.",
            "_trigger": f"Chest pain is {cp}/10",
        })

    # Dry cough
    dc = rec.dry_cough or 0
    if dc >= SYMPTOM_MED:
        out.append({
            "category": "general", "priority": "medium",
            "title": "Soothe a persistent dry cough",
            "body": "Try warm lemon-honey water, a bedside humidifier, and "
                    "sleeping propped up on two pillows. Avoid cold air and "
                    "smoke.",
            "_trigger": f"Dry cough is {dc}/10",
        })

    # Coughing of blood — always urgent
    cob = rec.coughing_of_blood or 0
    if cob >= 3:
        out.append({
            "category": "general", "priority": "urgent",
            "title": "Coughing blood — call your doctor now",
            "body": "Any amount of coughed-up blood should be reported to "
                    "your oncology team today. Do not wait.",
            "_trigger": f"Coughing of blood is {cob}/10",
        })

    # Swallowing difficulty
    sd = rec.swallowing_difficulty or 0
    if sd >= SYMPTOM_MED:
        out.append({
            "category": "diet", "priority": "medium",
            "title": "Eat softer foods while swallowing is hard",
            "body": "Try mashed potatoes, yogurt, smoothies, soups, and "
                    "scrambled eggs. Avoid dry bread, raw vegetables, and "
                    "very hot or spicy foods.",
            "_trigger": f"Swallowing difficulty is {sd}/10",
        })

    return out


def _lifestyle_gap_tips(avg_sleep, avg_ex, avg_diet, avg_water) -> list:
    out = []

    if avg_water is not None and avg_water < 1.5:
        out.append({
            "category": "diet", "priority": "high",
            "title": "You're under-hydrated this week",
            "body": f"Your 7-day average is {avg_water:.1f} L/day. Aim for "
                    "2+ L during treatment — set a 1L bottle nearby and "
                    "refill twice.",
            "_trigger": f"Avg water {avg_water:.1f} L/day",
        })

    if avg_sleep is not None and avg_sleep < 6:
        out.append({
            "category": "sleep", "priority": "high",
            "title": "You're short on sleep",
            "body": f"Averaging {avg_sleep:.1f} hrs/night. Cancer treatment "
                    "needs 7–9 hrs. Try a fixed bedtime, dim lights an hour "
                    "before, and no screens in bed.",
            "_trigger": f"Avg sleep {avg_sleep:.1f} hrs",
        })

    if avg_ex is not None and avg_ex < 10:
        out.append({
            "category": "exercise", "priority": "medium",
            "title": "Tiny movement goal: 10 min/day",
            "body": f"Your weekly exercise is averaging {avg_ex:.0f} min/day. "
                    "Even a slow 10-min walk after one meal reduces fatigue "
                    "and improves mood. No equipment needed.",
            "_trigger": f"Avg exercise {avg_ex:.0f} min",
        })

    if avg_diet is not None and avg_diet < 4:
        out.append({
            "category": "diet", "priority": "medium",
            "title": "Boost diet quality with 1 swap",
            "body": f"You rated diet quality {avg_diet:.1f}/10 this week. "
                    "Pick ONE meal per day and upgrade it: add a vegetable, "
                    "a protein, or a fruit. Small consistent wins beat "
                    "big overhauls.",
            "_trigger": f"Avg diet {avg_diet:.1f}/10",
        })

    return out


def _cancer_type_tips(cancer_type: str | None) -> list:
    if not cancer_type:
        return []
    ct = cancer_type.lower()

    if "lung" in ct:
        return [{
            "category": "exercise", "priority": "medium",
            "title": "Daily breathing practice (lung cancer)",
            "body": "Diaphragmatic breathing 2x/day: hand on belly, inhale "
                    "4 sec (belly rises), exhale 6 sec. Helps lung capacity "
                    "and calms anxiety.",
        }]
    if "breast" in ct:
        return [{
            "category": "exercise", "priority": "medium",
            "title": "Gentle arm mobility (breast cancer)",
            "body": "Wall-walks and shoulder rolls daily maintain range of "
                    "motion, especially after surgery. Stop at any sharp pain "
                    "and ask your physio for a guided plan.",
        }]
    if "colon" in ct or "colorectal" in ct:
        return [{
            "category": "diet", "priority": "medium",
            "title": "Fibre & hydration (colorectal cancer)",
            "body": "Soluble fibre (oats, bananas, lentils) with plenty of "
                    "water reduces constipation from opioids and "
                    "chemotherapy.",
        }]
    if "prostate" in ct:
        return [{
            "category": "exercise", "priority": "medium",
            "title": "Pelvic floor exercises (prostate cancer)",
            "body": "Kegels 3 sets of 10 reps daily help urinary control "
                    "during and after treatment.",
        }]
    return []


def _treatment_phase_tips(treatment_start) -> list:
    if not treatment_start:
        return []
    days = (date.today() - treatment_start).days
    if days < 0:
        return []
    if days < 30:
        return [{
            "category": "general", "priority": "low",
            "title": "You're in the first month — log daily",
            "body": "The first 30 days of treatment set a baseline. Even "
                    "short logs help the system learn what's normal for you.",
        }]
    if days < 90:
        return [{
            "category": "general", "priority": "low",
            "title": "Mid-treatment: watch cumulative fatigue",
            "body": "Fatigue often peaks around weeks 6–10. If you notice "
                    "it climbing, tell your team early — small adjustments "
                    "help a lot.",
        }]
    return [{
        "category": "general", "priority": "low",
        "title": f"Day {days} of treatment — you've come far",
        "body": "Long-haul treatment is a marathon. Celebrate small wins, "
                "keep logging, and don't skip follow-ups.",
    }]


def _consistency_tip(week_symptoms) -> dict | None:
    if len(week_symptoms) == 0:
        return None
    # Gap detection: latest log more than 3 days old?
    latest_log = max(s.log_date for s in week_symptoms)
    gap = (date.today() - latest_log).days
    if gap >= 3:
        return {
            "category": "general", "priority": "medium",
            "title": f"It's been {gap} days since your last log",
            "body": "Daily logs — even quick ones — make the risk predictions "
                    "dramatically more accurate. 60 seconds is all it takes.",
        }
    return None


def _confidence_text(rec) -> str:
    """User-friendly confidence hint instead of raw number."""
    # The ML service stores confidence as a decimal if it runs;
    # if the schema doesn't have it yet, just give a generic hint.
    conf = getattr(rec, "prediction_confidence", None)
    if conf is None:
        return "Based on your latest log"
    pct = int(float(conf) * 100)
    if pct >= 85:
        return f"High confidence ({pct}%)"
    if pct >= 65:
        return f"Moderate confidence ({pct}%)"
    return f"Low confidence ({pct}%) — log more days for better accuracy"


def _default_bundle(note: str) -> dict:
    return {
        "current_risk": "Not assessed yet",
        "confidence_hint": note,
        "recommendations": [
            {"category": "general", "priority": "info",
             "title": "Log your symptoms to get started",
             "body": "Open the Symptoms tab and submit today's log. Once you "
                     "do, I'll give you tips tailored to your actual data."},
            {"category": "diet", "priority": "low",
             "title": "Stay hydrated",
             "body": "2+ litres of water daily supports your body through "
                     "treatment."},
            {"category": "exercise", "priority": "low",
             "title": "10-minute daily walk",
             "body": "A short walk improves mood, energy, and sleep. "
                     "No equipment needed."},
            {"category": "sleep", "priority": "low",
             "title": "Consistent sleep schedule",
             "body": "Same bedtime and wake time every day helps your body "
                     "heal during treatment."},
        ],
        "personalization_reasons": [],
    }
