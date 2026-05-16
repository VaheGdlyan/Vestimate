-- ============================================================
-- PHASE 3 MIGRATION: Indexes + Prompt Seed
-- Run this against your Supabase project via the SQL editor.
-- ============================================================

-- 1. IVFFlat index for cosine similarity on wardrobe embeddings
--    NOTE: Only run after wardrobe_items has at least 1 row with
--    a non-null embedding. If table is empty, run after first
--    garment is ingested.
CREATE INDEX IF NOT EXISTS idx_wardrobe_embedding
ON wardrobe_items
USING ivfflat (embedding vector_cosine_ops)
WITH (lists = 100);

-- 2. Composite index for the category-split retrieval query pattern
CREATE INDEX IF NOT EXISTS idx_wardrobe_active_user_category
ON wardrobe_items (user_id, category)
WHERE status = 'active';

-- 3. Index for recency filter
CREATE INDEX IF NOT EXISTS idx_wardrobe_last_worn
ON wardrobe_items (user_id, last_worn_at DESC);

-- 4. Seed the initial prompt version (required for Phase 3 to run)
INSERT INTO prompt_versions (version, system_prompt, user_prompt_template, is_active, notes)
VALUES (
  'v1.0.0',
  'You are a professional stylist assistant. Your task is to select one complete outfit from the provided candidate garments that is appropriate for the given context. You must return ONLY a valid JSON object matching the exact schema provided. Do not add commentary, explanation, or text outside the JSON object.',
  '{"context": {{context}}, "candidates": {{candidates}}}',
  true,
  'Phase 3 initial launch prompt'
)
ON CONFLICT DO NOTHING;
