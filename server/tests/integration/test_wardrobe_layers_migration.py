import json
import sqlite3
from pathlib import Path

from alembic import command
from alembic.config import Config

from app.core.config import get_settings


def test_wardrobe_layers_migration_seeds_v2_outfit(tmp_path, monkeypatch):
    database_path = tmp_path / "wardrobe-layers.db"
    monkeypatch.setenv(
        "DATABASE_URL", f"sqlite+aiosqlite:///{database_path.as_posix()}"
    )
    get_settings.cache_clear()

    server_dir = Path(__file__).resolve().parents[2]
    config = Config(str(server_dir / "alembic.ini"))
    config.set_main_option("script_location", str(server_dir / "alembic"))

    expected_species = {
        "baby-pot",
        "handsome-pot",
        "pretty-pot",
        "tsundere-pot",
        "zombie-pot",
        "gumiho-pot",
        "ninja-pot",
        "magical-pot",
    }
    try:
        command.upgrade(config, "head")
        with sqlite3.connect(database_path) as connection:
            row = connection.execute(
                """
                SELECT type, name, price_seeds, asset_manifest
                FROM items
                WHERE code = 'wardrobe_garden_daily'
                """
            ).fetchone()

        assert row is not None
        item_type, name, price_seeds, raw_manifest = row
        manifest = json.loads(raw_manifest)
        assert item_type == "wardrobe"
        assert name == "정원 데일리 셋"
        assert price_seeds == 180
        assert manifest["wardrobe_layer_key"] == "garden-daily"
        assert manifest["layer_contract"] == 2
        assert set(manifest["compatible_species"]) == expected_species
        assert manifest["child_safe_species"] == ["baby-pot"]

        command.downgrade(config, "0017_mood_resonance")
        with sqlite3.connect(database_path) as connection:
            remaining = connection.execute(
                "SELECT COUNT(*) FROM items WHERE code = 'wardrobe_garden_daily'"
            ).fetchone()[0]
        assert remaining == 0
    finally:
        get_settings.cache_clear()
