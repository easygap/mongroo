import json
import sqlite3
from pathlib import Path

from alembic import command
from alembic.config import Config

from app.core.config import get_settings


def test_first_session_payoff_migration_updates_leaf_cushion_and_downgrades(
    tmp_path, monkeypatch
):
    database_path = tmp_path / "first-session-payoff.db"
    monkeypatch.setenv(
        "DATABASE_URL", f"sqlite+aiosqlite:///{database_path.as_posix()}"
    )
    get_settings.cache_clear()

    server_dir = Path(__file__).resolve().parents[2]
    config = Config(str(server_dir / "alembic.ini"))
    config.set_main_option("script_location", str(server_dir / "alembic"))

    try:
        command.upgrade(config, "0011_content_progression")
        with sqlite3.connect(database_path) as connection:
            original_price, original_manifest_raw = connection.execute(
                """
                SELECT price_seeds, asset_manifest
                FROM items
                WHERE code = 'deco_cushion_leaf'
                """
            ).fetchone()
        original_manifest = json.loads(original_manifest_raw)

        assert original_price == 25
        assert "acquisition" not in original_manifest

        command.upgrade(config, "head")
        with sqlite3.connect(database_path) as connection:
            upgraded_price, upgraded_manifest_raw = connection.execute(
                """
                SELECT price_seeds, asset_manifest
                FROM items
                WHERE code = 'deco_cushion_leaf'
                """
            ).fetchone()
        upgraded_manifest = json.loads(upgraded_manifest_raw)

        assert upgraded_price == 0
        assert {
            key: value
            for key, value in upgraded_manifest.items()
            if key != "acquisition"
        } == original_manifest
        assert upgraded_manifest["acquisition"] == {
            "type": "record_count",
            "target": 1,
            "label": "첫 마음 기록을 남기면 받아요",
        }

        command.downgrade(config, "0011_content_progression")
        with sqlite3.connect(database_path) as connection:
            downgraded_price, downgraded_manifest_raw = connection.execute(
                """
                SELECT price_seeds, asset_manifest
                FROM items
                WHERE code = 'deco_cushion_leaf'
                """
            ).fetchone()

        assert downgraded_price == original_price
        assert json.loads(downgraded_manifest_raw) == original_manifest
    finally:
        get_settings.cache_clear()
