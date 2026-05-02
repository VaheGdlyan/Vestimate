import asyncio
import os
import sys

# Add the project root to the PYTHONPATH
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

from sqlalchemy import text
from app.core.config import async_session_maker

async def check_db():
    try:
        async with async_session_maker() as session:
            result = await session.execute(text("SELECT 1"))
            print(f"Database connection successful. Output: {result.scalar()}")
    except Exception as e:
        print(f"Database connection failed: {e}")

if __name__ == "__main__":
    asyncio.run(check_db())
