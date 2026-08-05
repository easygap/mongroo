"""던전 접근 방식과 결과 스냅샷 추가

Revision ID: 0023_dungeon_approaches
Revises: 0022_adventure_research
Create Date: 2026-08-03
"""

import sqlalchemy as sa
from alembic import op


revision = "0023_dungeon_approaches"
down_revision = "0022_adventure_research"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "dungeon_runs",
        sa.Column(
            "approach_code",
            sa.String(40),
            nullable=False,
            server_default="steady",
        ),
    )
    op.add_column(
        "dungeon_runs",
        sa.Column("approach_stat", sa.String(20), nullable=True),
    )
    op.add_column(
        "dungeon_runs",
        sa.Column(
            "outcome_code",
            sa.String(20),
            nullable=False,
            server_default="steady",
        ),
    )


def downgrade() -> None:
    op.drop_column("dungeon_runs", "outcome_code")
    op.drop_column("dungeon_runs", "approach_stat")
    op.drop_column("dungeon_runs", "approach_code")
