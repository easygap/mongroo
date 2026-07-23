import json
import sqlite3
from pathlib import Path

from alembic import command
from alembic.config import Config

from app.core.config import get_settings


def test_growth_visual_identity_preserves_other_manifest_fields_and_downgrades(
    tmp_path, monkeypatch
):
    database_path = tmp_path / "growth-visual-identity.db"
    monkeypatch.setenv(
        "DATABASE_URL", f"sqlite+aiosqlite:///{database_path.as_posix()}"
    )
    get_settings.cache_clear()
    server_dir = Path(__file__).resolve().parents[2]
    config = Config(str(server_dir / "alembic.ini"))
    config.set_main_option("script_location", str(server_dir / "alembic"))

    try:
        command.upgrade(config, "0014_student_reward")
        with sqlite3.connect(database_path) as connection:
            connection.execute(
                "UPDATE plant_species SET asset_manifest = ? WHERE code = 'cactus'",
                (json.dumps({"legacy_key": "kept"}),),
            )

        command.upgrade(config, "head")
        with sqlite3.connect(database_path) as connection:
            manifests = {
                code: json.loads(raw)
                for code, raw in connection.execute(
                    "SELECT code, asset_manifest FROM plant_species"
                )
            }

        assert manifests["basic_sprout"]["growth"] == {
            "seed_shape": "heart_speck_seed",
            "vessel_style": "round_terracotta_pot",
            "rarity_effect": "none",
            "asset_namespace": "plants/basic_sprout",
        }
        assert manifests["cactus"]["legacy_key"] == "kept"
        assert manifests["cactus"]["growth"]["seed_shape"] == "spined_star_seed"
        assert (
            manifests["cactus"]["growth"]["vessel_style"] == "ribbed_desert_incubator"
        )
        assert manifests["sunflower"]["growth"]["seed_shape"] == "striped_sun_seed"
        assert manifests["sunflower"]["growth"]["vessel_style"] == "sunbeam_bell_jar"

        command.downgrade(config, "0014_student_reward")
        with sqlite3.connect(database_path) as connection:
            downgraded = {
                code: json.loads(raw)
                for code, raw in connection.execute(
                    "SELECT code, asset_manifest FROM plant_species"
                )
            }
        assert "growth" not in downgraded["basic_sprout"]
        assert downgraded["cactus"] == {"legacy_key": "kept"}
        assert "growth" not in downgraded["sunflower"]
    finally:
        get_settings.cache_clear()
