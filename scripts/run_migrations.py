import asyncio
import asyncpg
import os
import glob
import sys
from pathlib import Path

# Add project root to sys.path to allow imports if needed
project_root = Path(__file__).parent.parent
sys.path.append(str(project_root))

from app.core.config import settings

async def run_migrations():
    url = settings.SUPABASE_DATABASE_URL.replace("postgresql+asyncpg://", "postgresql://")
    print(f"Connecting to database...")
    
    try:
        conn = await asyncpg.connect(url, statement_cache_size=0)
    except Exception as e:
        print(f"Failed to connect to database: {e}")
        sys.exit(1)
        
    try:
        # Create schema_migrations table if it doesn't exist to track applied migrations
        await conn.execute("""
            CREATE TABLE IF NOT EXISTS schema_migrations (
                filename TEXT PRIMARY KEY,
                applied_at TIMESTAMPTZ DEFAULT NOW()
            );
        """)
        
        # Collect all SQL files from scripts/ and migrations/
        sql_files = []
        sql_files.extend(glob.glob(os.path.join(project_root, "scripts", "*.sql")))
        sql_files.extend(glob.glob(os.path.join(project_root, "migrations", "*.sql")))
        
        # Sort files alphabetically to ensure execution order
        sql_files.sort(key=lambda f: os.path.basename(f))
        
        if not sql_files:
            print("No migration scripts found.")
            return

        for filepath in sql_files:
            filename = os.path.basename(filepath)
            
            # Check if migration already applied
            row = await conn.fetchrow("SELECT filename FROM schema_migrations WHERE filename = $1", filename)
            if row:
                print(f"Skipping {filename} (already applied)")
                continue
                
            print(f"Applying migration: {filename}...")
            try:
                with open(filepath, "r", encoding="utf-8") as f:
                    sql = f.read()
                    
                # Run the migration
                await conn.execute(sql)
                
                # Record the migration as applied
                await conn.execute("INSERT INTO schema_migrations (filename) VALUES ($1)", filename)
                print(f"Successfully applied {filename}")
                
            except Exception as e:
                print(f"Error applying {filename}: {e}")
                print("Aborting remaining migrations.")
                sys.exit(1)
                
    finally:
        await conn.close()
        print("Database connection closed.")

if __name__ == "__main__":
    asyncio.run(run_migrations())
