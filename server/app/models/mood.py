from datetime import date, datetime

import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, BigIntPK, PreciseDateTime, TimestampMixin
from app.models.enums import AnalysisStatus


class MoodEntry(TimestampMixin, Base):
    __tablename__ = "mood_entries"
    __table_args__ = (
        sa.CheckConstraint("mood_level BETWEEN 1 AND 5", name="ck_mood_level"),
        sa.Index("ix_mood_user_date", "user_id", "local_date", "recorded_at_utc"),
        sa.Index("ix_mood_growth_lifecycle", "user_id", "recorded_at_utc", "id"),
    )

    id: Mapped[int] = mapped_column(BigIntPK, primary_key=True, autoincrement=True)
    user_id: Mapped[int] = mapped_column(
        sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    local_date: Mapped[date] = mapped_column(sa.Date, nullable=False)
    recorded_at_utc: Mapped[datetime] = mapped_column(PreciseDateTime, nullable=False)
    mood_level: Mapped[int] = mapped_column(sa.SmallInteger, nullable=False)
    # false면 content-only 요청을 기존 NOT NULL 스키마에 저장하기 위한 내부 3이다.
    # 캘린더/리포트/채팅에서 사용자가 직접 고른 기분처럼 집계하지 않는다.
    mood_level_explicit: Mapped[bool] = mapped_column(
        sa.Boolean, nullable=False, default=True, server_default=sa.true()
    )
    emotion_tags: Mapped[list] = mapped_column(sa.JSON, nullable=False, default=list)
    content: Mapped[str | None] = mapped_column(sa.Text, nullable=True)
    # 사용자 편집만 증가시키는 낙관적 잠금 버전이다. AI 분석 상태처럼 백그라운드
    # 메타데이터가 updated_at을 바꿔도 사용자의 편집 토큰은 흔들리지 않는다.
    edit_version: Mapped[int] = mapped_column(
        sa.Integer, nullable=False, default=1, server_default="1"
    )
    input_version: Mapped[int] = mapped_column(sa.Integer, nullable=False, default=1)
    # 본문 분류 job의 낙관적 버전. input_version은 리포트 stale 판정을 위해
    # 기분/태그 수정에도 증가하지만, 이 값은 일기 본문이 바뀔 때만 증가한다.
    analysis_version: Mapped[int] = mapped_column(
        sa.Integer, nullable=False, default=1, server_default="1"
    )
    analysis_status: Mapped[str] = mapped_column(
        sa.String(20), nullable=False, default=AnalysisStatus.NOT_REQUESTED
    )
    ai_emotion: Mapped[str | None] = mapped_column(sa.String(20), nullable=True)
    ai_scores: Mapped[dict | None] = mapped_column(sa.JSON, nullable=True)
    ai_emotion_override: Mapped[str | None] = mapped_column(
        sa.String(20), nullable=True
    )
    ai_label_hidden: Mapped[bool] = mapped_column(
        sa.Boolean, nullable=False, default=False
    )
    analysis_model_version: Mapped[str | None] = mapped_column(
        sa.String(80), nullable=True
    )
    analyzed_at: Mapped[datetime | None] = mapped_column(sa.DateTime(), nullable=True)
    analysis_error_code: Mapped[str | None] = mapped_column(
        sa.String(40), nullable=True
    )
