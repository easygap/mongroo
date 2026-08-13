"""마음결 기록서 소유와 캐릭터별 장착 프리셋

Revision ID: 0035_skill_book_ownership
Revises: 0034_character_expansion_v7
Create Date: 2026-08-12

소유(계정이 무엇을 가졌나)와 장착(어느 캐릭터의 어느 프리셋에 넣었나)을 서로 다른
테이블로 나눈다. 보유해도 자동 장착하지 않는다는 계약을 스키마가 먼저 지킨다.
기록서 카탈로그는 콘텐츠 코드에 있으므로 여기서는 code 문자열만 남긴다.
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import mysql


revision = "0035_skill_book_ownership"
down_revision = "0034_character_expansion_v7"
branch_labels = None
depends_on = None


PreciseDateTime = sa.DateTime().with_variant(mysql.DATETIME(fsp=6), "mysql")
BigIntPK = sa.BigInteger().with_variant(sa.Integer(), "sqlite")


def upgrade() -> None:
    op.create_table(
        "user_skill_books",
        sa.Column("id", BigIntPK, primary_key=True, autoincrement=True),
        sa.Column(
            "user_id",
            BigIntPK,
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("skill_book_code", sa.String(48), nullable=False),
        sa.Column("acquired_at", PreciseDateTime, nullable=False),
        sa.Column("acquire_source", sa.String(24), nullable=False),
        sa.Column("source_ref", sa.String(64), nullable=True),
        # 같은 코드는 계정에 한 장뿐이다. 중복 획득은 여기서 먼저 막힌다.
        sa.UniqueConstraint("user_id", "skill_book_code", name="uq_user_skill_book"),
    )
    op.create_index("ix_user_skill_books_user_id", "user_skill_books", ["user_id"])
    op.create_index(
        "ix_user_skill_books_user", "user_skill_books", ["user_id", "acquired_at"]
    )

    op.create_table(
        "plant_skill_loadouts",
        sa.Column(
            "plant_id",
            BigIntPK,
            sa.ForeignKey("plants.id", ondelete="CASCADE"),
            primary_key=True,
            nullable=False,
        ),
        sa.Column("preset_code", sa.String(16), primary_key=True, nullable=False),
        sa.Column(
            "user_id",
            BigIntPK,
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("slot_b1_code", sa.String(48), nullable=True),
        sa.Column("slot_b2_code", sa.String(48), nullable=True),
        sa.Column("revision", sa.Integer, nullable=False, server_default="1"),
        sa.Column("updated_at", PreciseDateTime, nullable=False),
    )
    op.create_index(
        "ix_plant_skill_loadouts_user", "plant_skill_loadouts", ["user_id"]
    )


def downgrade() -> None:
    op.drop_index("ix_plant_skill_loadouts_user", table_name="plant_skill_loadouts")
    op.drop_table("plant_skill_loadouts")
    op.drop_index("ix_user_skill_books_user", table_name="user_skill_books")
    op.drop_index("ix_user_skill_books_user_id", table_name="user_skill_books")
    op.drop_table("user_skill_books")
