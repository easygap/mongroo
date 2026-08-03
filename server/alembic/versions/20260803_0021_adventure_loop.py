"""마음 일기 기반 순찰·던전 탐험 루프 추가

Revision ID: 0021_adventure_loop
Revises: 0020_complete_wardrobe
Create Date: 2026-08-03
"""

import sqlalchemy as sa
from alembic import op


revision = "0021_adventure_loop"
down_revision = "0020_complete_wardrobe"
branch_labels = None
depends_on = None


OUTFIT_BONUSES = {
    "wardrobe_garden_daily": {
        "context": "patrol",
        "stat": "care",
        "amount": 2,
        "label": "순찰 돌봄 +2",
    },
    "wardrobe_city_night": {
        "context": "dungeon",
        "stat": "focus",
        "amount": 2,
        "label": "던전 집중 +2",
    },
}


def _update_outfit_bonuses(*, remove: bool) -> None:
    bind = op.get_bind()
    items = sa.table(
        "items",
        sa.column("id", sa.BigInteger),
        sa.column("code", sa.String),
        sa.column("asset_manifest", sa.JSON),
    )
    rows = bind.execute(
        sa.select(items.c.id, items.c.code, items.c.asset_manifest).where(
            items.c.code.in_(tuple(OUTFIT_BONUSES))
        )
    ).mappings()
    for row in rows:
        manifest = dict(row["asset_manifest"] or {})
        if remove:
            manifest.pop("adventure_bonus", None)
        else:
            manifest["adventure_bonus"] = OUTFIT_BONUSES[row["code"]]
        bind.execute(
            sa.update(items)
            .where(items.c.id == row["id"])
            .values(asset_manifest=manifest)
        )


def upgrade() -> None:
    op.create_table(
        "adventure_patrols",
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
        sa.Column(
            "plant_id",
            sa.BigInteger(),
            sa.ForeignKey("plants.id", ondelete="RESTRICT"),
            nullable=False,
        ),
        sa.Column("route_code", sa.String(40), nullable=False),
        sa.Column("local_date", sa.Date(), nullable=False),
        sa.Column("status", sa.String(20), nullable=False, server_default="active"),
        sa.Column("started_at", sa.DateTime(), nullable=False),
        sa.Column("returns_at", sa.DateTime(), nullable=False),
        sa.Column("claimed_at", sa.DateTime(), nullable=True),
        sa.Column("reward_exp", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("reward_seeds", sa.Integer(), nullable=False, server_default="3"),
        sa.Column("discovery_code", sa.String(40), nullable=True),
        sa.Column("found_item_code", sa.String(40), nullable=False),
        sa.Column("found_quantity", sa.Integer(), nullable=False, server_default="1"),
        sa.Column("performance_score", sa.Integer(), nullable=False),
        sa.UniqueConstraint("user_id", "local_date", name="uq_adventure_patrol_day"),
        sa.CheckConstraint(
            "status IN ('active','claimed')", name="ck_adventure_patrol_status"
        ),
        sa.CheckConstraint(
            "reward_exp >= 0 AND reward_seeds >= 0",
            name="ck_adventure_patrol_reward_nonnegative",
        ),
    )
    op.create_index("ix_adventure_patrols_user_id", "adventure_patrols", ["user_id"])

    op.create_table(
        "user_dungeons",
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
        sa.Column("dungeon_code", sa.String(40), nullable=False),
        sa.Column("discovered_at", sa.DateTime(), nullable=False),
        sa.Column("clear_count", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("last_cleared_at", sa.DateTime(), nullable=True),
        sa.UniqueConstraint("user_id", "dungeon_code", name="uq_user_dungeon"),
        sa.CheckConstraint("clear_count >= 0", name="ck_user_dungeon_clear_count"),
    )
    op.create_index("ix_user_dungeons_user_id", "user_dungeons", ["user_id"])

    op.create_table(
        "dungeon_runs",
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
        sa.Column(
            "plant_id",
            sa.BigInteger(),
            sa.ForeignKey("plants.id", ondelete="RESTRICT"),
            nullable=False,
        ),
        sa.Column(
            "user_dungeon_id",
            sa.BigInteger(),
            sa.ForeignKey("user_dungeons.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("local_date", sa.Date(), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("reward_exp", sa.Integer(), nullable=False, server_default="10"),
        sa.Column("reward_seeds", sa.Integer(), nullable=False, server_default="4"),
        sa.Column("found_item_code", sa.String(40), nullable=False),
        sa.Column("found_quantity", sa.Integer(), nullable=False, server_default="1"),
        sa.Column("performance_score", sa.Integer(), nullable=False),
        sa.UniqueConstraint("user_id", "local_date", name="uq_dungeon_run_day"),
        sa.CheckConstraint(
            "reward_exp >= 0 AND reward_seeds >= 0",
            name="ck_dungeon_run_reward_nonnegative",
        ),
    )
    op.create_index("ix_dungeon_runs_user_id", "dungeon_runs", ["user_id"])

    op.create_table(
        "user_adventure_items",
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
        sa.Column("item_code", sa.String(40), nullable=False),
        sa.Column("quantity", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
        sa.UniqueConstraint("user_id", "item_code", name="uq_user_adventure_item"),
        sa.CheckConstraint("quantity >= 0", name="ck_adventure_item_quantity"),
    )
    op.create_index(
        "ix_user_adventure_items_user_id", "user_adventure_items", ["user_id"]
    )
    _update_outfit_bonuses(remove=False)


def downgrade() -> None:
    _update_outfit_bonuses(remove=True)
    op.drop_index("ix_user_adventure_items_user_id", table_name="user_adventure_items")
    op.drop_table("user_adventure_items")
    op.drop_index("ix_dungeon_runs_user_id", table_name="dungeon_runs")
    op.drop_table("dungeon_runs")
    op.drop_index("ix_user_dungeons_user_id", table_name="user_dungeons")
    op.drop_table("user_dungeons")
    op.drop_index("ix_adventure_patrols_user_id", table_name="adventure_patrols")
    op.drop_table("adventure_patrols")
