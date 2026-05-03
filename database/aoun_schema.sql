-- ── CLEAN SLATE ──────────────────────────────────────────────
DROP TABLE IF EXISTS alert          CASCADE;
DROP TABLE IF EXISTS recommendation CASCADE;
DROP TABLE IF EXISTS activity_log   CASCADE;
DROP TABLE IF EXISTS symptom_record CASCADE;
DROP TABLE IF EXISTS patient        CASCADE;
DROP TABLE IF EXISTS doctor         CASCADE;
DROP TABLE IF EXISTS admin_user     CASCADE;

-- ── ENUMS ─────────────────────────────────────────────────────
DO $$ BEGIN
    CREATE TYPE risk_level_enum   AS ENUM ('Low', 'Medium', 'High');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE cancer_stage_enum AS ENUM ('Stage I','Stage II','Stage III','Stage IV','Unknown');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE alert_type_enum   AS ENUM ('HighRisk','ThresholdExceeded','InvalidDataRepeat','Emergency');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE gender_enum AS ENUM ('Male','Female','Other');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ── ADMIN USER ────────────────────────────────────────────────
CREATE TABLE admin_user (
    id            SERIAL       PRIMARY KEY,
    full_name     VARCHAR(150) NOT NULL,
    email         VARCHAR(200) NOT NULL UNIQUE,
    password_hash VARCHAR(256) NOT NULL,
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

-- ── DOCTOR ────────────────────────────────────────────────────
CREATE TABLE doctor (
    id              SERIAL       PRIMARY KEY,
    full_name       VARCHAR(150) NOT NULL,
    email           VARCHAR(200) NOT NULL UNIQUE,
    password_hash   VARCHAR(256) NOT NULL,
    specialization  VARCHAR(150),
    is_active       BOOLEAN      NOT NULL DEFAULT FALSE,  -- activated by admin
    approved_by     INTEGER      REFERENCES admin_user(id),
    approved_at     TIMESTAMPTZ,
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

-- ── PATIENT ───────────────────────────────────────────────────
-- Central entity (from GP1 ER diagram)
CREATE TABLE patient (
    id                  SERIAL          PRIMARY KEY,
    full_name           VARCHAR(150)    NOT NULL,
    email               VARCHAR(200)    NOT NULL UNIQUE,
    password_hash       VARCHAR(256)    NOT NULL,
    date_of_birth       DATE,
    gender              gender_enum,
    -- Doctor-confirmed diagnosis fields (FR4)
    cancer_type         VARCHAR(100),
    cancer_stage        cancer_stage_enum DEFAULT 'Unknown',
    treatment_type      VARCHAR(150),
    diagnosis_confirmed BOOLEAN         NOT NULL DEFAULT FALSE,
    confirmed_by_doctor INTEGER         REFERENCES doctor(id),
    confirmed_at        TIMESTAMPTZ,
    -- Account state (FR2)
    is_active           BOOLEAN         NOT NULL DEFAULT FALSE,
    approved_by         INTEGER         REFERENCES admin_user(id),
    approved_at         TIMESTAMPTZ,
    -- Wearable (FR7)
    wearable_connected  BOOLEAN         NOT NULL DEFAULT FALSE,
    wearable_token      TEXT,
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

-- ── SYMPTOM RECORD ────────────────────────────────────────────
-- FR5 — daily symptom logging
-- Column names match the ML model's exact feature names
CREATE TABLE symptom_record (
    id                      SERIAL          PRIMARY KEY,
    patient_id              INTEGER         NOT NULL REFERENCES patient(id) ON DELETE CASCADE,
    logged_at               TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    log_date                DATE            NOT NULL DEFAULT CURRENT_DATE,
    -- Symptom fields (1–10 scale, matching ML model features)
    age                     NUMERIC(5,2),
    gender_val              NUMERIC(3,1),   -- 0=Female 1=Male (numeric for ML)
    air_pollution           NUMERIC(4,2),
    alcohol_use             NUMERIC(4,2),
    dust_allergy            NUMERIC(4,2),
    occupational_hazards    NUMERIC(4,2),
    genetic_risk            NUMERIC(4,2),
    chronic_lung_disease    NUMERIC(4,2),
    balanced_diet           NUMERIC(4,2),
    obesity                 NUMERIC(4,2),
    smoking                 NUMERIC(4,2),
    passive_smoker          NUMERIC(4,2),
    chest_pain              NUMERIC(4,2),
    coughing_of_blood       NUMERIC(4,2),
    fatigue                 NUMERIC(4,2),
    weight_loss             NUMERIC(4,2),
    shortness_of_breath     NUMERIC(4,2),
    wheezing                NUMERIC(4,2),
    swallowing_difficulty   NUMERIC(4,2),
    clubbing_of_finger_nails NUMERIC(4,2),
    frequent_cold           NUMERIC(4,2),
    dry_cough               NUMERIC(4,2),
    snoring                 NUMERIC(4,2),
    -- ML prediction result (stored after calling /predict)
    predicted_risk          risk_level_enum,
    risk_confidence         NUMERIC(5,4),   -- 0.0000–1.0000
    -- Data quality (FR8, FR9, FR10)
    is_validated            BOOLEAN         NOT NULL DEFAULT FALSE,
    invalid_attempt_count   INTEGER         NOT NULL DEFAULT 0,
    validation_notes        TEXT,
    UNIQUE (patient_id, log_date)   -- one record per patient per day
);

-- ── ACTIVITY LOG ──────────────────────────────────────────────
-- FR6 — lifestyle data (diet, exercise, sleep)
CREATE TABLE activity_log (
    id              SERIAL          PRIMARY KEY,
    patient_id      INTEGER         NOT NULL REFERENCES patient(id) ON DELETE CASCADE,
    logged_at       TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    log_date        DATE            NOT NULL DEFAULT CURRENT_DATE,
    -- Lifestyle fields
    sleep_hours     NUMERIC(4,2),           -- hours per night
    exercise_mins   INTEGER,                -- minutes of physical activity
    diet_quality    INTEGER CHECK (diet_quality BETWEEN 1 AND 10),
    water_intake_l  NUMERIC(4,2),           -- litres
    notes           TEXT,
    UNIQUE (patient_id, log_date)
);

-- ── RECOMMENDATION ────────────────────────────────────────────
-- FR17, FR18 — personalised lifestyle recommendations
CREATE TABLE recommendation (
    id              SERIAL          PRIMARY KEY,
    patient_id      INTEGER         NOT NULL REFERENCES patient(id) ON DELETE CASCADE,
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    risk_level      risk_level_enum NOT NULL,
    category        VARCHAR(50)     NOT NULL, -- 'diet' | 'exercise' | 'sleep' | 'general'
    title           VARCHAR(200)    NOT NULL,
    body            TEXT            NOT NULL,
    is_read         BOOLEAN         NOT NULL DEFAULT FALSE
);

-- ── ALERT ─────────────────────────────────────────────────────
-- FR16, FR23, FR25 — risk alerts and emergency guidance
CREATE TABLE alert (
    id              SERIAL          PRIMARY KEY,
    patient_id      INTEGER         NOT NULL REFERENCES patient(id) ON DELETE CASCADE,
    symptom_id      INTEGER         REFERENCES symptom_record(id),
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    alert_type      alert_type_enum NOT NULL,
    risk_level      risk_level_enum NOT NULL,
    message         TEXT            NOT NULL,
    -- Delivery tracking
    sent_to_patient BOOLEAN         NOT NULL DEFAULT FALSE,
    sent_to_doctor  BOOLEAN         NOT NULL DEFAULT FALSE,
    doctor_id       INTEGER         REFERENCES doctor(id),
    -- Acknowledgement
    acknowledged    BOOLEAN         NOT NULL DEFAULT FALSE,
    acknowledged_at TIMESTAMPTZ,
    -- ML feedback (FR26)
    doctor_confirmed_correct  BOOLEAN,      -- doctor says prediction was right/wrong
    doctor_feedback_at        TIMESTAMPTZ
);

-- ── INDEXES ───────────────────────────────────────────────────
-- Speed up the most common queries

-- Patient lookups
CREATE INDEX idx_patient_email    ON patient(email);
CREATE INDEX idx_patient_doctor   ON patient(confirmed_by_doctor);
CREATE INDEX idx_patient_active   ON patient(is_active);

-- Symptom history (FR11 — view by day/week/month)
CREATE INDEX idx_symptom_patient_date ON symptom_record(patient_id, log_date DESC);
CREATE INDEX idx_symptom_risk         ON symptom_record(predicted_risk);

-- Activity history (FR12)
CREATE INDEX idx_activity_patient_date ON activity_log(patient_id, log_date DESC);

-- Alerts — doctor dashboard (FR21, FR24 — triage by risk)
CREATE INDEX idx_alert_patient    ON alert(patient_id, created_at DESC);
CREATE INDEX idx_alert_doctor     ON alert(doctor_id, acknowledged);
CREATE INDEX idx_alert_risk       ON alert(risk_level, acknowledged);

-- Recommendations history (FR18)
CREATE INDEX idx_rec_patient ON recommendation(patient_id, created_at DESC);

-- ── SAMPLE SEED DATA (for testing) ────────────────────────────
INSERT INTO admin_user (full_name, email, password_hash)
VALUES ('System Admin', 'admin@aoun.health', 'hashed_password_here');

INSERT INTO doctor (full_name, email, password_hash, specialization, is_active, approved_by, approved_at)
VALUES ('Dr. Hassan Altarawneh', 'hassan@aoun.health', 'hashed_password_here',
        'Oncology', TRUE, 1, NOW());

INSERT INTO patient (full_name, email, password_hash, gender, cancer_type, cancer_stage,
                     treatment_type, diagnosis_confirmed, confirmed_by_doctor,
                     confirmed_at, is_active, approved_by, approved_at)
VALUES ('Test Patient', 'patient@aoun.health', 'hashed_password_here',
        'Male', 'Lung Cancer', 'Stage II',
        'Chemotherapy', TRUE, 1, NOW(), TRUE, 1, NOW());

-- ── VERIFY ────────────────────────────────────────────────────
SELECT
    table_name,
    (SELECT COUNT(*) FROM information_schema.columns c
     WHERE c.table_name = t.table_name
       AND c.table_schema = 'public') AS column_count
FROM information_schema.tables t
WHERE table_schema = 'public'
  AND table_type = 'BASE TABLE'
ORDER BY table_name;
