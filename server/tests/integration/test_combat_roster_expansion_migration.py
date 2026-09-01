import json
import sqlite3
from pathlib import Path

from alembic import command
from alembic.config import Config

from app.api.routers.health import EXPECTED_SCHEMA_REVISION
from app.core.config import get_settings


def test_combat_roster_migration_links_characters_growth_and_existing_owners(
    tmp_path, monkeypatch
):
    database_path = tmp_path / "combat-roster.db"
    monkeypatch.setenv(
        "DATABASE_URL", f"sqlite+aiosqlite:///{database_path.as_posix()}"
    )
    get_settings.cache_clear()

    server_dir = Path(__file__).resolve().parents[2]
    config = Config(str(server_dir / "alembic.ini"))
    config.set_main_option("script_location", str(server_dir / "alembic"))

    try:
        command.upgrade(config, "0031_stage_progress")
        with sqlite3.connect(database_path) as connection:
            user_cursor = connection.execute(
                """
                INSERT INTO users (
                    email, password_hash, nickname, timezone, seed_balance, streak_days,
                    created_at, updated_at
                ) VALUES (?, ?, ?, ?, 0, 0, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
                """,
                ("roster-owner@example.com", "not-used", "성장대 주인", "Asia/Seoul"),
            )
            user_id = user_cursor.lastrowid
            magical_item_id = connection.execute(
                "SELECT id FROM items WHERE code = 'character_magical_pot'"
            ).fetchone()[0]
            connection.execute(
                """
                INSERT INTO user_items (user_id, item_id, acquired_at)
                VALUES (?, ?, CURRENT_TIMESTAMP)
                """,
                (user_id, magical_item_id),
            )

        command.upgrade(config, "head")
        with sqlite3.connect(database_path) as connection:
            species_rows = connection.execute(
                """
                SELECT code, rarity, unlock_price, asset_manifest
                FROM plant_species
                WHERE code LIKE '%-pot'
                ORDER BY unlock_price, code
                """
            ).fetchall()
            premium_rows = connection.execute(
                """
                SELECT code, price_seeds, rarity, asset_manifest
                FROM items
                WHERE code IN ('character_maestro_pot', 'character_nurse_pot')
                ORDER BY price_seeds
                """
            ).fetchall()
            expansion_rows = connection.execute(
                """
                SELECT code, price_seeds, rarity, asset_manifest
                FROM items
                WHERE code IN (
                    'character_restorer_pot',
                    'character_marten_pot',
                    'character_gal_pot'
                )
                ORDER BY price_seeds
                """
            ).fetchall()
            linked_character_manifests = [
                json.loads(row[0])
                for row in connection.execute(
                    """
                    SELECT asset_manifest
                    FROM items
                    WHERE type = 'main_character'
                      AND code LIKE 'character_%_pot'
                    """
                ).fetchall()
            ]
            granted_species = connection.execute(
                """
                SELECT ps.code
                FROM user_species_unlocks AS usu
                JOIN plant_species AS ps ON ps.id = usu.species_id
                WHERE usu.user_id = ?
                """,
                (user_id,),
            ).fetchall()
            revision = connection.execute(
                "SELECT version_num FROM alembic_version"
            ).fetchone()[0]

        # 마이그레이션을 하나 더 붙일 때마다 손으로 고치지 않는다. `head`까지
        # 올린 뒤이므로 헬스체크가 기대하는 그 값이어야 한다.
        assert revision == EXPECTED_SCHEMA_REVISION
        assert len(species_rows) == 15
        assert {row[0] for row in species_rows} >= {"maestro-pot", "nurse-pot"}
        assert all(
            json.loads(row[3])["combat"]["kit_version"] == 8 for row in species_rows
        )
        assert [(row[0], row[1], row[2]) for row in premium_rows] == [
            ("character_maestro_pot", 240, 5),
            ("character_nurse_pot", 280, 5),
        ]
        assert [json.loads(row[3])["base_outfit"]["name"] for row in premium_rows] == [
            "미드나잇 레조넌스",
            "순백 트리아주",
        ]
        assert [(row[0], row[1], row[2]) for row in expansion_rows] == [
            ("character_marten_pot", 170, 4),
            ("character_restorer_pot", 260, 5),
            ("character_gal_pot", 320, 5),
        ]
        expansion_manifests = [json.loads(row[3]) for row in expansion_rows]
        assert [
            manifest["base_outfit"]["name"] for manifest in expansion_manifests
        ] == [
            "잎길 탐험 하네스",
            "블루그레이 복원 워크웨어",
            "코랄 란제리 워크 스트리트",
        ]
        assert all(manifest["asset_version"] == 7 for manifest in expansion_manifests)
        premium_manifests = [json.loads(row[3]) for row in premium_rows]
        assert all(manifest["asset_version"] == 6 for manifest in premium_manifests)
        assert [
            manifest["visual_story"]["shape_language"] for manifest in premium_manifests
        ] == ["sharp_angles", "soft_curves"]
        assert premium_manifests[0]["visual_story"]["hair"] == ("ink_violet_blunt_bob")
        assert premium_manifests[1]["visual_story"]["hair"] == (
            "pearl_champagne_long_wave"
        )
        assert all(
            manifest.get("species_code") for manifest in linked_character_manifests
        )
        assert granted_species == [("magical-pot",)]

        with sqlite3.connect(database_path) as connection:
            magical_species_id = connection.execute(
                "SELECT id FROM plant_species WHERE code = 'magical-pot'"
            ).fetchone()[0]
            connection.execute(
                """
                INSERT INTO plants (
                    user_id, species_id, name, exp, status, planted_at,
                    created_at, updated_at
                ) VALUES (?, ?, '별솔의 씨앗', 0, 'active', CURRENT_TIMESTAMP,
                          CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
                """,
                (user_id, magical_species_id),
            )

        command.downgrade(config, "0031_stage_progress")
        with sqlite3.connect(database_path) as connection:
            remaining_premium = connection.execute(
                """
                SELECT COUNT(*) FROM items
                WHERE code IN ('character_maestro_pot', 'character_nurse_pot')
                """
            ).fetchone()[0]
            magical_manifest = json.loads(
                connection.execute(
                    "SELECT asset_manifest FROM items WHERE code = 'character_magical_pot'"
                ).fetchone()[0]
            )
            retained_species = connection.execute(
                "SELECT COUNT(*) FROM plant_species WHERE code = 'magical-pot'"
            ).fetchone()[0]
            retained_unlock = connection.execute(
                """
                SELECT COUNT(*)
                FROM user_species_unlocks AS usu
                JOIN plant_species AS ps ON ps.id = usu.species_id
                WHERE usu.user_id = ? AND ps.code = 'magical-pot'
                """,
                (user_id,),
            ).fetchone()[0]
            removed_unused_species = connection.execute(
                "SELECT COUNT(*) FROM plant_species WHERE code = 'nurse-pot'"
            ).fetchone()[0]

        assert remaining_premium == 0
        assert "species_code" not in magical_manifest
        assert "growth_asset_namespace" not in magical_manifest
        assert retained_species == 1
        assert retained_unlock == 1
        assert removed_unused_species == 0
    finally:
        get_settings.cache_clear()
