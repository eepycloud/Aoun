# Aoun (عون) — Intelligent Cancer Patient Monitoring System

> AI-powered platform for continuous cancer patient monitoring, risk stratification, and intelligent medical assistance — fully local, no cloud dependency.

[![Python](https://img.shields.io/badge/Python-3.11-blue?style=flat-square&logo=python)](https://python.org)
[![Flutter](https://img.shields.io/badge/Flutter-3.41-blue?style=flat-square&logo=flutter)](https://flutter.dev)
[![FastAPI](https://img.shields.io/badge/FastAPI-0.110-green?style=flat-square&logo=fastapi)](https://fastapi.tiangolo.com)
[![License](https://img.shields.io/badge/License-MIT-green?style=flat-square)](LICENSE)

---

## What is Aoun?

Cancer patients spend most of their time between clinic visits with no intelligent monitoring. Aoun closes that gap.

It is a mobile health platform that lets patients log daily symptoms, get AI-generated risk assessments, perform facial wellness checks, and consult an intelligent health chatbot — while their oncologist receives real-time alerts and monitors risk trends from a dedicated dashboard.

Everything runs locally. No cloud. No API keys. Patient data never leaves the device.

---

## Features

| Feature | Description |
|---|---|
| 🧠 **ML Risk Prediction** | Random Forest evaluating 23 clinical features. 92% accuracy on a held-out test set of 148,746 records. Classifies risk as High / Medium / Low. |
| 💬 **RAG Medical Chatbot** | Mistral-7B via Ollama + ChromaDB vector store with 254 indexed entries from a curated FAQ and NCI/CancerCare clinical PDFs. Feedback-weighted retrieval that improves with use. |
| 📷 **Facial Wellness Analyzer** | OpenCV pipeline extracting pallor, eye fatigue, skin uniformity, and skin dullness from selfie photos to detect physical illness signs. No training data needed. |
| 🔔 **Real-time Doctor Alerts** | Firebase Cloud Messaging pushes High-risk patient updates to the doctor's device instantly. |
| 📊 **Doctor Triage Dashboard** | Patients sorted by ML risk level. Full symptom history. ML feedback buttons (correct / incorrect) for model improvement loop. |
| 🚨 **Emergency Screen** | Symptom-specific guidance cards with one-tap emergency calling. Works offline. |
| 🔁 **Learning Loop** | Doctor and patient feedback updates RAG source weights. Poorly rated sources are penalized or blocked. |

---

## Tech Stack

| Layer | Technologies |
|---|---|
| Mobile | Flutter 3.41 · Dart · fl_chart · Firebase Messaging |
| Backend | FastAPI · Python 3.11 · PostgreSQL · SQLAlchemy · Uvicorn |
| ML Model | scikit-learn · Random Forest · pandas · NumPy |
| Computer Vision | OpenCV · Haar Cascade · LAB color space |
| RAG Chatbot | Ollama Mistral-7B · ChromaDB · all-MiniLM-L6-v2 (384-dim) |
| Knowledge Base | pypdf · NCI / CancerCare clinical PDFs · 254 indexed entries |
| Notifications | Firebase Cloud Messaging (FCM) |

---

## System Architecture

```
┌─────────────────────────────────────────────────┐
│                  Flutter App                    │
│  Patient · Doctor · Admin — 13 screens          │
└───────────────────┬─────────────────────────────┘
                    │ HTTP REST
┌───────────────────▼─────────────────────────────┐
│              FastAPI Backend  :8002              │
│                                                 │
│  ┌─────────────┐  ┌──────────────────────────┐  │
│  │ ML Service  │  │     RAG Chatbot           │  │
│  │ :8001       │  │  Mistral-7B + ChromaDB    │  │
│  │ Random      │  │  254 medical entries      │  │
│  │ Forest 92%  │  │  Feedback-weighted        │  │
│  └─────────────┘  └──────────────────────────┘  │
│                                                 │
│  ┌─────────────┐  ┌──────────────────────────┐  │
│  │   OpenCV    │  │      PostgreSQL           │  │
│  │   Facial    │  │      Database             │  │
│  │   Wellness  │  │      Port 5432            │  │
│  └─────────────┘  └──────────────────────────┘  │
└───────────────────┬─────────────────────────────┘
                    │
         ┌──────────▼──────────┐
         │   Firebase FCM      │
         │   Doctor Alerts     │
         └─────────────────────┘
```

---

## ML Model Details

- **Algorithm:** Random Forest Classifier (100 estimators)
- **Pipeline:** SimpleImputer (median) → StandardScaler → RandomForestClassifier
- **Features:** 23 — Age, Gender, 21 symptom / risk-factor indicators
- **Training data:** 1,000 real Kaggle oncology records, class-balanced with SMOTE on the training split only → 594,982 train / 148,746 test (80/20 stratified). The test set is excluded from SMOTE.
- **Accuracy:** 92.0% (0.9201) · Precision: 0.9200 · Recall (macro): 0.9195 · F1: 0.9197
- **Output:** Risk level (High / Medium / Low) + confidence + top contributing features
- **Top feature:** Coughing of Blood
- **Inference:** <200 ms · Serialized to `aoun_model.pkl`

> **Note on scale:** the source symptoms are scored 1–8. The patient-facing app sliders use a 0–10 scale for usability; a value of 0 is mapped to 1 at inference to stay within the model's valid input range.

### Confusion Matrix (148,746 test patients)

|  | Predicted High | Predicted Medium | Predicted Low |
|---|---|---|---|
| **Actual High** | **49,929** | 1,815 | 2,004 |
| **Actual Medium** | 2,223 | **41,371** | 1,966 |
| **Actual Low** | 2,094 | 1,782 | **45,562** |

---

## Facial Wellness Analyzer

Four clinical features extracted from a selfie photo using OpenCV:

| Feature | Method | Weight |
|---|---|---|
| Pallor Score | LAB color space A-channel mean | 40% |
| Eye Fatigue | Haar cascade height/width ratio | 35% |
| Skin Uniformity | LAB L-channel standard deviation | 15% |
| Skin Dullness | LAB L-channel mean | 10% |

**Output:** Illness score 0–100 → `Appears Well` / `Mild Fatigue` / `Appears Unwell`

**Evaluation:** 88% face-detection success (44/50 test photos) · 100% EXIF orientation correction (12/12). The `_fix_rotation()` routine uses the Haar cascade as a rotation oracle, so no EXIF parsing library is required.

Grounded in: *Forte et al. (2021). Deep Learning for Identification of Acute Illness and Facial Cues of Illness. Frontiers in Medicine, 8, 661309.*

> Proof-of-concept only — not clinically validated. Formal validation with oncology patients requires medical ethics board approval and is documented as future work.

---

## RAG Chatbot Knowledge Base

Three source types are combined at query time and stored in a ChromaDB vector store (all-MiniLM-L6-v2, 384-dim). Every response carries citation chips tracing the answer back to its source.

| Source | Type | Notes |
|---|---|---|
| Curated FAQ (`knowledge_base.py`) | Structured | 20 evidence-based Q&A entries across 7 categories, adapted from ACS / Macmillan / Cancer Research UK |
| NCI *Chemotherapy and You* | Real PDF | Ingested page-by-page (~900-char chunks, 150-char overlap) |
| CancerCare *Chemo Side Effects* | Real PDF | Neutropenia monitoring, treatment-specific symptoms |
| Live patient context | PostgreSQL | Built per-message from 5 tables (profile, latest symptoms, 7-day trends, lifestyle averages, unread alerts) |
| Conversation memory | ChromaDB | Past turns retrieved semantically for multi-turn coherence |
| **Total indexed entries** | | **254** |

**Retrieval:** Over-fetch 3× → re-rank by feedback weights → inject into the Mistral-7B prompt alongside live patient data from PostgreSQL. Thumbs-up: +5% boost per vote; thumbs-down: −10% penalty per vote; net rating ≤ −3 permanently blocks a source.

---

## Getting Started

### Prerequisites

```
Python 3.11+
Flutter 3.41+
PostgreSQL 18
Ollama (https://ollama.com)
```

### 1. Clone and set up backend

```bash
git clone https://github.com/<your-org>/aoun.git
cd aoun/backend
python -m venv venv
venv\Scripts\activate        # Windows
pip install -r requirements.txt
```

### 2. Train the ML model

The trained model files are not included in the repo. Generate them from the notebook:

```
1. Download the "Cancer Patient Data Sets" CSV from Kaggle (see Dataset section).
2. Open gp2.ipynb (Google Colab or Jupyter) and point the read_csv path at your CSV.
3. Run all cells. This produces:
     aoun_model.pkl, aoun_scaler.pkl, aoun_imputer.pkl,
     aoun_label_encoder.pkl, aoun_features.csv
4. Copy those 5 files into the ml_service/ folder.
```

The ML service loads these on startup, so it will not run until they are present.

### 3. Set up database

```bash
psql -U postgres -c "CREATE DATABASE aoun_db;"
psql -U postgres -d aoun_db -f database/aoun_schema.sql
psql -U postgres -d aoun_db -f database/chat_feedback_migration.sql
```

### 4. Pull the LLM

```bash
ollama serve
ollama pull mistral:7b-instruct
```

### 5. Ingest knowledge base PDFs

```bash
python ingest_pdfs.py
```

### 6. Start all services

```bash
# Terminal 1 — ML service (port 8001)
cd ml_service && python -m uvicorn ml_main:app --reload --port 8001 --host 0.0.0.0

# Terminal 2 — Backend (port 8002)
cd backend && python -m uvicorn backend_main:app --reload --port 8002 --host 0.0.0.0

# Terminal 3 — Flutter
cd aoun_app && flutter run
```

---

## Project Structure

```
aoun/
├── backend/
│   ├── backend_main.py          # FastAPI entry point
│   ├── models.py                # SQLAlchemy ORM models
│   ├── schemas.py               # Pydantic request/response schemas
│   ├── database.py              # DB connection and session
│   ├── chatbot_routes.py        # Chatbot endpoints + safety guardrails
│   ├── aoun_rag.py              # Feedback-weighted RAG pipeline
│   ├── knowledge_base.py        # Curated FAQ entries
│   ├── ingest_pdfs.py           # PDF ingestion into ChromaDB
│   ├── smart_recommendations.py # Lifestyle recommendation engine
│   └── wellness_analyzer.py     # OpenCV facial analysis
├── ml_service/
│   └── ml_main.py               # Random Forest inference API
├── aoun_app/                    # Flutter app (13 screens)
├── database/
│   ├── aoun_schema.sql
│   └── chat_feedback_migration.sql
└── requirements.txt
```

---

## Functional Requirements

27 of 28 functional requirements implemented.

| Status | Count | Notes |
|---|---|---|
| ✅ Implemented | 27 | All core features |
| ❌ Deferred | 1 | FR7: Wearable integration (hardware dependency) |

GP2 additions: Emergency screen · Facial wellness · RAG chatbot · ML feedback loop

---

## Testing

19 of 20 black-box test cases passed. TC19 (Firebase push alert) is deferred — it requires a live production Firebase key and is not testable locally.

---

## Known Limitations

- Authentication uses standard password hashing — salted Argon2/bcrypt and JWT migration planned
- Session-based auth only — JWT access tokens planned
- Voice input works on Chrome/Edge only (Web Speech API)
- Chatbot feedback quality improvement requires scale (hundreds of ratings)
- Facial wellness analyzer is a proof-of-concept — not clinically validated
- Firebase push notifications require a production server key not bundled with the repo

---

## Status

Completed ✅

---

## Disclaimer

Aoun is an independent academic research project. It is designed to support clinical decision-making and does **not** replace medical diagnosis, clinical judgment, or professional oncology care. All risk predictions and wellness assessments are advisory only.

---

## License

This project is licensed under the MIT License — see [LICENSE](LICENSE) for details.

---

## Dataset

The ML model was trained on the publicly available **Cancer Patient Data Sets** (`cancer_patient_data_sets.csv`) from Kaggle with SMOTE applied to make it more authentic.

| Property | Value |
|---|---|
| Raw records | 1,000 patients (real) |
| Columns | 26 — patient ID, age (14–73), gender, 21 symptom/risk-factor features, target `Level` |
| Raw class split | High 36.5% · Medium 33.2% · Low 30.3% |
| Balancing | SMOTE applied to the training split only |
| After SMOTE | 743,728 records — 594,982 train / 148,746 test (80/20 stratified) |
| Target variable | Risk level — High / Medium / Low |

Real-world EHR data was not used due to patient-privacy law, IRB approval timelines, and the sensitivity of oncology records. The Kaggle dataset provides a scientifically structured training environment grounded in real clinical symptom patterns. The raw CSV is subject to Kaggle's terms and is not redistributed here — see the source on Kaggle to obtain it.
