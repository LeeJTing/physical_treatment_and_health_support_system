from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    supabase_jwt_secret: str = ""
    supabase_jwks_url: str = ""
    dev_auth_bypass: bool = True
    model_dir: str = "models/weights"
    api_version: str = "0.1.0"


@lru_cache
def get_settings() -> Settings:
    return Settings()
