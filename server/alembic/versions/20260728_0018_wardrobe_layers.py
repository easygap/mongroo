"""캐릭터 의상 레이어와 첫 공용 의상 추가

Revision ID: 0018_wardrobe_layers
Revises: 0017_mood_resonance
Create Date: 2026-07-28
"""

import sqlalchemy as sa
from alembic import op


revision = "0018_wardrobe_layers"
down_revision = "0017_mood_resonance"
branch_labels = None
depends_on = None


# 무착의형 base/ 시트와 자세가 맞는 의상 시트를 모두 갖춘 종만 넣는다.
# 나머지는 계약(design-system/concepts/wardrobe-v1/README.md)을 만족하는
# 에셋이 빌드되는 대로 후속 마이그레이션에서 추가한다.  없는 에셋을 미리
# 열어 두면 상점에서 살 수는 있는데 입히면 아무것도 바뀌지 않는다.
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

WARDROBE_ROWS = (
    {
        "code": "wardrobe_garden_daily",
        "type": "wardrobe",
        "name": "정원 데일리 셋",
        "description": "장식은 덜고 캐릭터의 표정과 움직임이 잘 보이게 다듬은 공용 데일리 의상이에요.",
        "price_seeds": 180,
        "rarity": 2,
        "asset_manifest": {
            "asset_key": "wardrobe/garden-daily",
            "preview_url": "assets/wardrobe/previews/garden-daily.webp",
            "wardrobe_slot": "outfit",
            "wardrobe_layer_key": "garden-daily",
            "layer_contract": 2,
            "compatible_species": list(CHARACTER_SPECIES),
            "child_safe_species": ["baby-pot"],
        },
        "is_active": True,
    },
)


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


def _replace_item_type_constraint(values: str) -> None:
    with op.batch_alter_table("items") as batch:
        batch.drop_constraint("ck_item_type", type_="check")
        batch.create_check_constraint("ck_item_type", f"type IN ({values})")


def upgrade() -> None:
    _replace_item_type_constraint(
        "'deco','room_theme','main_character','companion','species_unlock','wardrobe'"
    )
    op.bulk_insert(_items_table(), list(WARDROBE_ROWS))


def downgrade() -> None:
    bind = op.get_bind()
    items = _items_table()
    codes = tuple(row["code"] for row in WARDROBE_ROWS)
    item_ids = tuple(
        bind.execute(sa.select(items.c.id).where(items.c.code.in_(codes))).scalars()
    )
    if item_ids:
        user_items = sa.table(
            "user_items",
            sa.column("id", sa.BigInteger),
            sa.column("item_id", sa.BigInteger),
        )
        owned_ids = set(
            bind.execute(
                sa.select(user_items.c.id).where(user_items.c.item_id.in_(item_ids))
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
        bind.execute(sa.delete(user_items).where(user_items.c.item_id.in_(item_ids)))
        bind.execute(sa.delete(items).where(items.c.id.in_(item_ids)))

    _replace_item_type_constraint(
        "'deco','room_theme','main_character','companion','species_unlock'"
    )
