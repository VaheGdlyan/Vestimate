from pydantic_settings import BaseSettings
from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker, AsyncSession

class Settings(BaseSettings):
    APP_NAME: str = "Vestimate"
    DEBUG: bool = True
    REDIS_URL: str = "redis://127.0.0.1:6379/0"
    SUPABASE_DATABASE_URL: str = "postgresql+asyncpg://postgres:postgres@127.0.0.1:5432/postgres"
    
    # Supabase REST API (used by supabase-py client for table ops)
    SUPABASE_URL: str = ""
    SUPABASE_SERVICE_KEY: str = ""
    
    # Cloudflare R2 Configuration
    R2_ACCOUNT_ID: str = ""
    R2_ACCESS_KEY_ID: str = ""
    R2_SECRET_ACCESS_KEY: str = ""
    R2_BUCKET_NAME: str = "vestimate-assets"

    # Modal GPU Inference Endpoints
    MODAL_ENDPOINT_SEGMENT: str = ""
    MODAL_ENDPOINT_EMBED: str = ""
    MODAL_ENDPOINT_TEXT_EMBED: str = ""
    
    # External APIs
    OPENAI_API_KEY: str = ""
    OPENWEATHERMAP_API_KEY: str = ""

    # Phase 4
    SUPABASE_JWKS_URL: str = ""
    SUPABASE_JWT_AUDIENCE: str = "authenticated"
    SENTRY_DSN: str = ""
    LOGFIRE_TOKEN: str = ""
    PROMETHEUS_METRICS_TOKEN: str = ""
    RATE_LIMIT_UPLOAD: str = "10/minute"
    RATE_LIMIT_RECOMMENDATION: str = "30/minute"
    RATE_LIMIT_FEEDBACK: str = "60/minute"
    TOKEN_ENCRYPTION_KEY: str = "0sCkYAU5Np4gwWW7E4ffuryzi831doTur-LNg2FEw-A"
    ENV: str = "local"
    PREWARM_CRON_UTC: str = "23:00"

    model_config = {"env_file": ".env", "env_file_encoding": "utf-8"}

settings = Settings()

# SQLAlchemy 2.0 Async Engine Initialization
engine = create_async_engine(
    settings.SUPABASE_DATABASE_URL,
    echo=settings.DEBUG,
    future=True,
    connect_args={"statement_cache_size": 0}
)

async_session_maker = async_sessionmaker(
    engine,
    class_=AsyncSession,
    expire_on_commit=False
)
