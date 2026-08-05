import base64
import binascii
import re
from functools import lru_cache
from typing import Literal
from urllib.parse import urlparse

from pydantic import Field, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env", env_file_encoding="utf-8", extra="ignore"
    )

    app_name: str = "mongroo-api"
    app_env: Literal["development", "test", "production"] = "development"
    # demo는 합성 데이터 전용, real-data는 필드 암호화와 명시적 동의를 강제한다.
    data_profile: Literal["demo", "real-data"] = "demo"

    # 민감 필드는 ``enc:v1:{key_id}:...`` envelope로 저장한다. 키 값은
    # base64로 인코딩한 정확히 32바이트여야 하며 DB나 저장소에 넣지 않는다.
    field_encryption_keys: dict[str, str] = Field(default_factory=dict)
    active_field_encryption_key_id: str = ""
    terms_version: str = "2026-08-05"
    privacy_version: str = "2026-08-05"
    sensitive_consent_version: str = "2026-08-05"

    database_url: str = "mysql+aiomysql://mongroo:mongroo@127.0.0.1:3306/mongroo"

    jwt_secret: str = "dev-only-secret-change-me"
    jwt_issuer: str = "mongroo-api"
    jwt_audience: str = "mongroo-app"
    access_token_ttl_seconds: int = 900
    refresh_token_ttl_days: int = 30

    login_rate_limit_count: int = 10
    login_ip_rate_limit_count: int = 50
    login_rate_limit_window_seconds: int = 300

    database_pool_size: int = 10
    database_max_overflow: int = 20
    database_pool_recycle_seconds: int = 1800

    user_timezone: str = "Asia/Seoul"

    # rules: 배포 가능한 결정적 규칙 분석/대화, local: 로컬 모델, fake: 테스트 전용
    ai_mode: Literal["disabled", "fake", "rules", "local"] = "fake"

    ollama_base_url: str = "http://127.0.0.1:11434"
    ollama_model: str = "qwen3:8b-q4_K_M"
    ollama_num_ctx: int = 4096
    ollama_num_predict: int = 384
    ollama_temperature: float = 0.3
    ollama_timeout_seconds: int = 60

    classifier_model_dir: str = ""  # MONGROO_MODEL_ROOT/emotion_classifier/current
    classifier_abstain_threshold: float = 0.5

    worker_poll_interval_seconds: float = 1.0
    worker_heartbeat_stale_seconds: int = 60
    job_max_attempts: int = 3
    job_stale_running_seconds: int = 600

    chat_session_max_user_turns: int = 10
    chat_session_max_minutes: int = 30
    chat_prompt_message_window: int = 6

    # P1 퀘스트가 활성화된 현재 프로필은 전체 행동 합산 상한 50을 사용한다.
    daily_exp_cap: int = 50

    # Flutter web 로컬 개발용. credentials와 함께 wildcard origin은 사용하지 않는다.
    cors_origins: list[str] = [
        "http://localhost:3000",
        "http://127.0.0.1:3000",
        "http://localhost:5173",
        "http://127.0.0.1:5173",
        "http://localhost:8080",
        "http://127.0.0.1:8080",
    ]
    cors_origin_regex: str | None = r"^https?://(localhost|127\.0\.0\.1)(:\d+)?$"
    allowed_hosts: list[str] = ["localhost", "127.0.0.1", "test"]

    @model_validator(mode="after")
    def validate_production_settings(self):
        errors: list[str] = []
        if self.data_profile == "real-data":
            if not re.fullmatch(r"[A-Za-z0-9_-]{1,32}", self.active_field_encryption_key_id):
                errors.append(
                    "ACTIVE_FIELD_ENCRYPTION_KEY_ID must be 1-32 URL-safe characters"
                )
            if self.active_field_encryption_key_id not in self.field_encryption_keys:
                errors.append(
                    "ACTIVE_FIELD_ENCRYPTION_KEY_ID must select a configured key"
                )
            for key_id, encoded_key in self.field_encryption_keys.items():
                if not re.fullmatch(r"[A-Za-z0-9_-]{1,32}", key_id):
                    errors.append(
                        f"field encryption key ID {key_id!r} must be 1-32 URL-safe characters"
                    )
                    continue
                try:
                    decoded = base64.b64decode(encoded_key, validate=True)
                except (binascii.Error, ValueError):
                    decoded = b""
                if len(decoded) != 32:
                    errors.append(
                        f"field encryption key {key_id!r} must be base64 for exactly 32 bytes"
                    )
            for version_name, version in (
                ("TERMS_VERSION", self.terms_version),
                ("PRIVACY_VERSION", self.privacy_version),
                ("SENSITIVE_CONSENT_VERSION", self.sensitive_consent_version),
            ):
                if not version.strip():
                    errors.append(f"{version_name} must not be empty")

        if self.app_env != "production":
            if errors:
                raise ValueError("; ".join(errors))
            return self

        if self.data_profile != "real-data":
            errors.append("DATA_PROFILE=real-data is required in production")
        if len(self.jwt_secret.encode()) < 32 or self.jwt_secret in {
            "dev-only-secret-change-me",
            "change-me-to-a-random-32byte-or-longer-secret",
        }:
            errors.append("JWT_SECRET must be a non-default value of at least 32 bytes")
        database = urlparse(self.database_url)
        if (
            database.scheme != "mysql+aiomysql"
            or not database.hostname
            or not database.username
            or not database.password
            or "replace-with" in database.password
            or database.password == "mongroo"
        ):
            errors.append(
                "DATABASE_URL must use mysql+aiomysql with non-placeholder credentials"
            )
        if self.ai_mode == "fake":
            errors.append("AI_MODE=fake is not allowed in production")
        if self.cors_origin_regex:
            errors.append("CORS_ORIGIN_REGEX must be empty in production")
        if not self.cors_origins:
            errors.append("CORS_ORIGINS must contain the public app origin")
        for origin in self.cors_origins:
            parsed = urlparse(origin)
            if (
                parsed.scheme != "https"
                or not parsed.netloc
                or parsed.path not in ("", "/")
            ):
                errors.append(
                    f"CORS origin must be an HTTPS origin without a path: {origin}"
                )
        if not self.allowed_hosts or any(
            host == "*" or host.startswith("localhost") or host.startswith("127.")
            for host in self.allowed_hosts
        ):
            errors.append("ALLOWED_HOSTS must contain explicit public hosts")
        if errors:
            raise ValueError("; ".join(errors))
        return self


@lru_cache
def get_settings() -> Settings:
    return Settings()
