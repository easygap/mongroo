import asyncio
from pathlib import Path

import sqlalchemy as sa
import pytest
from alembic import command
from alembic.config import Config
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine

from app.core.config import get_settings
from app.core.field_encryption import FieldEncryptionError
from app.models.mood import MoodEntry
from app.models.ops import IdempotencyKey
from app.models.report import Report
from app.models.user import User
from app.protect_sensitive_data import run


async def test_plaintext_backfill_verification_and_key_rotation(tmp_path, monkeypatch):
    database_path = tmp_path / "protected.db"
    database_url = f"sqlite+aiosqlite:///{database_path}"
    monkeypatch.setenv("DATABASE_URL", database_url)
    monkeypatch.setenv("DATA_PROFILE", "demo")
    get_settings.cache_clear()

    server_dir = Path(__file__).resolve().parents[2]
    config = Config(str(server_dir / "alembic.ini"))
    config.set_main_option("script_location", str(server_dir / "alembic"))
    await asyncio.to_thread(command.upgrade, config, "head")

    engine = create_async_engine(database_url)
    sessions = async_sessionmaker(engine, expire_on_commit=False)
    async with sessions() as db:
        user = User(
            email="protected@example.com",
            password_hash="not-a-real-password-hash",
            nickname="암호화 확인",
            terms_version="2026-08-05",
            privacy_version="2026-08-05",
            sensitive_consent_version="2026-08-05",
        )
        db.add(user)
        await db.flush()
        db.add(
            MoodEntry(
                user_id=user.id,
                local_date=sa.func.current_date(),
                recorded_at_utc=sa.func.current_timestamp(),
                mood_level=3,
                mood_level_explicit=False,
                emotion_tags=["안도"],
                content="암호화 전 평문 마음 일기",
                ai_emotion="기쁨",
                ai_scores={"기쁨": 0.9},
            )
        )
        db.add(
            Report(
                user_id=user.id,
                period_type="weekly",
                period_start=sa.func.current_date(),
                period_end=sa.func.current_date(),
                input_hash="a" * 64,
                stats={"keywords": ["마음"]},
                summary={"reflection": "조금 편안해졌어요"},
            )
        )
        db.add(
            IdempotencyKey(
                user_id=user.id,
                route_scope="test",
                idempotency_key="migration-test",
                request_hash="b" * 64,
                response_status=201,
                response_body={"mood": {"content": "응답 안의 일기"}},
            )
        )
        await db.commit()

    monkeypatch.setenv("DATA_PROFILE", "real-data")
    monkeypatch.setenv(
        "FIELD_ENCRYPTION_KEYS",
        '{"v1":"MDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDA="}',
    )
    monkeypatch.setenv("ACTIVE_FIELD_ENCRYPTION_KEY_ID", "v1")
    get_settings.cache_clear()

    changed, remaining = await run(verify_only=False, rotate=False)
    assert changed == 7
    assert remaining == 0

    async with engine.connect() as connection:
        raw = (
            await connection.execute(
                sa.text(
                    "SELECT content, emotion_tags, ai_emotion, ai_scores, content_length "
                    "FROM mood_entries"
                )
            )
        ).one()
        assert all(value.startswith("enc:v1:v1:") for value in raw[:4])
        assert raw.content_length == 1
        protection_state = (
            await connection.execute(
                sa.text(
                    "SELECT schema_revision, active_key_id, remaining_plaintext "
                    "FROM data_protection_states"
                )
            )
        ).one()
        assert protection_state == ("0029_real_data_protection", "v1", 0)

    async with sessions() as db:
        mood = await db.scalar(sa.select(MoodEntry))
        assert mood.content == "암호화 전 평문 마음 일기"
        assert mood.emotion_tags == ["안도"]
        assert mood.ai_scores == {"기쁨": 0.9}

    monkeypatch.setenv(
        "FIELD_ENCRYPTION_KEYS",
        '{"v1":"MDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDA=",'
        '"v2":"MTExMTExMTExMTExMTExMTExMTExMTExMTExMTExMTE="}',
    )
    monkeypatch.setenv("ACTIVE_FIELD_ENCRYPTION_KEY_ID", "v2")
    get_settings.cache_clear()
    rotated, remaining = await run(verify_only=False, rotate=True)
    assert rotated == 7
    assert remaining == 0
    async with engine.connect() as connection:
        raw_content = await connection.scalar(
            sa.text("SELECT content FROM mood_entries")
        )
        assert raw_content.startswith("enc:v1:v2:")
        active_key_id = await connection.scalar(
            sa.text("SELECT active_key_id FROM data_protection_states")
        )
        assert active_key_id == "v2"

    async with engine.begin() as connection:
        encrypted = await connection.scalar(sa.text("SELECT content FROM mood_entries"))
        marker = len(encrypted) // 2
        replacement = "A" if encrypted[marker] != "A" else "B"
        await connection.execute(
            sa.text("UPDATE mood_entries SET content = :content"),
            {"content": encrypted[:marker] + replacement + encrypted[marker + 1 :]},
        )

    with pytest.raises(FieldEncryptionError):
        await run(verify_only=True, rotate=False)
    async with engine.connect() as connection:
        remaining_plaintext = await connection.scalar(
            sa.text("SELECT remaining_plaintext FROM data_protection_states")
        )
        assert remaining_plaintext == -1

    await engine.dispose()
    get_settings.cache_clear()
