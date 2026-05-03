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
| 🧠 **ML Risk Prediction** | Random Forest trained on 743,728 patient records. 23 features. 92% accuracy. Classifies risk as High / Medium / Low. |
| 💬 **RAG Medical Chatbot** | Mistral-7B via Ollama + ChromaDB vector store with 254 indexed entries from NCI and ACS clinical PDFs. Feedback-weighted retrieval that improves with use. |
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
| Knowledge Base | pypdf · NCI / ACS clinical PDFs · 254 indexed entries |
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
- **Dataset:** 743,728 cancer patient records
- **Features:** 23 — Age, Gender, 21 symptom indicators (0–10 scale)
- **Pipeline:** SimpleImputer → StandardScaler → RandomForestClassifier
- **Accuracy:** 92.0% · Recall: 92.0%
- **Output:** Risk level (High / Medium / Low) + confidence + top contributing features
- **Top feature:** Coughing of Blood (12.8% importance)

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

Grounded in: *Forte et al. (2021). Deep Learning for Identification of Acute Illness and Facial Cues of Illness. Frontiers in Medicine, 8, 661309.*

---

## RAG Chatbot Knowledge Base

| Source | Type | Entries |
|---|---|---|
| NCI Chemotherapy and You | Real PDF | ~80 chunks |
| NCI Understanding Chemotherapy | Real PDF | ~30 chunks |
| CancerCare Chemo Side Effects | Real PDF | ~100 chunks |
| ACS Help for Patients | Real PDF | 7 chunks |
| Synthetic clinical guides | PDF | 29 chunks |
| Hardcoded FAQ | Structured | 20 entries |
| **Total** | | **254 entries** |

**Retrieval:** Over-fetch 3× → re-rank by feedback weights → inject into Mistral-7B prompt alongside live patient data from PostgreSQL.

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
git clone https://github.com/eepycloud/aoun.git
cd aoun/backend
python -m venv venv
venv\Scripts\activate        # Windows
pip install -r requirements.txt
```

### 2. Set up database

```bash
psql -U postgres -c "CREATE DATABASE aoun_db;"
psql -U postgres -d aoun_db -f database/aoun_schema.sql
psql -U postgres -d aoun_db -f database/chat_feedback_migration.sql
```

### 3. Pull the LLM

```bash
ollama pull mistral:7b-instruct
```

### 4. Ingest knowledge base PDFs

```bash
python ingest_pdfs.py
```

### 5. Start all services

```bash
# Terminal 1 — ML service
cd ml_service && python ml_main.py

# Terminal 2 — Backend
cd backend && uvicorn main:app --port 8002 --reload

# Terminal 3 — Flutter
cd aoun_app && flutter run
```

---

## Project Structure

```
aoun/
├── backend/
│   ├── main.py                  # FastAPI entry point
│   ├── models.py                # SQLAlchemy ORM models
│   ├── schemas.py               # Pydantic request/response schemas
│   ├── database.py              # DB connection and session
│   ├── chatbot_routes.py        # Chatbot endpoints
│   ├── aoun_rag.py              # 5-layer RAG pipeline
│   ├── knowledge_base.py        # Hardcoded FAQ entries
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

## Known Limitations

- Passwords currently stored as plaintext — bcrypt migration planned
- No JWT authentication — session-based only
- Voice input works on Chrome/Edge only (Web Speech API)
- Chatbot feedback quality improvement requires scale (hundreds of ratings)
- Facial wellness analyzer is a proof-of-concept — not clinically validated

---

## Status

🚧 In Progress — Expected June 2026

---

## Disclaimer

Aoun is an academic research project. It is designed to support clinical decision-making and does **not** replace medical diagnosis, clinical judgment, or professional oncology care. All risk predictions and wellness assessments are advisory only.

---

## License

This project is licensed under the MIT License — see [LICENSE](LICENSE) for details.

---

## Dataset

The ML model was trained on a curated dataset of **743,728 cancer patient records** compiled from multiple publicly available sources and merged into a single unified dataset.

| Property | Value |
|---|---|
| Total records | 743,728 patients |
| Features | 23 (Age, Gender, 21 symptom indicators on 0–10 scale) |
| Target variable | Risk level — High / Medium / Low |
| Train / Test split | 80% / 20% (594,982 train · 148,746 test) |
| Class distribution | High: ~268K · Medium: ~247K · Low: ~228K |

The dataset was collected, cleaned, and consolidated by the project team from multiple cancer patient data sources. It is not directly available for redistribution. To request access or understand the data pipeline, open an issue in this repository.

