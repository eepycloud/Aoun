from sqlalchemy import Column, Integer, String, Boolean, Date, DateTime, Numeric, Text, ForeignKey
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func
from database import Base

class Patient(Base):
    __tablename__ = "patient"
    id                  = Column(Integer, primary_key=True, index=True)
    full_name           = Column(String(150), nullable=False)
    email               = Column(String(200), unique=True, nullable=False)
    password_hash       = Column(String(256), nullable=False)
    gender              = Column(String(10))
    date_of_birth       = Column(Date, nullable=True)
    cancer_type         = Column(String(100))
    cancer_stage        = Column(String(20), default="Unknown")
    treatment_type      = Column(String(150))
    treatment_start     = Column(Date, nullable=True)          # NEW — treatment start date
    diagnosis_confirmed = Column(Boolean, default=False)
    confirmed_by_doctor = Column(Integer, ForeignKey("doctor.id"), nullable=True)
    confirmed_at        = Column(DateTime(timezone=True))
    is_active           = Column(Boolean, default=False)
    approved_by         = Column(Integer, nullable=True)
    approved_at         = Column(DateTime(timezone=True))
    created_at          = Column(DateTime(timezone=True), server_default=func.now())
    updated_at          = Column(DateTime(timezone=True), server_default=func.now())

    symptoms        = relationship("SymptomRecord",  back_populates="patient")
    activity_logs   = relationship("ActivityLog",    back_populates="patient")
    recommendations = relationship("Recommendation", back_populates="patient")
    alerts          = relationship("Alert",          back_populates="patient")

class Doctor(Base):
    __tablename__ = "doctor"
    id             = Column(Integer, primary_key=True, index=True)
    full_name      = Column(String(150), nullable=False)
    email          = Column(String(200), unique=True, nullable=False)
    password_hash  = Column(String(256), nullable=False)
    specialization = Column(String(150))
    is_active      = Column(Boolean, default=False)
    created_at     = Column(DateTime(timezone=True), server_default=func.now())

class SymptomRecord(Base):
    __tablename__ = "symptom_record"
    id                       = Column(Integer, primary_key=True, index=True)
    patient_id               = Column(Integer, ForeignKey("patient.id"), nullable=False)
    logged_at                = Column(DateTime(timezone=True), server_default=func.now())
    log_date                 = Column(Date, nullable=False)
    age                      = Column(Numeric(5, 2))
    gender_val               = Column(Numeric(3, 1))
    air_pollution            = Column(Numeric(4, 2))
    alcohol_use              = Column(Numeric(4, 2))
    dust_allergy             = Column(Numeric(4, 2))
    occupational_hazards     = Column(Numeric(4, 2))
    genetic_risk             = Column(Numeric(4, 2))
    chronic_lung_disease     = Column(Numeric(4, 2))
    balanced_diet            = Column(Numeric(4, 2))
    obesity                  = Column(Numeric(4, 2))
    smoking                  = Column(Numeric(4, 2))
    passive_smoker           = Column(Numeric(4, 2))
    chest_pain               = Column(Numeric(4, 2))
    coughing_of_blood        = Column(Numeric(4, 2))
    fatigue                  = Column(Numeric(4, 2))
    weight_loss              = Column(Numeric(4, 2))
    shortness_of_breath      = Column(Numeric(4, 2))
    wheezing                 = Column(Numeric(4, 2))
    swallowing_difficulty    = Column(Numeric(4, 2))
    clubbing_of_finger_nails = Column(Numeric(4, 2))
    frequent_cold            = Column(Numeric(4, 2))
    dry_cough                = Column(Numeric(4, 2))
    snoring                  = Column(Numeric(4, 2))
    predicted_risk           = Column(String(10))
    risk_confidence          = Column(Numeric(5, 4))
    is_validated             = Column(Boolean, default=False)
    invalid_attempt_count    = Column(Integer, default=0)
    validation_notes         = Column(Text)

    patient = relationship("Patient", back_populates="symptoms")
    alerts  = relationship("Alert",   back_populates="symptom")

class ActivityLog(Base):
    __tablename__ = "activity_log"
    id             = Column(Integer, primary_key=True, index=True)
    patient_id     = Column(Integer, ForeignKey("patient.id"), nullable=False)
    logged_at      = Column(DateTime(timezone=True), server_default=func.now())
    log_date       = Column(Date, nullable=False)
    sleep_hours    = Column(Numeric(4, 2))
    exercise_mins  = Column(Integer)
    diet_quality   = Column(Integer)
    water_intake_l = Column(Numeric(4, 2))
    notes          = Column(Text)

    patient = relationship("Patient", back_populates="activity_logs")

class Recommendation(Base):
    __tablename__ = "recommendation"
    id         = Column(Integer, primary_key=True, index=True)
    patient_id = Column(Integer, ForeignKey("patient.id"), nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    risk_level = Column(String(10), nullable=False)
    category   = Column(String(50), nullable=False)
    title      = Column(String(200), nullable=False)
    body       = Column(Text, nullable=False)
    is_read    = Column(Boolean, default=False)

    patient = relationship("Patient", back_populates="recommendations")

class Alert(Base):
    __tablename__ = "alert"
    id                       = Column(Integer, primary_key=True, index=True)
    patient_id               = Column(Integer, ForeignKey("patient.id"), nullable=False)
    symptom_id               = Column(Integer, ForeignKey("symptom_record.id"), nullable=True)
    created_at               = Column(DateTime(timezone=True), server_default=func.now())
    alert_type               = Column(String(30), nullable=False)
    risk_level               = Column(String(10), nullable=False)
    message                  = Column(Text, nullable=False)
    sent_to_patient          = Column(Boolean, default=False)
    sent_to_doctor           = Column(Boolean, default=False)
    doctor_id                = Column(Integer, ForeignKey("doctor.id"), nullable=True)
    acknowledged             = Column(Boolean, default=False)
    acknowledged_at          = Column(DateTime(timezone=True))
    doctor_confirmed_correct = Column(Boolean, nullable=True)
    doctor_feedback_at       = Column(DateTime(timezone=True))

    patient = relationship("Patient",       back_populates="alerts")
    symptom = relationship("SymptomRecord", back_populates="alerts")
