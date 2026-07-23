import json
import sqlite3
from pathlib import Path

from alembic import command
from alembic.config import Config

from app.core.config import get_settings


def test_mood_resonance_relics_have_equal_harvest_unlock_rules(tmp_path, monkeypatch):
    database_path = tmp_path / "mood-resonance-relics.db"
    monkeypatch.setenv(
        "DATABASE_URL", f"sqlite+aiosqlite:///{database_path.as_posix()}"
    )
    get_settings.cache_clear()
    server_dir = Path(__file__).resolve().parents[2]
    config = Config(str(server_dir / "alembic.ini"))
    config.set_main_option("script_location", str(server_dir / "alembic"))

    expected = {
        "sunny": ("deco_resonance_sunny", "햇살 씨앗등"),
        "rainy": ("deco_resonance_rainy", "빗방울 경청 풍경"),
        "ember": ("deco_resonance_ember", "불씨 용기등"),
        "moonlit": ("deco_resonance_moonlit", "달그늘 준비등"),
        "sparkling": ("deco_resonance_sparkling", "반짝 프리즘 꽃봉오리"),
        "mosaic": ("deco_resonance_mosaic", "마음모아 균형 모빌"),
    }
    codes = tuple(code for code, _name in expected.values())
    try:
        command.upgrade(config, "head")
        with sqlite3.connect(database_path) as connection:
            rows = connection.execute(
                f"""
                SELECT code, name, type, price_seeds, rarity, asset_manifest
                FROM items
                WHERE code IN ({",".join("?" for _ in codes)})
                ORDER BY code
                """,
                codes,
            ).fetchall()

        assert len(rows) == 6
        assert {row[0] for row in rows} == set(codes)
        for code, name, item_type, price, rarity, raw_manifest in rows:
            manifest = json.loads(raw_manifest)
            acquisition = manifest["acquisition"]
            form = acquisition["form"]

            assert (code, name) == expected[form]
            assert item_type == "deco"
            assert price == 0
            assert rarity == 2
            assert manifest["asset_key"] == f"deco/resonance_{form}"
            assert manifest["collection"] == "mood_resonance"
            assert manifest["affinity_forms"] == [form]
            assert isinstance(manifest["reaction_copy"], str)
            assert manifest["reaction_copy"].strip()
            assert acquisition["type"] == "harvest_form"
            assert acquisition["target"] == 1
            # 어떤 마음결도 성장 속도나 재화 우위를 주지 않는다.
            assert not {
                "growth_bonus",
                "growth_speed_bonus",
                "reward_bonus",
                "seed_bonus",
            }.intersection(manifest)

        command.downgrade(config, "0016_pressed_collection")
        with sqlite3.connect(database_path) as connection:
            remaining = connection.execute(
                f"SELECT COUNT(*) FROM items WHERE code IN ({','.join('?' for _ in codes)})",
                codes,
            ).fetchone()[0]
        assert remaining == 0
    finally:
        get_settings.cache_clear()
