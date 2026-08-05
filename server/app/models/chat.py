from datetime import datetime

import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column

from app.core.field_encryption import ProtectedText
from app.models.base import Base, BigIntPK
from app.models.enums import ChatSessionStatus, ReflectionStage, RunStatus, SafetyState
from app.core.timeutil import utcnow


class ChatSession(Base):
    __tablename__ = "chat_sessions"

    id: Mapped[int] = mapped_column(BigIntPK, primary_key=True, autoincrement=True)
    user_id: Mapped[int] = mapped_column(
        sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    plant_id: Mapped[int] = mapped_column(
        sa.ForeignKey("plants.id", ondelete="CASCADE"), nullable=False
    )
    reflection_stage: Mapped[str] = mapped_column(
        sa.String(20), nullable=False, default=ReflectionStage.GREETING
    )
    safety_state: Mapped[str] = mapped_column(
        sa.String(20), nullable=False, default=SafetyState.NORMAL
    )
    status: Mapped[str] = mapped_column(
        sa.String(20), nullable=False, default=ChatSessionStatus.ACTIVE
    )
    started_at: Mapped[datetime] = mapped_column(sa.DateTime(), default=utcnow, nullable=False)
    ended_at: Mapped[datetime | None] = mapped_column(sa.DateTime(), nullable=True)
    last_message_at: Mapped[datetime | None] = mapped_column(sa.DateTime(), nullable=True)


class ChatMessage(Base):
    __tablename__ = "chat_messages"
    __table_args__ = (sa.Index("ix_chat_messages_session", "session_id", "created_at"),)

    id: Mapped[int] = mapped_column(BigIntPK, primary_key=True, autoincrement=True)
    session_id: Mapped[int] = mapped_column(
        sa.ForeignKey("chat_sessions.id", ondelete="CASCADE"), nullable=False
    )
    role: Mapped[str] = mapped_column(sa.String(10), nullable=False)  # user | plant
    content: Mapped[str] = mapped_column(
        ProtectedText("chat_messages.content"), nullable=False
    )
    safety_status: Mapped[str] = mapped_column(sa.String(20), nullable=False, default="normal")
    ai_emotion: Mapped[str | None] = mapped_column(sa.String(20), nullable=True)
    model_version: Mapped[str | None] = mapped_column(sa.String(80), nullable=True)
    created_at: Mapped[datetime] = mapped_column(sa.DateTime(), default=utcnow, nullable=False)


class ChatRun(Base):
    __tablename__ = "chat_runs"

    id: Mapped[int] = mapped_column(BigIntPK, primary_key=True, autoincrement=True)
    session_id: Mapped[int] = mapped_column(
        sa.ForeignKey("chat_sessions.id", ondelete="CASCADE"), nullable=False, index=True
    )
    user_message_id: Mapped[int] = mapped_column(
        sa.ForeignKey("chat_messages.id", ondelete="CASCADE"), nullable=False
    )
    assistant_message_id: Mapped[int | None] = mapped_column(
        sa.ForeignKey("chat_messages.id", ondelete="SET NULL"), nullable=True
    )
    client_message_id: Mapped[str] = mapped_column(sa.String(64), unique=True, nullable=False)
    status: Mapped[str] = mapped_column(sa.String(20), nullable=False, default=RunStatus.QUEUED)
    error_code: Mapped[str | None] = mapped_column(sa.String(40), nullable=True)
    created_at: Mapped[datetime] = mapped_column(sa.DateTime(), default=utcnow, nullable=False)
    finished_at: Mapped[datetime | None] = mapped_column(sa.DateTime(), nullable=True)
