-- Migration: add chat_feedback table for RAG feedback loop (Phase 4)
--
-- Records patient thumbs-up/down ratings on bot responses and links
-- them to the specific source chunks that grounded each reply.
-- Used to adjust retrieval ranking over time.

CREATE TABLE IF NOT EXISTS chat_feedback (
    id          SERIAL PRIMARY KEY,
    patient_id  INTEGER NOT NULL REFERENCES patient(id),
    message_id  VARCHAR(64) NOT NULL,       -- uuid of the bot reply
    source_id   VARCHAR(200) NOT NULL,      -- ChromaDB document id used
    source_type VARCHAR(20) NOT NULL,       -- 'faq', 'pdf', 'conversation'
    rating      SMALLINT NOT NULL CHECK (rating IN (-1, 1)),
    created_at  TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Indexes for the hot query path: "get feedback stats for source X"
CREATE INDEX IF NOT EXISTS ix_chat_feedback_source  ON chat_feedback(source_id);
CREATE INDEX IF NOT EXISTS ix_chat_feedback_patient ON chat_feedback(patient_id);
CREATE INDEX IF NOT EXISTS ix_chat_feedback_msg     ON chat_feedback(message_id);

-- Confirm
SELECT 'chat_feedback table ready' AS status;
