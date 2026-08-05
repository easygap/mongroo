from functools import lru_cache
from typing import Literal
from urllib.parse import urlparse

from pydantic import model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env", env_file_encoding="utf-8", extra="ignore"
    )

    app_name: str = "mongroo-api"
    app_env: Literal["development", "test", "production"] = "development"
    # demo 프로파일에서는 합성 데이터만 사용한다 (design.md 9.1)
    data_profile: Literal["demo"] = "demo"

    database_url: str = "mysql+aiomysql://mongroo:mongroo@127.0.0.1:3306/mongroo"

    jwt_secret: str = "dev-only-secret-change-me"
    jwt_issuer: str = "mongroo-api"
    jwt_audience: str = "mongroo-app"
    access_token_ttl_seconds: int = 900
    refresh_token_ttl_days: int = 30

    login_rate_limit_count: int = 10
    login_rate_limit_window_seconds: int = 300

    user_timezone: str = "Asia/Seoul"

    # disabled: AI job 생성 안 함 / fake: 결정적 가짜 응답 / local: 로컬 모델 사용
    ai_mode: Literal["disabled", "fake", "local"] = "fake"

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
        if self.app_env != "production":
            return self
        errors: list[str] = []
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
