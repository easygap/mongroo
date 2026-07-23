import json
import sqlite3
from pathlib import Path

from alembic import command
from alembic.config import Config

from app.core.config import get_settings


def test_pressed_flower_collection_seeds_purchase_and_unlock_items(
    tmp_path, monkeypatch
):
    database_path = tmp_path / "pressed-flower-collection.db"
    monkeypatch.setenv(
        "DATABASE_URL", f"sqlite+aiosqlite:///{database_path.as_posix()}"
    )
    get_settings.cache_clear()
    server_dir = Path(__file__).resolve().parents[2]
    config = Config(str(server_dir / "alembic.ini"))
    config.set_main_option("script_location", str(server_dir / "alembic"))

    codes = tuple(
        row["code"]
        for row in (
            {"code": "deco_books_pressed"},
            {"code": "deco_stool_frog"},
            {"code": "deco_lamp_mushroom"},
            {"code": "deco_radio_strawberry"},
            {"code": "deco_planter_teacup"},
            {"code": "deco_mobile_moon_seed"},
            {"code": "room_pressed_studio"},
        )
    )
    try:
        command.upgrade(config, "head")
        with sqlite3.connect(database_path) as connection:
            rows = connection.execute(
                f"""
                SELECT code, type, price_seeds, asset_manifest
                FROM items
                WHERE code IN ({",".join("?" for _ in codes)})
                ORDER BY code
                """,
                codes,
            ).fetchall()

        assert {row[0] for row in rows} == set(codes)
        by_code = {
            code: {
                "type": item_type,
                "price": price,
                "manifest": json.loads(manifest),
            }
            for code, item_type, price, manifest in rows
        }
        assert sum(row["type"] == "deco" for row in by_code.values()) == 6
        assert all(
            row["manifest"]["collection"] == "pressed_flower_studio"
            for row in by_code.values()
        )
        room = by_code["room_pressed_studio"]
        assert room["price"] == 0
        assert room["manifest"]["acquisition"] == {
            "type": "collection_count",
            "target": 4,
            "label": "아이템 4종을 모으면 해금",
        }
        assert by_code["deco_books_pressed"]["price"] == 30
        assert by_code["deco_mobile_moon_seed"]["price"] == 85

        command.downgrade(config, "0015_growth_visual")
        with sqlite3.connect(database_path) as connection:
            remaining = connection.execute(
                f"SELECT COUNT(*) FROM items WHERE code IN ({','.join('?' for _ in codes)})",
                codes,
            ).fetchone()[0]
        assert remaining == 0
    finally:
        get_settings.cache_clear()
