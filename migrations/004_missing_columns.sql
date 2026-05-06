-- Migration: add missing columns for Vestimate

-- Add last_active_at to users table
ALTER TABLE users ADD COLUMN IF NOT EXISTS last_active_at TIMESTAMPTZ;
CREATE INDEX IF NOT EXISTS idx_users_last_active ON users(last_active_at DESC);

-- Add google_oauth_scopes column
ALTER TABLE users ADD COLUMN IF NOT EXISTS google_oauth_scopes TEXT[];
