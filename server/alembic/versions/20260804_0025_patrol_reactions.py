"""순찰 캐릭터 귀환 반응 스냅샷 추가

Revision ID: 0025_patrol_reactions
Revises: 0024_patrol_encounters
Create Date: 2026-08-04
"""

import sqlalchemy as sa
from alembic import op


revision = "0025_patrol_reactions"
down_revision = "0024_patrol_encounters"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "adventure_patrols",
        sa.Column("reaction_form", sa.String(20), nullable=True),
    )
    op.add_column(
        "adventure_patrols",
        sa.Column("reaction_speaker", sa.String(40), nullable=True),
    )
    op.add_column(
        "adventure_patrols",
        sa.Column("reaction_text", sa.Text(), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("adventure_patrols", "reaction_text")
    op.drop_column("adventure_patrols", "reaction_speaker")
    op.drop_column("adventure_patrols", "reaction_form")
