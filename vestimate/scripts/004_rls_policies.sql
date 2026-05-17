-- ══════════════════════════════════════════════════
-- VESTIMATE — Row-Level Security Policies
-- Run against Supabase production project
-- ══════════════════════════════════════════════════

-- wardrobe_items
ALTER TABLE wardrobe_items ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "wardrobe_items_user_isolation" ON wardrobe_items;
CREATE POLICY "wardrobe_items_user_isolation"
  ON wardrobe_items FOR ALL
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- feedback_events
ALTER TABLE feedback_events ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "feedback_events_user_isolation" ON feedback_events;
CREATE POLICY "feedback_events_user_isolation"
  ON feedback_events FOR ALL
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- recommendation_cache
ALTER TABLE recommendation_cache ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "recommendation_cache_user_isolation" ON recommendation_cache;
CREATE POLICY "recommendation_cache_user_isolation"
  ON recommendation_cache FOR ALL
  USING (user_id = auth.uid());

-- outfits
ALTER TABLE outfits ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "outfits_user_isolation" ON outfits;
CREATE POLICY "outfits_user_isolation"
  ON outfits FOR ALL
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- manual_review_queue
ALTER TABLE manual_review_queue ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "review_queue_user_isolation" ON manual_review_queue;
CREATE POLICY "review_queue_user_isolation"
  ON manual_review_queue FOR SELECT
  USING (user_id = auth.uid());

-- event_log (read-only for users; write is service_role only)
ALTER TABLE event_log ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "event_log_user_read" ON event_log;
CREATE POLICY "event_log_user_read"
  ON event_log FOR SELECT
  USING (user_id = auth.uid());

-- users (users can read/update only their own row)
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "users_self_access" ON users;
CREATE POLICY "users_self_access"
  ON users FOR ALL
  USING (id = auth.uid())
  WITH CHECK (id = auth.uid());

-- prompt_versions (read-only for all authenticated users; write is service_role)
ALTER TABLE prompt_versions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "prompt_versions_read_all" ON prompt_versions;
CREATE POLICY "prompt_versions_read_all"
  ON prompt_versions FOR SELECT
  USING (auth.role() = 'authenticated');
