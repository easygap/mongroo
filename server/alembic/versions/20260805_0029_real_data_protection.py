"""실데이터 암호화·동의·로그인 제한 기반 추가

Revision ID: 0029_real_data_protection
Revises: 0028_expedition_progress
Create Date: 2026-08-05
"""

import sqlalchemy as sa
from alembic import op


revision = "0029_real_data_protection"
down_revision = "0028_expedition_progress"
branch_labels = None
depends_on = None

PROTECTION_STATE_KEY = "sensitive-fields-v1"


def _alter_sensitive_json_columns(to_text: bool) -> None:
    # SQLite의 JSON과 TEXT는 같은 저장 affinity이고 모델 TypeDecorator가 직렬화를
    # 담당한다. MySQL만 물리 JSON 컬럼을 ciphertext 수용 가능한 TEXT로 바꾼다.
    if op.get_bind().dialect.name != "mysql":
        return
    changes = (
        ("mood_entries", "emotion_tags", sa.JSON(), sa.Text(), False),
        ("mood_entries", "ai_scores", sa.JSON(), sa.Text(), True),
        ("reports", "stats", sa.JSON(), sa.Text(), False),
        ("reports", "summary", sa.JSON(), sa.Text(), True),
        ("idempotency_keys", "response_body", sa.JSON(), sa.Text(), False),
        ("plants", "emotion_profile", sa.JSON(), sa.Text(), True),
        ("expedition_runs", "summary_snapshot", sa.JSON(), sa.Text(), True),
        ("expedition_party_members", "snapshot", sa.JSON(), sa.Text(), False),
        ("expedition_actions", "result_payload", sa.JSON(), sa.Text(), False),
    )
    for table, column, json_type, text_type, nullable in changes:
        op.alter_column(
            table,
            column,
            existing_type=text_type if not to_text else json_type,
            type_=json_type if not to_text else text_type,
            existing_nullable=nullable,
        )


def upgrade() -> None:
    op.add_column(
        "mood_entries",
        sa.Column("content_length", sa.Integer(), nullable=False, server_default="0"),
    )
    length_function = (
        "LENGTH" if op.get_bind().dialect.name == "sqlite" else "CHAR_LENGTH"
    )
    op.execute(
        sa.text(
            "UPDATE mood_entries SET content_length = "
            "CASE "
            f"WHEN content IS NULL OR {length_function}(TRIM(content)) = 0 THEN 0 "
            f"WHEN {length_function}(TRIM(content)) >= 50 THEN 50 "
            "ELSE 1 END"
        )
    )

    op.add_column("users", sa.Column("terms_version", sa.String(32), nullable=True))
    op.add_column("users", sa.Column("privacy_version", sa.String(32), nullable=True))
    op.add_column(
        "users",
        sa.Column("sensitive_consent_version", sa.String(32), nullable=True),
    )
    op.add_column("users", sa.Column("age_confirmed_at", sa.DateTime(), nullable=True))
    op.add_column("users", sa.Column("consented_at", sa.DateTime(), nullable=True))

    op.create_table(
        "login_rate_limits",
        sa.Column("rate_key", sa.String(64), primary_key=True),
        sa.Column("failure_count", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("window_started_at", sa.DateTime(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
        sa.CheckConstraint(
            "failure_count >= 0", name="ck_login_rate_limit_nonnegative"
        ),
    )
    op.create_index(
        "ix_login_rate_limits_updated_at", "login_rate_limits", ["updated_at"]
    )
    op.create_table(
        "data_protection_states",
        sa.Column("protection_key", sa.String(64), primary_key=True),
        sa.Column("schema_revision", sa.String(64), nullable=False),
        sa.Column("active_key_id", sa.String(32), nullable=False),
        sa.Column("remaining_plaintext", sa.Integer(), nullable=False),
        sa.Column("verified_at", sa.DateTime(), nullable=False),
    )

    _alter_sensitive_json_columns(to_text=True)
    if op.get_bind().dialect.name == "mysql":
        for column in ("ai_emotion", "ai_emotion_override"):
            op.alter_column(
                "mood_entries",
                column,
                existing_type=sa.String(20),
                type_=sa.Text(),
                existing_nullable=True,
            )
        for column, nullable in (
            ("name", False),
            ("final_form", True),
            ("growth_branch", True),
        ):
            op.alter_column(
                "plants",
                column,
                existing_type=sa.String(20),
                type_=sa.Text(),
                existing_nullable=nullable,
            )
        op.alter_column(
            "adventure_patrols",
            "reaction_speaker",
            existing_type=sa.String(40),
            type_=sa.Text(),
            existing_nullable=True,
        )


def downgrade() -> None:
    # 운영 ciphertext가 남은 상태에서 JSON으로 되돌리면 데이터가 훼손되므로 실제
    # 롤백은 백업 복구 절차를 사용한다. 합성/빈 DB의 migration test만 지원한다.
    if op.get_bind().dialect.name == "mysql":
        protected_columns = {
            "mood_entries": (
                "content",
                "emotion_tags",
                "ai_emotion",
                "ai_scores",
                "ai_emotion_override",
            ),
            "chat_messages": ("content",),
            "reports": ("stats", "summary"),
            "idempotency_keys": ("response_body",),
            "plants": ("name", "final_form", "emotion_profile", "growth_branch"),
            "adventure_patrols": ("reaction_speaker",),
            "expedition_runs": ("summary_snapshot",),
            "expedition_party_members": ("snapshot",),
            "expedition_actions": ("result_payload",),
        }
        for table, columns in protected_columns.items():
            predicate = " OR ".join(
                f"{column} LIKE 'enc:v1:%'" for column in columns
            )
            encrypted = op.get_bind().execute(
                sa.text(f"SELECT COUNT(*) FROM {table} WHERE {predicate}")
            ).scalar_one()
            if encrypted:
                raise RuntimeError(
                    "encrypted production data cannot be downgraded in place; "
                    "restore a backup"
                )
        for column in ("ai_emotion", "ai_emotion_override"):
            op.alter_column(
                "mood_entries",
                column,
                existing_type=sa.Text(),
                type_=sa.String(20),
                existing_nullable=True,
            )
        for column, nullable in (
            ("name", False),
            ("final_form", True),
            ("growth_branch", True),
        ):
            op.alter_column(
                "plants",
                column,
                existing_type=sa.Text(),
                type_=sa.String(20),
                existing_nullable=nullable,
            )
        op.alter_column(
            "adventure_patrols",
            "reaction_speaker",
            existing_type=sa.Text(),
            type_=sa.String(40),
            existing_nullable=True,
        )
    _alter_sensitive_json_columns(to_text=False)

    op.drop_table("data_protection_states")
    op.drop_index("ix_login_rate_limits_updated_at", table_name="login_rate_limits")
    op.drop_table("login_rate_limits")
    op.drop_column("users", "consented_at")
    op.drop_column("users", "age_confirmed_at")
    op.drop_column("users", "sensitive_consent_version")
    op.drop_column("users", "privacy_version")
    op.drop_column("users", "terms_version")
    op.drop_column("mood_entries", "content_length")
