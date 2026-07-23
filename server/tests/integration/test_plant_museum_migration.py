import json
import sqlite3
from pathlib import Path

from alembic import command
from alembic.config import Config

from app.core.config import get_settings


def test_plant_museum_migration_backfills_harvested_plants(tmp_path, monkeypatch):
    database_path = tmp_path / "plant-museum.db"
    monkeypatch.setenv(
        "DATABASE_URL", f"sqlite+aiosqlite:///{database_path.as_posix()}"
    )
    get_settings.cache_clear()

    server_dir = Path(__file__).resolve().parents[2]
    config = Config(str(server_dir / "alembic.ini"))
    config.set_main_option("script_location", str(server_dir / "alembic"))

    try:
        command.upgrade(config, "0006_room_acquisition")
        with sqlite3.connect(database_path) as connection:
            user_id = connection.execute(
                """
                INSERT INTO users (
                    email, password_hash, nickname, timezone, seed_balance, streak_days,
                    created_at, updated_at
                ) VALUES (?, ?, ?, ?, 0, 0, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
                """,
                ("museum-migration@example.com", "not-used", "표본 주인", "Asia/Seoul"),
            ).lastrowid
            species_id = connection.execute(
                "SELECT id FROM plant_species WHERE code = 'basic_sprout'"
            ).fetchone()[0]
            harvested_id = connection.execute(
                """
                INSERT INTO plants (
                    user_id, species_id, name, exp, status, planted_at, harvested_at,
                    created_at, updated_at
                ) VALUES (?, ?, '기존 표본', 1000, 'harvested', CURRENT_TIMESTAMP,
                          CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
                """,
                (user_id, species_id),
            ).lastrowid
            active_id = connection.execute(
                """
                INSERT INTO plants (
                    user_id, species_id, name, exp, status, planted_at,
                    created_at, updated_at
                ) VALUES (?, ?, '성장 중', 20, 'active', CURRENT_TIMESTAMP,
                          CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
                """,
                (user_id, species_id),
            ).lastrowid

        command.upgrade(config, "head")
        with sqlite3.connect(database_path) as connection:
            harvested = connection.execute(
                """
                SELECT final_form, emotion_profile, museum_featured, growth_branch
                FROM plants WHERE id = ?
                """,
                (harvested_id,),
            ).fetchone()
            active = connection.execute(
                """
                SELECT final_form, emotion_profile, museum_featured, growth_branch
                FROM plants WHERE id = ?
                """,
                (active_id,),
            ).fetchone()
            indexes = {
                row[1] for row in connection.execute("PRAGMA index_list(plants)")
            }

        assert harvested[0] == "mosaic"
        assert json.loads(harvested[1])["total"] == 0
        assert harvested[2:] == (0, "mixed")
        assert active[0] is None
        assert json.loads(active[1])["version"] == 2
        assert json.loads(active[1])["total"] == 0
        assert active[2:] == (0, None)
        assert "ix_plants_museum" in indexes

        command.downgrade(config, "0006_room_acquisition")
        with sqlite3.connect(database_path) as connection:
            columns = {row[1] for row in connection.execute("PRAGMA table_info(plants)")}
        assert {"final_form", "emotion_profile", "museum_featured"}.isdisjoint(columns)
    finally:
        get_settings.cache_clear()
