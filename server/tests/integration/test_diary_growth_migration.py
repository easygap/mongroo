import json
import sqlite3
from pathlib import Path

from alembic import command
from alembic.config import Config

from app.core.config import get_settings


def test_diary_growth_migration_backfills_raw_analysis_and_versions(
    tmp_path, monkeypatch
):
    database_path = tmp_path / "diary-growth.db"
    monkeypatch.setenv(
        "DATABASE_URL", f"sqlite+aiosqlite:///{database_path.as_posix()}"
    )
    get_settings.cache_clear()
    server_dir = Path(__file__).resolve().parents[2]
    config = Config(str(server_dir / "alembic.ini"))
    config.set_main_option("script_location", str(server_dir / "alembic"))

    try:
        command.upgrade(config, "0009_content_copy")
        with sqlite3.connect(database_path) as connection:
            user_id = connection.execute(
                """
                INSERT INTO users (
                    email, password_hash, nickname, timezone, seed_balance, streak_days,
                    created_at, updated_at
                ) VALUES (?, ?, ?, ?, 0, 0, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
                """,
                ("growth-migration@example.com", "unused", "기록자", "Asia/Seoul"),
            ).lastrowid
            species_id = connection.execute(
                "SELECT id FROM plant_species WHERE code = 'basic_sprout'"
            ).fetchone()[0]
            plant_id = connection.execute(
                """
                INSERT INTO plants (
                    user_id, species_id, name, exp, status, planted_at,
                    created_at, updated_at, museum_featured
                ) VALUES (?, ?, '성장 중', 300, 'active', '2026-07-01 00:00:00',
                          CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 0)
                """,
                (user_id, species_id),
            ).lastrowid
            harvested_plant_id = connection.execute(
                """
                INSERT INTO plants (
                    user_id, species_id, name, exp, status, planted_at, harvested_at,
                    final_form, emotion_profile, created_at, updated_at, museum_featured
                ) VALUES (?, ?, '지난 식물', 1000, 'harvested', '2026-06-01 00:00:00',
                          '2026-06-30 23:59:59', 'sunny', '{"version": 1}',
                          CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 0)
                """,
                (user_id, species_id),
            ).lastrowid
            connection.execute(
                """
                INSERT INTO mood_entries (
                    user_id, local_date, recorded_at_utc, mood_level, emotion_tags,
                    content, input_version, analysis_status, ai_emotion,
                    ai_label_hidden, created_at, updated_at, edit_version
                ) VALUES (?, '2026-06-02', '2026-06-02 08:00:00', 3, '[]',
                          '지난 식물의 행복한 일기', 1, 'succeeded', '기쁨', 0,
                          CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 1)
                """,
                (user_id,),
            )
            for index in range(3):
                connection.execute(
                    """
                    INSERT INTO mood_entries (
                        user_id, local_date, recorded_at_utc, mood_level, emotion_tags,
                        content, input_version, analysis_status, ai_emotion,
                        ai_emotion_override, ai_label_hidden, created_at, updated_at,
                        edit_version
                    ) VALUES (?, '2026-07-02', ?, ?, '[]', ?, 4, 'succeeded',
                              '기쁨', '분노', 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 1)
                    """,
                    (user_id, f"2026-07-02 0{index}:00:00", 1, f"행복한 일기 {index}"),
                )
            half_state_entry_id = connection.execute(
                """
                INSERT INTO mood_entries (
                    user_id, local_date, recorded_at_utc, mood_level, emotion_tags,
                    content, input_version, analysis_status, ai_label_hidden,
                    created_at, updated_at, edit_version
                ) VALUES (?, '2026-07-03', '2026-07-03 09:00:00', 3, '[]',
                          'job만 실패한 일기', 5, 'running', 0,
                          CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 1)
                """,
                (user_id,),
            ).lastrowid
            connection.execute(
                """
                INSERT INTO ai_jobs (
                    job_type, resource_type, resource_id, input_version, status,
                    attempts, available_at, last_error_code, created_at
                ) VALUES ('mood_analysis', 'mood_entry', ?, 5, 'failed', 3,
                          CURRENT_TIMESTAMP, 'CLASSIFIER_ERROR', CURRENT_TIMESTAMP)
                """,
                (half_state_entry_id,),
            )

        command.upgrade(config, "head")
        with sqlite3.connect(database_path) as connection:
            versions_and_explicit = set(
                connection.execute(
                    "SELECT analysis_version, mood_level_explicit FROM mood_entries"
                )
            )
            growth_branch, raw_profile, branch_decided_at = connection.execute(
                "SELECT growth_branch, emotion_profile, branch_decided_at "
                "FROM plants WHERE id = ?",
                (plant_id,),
            ).fetchone()
            harvested_branch, harvested_raw_profile, harvested_decided_at = (
                connection.execute(
                    "SELECT growth_branch, emotion_profile, branch_decided_at "
                    "FROM plants WHERE id = ?",
                    (harvested_plant_id,),
                ).fetchone()
            )
            half_state = connection.execute(
                "SELECT analysis_version, analysis_status, analysis_error_code "
                "FROM mood_entries WHERE id = ?",
                (half_state_entry_id,),
            ).fetchone()
            mood_indexes = {
                row[1] for row in connection.execute("PRAGMA index_list(mood_entries)")
            }

        profile = json.loads(raw_profile)
        assert versions_and_explicit == {(1, 1), (4, 1), (5, 1)}
        assert growth_branch == "joy"
        assert branch_decided_at is not None
        assert profile["version"] == 2
        assert profile["source"] == "diary_text_analysis"
        assert profile["counts"]["joy"] == 3
        assert profile["pending_count"] == 0
        assert profile["unavailable_count"] == 1
        # 사용자 직접 점수·교정·숨김은 migration에서도 성장 입력이 아니다.
        assert profile["counts"]["anger"] == 0
        assert profile["counts"]["sadness"] == 0
        harvested_profile = json.loads(harvested_raw_profile)
        assert harvested_branch == "joy"
        assert harvested_decided_at is not None
        assert harvested_profile["version"] == 2
        assert harvested_profile["counts"]["joy"] == 1
        assert half_state == (5, "failed", "CLASSIFIER_ERROR")
        assert "ix_mood_growth_lifecycle" in mood_indexes

        command.downgrade(config, "0009_content_copy")
        with sqlite3.connect(database_path) as connection:
            mood_columns = {
                row[1] for row in connection.execute("PRAGMA table_info(mood_entries)")
            }
            plant_columns = {
                row[1] for row in connection.execute("PRAGMA table_info(plants)")
            }
            downgraded_indexes = {
                row[1] for row in connection.execute("PRAGMA index_list(mood_entries)")
            }
        assert "analysis_version" not in mood_columns
        assert "mood_level_explicit" not in mood_columns
        assert {"growth_branch", "branch_decided_at"}.isdisjoint(plant_columns)
        assert "ix_mood_growth_lifecycle" not in downgraded_indexes
    finally:
        get_settings.cache_clear()
