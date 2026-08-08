"""스테이지 진행 기록과 run의 스테이지 번호 추가

Revision ID: 0031_stage_progress
Revises: 0030_ai_job_ownership
Create Date: 2026-08-08
"""

import sqlalchemy as sa
from alembic import op


revision = "0031_stage_progress"
down_revision = "0030_ai_job_ownership"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "user_stage_progress",
        sa.Column(
            "user_id",
            sa.BigInteger(),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            primary_key=True,
        ),
        sa.Column("region_code", sa.String(length=40), primary_key=True),
        sa.Column("stage_no", sa.SmallInteger(), primary_key=True),
        sa.Column("cleared_at", sa.DateTime(), nullable=False),
        sa.Column(
            "clear_count", sa.Integer(), nullable=False, server_default=sa.text("1")
        ),
        sa.Column(
            "story_seen", sa.Boolean(), nullable=False, server_default=sa.false()
        ),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
        sa.CheckConstraint("stage_no BETWEEN 1 AND 8", name="ck_user_stage_no"),
        sa.CheckConstraint("clear_count >= 1", name="ck_user_stage_clear_count"),
    )
    # 스테이지 지도에서 시작한 run만 값을 가진다. 기존 run은 NULL로 남아
    # 구버전 노드 지도 흐름 그대로 끝까지 진행된다.
    op.add_column(
        "expedition_runs", sa.Column("stage_no", sa.SmallInteger(), nullable=True)
    )


def downgrade() -> None:
    op.drop_column("expedition_runs", "stage_no")
    op.drop_table("user_stage_progress")
