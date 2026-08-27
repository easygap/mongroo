import json
import sqlite3
from pathlib import Path

from alembic import command
from alembic.config import Config

from app.core.config import get_settings


def test_room_theme_acquisition_migration_preserves_and_seeds_catalog(
    tmp_path, monkeypatch
):
    database_path = tmp_path / "room-theme-acquisition.db"
    monkeypatch.setenv(
        "DATABASE_URL", f"sqlite+aiosqlite:///{database_path.as_posix()}"
    )
    get_settings.cache_clear()

    server_dir = Path(__file__).resolve().parents[2]
    config = Config(str(server_dir / "alembic.ini"))
    config.set_main_option("script_location", str(server_dir / "alembic"))

    new_codes = (
        "room_moonlit",
        "room_sakura",
        "room_fox_shrine",
        "room_magic_atelier",
        "room_cloud_cafe",
    )
    try:
        command.upgrade(config, "0005_mood_edit_version")
        with sqlite3.connect(database_path) as connection:
            sunny_before = json.loads(
                connection.execute(
                    "SELECT asset_manifest FROM items WHERE code = 'room_sunny'"
                ).fetchone()[0]
            )

        command.upgrade(config, "head")
        with sqlite3.connect(database_path) as connection:
            rows = connection.execute(
                """
                SELECT code, name, type, price_seeds, asset_manifest
                FROM items
                WHERE code IN (?, ?, ?, ?, ?)
                ORDER BY code
                """,
                new_codes,
            ).fetchall()
            sunny_after = json.loads(
                connection.execute(
                    "SELECT asset_manifest FROM items WHERE code = 'room_sunny'"
                ).fetchone()[0]
            )

        assert {row[0] for row in rows} == set(new_codes)
        assert {row[0]: row[1] for row in rows} == {
            "room_cloud_cafe": "구름 퐁당 디저트 카페",
            "room_fox_shrine": "여우별 비밀 신사",
            "room_magic_atelier": "별똥별 마법 공방",
            "room_moonlit": "달빛 몽상 온실",
            "room_sakura": "벚꽃 소풍 다락방",
        }
        assert all(row[2] == "room_theme" for row in rows)
        assert all(row[3] == 0 for row in rows)
        manifests = {code: json.loads(raw) for code, _name, _type, _price, raw in rows}
        assert {
            code: manifest["asset_key"] for code, manifest in manifests.items()
        } == {
            "room_moonlit": "room/moonlit_dream",
            "room_sakura": "room/sakura_loft",
            "room_fox_shrine": "room/fox_star_shrine",
            "room_magic_atelier": "room/magic_atelier",
            "room_cloud_cafe": "room/cloud_cafe",
        }
        # 0039가 `일일 퀘스트`를 앱이 쓰는 말로 바꾼다. 판정 키는 그대로다.
        assert manifests["room_moonlit"]["acquisition"] == {
            "type": "quest_count",
            "target": 3,
            "label": "작은 행동 3회 완료",
        }
        assert manifests["room_sakura"]["acquisition"] == {
            "type": "record_count",
            "target": 7,
            "label": "마음을 기록한 날 누적 7일",
        }
        assert manifests["room_fox_shrine"]["acquisition"] == {
            "type": "own_item",
            "item_code": "character_gumiho_pot",
            "label": "구미호 여우비를 만나면 해금",
        }
        assert (
            manifests["room_magic_atelier"]["acquisition"]["type"] == "collection_count"
        )
        assert manifests["room_cloud_cafe"]["acquisition"]["target"] == 10

        assert sunny_after["asset_key"] == sunny_before["asset_key"]
        assert {
            key: value for key, value in sunny_after.items() if key != "acquisition"
        } == sunny_before
        assert sunny_after["acquisition"] == {
            "type": "purchase",
            "label": "씨앗 100개로 구매",
        }

        with sqlite3.connect(database_path) as connection:
            user_cursor = connection.execute(
                """
                INSERT INTO users (
                    email, password_hash, nickname, timezone, seed_balance, streak_days,
                    created_at, updated_at
                ) VALUES (?, ?, ?, ?, 0, 0, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
                """,
                ("room-owner@example.com", "not-used", "방 소유자", "Asia/Seoul"),
            )
            user_id = user_cursor.lastrowid
            room_id = connection.execute(
                "SELECT id FROM items WHERE code = 'room_moonlit'"
            ).fetchone()[0]
            user_item_cursor = connection.execute(
                """
                INSERT INTO user_items (user_id, item_id, acquired_at)
                VALUES (?, ?, CURRENT_TIMESTAMP)
                """,
                (user_id, room_id),
            )
            user_item_id = user_item_cursor.lastrowid
            connection.execute(
                """
                INSERT INTO farm_layouts (user_id, version, layout, updated_at)
                VALUES (?, 1, ?, CURRENT_TIMESTAMP)
                """,
                (
                    user_id,
                    json.dumps(
                        {
                            "room_theme_user_item_id": user_item_id,
                            "main_character_user_item_id": None,
                            "companion_user_item_ids": [],
                            "decorations": [],
                        }
                    ),
                ),
            )

        command.downgrade(config, "0005_mood_edit_version")
        with sqlite3.connect(database_path) as connection:
            remaining = connection.execute(
                "SELECT COUNT(*) FROM items WHERE code IN (?, ?, ?, ?, ?)",
                new_codes,
            ).fetchone()[0]
            sunny_downgraded = json.loads(
                connection.execute(
                    "SELECT asset_manifest FROM items WHERE code = 'room_sunny'"
                ).fetchone()[0]
            )
            downgraded_layout = json.loads(
                connection.execute(
                    "SELECT layout FROM farm_layouts WHERE user_id = ?", (user_id,)
                ).fetchone()[0]
            )
        assert remaining == 0
        assert sunny_downgraded == sunny_before
        assert downgraded_layout["room_theme_user_item_id"] is None
    finally:
        get_settings.cache_clear()
