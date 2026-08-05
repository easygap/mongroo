"""직접 탐험 유대와 지역 진행도 추가

Revision ID: 0028_expedition_progress
Revises: 0027_interactive_expeditions
Create Date: 2026-08-04
"""

import sqlalchemy as sa
from alembic import op


revision = "0028_expedition_progress"
down_revision = "0027_interactive_expeditions"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "plant_adventure_bonds",
        sa.Column(
            "plant_id",
            sa.BigInteger(),
            sa.ForeignKey("plants.id", ondelete="CASCADE"),
            primary_key=True,
        ),
        sa.Column(
            "user_id",
            sa.BigInteger(),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("bond_points", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("last_bond_local_date", sa.Date(), nullable=True),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
        sa.CheckConstraint("bond_points >= 0", name="ck_plant_adventure_bond_points"),
    )
    op.create_index(
        "ix_plant_adventure_bonds_user_id", "plant_adventure_bonds", ["user_id"]
    )

    op.create_table(
        "user_region_progress",
        sa.Column(
            "user_id",
            sa.BigInteger(),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            primary_key=True,
        ),
        sa.Column("region_code", sa.String(40), primary_key=True),
        sa.Column("first_cleared_at", sa.DateTime(), nullable=True),
        sa.Column("clear_count", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("templates_seen", sa.JSON(), nullable=False),
        sa.Column("events_seen", sa.JSON(), nullable=False),
        sa.Column("knowledge_code", sa.String(40), nullable=True),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
        sa.CheckConstraint("clear_count >= 0", name="ck_user_region_clear_count"),
    )

    op.create_table(
        "plant_region_familiarities",
        sa.Column(
            "plant_id",
            sa.BigInteger(),
            sa.ForeignKey("plants.id", ondelete="CASCADE"),
            primary_key=True,
        ),
        sa.Column("region_code", sa.String(40), primary_key=True),
        sa.Column(
            "user_id",
            sa.BigInteger(),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("points", sa.SmallInteger(), nullable=False, server_default="0"),
        sa.Column(
            "participation_count", sa.Integer(), nullable=False, server_default="0"
        ),
        sa.Column("last_point_local_date", sa.Date(), nullable=True),
        sa.Column("unlocked_scene_codes", sa.JSON(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
        sa.CheckConstraint(
            "points BETWEEN 0 AND 6", name="ck_plant_region_familiarity_points"
        ),
        sa.CheckConstraint(
            "participation_count >= 0",
            name="ck_plant_region_familiarity_participation",
        ),
    )
    op.create_index(
        "ix_plant_region_familiarities_user_id",
        "plant_region_familiarities",
        ["user_id"],
    )


def downgrade() -> None:
    op.drop_index(
        "ix_plant_region_familiarities_user_id",
        table_name="plant_region_familiarities",
    )
    op.drop_table("plant_region_familiarities")
    op.drop_table("user_region_progress")
    op.drop_index(
        "ix_plant_adventure_bonds_user_id", table_name="plant_adventure_bonds"
    )
    op.drop_table("plant_adventure_bonds")
