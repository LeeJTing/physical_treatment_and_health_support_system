from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    supabase_jwt_secret: str = ""
    supabase_jwks_url: str = ""
    dev_auth_bypass: bool = True
    model_dir: str = "models/weights"
    # Where new models run (app/device.py): "auto" = the GPU when torch sees one (Elwin's PC: RTX 3050),
    # else the CPU; "cpu" or "cuda" to force it.
    torch_device: str = "auto"
    api_version: str = "0.1.0"
    # Development viewer (devtools/, 9 Oct). Off by default: when on, every /pose request's video,
    # landmarks and step-by-step trace are kept in dev_runs_dir (newest dev_runs_keep) so they can be
    # looked at on http://127.0.0.1:8001. Never on with real patients' videos.
    dev_tools: bool = False
    dev_runs_dir: str = "dev_runs"
    dev_runs_keep: int = 20


@lru_cache
def get_settings() -> Settings:
    return Settings()
