"""감정 기록 사용자 편집 버전 분리

Revision ID: 0005_mood_edit_version
Revises: 0004_content_depth
Create Date: 2026-07-13
"""

from alembic import op
import sqlalchemy as sa


revision = "0005_mood_edit_version"
down_revision = "0004_content_depth"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # 기존 행은 사용자 편집 이력이 없다고 보고 1부터 시작한다. updated_at은 AI
    # worker도 갱신하므로 과거 값을 버전으로 변환하지 않는다.
    op.add_column(
        "mood_entries",
        sa.Column("edit_version", sa.Integer(), nullable=False, server_default="1"),
    )


def downgrade() -> None:
    op.drop_column("mood_entries", "edit_version")
