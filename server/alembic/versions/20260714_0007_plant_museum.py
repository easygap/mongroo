"""식물 박물관 감정 표현형 스냅샷

Revision ID: 0007_plant_museum
Revises: 0006_room_acquisition
Create Date: 2026-07-14
"""

from alembic import op
import sqlalchemy as sa


revision = "0007_plant_museum"
down_revision = "0006_room_acquisition"
branch_labels = None
depends_on = None


EMPTY_PROFILE = {
    "version": 1,
    "total": 0,
    "counts": {
        "joy": 0,
        "sadness": 0,
        "anger": 0,
        "anxiety": 0,
        "surprise": 0,
        "mixed": 0,
    },
    "ratios": {
        "joy": 0.0,
        "sadness": 0.0,
        "anger": 0.0,
        "anxiety": 0.0,
        "surprise": 0.0,
        "mixed": 0.0,
    },
}


def upgrade() -> None:
    op.add_column("plants", sa.Column("final_form", sa.String(20), nullable=True))
    op.add_column("plants", sa.Column("emotion_profile", sa.JSON(), nullable=True))
    op.add_column(
        "plants",
        sa.Column(
            "museum_featured",
            sa.Boolean(),
            nullable=False,
            server_default=sa.false(),
        ),
    )
    op.create_index(
        "ix_plants_museum",
        "plants",
        ["user_id", "museum_featured", "harvested_at"],
    )

    # 이미 수확된 식물은 당시 분석 원본을 재현할 수 없으므로 중립적인 모자이크형으로
    # 안전하게 보존한다. 새 수확부터는 실제 생애 주기의 기록으로 스냅샷을 만든다.
    plants = sa.table(
        "plants",
        sa.column("status", sa.String),
        sa.column("final_form", sa.String),
        sa.column("emotion_profile", sa.JSON),
    )
    op.get_bind().execute(
        sa.update(plants)
        .where(plants.c.status == "harvested")
        .values(final_form="mosaic", emotion_profile=EMPTY_PROFILE)
    )


def downgrade() -> None:
    op.drop_index("ix_plants_museum", table_name="plants")
    op.drop_column("plants", "museum_featured")
    op.drop_column("plants", "emotion_profile")
    op.drop_column("plants", "final_form")
