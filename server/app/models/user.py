from datetime import date, datetime

import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, BigIntPK, TimestampMixin
from app.core.timeutil import utcnow


class User(TimestampMixin, Base):
    __tablename__ = "users"
    __table_args__ = (
        sa.CheckConstraint("seed_balance >= 0", name="ck_user_seed_balance_nonnegative"),
    )

    id: Mapped[int] = mapped_column(BigIntPK, primary_key=True, autoincrement=True)
    email: Mapped[str] = mapped_column(sa.String(255), unique=True, nullable=False)
    password_hash: Mapped[str] = mapped_column(sa.String(255), nullable=False)
    nickname: Mapped[str] = mapped_column(sa.String(30), nullable=False)
    timezone: Mapped[str] = mapped_column(sa.String(64), nullable=False, default="Asia/Seoul")
    seed_balance: Mapped[int] = mapped_column(sa.Integer, nullable=False, default=0)
    streak_days: Mapped[int] = mapped_column(sa.Integer, nullable=False, default=0)
    last_recorded_local_date: Mapped[date | None] = mapped_column(sa.Date, nullable=True)
    terms_version: Mapped[str | None] = mapped_column(sa.String(32), nullable=True)
    privacy_version: Mapped[str | None] = mapped_column(sa.String(32), nullable=True)
    sensitive_consent_version: Mapped[str | None] = mapped_column(
        sa.String(32), nullable=True
    )
    age_confirmed_at: Mapped[datetime | None] = mapped_column(
        sa.DateTime(), nullable=True
    )
    consented_at: Mapped[datetime | None] = mapped_column(sa.DateTime(), nullable=True)


class AuthSession(Base):
    __tablename__ = "auth_sessions"

    id: Mapped[int] = mapped_column(BigIntPK, primary_key=True, autoincrement=True)
    user_id: Mapped[int] = mapped_column(
        sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    session_family: Mapped[str] = mapped_column(sa.String(64), unique=True, nullable=False)
    expires_at: Mapped[datetime] = mapped_column(sa.DateTime(), nullable=False)
    revoked_at: Mapped[datetime | None] = mapped_column(sa.DateTime(), nullable=True)
    created_at: Mapped[datetime] = mapped_column(sa.DateTime(), default=utcnow, nullable=False)


class RefreshToken(Base):
    __tablename__ = "refresh_tokens"

    id: Mapped[int] = mapped_column(BigIntPK, primary_key=True, autoincrement=True)
    session_id: Mapped[int] = mapped_column(
        sa.ForeignKey("auth_sessions.id", ondelete="CASCADE"), nullable=False, index=True
    )
    jti_hash: Mapped[str] = mapped_column(sa.String(64), unique=True, nullable=False)
    expires_at: Mapped[datetime] = mapped_column(sa.DateTime(), nullable=False)
    used_at: Mapped[datetime | None] = mapped_column(sa.DateTime(), nullable=True)
    revoked_at: Mapped[datetime | None] = mapped_column(sa.DateTime(), nullable=True)
    replaced_by_id: Mapped[int | None] = mapped_column(sa.BigInteger, nullable=True)
    created_at: Mapped[datetime] = mapped_column(sa.DateTime(), default=utcnow, nullable=False)


class LoginRateLimit(Base):
    """이메일·IP HMAC 키별 로그인 실패 횟수. 원문 식별자는 저장하지 않는다."""

    __tablename__ = "login_rate_limits"
    __table_args__ = (
        sa.CheckConstraint(
            "failure_count >= 0", name="ck_login_rate_limit_nonnegative"
        ),
        sa.Index("ix_login_rate_limits_updated_at", "updated_at"),
    )

    rate_key: Mapped[str] = mapped_column(sa.String(64), primary_key=True)
    failure_count: Mapped[int] = mapped_column(
        sa.Integer, nullable=False, default=0, server_default="0"
    )
    window_started_at: Mapped[datetime] = mapped_column(sa.DateTime(), nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        sa.DateTime(), default=utcnow, onupdate=utcnow, nullable=False
    )
