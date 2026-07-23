"""압화 작업실 방과 문구점 소품 컬렉션

Revision ID: 0016_pressed_collection
Revises: 0015_growth_visual
Create Date: 2026-07-16
"""

from alembic import op
import sqlalchemy as sa


revision = "0016_pressed_collection"
down_revision = "0015_growth_visual"
branch_labels = None
depends_on = None


COLLECTION_ROWS = (
    {
        "code": "deco_books_pressed",
        "type": "deco",
        "name": "압화 노트 더미",
        "description": "오늘의 마음을 눌러 말린 꽃처럼 차곡차곡 보관해요.",
        "price_seeds": 30,
        "rarity": 1,
        "asset_manifest": {
            "asset_key": "deco/pressed_flower_books",
            "collection": "pressed_flower_studio",
            "placement": "floor",
        },
        "is_active": True,
    },
    {
        "code": "deco_stool_frog",
        "type": "deco",
        "name": "연못 개구리 스툴",
        "description": "말없이 들어 주는 초록 친구가 방 한쪽을 지켜요.",
        "price_seeds": 40,
        "rarity": 1,
        "asset_manifest": {
            "asset_key": "deco/frog_stool",
            "collection": "pressed_flower_studio",
            "placement": "floor",
        },
        "is_active": True,
    },
    {
        "code": "deco_lamp_mushroom",
        "type": "deco",
        "name": "버섯 독서등",
        "description": "늦은 밤 기록도 눈부시지 않게 밝혀 주는 작은 조명이에요.",
        "price_seeds": 55,
        "rarity": 2,
        "asset_manifest": {
            "asset_key": "deco/mushroom_reading_lamp",
            "collection": "pressed_flower_studio",
            "placement": "floor",
        },
        "is_active": True,
    },
    {
        "code": "deco_radio_strawberry",
        "type": "deco",
        "name": "딸기잎 라디오",
        "description": "방 안의 공기를 산뜻하게 바꾸는 작고 씩씩한 라디오예요.",
        "price_seeds": 60,
        "rarity": 2,
        "asset_manifest": {
            "asset_key": "deco/strawberry_radio",
            "collection": "pressed_flower_studio",
            "placement": "floor",
        },
        "is_active": True,
    },
    {
        "code": "deco_planter_teacup",
        "type": "deco",
        "name": "찻잔 덩굴 화분",
        "description": "쉬어 가는 시간만큼 덩굴이 한 뼘씩 자라요.",
        "price_seeds": 70,
        "rarity": 2,
        "asset_manifest": {
            "asset_key": "deco/teacup_planter",
            "collection": "pressed_flower_studio",
            "placement": "floor",
        },
        "is_active": True,
    },
    {
        "code": "deco_mobile_moon_seed",
        "type": "deco",
        "name": "달씨앗 모빌",
        "description": "서로 다른 씨앗이 천천히 흔들리며 밤의 균형을 맞춰요.",
        "price_seeds": 85,
        "rarity": 3,
        "asset_manifest": {
            "asset_key": "deco/moon_seed_mobile",
            "collection": "pressed_flower_studio",
            "placement": "wall",
        },
        "is_active": True,
    },
    {
        "code": "room_pressed_studio",
        "type": "room_theme",
        "name": "압화 편지 작업실",
        "description": "말로 다 적지 못한 마음까지 꽃잎과 편지 사이에 보관하는 작업실이에요.",
        "price_seeds": 0,
        "rarity": 3,
        "asset_manifest": {
            "asset_key": "room/pressed_flower_studio",
            "collection": "pressed_flower_studio",
            "palette": ["#EFEFEF", "#3B1F06", "#B9EE84"],
            "ambient_motion": "paper_dust",
            "acquisition": {
                "type": "collection_count",
                "target": 4,
                "label": "아이템 4종을 모으면 해금",
            },
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


def upgrade() -> None:
    items = _items_table()
    op.bulk_insert(
        items,
        [
            {key: value for key, value in row.items() if key != "id"}
            for row in COLLECTION_ROWS
        ],
    )


def downgrade() -> None:
    bind = op.get_bind()
    codes = tuple(row["code"] for row in COLLECTION_ROWS)
    items = _items_table()
    item_ids = tuple(
        bind.execute(sa.select(items.c.id).where(items.c.code.in_(codes))).scalars()
    )
    if not item_ids:
        return

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
            changed = False
            if layout.get("room_theme_user_item_id") in owned_ids:
                layout["room_theme_user_item_id"] = None
                changed = True
            decorations = list(layout.get("decorations") or [])
            kept = [
                decoration
                for decoration in decorations
                if decoration.get("user_item_id") not in owned_ids
            ]
            if len(kept) != len(decorations):
                layout["decorations"] = kept
                changed = True
            if changed:
                bind.execute(
                    sa.update(farm_layouts)
                    .where(farm_layouts.c.user_id == row["user_id"])
                    .values(layout=layout)
                )

    bind.execute(sa.delete(user_items).where(user_items.c.item_id.in_(item_ids)))
    bind.execute(sa.delete(items).where(items.c.id.in_(item_ids)))
