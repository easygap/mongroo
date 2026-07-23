"""P1 퀘스트, 상점, 컬렉션과 마이팜

Revision ID: 0002_p1_gameplay
Revises: 0001_p0_schema
Create Date: 2026-07-13
"""
from alembic import op
import sqlalchemy as sa


revision = "0002_p1_gameplay"
down_revision = "0001_p0_schema"
branch_labels = None
depends_on = None

BigIntPK = sa.BigInteger().with_variant(sa.Integer(), "sqlite")
BigIntFK = sa.BigInteger().with_variant(sa.Integer(), "sqlite")


def upgrade() -> None:
    if op.get_bind().dialect.name != "sqlite":
        op.create_check_constraint(
            "ck_user_seed_balance_nonnegative", "users", "seed_balance >= 0"
        )
    op.create_table(
        "quests",
        sa.Column("id", BigIntPK, primary_key=True, autoincrement=True),
        sa.Column("code", sa.String(40), nullable=False, unique=True),
        sa.Column("title", sa.String(80), nullable=False),
        sa.Column("description", sa.String(300), nullable=False),
        sa.Column("trigger_rule", sa.String(40), nullable=False, server_default="daily_neutral"),
        sa.Column("category", sa.String(30), nullable=False),
        sa.Column("burden_level", sa.SmallInteger(), nullable=False, server_default="1"),
        sa.Column("estimated_minutes", sa.Integer(), nullable=False),
        sa.Column("safety_tags", sa.JSON(), nullable=False),
        sa.Column("reward_exp", sa.Integer(), nullable=False, server_default="20"),
        sa.Column("reward_seeds", sa.Integer(), nullable=False, server_default="5"),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default="1"),
        sa.CheckConstraint("burden_level BETWEEN 1 AND 3", name="ck_quest_burden"),
        sa.CheckConstraint("estimated_minutes > 0", name="ck_quest_minutes"),
        sa.CheckConstraint("reward_exp >= 0 AND reward_seeds >= 0", name="ck_quest_rewards"),
    )
    op.create_table(
        "user_quests",
        sa.Column("id", BigIntPK, primary_key=True, autoincrement=True),
        sa.Column("user_id", BigIntFK, sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("quest_id", BigIntFK, sa.ForeignKey("quests.id", ondelete="RESTRICT"), nullable=False),
        sa.Column("quest_date", sa.Date(), nullable=False),
        sa.Column("status", sa.String(20), nullable=False, server_default="assigned"),
        sa.Column("completed_at", sa.DateTime(), nullable=True),
        sa.UniqueConstraint("user_id", "quest_date", name="uq_user_quest_day"),
        sa.CheckConstraint("status IN ('assigned','completed','skipped')", name="ck_user_quest_status"),
    )
    op.create_index("ix_user_quests_user", "user_quests", ["user_id"])
    op.create_index("ix_user_quests_today", "user_quests", ["user_id", "quest_date"])

    op.create_table(
        "items",
        sa.Column("id", BigIntPK, primary_key=True, autoincrement=True),
        sa.Column("code", sa.String(40), nullable=False, unique=True),
        sa.Column("type", sa.String(30), nullable=False),
        sa.Column("name", sa.String(80), nullable=False),
        sa.Column("description", sa.String(300), nullable=False, server_default=""),
        sa.Column("price_seeds", sa.Integer(), nullable=False),
        sa.Column("rarity", sa.SmallInteger(), nullable=False, server_default="1"),
        sa.Column("asset_manifest", sa.JSON(), nullable=False),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default="1"),
        sa.CheckConstraint(
            "type IN ('deco','room_theme','main_character','companion','species_unlock')", name="ck_item_type"
        ),
        sa.CheckConstraint("price_seeds >= 0", name="ck_item_price_nonnegative"),
    )
    op.create_table(
        "user_items",
        sa.Column("id", BigIntPK, primary_key=True, autoincrement=True),
        sa.Column("user_id", BigIntFK, sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("item_id", BigIntFK, sa.ForeignKey("items.id", ondelete="RESTRICT"), nullable=False),
        sa.Column("acquired_at", sa.DateTime(), nullable=False),
        sa.UniqueConstraint("user_id", "item_id", name="uq_user_item_catalog"),
    )
    op.create_index("ix_user_items_user", "user_items", ["user_id"])
    op.create_table(
        "farm_layouts",
        sa.Column("user_id", BigIntFK, sa.ForeignKey("users.id", ondelete="CASCADE"), primary_key=True),
        sa.Column("version", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("layout", sa.JSON(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
    )
    op.create_table(
        "user_species_unlocks",
        sa.Column("id", BigIntPK, primary_key=True, autoincrement=True),
        sa.Column("user_id", BigIntFK, sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("species_id", BigIntFK, sa.ForeignKey("plant_species.id", ondelete="RESTRICT"), nullable=False),
        sa.Column("unlocked_at", sa.DateTime(), nullable=False),
        sa.UniqueConstraint("user_id", "species_id", name="uq_user_species_unlock"),
    )
    op.create_index("ix_species_unlocks_user", "user_species_unlocks", ["user_id"])

    quests = sa.table(
        "quests",
        sa.column("code", sa.String), sa.column("title", sa.String),
        sa.column("description", sa.String), sa.column("trigger_rule", sa.String),
        sa.column("category", sa.String), sa.column("burden_level", sa.SmallInteger),
        sa.column("estimated_minutes", sa.Integer), sa.column("safety_tags", sa.JSON),
        sa.column("reward_exp", sa.Integer), sa.column("reward_seeds", sa.Integer),
        sa.column("is_active", sa.Boolean),
    )
    quest_rows = [
        ("QST_NOTICE_THREE", "색·모양·글자 찾기", "지금 있는 곳에서 색, 모양, 글자를 하나씩 찾아 이름을 적어보세요.", "senses", 1, 3, []),
        ("QST_TODAY_COLOR", "오늘을 대표할 색", "색상표나 주변 물건에서 오늘 기분에 어울리는 색을 고르고 이름을 붙여보세요.", "reflection", 1, 3, []),
        ("QST_SIP_COMMA", "음료 세 모금", "물이나 평소 마시는 음료를 준비해 세 모금 마신 뒤 컵을 내려놓으세요.", "rest", 1, 2, []),
        ("QST_WINDOW_HELLO", "창밖 30초 관찰", "창문 너머나 방 안 먼 곳을 30초 보고, 움직이는 것과 멈춰 있는 것을 하나씩 찾아보세요.", "senses", 1, 3, []),
        ("QST_TIDY_THREE", "책상 위 세 물건 정리", "가장 가까운 물건 세 개를 원래 자리나 사용하기 편한 곳으로 옮겨보세요.", "space", 1, 5, []),
        ("QST_ONE_TRUE_SENTENCE", "오늘 상태 한 줄", "‘지금 나는 ___하다’ 문장을 완성해 메모에 남겨보세요.", "reflection", 1, 3, []),
        ("QST_BODY_WEATHER", "몸 상태 빠른 점검", "턱, 어깨, 손 세 곳을 차례로 살펴 편한 곳과 불편한 곳을 확인하세요.", "body", 1, 4, []),
        ("QST_OWN_PACE_WALK", "익숙한 길 7분", "가능하면 안전하고 익숙한 곳을 7분 걸어보세요. 밖이 어렵다면 실내에서 이동하거나 앉은 채 발을 번갈아 움직여도 됩니다.", "movement", 2, 7, ["outdoor_optional"]),
        ("QST_COLLECT_SOUNDS", "가까운 소리·먼 소리", "지금 들리는 소리 중 가까운 것 두 개와 먼 것 하나를 구분해보세요.", "senses", 1, 3, []),
        ("QST_KEEP_A_SCENE", "오늘의 장면 캡션", "오늘 기억나는 장면 하나를 고르고 사진 설명처럼 20자 안팎으로 적어보세요.", "reflection", 1, 4, []),
        ("QST_LIGHT_HELLO", "화면 밖 시선 휴식", "휴대폰에서 시선을 떼고 방 안의 먼 지점이나 창밖을 30초 바라보세요.", "rest", 1, 3, []),
        ("QST_TOMORROW_SEED", "내일 준비물 꺼내기", "내일 쓸 옷, 가방, 문서 중 하나를 골라 눈에 보이는 곳에 준비해두세요.", "planning", 2, 5, []),
    ]
    op.bulk_insert(quests, [
        {"code": code, "title": title, "description": description,
         "trigger_rule": "daily_neutral", "category": category,
         "burden_level": burden, "estimated_minutes": minutes, "safety_tags": tags,
         "reward_exp": 20, "reward_seeds": 5, "is_active": True}
        for code, title, description, category, burden, minutes, tags in quest_rows
    ])

    items = sa.table(
        "items",
        sa.column("code", sa.String), sa.column("type", sa.String),
        sa.column("name", sa.String), sa.column("description", sa.String),
        sa.column("price_seeds", sa.Integer), sa.column("rarity", sa.SmallInteger),
        sa.column("asset_manifest", sa.JSON), sa.column("is_active", sa.Boolean),
    )
    op.bulk_insert(items, [
        {"code": "deco_cushion_leaf", "type": "deco", "name": "잎사귀 쿠션", "description": "폭신한 초록 잎사귀 모양 쿠션", "price_seeds": 25, "rarity": 1, "asset_manifest": {"asset_key": "deco/cushion_leaf"}, "is_active": True},
        {"code": "deco_lamp_moon", "type": "deco", "name": "달빛 조명", "description": "은은하게 방을 밝혀 주는 달 조명", "price_seeds": 50, "rarity": 2, "asset_manifest": {"asset_key": "deco/lamp_moon"}, "is_active": True},
        {"code": "deco_rug_cloud", "type": "deco", "name": "구름 러그", "description": "발끝이 포근해지는 작은 구름 러그", "price_seeds": 50, "rarity": 2, "asset_manifest": {"asset_key": "deco/rug_cloud"}, "is_active": True},
        {"code": "room_sunny", "type": "room_theme", "name": "햇살 온실", "description": "따뜻한 오후 햇살이 머무는 온실", "price_seeds": 100, "rarity": 2, "asset_manifest": {"asset_key": "room/sunny_greenhouse"}, "is_active": True},
        {"code": "character_mongle", "type": "main_character", "name": "몽글이", "description": "마음을 포근하게 안아 주는 구름 친구", "price_seeds": 100, "rarity": 2, "asset_manifest": {"asset_key": "character/mongle"}, "is_active": True},
        {"code": "companion_dewdrop", "type": "companion", "name": "이슬이", "description": "반짝이는 아침 이슬 요정", "price_seeds": 75, "rarity": 2, "asset_manifest": {"asset_key": "companion/dewdrop"}, "is_active": True},
        {"code": "companion_star", "type": "companion", "name": "별콩이", "description": "작게 반짝이며 곁을 지키는 별 친구", "price_seeds": 150, "rarity": 3, "asset_manifest": {"asset_key": "companion/star"}, "is_active": True},
        {"code": "companion_bunny", "type": "companion", "name": "보송이", "description": "조용히 귀를 기울여 주는 토끼 친구", "price_seeds": 200, "rarity": 4, "asset_manifest": {"asset_key": "companion/bunny"}, "is_active": True},
        {"code": "species_cactus", "type": "species_unlock", "name": "가시니 씨앗", "description": "가시니 품종을 심을 수 있어요", "price_seeds": 100, "rarity": 2, "asset_manifest": {"asset_key": "species/cactus", "species_code": "cactus"}, "is_active": True},
        {"code": "species_sunflower", "type": "species_unlock", "name": "해바라기 씨앗", "description": "해바라기 품종을 심을 수 있어요", "price_seeds": 100, "rarity": 2, "asset_manifest": {"asset_key": "species/sunflower", "species_code": "sunflower"}, "is_active": True},
    ])


def downgrade() -> None:
    for table in (
        "user_species_unlocks", "farm_layouts", "user_items", "items", "user_quests", "quests"
    ):
        op.drop_table(table)
    if op.get_bind().dialect.name != "sqlite":
        op.drop_constraint("ck_user_seed_balance_nonnegative", "users", type_="check")
