"""순찰 발견 이야기 스냅샷 추가

Revision ID: 0024_patrol_encounters
Revises: 0023_dungeon_approaches
Create Date: 2026-08-04
"""

import sqlalchemy as sa
from alembic import op


revision = "0024_patrol_encounters"
down_revision = "0023_dungeon_approaches"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "adventure_patrols",
        sa.Column("encounter_code", sa.String(40), nullable=True),
    )
    op.add_column(
        "adventure_patrols",
        sa.Column("encounter_title", sa.String(100), nullable=True),
    )
    op.add_column(
        "adventure_patrols",
        sa.Column("encounter_text", sa.Text(), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("adventure_patrols", "encounter_text")
    op.drop_column("adventure_patrols", "encounter_title")
    op.drop_column("adventure_patrols", "encounter_code")
