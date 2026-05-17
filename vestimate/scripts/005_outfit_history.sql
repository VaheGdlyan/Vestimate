-- =============================================
-- VESTIMATE Database Migration: Phase 5
-- Outfit History Upgrades (Epic 3)
-- Adds prompt-mandated fields to outfits table.
-- =============================================

ALTER TABLE outfits
ADD COLUMN IF NOT EXISTS label TEXT,
ADD COLUMN IF NOT EXISTS item_ids UUID[],
ADD COLUMN IF NOT EXISTS worn_at TIMESTAMPTZ;
