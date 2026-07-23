from functools import lru_cache
from typing import Literal

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    app_name: str = "mongroo-api"
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
        "http://localhost:3000", "http://127.0.0.1:3000",
        "http://localhost:5173", "http://127.0.0.1:5173",
        "http://localhost:8080", "http://127.0.0.1:8080",
    ]
    cors_origin_regex: str | None = r"^https?://(localhost|127\.0\.0\.1)(:\d+)?$"


@lru_cache
def get_settings() -> Settings:
    return Settings()
