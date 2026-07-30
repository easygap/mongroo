import json
import sqlite3
from pathlib import Path

from alembic import command
from alembic.config import Config

from app.core.config import get_settings


def test_city_night_wardrobe_migration_keeps_existing_outfit(tmp_path, monkeypatch):
    database_path = tmp_path / "city-night-wardrobe.db"
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
        command.upgrade(config, "0018_wardrobe_layers")
        with sqlite3.connect(database_path) as connection:
            before = connection.execute(
                "SELECT COUNT(*) FROM items WHERE code = 'wardrobe_city_night'"
            ).fetchone()[0]
        assert before == 0

        command.upgrade(config, "0019_city_night_wardrobe")
        with sqlite3.connect(database_path) as connection:
            rows = connection.execute(
                """
                SELECT code, type, name, price_seeds, rarity, asset_manifest
                FROM items
                WHERE code IN ('wardrobe_garden_daily', 'wardrobe_city_night')
                ORDER BY code
                """
            ).fetchall()

        assert [row[0] for row in rows] == [
            "wardrobe_city_night",
            "wardrobe_garden_daily",
        ]
        city_night = rows[0]
        manifest = json.loads(city_night[5])
        assert city_night[1:5] == ("wardrobe", "시티 나이트 셋", 260, 3)
        assert manifest["asset_key"] == "wardrobe/city-night"
        assert manifest["wardrobe_layer_key"] == "city-night"
        assert manifest["layer_contract"] == 2
        assert set(manifest["compatible_species"]) == expected_species
        assert manifest["child_safe_species"] == ["baby-pot"]

        command.downgrade(config, "0018_wardrobe_layers")
        with sqlite3.connect(database_path) as connection:
            remaining = dict(
                connection.execute(
                    """
                    SELECT code, COUNT(*)
                    FROM items
                    WHERE code IN ('wardrobe_garden_daily', 'wardrobe_city_night')
                    GROUP BY code
                    """
                ).fetchall()
            )
        assert remaining == {"wardrobe_garden_daily": 1}
    finally:
        get_settings.cache_clear()
