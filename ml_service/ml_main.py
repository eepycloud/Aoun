from fastapi import FastAPI, HTTPException, UploadFile, File
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
import joblib
import numpy as np
import pandas as pd
import tempfile
import os

# Import our wellness analyzer (same folder)
from wellness_analyzer import analyze_face_wellness, analyze_video_wellness

BASE = os.path.dirname(os.path.abspath(__file__))

# ── LOAD MODEL 1: Random Forest ───────────────────────────────
model   = joblib.load(os.path.join(BASE, "aoun_model.pkl"))
scaler  = joblib.load(os.path.join(BASE, "aoun_scaler.pkl"))
imputer = joblib.load(os.path.join(BASE, "aoun_imputer.pkl"))
le      = joblib.load(os.path.join(BASE, "aoun_label_encoder.pkl"))

if hasattr(model, "feature_names_in_"):
    FEATURES = list(model.feature_names_in_)
else:
    # Fallback: read the CSV but strip any header junk
    _raw = pd.read_csv(os.path.join(BASE, "aoun_features.csv"),
                       header=None)[0].tolist()
    FEATURES = [str(f).strip() for f in _raw
                if str(f).strip() and str(f).strip() != "0"]

# Sanity check on startup — crashes loudly if something is still wrong
assert len(FEATURES) == model.n_features_in_, (
    f"FEATURES has {len(FEATURES)} items but model expects "
    f"{model.n_features_in_}. Check aoun_features.csv."
)
print(f"✅ Features loaded: {len(FEATURES)} → {FEATURES[:3]}...{FEATURES[-2:]}")

print(f"✅ Model 1 loaded — Random Forest ({model.n_estimators} trees, "
      f"{model.n_features_in_} features, 92% accuracy)")
print(f"✅ Model 2 loaded — OpenCV Facial Wellness Analyzer")

# ── APP ───────────────────────────────────────────────────────
app = FastAPI(
    title       = "Aoun ML Service",
    description = (
        "**Multi-Model System**\n\n"
        "**Model 1 — Symptom Risk Predictor:**\n"
        "Random Forest · 743,728 patients · 92% accuracy\n\n"
        "**Model 2 — Facial Wellness Analyzer (Computer Vision):**\n"
        "OpenCV image processing · Detects visible illness signs from face photos/video\n"
        "Features: skin pallor · eye droopiness · skin uniformity · brightness\n"
        "Method: LAB color space analysis + Haar cascade detection\n"
        "Reference: Floris et al. 2021, Frontiers in Medicine"
    ),
    version = "2.0.0",
)
app.add_middleware(CORSMiddleware, allow_origins=["*"],
                   allow_methods=["*"], allow_headers=["*"])

# ── SCHEMAS ───────────────────────────────────────────────────
INPUT_TO_FEATURE = {
    "age":"Age","gender":"Gender","air_pollution":"Air Pollution",
    "alcohol_use":"Alcohol use","dust_allergy":"Dust Allergy",
    "occupational_hazards":"OccuPational Hazards","genetic_risk":"Genetic Risk",
    "chronic_lung_disease":"chronic Lung Disease","balanced_diet":"Balanced Diet",
    "obesity":"Obesity","smoking":"Smoking","passive_smoker":"Passive Smoker",
    "chest_pain":"Chest Pain","coughing_of_blood":"Coughing of Blood",
    "fatigue":"Fatigue","weight_loss":"Weight Loss",
    "shortness_of_breath":"Shortness of Breath","wheezing":"Wheezing",
    "swallowing_difficulty":"Swallowing Difficulty",
    "clubbing_of_finger_nails":"Clubbing of Finger Nails",
    "frequent_cold":"Frequent Cold","dry_cough":"Dry Cough","snoring":"Snoring",
}
IMPORTANCES = {
    "Coughing of Blood":0.1281,"Passive Smoker":0.1042,
    "Obesity":0.0953,"Wheezing":0.0771,"Fatigue":0.0648,
}

class PatientInput(BaseModel):
    age:float=Field(...,ge=1,le=120);gender:float=Field(...,ge=0,le=1)
    air_pollution:float=Field(...,ge=0,le=10);alcohol_use:float=Field(...,ge=0,le=10)
    dust_allergy:float=Field(...,ge=0,le=10);occupational_hazards:float=Field(...,ge=0,le=10)
    genetic_risk:float=Field(...,ge=0,le=10);chronic_lung_disease:float=Field(...,ge=0,le=10)
    balanced_diet:float=Field(...,ge=0,le=10);obesity:float=Field(...,ge=0,le=10)
    smoking:float=Field(...,ge=0,le=10);passive_smoker:float=Field(...,ge=0,le=10)
    chest_pain:float=Field(...,ge=0,le=10);coughing_of_blood:float=Field(...,ge=0,le=10)
    fatigue:float=Field(...,ge=0,le=10);weight_loss:float=Field(...,ge=0,le=10)
    shortness_of_breath:float=Field(...,ge=0,le=10);wheezing:float=Field(...,ge=0,le=10)
    swallowing_difficulty:float=Field(...,ge=0,le=10)
    clubbing_of_finger_nails:float=Field(...,ge=0,le=10)
    frequent_cold:float=Field(...,ge=0,le=10);dry_cough:float=Field(...,ge=0,le=10)
    snoring:float=Field(...,ge=0,le=10)

# ── ENDPOINTS ─────────────────────────────────────────────────

@app.get("/")
def root():
    return {
        "service": "Aoun ML Service v2.0",
        "model_1": "Random Forest — symptom risk",
        "model_2": "OpenCV — facial wellness analyzer",
        "docs":    "/docs",
    }

@app.get("/health")
def health():
    return {
        "status":          "ok",
        "tabular_model":   True,
        "vision_model":    True,
        "opencv_version":  __import__('cv2').__version__,
    }

# ── IMAGE VALIDATION ─────────────────────────────────────
def _is_image_upload(upload) -> bool:
    """Accept an upload as an image if EITHER the content-type looks
    image-ish OR the filename has a common image extension.
    Final validation happens when OpenCV tries to decode the bytes."""
    ct = (upload.content_type or "").lower()
    if ct.startswith("image/"):
        return True
    # Flutter's MultipartFile.fromPath sends octet-stream by default
    if ct in ("application/octet-stream", "binary/octet-stream", ""):
        return True
    fname = (upload.filename or "").lower()
    if any(fname.endswith(ext) for ext in
           (".jpg", ".jpeg", ".png", ".webp", ".bmp", ".heic")):
        return True
    return False

#──── Video Validation ───────────────────────────────────
def _is_video_upload(upload) -> bool:
    ct = (upload.content_type or "").lower()
    if ct.startswith("video/"):
        return True
    if ct in ("application/octet-stream", "binary/octet-stream", ""):
        return True
    fname = (upload.filename or "").lower()
    if any(fname.endswith(ext) for ext in
           (".mp4", ".mov", ".webm", ".avi", ".mkv", ".3gp")):
        return True
    return False

# ── MODEL 1: SYMPTOM RISK ─────────────────────────────────────
@app.post("/predict")
def predict(p: PatientInput):
    """
    Model 1 — Symptom-based risk prediction.
    Pipeline: SimpleImputer → StandardScaler → RandomForest
    Input: 23 symptom/lifestyle features (scale 0–10)
    Output: High / Medium / Low risk + confidence
    """
    row = {INPUT_TO_FEATURE[k]: v for k, v in p.dict().items()}
    df  = pd.DataFrame([row])[FEATURES]
    scl = scaler.transform(imputer.transform(df))
    code= int(model.predict(scl)[0])
    prob= model.predict_proba(scl)[0]
    lbl = str(le.inverse_transform([code])[0])
    return {
        "risk_level":       lbl,
        "confidence":       round(float(prob[code]), 4),
        "probabilities":    {str(le.inverse_transform([i])[0]): round(float(v), 4)
                             for i, v in enumerate(prob)},
        "alert_required":   lbl == "High",
        "top_risk_factors": sorted(IMPORTANCES, key=IMPORTANCES.get,
                                   reverse=True)[:3],
    }

# ── MODEL 2: FACIAL WELLNESS — PHOTO ──────────────────────────
@app.post("/analyze/face")
async def analyze_face(file: UploadFile = File(...)):
    """
    Model 2 — Facial wellness detection from a photo.
    Accepts JPEG, PNG, WEBP, BMP. Relies on OpenCV's imdecode to
    validate the actual bytes rather than trusting the HTTP
    content-type (Flutter often sends application/octet-stream).
    """
    if not _is_image_upload(file):
        raise HTTPException(
            status_code=400,
            detail=(
                "Unsupported file. Please upload a JPG, PNG, or WEBP image. "
                f"(Received content-type: {file.content_type}, "
                f"filename: {file.filename})"
            ),
        )

    try:
        contents = await file.read()
        if not contents or len(contents) < 100:
            raise HTTPException(400, "Empty or corrupted image file.")

        result = analyze_face_wellness(contents)

        if not result.get("success"):
            # No face detected, unreadable image, etc. — friendly 422
            raise HTTPException(
                status_code=422,
                detail=result.get("error", "Analysis failed"),
            )

        return result

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(500, f"Face analysis error: {e}")
    
# ── MODEL 2: FACIAL WELLNESS — VIDEO ──────────────────────────

@app.post("/analyze/video")
async def analyze_video(file: UploadFile = File(...)):
    if not _is_video_upload(file):
        raise HTTPException(400, "Please upload a JPG/MP4/MOV video.")

    try:
        contents = await file.read()
        if not contents or len(contents) < 1000:
            raise HTTPException(400, "Empty or corrupted video file.")

        # Save to temp then run the analyzer (analyze_video_wellness
        # expects a path in the existing code)
        with tempfile.NamedTemporaryFile(
                delete=False, suffix=".mp4") as tmp:
            tmp.write(contents)
            tmp_path = tmp.name

        try:
            result = analyze_video_wellness(tmp_path)
        finally:
            try:
                os.remove(tmp_path)
            except OSError:
                pass

        if not result.get("success"):
            raise HTTPException(422, result.get("error",
                                                "Video analysis failed"))
        return result

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(500, f"Video analysis error: {e}")

# ── MODEL INFO ────────────────────────────────────────────────
@app.get("/model/info")
def model_info():
    return {
        "model_1_tabular": {
            "algorithm":   "Random Forest Classifier",
            "n_trees":     100,
            "features":    23,
            "classes":     list(le.classes_),
            "accuracy":    "92.0%",
            "recall":      "92.0%",
            "trained_on":  "743,728 cancer patients",
            "pipeline":    "SimpleImputer(median) → StandardScaler → RandomForest",
            "pkl_files":   ["aoun_model.pkl", "aoun_scaler.pkl",
                            "aoun_imputer.pkl", "aoun_label_encoder.pkl"],
        },
        "model_2_vision": {
            "algorithm":   "OpenCV Image Processing",
            "type":        "Rule-based computer vision (no separate training needed)",
            "technique":   "LAB color space analysis + Haar cascade detection",
            "features": [
                "Pallor score (LAB A-channel — skin redness/pinkness)",
                "Eye fatigue score (Haar eye cascade — lid droopiness)",
                "Skin uniformity (LAB L-channel std deviation)",
                "Skin brightness/dullness (LAB L-channel mean)",
            ],
            "output":      "Appears Well / Mild Fatigue / Appears Unwell",
            "reference":   "Floris et al. 2021, Frontiers in Medicine",
            "endpoint":    "/analyze/face (photo) or /analyze/video (video)",
            "no_training": "Uses OpenCV built-in classifiers — no dataset download needed",
        },
    }

@app.get("/features")
def list_features():
    return {"features": FEATURES, "count": len(FEATURES)}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8001, reload=True)
