"""직접 조작형 탐험 런과 행동 원장 추가

Revision ID: 0027_interactive_expeditions
Revises: 0026_dungeon_scenes
Create Date: 2026-08-04
"""

import sqlalchemy as sa
from alembic import op


revision = "0027_interactive_expeditions"
down_revision = "0026_dungeon_scenes"
branch_labels = None
depends_on = None


PK = sa.BigInteger().with_variant(sa.Integer(), "sqlite")


def upgrade() -> None:
    op.create_table(
        "expedition_runs",
        sa.Column("id", PK, primary_key=True, autoincrement=True),
        sa.Column(
            "user_id",
            sa.BigInteger(),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("region_code", sa.String(40), nullable=False),
        sa.Column("mode", sa.String(24), nullable=False),
        sa.Column("status", sa.String(24), nullable=False, server_default="active"),
        sa.Column("phase", sa.String(24), nullable=False, server_default="exploring"),
        sa.Column("local_date", sa.Date(), nullable=False),
        sa.Column("content_version", sa.String(32), nullable=False),
        sa.Column("map_seed", sa.String(64), nullable=False),
        sa.Column("map_snapshot", sa.JSON(), nullable=False),
        sa.Column("run_thread_snapshot", sa.JSON(), nullable=False),
        sa.Column("run_memory_snapshot", sa.JSON(), nullable=False),
        sa.Column("spotlight_snapshot", sa.JSON(), nullable=False),
        sa.Column("runtime_effects_snapshot", sa.JSON(), nullable=False),
        sa.Column("current_node_code", sa.String(40), nullable=False),
        sa.Column(
            "trail_light", sa.SmallInteger(), nullable=False, server_default="10"
        ),
        sa.Column("resolve", sa.SmallInteger(), nullable=False, server_default="6"),
        sa.Column(
            "objective_secured", sa.Boolean(), nullable=False, server_default=sa.false()
        ),
        sa.Column(
            "reward_eligible", sa.Boolean(), nullable=False, server_default=sa.false()
        ),
        sa.Column("revision", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("started_at", sa.DateTime(), nullable=False),
        sa.Column("completed_at", sa.DateTime(), nullable=True),
        sa.Column("summary_snapshot", sa.JSON(), nullable=True),
        sa.Column("home_reflection_seen_at", sa.DateTime(), nullable=True),
        sa.CheckConstraint(
            "status IN ('active','completed','retreated','safe_returned')",
            name="ck_expedition_run_status",
        ),
        sa.CheckConstraint(
            "phase IN ('exploring','awaiting_event','camp')",
            name="ck_expedition_run_phase",
        ),
        sa.CheckConstraint(
            "trail_light BETWEEN 0 AND 12", name="ck_expedition_trail_light"
        ),
        sa.CheckConstraint("resolve BETWEEN 0 AND 6", name="ck_expedition_resolve"),
    )
    op.create_index("ix_expedition_runs_user_id", "expedition_runs", ["user_id"])

    op.create_table(
        "user_active_expeditions",
        sa.Column(
            "user_id",
            sa.BigInteger(),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            primary_key=True,
        ),
        sa.Column(
            "run_id",
            sa.BigInteger(),
            sa.ForeignKey("expedition_runs.id", ondelete="CASCADE"),
            nullable=False,
            unique=True,
        ),
        sa.Column("created_at", sa.DateTime(), nullable=False),
    )

    op.create_table(
        "expedition_party_members",
        sa.Column("id", PK, primary_key=True, autoincrement=True),
        sa.Column(
            "run_id",
            sa.BigInteger(),
            sa.ForeignKey("expedition_runs.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("position", sa.SmallInteger(), nullable=False),
        sa.Column(
            "plant_id",
            sa.BigInteger(),
            sa.ForeignKey("plants.id", ondelete="RESTRICT"),
            nullable=True,
        ),
        sa.Column("is_guide", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("snapshot", sa.JSON(), nullable=False),
        sa.Column(
            "signature_used", sa.Boolean(), nullable=False, server_default=sa.false()
        ),
        sa.Column("form_used", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.UniqueConstraint("run_id", "position", name="uq_expedition_party_position"),
        sa.UniqueConstraint("run_id", "plant_id", name="uq_expedition_party_plant"),
    )
    op.create_index(
        "ix_expedition_party_members_run_id", "expedition_party_members", ["run_id"]
    )

    op.create_table(
        "expedition_node_states",
        sa.Column("id", PK, primary_key=True, autoincrement=True),
        sa.Column(
            "run_id",
            sa.BigInteger(),
            sa.ForeignKey("expedition_runs.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("node_code", sa.String(40), nullable=False),
        sa.Column("status", sa.String(20), nullable=False),
        sa.Column("event_code", sa.String(40), nullable=True),
        sa.Column("entered_at", sa.DateTime(), nullable=True),
        sa.Column("resolved_at", sa.DateTime(), nullable=True),
        sa.Column("outcome_code", sa.String(20), nullable=True),
        sa.Column(
            "acting_member_id",
            sa.BigInteger(),
            sa.ForeignKey("expedition_party_members.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column("story_snapshot", sa.JSON(), nullable=True),
        sa.UniqueConstraint("run_id", "node_code", name="uq_expedition_node"),
        sa.CheckConstraint(
            "status IN ('hidden','revealed','visited','resolved')",
            name="ck_expedition_node_status",
        ),
    )
    op.create_index(
        "ix_expedition_node_states_run_id", "expedition_node_states", ["run_id"]
    )

    op.create_table(
        "expedition_actions",
        sa.Column("id", PK, primary_key=True, autoincrement=True),
        sa.Column(
            "run_id",
            sa.BigInteger(),
            sa.ForeignKey("expedition_runs.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("action_index", sa.Integer(), nullable=False),
        sa.Column("client_action_id", sa.String(64), nullable=False),
        sa.Column("expected_revision", sa.Integer(), nullable=False),
        sa.Column("action_type", sa.String(24), nullable=False),
        sa.Column("request_payload", sa.JSON(), nullable=False),
        sa.Column("result_payload", sa.JSON(), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.UniqueConstraint(
            "run_id", "action_index", name="uq_expedition_action_index"
        ),
        sa.UniqueConstraint(
            "run_id", "client_action_id", name="uq_expedition_client_action"
        ),
    )
    op.create_index("ix_expedition_actions_run_id", "expedition_actions", ["run_id"])

    op.create_table(
        "expedition_loot",
        sa.Column("id", PK, primary_key=True, autoincrement=True),
        sa.Column(
            "run_id",
            sa.BigInteger(),
            sa.ForeignKey("expedition_runs.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("node_code", sa.String(40), nullable=False),
        sa.Column("item_code", sa.String(40), nullable=False),
        sa.Column("quantity", sa.Integer(), nullable=False, server_default="1"),
        sa.Column("value_units", sa.SmallInteger(), nullable=False, server_default="1"),
        sa.Column("loot_kind", sa.String(20), nullable=False),
        sa.Column(
            "disposition", sa.String(20), nullable=False, server_default="candidate"
        ),
        sa.Column("granted_at", sa.DateTime(), nullable=True),
        sa.UniqueConstraint(
            "run_id", "node_code", "item_code", "loot_kind", name="uq_expedition_loot"
        ),
    )
    op.create_index("ix_expedition_loot_run_id", "expedition_loot", ["run_id"])

    op.create_table(
        "expedition_content_exposures",
        sa.Column("id", PK, primary_key=True, autoincrement=True),
        sa.Column(
            "user_id",
            sa.BigInteger(),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "run_id",
            sa.BigInteger(),
            sa.ForeignKey("expedition_runs.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("content_kind", sa.String(24), nullable=False),
        sa.Column("content_code", sa.String(96), nullable=False),
        sa.Column("context_code", sa.String(96), nullable=True),
        sa.Column("exposure_index", sa.Integer(), nullable=False),
        sa.Column("shown_at", sa.DateTime(), nullable=False),
        sa.UniqueConstraint(
            "run_id",
            "content_kind",
            "content_code",
            "exposure_index",
            name="uq_expedition_content_exposure",
        ),
    )
    op.create_index(
        "ix_expedition_exposure_recent",
        "expedition_content_exposures",
        ["user_id", "content_kind", "context_code", "shown_at"],
    )


def downgrade() -> None:
    op.drop_index(
        "ix_expedition_exposure_recent", table_name="expedition_content_exposures"
    )
    op.drop_table("expedition_content_exposures")
    op.drop_index("ix_expedition_loot_run_id", table_name="expedition_loot")
    op.drop_table("expedition_loot")
    op.drop_index("ix_expedition_actions_run_id", table_name="expedition_actions")
    op.drop_table("expedition_actions")
    op.drop_index(
        "ix_expedition_node_states_run_id", table_name="expedition_node_states"
    )
    op.drop_table("expedition_node_states")
    op.drop_index(
        "ix_expedition_party_members_run_id", table_name="expedition_party_members"
    )
    op.drop_table("expedition_party_members")
    op.drop_table("user_active_expeditions")
    op.drop_index("ix_expedition_runs_user_id", table_name="expedition_runs")
    op.drop_table("expedition_runs")
