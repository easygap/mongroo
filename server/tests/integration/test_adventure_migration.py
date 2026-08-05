import json
import sqlite3
from pathlib import Path

from alembic import command
from alembic.config import Config

from app.core.config import get_settings


def _outfit_manifests(database_path: Path) -> dict[str, dict]:
    with sqlite3.connect(database_path) as connection:
        rows = connection.execute(
            "SELECT code, asset_manifest FROM items WHERE code LIKE 'wardrobe_%'"
        ).fetchall()
    return {code: json.loads(raw) for code, raw in rows}


def test_adventure_migration_creates_tables_and_outfit_bonuses(tmp_path, monkeypatch):
    database_path = tmp_path / "adventure.db"
    monkeypatch.setenv(
        "DATABASE_URL", f"sqlite+aiosqlite:///{database_path.as_posix()}"
    )
    get_settings.cache_clear()
    server_dir = Path(__file__).resolve().parents[2]
    config = Config(str(server_dir / "alembic.ini"))
    config.set_main_option("script_location", str(server_dir / "alembic"))
    try:
        command.upgrade(config, "head")
        with sqlite3.connect(database_path) as connection:
            tables = {
                row[0]
                for row in connection.execute(
                    "SELECT name FROM sqlite_master WHERE type = 'table'"
                )
            }
        assert {
            "adventure_patrols",
            "user_dungeons",
            "dungeon_runs",
            "user_adventure_items",
            "user_adventure_research",
            "expedition_runs",
            "user_active_expeditions",
            "expedition_party_members",
            "expedition_node_states",
            "expedition_actions",
            "expedition_loot",
            "expedition_content_exposures",
            "plant_adventure_bonds",
            "user_region_progress",
            "plant_region_familiarities",
        } <= tables
        with sqlite3.connect(database_path) as connection:
            dungeon_run_columns = {
                row[1] for row in connection.execute("PRAGMA table_info(dungeon_runs)")
            }
            patrol_columns = {
                row[1]
                for row in connection.execute("PRAGMA table_info(adventure_patrols)")
            }
        assert {"approach_code", "approach_stat", "outcome_code"} <= (
            dungeon_run_columns
        )
        assert {"scene_code", "scene_title", "scene_text"} <= dungeon_run_columns
        assert {"encounter_code", "encounter_title", "encounter_text"} <= (
            patrol_columns
        )
        assert {"reaction_form", "reaction_speaker", "reaction_text"} <= (
            patrol_columns
        )
        manifests = _outfit_manifests(database_path)
        assert manifests["wardrobe_garden_daily"]["adventure_bonus"] == {
            "context": "patrol",
            "stat": "care",
            "amount": 2,
            "label": "순찰 돌봄 +2",
        }
        assert (
            manifests["wardrobe_city_night"]["adventure_bonus"]["context"] == "dungeon"
        )

        command.downgrade(config, "0026_dungeon_scenes")
        with sqlite3.connect(database_path) as connection:
            tables = {
                row[0]
                for row in connection.execute(
                    "SELECT name FROM sqlite_master WHERE type = 'table'"
                )
            }
        assert "expedition_runs" not in tables
        assert "expedition_actions" not in tables
        assert "plant_adventure_bonds" not in tables
        assert "user_region_progress" not in tables
        assert "plant_region_familiarities" not in tables

        command.downgrade(config, "0025_patrol_reactions")
        with sqlite3.connect(database_path) as connection:
            dungeon_run_columns = {
                row[1] for row in connection.execute("PRAGMA table_info(dungeon_runs)")
            }
        assert not {"scene_code", "scene_title", "scene_text"} & dungeon_run_columns
        assert {"approach_code", "approach_stat", "outcome_code"} <= (
            dungeon_run_columns
        )

        command.downgrade(config, "0024_patrol_encounters")
        with sqlite3.connect(database_path) as connection:
            patrol_columns = {
                row[1]
                for row in connection.execute("PRAGMA table_info(adventure_patrols)")
            }
        assert not {"reaction_form", "reaction_speaker", "reaction_text"} & (
            patrol_columns
        )
        assert {"encounter_code", "encounter_title", "encounter_text"} <= (
            patrol_columns
        )

        command.downgrade(config, "0023_dungeon_approaches")
        with sqlite3.connect(database_path) as connection:
            patrol_columns = {
                row[1]
                for row in connection.execute("PRAGMA table_info(adventure_patrols)")
            }
        assert not {"encounter_code", "encounter_title", "encounter_text"} & (
            patrol_columns
        )

        command.downgrade(config, "0022_adventure_research")
        with sqlite3.connect(database_path) as connection:
            dungeon_run_columns = {
                row[1] for row in connection.execute("PRAGMA table_info(dungeon_runs)")
            }
            tables = {
                row[0]
                for row in connection.execute(
                    "SELECT name FROM sqlite_master WHERE type = 'table'"
                )
            }
        assert not {"approach_code", "approach_stat", "outcome_code"} & (
            dungeon_run_columns
        )
        assert "user_adventure_research" in tables

        command.downgrade(config, "0021_adventure_loop")
        with sqlite3.connect(database_path) as connection:
            tables = {
                row[0]
                for row in connection.execute(
                    "SELECT name FROM sqlite_master WHERE type = 'table'"
                )
            }
        assert "user_adventure_research" not in tables
        assert "user_adventure_items" in tables

        command.downgrade(config, "0020_complete_wardrobe")
        downgraded = _outfit_manifests(database_path)
        assert all(
            "adventure_bonus" not in manifest for manifest in downgraded.values()
        )
    finally:
        get_settings.cache_clear()
