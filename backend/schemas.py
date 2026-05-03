from pydantic import BaseModel, Field
from typing import Optional
from datetime import date

class RegisterRequest(BaseModel):
    full_name:       str
    email:           str
    password:        str
    gender:          Optional[str] = None
    date_of_birth:   Optional[date] = None
    cancer_type:     Optional[str]  = None
    cancer_stage:    Optional[str]  = None
    treatment_start: Optional[date] = None

class LoginRequest(BaseModel):
    email:    str
    password: str

class ProfileUpdate(BaseModel):
    cancer_type:     Optional[str] = None
    cancer_stage:    Optional[str] = None
    treatment_type:  Optional[str] = None
    treatment_start: Optional[date] = None

class DiagnosisConfirm(BaseModel):
    doctor_id:     int
    cancer_type:   str
    cancer_stage:  str
    treatment_type:str

class SymptomInput(BaseModel):
    log_date:                Optional[date] = None
    age:                     float = Field(..., ge=0,  le=120)
    gender_val:              float = Field(..., ge=0,  le=1)
    air_pollution:           float = Field(..., ge=0,  le=10)
    alcohol_use:             float = Field(..., ge=0,  le=10)
    dust_allergy:            float = Field(..., ge=0,  le=10)
    occupational_hazards:    float = Field(..., ge=0,  le=10)
    genetic_risk:            float = Field(..., ge=0,  le=10)
    chronic_lung_disease:    float = Field(..., ge=0,  le=10)
    balanced_diet:           float = Field(..., ge=0,  le=10)
    obesity:                 float = Field(..., ge=0,  le=10)
    smoking:                 float = Field(..., ge=0,  le=10)
    passive_smoker:          float = Field(..., ge=0,  le=10)
    chest_pain:              float = Field(..., ge=0,  le=10)
    coughing_of_blood:       float = Field(..., ge=0,  le=10)
    fatigue:                 float = Field(..., ge=0,  le=10)
    weight_loss:             float = Field(..., ge=0,  le=10)
    shortness_of_breath:     float = Field(..., ge=0,  le=10)
    wheezing:                float = Field(..., ge=0,  le=10)
    swallowing_difficulty:   float = Field(..., ge=0,  le=10)
    clubbing_of_finger_nails:float = Field(..., ge=0,  le=10)
    frequent_cold:           float = Field(..., ge=0,  le=10)
    dry_cough:               float = Field(..., ge=0,  le=10)
    snoring:                 float = Field(..., ge=0,  le=10)

    class Config:
        json_schema_extra = {"example": {
            "age": 45, "gender_val": 1, "air_pollution": 4, "alcohol_use": 3,
            "dust_allergy": 5, "occupational_hazards": 3, "genetic_risk": 6,
            "chronic_lung_disease": 2, "balanced_diet": 5, "obesity": 4,
            "smoking": 7, "passive_smoker": 2, "chest_pain": 6,
            "coughing_of_blood": 7, "fatigue": 7, "weight_loss": 5,
            "shortness_of_breath": 6, "wheezing": 3, "swallowing_difficulty": 2,
            "clubbing_of_finger_nails": 3, "frequent_cold": 4,
            "dry_cough": 5, "snoring": 2
        }}

class LifestyleInput(BaseModel):
    log_date:      Optional[date]  = None
    sleep_hours:   Optional[float] = Field(None, ge=0, le=24)
    exercise_mins: Optional[int]   = Field(None, ge=0, le=600)
    diet_quality:  Optional[int]   = Field(None, ge=0, le=10)
    water_intake_l:Optional[float] = Field(None, ge=0, le=20)
    notes:         Optional[str]   = None

class MLFeedback(BaseModel):
    is_correct: bool

class WellnessScanInput(BaseModel):
    prediction:    str            # "Appears Well" / "Mild Fatigue Detected" / "Appears Unwell"
    illness_score: float          # 0-100
    severity:      str            # "low" / "medium" / "high"
    pallor_score:  Optional[float] = None
    eye_fatigue:   Optional[float] = None
    skin_dullness: Optional[float] = None
    scan_type:     str = "photo"  # "photo" or "video"
