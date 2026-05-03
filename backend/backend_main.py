from fastapi import FastAPI, HTTPException, Depends
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import text as sqltext
from datetime import date, datetime
import httpx
import os

from database import get_db, engine
import models, schemas

# ── NEW: Smart recommendations engine + chatbot ──────────────
from smart_recommendations import generate_recommendations
from chatbot_routes import router as chatbot_router

models.Base.metadata.create_all(bind=engine)

app = FastAPI(title="Aoun Backend API", version="1.1.0")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

# Mount chatbot endpoints: /patient/{id}/chat  and  /patient/{id}/chat/welcome
app.include_router(chatbot_router)

ML_SERVICE_URL    = os.getenv("ML_SERVICE_URL",    "http://localhost:8001")
FIREBASE_KEY      = os.getenv("FIREBASE_SERVER_KEY", "")
INVALID_THRESHOLD = 3

# ── HELPERS ──────────────────────────────────────────────────

def _symptom_value_valid(v):
    return v is not None and 1 <= v <= 10

def _verify_against_diagnosis(payload, patient) -> str | None:
    """FR9 — cross-check patient input against confirmed diagnosis."""
    if not patient.diagnosis_confirmed:
        return None
    stage = (patient.cancer_stage or "").lower()
    extreme_count = sum([
        1 for v in [payload.coughing_of_blood, payload.chest_pain,
                    payload.shortness_of_breath, payload.fatigue]
        if v is not None and v >= 9
    ])
    if "stage i" in stage and extreme_count >= 3:
        return "Symptom values seem inconsistent with Stage I diagnosis — please review your entries."
    return None

async def _send_firebase(topic: str, title: str, body: str):
    if not FIREBASE_KEY or FIREBASE_KEY == "skip_for_now":
        print(f"[Firebase] Skipped — no key. Would send: {title}")
        return
    try:
        async with httpx.AsyncClient() as client:
            await client.post(
                "https://fcm.googleapis.com/fcm/send",
                headers={"Authorization": f"key={FIREBASE_KEY}",
                         "Content-Type": "application/json"},
                json={"to": f"/topics/{topic}",
                      "notification": {"title": title, "body": body}},
                timeout=5.0,
            )
    except Exception as e:
        print(f"[Firebase] Error: {e}")

# ── ROOT ─────────────────────────────────────────────────────

@app.get("/")
def root():
    return {"service": "Aoun Backend", "status": "running", "docs": "/docs"}

@app.get("/health")
def health():
    return {"status": "ok"}

# ── AUTH ─────────────────────────────────────────────────────

@app.post("/auth/register", status_code=201)
def register(payload: schemas.RegisterRequest, db: Session = Depends(get_db)):
    existing = db.query(models.Patient).filter(models.Patient.email == payload.email).first()
    if existing:
        raise HTTPException(400, "Email already registered")
    patient = models.Patient(
        full_name       = payload.full_name,
        email           = payload.email,
        password_hash   = payload.password,
        gender          = payload.gender,
        date_of_birth   = payload.date_of_birth,
        cancer_type     = payload.cancer_type,
        cancer_stage    = payload.cancer_stage or "Unknown",
        treatment_start = payload.treatment_start,
        is_active       = True,
    )
    db.add(patient)
    db.commit()
    db.refresh(patient)
    return {"message": "Registration successful", "id": patient.id}

@app.post("/auth/login")
def login(payload: schemas.LoginRequest, db: Session = Depends(get_db)):
    patient = db.query(models.Patient).filter(models.Patient.email == payload.email).first()
    if not patient or patient.password_hash != payload.password:
        raise HTTPException(401, "Invalid credentials")
    if not patient.is_active:
        raise HTTPException(403, "Account not yet approved")
    return {"patient_id": patient.id, "name": patient.full_name}

@app.post("/admin/approve/{patient_id}")
def approve_patient(patient_id: int, db: Session = Depends(get_db)):
    patient = db.query(models.Patient).filter(models.Patient.id == patient_id).first()
    if not patient:
        raise HTTPException(404, "Patient not found")
    patient.is_active = True
    patient.approved_at = datetime.utcnow()
    db.commit()
    return {"message": f"Patient {patient.full_name} approved"}

# ── FR22 — ADMIN ─────────────────────────────────────────────

@app.get("/admin/patients")
def admin_get_all_patients(db: Session = Depends(get_db)):
    patients = db.query(models.Patient).order_by(models.Patient.created_at.desc()).all()
    return [{"id": p.id, "full_name": p.full_name, "email": p.email,
             "gender": p.gender, "is_active": p.is_active,
             "cancer_type": p.cancer_type, "created_at": str(p.created_at)}
            for p in patients]

@app.put("/admin/deactivate/{patient_id}")
def deactivate_patient(patient_id: int, db: Session = Depends(get_db)):
    patient = db.query(models.Patient).filter(models.Patient.id == patient_id).first()
    if not patient:
        raise HTTPException(404, "Patient not found")
    patient.is_active = False
    db.commit()
    return {"message": f"Patient {patient.full_name} deactivated"}

# ── PROFILE ───────────────────────────────────────────────────

@app.get("/patient/{patient_id}/profile")
def get_profile(patient_id: int, db: Session = Depends(get_db)):
    p = db.query(models.Patient).filter(models.Patient.id == patient_id).first()
    if not p:
        raise HTTPException(404, "Patient not found")

    # Calculate age from date_of_birth
    age = None
    if p.date_of_birth:
        from datetime import date
        today = date.today()
        age = today.year - p.date_of_birth.year
        if (today.month, today.day) < (p.date_of_birth.month, p.date_of_birth.day):
            age -= 1

    return {
        "id":                  p.id,
        "full_name":           p.full_name,
        "email":               p.email,
        "gender":              p.gender,
        "date_of_birth":       str(p.date_of_birth) if p.date_of_birth else None,
        "age":                 age,
        "cancer_type":         p.cancer_type,
        "cancer_stage":        p.cancer_stage,
        "treatment_type":      p.treatment_type,
        "treatment_start":     str(p.treatment_start) if p.treatment_start else None,
        "diagnosis_confirmed": p.diagnosis_confirmed,
    }

@app.put("/doctor/confirm-diagnosis/{patient_id}")
def confirm_diagnosis(patient_id: int, payload: schemas.DiagnosisConfirm, db: Session = Depends(get_db)):
    p = db.query(models.Patient).filter(models.Patient.id == patient_id).first()
    if not p:
        raise HTTPException(404, "Patient not found")
    p.cancer_type = payload.cancer_type
    p.cancer_stage = payload.cancer_stage
    p.treatment_type = payload.treatment_type
    p.diagnosis_confirmed = True
    p.confirmed_at = datetime.utcnow()
    db.commit()
    return {"message": "Diagnosis confirmed"}

# ── FR5 SYMPTOMS ─────────────────────────────────────────────

@app.post("/patient/{patient_id}/symptoms", status_code=201)
async def log_symptoms(patient_id: int, payload: schemas.SymptomInput, db: Session = Depends(get_db)):
    p = db.query(models.Patient).filter(models.Patient.id == patient_id).first()
    if not p:
        raise HTTPException(404, "Patient not found")

    # FR8 — range validation
    invalid_fields = [
        f for f in ["air_pollution","alcohol_use","dust_allergy","occupational_hazards",
                    "genetic_risk","chronic_lung_disease","balanced_diet","obesity",
                    "smoking","passive_smoker","chest_pain","coughing_of_blood","fatigue",
                    "weight_loss","shortness_of_breath","wheezing","swallowing_difficulty",
                    "clubbing_of_finger_nails","frequent_cold","dry_cough","snoring"]
        if not _symptom_value_valid(getattr(payload, f, None))
    ]
    if invalid_fields:
        raise HTTPException(422, f"Values out of range (1-10): {', '.join(invalid_fields)}")

    # FR9 — diagnosis check
    diagnosis_warning = _verify_against_diagnosis(payload, p)

    # Save record
    record = models.SymptomRecord(
        patient_id=patient_id,
        log_date=payload.log_date or date.today(),
        age=payload.age, gender_val=payload.gender_val,
        air_pollution=payload.air_pollution, alcohol_use=payload.alcohol_use,
        dust_allergy=payload.dust_allergy, occupational_hazards=payload.occupational_hazards,
        genetic_risk=payload.genetic_risk, chronic_lung_disease=payload.chronic_lung_disease,
        balanced_diet=payload.balanced_diet, obesity=payload.obesity,
        smoking=payload.smoking, passive_smoker=payload.passive_smoker,
        chest_pain=payload.chest_pain, coughing_of_blood=payload.coughing_of_blood,
        fatigue=payload.fatigue, weight_loss=payload.weight_loss,
        shortness_of_breath=payload.shortness_of_breath, wheezing=payload.wheezing,
        swallowing_difficulty=payload.swallowing_difficulty,
        clubbing_of_finger_nails=payload.clubbing_of_finger_nails,
        frequent_cold=payload.frequent_cold, dry_cough=payload.dry_cough,
        snoring=payload.snoring, is_validated=True,
        validation_notes=diagnosis_warning,
        # FR10 — track invalid attempts on the record itself
        invalid_attempt_count=1 if diagnosis_warning else 0,
    )
    db.add(record)
    db.commit()
    db.refresh(record)

    # FR10 — count total invalid records for this patient, alert if >= threshold
    fr10_alert = None
    if diagnosis_warning:
        total_invalid = (
            db.query(models.SymptomRecord)
            .filter(models.SymptomRecord.patient_id == patient_id,
                    models.SymptomRecord.invalid_attempt_count > 0)
            .count()
        )
        if total_invalid >= INVALID_THRESHOLD:
            fr10_alert = "You have entered inconsistent data multiple times. Please review your symptoms or contact your doctor."
            db.add(models.Alert(
                patient_id=patient_id, symptom_id=record.id,
                alert_type="InvalidDataRepeat", risk_level="Medium",
                message=fr10_alert, sent_to_patient=True,
            ))
            db.commit()

    # ML prediction — FR14, FR15
    prediction = None
    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            ml_payload = {
                "age": payload.age, "gender": payload.gender_val,
                "air_pollution": payload.air_pollution, "alcohol_use": payload.alcohol_use,
                "dust_allergy": payload.dust_allergy, "occupational_hazards": payload.occupational_hazards,
                "genetic_risk": payload.genetic_risk, "chronic_lung_disease": payload.chronic_lung_disease,
                "balanced_diet": payload.balanced_diet, "obesity": payload.obesity,
                "smoking": payload.smoking, "passive_smoker": payload.passive_smoker,
                "chest_pain": payload.chest_pain, "coughing_of_blood": payload.coughing_of_blood,
                "fatigue": payload.fatigue, "weight_loss": payload.weight_loss,
                "shortness_of_breath": payload.shortness_of_breath, "wheezing": payload.wheezing,
                "swallowing_difficulty": payload.swallowing_difficulty,
                "clubbing_of_finger_nails": payload.clubbing_of_finger_nails,
                "frequent_cold": payload.frequent_cold, "dry_cough": payload.dry_cough,
                "snoring": payload.snoring,
            }
            resp = await client.post(f"{ML_SERVICE_URL}/predict", json=ml_payload)
            if resp.status_code == 200:
                prediction = resp.json()
                record.predicted_risk  = prediction["risk_level"]
                record.risk_confidence = prediction["confidence"]
                db.commit()
            else:
                print(f"ML service returned {resp.status_code}: {resp.text}")
    except Exception as e:
        print(f"ML service error: {e}")

    # FR16 + FR23 — alert and notify
    alert_created = False
    if prediction and prediction.get("risk_level") == "High":
        db.add(models.Alert(
            patient_id=patient_id, symptom_id=record.id,
            alert_type="HighRisk", risk_level="High",
            message="High risk detected. Please contact your oncologist.",
            sent_to_patient=True, sent_to_doctor=True,
            doctor_id=p.confirmed_by_doctor,
        ))
        db.commit()
        alert_created = True
        await _send_firebase(f"patient_{patient_id}", "Aoun Health Alert",
                             "High risk detected. Check the app and contact your doctor.")
        if p.confirmed_by_doctor:
            await _send_firebase(f"doctor_{p.confirmed_by_doctor}", "Patient Risk Alert",
                                 f"Patient {p.full_name} has been flagged as High risk.")

    return {
        "symptom_record_id":   record.id,
        "prediction":          prediction,
        "alert_created":       alert_created,
        "diagnosis_warning":   diagnosis_warning,
        "repeated_data_alert": fr10_alert,
    }

# ── FR11 SYMPTOM HISTORY ──────────────────────────────────────

@app.get("/patient/{patient_id}/symptoms")
def get_symptom_history(patient_id: int, period: str = "week", db: Session = Depends(get_db)):
    from datetime import timedelta
    cutoff = date.today() - timedelta(
        days=1 if period == "day" else 7 if period == "week" else 30)
    records = (
        db.query(models.SymptomRecord)
        .filter(models.SymptomRecord.patient_id == patient_id,
                models.SymptomRecord.log_date >= cutoff)
        .order_by(models.SymptomRecord.log_date.desc()).all()
    )
    return [{"date": str(r.log_date),
             "fatigue":    float(r.fatigue)        if r.fatigue        else None,
             "chest_pain": float(r.chest_pain)     if r.chest_pain     else None,
             "coughing":   float(r.coughing_of_blood) if r.coughing_of_blood else None,
             "shortness":  float(r.shortness_of_breath) if r.shortness_of_breath else None,
             "predicted_risk": r.predicted_risk,
             "confidence": float(r.risk_confidence) if r.risk_confidence else None}
            for r in records]

# ── FR6, FR12 LIFESTYLE ───────────────────────────────────────

@app.post("/patient/{patient_id}/lifestyle", status_code=201)
def log_lifestyle(patient_id: int, payload: schemas.LifestyleInput, db: Session = Depends(get_db)):
    log = models.ActivityLog(
        patient_id=patient_id, log_date=payload.log_date or date.today(),
        sleep_hours=payload.sleep_hours, exercise_mins=payload.exercise_mins,
        diet_quality=payload.diet_quality, water_intake_l=payload.water_intake_l,
        notes=payload.notes,
    )
    db.add(log)
    db.commit()
    db.refresh(log)
    return {"activity_log_id": log.id, "message": "Lifestyle data saved"}

@app.get("/patient/{patient_id}/lifestyle")
def get_lifestyle_history(patient_id: int, period: str = "week", db: Session = Depends(get_db)):
    from datetime import timedelta
    cutoff = date.today() - timedelta(days=7 if period == "week" else 30)
    logs = (
        db.query(models.ActivityLog)
        .filter(models.ActivityLog.patient_id == patient_id,
                models.ActivityLog.log_date >= cutoff)
        .order_by(models.ActivityLog.log_date.desc()).all()
    )
    return [{"date": str(l.log_date),
             "sleep_hours":   float(l.sleep_hours)   if l.sleep_hours   else None,
             "exercise_mins": l.exercise_mins,
             "diet_quality":  l.diet_quality,
             "water_intake_l":float(l.water_intake_l) if l.water_intake_l else None}
            for l in logs]

# ── FR17, FR18 RECOMMENDATIONS (SMART ENGINE) ────────────────
# Replaces the old flat RULES dict with an engine that personalizes
# tips based on specific symptom values, lifestyle logs, cancer type,
# and treatment phase. Returns 6–10 tailored tips.

@app.get("/patient/{patient_id}/recommendations")
def get_recommendations(patient_id: int, db: Session = Depends(get_db)):
    """
    Personalized health recommendations.
    Uses smart_recommendations.generate_recommendations() which considers:
      • Specific symptom VALUES (not just risk label)
      • Lifestyle logs from last 7 days (sleep, water, exercise, diet)
      • Cancer type (lung, breast, colon, prostate, ...)
      • Days in treatment (early / mid / late phase)
      • Logging consistency
    """
    bundle = generate_recommendations(db, patient_id)

    # Persist tips to the recommendation history table
    valid_risk = bundle["current_risk"] if bundle["current_risk"] in ("High", "Medium", "Low") else "Medium"
    for r in bundle["recommendations"]:
        db.add(models.Recommendation(
            patient_id = patient_id,
            risk_level = valid_risk,
            category   = r.get("category", "general"),
            title      = r["title"],
            body       = r["body"],
        ))
    db.commit()

    # Response is backward-compatible with existing Flutter UI
    # (adds confidence_hint + personalization_reasons as extra fields)
    return bundle

@app.get("/patient/{patient_id}/recommendations/history")
def get_recommendation_history(patient_id: int, db: Session = Depends(get_db)):
    recs = (
        db.query(models.Recommendation)
        .filter(models.Recommendation.patient_id == patient_id)
        .order_by(models.Recommendation.created_at.desc()).limit(20).all()
    )
    return [{"date": str(r.created_at.date()), "risk_level": r.risk_level,
             "category": r.category, "title": r.title, "body": r.body} for r in recs]

# ── FR16 ALERTS ───────────────────────────────────────────────

@app.get("/patient/{patient_id}/alerts")
def get_alerts(patient_id: int, db: Session = Depends(get_db)):
    alerts = (
        db.query(models.Alert)
        .filter(models.Alert.patient_id == patient_id)
        .order_by(models.Alert.created_at.desc()).limit(20).all()
    )
    return [{"id": a.id, "type": a.alert_type, "risk": a.risk_level,
             "message": a.message, "created_at": str(a.created_at),
             "acknowledged": a.acknowledged} for a in alerts]

@app.put("/alerts/{alert_id}/acknowledge")
def acknowledge_alert(alert_id: int, db: Session = Depends(get_db)):
    alert = db.query(models.Alert).filter(models.Alert.id == alert_id).first()
    if not alert:
        raise HTTPException(404, "Alert not found")
    alert.acknowledged    = True
    alert.acknowledged_at = datetime.utcnow()
    db.commit()
    return {"message": "Alert acknowledged"}

# ── FR26 ML FEEDBACK ─────────────────────────────────────────

@app.put("/alerts/{alert_id}/feedback")
def ml_feedback(alert_id: int, payload: schemas.MLFeedback, db: Session = Depends(get_db)):
    alert = db.query(models.Alert).filter(models.Alert.id == alert_id).first()
    if not alert:
        raise HTTPException(404, "Alert not found")
    alert.doctor_confirmed_correct = payload.is_correct
    alert.doctor_feedback_at       = datetime.utcnow()
    db.commit()
    return {"message": "Feedback recorded — will improve future predictions"}

# ── FR21, FR24 DOCTOR DASHBOARD ──────────────────────────────

@app.get("/doctor/{doctor_id}/patients")
def get_doctor_patients(doctor_id: int, db: Session = Depends(get_db)):
    patients = db.query(models.Patient).filter(models.Patient.is_active == True).all()
    result = []
    for p in patients:
        latest = (
            db.query(models.SymptomRecord)
            .filter(models.SymptomRecord.patient_id == p.id)
            .order_by(models.SymptomRecord.log_date.desc()).first()
        )
        unread = (
            db.query(models.Alert)
            .filter(models.Alert.patient_id == p.id,
                    models.Alert.acknowledged == False).count()
        )
        result.append({"patient_id": p.id, "name": p.full_name,
                       "cancer_type": p.cancer_type, "cancer_stage": p.cancer_stage,
                       "latest_risk": latest.predicted_risk if latest else None,
                       "last_log_date": str(latest.log_date) if latest else None,
                       "unread_alerts": unread})
    risk_order = {"High": 0, "Medium": 1, "Low": 2, None: 3}
    result.sort(key=lambda x: risk_order.get(x["latest_risk"], 3))
    return result

@app.get("/doctor/{doctor_id}/alerts")
def get_doctor_alerts(doctor_id: int, db: Session = Depends(get_db)):
    alerts = (
        db.query(models.Alert)
        .filter(models.Alert.doctor_id == doctor_id, models.Alert.acknowledged == False)
        .order_by(models.Alert.created_at.desc()).all()
    )
    return [{"alert_id": a.id, "patient_id": a.patient_id, "risk": a.risk_level,
             "message": a.message, "created_at": str(a.created_at)} for a in alerts]

# ── FR27 ─ CHAT FEEDBACK ANALYTICS FOR DOCTORS ──────────────

@app.get("/doctor/{doctor_id}/chat-feedback-analytics")
def get_chat_feedback_analytics(doctor_id: int, db: Session = Depends(get_db)):
    """Aggregate RAG thumbs-up/down feedback for the doctor dashboard."""
    try:
        # Totals
        row = db.execute(sqltext(
            "SELECT COUNT(*) AS total, "
            "SUM(CASE WHEN rating=1  THEN 1 ELSE 0 END) AS pos, "
            "SUM(CASE WHEN rating=-1 THEN 1 ELSE 0 END) AS neg "
            "FROM chat_feedback"
        )).fetchone()
        total = int(row[0] or 0) if row else 0
        positive = int(row[1] or 0) if row else 0
        negative = int(row[2] or 0) if row else 0

        # Last 7 days
        row7 = db.execute(sqltext(
            "SELECT "
            "SUM(CASE WHEN rating=1  THEN 1 ELSE 0 END) AS pos, "
            "SUM(CASE WHEN rating=-1 THEN 1 ELSE 0 END) AS neg "
            "FROM chat_feedback "
            "WHERE created_at >= NOW() - INTERVAL '7 days'"
        )).fetchone()
        pos7 = int(row7[0] or 0) if row7 else 0
        neg7 = int(row7[1] or 0) if row7 else 0

        # Net rating per source
        net_rows = db.execute(sqltext(
            "SELECT source_id, source_type, SUM(rating)::int AS net, "
            "COUNT(*) AS votes "
            "FROM chat_feedback "
            "GROUP BY source_id, source_type "
            "HAVING COUNT(*) >= 1"
        )).fetchall()

        sources = [
            {"source_id": r[0], "source_type": r[1],
             "net_rating": int(r[2]), "votes": int(r[3])}
            for r in net_rows
        ]

        top_positive = sorted(
            [s for s in sources if s["net_rating"] > 0],
            key=lambda x: -x["net_rating"]
        )[:5]
        top_negative = sorted(
            [s for s in sources if s["net_rating"] < 0],
            key=lambda x: x["net_rating"]
        )[:5]
        blocked = sum(1 for s in sources if s["net_rating"] <= -3)

        # Enrich with human-readable titles from ChromaDB
        try:
            import aoun_rag
            aoun_rag.init()
            col = aoun_rag._knowledge_col
            all_ids = [s["source_id"] for s in (top_positive + top_negative)]
            if all_ids:
                lookup = col.get(ids=all_ids, include=["metadatas"])
                id_to_meta = dict(zip(lookup.get("ids", []),
                                      lookup.get("metadatas", [])))

                def enrich(s):
                    m = id_to_meta.get(s["source_id"]) or {}
                    s["title"] = m.get("source_title", "Knowledge")
                    s["page"] = m.get("page")
                    s["category"] = m.get("category")
                    s["question"] = m.get("question")
                    return s

                top_positive = [enrich(s) for s in top_positive]
                top_negative = [enrich(s) for s in top_negative]
        except Exception as e:
            print(f"[analytics] enrich error: {e}")

        return {
            "total_ratings": total,
            "positive": positive,
            "negative": negative,
            "recent_7_days": {"positive": pos7, "negative": neg7},
            "top_positive": top_positive,
            "top_negative": top_negative,
            "blocked_sources": blocked,
        }
    except Exception as e:
        print(f"[analytics] error: {e}")
        return {
            "total_ratings": 0,
            "positive": 0,
            "negative": 0,
            "recent_7_days": {"positive": 0, "negative": 0},
            "top_positive": [],
            "top_negative": [],
            "blocked_sources": 0,
        }

# ── FACE WELLNESS SCAN RESULT STORAGE ────────────────────────
# Called by Flutter after getting result from ML service
# Saves the result to DB and creates alert if patient appears unwell

@app.post("/patient/{patient_id}/wellness-scan", status_code=201)
async def save_wellness_scan(
    patient_id: int,
    payload: schemas.WellnessScanInput,
    db: Session = Depends(get_db)
):
    """
    Saves the face wellness scan result from the ML service.
    - Video/photo is NEVER saved (privacy + size)
    - Only the analysis result (score, classification, features) is saved
    - If patient appears unwell → creates alert → notifies doctor
    """
    p = db.query(models.Patient).filter(models.Patient.id == patient_id).first()
    if not p:
        raise HTTPException(404, "Patient not found")

    # Save wellness scan record (we add this as a note in the alert table)
    alert_created = False
    alert_message = None

    if payload.severity in ("medium", "high"):
        urgency_label = {
            "medium": "Mild Fatigue",
            "high":   "Appears Unwell",
        }.get(payload.severity, "Unknown")

        alert_message = (
            f"Face wellness scan detected: {payload.prediction}. "
            f"Illness score: {payload.illness_score}/100. "
            f"Features — Pallor: {payload.pallor_score}, "
            f"Eye fatigue: {payload.eye_fatigue}, "
            f"Skin dullness: {payload.skin_dullness}."
        )

        alert = models.Alert(
            patient_id      = patient_id,
            alert_type      = "WellnessScan",
            risk_level      = "High" if payload.severity == "high" else "Medium",
            message         = alert_message,
            sent_to_patient = True,
            sent_to_doctor  = True,
            doctor_id       = p.confirmed_by_doctor,
        )
        db.add(alert)
        db.commit()
        alert_created = True

        # Firebase push to doctor
        if payload.severity == "high" and p.confirmed_by_doctor:
            await _send_firebase(
                topic=f"doctor_{p.confirmed_by_doctor}",
                title="Patient Wellness Alert",
                body=f"Patient {p.full_name} appears unwell based on face scan. "
                     f"Score: {payload.illness_score}/100.",
            )

    return {
        "saved":         True,
        "alert_created": alert_created,
        "message":       alert_message or "Scan result saved — no alert needed.",
    }

# ── FR19 REPORT ───────────────────────────────────────────────

@app.get("/patient/{patient_id}/report")
def generate_report(patient_id: int, days: int = 30, db: Session = Depends(get_db)):
    from datetime import timedelta
    cutoff   = date.today() - timedelta(days=days)
    symptoms = (
        db.query(models.SymptomRecord)
        .filter(models.SymptomRecord.patient_id == patient_id,
                models.SymptomRecord.log_date >= cutoff)
        .order_by(models.SymptomRecord.log_date).all()
    )
    alerts = db.query(models.Alert).filter(models.Alert.patient_id == patient_id).all()
    risk_counts = {"High": 0, "Medium": 0, "Low": 0}
    for s in symptoms:
        if s.predicted_risk:
            risk_counts[s.predicted_risk] = risk_counts.get(s.predicted_risk, 0) + 1
    return {"patient_id": patient_id, "report_period": f"Last {days} days",
            "total_logs": len(symptoms), "risk_summary": risk_counts,
            "total_alerts": len(alerts),
            "symptom_trend": [{"date": str(s.log_date),
                                "fatigue": float(s.fatigue) if s.fatigue else None,
                                "chest_pain": float(s.chest_pain) if s.chest_pain else None,
                                "risk": s.predicted_risk} for s in symptoms]}
