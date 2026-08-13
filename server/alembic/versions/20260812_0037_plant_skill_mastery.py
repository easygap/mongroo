"""캐릭터별 스킬 숙련 기록

Revision ID: 0037_plant_skill_mastery
Revises: 0036_skill_book_shop
Create Date: 2026-08-12

숙련은 성능을 바꾸지 않는 기록이다(설계서 11.6). 회상 문장을 여는 용도이면서,
`마음 지키기 누적 30회` 같은 기록서 해금 조건의 근거로도 함께 쓴다. 조건마다
카운터를 새로 만들지 않으려고 이미 남기는 기록을 읽는 구조다.
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import mysql


revision = "0037_plant_skill_mastery"
down_revision = "0036_skill_book_shop"
branch_labels = None
depends_on = None


PreciseDateTime = sa.DateTime().with_variant(mysql.DATETIME(fsp=6), "mysql")
BigIntPK = sa.BigInteger().with_variant(sa.Integer(), "sqlite")


def upgrade() -> None:
    op.create_table(
        "plant_skill_mastery",
        sa.Column(
            "plant_id",
            BigIntPK,
            sa.ForeignKey("plants.id", ondelete="CASCADE"),
            primary_key=True,
            nullable=False,
        ),
        sa.Column("skill_code", sa.String(48), primary_key=True, nullable=False),
        sa.Column("use_count", sa.Integer, nullable=False, server_default="0"),
        sa.Column("mastery_level", sa.SmallInteger, nullable=False, server_default="0"),
        sa.Column("updated_at", PreciseDateTime, nullable=False),
    )
    # 해금 조건은 계정 전체의 같은 스킬 사용 횟수를 더해서 본다.
    op.create_index(
        "ix_plant_skill_mastery_skill", "plant_skill_mastery", ["skill_code"]
    )


def downgrade() -> None:
    op.drop_index("ix_plant_skill_mastery_skill", table_name="plant_skill_mastery")
    op.drop_table("plant_skill_mastery")
