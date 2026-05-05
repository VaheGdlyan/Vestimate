import asyncio
import asyncpg
import sys
import os

sys.path.append(os.getcwd())
from app.core.config import settings

async def check():
    url = settings.SUPABASE_DATABASE_URL.replace('postgresql+asyncpg://', 'postgresql://')
    conn = await asyncpg.connect(url)
    try:
        row = await conn.fetchrow("SELECT * FROM pg_extension WHERE extname = 'pgcrypto'")
        print(f"pgcrypto enabled: {bool(row)}")
    finally:
        await conn.close()

if __name__ == "__main__":
    asyncio.run(check())
