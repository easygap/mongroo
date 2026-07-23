import json
import runpy
import sqlite3
from collections import Counter
from pathlib import Path

from alembic import command
from alembic.config import Config

from app.core.config import get_settings


def test_quest_content_expansion_is_balanced_neutral_and_reversible(
    tmp_path, monkeypatch
):
    database_path = tmp_path / "quest-content-expansion.db"
    monkeypatch.setenv(
        "DATABASE_URL", f"sqlite+aiosqlite:///{database_path.as_posix()}"
    )
    get_settings.cache_clear()

    server_dir = Path(__file__).resolve().parents[2]
    config = Config(str(server_dir / "alembic.ini"))
    config.set_main_option("script_location", str(server_dir / "alembic"))
    migration = runpy.run_path(
        str(
            server_dir
            / "alembic"
            / "versions"
            / "20260716_0013_quest_content_expansion.py"
        )
    )
    quest_codes = tuple(row[0] for row in migration["QUEST_ROWS"])
    placeholders = ", ".join("?" for _ in quest_codes)

    try:
        command.upgrade(config, "0012_first_payoff")
        with sqlite3.connect(database_path) as connection:
            before_count = connection.execute("SELECT COUNT(*) FROM quests").fetchone()[
                0
            ]

        command.upgrade(config, "head")
        with sqlite3.connect(database_path) as connection:
            quest_rows = connection.execute(
                f"""
                SELECT code, title, description, trigger_rule, category,
                       burden_level, estimated_minutes, safety_tags,
                       reward_exp, reward_seeds, is_active
                FROM quests
                WHERE code IN ({placeholders})
                ORDER BY code
                """,
                quest_codes,
            ).fetchall()
            after_count = connection.execute("SELECT COUNT(*) FROM quests").fetchone()[
                0
            ]
            category_counts = dict(
                connection.execute(
                    "SELECT category, COUNT(*) FROM quests GROUP BY category"
                ).fetchall()
            )
            light_movement_count = connection.execute(
                """
                SELECT COUNT(*) FROM quests
                WHERE category = 'movement' AND burden_level = 1
                """
            ).fetchone()[0]

        assert before_count == 36
        assert after_count == 45
        assert len(quest_rows) == 9
        assert {row[0] for row in quest_rows} == set(quest_codes)
        assert len({row[1] for row in quest_rows}) == 9
        assert len({row[2] for row in quest_rows}) == 9
        assert Counter(row[4] for row in quest_rows) == {
            "connection": 3,
            "self_kindness": 2,
            "rest": 1,
            "creativity": 1,
            "movement": 2,
        }
        assert {
            category: category_counts[category]
            for category in (
                "connection",
                "self_kindness",
                "rest",
                "creativity",
                "movement",
            )
        } == {
            "connection": 4,
            "self_kindness": 4,
            "rest": 4,
            "creativity": 4,
            "movement": 5,
        }
        assert light_movement_count == 2
        assert all(row[3] == "daily_neutral" for row in quest_rows)
        assert all(row[5] == 1 for row in quest_rows)
        assert all(1 <= row[6] <= 7 for row in quest_rows)
        assert {(row[8], row[9]) for row in quest_rows} == {(20, 5)}
        assert all(row[10] == 1 for row in quest_rows)

        rows_by_code = {row[0]: row for row in quest_rows}
        for code in (
            "QST_SHARED_LAUGH",
            "QST_RECOMMEND_ONE",
            "QST_QUIET_COMPANY",
        ):
            assert json.loads(rows_by_code[code][7]) == ["social_optional"]
        for code in ("QST_NEARBY_ROUND_TRIP", "QST_FOUR_BEAT_MOVE"):
            assert "mobility_adaptable" in json.loads(rows_by_code[code][7])

        prohibited_framing = ("진단", "치료", "상담", "우울증", "불안장애", "증상")
        assert all(
            not any(word in f"{row[1]} {row[2]}" for word in prohibited_framing)
            for row in quest_rows
        )

        with sqlite3.connect(database_path) as connection:
            user_id = connection.execute(
                """
                INSERT INTO users (
                    email, password_hash, nickname, timezone, seed_balance,
                    streak_days, created_at, updated_at
                ) VALUES (?, ?, ?, ?, 0, 0, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
                """,
                ("quest-rollback@example.com", "not-used", "퀘스트 검증", "Asia/Seoul"),
            ).lastrowid
            quest_id = connection.execute(
                "SELECT id FROM quests WHERE code = 'QST_SHARED_LAUGH'"
            ).fetchone()[0]
            user_quest_id = connection.execute(
                """
                INSERT INTO user_quests (user_id, quest_id, quest_date, status)
                VALUES (?, ?, '2026-07-16', 'assigned')
                """,
                (user_id, quest_id),
            ).lastrowid

        command.downgrade(config, "0012_first_payoff")
        with sqlite3.connect(database_path) as connection:
            remaining_quests = connection.execute(
                f"SELECT COUNT(*) FROM quests WHERE code IN ({placeholders})",
                quest_codes,
            ).fetchone()[0]
            remaining_assignment = connection.execute(
                "SELECT COUNT(*) FROM user_quests WHERE id = ?", (user_quest_id,)
            ).fetchone()[0]
            downgraded_count = connection.execute(
                "SELECT COUNT(*) FROM quests"
            ).fetchone()[0]

        assert remaining_quests == 0
        assert remaining_assignment == 0
        assert downgraded_count == before_count
    finally:
        get_settings.cache_clear()
