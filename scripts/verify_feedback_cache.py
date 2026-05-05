import sys
import os
from datetime import datetime, timezone

# Add the project root to sys.path
sys.path.append(os.getcwd())

from app.services.recommendation_cache import (
    _cache, 
    build_cache_key, 
    set_cached_recommendation, 
    invalidate_user_cache
)

def verify():
    user_id = "test-user-123"
    date = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    cache_key = build_cache_key(user_id, date, "mild")
    
    # 1. Set cache
    set_cached_recommendation(cache_key, {"test": "data"})
    print(f"Set cache for {cache_key}")
    
    # 2. Verify exists
    exists = _cache.exists(cache_key)
    print(f"Cache exists: {bool(exists)}")
    
    # 3. Invalidate
    deleted = invalidate_user_cache(user_id)
    print(f"Invalidated. Keys deleted: {deleted}")
    
    # 4. Verify gone
    exists_after = _cache.exists(cache_key)
    if not exists_after:
        print("SUCCESS: Cache invalidated successfully.")
    else:
        print("FAIL: Cache still exists.")

if __name__ == "__main__":
    verify()
