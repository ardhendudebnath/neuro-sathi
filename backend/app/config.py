"""Server settings. Every secret is read from the environment (a git-ignored
.env in development, a secret manager in production) and never leaves the server."""

from functools import lru_cache

from pydantic import Field, SecretStr
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    env: str = "development"  # development | test | production

    # Database. The API connects as the restricted `app_user` role (RLS applies).
    # The service role (BYPASSRLS, narrow grants) is used only for login, caregiver
    # link redemption and the scheduled deviation job.
    database_url: SecretStr = SecretStr("sqlite+pysqlite:///./neuro_sathi_dev.db")
    service_database_url: SecretStr | None = None

    redis_url: SecretStr | None = None  # rate-limit counters; in-memory when unset

    jwt_secret: SecretStr = SecretStr("dev-only-change-me-dev-only-change-me")
    jwt_algorithm: str = "HS256"
    access_token_minutes: int = 60 * 24 * 7

    otp_ttl_seconds: int = 300
    otp_max_attempts: int = 5
    otp_dev_echo: bool = False  # development only: return the OTP in the response

    sms_provider: str = "console"  # console | msg91
    sms_api_key: SecretStr | None = None
    sms_template_id: str | None = None

    # NVIDIA build.nvidia.com (server-side only)
    nvidia_api_key: SecretStr | None = None
    nvidia_base_url: str = "https://integrate.api.nvidia.com/v1"
    sathi_model: str = "sarvamai/sarvam-m"
    safety_model: str = "nvidia/llama-3.1-nemotron-safety-guard-multilingual-8b-v1"
    riva_grpc_uri: str = "grpc.nvcf.nvidia.com:443"
    asr_function_id: str | None = None  # Canary 1B ASR / Whisper Large V3
    tts_function_id: str | None = None  # Magpie TTS Multilingual

    # Global monthly budget for paid APIs; above it Sathi falls back to offline answers.
    paid_api_monthly_budget_inr: float = 5000.0
    llm_cost_per_call_inr: float = 0.5
    speech_cost_per_call_inr: float = 0.3

    # Photo storage: "local" (development) or "s3" (S3-compatible, private bucket)
    storage_backend: str = "local"
    storage_local_dir: str = "./uploads"
    s3_bucket: str | None = None
    s3_endpoint_url: str | None = None
    s3_public_endpoint_url: str | None = None  # host browsers use for signed URLs, if different
    s3_region: str = "ap-south-1"
    s3_access_key: SecretStr | None = None
    s3_secret_key: SecretStr | None = None
    signed_url_seconds: int = 300
    max_upload_bytes: int = 10 * 1024 * 1024

    firebase_credentials_file: str | None = None  # Firebase Admin, for caregiver push alerts

    # content/language-packs in the repo by default; the Docker image sets it explicitly.
    language_packs_dir: str | None = None

    cors_origins: list[str] = Field(default_factory=lambda: ["http://localhost:3000"])
    public_base_url: str = "http://localhost:8000"

    @property
    def is_production(self) -> bool:
        return self.env == "production"


@lru_cache
def get_settings() -> Settings:
    s = Settings()
    if s.is_production:
        if s.jwt_secret.get_secret_value().startswith("dev-only"):
            raise RuntimeError("JWT_SECRET must be set in production")
        if s.otp_dev_echo:
            raise RuntimeError("OTP_DEV_ECHO must be off in production")
    return s
