"""P0 스키마: 사용자/인증, 감정 기록, 식물, 보상 원장, 대화, 리포트, 안전 이벤트, 운영 테이블

Revision ID: 0001_p0_schema
Revises:
Create Date: 2026-07-10
"""
from alembic import op
import sqlalchemy as sa

revision = "0001_p0_schema"
down_revision = None
branch_labels = None
depends_on = None

BigIntPK = sa.BigInteger().with_variant(sa.Integer(), "sqlite")


def _timestamps():
    return (
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
    )


def upgrade() -> None:
    op.create_table(
        "users",
        sa.Column("id", BigIntPK, primary_key=True, autoincrement=True),
        sa.Column("email", sa.String(255), nullable=False, unique=True),
        sa.Column("password_hash", sa.String(255), nullable=False),
        sa.Column("nickname", sa.String(30), nullable=False),
        sa.Column("timezone", sa.String(64), nullable=False, server_default="Asia/Seoul"),
        sa.Column("seed_balance", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("streak_days", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("last_recorded_local_date", sa.Date(), nullable=True),
        *_timestamps(),
    )

    op.create_table(
        "auth_sessions",
        sa.Column("id", BigIntPK, primary_key=True, autoincrement=True),
        sa.Column("user_id", sa.BigInteger().with_variant(sa.Integer(), "sqlite"),
                  sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True),
        sa.Column("session_family", sa.String(64), nullable=False, unique=True),
        sa.Column("expires_at", sa.DateTime(), nullable=False),
        sa.Column("revoked_at", sa.DateTime(), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
    )

    op.create_table(
        "refresh_tokens",
        sa.Column("id", BigIntPK, primary_key=True, autoincrement=True),
        sa.Column("session_id", sa.BigInteger().with_variant(sa.Integer(), "sqlite"),
                  sa.ForeignKey("auth_sessions.id", ondelete="CASCADE"), nullable=False, index=True),
        sa.Column("jti_hash", sa.String(64), nullable=False, unique=True),
        sa.Column("expires_at", sa.DateTime(), nullable=False),
        sa.Column("used_at", sa.DateTime(), nullable=True),
        sa.Column("revoked_at", sa.DateTime(), nullable=True),
        sa.Column("replaced_by_id", sa.BigInteger(), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
    )

    op.create_table(
        "mood_entries",
        sa.Column("id", BigIntPK, primary_key=True, autoincrement=True),
        sa.Column("user_id", sa.BigInteger().with_variant(sa.Integer(), "sqlite"),
                  sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("local_date", sa.Date(), nullable=False),
        sa.Column("recorded_at_utc", sa.DateTime(), nullable=False),
        sa.Column("mood_level", sa.SmallInteger(), nullable=False),
        sa.Column("emotion_tags", sa.JSON(), nullable=False),
        sa.Column("content", sa.Text(), nullable=True),
        sa.Column("input_version", sa.Integer(), nullable=False, server_default="1"),
        sa.Column("analysis_status", sa.String(20), nullable=False,
                  server_default="not_requested"),
        sa.Column("ai_emotion", sa.String(20), nullable=True),
        sa.Column("ai_scores", sa.JSON(), nullable=True),
        sa.Column("ai_emotion_override", sa.String(20), nullable=True),
        sa.Column("ai_label_hidden", sa.Boolean(), nullable=False, server_default="0"),
        sa.Column("analysis_model_version", sa.String(80), nullable=True),
        sa.Column("analyzed_at", sa.DateTime(), nullable=True),
        sa.Column("analysis_error_code", sa.String(40), nullable=True),
        *_timestamps(),
        sa.CheckConstraint("mood_level BETWEEN 1 AND 5", name="ck_mood_level"),
        sa.CheckConstraint(
            "analysis_status IN ('not_requested','pending','running','succeeded','failed')",
            name="ck_analysis_status",
        ),
    )
    op.create_index("ix_mood_user_date", "mood_entries",
                    ["user_id", "local_date", "recorded_at_utc"])

    op.create_table(
        "plant_species",
        sa.Column("id", BigIntPK, primary_key=True, autoincrement=True),
        sa.Column("code", sa.String(40), nullable=False, unique=True),
        sa.Column("name", sa.String(40), nullable=False),
        sa.Column("persona_key", sa.String(40), nullable=False),
        sa.Column("asset_manifest", sa.JSON(), nullable=False),
        sa.Column("rarity", sa.SmallInteger(), nullable=False, server_default="1"),
        sa.Column("unlock_price", sa.Integer(), nullable=False, server_default="0"),
    )

    op.create_table(
        "plants",
        sa.Column("id", BigIntPK, primary_key=True, autoincrement=True),
        sa.Column("user_id", sa.BigInteger().with_variant(sa.Integer(), "sqlite"),
                  sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True),
        sa.Column("species_id", sa.BigInteger().with_variant(sa.Integer(), "sqlite"),
                  sa.ForeignKey("plant_species.id", ondelete="RESTRICT"), nullable=False),
        sa.Column("name", sa.String(20), nullable=False),
        sa.Column("exp", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("status", sa.String(20), nullable=False, server_default="active"),
        sa.Column("planted_at", sa.DateTime(), nullable=False),
        sa.Column("harvested_at", sa.DateTime(), nullable=True),
        *_timestamps(),
        sa.CheckConstraint("status IN ('active','harvested')", name="ck_plant_status"),
    )
    # 사용자당 활성 식물 1개 강제 (design.md 4.1)
    bind = op.get_bind()
    if bind.dialect.name == "mysql":
        op.execute(
            "ALTER TABLE plants ADD COLUMN active_user_id BIGINT "
            "GENERATED ALWAYS AS (CASE WHEN status='active' THEN user_id ELSE NULL END) STORED"
        )
        op.execute(
            "CREATE UNIQUE INDEX uq_plants_active_user ON plants (active_user_id)"
        )
    else:
        op.execute(
            "CREATE UNIQUE INDEX uq_plants_active_user ON plants (user_id) "
            "WHERE status = 'active'"
        )

    op.create_table(
        "reward_events",
        sa.Column("id", BigIntPK, primary_key=True, autoincrement=True),
        sa.Column("user_id", sa.BigInteger().with_variant(sa.Integer(), "sqlite"),
                  sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True),
        sa.Column("plant_id", sa.BigInteger().with_variant(sa.Integer(), "sqlite"),
                  sa.ForeignKey("plants.id", ondelete="SET NULL"), nullable=True),
        sa.Column("event_type", sa.String(30), nullable=False),
        sa.Column("source_type", sa.String(30), nullable=False),
        sa.Column("source_id", sa.BigInteger(), nullable=True),
        sa.Column("dedupe_key", sa.String(120), nullable=False, unique=True),
        sa.Column("exp_delta", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("seed_delta", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("seed_balance_after", sa.Integer(), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.CheckConstraint("seed_balance_after >= 0", name="ck_seed_balance"),
    )

    op.create_table(
        "chat_sessions",
        sa.Column("id", BigIntPK, primary_key=True, autoincrement=True),
        sa.Column("user_id", sa.BigInteger().with_variant(sa.Integer(), "sqlite"),
                  sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True),
        sa.Column("plant_id", sa.BigInteger().with_variant(sa.Integer(), "sqlite"),
                  sa.ForeignKey("plants.id", ondelete="CASCADE"), nullable=False),
        sa.Column("reflection_stage", sa.String(20), nullable=False, server_default="greeting"),
        sa.Column("safety_state", sa.String(20), nullable=False, server_default="normal"),
        sa.Column("status", sa.String(20), nullable=False, server_default="active"),
        sa.Column("started_at", sa.DateTime(), nullable=False),
        sa.Column("ended_at", sa.DateTime(), nullable=True),
        sa.Column("last_message_at", sa.DateTime(), nullable=True),
        sa.CheckConstraint("status IN ('active','closed')", name="ck_chat_session_status"),
    )

    op.create_table(
        "chat_messages",
        sa.Column("id", BigIntPK, primary_key=True, autoincrement=True),
        sa.Column("session_id", sa.BigInteger().with_variant(sa.Integer(), "sqlite"),
                  sa.ForeignKey("chat_sessions.id", ondelete="CASCADE"), nullable=False),
        sa.Column("role", sa.String(10), nullable=False),
        sa.Column("content", sa.Text(), nullable=False),
        sa.Column("safety_status", sa.String(20), nullable=False, server_default="normal"),
        sa.Column("ai_emotion", sa.String(20), nullable=True),
        sa.Column("model_version", sa.String(80), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
    )
    op.create_index("ix_chat_messages_session", "chat_messages", ["session_id", "created_at"])

    op.create_table(
        "chat_runs",
        sa.Column("id", BigIntPK, primary_key=True, autoincrement=True),
        sa.Column("session_id", sa.BigInteger().with_variant(sa.Integer(), "sqlite"),
                  sa.ForeignKey("chat_sessions.id", ondelete="CASCADE"), nullable=False, index=True),
        sa.Column("user_message_id", sa.BigInteger().with_variant(sa.Integer(), "sqlite"),
                  sa.ForeignKey("chat_messages.id", ondelete="CASCADE"), nullable=False),
        sa.Column("assistant_message_id", sa.BigInteger().with_variant(sa.Integer(), "sqlite"),
                  sa.ForeignKey("chat_messages.id", ondelete="SET NULL"), nullable=True),
        sa.Column("client_message_id", sa.String(64), nullable=False, unique=True),
        sa.Column("status", sa.String(20), nullable=False, server_default="queued"),
        sa.Column("error_code", sa.String(40), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("finished_at", sa.DateTime(), nullable=True),
        sa.CheckConstraint(
            "status IN ('queued','generating','succeeded','failed')", name="ck_chat_run_status"
        ),
    )

    op.create_table(
        "reports",
        sa.Column("id", BigIntPK, primary_key=True, autoincrement=True),
        sa.Column("user_id", sa.BigInteger().with_variant(sa.Integer(), "sqlite"),
                  sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True),
        sa.Column("period_type", sa.String(10), nullable=False),
        sa.Column("period_start", sa.Date(), nullable=False),
        sa.Column("period_end", sa.Date(), nullable=False),
        sa.Column("input_hash", sa.String(64), nullable=False),
        sa.Column("status", sa.String(20), nullable=False, server_default="pending"),
        sa.Column("stats", sa.JSON(), nullable=False),
        sa.Column("analysis_coverage", sa.Float(), nullable=False, server_default="0"),
        sa.Column("summary", sa.JSON(), nullable=True),
        sa.Column("summary_model_version", sa.String(80), nullable=True),
        sa.Column("error_code", sa.String(40), nullable=True),
        *_timestamps(),
        sa.UniqueConstraint("user_id", "period_type", "period_start", "input_hash",
                            name="uq_report_input"),
        sa.CheckConstraint("period_type IN ('weekly','monthly')", name="ck_report_period_type"),
    )

    op.create_table(
        "safety_events",
        sa.Column("id", BigIntPK, primary_key=True, autoincrement=True),
        sa.Column("user_id", sa.BigInteger().with_variant(sa.Integer(), "sqlite"),
                  sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True),
        sa.Column("source", sa.String(20), nullable=False),
        sa.Column("resource_type", sa.String(30), nullable=False),
        sa.Column("resource_id", sa.BigInteger(), nullable=True),
        sa.Column("severity", sa.String(20), nullable=False),
        sa.Column("reason_codes", sa.JSON(), nullable=False),
        sa.Column("detector_version", sa.String(40), nullable=False),
        sa.Column("action_taken", sa.String(40), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
    )

    op.create_table(
        "ai_jobs",
        sa.Column("id", BigIntPK, primary_key=True, autoincrement=True),
        sa.Column("job_type", sa.String(30), nullable=False),
        sa.Column("resource_type", sa.String(30), nullable=False),
        sa.Column("resource_id", sa.BigInteger(), nullable=False),
        sa.Column("input_version", sa.Integer(), nullable=False, server_default="1"),
        sa.Column("status", sa.String(20), nullable=False, server_default="pending"),
        sa.Column("attempts", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("available_at", sa.DateTime(), nullable=False),
        sa.Column("locked_at", sa.DateTime(), nullable=True),
        sa.Column("last_error_code", sa.String(40), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.UniqueConstraint("job_type", "resource_type", "resource_id", "input_version",
                            name="uq_ai_job_input"),
        sa.CheckConstraint(
            "status IN ('pending','running','succeeded','failed')", name="ck_ai_job_status"
        ),
    )
    op.create_index("ix_ai_jobs_claim", "ai_jobs", ["status", "available_at"])

    op.create_table(
        "idempotency_keys",
        sa.Column("id", BigIntPK, primary_key=True, autoincrement=True),
        sa.Column("user_id", sa.BigInteger().with_variant(sa.Integer(), "sqlite"),
                  sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("route_scope", sa.String(40), nullable=False),
        sa.Column("idempotency_key", sa.String(64), nullable=False),
        sa.Column("request_hash", sa.String(64), nullable=False),
        sa.Column("response_status", sa.Integer(), nullable=False),
        sa.Column("response_body", sa.JSON(), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.UniqueConstraint("user_id", "route_scope", "idempotency_key", name="uq_idem_key"),
    )

    op.create_table(
        "worker_heartbeats",
        sa.Column("worker_name", sa.String(40), primary_key=True),
        sa.Column("beat_at", sa.DateTime(), nullable=False),
    )

    # 기본 품종 시드. basic_sprout만 무료(P0), 나머지는 P1 상점 해금 대상
    species = sa.table(
        "plant_species",
        sa.column("code", sa.String), sa.column("name", sa.String),
        sa.column("persona_key", sa.String), sa.column("asset_manifest", sa.JSON),
        sa.column("rarity", sa.SmallInteger), sa.column("unlock_price", sa.Integer),
    )
    op.bulk_insert(
        species,
        [
            {"code": "basic_sprout", "name": "새싹몬", "persona_key": "sprout",
             "asset_manifest": {}, "rarity": 1, "unlock_price": 0},
            {"code": "cactus", "name": "가시니", "persona_key": "cactus",
             "asset_manifest": {}, "rarity": 2, "unlock_price": 100},
            {"code": "sunflower", "name": "해바라기", "persona_key": "sunflower",
             "asset_manifest": {}, "rarity": 2, "unlock_price": 100},
        ],
    )


def downgrade() -> None:
    for table in (
        "worker_heartbeats", "idempotency_keys", "ai_jobs", "safety_events", "reports",
        "chat_runs", "chat_messages", "chat_sessions", "reward_events", "plants",
        "plant_species", "mood_entries", "refresh_tokens", "auth_sessions", "users",
    ):
        op.drop_table(table)
