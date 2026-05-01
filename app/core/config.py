from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    """Centralized application settings.

    All configuration is loaded from environment variables (or .env file).
    No hardcoded strings anywhere else in the codebase.
    """

    APP_NAME: str = "Vestimate"
    DEBUG: bool = True
    REDIS_URL: str = "redis://localhost:6379/0"

    model_config = {"env_file": ".env", "env_file_encoding": "utf-8"}


settings = Settings()
