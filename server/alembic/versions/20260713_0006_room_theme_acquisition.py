"""방 테마 획득 경로 카탈로그 확장

Revision ID: 0006_room_acquisition
Revises: 0005_mood_edit_version
Create Date: 2026-07-13
"""

from alembic import op
import sqlalchemy as sa


revision = "0006_room_acquisition"
down_revision = "0005_mood_edit_version"
branch_labels = None
depends_on = None


ROOM_THEME_ROWS = (
    {
        "code": "room_moonlit",
        "type": "room_theme",
        "name": "달빛 몽상 온실",
        "description": "반짝이는 달빛과 파란 나비가 쉬어 가는 조용한 밤 정원",
        "price_seeds": 0,
        "rarity": 2,
        "asset_manifest": {
            "asset_key": "room/moonlit_dream",
            "palette": ["#202B5B", "#7E8FEA", "#D9D7FF"],
            "ambient_motion": "moon_motes",
            "acquisition": {
                "type": "quest_count",
                "target": 3,
                "label": "일일 퀘스트 3회 완료",
            },
        },
        "is_active": True,
    },
    {
        "code": "room_sakura",
        "type": "room_theme",
        "name": "벚꽃 소풍 다락방",
        "description": "벚꽃잎과 소풍 매트 사이로 봄바람이 머무는 방",
        "price_seeds": 0,
        "rarity": 3,
        "asset_manifest": {
            "asset_key": "room/sakura_loft",
            "palette": ["#FFD5E3", "#FFF1E8", "#AFCF9A"],
            "ambient_motion": "sakura_drift",
            "acquisition": {
                "type": "streak",
                "target": 7,
                "label": "마음 기록 7일 연속 달성",
            },
        },
        "is_active": True,
    },
    {
        "code": "room_fox_shrine",
        "type": "room_theme",
        "name": "여우별 비밀 신사",
        "description": "여우비의 꼬리불과 작은 소원 방울이 빛나는 달밤 신사",
        "price_seeds": 0,
        "rarity": 4,
        "asset_manifest": {
            "asset_key": "room/fox_star_shrine",
            "palette": ["#5A235F", "#E65878", "#F8C76A"],
            "ambient_motion": "fox_fire_orbit",
            "acquisition": {
                "type": "own_item",
                "item_code": "character_gumiho_pot",
                "label": "구미호 여우비를 만나면 해금",
            },
        },
        "is_active": True,
    },
    {
        "code": "room_magic_atelier",
        "type": "room_theme",
        "name": "별똥별 마법 공방",
        "description": "마음의 색을 조제하는 물약과 살아 움직이는 별자리 책이 가득한 공방",
        "price_seeds": 0,
        "rarity": 4,
        "asset_manifest": {
            "asset_key": "room/magic_atelier",
            "palette": ["#49367A", "#A77CE4", "#65D8C7"],
            "ambient_motion": "potion_sparkles",
            "acquisition": {
                "type": "collection_count",
                "target": 5,
                "label": "아이템 5종 수집",
            },
        },
        "is_active": True,
    },
    {
        "code": "room_cloud_cafe",
        "type": "room_theme",
        "name": "구름 퐁당 디저트 카페",
        "description": "말랑한 구름 의자와 따뜻한 라떼 향이 반겨 주는 하늘 카페",
        "price_seeds": 0,
        "rarity": 5,
        "asset_manifest": {
            "asset_key": "room/cloud_cafe",
            "palette": ["#CBE9FF", "#FFF4D6", "#D8C5F2"],
            "ambient_motion": "cloud_steam",
            "acquisition": {
                "type": "quest_count",
                "target": 10,
                "label": "일일 퀘스트 10회 완료",
            },
        },
        "is_active": True,
    },
)


def _set_sunny_acquisition(*, remove: bool = False) -> None:
    bind = op.get_bind()
    items = sa.table(
        "items",
        sa.column("code", sa.String),
        sa.column("price_seeds", sa.Integer),
        sa.column("asset_manifest", sa.JSON),
    )
    row = bind.execute(
        sa.select(items.c.price_seeds, items.c.asset_manifest).where(
            items.c.code == "room_sunny"
        )
    ).mappings().first()
    if row is None:
        return
    manifest = dict(row["asset_manifest"] or {})
    if remove:
        manifest.pop("acquisition", None)
    else:
        manifest["acquisition"] = {
            "type": "purchase",
            "label": f"씨앗 {row['price_seeds']}개로 구매",
        }
    bind.execute(
        sa.update(items)
        .where(items.c.code == "room_sunny")
        .values(asset_manifest=manifest)
    )


def upgrade() -> None:
    items = sa.table(
        "items",
        sa.column("code", sa.String),
        sa.column("type", sa.String),
        sa.column("name", sa.String),
        sa.column("description", sa.String),
        sa.column("price_seeds", sa.Integer),
        sa.column("rarity", sa.SmallInteger),
        sa.column("asset_manifest", sa.JSON),
        sa.column("is_active", sa.Boolean),
    )
    op.bulk_insert(items, list(ROOM_THEME_ROWS))
    _set_sunny_acquisition()


def downgrade() -> None:
    bind = op.get_bind()
    new_codes = tuple(row["code"] for row in ROOM_THEME_ROWS)
    items = sa.table(
        "items",
        sa.column("id", sa.BigInteger),
        sa.column("code", sa.String),
    )
    user_items = sa.table(
        "user_items",
        sa.column("id", sa.BigInteger),
        sa.column("user_id", sa.BigInteger),
        sa.column("item_id", sa.BigInteger),
    )
    item_ids = sa.select(items.c.id).where(items.c.code.in_(new_codes))
    affected_user_item_ids = set(
        bind.execute(
            sa.select(user_items.c.id).where(user_items.c.item_id.in_(item_ids))
        ).scalars()
    )
    if affected_user_item_ids:
        farm_layouts = sa.table(
            "farm_layouts",
            sa.column("user_id", sa.BigInteger),
            sa.column("layout", sa.JSON),
        )
        layouts = list(
            bind.execute(
                sa.select(farm_layouts.c.user_id, farm_layouts.c.layout)
            ).mappings()
        )
        for row in layouts:
            layout = dict(row["layout"] or {})
            if layout.get("room_theme_user_item_id") in affected_user_item_ids:
                layout["room_theme_user_item_id"] = None
                bind.execute(
                    sa.update(farm_layouts)
                    .where(farm_layouts.c.user_id == row["user_id"])
                    .values(layout=layout)
                )
    bind.execute(sa.delete(user_items).where(user_items.c.item_id.in_(item_ids)))
    bind.execute(sa.delete(items).where(items.c.code.in_(new_codes)))
    _set_sunny_acquisition(remove=True)
