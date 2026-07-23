"""연속 출석 대신 누적 기록으로 방 테마 해금

Revision ID: 0011_content_progression
Revises: 0010_diary_growth
Create Date: 2026-07-15
"""

from alembic import op
import sqlalchemy as sa


revision = "0011_content_progression"
down_revision = "0010_diary_growth"
branch_labels = None
depends_on = None


def _set_sakura_rule(*, cumulative: bool) -> None:
    bind = op.get_bind()
    items = sa.table(
        "items",
        sa.column("code", sa.String),
        sa.column("asset_manifest", sa.JSON),
    )
    row = (
        bind.execute(
            sa.select(items.c.asset_manifest).where(items.c.code == "room_sakura")
        )
        .mappings()
        .first()
    )
    if row is None:
        return

    manifest = dict(row["asset_manifest"] or {})
    manifest["acquisition"] = (
        {
            "type": "record_count",
            "target": 7,
            "label": "마음을 기록한 날 누적 7일",
        }
        if cumulative
        else {
            "type": "streak",
            "target": 7,
            "label": "마음 기록 7일 연속 달성",
        }
    )
    bind.execute(
        sa.update(items)
        .where(items.c.code == "room_sakura")
        .values(asset_manifest=manifest)
    )


def upgrade() -> None:
    _set_sakura_rule(cumulative=True)


def downgrade() -> None:
    _set_sakura_rule(cumulative=False)
