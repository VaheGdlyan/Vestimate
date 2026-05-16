-- =============================================
-- VESTIMATE Database Migration: Phase 2
-- Tables: outfits, recommendation_cache, feedback_events, 
--         prompt_versions, manual_review_queue, event_log
-- Run this AFTER 001_database_migration.sql
-- =============================================

-- Outfits table (stores assembled outfit records)
CREATE TABLE IF NOT EXISTS outfits (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  top_id          UUID REFERENCES wardrobe_items(id),
  bottom_id       UUID REFERENCES wardrobe_items(id),
  shoe_id         UUID REFERENCES wardrobe_items(id),
  stylist_note    TEXT,
  source          TEXT NOT NULL CHECK (source IN ('llm', 'fallback', 'user_created')),
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

-- Recommendation cache (durable record of recommendations for analytics)
CREATE TABLE IF NOT EXISTS recommendation_cache (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id           UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  outfit_id         UUID REFERENCES outfits(id),
  cache_key         TEXT NOT NULL,
  weather_snapshot  JSONB,
  schedule_snapshot JSONB,
  was_cache_hit     BOOLEAN,
  fallback_used     BOOLEAN DEFAULT false,
  generated_at      TIMESTAMPTZ DEFAULT NOW(),
  
  UNIQUE(user_id, cache_key)
);

-- Feedback events (user interactions with recommendations)
CREATE TABLE IF NOT EXISTS feedback_events (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id               UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  recommendation_id     UUID REFERENCES recommendation_cache(id),
  action                TEXT NOT NULL CHECK (action IN ('worn', 'skipped', 'saved')),
  item_ids              UUID[],
  created_at            TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_feedback_user ON feedback_events(user_id, created_at DESC);

-- Prompt versions (versioned LLM prompt templates for A/B testing)
CREATE TABLE IF NOT EXISTS prompt_versions (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  version         TEXT NOT NULL UNIQUE,
  system_prompt   TEXT NOT NULL,
  user_prompt_template TEXT NOT NULL,
  is_active       BOOLEAN DEFAULT false,
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  notes           TEXT
);

-- Only one row may have is_active = true
CREATE UNIQUE INDEX IF NOT EXISTS idx_prompt_active ON prompt_versions(is_active) WHERE is_active = true;

-- Manual review queue (items with low ML confidence)
CREATE TABLE IF NOT EXISTS manual_review_queue (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  item_id         UUID NOT NULL REFERENCES wardrobe_items(id) ON DELETE CASCADE,
  user_id         UUID NOT NULL REFERENCES users(id),
  tags_raw        JSONB,
  reviewed        BOOLEAN DEFAULT false,
  reviewed_at     TIMESTAMPTZ,
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

-- Event log (append-only audit trail)
CREATE TABLE IF NOT EXISTS event_log (
  id          BIGSERIAL PRIMARY KEY,
  event_type  TEXT NOT NULL,
  user_id     UUID REFERENCES users(id),
  payload     JSONB,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_event_log_user_type ON event_log(user_id, event_type, created_at DESC);
