"""연결과 저부담 행동 중심의 일일 퀘스트 확장

Revision ID: 0013_quest_expansion
Revises: 0012_first_payoff
Create Date: 2026-07-16
"""

from alembic import op
import sqlalchemy as sa


revision = "0013_quest_expansion"
down_revision = "0012_first_payoff"
branch_labels = None
depends_on = None


QUEST_ROWS = (
    (
        "QST_SHARED_LAUGH",
        "같이 웃었던 말 적기",
        "누군가와 같이 웃었던 말이나 장면 하나를 다섯 단어 안으로 적으세요. 떠오르지 않으면 좋아하는 캐릭터의 대사를 골라도 됩니다.",
        "connection",
        1,
        3,
        ["social_optional"],
    ),
    (
        "QST_RECOMMEND_ONE",
        "추천 목록에 하나 담기",
        "간식, 영상, 장소 중 다른 사람에게 추천하고 싶은 것 하나를 골라 이름만 메모하세요. 지금 보내지 않아도 됩니다.",
        "connection",
        1,
        3,
        ["social_optional"],
    ),
    (
        "QST_QUIET_COMPANY",
        "같은 자리에서 1분 보내기",
        "사람이나 반려동물이 같은 공간에 있다면 대화 없이 1분만 함께 있어 보세요. 혼자라면 좋아하는 캐릭터 사진을 옆에 띄워도 됩니다.",
        "connection",
        1,
        1,
        ["social_optional"],
    ),
    (
        "QST_DONE_STAR",
        "끝낸 일에 별표 하나",
        "오늘 끝낸 일 하나를 메모하고 옆에 별표나 스티커를 붙이세요. 컵 씻기처럼 금방 끝난 일도 넣어도 됩니다.",
        "self_kindness",
        1,
        2,
        [],
    ),
    (
        "QST_PICK_YOUR_FLAVOR",
        "내가 먹고 싶은 맛 고르기",
        "다음에 마실 음료나 먹을 간식에서 원하는 맛 하나를 고르고 이름을 메모하세요. 지금 준비하지 않아도 됩니다.",
        "self_kindness",
        1,
        2,
        [],
    ),
    (
        "QST_DIM_ONE_SETTING",
        "밝기나 소리 2분 낮추기",
        "화면 밝기나 기기 소리 중 하나를 편한 만큼 낮추고 2분 뒤 원래대로 돌려도 됩니다.",
        "rest",
        1,
        2,
        ["audio_optional"],
    ),
    (
        "QST_IMAGINARY_DRINK",
        "가상 음료 이름 짓기",
        "지금 보이는 색 하나와 떠오르는 맛 하나를 합쳐 가상 음료 이름을 지어 메모하세요.",
        "creativity",
        1,
        3,
        [],
    ),
    (
        "QST_NEARBY_ROUND_TRIP",
        "가까운 곳 한 번 왕복",
        "지금 자리에서 안전하게 닿을 지점 하나를 정해 한 번 다녀오세요. 이동이 어렵다면 손이나 시선으로 경로를 따라가도 됩니다.",
        "movement",
        1,
        2,
        ["mobility_adaptable"],
    ),
    (
        "QST_FOUR_BEAT_MOVE",
        "네 박자 움직임",
        "좋아하는 네 박자를 떠올리고 손가락, 어깨, 발끝 중 편한 곳으로 네 번 박자를 표시하세요. 소리를 재생하지 않아도 됩니다.",
        "movement",
        1,
        2,
        ["mobility_adaptable", "audio_optional"],
    ),
)


def upgrade() -> None:
    quests = sa.table(
        "quests",
        sa.column("code", sa.String),
        sa.column("title", sa.String),
        sa.column("description", sa.String),
        sa.column("trigger_rule", sa.String),
        sa.column("category", sa.String),
        sa.column("burden_level", sa.SmallInteger),
        sa.column("estimated_minutes", sa.Integer),
        sa.column("safety_tags", sa.JSON),
        sa.column("reward_exp", sa.Integer),
        sa.column("reward_seeds", sa.Integer),
        sa.column("is_active", sa.Boolean),
    )
    op.bulk_insert(
        quests,
        [
            {
                "code": code,
                "title": title,
                "description": description,
                "trigger_rule": "daily_neutral",
                "category": category,
                "burden_level": burden,
                "estimated_minutes": minutes,
                "safety_tags": tags,
                "reward_exp": 20,
                "reward_seeds": 5,
                "is_active": True,
            }
            for code, title, description, category, burden, minutes, tags in QUEST_ROWS
        ],
    )


def downgrade() -> None:
    quests = sa.table(
        "quests", sa.column("id", sa.BigInteger), sa.column("code", sa.String)
    )
    user_quests = sa.table("user_quests", sa.column("quest_id", sa.BigInteger))
    quest_ids = sa.select(quests.c.id).where(
        quests.c.code.in_(tuple(row[0] for row in QUEST_ROWS))
    )
    op.execute(sa.delete(user_quests).where(user_quests.c.quest_id.in_(quest_ids)))
    op.execute(
        sa.delete(quests).where(quests.c.code.in_(tuple(row[0] for row in QUEST_ROWS)))
    )
