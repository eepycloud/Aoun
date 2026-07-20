"""
knowledge_base.py — Curated cancer-care knowledge for Aoun

Hand-written patient-education entries covering the most common
questions cancer patients ask their care team. Each entry has:
  - id:        unique key
  - category:  broad topic (fatigue, nutrition, mood, etc.)
  - question:  a representative patient phrasing (used for search)
  - answer:    2-4 sentence evidence-informed response

Content is adapted from public patient-education sources
(American Cancer Society, Macmillan, Cancer Research UK).
NOT medical advice — always defer to the oncology team.
"""

KNOWLEDGE_ENTRIES = [
    # -- FATIGUE ------------------------------------------------------
    {
        "id": "kb_001",
        "category": "fatigue",
        "question": "Why am I so tired during cancer treatment?",
        "answer": (
            "Cancer-related fatigue is the most common side effect of treatment "
            "and is usually not relieved by sleep alone. It is caused by the "
            "cancer itself, chemotherapy, radiation, anemia, poor nutrition, "
            "stress, and disrupted sleep. Pace yourself with short rest periods, "
            "prioritize meaningful activities, and tell your oncology team if "
            "fatigue is severe — it can often be improved."
        ),
    },
    {
        "id": "kb_002",
        "category": "fatigue",
        "question": "How can I manage my energy during chemotherapy?",
        "answer": (
            "Use the 4 Ps: Plan, Prioritize, Pace, and Position. Plan the day "
            "around times you feel strongest (often mornings). Prioritize 1-2 "
            "important tasks. Pace with short 15-20 minute rests between "
            "activities. Position yourself to conserve energy (sit instead of "
            "stand). Light walking 10-20 minutes daily is proven to reduce "
            "fatigue over time."
        ),
    },
    # -- NUTRITION ----------------------------------------------------
    {
        "id": "kb_003",
        "category": "nutrition",
        "question": "What should I eat during cancer treatment?",
        "answer": (
            "Aim for protein at every meal (eggs, fish, lentils, yogurt, lean "
            "meat) to preserve muscle during treatment. Include colorful fruits "
            "and cooked vegetables, whole grains, and healthy fats. Eat small, "
            "frequent meals (5-6 per day) if your appetite is poor. Avoid raw "
            "fish, unpasteurized dairy, and buffet food if your immunity is low."
        ),
    },
    {
        "id": "kb_004",
        "category": "nutrition",
        "question": "I have no appetite — how do I eat enough?",
        "answer": (
            "Try small, calorie-dense snacks every 2-3 hours instead of large "
            "meals: nut butter on toast, cheese, avocado, smoothies with protein "
            "powder. Cold bland foods like yogurt and smoothies are often easier "
            "than hot or spicy foods. Drink liquids between meals, not with "
            "them, to leave room for food. Ask your oncology team for a "
            "dietitian referral."
        ),
    },
    {
        "id": "kb_005",
        "category": "nutrition",
        "question": "How do I deal with nausea from chemo?",
        "answer": (
            "Eat bland, dry foods like crackers or toast before treatment and "
            "first thing in the morning. Ginger (tea, chews, or real ginger ale) "
            "helps many patients. Avoid strong food smells — cold food smells "
            "less. Take anti-nausea medications proactively as prescribed, not "
            "after nausea starts. If you cannot keep fluids down for 24 hours, "
            "call your oncology team."
        ),
    },
    # -- HYDRATION ----------------------------------------------------
    {
        "id": "kb_006",
        "category": "hydration",
        "question": "How much water should I drink during treatment?",
        "answer": (
            "Aim for 2-3 liters of fluid daily during active treatment unless "
            "your doctor has restricted fluids (for example, heart or kidney "
            "conditions). Water, broth, diluted juice, and herbal tea all count. "
            "Good hydration helps your kidneys clear chemotherapy drugs and "
            "reduces fatigue. A practical trick: keep a 1-liter bottle visible "
            "and refill it twice a day."
        ),
    },
    # -- SLEEP --------------------------------------------------------
    {
        "id": "kb_007",
        "category": "sleep",
        "question": "I can't sleep during treatment. What helps?",
        "answer": (
            "Keep a consistent bedtime and wake time, even on weekends. Avoid "
            "screens for 60 minutes before bed. Keep the bedroom cool, dark, "
            "and quiet. Limit caffeine after noon and alcohol entirely. If you "
            "nap, keep it under 30 minutes and before 3 PM. Persistent insomnia "
            "for more than 2 weeks should be discussed with your medical team — "
            "it is treatable."
        ),
    },
    {
        "id": "kb_008",
        "category": "sleep",
        "question": "Is it okay to nap a lot during treatment?",
        "answer": (
            "Short naps (20-30 minutes) can genuinely help restore energy. "
            "Longer naps, especially late in the afternoon, tend to disrupt "
            "night sleep and worsen the fatigue cycle. If you are sleeping 4+ "
            "hours during the day, your sleep is fragmented — tell your team, "
            "because this can be improved with adjustments to sleep hygiene or "
            "sometimes medication."
        ),
    },
    # -- EXERCISE -----------------------------------------------------
    {
        "id": "kb_009",
        "category": "exercise",
        "question": "Should I exercise during cancer treatment?",
        "answer": (
            "Yes. Evidence is very strong that moderate exercise during "
            "treatment reduces fatigue, improves mood, preserves muscle, and "
            "may improve outcomes. Target 150 minutes of moderate activity per "
            "week — walking is ideal. Start small: 10 minutes twice a day is a "
            "fine beginning. Avoid exercise on days with fever, very low blood "
            "counts, or severe fatigue. Always clear a new routine with your "
            "doctor."
        ),
    },
    {
        "id": "kb_010",
        "category": "exercise",
        "question": "I'm too tired to exercise. Does light activity still help?",
        "answer": (
            "Yes, and this is one of the most counterintuitive but best-proven "
            "facts in cancer care. Even 5-10 minutes of slow walking on a "
            "'bad' day can reduce fatigue more than rest does. The goal is "
            "movement, not intensity. Chair exercises, stretching, and gentle "
            "yoga all count. On your worst days, a short walk to the mailbox "
            "is a win."
        ),
    },
    # -- MOOD / MENTAL HEALTH -----------------------------------------
    {
        "id": "kb_011",
        "category": "mood",
        "question": "It's normal to feel depressed during cancer treatment?",
        "answer": (
            "Feeling sad, scared, anxious, or angry during cancer treatment is "
            "extremely common — around 1 in 4 patients experience clinical "
            "depression. It does not mean you are weak or failing. Talk to "
            "your oncology team: they can refer you to psycho-oncology "
            "counseling, peer support groups, or prescribe help if needed. "
            "Addressing mental health improves treatment outcomes and quality "
            "of life."
        ),
    },
    {
        "id": "kb_012",
        "category": "mood",
        "question": "How do I cope with the anxiety between scans?",
        "answer": (
            "Scanxiety is a real and widely-shared experience. Techniques that "
            "help: scheduling the scan and result appointment close together "
            "to shorten waiting, grounding exercises (5-4-3-2-1 senses), daily "
            "10-minute walks, limiting online symptom-checking, and talking "
            "with others who have been through it. Peer support groups "
            "(in-person or online) are especially powerful for scan anxiety."
        ),
    },
    # -- TREATMENT / SIDE EFFECTS -------------------------------------
    {
        "id": "kb_013",
        "category": "treatment",
        "question": "What side effects should I report immediately?",
        "answer": (
            "Call your oncology team the same day for: fever over 38 C (100.4 F), "
            "shaking chills, unusual bleeding or bruising, severe pain, "
            "vomiting that prevents you keeping fluids down for 24 hours, a "
            "new rash, or a new cough with shortness of breath. Go to the ER "
            "for: severe chest pain, inability to breathe, loss of "
            "consciousness, or coughing up blood."
        ),
    },
    {
        "id": "kb_014",
        "category": "treatment",
        "question": "How long do chemotherapy side effects last?",
        "answer": (
            "It varies by drug and by person. Acute side effects like nausea "
            "and fatigue usually peak 2-5 days after an infusion and improve "
            "by the next cycle. Hair typically starts regrowing 1-3 months "
            "after the last session. Some effects like neuropathy (numbness) "
            "or fatigue can persist for months. Long-term survivorship clinics "
            "can help with effects that linger."
        ),
    },
    {
        "id": "kb_015",
        "category": "treatment",
        "question": "Why is my immune system low during treatment?",
        "answer": (
            "Chemotherapy attacks fast-dividing cells, which includes bone "
            "marrow cells that make white blood cells (your infection fighters). "
            "Your white count typically drops 7-14 days after an infusion and "
            "recovers by the next cycle. During this 'nadir' period, avoid "
            "crowded places, sick people, raw foods, and wash hands often. A "
            "fever over 38 C is a medical emergency during this window."
        ),
    },
    # -- LIFESTYLE / PRACTICAL ----------------------------------------
    {
        "id": "kb_016",
        "category": "lifestyle",
        "question": "Can I drink alcohol during cancer treatment?",
        "answer": (
            "Generally no. Alcohol can interact with many chemotherapy drugs, "
            "worsen nausea, irritate the mouth and stomach, interfere with "
            "sleep, and stress the liver which is already metabolizing "
            "treatment. If you have questions about a specific drink on a "
            "specific day, ask your oncologist — do not guess."
        ),
    },
    {
        "id": "kb_017",
        "category": "lifestyle",
        "question": "Is it safe to be around children or pets during treatment?",
        "answer": (
            "Generally yes, but with sensible precautions. Avoid close contact "
            "with anyone who has a cold, flu, or infection, especially during "
            "the low-immunity window after infusions. Wash hands before "
            "handling pet food, and avoid cleaning litter boxes or bird cages "
            "yourself. Pregnant people should not clean up animal waste. Normal "
            "play and cuddling with healthy pets is fine and good for your mood."
        ),
    },
    # -- EMOTIONAL / SUPPORT ------------------------------------------
    {
        "id": "kb_018",
        "category": "support",
        "question": "How do I tell family and friends about my diagnosis?",
        "answer": (
            "There is no single right way. Many patients prefer telling one or "
            "two close people first and asking them to share with the wider "
            "circle. Be honest about what help you want (rides, meals, "
            "childcare) and what you don't (unsolicited advice, sympathy "
            "visits). Social workers at your treatment center can help with "
            "wording and family meetings if needed."
        ),
    },
    {
        "id": "kb_019",
        "category": "support",
        "question": "What are the benefits of joining a cancer support group?",
        "answer": (
            "Support groups reduce isolation, provide practical tips from "
            "people who have been through the same treatment, and improve "
            "emotional resilience. Research shows participation is linked to "
            "better quality of life and sometimes better survival. Options "
            "include in-person hospital groups, cancer-specific organizations, "
            "and online communities. Try 2-3 before deciding — each group has "
            "its own dynamic."
        ),
    },
    # -- MONITORING / APP USE -----------------------------------------
    {
        "id": "kb_020",
        "category": "app",
        "question": "Why should I log my symptoms daily in the app?",
        "answer": (
            "Daily logging creates a trend line your doctor can see, catches "
            "drift early (for example, fatigue creeping up over a week), and "
            "gives the risk-prediction model more data to work with. Studies "
            "show patients who track symptoms electronically during cancer "
            "treatment have fewer emergency visits and better outcomes. 60 "
            "seconds a day is enough."
        ),
    },
]


def get_all_entries():
    """Return the full list of knowledge entries."""
    return KNOWLEDGE_ENTRIES


def get_entry_text(entry: dict) -> str:
    """Format a single entry as a searchable/retrievable text block."""
    return (f"[{entry['category'].upper()}] "
            f"Q: {entry['question']}\n"
            f"A: {entry['answer']}")
