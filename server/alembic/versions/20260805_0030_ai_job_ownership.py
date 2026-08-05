"""AI 작업 소유권과 계정 삭제 cascade 추가

Revision ID: 0030_ai_job_ownership
Revises: 0029_real_data_protection
Create Date: 2026-08-05
"""

import sqlalchemy as sa
from alembic import op


revision = "0030_ai_job_ownership"
down_revision = "0029_real_data_protection"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("ai_jobs", sa.Column("user_id", sa.BigInteger(), nullable=True))

    # 기존 polymorphic resource를 실제 소유 리소스까지 따라가 backfill한다.
    # 대상이 이미 삭제되어 소유자를 복원할 수 없는 과거 고아 작업은 보존 가치가
    # 없고 계정 삭제 계약에도 어긋나므로 FK를 걸기 전에 제거한다.
    op.execute(
        sa.text(
            """
            UPDATE ai_jobs
               SET user_id = (
                   SELECT mood_entries.user_id
                     FROM mood_entries
                    WHERE mood_entries.id = ai_jobs.resource_id
               )
             WHERE resource_type = 'mood_entry'
            """
        )
    )
    op.execute(
        sa.text(
            """
            UPDATE ai_jobs
               SET user_id = (
                   SELECT chat_sessions.user_id
                     FROM chat_runs
                     JOIN chat_sessions ON chat_sessions.id = chat_runs.session_id
                    WHERE chat_runs.id = ai_jobs.resource_id
               )
             WHERE resource_type = 'chat_run'
            """
        )
    )
    op.execute(
        sa.text(
            """
            UPDATE ai_jobs
               SET user_id = (
                   SELECT reports.user_id
                     FROM reports
                    WHERE reports.id = ai_jobs.resource_id
               )
             WHERE resource_type = 'report'
            """
        )
    )
    op.execute(sa.text("DELETE FROM ai_jobs WHERE user_id IS NULL"))

    with op.batch_alter_table("ai_jobs") as batch:
        batch.alter_column("user_id", existing_type=sa.BigInteger(), nullable=False)
        batch.create_foreign_key(
            "fk_ai_jobs_user_id_users",
            "users",
            ["user_id"],
            ["id"],
            ondelete="CASCADE",
        )
    op.create_index("ix_ai_jobs_user_id", "ai_jobs", ["user_id"])


def downgrade() -> None:
    op.drop_index("ix_ai_jobs_user_id", table_name="ai_jobs")
    with op.batch_alter_table("ai_jobs") as batch:
        batch.drop_constraint("fk_ai_jobs_user_id_users", type_="foreignkey")
        batch.drop_column("user_id")
