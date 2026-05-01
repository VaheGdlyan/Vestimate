from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    APP_NAME: str = "Vestimate"
    DEBUG: bool = True
    REDIS_URL: str = "redis://redis:6379/0"

    model_config = {"env_file": ".env", "env_file_encoding": "utf-8"}

settings = Settings()
