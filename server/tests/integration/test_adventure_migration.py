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
        } <= tables
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

        command.downgrade(config, "0020_complete_wardrobe")
        downgraded = _outfit_manifests(database_path)
        assert all(
            "adventure_bonus" not in manifest for manifest in downgraded.values()
        )
    finally:
        get_settings.cache_clear()
