from functools import lru_cache

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="NOIR_", env_file=".env", extra="ignore")

    env: str = "development"
    secret_key: str = Field(default="dev-only-change-me")
    database_url: str = "sqlite:///./noir.sqlite3"
    cors_origins: str = (
        "http://localhost:5173,http://localhost:8080,http://localhost:3000,"
        "http://127.0.0.1:5173,http://127.0.0.1:8080,http://127.0.0.1:3000"
    )
    auto_create_tables: bool = True

    object_storage_backend: str = "local"
    s3_endpoint_url: str | None = None
    s3_access_key_id: str | None = None
    s3_secret_access_key: str | None = None
    s3_bucket: str = "noir-photos"
    s3_region: str = "us-east-1"
    s3_public_base_url: str | None = None

    access_token_days: int = 30
    otp_ttl_seconds: int = 600
    upload_url_ttl_seconds: int = 900
    download_url_ttl_seconds: int = 900

    @property
    def cors_origin_list(self) -> list[str]:
        return [origin.strip() for origin in self.cors_origins.split(",") if origin.strip()]

    @property
    def is_development(self) -> bool:
        return self.env.lower() in {"dev", "development", "local", "test"}


@lru_cache
def get_settings() -> Settings:
    return Settings()
