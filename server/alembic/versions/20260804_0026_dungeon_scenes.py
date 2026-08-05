"""던전 내부 장면 스냅샷 추가

Revision ID: 0026_dungeon_scenes
Revises: 0025_patrol_reactions
Create Date: 2026-08-04
"""

import sqlalchemy as sa
from alembic import op


revision = "0026_dungeon_scenes"
down_revision = "0025_patrol_reactions"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "dungeon_runs",
        sa.Column("scene_code", sa.String(40), nullable=True),
    )
    op.add_column(
        "dungeon_runs",
        sa.Column("scene_title", sa.String(100), nullable=True),
    )
    op.add_column(
        "dungeon_runs",
        sa.Column("scene_text", sa.Text(), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("dungeon_runs", "scene_text")
    op.drop_column("dungeon_runs", "scene_title")
    op.drop_column("dungeon_runs", "scene_code")
