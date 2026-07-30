import json
import sqlite3
from pathlib import Path

from alembic import command
from alembic.config import Config

from app.core.config import get_settings


ORIGINAL_SPECIES = {
    "baby-pot",
    "handsome-pot",
    "pretty-pot",
    "tsundere-pot",
    "zombie-pot",
    "gumiho-pot",
    "ninja-pot",
    "magical-pot",
}
ADDED_SPECIES = {"aloof-pot", "student-pot"}
WARDROBE_CODES = {
    "wardrobe_garden_daily",
    "wardrobe_city_night",
}


def _manifests(database_path: Path) -> dict[str, dict]:
    with sqlite3.connect(database_path) as connection:
        rows = connection.execute(
            """
            SELECT code, asset_manifest
            FROM items
            WHERE code IN ('wardrobe_garden_daily', 'wardrobe_city_night')
            """
        ).fetchall()
    return {code: json.loads(raw_manifest) for code, raw_manifest in rows}


def test_complete_wardrobe_species_migration_updates_both_outfits(
    tmp_path, monkeypatch
):
    database_path = tmp_path / "complete-wardrobe-species.db"
    monkeypatch.setenv(
        "DATABASE_URL", f"sqlite+aiosqlite:///{database_path.as_posix()}"
    )
    get_settings.cache_clear()

    server_dir = Path(__file__).resolve().parents[2]
    config = Config(str(server_dir / "alembic.ini"))
    config.set_main_option("script_location", str(server_dir / "alembic"))

    try:
        command.upgrade(config, "0019_city_night_wardrobe")
        before = _manifests(database_path)
        assert set(before) == WARDROBE_CODES
        for manifest in before.values():
            assert set(manifest["compatible_species"]) == ORIGINAL_SPECIES

        command.upgrade(config, "head")
        after = _manifests(database_path)
        assert set(after) == WARDROBE_CODES
        for code, manifest in after.items():
            assert set(manifest["compatible_species"]) == (
                ORIGINAL_SPECIES | ADDED_SPECIES
            )
            assert manifest["wardrobe_layer_key"] == (
                "garden-daily"
                if code == "wardrobe_garden_daily"
                else "city-night"
            )
            assert manifest["child_safe_species"] == ["baby-pot"]

        command.downgrade(config, "0019_city_night_wardrobe")
        downgraded = _manifests(database_path)
        for manifest in downgraded.values():
            assert set(manifest["compatible_species"]) == ORIGINAL_SPECIES
    finally:
        get_settings.cache_clear()
