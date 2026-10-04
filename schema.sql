-- Clara DB Schema
-- Turso (libSQL) compatible — no MySQL/Postgres-specific syntax

-- System prompts (soul, extractor, emotion_tracker, etc.)
CREATE TABLE IF NOT EXISTS prompts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  key TEXT NOT NULL UNIQUE,
  role TEXT NOT NULL DEFAULT 'system',
  content TEXT NOT NULL,
  updated_at TEXT DEFAULT (datetime('now'))
);

-- Conversation sessions
CREATE TABLE IF NOT EXISTS sessions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  session_id TEXT NOT NULL UNIQUE,
  started_at TEXT DEFAULT (datetime('now')),
  last_active TEXT DEFAULT (datetime('now')),
  summary TEXT,
  message_count INTEGER DEFAULT 0,
  status TEXT DEFAULT 'active'
);

-- All messages
CREATE TABLE IF NOT EXISTS messages (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  session_id TEXT NOT NULL,
  role TEXT NOT NULL CHECK(role IN ('user', 'assistant')),
  content TEXT NOT NULL,
  emotion_self TEXT,
  emotion_user TEXT,
  extracted INTEGER DEFAULT 0,
  created_at TEXT DEFAULT (datetime('now')),
  FOREIGN KEY (session_id) REFERENCES sessions(session_id)
);

-- Extracted facts about the user (memory lenses from ai-companion-memory)
-- Categories: identity, preference, commitment, relationship, emotion,
--            routine, episodic, boundary, ongoing_topic, detail
CREATE TABLE IF NOT EXISTS facts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  fact TEXT NOT NULL,
  category TEXT DEFAULT 'detail',
  source_session TEXT,
  confidence REAL DEFAULT 1.0,
  strength INTEGER DEFAULT 1,
  created_at TEXT DEFAULT (datetime('now')),
  last_referenced TEXT,
  FOREIGN KEY (source_session) REFERENCES sessions(session_id)
);

-- Mood trends over time
CREATE TABLE IF NOT EXISTS mood_log (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  session_id TEXT,
  emotion TEXT NOT NULL,
  intensity REAL DEFAULT 0.5,
  trigger_msg TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  FOREIGN KEY (session_id) REFERENCES sessions(session_id)
);

-- Indexes for fast lookups
CREATE INDEX IF NOT EXISTS idx_messages_session ON messages(session_id, created_at);
CREATE INDEX IF NOT EXISTS idx_messages_unextracted ON messages(extracted) WHERE extracted = 0;
CREATE INDEX IF NOT EXISTS idx_facts_category ON facts(category);
CREATE INDEX IF NOT EXISTS idx_facts_strength ON facts(strength DESC);
CREATE INDEX IF NOT EXISTS idx_mood_log_session ON mood_log(session_id, created_at);
CREATE INDEX IF NOT EXISTS idx_sessions_active ON sessions(status, last_active);

CREATE VIEW IF NOT EXISTS v_strong_facts AS
  SELECT fact, category, strength, confidence
  FROM facts
  WHERE confidence >= 0.7 AND strength >= 5
  ORDER BY
    CASE category
      WHEN 'identity' THEN 0
      WHEN 'boundary' THEN 1
      WHEN 'preference' THEN 2
      WHEN 'commitment' THEN 3
      WHEN 'relationship' THEN 4
      WHEN 'emotion' THEN 5
      WHEN 'routine' THEN 6
      WHEN 'ongoing_topic' THEN 7
      WHEN 'episodic' THEN 8
      WHEN 'detail' THEN 9
    END,
    strength DESC
  LIMIT 20;
