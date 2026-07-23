"""마음결 수확 기념 소품 컬렉션

Revision ID: 0017_mood_resonance
Revises: 0016_pressed_collection
Create Date: 2026-07-16
"""

import sqlalchemy as sa
from alembic import op


revision = "0017_mood_resonance"
down_revision = "0016_pressed_collection"
branch_labels = None
depends_on = None


RESONANCE_ROWS = (
    {
        "code": "deco_resonance_sunny",
        "type": "deco",
        "name": "햇살 씨앗등",
        "description": "환하게 자란 마음의 시간을 작은 씨앗 불빛으로 간직해요.",
        "price_seeds": 0,
        "rarity": 2,
        "asset_manifest": {
            "asset_key": "deco/resonance_sunny",
            "collection": "mood_resonance",
            "placement": "floor",
            "affinity_forms": ["sunny"],
            "reaction_copy": "햇살결이 가까이 오자 씨앗등이 포근하게 반짝여요.",
            "acquisition": {
                "type": "harvest_form",
                "form": "sunny",
                "target": 1,
                "label": "햇살결 식물을 1회 수확하면 받기",
            },
        },
        "is_active": True,
    },
    {
        "code": "deco_resonance_rainy",
        "type": "deco",
        "name": "빗방울 경청 풍경",
        "description": "가라앉은 마음을 서두르지 않고 들어 준 시간을 맑은 울림으로 남겨요.",
        "price_seeds": 0,
        "rarity": 2,
        "asset_manifest": {
            "asset_key": "deco/resonance_rainy",
            "collection": "mood_resonance",
            "placement": "wall",
            "affinity_forms": ["rainy"],
            "reaction_copy": "빗방울결이 머무르면 풍경이 맑고 낮게 울려요.",
            "acquisition": {
                "type": "harvest_form",
                "form": "rainy",
                "target": 1,
                "label": "빗방울결 식물을 1회 수확하면 받기",
            },
        },
        "is_active": True,
    },
    {
        "code": "deco_resonance_ember",
        "type": "deco",
        "name": "불씨 용기등",
        "description": "뜨거웠던 마음이 나를 지킨 힘이었다는 사실을 은은한 불씨로 밝혀요.",
        "price_seeds": 0,
        "rarity": 2,
        "asset_manifest": {
            "asset_key": "deco/resonance_ember",
            "collection": "mood_resonance",
            "placement": "floor",
            "affinity_forms": ["ember"],
            "reaction_copy": "불씨결과 만나면 용기등 안쪽 불빛이 힘차게 일렁여요.",
            "acquisition": {
                "type": "harvest_form",
                "form": "ember",
                "target": 1,
                "label": "불씨결 식물을 1회 수확하면 받기",
            },
        },
        "is_active": True,
    },
    {
        "code": "deco_resonance_moonlit",
        "type": "deco",
        "name": "달그늘 준비등",
        "description": "조심스럽게 앞날을 살핀 마음의 시간을 작은 달빛 창에 담아 둬요.",
        "price_seeds": 0,
        "rarity": 2,
        "asset_manifest": {
            "asset_key": "deco/resonance_moonlit",
            "collection": "mood_resonance",
            "placement": "floor",
            "affinity_forms": ["moonlit"],
            "reaction_copy": "달그늘결 곁에서는 준비등의 작은 창이 차분히 켜져요.",
            "acquisition": {
                "type": "harvest_form",
                "form": "moonlit",
                "target": 1,
                "label": "달그늘결 식물을 1회 수확하면 받기",
            },
        },
        "is_active": True,
    },
    {
        "code": "deco_resonance_sparkling",
        "type": "deco",
        "name": "반짝 프리즘 꽃봉오리",
        "description": "뜻밖의 순간을 만난 마음의 빛을 여러 색으로 펼쳐 보여 줘요.",
        "price_seeds": 0,
        "rarity": 2,
        "asset_manifest": {
            "asset_key": "deco/resonance_sparkling",
            "collection": "mood_resonance",
            "placement": "floor",
            "affinity_forms": ["sparkling"],
            "reaction_copy": "반짝결이 스치면 프리즘 꽃봉오리가 색색의 빛을 흩뿌려요.",
            "acquisition": {
                "type": "harvest_form",
                "form": "sparkling",
                "target": 1,
                "label": "반짝결 식물을 1회 수확하면 받기",
            },
        },
        "is_active": True,
    },
    {
        "code": "deco_resonance_mosaic",
        "type": "deco",
        "name": "마음모아 균형 모빌",
        "description": "서로 다른 마음이 함께 자란 시간을 가볍고 균형 잡힌 움직임으로 기억해요.",
        "price_seeds": 0,
        "rarity": 2,
        "asset_manifest": {
            "asset_key": "deco/resonance_mosaic",
            "collection": "mood_resonance",
            "placement": "wall",
            "affinity_forms": ["mosaic"],
            "reaction_copy": "모아결과 함께하면 서로 다른 조각이 한 박자로 흔들려요.",
            "acquisition": {
                "type": "harvest_form",
                "form": "mosaic",
                "target": 1,
                "label": "모아결 식물을 1회 수확하면 받기",
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
    op.bulk_insert(items, list(RESONANCE_ROWS))


def downgrade() -> None:
    bind = op.get_bind()
    codes = tuple(row["code"] for row in RESONANCE_ROWS)
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
            decorations = list(layout.get("decorations") or [])
            kept = [
                decoration
                for decoration in decorations
                if decoration.get("user_item_id") not in owned_ids
            ]
            if len(kept) == len(decorations):
                continue
            layout["decorations"] = kept
            bind.execute(
                sa.update(farm_layouts)
                .where(farm_layouts.c.user_id == row["user_id"])
                .values(layout=layout)
            )

    bind.execute(sa.delete(user_items).where(user_items.c.item_id.in_(item_ids)))
    bind.execute(sa.delete(items).where(items.c.id.in_(item_ids)))
