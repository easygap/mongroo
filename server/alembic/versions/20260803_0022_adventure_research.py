"""탐험 표본 연구 진행 상태 추가

Revision ID: 0022_adventure_research
Revises: 0021_adventure_loop
Create Date: 2026-08-03
"""

import sqlalchemy as sa
from alembic import op


revision = "0022_adventure_research"
down_revision = "0021_adventure_loop"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "user_adventure_research",
        sa.Column(
            "id",
            sa.BigInteger().with_variant(sa.Integer(), "sqlite"),
            primary_key=True,
            autoincrement=True,
        ),
        sa.Column(
            "user_id",
            sa.BigInteger(),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("project_code", sa.String(40), nullable=False),
        sa.Column("completed_at", sa.DateTime(), nullable=False),
        sa.UniqueConstraint(
            "user_id", "project_code", name="uq_user_adventure_research"
        ),
    )
    op.create_index(
        "ix_user_adventure_research_user_id",
        "user_adventure_research",
        ["user_id"],
    )


def downgrade() -> None:
    op.drop_index(
        "ix_user_adventure_research_user_id",
        table_name="user_adventure_research",
    )
    op.drop_table("user_adventure_research")
