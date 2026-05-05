import asyncio
import asyncpg
import sys
import os

# Add the project root to sys.path
sys.path.append(os.getcwd())

from app.core.config import settings

async def verify_rls():
    url = settings.SUPABASE_DATABASE_URL.replace('postgresql+asyncpg://', 'postgresql://')
    conn = await asyncpg.connect(url, statement_cache_size=0)
    try:
        tables = ['wardrobe_items', 'outfits', 'feedback_events', 'recommendation_cache', 'users']
        print('Verifying RLS status:')
        for table in tables:
            row = await conn.fetchrow(
                'SELECT relname, relrowsecurity FROM pg_class WHERE relname = $1',
                table
            )
            if row:
                status = 'ENABLED' if row['relrowsecurity'] else 'DISABLED'
                print(f'  Table: {table:<25} RLS: {status}')
            else:
                print(f'  Table: {table:<25} RLS: NOT FOUND')
    except Exception as e:
        print(f'Error: {e}')
    finally:
        await conn.close()

if __name__ == "__main__":
    asyncio.run(verify_rls())
