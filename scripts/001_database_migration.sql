-- Enable pgvector extension
CREATE EXTENSION IF NOT EXISTS vector;

-- Create users table (required as a foreign key reference)
CREATE TABLE IF NOT EXISTS users (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email           TEXT UNIQUE NOT NULL,
  display_name    TEXT,
  city            TEXT NOT NULL,
  timezone        TEXT NOT NULL DEFAULT 'UTC',
  google_oauth_token  JSONB,
  onboarding_complete BOOLEAN DEFAULT false,
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW()
);

-- Create wardrobe_items table
CREATE TABLE IF NOT EXISTS wardrobe_items (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  
  -- Status lifecycle: processing → active | failed | archived
  status          TEXT NOT NULL DEFAULT 'processing'
                  CHECK (status IN ('processing', 'active', 'failed', 'archived')),
  
  -- User-provided
  item_name       TEXT,
  
  -- ML-derived tags
  category        TEXT CHECK (category IN (
                    'top', 'bottom', 'outerwear', 'shoes', 'accessory', 'dress', 'unknown'
                  )),
  material        TEXT,
  fit             TEXT,
  colors          TEXT[],                 -- array of color names from 32-color palette
  confidence_min  FLOAT,                  -- min confidence across all tags; < 0.70 = needs_review
  needs_review    BOOLEAN DEFAULT false,
  
  -- Storage references
  raw_image_key   TEXT,                   -- R2 object key for original upload
  image_url       TEXT,                   -- CDN URL of segmented image (public)
  
  -- Vector embedding (512 dimensions for FashionCLIP)
  embedding       vector(512),
  
  -- Lifecycle tracking
  last_worn_at    TIMESTAMPTZ,
  wear_count      INTEGER DEFAULT 0,
  processed_at    TIMESTAMPTZ,
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_wardrobe_items_user_id ON wardrobe_items(user_id);
CREATE INDEX IF NOT EXISTS idx_wardrobe_items_user_category ON wardrobe_items(user_id, category) 
  WHERE status = 'active';
CREATE INDEX IF NOT EXISTS idx_wardrobe_items_last_worn ON wardrobe_items(user_id, last_worn_at);

-- pgvector index for fast cosine similarity retrieval (IVFFlat)
CREATE INDEX IF NOT EXISTS idx_wardrobe_embedding ON wardrobe_items 
  USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);
