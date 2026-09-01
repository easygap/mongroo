"""장거리 개척: 구간 둘~셋을 묶는 원정 기록

Revision ID: 0040_long_haul_journeys
Revises: 0039_small_action_wording
Create Date: 2026-09-01

구간은 지금까지의 탐험 run 그대로다. 새로 필요한 것은 **그 run들을 묶는 행**과
run에서 부모를 되짚는 길뿐이다.

활성 슬롯의 `run_id`를 NULL 허용으로 바꾼다. 야영 중인 개척은 진행 중인 run이
없는데도 슬롯을 잡고 있어야 하기 때문이다 — 그래야 개척 중에 일반 탐험을
따로 시작할 수 없다.
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

from app.models.base import BigIntPK, PreciseDateTime


revision = "0040_long_haul_journeys"
down_revision = "0039_small_action_wording"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "expedition_journeys",
        # `sa.BigInteger`를 그대로 쓰면 SQLite에서 autoincrement가 안 붙어
        # `NOT NULL constraint failed: expedition_journeys.id`가 난다.
        # 모델과 같은 variant를 써야 한다.
        sa.Column("id", BigIntPK, autoincrement=True, nullable=False),
        sa.Column("user_id", sa.BigInteger(), nullable=False),
        sa.Column("direction_code", sa.String(length=40), nullable=False),
        sa.Column("status", sa.String(length=24), nullable=False),
        sa.Column("mode", sa.String(length=24), nullable=False),
        sa.Column("local_date", sa.Date(), nullable=False),
        sa.Column("content_version", sa.String(length=32), nullable=False),
        sa.Column("max_legs", sa.SmallInteger(), nullable=False),
        sa.Column("current_leg_index", sa.SmallInteger(), nullable=False),
        sa.Column("deepest_secured_region", sa.String(length=40), nullable=True),
        sa.Column(
            "reward_eligible",
            sa.Boolean(),
            nullable=False,
            server_default=sa.false(),
        ),
        sa.Column("revision", sa.Integer(), nullable=False),
        sa.Column("legs_snapshot", sa.JSON(), nullable=False),
        sa.Column("members_snapshot", sa.JSON(), nullable=False),
        sa.Column("summary_snapshot", sa.JSON(), nullable=True),
        sa.Column("started_at", PreciseDateTime, nullable=False),
        sa.Column("completed_at", PreciseDateTime, nullable=True),
        sa.CheckConstraint(
            "status IN ('active','completed','retreated','safe_returned')",
            name="ck_expedition_journey_status",
        ),
        sa.CheckConstraint(
            "max_legs BETWEEN 2 AND 3", name="ck_expedition_journey_max_legs"
        ),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_expedition_journeys_user_id", "expedition_journeys", ["user_id"]
    )

    with op.batch_alter_table("expedition_runs") as batch:
        batch.add_column(sa.Column("journey_id", sa.BigInteger(), nullable=True))
        batch.add_column(
            sa.Column("journey_leg_index", sa.SmallInteger(), nullable=True)
        )
        batch.create_foreign_key(
            "fk_expedition_runs_journey_id",
            "expedition_journeys",
            ["journey_id"],
            ["id"],
            ondelete="CASCADE",
        )
    op.create_index(
        "ix_expedition_runs_journey_id", "expedition_runs", ["journey_id"]
    )

    with op.batch_alter_table("user_active_expeditions") as batch:
        batch.alter_column("run_id", existing_type=sa.BigInteger(), nullable=True)
        batch.add_column(sa.Column("journey_id", sa.BigInteger(), nullable=True))
        batch.create_foreign_key(
            "fk_user_active_expeditions_journey_id",
            "expedition_journeys",
            ["journey_id"],
            ["id"],
            ondelete="CASCADE",
        )
        batch.create_unique_constraint(
            "uq_user_active_expeditions_journey_id", ["journey_id"]
        )


def downgrade() -> None:
    with op.batch_alter_table("user_active_expeditions") as batch:
        batch.drop_constraint(
            "uq_user_active_expeditions_journey_id", type_="unique"
        )
        batch.drop_constraint(
            "fk_user_active_expeditions_journey_id", type_="foreignkey"
        )
        batch.drop_column("journey_id")
        # 되돌릴 때 슬롯이 비어 있는 행은 남길 수 없다. 야영 중인 개척은
        # 이 시점에 이미 의미를 잃으므로 함께 지운다.
        op.execute(sa.text("DELETE FROM user_active_expeditions WHERE run_id IS NULL"))
        batch.alter_column("run_id", existing_type=sa.BigInteger(), nullable=False)

    op.drop_index("ix_expedition_runs_journey_id", table_name="expedition_runs")
    with op.batch_alter_table("expedition_runs") as batch:
        batch.drop_constraint("fk_expedition_runs_journey_id", type_="foreignkey")
        batch.drop_column("journey_leg_index")
        batch.drop_column("journey_id")

    op.drop_index(
        "ix_expedition_journeys_user_id", table_name="expedition_journeys"
    )
    op.drop_table("expedition_journeys")
