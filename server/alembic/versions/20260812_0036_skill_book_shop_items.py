"""마음결 기록서 상점 항목

Revision ID: 0036_skill_book_shop
Revises: 0035_skill_book_ownership
Create Date: 2026-08-12

기록서를 기존 아이템 체계에 넣어 상점에서 산다. 다만 **보유의 단일 원본은
`user_skill_books`**이고 `user_items`는 구매 사실만 남긴다. 품종 해금 아이템이
`user_species_unlocks`를 함께 쓰는 것과 같은 구조다.

상점에 올리는 것은 설계서 7.6의 구매 경로 11종(1등급 7 × 씨앗 40, 2등급 상점 4 ×
씨앗 120)뿐이다. 해금·도전으로만 얻는 책은 상점에 나타나지 않는다.
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op


revision = "0036_skill_book_shop"
down_revision = "0035_skill_book_ownership"
branch_labels = None
depends_on = None


ITEM_TYPES_WITH_BOOKS = (
    "'deco','room_theme','main_character','companion','species_unlock',"
    "'wardrobe','skill_book'"
)
ITEM_TYPES_WITHOUT_BOOKS = (
    "'deco','room_theme','main_character','companion','species_unlock','wardrobe'"
)

# (code, 이름, 등급, 가격, 효과 문장)
SHOP_BOOKS = (
    ("first_breath", "첫 호흡", 1, 40, "전투 시작 시 집중력 +1 (상한 5 유지)"),
    ("leaf_greave", "잎사귀 각반", 1, 40, "마음 지키기 방어량 2 → 3"),
    ("clear_aim", "또렷한 겨냥", 1, 40, "기본 공격 위력 +3"),
    ("short_cheer", "짧은 격려", 1, 40, "전투 1회, 1라운드에 최저 HP 대원 1 회복"),
    ("echo_read", "잔향 읽기", 1, 40, "전투 1회, 다음 라운드 적 의도 1개를 미리 공개"),
    ("bracing", "버티는 자세", 1, 40, "전투 1회, 방어를 고르면 집중력 1 추가 생성"),
    ("final_resolve", "마무리 결심", 1, 40, "적 장벽 20% 이하일 때 기본 공격 위력 +5"),
    (
        "resonance_tuner",
        "마음결 조율기",
        2,
        120,
        "전투 1회, 다음 공격 성장결을 확정 전에 다른 결로 변경",
    ),
    ("focus_knot", "집중의 매듭", 2, 120, "전투 1회, 스킬 사용 후 집중력 1 환급"),
    (
        "first_signal",
        "선제 신호",
        2,
        120,
        "전투 1회, 적 의도 공개 후 1라운드 명령 순서 재배치",
    ),
    ("steady_axis", "흔들리지 않는 축", 2, 120, "적 `all` 공격 피해 −1"),
)


def _items_table() -> sa.Table:
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


def _rows() -> list[dict]:
    return [
        {
            "code": f"skill_book_{code}",
            "type": "skill_book",
            "name": name,
            "description": summary,
            "price_seeds": price,
            "rarity": grade,
            # 구매 처리기가 이 코드로 어떤 기록서를 지급할지 찾는다.
            # `sa.JSON` 컬럼이라 dict를 그대로 넘긴다. 문자열로 미리 직렬화하면
            # 이중 인코딩돼 앱이 dict 대신 문자열을 읽는다.
            "asset_manifest": {"skill_book_code": code},
            "is_active": True,
        }
        for code, name, grade, price, summary in SHOP_BOOKS
    ]


def _replace_item_type_constraint(values: str) -> None:
    with op.batch_alter_table("items") as batch:
        batch.drop_constraint("ck_item_type", type_="check")
        batch.create_check_constraint("ck_item_type", f"type IN ({values})")


def upgrade() -> None:
    _replace_item_type_constraint(ITEM_TYPES_WITH_BOOKS)
    op.bulk_insert(_items_table(), _rows())


def downgrade() -> None:
    bind = op.get_bind()
    items = _items_table()
    codes = tuple(row["code"] for row in _rows())
    item_ids = tuple(
        bind.execute(sa.select(items.c.id).where(items.c.code.in_(codes))).scalars()
    )
    if item_ids:
        user_items = sa.table(
            "user_items",
            sa.column("id", sa.BigInteger),
            sa.column("item_id", sa.BigInteger),
        )
        op.execute(user_items.delete().where(user_items.c.item_id.in_(item_ids)))
        op.execute(items.delete().where(items.c.id.in_(item_ids)))
    _replace_item_type_constraint(ITEM_TYPES_WITHOUT_BOOKS)
