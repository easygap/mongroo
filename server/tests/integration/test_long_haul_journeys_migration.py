"""마이그레이션이 만든 스키마에 개척을 **실제로 한 줄 넣어 본다**.

다른 통합 검사는 `Base.metadata.create_all`로 표를 만든다. 그래서 모델과
마이그레이션이 어긋나도 초록불이다. 실제로 그렇게 새어 나갔다 — 마이그레이션이
`id`를 `sa.BigInteger`로 만드는 바람에 SQLite에서 autoincrement가 붙지 않았고,
검사는 전부 통과하는데 실기에서 첫 개척이 500으로 떨어졌다.

여기서는 alembic으로만 표를 세우고 INSERT까지 해 본다.
"""

import sqlite3
from datetime import date, datetime
from pathlib import Path

from alembic import command
from alembic.config import Config

from app.api.routers.health import EXPECTED_SCHEMA_REVISION
from app.core.config import get_settings


def _migrated(tmp_path, monkeypatch) -> Path:
    database_path = tmp_path / "journeys.db"
    monkeypatch.setenv(
        "DATABASE_URL", f"sqlite+aiosqlite:///{database_path.as_posix()}"
    )
    get_settings.cache_clear()
    server_dir = Path(__file__).resolve().parents[2]
    config = Config(str(server_dir / "alembic.ini"))
    config.set_main_option("script_location", str(server_dir / "alembic"))
    command.upgrade(config, "head")
    get_settings.cache_clear()
    return database_path


def test_migrated_schema_accepts_a_journey_and_a_camping_slot(tmp_path, monkeypatch):
    database_path = _migrated(tmp_path, monkeypatch)
    now = datetime(2026, 9, 1, 3, 0, 0)

    with sqlite3.connect(database_path) as connection:
        connection.execute(
            """
            INSERT INTO users (email, password_hash, nickname, timezone,
                               seed_balance, streak_days, created_at, updated_at)
            VALUES (?, ?, ?, ?, 0, 0, ?, ?)
            """,
            ("walker@example.com", "x", "산책자", "Asia/Seoul", now, now),
        )
        user_id = connection.execute("SELECT last_insert_rowid()").fetchone()[0]

        # id를 주지 않는다. 여기가 실제로 터졌던 자리다.
        connection.execute(
            """
            INSERT INTO expedition_journeys
                (user_id, direction_code, status, mode, local_date,
                 content_version, max_legs, current_leg_index, reward_eligible,
                 revision, legs_snapshot, members_snapshot, started_at)
            VALUES (?, 'beyond_the_well', 'active', 'free_explore', ?,
                    'journey-v1', 2, 0, 0, 0, '[]', '{}', ?)
            """,
            (user_id, date(2026, 9, 1), now),
        )
        journey_id = connection.execute("SELECT last_insert_rowid()").fetchone()[0]
        assert journey_id > 0

        # 야영 중인 개척은 진행 중인 run 없이 슬롯을 잡는다.
        connection.execute(
            """
            INSERT INTO user_active_expeditions (user_id, journey_id, created_at)
            VALUES (?, ?, ?)
            """,
            (user_id, journey_id, now),
        )
        slot = connection.execute(
            "SELECT run_id, journey_id FROM user_active_expeditions"
        ).fetchone()
        assert slot == (None, journey_id)

        revision = connection.execute(
            "SELECT version_num FROM alembic_version"
        ).fetchone()[0]
        assert revision == EXPECTED_SCHEMA_REVISION


def test_journey_columns_land_on_runs_and_slots(tmp_path, monkeypatch):
    database_path = _migrated(tmp_path, monkeypatch)
    with sqlite3.connect(database_path) as connection:

        def columns(table: str) -> set[str]:
            return {
                row[1] for row in connection.execute(f"PRAGMA table_info({table})")
            }

        assert {"journey_id", "journey_leg_index"} <= columns("expedition_runs")
        assert "journey_id" in columns("user_active_expeditions")
        # 야영 중에는 run이 없으므로 NULL을 받아야 한다.
        run_id = next(
            row
            for row in connection.execute("PRAGMA table_info(user_active_expeditions)")
            if row[1] == "run_id"
        )
        assert run_id[3] == 0, "run_id는 NULL 허용이어야 한다"
