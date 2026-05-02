from pydantic_settings import BaseSettings
from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker, AsyncSession

class Settings(BaseSettings):
    APP_NAME: str = "Vestimate"
    DEBUG: bool = True
    REDIS_URL: str = "redis://127.0.0.1:6379/0"
    SUPABASE_DATABASE_URL: str = "postgresql+asyncpg://postgres:postgres@127.0.0.1:5432/postgres"
    
    # Cloudflare R2 Configuration
    R2_ACCOUNT_ID: str = ""
    R2_ACCESS_KEY_ID: str = ""
    R2_SECRET_ACCESS_KEY: str = ""
    R2_BUCKET_NAME: str = "vestimate-assets"

    model_config = {"env_file": ".env", "env_file_encoding": "utf-8"}

settings = Settings()

# SQLAlchemy 2.0 Async Engine Initialization
engine = create_async_engine(
    settings.SUPABASE_DATABASE_URL,
    echo=settings.DEBUG,
    future=True,
)

async_session_maker = async_sessionmaker(
    engine,
    class_=AsyncSession,
    expire_on_commit=False
)
