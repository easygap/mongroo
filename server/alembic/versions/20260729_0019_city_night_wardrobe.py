"""두 번째 공용 의상 시티 나이트 추가

Revision ID: 0019_city_night_wardrobe
Revises: 0018_wardrobe_layers
Create Date: 2026-07-29
"""

import sqlalchemy as sa
from alembic import op


revision = "0019_city_night_wardrobe"
down_revision = "0018_wardrobe_layers"
branch_labels = None
depends_on = None


CHARACTER_SPECIES = (
    "baby-pot",
    "handsome-pot",
    "pretty-pot",
    "tsundere-pot",
    "zombie-pot",
    "gumiho-pot",
    "ninja-pot",
    "magical-pot",
)

ITEM_CODE = "wardrobe_city_night"
ITEM_ROW = {
    "code": ITEM_CODE,
    "type": "wardrobe",
    "name": "시티 나이트 셋",
    "description": "차분한 야간 색감과 캐릭터별 실루엣을 살린 두 번째 공용 의상이에요.",
    "price_seeds": 260,
    "rarity": 3,
    "asset_manifest": {
        "asset_key": "wardrobe/city-night",
        "preview_url": "assets/wardrobe/previews/city-night.webp",
        "wardrobe_slot": "outfit",
        "wardrobe_layer_key": "city-night",
        "layer_contract": 2,
        "compatible_species": list(CHARACTER_SPECIES),
        "child_safe_species": ["baby-pot"],
    },
    "is_active": True,
}


def _items_table():
    return sa.table(
        "items",
        sa.column("id", sa.BigInteger),
        sa.column("code", sa.String),
        sa.column("type", sa.String),
        sa.column("name", sa.String),
        sa.column("description", sa.String),
        sa.column("price_seeds", sa.Integer),
        sa.column("rarity", sa.SmallInteger),
        sa.column("asset_manifest", sa.JSON),
        sa.column("is_active", sa.Boolean),
    )


def upgrade() -> None:
    op.bulk_insert(_items_table(), [ITEM_ROW])


def downgrade() -> None:
    bind = op.get_bind()
    items = _items_table()
    item_id = bind.execute(
        sa.select(items.c.id).where(items.c.code == ITEM_CODE)
    ).scalar_one_or_none()
    if item_id is None:
        return

    user_items = sa.table(
        "user_items",
        sa.column("id", sa.BigInteger),
        sa.column("item_id", sa.BigInteger),
    )
    owned_ids = set(
        bind.execute(
            sa.select(user_items.c.id).where(user_items.c.item_id == item_id)
        ).scalars()
    )
    if owned_ids:
        farm_layouts = sa.table(
            "farm_layouts",
            sa.column("user_id", sa.BigInteger),
            sa.column("layout", sa.JSON),
        )
        for row in bind.execute(
            sa.select(farm_layouts.c.user_id, farm_layouts.c.layout)
        ).mappings():
            layout = dict(row["layout"] or {})
            if layout.get("wardrobe_user_item_id") not in owned_ids:
                continue
            layout["wardrobe_user_item_id"] = None
            bind.execute(
                sa.update(farm_layouts)
                .where(farm_layouts.c.user_id == row["user_id"])
                .values(layout=layout)
            )

    bind.execute(sa.delete(user_items).where(user_items.c.item_id == item_id))
    bind.execute(sa.delete(items).where(items.c.id == item_id))
