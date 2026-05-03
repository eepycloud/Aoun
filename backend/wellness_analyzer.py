import cv2
import numpy as np
import json


def _fix_rotation(img: np.ndarray) -> np.ndarray:
    """
    Phone cameras save JPEGs with EXIF rotation tags.
    OpenCV ignores EXIF → image appears sideways/upside-down.
    This function tries all 4 rotations and picks the one
    where the face detector finds a face.
    """
    face_cascade = cv2.CascadeClassifier(
        cv2.data.haarcascades + 'haarcascade_frontalface_default.xml')

    rotations = [
        img,
        cv2.rotate(img, cv2.ROTATE_90_CLOCKWISE),
        cv2.rotate(img, cv2.ROTATE_180),
        cv2.rotate(img, cv2.ROTATE_90_COUNTERCLOCKWISE),
    ]
    for rotated in rotations:
        gray = cv2.cvtColor(rotated, cv2.COLOR_BGR2GRAY)
        faces = face_cascade.detectMultiScale(
            gray, scaleFactor=1.1, minNeighbors=3, minSize=(60, 60))
        if len(faces) > 0:
            return rotated
    # If no rotation works return original — caller handles no-face case
    return img


def load_face_detector():
    face_cascade = cv2.CascadeClassifier(
        cv2.data.haarcascades + 'haarcascade_frontalface_default.xml')
    eye_cascade = cv2.CascadeClassifier(
        cv2.data.haarcascades + 'haarcascade_eye.xml')
    return face_cascade, eye_cascade


def analyze_face_wellness(image_bytes: bytes) -> dict:
    """
    Full facial wellness analysis pipeline.
    Handles EXIF rotation, variable lighting, and real phone photos.
    """
    # ── STEP 1: Decode ───────────────────────────────────────
    nparr = np.frombuffer(image_bytes, np.uint8)
    img   = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
    if img is None:
        return {"success": False, "error": "Could not decode image. Please try again."}

    # ── STEP 2: Fix EXIF rotation (critical for phone selfies) ─
    img = _fix_rotation(img)

    # ── STEP 3: Resize to standard size ─────────────────────
    # Keep aspect ratio — don't force 640x480 which distorts
    h, w = img.shape[:2]
    scale = 640 / max(h, w)
    img   = cv2.resize(img, (int(w * scale), int(h * scale)))

    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)

    # ── STEP 4: Detect face ──────────────────────────────────
    face_cascade, eye_cascade = load_face_detector()

    # Try with generous parameters first (works for most photos)
    faces = face_cascade.detectMultiScale(
        gray, scaleFactor=1.05, minNeighbors=3, minSize=(60, 60))

    # If that fails, equalize histogram (fixes dark/overexposed photos)
    if len(faces) == 0:
        gray_eq = cv2.equalizeHist(gray)
        faces   = face_cascade.detectMultiScale(
            gray_eq, scaleFactor=1.05, minNeighbors=2, minSize=(50, 50))

    # If still nothing, try even more lenient
    if len(faces) == 0:
        faces = face_cascade.detectMultiScale(
            gray, scaleFactor=1.1, minNeighbors=1, minSize=(40, 40))

    if len(faces) == 0:
        return {
            "success":    False,
            "prediction": "Unable to assess",
            "error": (
                "No face detected. Tips: ensure good lighting, "
                "face the camera directly, avoid shadows, "
                "hold phone at arm's length."
            ),
        }

    # Use largest face
    x, y, w, h = sorted(faces, key=lambda f: f[2] * f[3], reverse=True)[0]
    face_roi  = img[y:y+h, x:x+w]
    face_gray = gray[y:y+h, x:x+w]

    # ── STEP 5: LAB color space analysis ─────────────────────
    face_lab = cv2.cvtColor(face_roi, cv2.COLOR_BGR2LAB)
    L, A, B  = cv2.split(face_lab)

    mean_L = float(np.mean(L))
    mean_A = float(np.mean(A))

    # Pallor: lower A = less red/pink = more pale
    # Range ~120-160 for faces. Shift baseline to 130 (more universal)
    pallor_score = max(0.0, min(100.0, (130 - mean_A) * 5))

    # ── STEP 6: Eye openness (Haar cascade on upper half) ────
    upper_h = max(1, h // 2)
    upper_face = face_gray[0:upper_h, :]
    eyes = eye_cascade.detectMultiScale(
        upper_face, scaleFactor=1.1, minNeighbors=2, minSize=(15, 15))

    eye_openness_score = 0.0
    if len(eyes) >= 2:
        eyes_sorted = sorted(eyes, key=lambda e: e[2]*e[3], reverse=True)[:2]
        ratios      = [(e[3] / e[2]) if e[2] > 0 else 0 for e in eyes_sorted]
        avg_ratio   = float(np.mean(ratios))
        eye_openness_score = min(100.0, avg_ratio * 250)
    elif len(eyes) == 1:
        eye_openness_score = 40.0
    else:
        # Eyes not detected — don't penalize heavily (lighting issue)
        eye_openness_score = 55.0

    eye_fatigue_score = 100.0 - eye_openness_score

    # ── STEP 7: Skin uniformity ──────────────────────────────
    std_L = float(np.std(L))
    uniformity_score = max(0.0, min(100.0, (std_L - 15) * 4))

    # ── STEP 8: Skin dullness ────────────────────────────────
    brightness_score = max(0.0, min(100.0, (120 - mean_L) * 2))

    # ── STEP 9: Weighted illness score ───────────────────────
    illness_score = (
        pallor_score      * 0.40 +
        eye_fatigue_score * 0.35 +
        uniformity_score  * 0.15 +
        brightness_score  * 0.10
    )
    illness_score = round(float(illness_score), 2)

    # ── STEP 10: Classify ────────────────────────────────────
    if illness_score < 30:
        classification = "Appears Well"
        severity       = "low"
        color_code     = "green"
        message        = "Facial appearance looks normal. Keep up your daily monitoring."
    elif illness_score < 55:
        classification = "Mild Fatigue Detected"
        severity       = "medium"
        color_code     = "orange"
        message        = "Some signs of fatigue visible. Rest and stay hydrated."
    else:
        classification = "Appears Unwell"
        severity       = "high"
        color_code     = "red"
        message        = "Multiple illness signs detected. Please contact your care team."

    return {
        "success":       True,
        "prediction":    classification,
        "illness_score": illness_score,
        "severity":      severity,
        "color_code":    color_code,
        "message":       message,
        "features": {
            "pallor_score":    round(pallor_score, 2),
            "eye_fatigue":     round(eye_fatigue_score, 2),
            "skin_uniformity": round(uniformity_score, 2),
            "skin_dullness":   round(brightness_score, 2),
        },
        "face_detected": True,
        "num_faces":     len(faces),
        "eyes_detected": len(eyes),
        "method":        "OpenCV LAB color space + Haar cascade",
        "reference":     "Floris et al. 2021, Frontiers in Medicine",
    }


def analyze_video_wellness(video_path: str, sample_frames: int = 10) -> dict:
    """Analyze wellness from a short video by sampling frames."""
    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        return {"success": False, "error": "Could not open video"}

    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    step         = max(1, total_frames // sample_frames)

    scores       = []
    pallors      = []
    eye_fatigues = []

    for i in range(0, total_frames, step):
        cap.set(cv2.CAP_PROP_POS_FRAMES, i)
        ret, frame = cap.read()
        if not ret:
            break
        _, encoded = cv2.imencode('.jpg', frame, [cv2.IMWRITE_JPEG_QUALITY, 90])
        result = analyze_face_wellness(encoded.tobytes())
        if result.get('success'):
            scores.append(result['illness_score'])
            pallors.append(result['features']['pallor_score'])
            eye_fatigues.append(result['features']['eye_fatigue'])

    cap.release()

    if not scores:
        return {"success": False, "error": "No valid frames with face detected"}

    avg_score = float(np.mean(scores))
    if avg_score < 30:
        classification = "Appears Well"
        severity       = "low"
        color_code     = "green"
        message        = "Patient appears well across video frames."
    elif avg_score < 55:
        classification = "Mild Fatigue Detected"
        severity       = "medium"
        color_code     = "orange"
        message        = "Some fatigue signs visible. Rest recommended."
    else:
        classification = "Appears Unwell"
        severity       = "high"
        color_code     = "red"
        message        = "Patient appears unwell. Please contact your care team."

    return {
        "success":         True,
        "prediction":      classification,
        "illness_score":   round(avg_score, 2),
        "severity":        severity,
        "color_code":      color_code,
        "message":         message,
        "frames_analyzed": len(scores),
        "avg_pallor":      round(float(np.mean(pallors)), 2),
        "avg_eye_fatigue": round(float(np.mean(eye_fatigues)), 2),
        "features": {
            "pallor_score":    round(float(np.mean(pallors)), 2),
            "eye_fatigue":     round(float(np.mean(eye_fatigues)), 2),
            "skin_uniformity": 0,
            "skin_dullness":   0,
        },
        "method": "OpenCV multi-frame video analysis",
    }


if __name__ == "__main__":
    import sys
    if len(sys.argv) > 1:
        with open(sys.argv[1], 'rb') as f:
            result = analyze_face_wellness(f.read())
        print(json.dumps(result, indent=2))
