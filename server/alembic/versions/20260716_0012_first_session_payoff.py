"""첫 마음 기록 후 잎사귀 쿠션 해금

Revision ID: 0012_first_payoff
Revises: 0011_content_progression
Create Date: 2026-07-16
"""

from alembic import op
import sqlalchemy as sa


revision = "0012_first_payoff"
down_revision = "0011_content_progression"
branch_labels = None
depends_on = None


def _set_leaf_cushion_rule(*, first_record: bool) -> None:
    bind = op.get_bind()
    items = sa.table(
        "items",
        sa.column("code", sa.String),
        sa.column("price_seeds", sa.Integer),
        sa.column("asset_manifest", sa.JSON),
    )
    row = (
        bind.execute(
            sa.select(items.c.asset_manifest).where(items.c.code == "deco_cushion_leaf")
        )
        .mappings()
        .first()
    )
    if row is None:
        return

    manifest = dict(row["asset_manifest"] or {})
    if first_record:
        manifest["acquisition"] = {
            "type": "record_count",
            "target": 1,
            "label": "첫 마음 기록을 남기면 받아요",
        }
        price_seeds = 0
    else:
        manifest.pop("acquisition", None)
        price_seeds = 25

    bind.execute(
        sa.update(items)
        .where(items.c.code == "deco_cushion_leaf")
        .values(price_seeds=price_seeds, asset_manifest=manifest)
    )


def upgrade() -> None:
    _set_leaf_cushion_rule(first_record=True)


def downgrade() -> None:
    _set_leaf_cushion_rule(first_record=False)
