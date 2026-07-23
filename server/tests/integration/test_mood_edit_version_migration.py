import sqlite3
from pathlib import Path

from alembic import command
from alembic.config import Config

from app.core.config import get_settings


def test_mood_edit_version_migration_backfills_existing_rows(tmp_path, monkeypatch):
    database_path = tmp_path / "mood-edit-version.db"
    monkeypatch.setenv(
        "DATABASE_URL", f"sqlite+aiosqlite:///{database_path.as_posix()}"
    )
    get_settings.cache_clear()

    server_dir = Path(__file__).resolve().parents[2]
    config = Config(str(server_dir / "alembic.ini"))
    config.set_main_option("script_location", str(server_dir / "alembic"))

    try:
        command.upgrade(config, "0004_content_depth")
        with sqlite3.connect(database_path) as connection:
            cursor = connection.execute(
                """
                INSERT INTO users (
                    email, password_hash, nickname, timezone, seed_balance, streak_days,
                    created_at, updated_at
                ) VALUES (?, ?, ?, ?, 0, 0, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
                """,
                ("before-0005@example.com", "not-used", "기존 사용자", "Asia/Seoul"),
            )
            user_id = cursor.lastrowid
            connection.execute(
                """
                INSERT INTO mood_entries (
                    user_id, local_date, recorded_at_utc, mood_level, emotion_tags,
                    input_version, analysis_status, ai_label_hidden, created_at, updated_at
                ) VALUES (?, '2026-07-13', CURRENT_TIMESTAMP, 3, '[]', 1,
                          'not_requested', 0, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
                """,
                (user_id,),
            )

        command.upgrade(config, "head")
        with sqlite3.connect(database_path) as connection:
            version = connection.execute(
                "SELECT edit_version FROM mood_entries"
            ).fetchone()[0]
        assert version == 1

        command.downgrade(config, "0004_content_depth")
        with sqlite3.connect(database_path) as connection:
            columns = {
                row[1] for row in connection.execute("PRAGMA table_info(mood_entries)")
            }
        assert "edit_version" not in columns
    finally:
        get_settings.cache_clear()
