"""애니메이션풍 화분 캐릭터 카탈로그와 기본 캐릭터 지급

Revision ID: 0003_character_catalog
Revises: 0002_p1_gameplay
Create Date: 2026-07-13
"""

from alembic import op
import sqlalchemy as sa


revision = "0003_character_catalog"
down_revision = "0002_p1_gameplay"
branch_labels = None
depends_on = None


CHARACTER_CODES = (
    "character_baby_pot",
    "character_handsome_pot",
    "character_pretty_pot",
    "character_tsundere_pot",
    "character_zombie_pot",
    "character_gumiho_pot",
    "character_ninja_pot",
    "character_magical_pot",
    "character_aloof_pot",
    "character_student_pot",
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
    op.bulk_insert(
        items,
        [
            {
                "code": "character_baby_pot",
                "type": "main_character",
                "name": "아기 화분 뽀또",
                "description": "민트 쪽쪽이와 포근한 싸개잎을 두른 정원의 막내",
                "price_seeds": 0,
                "rarity": 1,
                "asset_manifest": {
                    "asset_key": "characters/baby-pot",
                    "personality": "호기심이 자라는 순수한 막내",
                    "catchphrase": "오늘 마음도 내가 꼭 안아 둘게!",
                    "motion_key": "baby_bounce",
                    "palette": ["#FFE1BC", "#A9D98E", "#FFF8E8"],
                    "accent": "#FF8E79",
                },
                "is_active": True,
            },
            {
                "code": "character_handsome_pot",
                "type": "main_character",
                "name": "냉미남 화분 로제온",
                "description": "말수는 적지만 언제나 먼저 곁을 지키는 무심한 정원 에이스",
                "price_seeds": 50,
                "rarity": 2,
                "asset_manifest": {
                    "asset_key": "characters/handsome-pot",
                    "personality": "차가워 보여도 속은 다정한 냉미남",
                    "catchphrase": "말 안 해도 괜찮아. 여기 있을게.",
                    "motion_key": "prince_flourish",
                    "palette": ["#F2D6C9", "#171820", "#234C3A", "#7A2536"],
                    "accent": "#7A2536",
                },
                "is_active": True,
            },
            {
                "code": "character_pretty_pot",
                "type": "main_character",
                "name": "센터 아이돌 블루미",
                "description": "솔직한 마음을 가장 반짝이는 무대로 만드는 정원의 센터",
                "price_seeds": 50,
                "rarity": 2,
                "asset_manifest": {
                    "asset_key": "characters/pretty-pot",
                    "personality": "자신감 넘치고 다정한 센터 아이돌",
                    "catchphrase": "솔직한 네 마음이 오늘의 하이라이트야!",
                    "motion_key": "pretty_sparkle",
                    "palette": ["#F2D6C9", "#FF8C8C", "#2BAA9B", "#6A3BB8"],
                    "accent": "#E96978",
                },
                "is_active": True,
            },
            {
                "code": "character_tsundere_pot",
                "type": "main_character",
                "name": "선인장 츤데레 가시로",
                "description": "딱히 기다린 건 아니지만 네 자리는 미리 데워 둔 새침한 화분",
                "price_seeds": 80,
                "rarity": 3,
                "asset_manifest": {
                    "asset_key": "characters/tsundere-pot",
                    "personality": "툴툴대면서 은근히 챙기는 단짝",
                    "catchphrase": "딱히 네가 와서 좋은 건 아니거든!",
                    "motion_key": "tsundere_turn_away",
                    "palette": ["#F6C1CC", "#8D6675", "#FFF0E8"],
                    "accent": "#D85473",
                },
                "is_active": True,
            },
            {
                "code": "character_zombie_pot",
                "type": "main_character",
                "name": "좀비 화분 시들잎",
                "description": "새벽에도 비틀비틀 출석하는 끈질긴 생명력의 언데드 화분",
                "price_seeds": 90,
                "rarity": 3,
                "asset_manifest": {
                    "asset_key": "characters/zombie-pot",
                    "personality": "느긋하지만 절대 포기하지 않는 생존왕",
                    "catchphrase": "느려도 괜찮아… 결국 도착하니까.",
                    "motion_key": "zombie_sway",
                    "palette": ["#B9D7A5", "#725E83", "#DDE7C7"],
                    "accent": "#7A4F92",
                },
                "is_active": True,
            },
            {
                "code": "character_gumiho_pot",
                "type": "main_character",
                "name": "구미호 여우비",
                "description": "부채 뒤 미소와 아홉 꼬리로 숨긴 마음까지 알아채는 장난꾸러기",
                "price_seeds": 120,
                "rarity": 4,
                "asset_manifest": {
                    "asset_key": "characters/gumiho-pot",
                    "personality": "발칙한 장난기와 천년의 여유를 품은 여우",
                    "catchphrase": "숨긴 마음은 꼬리 끝에 다 보이거든?",
                    "motion_key": "gumiho_float",
                    "palette": ["#F2D6C9", "#161316", "#E8752A", "#8F1F2F"],
                    "accent": "#C43B2F",
                },
                "is_active": True,
            },
            {
                "code": "character_ninja_pot",
                "type": "main_character",
                "name": "닌자 그림싹",
                "description": "그림자 사이로 슝 나타나 오늘의 작은 임무를 함께하는 화분",
                "price_seeds": 120,
                "rarity": 4,
                "asset_manifest": {
                    "asset_key": "characters/ninja-pot",
                    "personality": "말수는 적고 의리는 깊은 임무 달인",
                    "catchphrase": "오늘의 임무, 조용히 시작하지.",
                    "motion_key": "ninja_snap",
                    "palette": ["#3C405A", "#78C9A3", "#D9E6E2"],
                    "accent": "#38AA7B",
                },
                "is_active": True,
            },
            {
                "code": "character_magical_pot",
                "type": "main_character",
                "name": "마법사 별솔",
                "description": "별자리 망토와 식물 마도서를 펼치는 마법학원 최고의 문제아",
                "price_seeds": 150,
                "rarity": 5,
                "asset_manifest": {
                    "asset_key": "characters/magical-pot",
                    "personality": "영리하고 대담한 마법학원 에이스",
                    "catchphrase": "정답 없는 마음이라면, 새 주문을 만들면 되지!",
                    "motion_key": "magical_hover",
                    "palette": ["#F2D6C9", "#102B55", "#22B8BA", "#D9AC4A"],
                    "accent": "#159DA5",
                },
                "is_active": True,
            },
            {
                "code": "character_aloof_pot",
                "type": "main_character",
                "name": "서리동백 설화",
                "description": "서리 맺힌 동백잎을 우아하게 두른, 눈길 한 번도 특별한 화분",
                "price_seeds": 180,
                "rarity": 5,
                "asset_manifest": {
                    "asset_key": "characters/aloof-pot",
                    "personality": "도도하고 말수는 적지만 은근히 곁을 지키는 동백 아가씨",
                    "catchphrase": "흥, 이 정도 추위에 흔들릴 내가 아니야.",
                    "motion_key": "aloof_glance",
                    "palette": ["#F0D8D2", "#F2F0F6", "#17171D", "#A98BC8"],
                    "accent": "#8067A8",
                },
                "is_active": True,
            },
            {
                "code": "character_student_pot",
                "type": "main_character",
                "name": "학생회장 하루",
                "description": "반듯한 교복 차림으로 오늘의 계획을 야무지게 챙기는 학생회장 화분",
                "price_seeds": 130,
                "rarity": 4,
                "asset_manifest": {
                    "asset_key": "characters/student-pot",
                    "personality": "꼼꼼하고 책임감 넘치지만 웃을 때는 한없이 다정한 학생회장",
                    "catchphrase": "오늘 할 일은 작게 나누면 금방 끝나.",
                    "motion_key": "student_adjust",
                    "palette": ["#F2D6C9", "#1F304F", "#365C3D", "#9B8A7A"],
                    "accent": "#365C3D",
                },
                "is_active": True,
            },
        ],
    )

    # 0003 이전 가입자도 새 가입자와 같은 무료 스타터를 갖도록 한 번만 지급한다.
    users = sa.table("users", sa.column("id", sa.BigInteger))
    catalog = sa.table("items", sa.column("id", sa.BigInteger), sa.column("code", sa.String))
    user_items = sa.table(
        "user_items",
        sa.column("user_id", sa.BigInteger),
        sa.column("item_id", sa.BigInteger),
        sa.column("acquired_at", sa.DateTime),
    )
    starter_id = (
        sa.select(catalog.c.id)
        .where(catalog.c.code == "character_baby_pot")
        .scalar_subquery()
    )
    already_owned = sa.exists(
        sa.select(1)
        .select_from(user_items)
        .where(user_items.c.user_id == users.c.id, user_items.c.item_id == starter_id)
    )
    op.execute(
        sa.insert(user_items).from_select(
            ["user_id", "item_id", "acquired_at"],
            sa.select(users.c.id, starter_id, sa.func.current_timestamp()).where(~already_owned),
        )
    )


def downgrade() -> None:
    items = sa.table("items", sa.column("id", sa.BigInteger), sa.column("code", sa.String))
    user_items = sa.table("user_items", sa.column("item_id", sa.BigInteger))
    character_ids = sa.select(items.c.id).where(items.c.code.in_(CHARACTER_CODES))
    op.execute(sa.delete(user_items).where(user_items.c.item_id.in_(character_ids)))
    op.execute(sa.delete(items).where(items.c.code.in_(CHARACTER_CODES)))
