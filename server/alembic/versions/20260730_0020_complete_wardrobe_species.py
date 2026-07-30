"""마지막 두 캐릭터의 공용 의상 호환성 추가

Revision ID: 0020_complete_wardrobe
Revises: 0019_city_night_wardrobe
Create Date: 2026-07-30
"""

import sqlalchemy as sa
from alembic import op


revision = "0020_complete_wardrobe"
down_revision = "0019_city_night_wardrobe"
branch_labels = None
depends_on = None


WARDROBE_CODES = (
    "wardrobe_garden_daily",
    "wardrobe_city_night",
)
ADDED_SPECIES = (
    "aloof-pot",
    "student-pot",
)


def _items_table():
    return sa.table(
        "items",
        sa.column("id", sa.BigInteger),
        sa.column("code", sa.String),
        sa.column("asset_manifest", sa.JSON),
    )


def _update_compatible_species(*, remove: bool) -> None:
    bind = op.get_bind()
    items = _items_table()
    rows = list(
        bind.execute(
            sa.select(items.c.id, items.c.asset_manifest).where(
                items.c.code.in_(WARDROBE_CODES)
            )
        ).mappings()
    )

    for row in rows:
        manifest = dict(row["asset_manifest"] or {})
        compatible = list(manifest.get("compatible_species") or [])
        if remove:
            compatible = [
                species for species in compatible if species not in ADDED_SPECIES
            ]
        else:
            for species in ADDED_SPECIES:
                if species not in compatible:
                    compatible.append(species)
        manifest["compatible_species"] = compatible
        bind.execute(
            sa.update(items)
            .where(items.c.id == row["id"])
            .values(asset_manifest=manifest)
        )


def upgrade() -> None:
    _update_compatible_species(remove=False)


def downgrade() -> None:
    _update_compatible_species(remove=True)
