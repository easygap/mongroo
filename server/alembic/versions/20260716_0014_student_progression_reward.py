"""누적 30일 기록 학생회장 캐릭터 해금

Revision ID: 0014_student_reward
Revises: 0013_quest_expansion
Create Date: 2026-07-16
"""

from alembic import op
import sqlalchemy as sa


revision = "0014_student_reward"
down_revision = "0013_quest_expansion"
branch_labels = None
depends_on = None


def _set_student_acquisition(*, record_reward: bool) -> None:
    bind = op.get_bind()
    items = sa.table(
        "items",
        sa.column("code", sa.String),
        sa.column("price_seeds", sa.Integer),
        sa.column("asset_manifest", sa.JSON),
    )
    row = (
        bind.execute(
            sa.select(items.c.asset_manifest).where(
                items.c.code == "character_student_pot"
            )
        )
        .mappings()
        .first()
    )
    if row is None:
        return

    manifest = dict(row["asset_manifest"] or {})
    if record_reward:
        manifest["acquisition"] = {
            "type": "record_count",
            "target": 30,
            "label": "마음을 기록한 날 누적 30일",
        }
        price_seeds = 0
    else:
        manifest.pop("acquisition", None)
        price_seeds = 130

    bind.execute(
        sa.update(items)
        .where(items.c.code == "character_student_pot")
        .values(price_seeds=price_seeds, asset_manifest=manifest)
    )


def upgrade() -> None:
    _set_student_acquisition(record_reward=True)


def downgrade() -> None:
    _set_student_acquisition(record_reward=False)
