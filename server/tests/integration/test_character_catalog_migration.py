import json
import sqlite3
from pathlib import Path

from alembic import command
from alembic.config import Config

from app.core.config import get_settings


def test_character_catalog_migration_seeds_and_grants_existing_users(
    tmp_path, monkeypatch
):
    database_path = tmp_path / "character-catalog.db"
    monkeypatch.setenv(
        "DATABASE_URL", f"sqlite+aiosqlite:///{database_path.as_posix()}"
    )
    get_settings.cache_clear()

    server_dir = Path(__file__).resolve().parents[2]
    config = Config(str(server_dir / "alembic.ini"))
    config.set_main_option("script_location", str(server_dir / "alembic"))

    try:
        command.upgrade(config, "0002_p1_gameplay")
        with sqlite3.connect(database_path) as connection:
            connection.execute(
                """
                INSERT INTO users (
                    email, password_hash, nickname, timezone, seed_balance, streak_days,
                    created_at, updated_at
                ) VALUES (?, ?, ?, ?, 0, 0, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
                """,
                ("before-0003@example.com", "not-used", "기존 사용자", "Asia/Seoul"),
            )

        command.upgrade(config, "0003_character_catalog")
        with sqlite3.connect(database_path) as connection:
            rows = connection.execute(
                """
                SELECT code, name, price_seeds, rarity, asset_manifest
                FROM items
                WHERE code IN (
                    'character_baby_pot', 'character_handsome_pot',
                    'character_pretty_pot', 'character_tsundere_pot',
                    'character_zombie_pot', 'character_gumiho_pot',
                    'character_ninja_pot', 'character_magical_pot',
                    'character_aloof_pot', 'character_student_pot'
                )
                ORDER BY id
                """
            ).fetchall()
            grants = connection.execute(
                """
                SELECT COUNT(*)
                FROM user_items AS ui
                JOIN items AS i ON i.id = ui.item_id
                WHERE i.code = 'character_baby_pot'
                """
            ).fetchone()[0]
            granted_character_codes = [
                row[0]
                for row in connection.execute(
                    """
                    SELECT i.code
                    FROM user_items AS ui
                    JOIN items AS i ON i.id = ui.item_id
                    WHERE i.type = 'main_character'
                    ORDER BY i.id
                    """
                ).fetchall()
            ]

        assert [row[1] for row in rows] == [
            "아기 화분 뽀또",
            "냉미남 화분 로제온",
            "센터 아이돌 블루미",
            "선인장 츤데레 가시로",
            "좀비 화분 시들잎",
            "구미호 여우비",
            "닌자 그림싹",
            "마법사 별솔",
            "서리동백 설화",
            "학생회장 하루",
        ]
        assert [row[2] for row in rows] == [0, 50, 50, 80, 90, 120, 120, 150, 180, 130]
        assert [row[3] for row in rows] == [1, 2, 2, 3, 3, 4, 4, 5, 5, 4]
        assert [json.loads(row[4])["motion_key"] for row in rows] == [
            "baby_bounce",
            "prince_flourish",
            "pretty_sparkle",
            "tsundere_turn_away",
            "zombie_sway",
            "gumiho_float",
            "ninja_snap",
            "magical_hover",
            "aloof_glance",
            "student_adjust",
        ]
        for code, _name, _price, _rarity, manifest_json in rows:
            manifest = json.loads(manifest_json)
            slug = code.removeprefix("character_").replace("_", "-")
            assert manifest["asset_key"] == f"characters/{slug}"
            assert manifest["personality"]
            assert manifest["catchphrase"]
            assert manifest["motion_key"]
            assert 3 <= len(manifest["palette"]) <= 4
            assert manifest["accent"].startswith("#")
        assert grants == 1
        assert granted_character_codes == ["character_baby_pot"]

        command.downgrade(config, "0002_p1_gameplay")
        with sqlite3.connect(database_path) as connection:
            remaining = connection.execute(
                "SELECT COUNT(*) FROM items WHERE code LIKE 'character_%_pot'"
            ).fetchone()[0]
            assert remaining == 0
    finally:
        get_settings.cache_clear()
