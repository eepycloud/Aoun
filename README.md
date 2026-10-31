# Aoun (عون) — Cancer Patient Monitoring Prototype

An academic graduation project combining a Flutter app, FastAPI/PostgreSQL backend, Random Forest classifier, a Mistral-7B RAG chatbot, and experimental OpenCV image analysis.

The project demonstrates how these components can be connected in a patient-monitoring workflow. It is not clinically validated and should not be used to make medical decisions.

## What is implemented

| Component | Implementation and scope |
| --- | --- |
| Mobile app | Flutter screens for patient, doctor, and admin workflows |
| Backend | FastAPI endpoints and PostgreSQL storage for profiles, symptoms, and alerts |
| ML service | Random Forest predicts the dataset's High / Medium / Low labels from 23 symptom and risk-factor features |
| Chatbot | Mistral-7B through Ollama, with ChromaDB retrieval over curated FAQ content and medical PDFs |
| Feedback | Source weighting changes based on feedback; improvement in answer quality has not been established by a controlled evaluation |
| Facial analysis | Experimental OpenCV image cues such as color statistics and eye geometry; these are not validated measures of illness |
| Push notifications | Optional Firebase integration in the code; end-to-end delivery remains unverified |

## Architecture and local operation

```text
Flutter app
    | HTTP requests
    v
FastAPI backend :8002 ---- PostgreSQL
    |                 |
    |                 +-- RAG retrieval / ChromaDB / local Ollama
    +-- ML and image-analysis service :8001
    +-- Optional Firebase cloud push integration
```

The backend, database, model, and Ollama services can be hosted locally. The app communicates with a backend; inference is not described as running entirely on the phone. Firebase push delivery is a cloud dependency when enabled. Patient information is exchanged with the configured backend, so the project does not claim that all information stays on the device.

## Model experiment and evidence limits

The committed [training notebook](main.ipynb) reads an external file named `cancer_patient_data.csv`. Its saved output reports a 743,728-row input and a 148,746-row test portion. The notebook uses a stratified 80/20 split, fits the median imputer and scaler on the training portion, and compares Random Forest, XGBoost, and logistic regression.

| Metric | Random Forest result recorded in the notebook |
| --- | --- |
| Accuracy | 0.9201 |
| Macro precision | 0.9201 |
| Macro recall | 0.9195 |
| Macro F1 | 0.9198 |

The Random Forest configuration is 100 estimators, maximum depth 15, and random seed 42. These are historical notebook results, not a newly reproduced benchmark or evidence of clinical performance.

Earlier project notes identified a 1,000-record public Kaggle source and described synthetic expansion with SMOTE. The expansion step and the input CSV are not included in the public notebook. Therefore:

- The 743,728 rows must not be represented as 743,728 independently observed patients.
- The published notebook does not establish that synthetic expansion occurred only after the train/test split, or that the test rows are independent of the expansion process.
- The source dataset's clinical provenance is not verified here. These labels are not validated outcomes for monitoring patients during cancer treatment.
- Reproducing the original source, documenting expansion, splitting original observations before augmentation, and evaluating on an untouched test set are required before claiming a reliable generalization result.

The recorded score is retained for transparency. Current portfolio descriptions focus on the implemented system rather than an inflated patient count.

## RAG and image analysis

The chatbot retrieves FAQ and PDF passages with `all-MiniLM-L6-v2` embeddings and ChromaDB, then supplies context to `mistral:7b-instruct` through Ollama. The repository documents an initial knowledge base of 254 entries; this is a project snapshot, not a fixed guarantee for a fresh installation. Sources include curated FAQ material and NCI/CancerCare PDFs. Patient context and conversation memory are also used by the backend.

Feedback adjusts retrieval weights. This is a reweighting mechanism, not proof that clinical correctness or response quality improves over time.

The OpenCV module computes heuristic image cues. Face detection or successful orientation handling does not establish diagnostic accuracy. No clinical validation of the resulting wellness score is claimed.

## Setup

This repository preserves an academic prototype. The model artifacts, original experiment CSV, database credentials, and medical PDF files are not supplied as a complete reproducible bundle. A fresh clone needs configuration before the full app can run.

### 1. Dependencies

Use Python 3.11+, Flutter, PostgreSQL, and Ollama. From the repository root:

```bash
git clone https://github.com/eepycloud/Aoun.git
cd Aoun
python -m venv .venv
```

Activate the environment with `.venv\Scripts\activate` on Windows, or `source .venv/bin/activate` on macOS/Linux, then install the service dependencies:

```bash
python -m pip install -r backend/requirements.txt
```

The training notebook additionally imports XGBoost, Matplotlib, and seaborn. It was written for Google Colab and mounts Google Drive; change those cells and the CSV path for another environment. Dependency versions are not pinned, so the original experiment environment is not fully reproduced by these instructions.

### 2. Configure PostgreSQL

Create a database and apply both SQL files with your PostgreSQL user:

```bash
createdb -U postgres aoun_db
psql -U postgres -d aoun_db -f database/aoun_schema.sql
psql -U postgres -d aoun_db -f database/chat_feedback_migration.sql
```

Create a local `backend/.env` with your connection settings, for example:

```dotenv
DATABASE_URL=postgresql://postgres:YOUR_LOCAL_PASSWORD@localhost:5432/aoun_db
ML_SERVICE_URL=http://localhost:8001
```

Do not commit your password. The fallback connection in `backend/database.py` uses port 8000, so set `DATABASE_URL` explicitly for your actual database port.

### 3. Prepare the model artifacts

Open [main.ipynb](main.ipynb), configure its input CSV, and run it only with data whose provenance you understand. Running it with a different source does not reproduce the saved 92% result. For a defensible new evaluation, split original observations before any augmentation and reserve the test set.

Copy the generated files into `ml_service/`:

```text
aoun_model.pkl
aoun_scaler.pkl
aoun_imputer.pkl
aoun_label_encoder.pkl
aoun_features.csv
```

These files must come from the same training run. The ML service loads model artifacts at startup and cannot start without them. Never load pickle/joblib files from an untrusted source.

### 4. Prepare Ollama and retrieval

Start Ollama and fetch the model in another terminal:

```bash
ollama serve
ollama pull mistral:7b-instruct
```

Place the PDFs you are authorized to use in `backend/knowledge_pdfs/`, then ingest them:

```bash
cd backend
python ingest_pdfs.py
```

Model and embedding downloads require an initial internet connection. The locally hosted services can then use those downloaded assets.

### 5. Start the services

In separate terminals with the virtual environment activated:

```bash
# From ml_service/
python -m uvicorn ml_main:app --port 8001

# From backend/
python -m uvicorn backend_main:app --port 8002

# From aoun_app/
flutter pub get
flutter run
```

Configure the API address in `aoun_app/lib/api_service.dart` for your emulator or device. A physical phone's localhost is not the backend computer. Bind the backend to an appropriate LAN interface only for a trusted development network.

Leave Firebase disabled for local development. The backend skips push calls when no `FIREBASE_SERVER_KEY` is configured. The current push code is an unverified integration and should be reviewed before enabling it; no working production push delivery is claimed.

## Repository layout

```text
main.ipynb                         Recorded ML experiment
backend/
  backend_main.py                  FastAPI backend
  database.py                      Database connection
  aoun_rag.py                      Retrieval and source weighting
  chatbot_routes.py                Chatbot API and Ollama calls
  ingest_pdfs.py                    PDF ingestion
  requirements.txt                 Shared backend / ML dependencies
ml_service/
  ml_main.py                       Model and image-analysis API
  wellness_analyzer.py             Experimental OpenCV analysis
aoun_app/                          Flutter application
database/
  aoun_schema.sql                  Database schema
  chat_feedback_migration.sql       Feedback schema migration
```

## Validation and remaining work

Earlier project notes recorded 19 of 20 manual black-box checks passing, with Firebase push delivery deferred. This is a historical manual-test summary, not a current automated test run. Wearable integration was also deferred.

Further work includes reproducible data preparation and model evaluation, clinical validation, authentication and authorization review, dependency pinning, and end-to-end notification tests. The application is an academic prototype, not a production medical service.

## License and data

The original project documentation states MIT licensing for the code, but this repository does not include a standalone license file. Dataset and PDF rights remain with their respective sources. The experiment CSV and real-world patient EHR data are not distributed as part of this repository.
