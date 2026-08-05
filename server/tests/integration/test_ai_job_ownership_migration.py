import sqlite3
from pathlib import Path

from alembic import command
from alembic.config import Config

from app.core.config import get_settings


def test_ai_job_owner_backfill_orphan_cleanup_and_account_cascade(
    tmp_path, monkeypatch
):
    database_path = tmp_path / "ai-job-ownership.db"
    monkeypatch.setenv(
        "DATABASE_URL", f"sqlite+aiosqlite:///{database_path.as_posix()}"
    )
    get_settings.cache_clear()
    server_dir = Path(__file__).resolve().parents[2]
    config = Config(str(server_dir / "alembic.ini"))
    config.set_main_option("script_location", str(server_dir / "alembic"))

    try:
        command.upgrade(config, "0029_real_data_protection")
        with sqlite3.connect(database_path) as connection:
            user_id = connection.execute(
                """
                INSERT INTO users (
                    email, password_hash, nickname, timezone, seed_balance,
                    streak_days, created_at, updated_at
                ) VALUES (?, ?, ?, 'Asia/Seoul', 0, 0,
                          CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
                """,
                ("job-owner@example.com", "unused", "작업 소유자"),
            ).lastrowid
            species_id = connection.execute(
                "SELECT id FROM plant_species ORDER BY id LIMIT 1"
            ).fetchone()[0]
            plant_id = connection.execute(
                """
                INSERT INTO plants (
                    user_id, species_id, name, exp, status, planted_at,
                    created_at, updated_at, museum_featured
                ) VALUES (?, ?, '작업 식물', 0, 'active', CURRENT_TIMESTAMP,
                          CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 0)
                """,
                (user_id, species_id),
            ).lastrowid
            mood_id = connection.execute(
                """
                INSERT INTO mood_entries (
                    user_id, local_date, recorded_at_utc, mood_level,
                    mood_level_explicit, emotion_tags, content, content_length,
                    input_version, analysis_version, analysis_status,
                    ai_label_hidden, edit_version, created_at, updated_at
                ) VALUES (?, '2026-08-05', CURRENT_TIMESTAMP, 3, 0, '[]',
                          '소유권 backfill 일기', 1, 1, 1, 'pending', 0, 1,
                          CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
                """,
                (user_id,),
            ).lastrowid
            session_id = connection.execute(
                """
                INSERT INTO chat_sessions (
                    user_id, plant_id, reflection_stage, safety_state, status,
                    started_at
                ) VALUES (?, ?, 'greeting', 'normal', 'active', CURRENT_TIMESTAMP)
                """,
                (user_id, plant_id),
            ).lastrowid
            message_id = connection.execute(
                """
                INSERT INTO chat_messages (
                    session_id, role, content, safety_status, created_at
                ) VALUES (?, 'user', '대화 입력', 'normal', CURRENT_TIMESTAMP)
                """,
                (session_id,),
            ).lastrowid
            run_id = connection.execute(
                """
                INSERT INTO chat_runs (
                    session_id, user_message_id, client_message_id, status,
                    created_at
                ) VALUES (?, ?, 'migration-chat-run', 'queued', CURRENT_TIMESTAMP)
                """,
                (session_id, message_id),
            ).lastrowid
            report_id = connection.execute(
                """
                INSERT INTO reports (
                    user_id, period_type, period_start, period_end, input_hash,
                    status, stats, analysis_coverage, created_at, updated_at
                ) VALUES (?, 'weekly', '2026-08-03', '2026-08-10', ?,
                          'pending', '{}', 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
                """,
                (user_id, "a" * 64),
            ).lastrowid
            jobs = (
                ("mood_analysis", "mood_entry", mood_id),
                ("chat_generation", "chat_run", run_id),
                ("report_summary", "report", report_id),
                ("mood_analysis", "mood_entry", 999_999),
            )
            connection.executemany(
                """
                INSERT INTO ai_jobs (
                    job_type, resource_type, resource_id, input_version, status,
                    attempts, available_at, created_at
                ) VALUES (?, ?, ?, 1, 'pending', 0,
                          CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
                """,
                jobs,
            )

        command.upgrade(config, "head")
        with sqlite3.connect(database_path) as connection:
            columns = {
                row[1]: row for row in connection.execute("PRAGMA table_info(ai_jobs)")
            }
            assert columns["user_id"][3] == 1
            assert (
                connection.execute(
                    "SELECT COUNT(*) FROM ai_jobs WHERE user_id = ?", (user_id,)
                ).fetchone()[0]
                == 3
            )
            assert (
                connection.execute(
                    "SELECT COUNT(*) FROM ai_jobs WHERE resource_id = 999999"
                ).fetchone()[0]
                == 0
            )
            foreign_keys = list(connection.execute("PRAGMA foreign_key_list(ai_jobs)"))
            assert any(
                row[2] == "users"
                and row[3] == "user_id"
                and row[4] == "id"
                and row[6].upper() == "CASCADE"
                for row in foreign_keys
            )

            connection.execute("PRAGMA foreign_keys = ON")
            connection.execute("DELETE FROM users WHERE id = ?", (user_id,))
            assert (
                connection.execute(
                    "SELECT COUNT(*) FROM ai_jobs WHERE user_id = ?", (user_id,)
                ).fetchone()[0]
                == 0
            )

        command.downgrade(config, "0029_real_data_protection")
        with sqlite3.connect(database_path) as connection:
            columns = {
                row[1] for row in connection.execute("PRAGMA table_info(ai_jobs)")
            }
            assert "user_id" not in columns

        command.upgrade(config, "head")
    finally:
        get_settings.cache_clear()
