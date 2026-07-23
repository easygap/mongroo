"""품종별 씨앗과 성장 용기 렌더링 계약

Revision ID: 0015_growth_visual
Revises: 0014_student_reward
Create Date: 2026-07-16
"""

from alembic import op
import sqlalchemy as sa


revision = "0015_growth_visual"
down_revision = "0014_student_reward"
branch_labels = None
depends_on = None


GROWTH_IDENTITIES = {
    "basic_sprout": {
        "seed_shape": "heart_speck_seed",
        "vessel_style": "round_terracotta_pot",
        "rarity_effect": "none",
        "asset_namespace": "plants/basic_sprout",
    },
    "cactus": {
        "seed_shape": "spined_star_seed",
        "vessel_style": "ribbed_desert_incubator",
        "rarity_effect": "warm_dust_glint",
        "asset_namespace": "plants/cactus",
    },
    "sunflower": {
        "seed_shape": "striped_sun_seed",
        "vessel_style": "sunbeam_bell_jar",
        "rarity_effect": "soft_sun_motes",
        "asset_namespace": "plants/sunflower",
    },
}


def _species_table():
    return sa.table(
        "plant_species",
        sa.column("code", sa.String),
        sa.column("asset_manifest", sa.JSON),
    )


def upgrade() -> None:
    species = _species_table()
    bind = op.get_bind()
    rows = bind.execute(
        sa.select(species.c.code, species.c.asset_manifest).where(
            species.c.code.in_(GROWTH_IDENTITIES)
        )
    ).mappings()
    for row in rows:
        manifest = dict(row["asset_manifest"] or {})
        manifest["growth"] = GROWTH_IDENTITIES[row["code"]]
        bind.execute(
            species.update()
            .where(species.c.code == row["code"])
            .values(asset_manifest=manifest)
        )


def downgrade() -> None:
    species = _species_table()
    bind = op.get_bind()
    rows = bind.execute(
        sa.select(species.c.code, species.c.asset_manifest).where(
            species.c.code.in_(GROWTH_IDENTITIES)
        )
    ).mappings()
    for row in rows:
        manifest = dict(row["asset_manifest"] or {})
        if manifest.get("growth") == GROWTH_IDENTITIES[row["code"]]:
            manifest.pop("growth")
        bind.execute(
            species.update()
            .where(species.c.code == row["code"])
            .values(asset_manifest=manifest)
        )
