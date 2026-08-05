from datetime import datetime

import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column

from app.core.field_encryption import ProtectedJSON
from app.models.base import Base, BigIntPK
from app.models.enums import JobStatus
from app.core.timeutil import utcnow


class AiJob(Base):
    """감정 분석·대화 생성·리포트 요약의 영속 큐 (design.md 5.4)."""

    __tablename__ = "ai_jobs"
    __table_args__ = (
        sa.UniqueConstraint(
            "job_type",
            "resource_type",
            "resource_id",
            "input_version",
            name="uq_ai_job_input",
        ),
        sa.Index("ix_ai_jobs_claim", "status", "available_at"),
    )

    id: Mapped[int] = mapped_column(BigIntPK, primary_key=True, autoincrement=True)
    user_id: Mapped[int] = mapped_column(
        sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    job_type: Mapped[str] = mapped_column(sa.String(30), nullable=False)
    resource_type: Mapped[str] = mapped_column(sa.String(30), nullable=False)
    resource_id: Mapped[int] = mapped_column(sa.BigInteger, nullable=False)
    input_version: Mapped[int] = mapped_column(sa.Integer, nullable=False, default=1)
    status: Mapped[str] = mapped_column(
        sa.String(20), nullable=False, default=JobStatus.PENDING
    )
    attempts: Mapped[int] = mapped_column(sa.Integer, nullable=False, default=0)
    available_at: Mapped[datetime] = mapped_column(
        sa.DateTime(), default=utcnow, nullable=False
    )
    locked_at: Mapped[datetime | None] = mapped_column(sa.DateTime(), nullable=True)
    last_error_code: Mapped[str | None] = mapped_column(sa.String(40), nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        sa.DateTime(), default=utcnow, nullable=False
    )


class IdempotencyKey(Base):
    __tablename__ = "idempotency_keys"
    __table_args__ = (
        sa.UniqueConstraint(
            "user_id", "route_scope", "idempotency_key", name="uq_idem_key"
        ),
    )

    id: Mapped[int] = mapped_column(BigIntPK, primary_key=True, autoincrement=True)
    user_id: Mapped[int] = mapped_column(
        sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    route_scope: Mapped[str] = mapped_column(sa.String(40), nullable=False)
    idempotency_key: Mapped[str] = mapped_column(sa.String(64), nullable=False)
    request_hash: Mapped[str] = mapped_column(sa.String(64), nullable=False)
    response_status: Mapped[int] = mapped_column(sa.Integer, nullable=False)
    response_body: Mapped[dict] = mapped_column(
        ProtectedJSON("idempotency_keys.response_body"), nullable=False
    )
    created_at: Mapped[datetime] = mapped_column(
        sa.DateTime(), default=utcnow, nullable=False
    )


class WorkerHeartbeat(Base):
    """AI worker 생존 확인용. /health/ready에서 조회한다."""

    __tablename__ = "worker_heartbeats"

    worker_name: Mapped[str] = mapped_column(sa.String(40), primary_key=True)
    beat_at: Mapped[datetime] = mapped_column(
        sa.DateTime(), default=utcnow, nullable=False
    )


class DataProtectionState(Base):
    """전수 암호화 검사가 끝났음을 readiness에 O(1)로 전달한다."""

    __tablename__ = "data_protection_states"

    protection_key: Mapped[str] = mapped_column(sa.String(64), primary_key=True)
    schema_revision: Mapped[str] = mapped_column(sa.String(64), nullable=False)
    active_key_id: Mapped[str] = mapped_column(sa.String(32), nullable=False)
    remaining_plaintext: Mapped[int] = mapped_column(sa.Integer, nullable=False)
    verified_at: Mapped[datetime] = mapped_column(sa.DateTime(), nullable=False)
