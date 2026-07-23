"""일기 분석 누적 성장 분기

Revision ID: 0010_diary_growth
Revises: 0009_content_copy
Create Date: 2026-07-14
"""

from collections import Counter

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import mysql


revision = "0010_diary_growth"
down_revision = "0009_content_copy"
branch_labels = None
depends_on = None


EMOTIONS = ("joy", "sadness", "anger", "anxiety", "surprise", "mixed")
ALIASES = {
    "joy": "joy",
    "happy": "joy",
    "happiness": "joy",
    "기쁨": "joy",
    "행복": "joy",
    "즐거움": "joy",
    "sad": "sadness",
    "sadness": "sadness",
    "hurt": "sadness",
    "슬픔": "sadness",
    "상처": "sadness",
    "anger": "anger",
    "angry": "anger",
    "분노": "anger",
    "anxiety": "anxiety",
    "anxious": "anxiety",
    "fear": "anxiety",
    "불안": "anxiety",
    "surprise": "surprise",
    "surprised": "surprise",
    "당황": "surprise",
    "mixed": "mixed",
    "uncertain": "mixed",
    "혼합": "mixed",
}
BRANCH_BY_FORM = {
    "sunny": "joy",
    "rainy": "sadness",
    "ember": "anger",
    "moonlit": "anxiety",
    "sparkling": "surprise",
    "mosaic": "mixed",
}
PRECISE_DATETIME = sa.DateTime().with_variant(mysql.DATETIME(fsp=6), "mysql")


def _profile(rows) -> dict:
    counts = Counter()
    pending = unavailable = empty = 0
    for content, status, label in rows:
        if not isinstance(content, str) or not content.strip():
            empty += 1
        elif status in ("pending", "running"):
            pending += 1
        elif status == "succeeded" and isinstance(label, str):
            emotion = ALIASES.get(label.strip().casefold())
            if emotion is None:
                unavailable += 1
            else:
                counts[emotion] += 1
        else:
            unavailable += 1
    normalized = {key: counts.get(key, 0) for key in EMOTIONS}
    total = sum(normalized.values())
    return {
        "version": 2,
        "source": "diary_text_analysis",
        "total": total,
        "pending_count": pending,
        "unavailable_count": unavailable,
        "empty_count": empty,
        "counts": normalized,
        "ratios": {
            key: round(value / total, 4) if total else 0.0
            for key, value in normalized.items()
        },
    }


def _initial_branch(profile: dict, exp: int) -> str | None:
    if exp < 300 or profile["total"] < 3:
        return None
    ranked = sorted(profile["counts"].items(), key=lambda item: item[1], reverse=True)
    if ranked[0][1] == ranked[1][1]:
        return None
    ratio = ranked[0][1] / profile["total"]
    margin = (ranked[0][1] - ranked[1][1]) / profile["total"]
    return ranked[0][0] if ratio >= 0.60 and margin >= 0.20 else None


def upgrade() -> None:
    op.add_column(
        "mood_entries",
        sa.Column(
            "mood_level_explicit",
            sa.Boolean(),
            nullable=False,
            server_default=sa.true(),
        ),
    )
    op.add_column(
        "mood_entries",
        sa.Column("analysis_version", sa.Integer(), nullable=False, server_default="1"),
    )
    op.add_column("plants", sa.Column("growth_branch", sa.String(20), nullable=True))
    op.add_column(
        "plants", sa.Column("branch_decided_at", PRECISE_DATETIME, nullable=True)
    )

    bind = op.get_bind()
    if bind.dialect.name == "mysql":
        op.alter_column(
            "mood_entries",
            "recorded_at_utc",
            existing_type=mysql.DATETIME(),
            type_=mysql.DATETIME(fsp=6),
            existing_nullable=False,
        )
        op.alter_column(
            "plants",
            "planted_at",
            existing_type=mysql.DATETIME(),
            type_=mysql.DATETIME(fsp=6),
            existing_nullable=False,
        )
        op.alter_column(
            "plants",
            "harvested_at",
            existing_type=mysql.DATETIME(),
            type_=mysql.DATETIME(fsp=6),
            existing_nullable=True,
        )
    op.create_index(
        "ix_mood_growth_lifecycle",
        "mood_entries",
        ["user_id", "recorded_at_utc", "id"],
    )

    bind.execute(sa.text("UPDATE mood_entries SET analysis_version = input_version"))

    # 구 worker가 job만 failed로 마감하고 entry를 pending/running에 남긴 뒤
    # 종료된 반쪽 상태는 새 worker가 다시 claim하지 못하므로 여기서 terminal로 맞춘다.
    half_states = bind.execute(
        sa.text(
            "SELECT m.id, j.last_error_code FROM mood_entries AS m "
            "JOIN ai_jobs AS j ON j.resource_id = m.id "
            "AND j.input_version = m.analysis_version "
            "WHERE j.job_type = 'mood_analysis' AND j.status = 'failed' "
            "AND m.analysis_status IN ('pending', 'running')"
        )
    ).mappings()
    for half_state in half_states:
        bind.execute(
            sa.text(
                "UPDATE mood_entries SET analysis_status = 'failed', "
                "analysis_error_code = :error_code WHERE id = :entry_id"
            ),
            {
                "entry_id": half_state["id"],
                "error_code": half_state["last_error_code"] or "CLASSIFIER_UNAVAILABLE",
            },
        )

    plant_rows = bind.execute(
        sa.text(
            "SELECT id, user_id, exp, status, planted_at, harvested_at, final_form "
            "FROM plants"
        )
    ).mappings()
    for plant in plant_rows:
        lifecycle_sql = (
            "SELECT content, analysis_status, ai_emotion FROM mood_entries "
            "WHERE user_id = :user_id AND recorded_at_utc >= :planted_at "
        )
        lifecycle_params = {
            "user_id": plant["user_id"],
            "planted_at": plant["planted_at"],
        }
        if plant["status"] == "harvested":
            lifecycle_sql += "AND recorded_at_utc <= :harvested_at "
            lifecycle_params["harvested_at"] = plant["harvested_at"]
        lifecycle_sql += "ORDER BY recorded_at_utc, id"
        entries = bind.execute(sa.text(lifecycle_sql), lifecycle_params).all()
        profile = _profile(entries)
        if plant["status"] == "harvested":
            branch = (
                BRANCH_BY_FORM.get(plant["final_form"])
                or _initial_branch(profile, int(plant["exp"]))
                or "mixed"
            )
            decided_at = plant["harvested_at"]
        else:
            branch = _initial_branch(profile, int(plant["exp"]))
            decided_at = None
        bind.execute(
            sa.text(
                "UPDATE plants SET emotion_profile = :profile, growth_branch = :branch, "
                "branch_decided_at = CASE WHEN :branch IS NULL THEN NULL "
                "ELSE COALESCE(:decided_at, CURRENT_TIMESTAMP) END "
                "WHERE id = :plant_id"
            ).bindparams(sa.bindparam("profile", type_=sa.JSON())),
            {
                "profile": profile,
                "branch": branch,
                "decided_at": decided_at,
                "plant_id": plant["id"],
            },
        )


def downgrade() -> None:
    op.drop_index("ix_mood_growth_lifecycle", table_name="mood_entries")
    op.drop_column("plants", "branch_decided_at")
    op.drop_column("plants", "growth_branch")
    op.drop_column("mood_entries", "analysis_version")
    op.drop_column("mood_entries", "mood_level_explicit")
    bind = op.get_bind()
    if bind.dialect.name == "mysql":
        op.alter_column(
            "mood_entries",
            "recorded_at_utc",
            existing_type=mysql.DATETIME(fsp=6),
            type_=mysql.DATETIME(),
            existing_nullable=False,
        )
        op.alter_column(
            "plants",
            "planted_at",
            existing_type=mysql.DATETIME(fsp=6),
            type_=mysql.DATETIME(),
            existing_nullable=False,
        )
        op.alter_column(
            "plants",
            "harvested_at",
            existing_type=mysql.DATETIME(fsp=6),
            type_=mysql.DATETIME(),
            existing_nullable=True,
        )
