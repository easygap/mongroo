from datetime import datetime

import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, BigIntPK
from app.core.timeutil import utcnow


class SafetyEvent(Base):
    """안전 이벤트. 원문은 저장하지 않는다 (design.md 4.2)."""

    __tablename__ = "safety_events"

    id: Mapped[int] = mapped_column(BigIntPK, primary_key=True, autoincrement=True)
    user_id: Mapped[int] = mapped_column(
        sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    source: Mapped[str] = mapped_column(sa.String(20), nullable=False)  # mood | chat
    resource_type: Mapped[str] = mapped_column(sa.String(30), nullable=False)
    resource_id: Mapped[int | None] = mapped_column(sa.BigInteger, nullable=True)
    severity: Mapped[str] = mapped_column(sa.String(20), nullable=False)  # concern | imminent
    reason_codes: Mapped[list] = mapped_column(sa.JSON, nullable=False, default=list)
    detector_version: Mapped[str] = mapped_column(sa.String(40), nullable=False)
    action_taken: Mapped[str] = mapped_column(sa.String(40), nullable=False)
    created_at: Mapped[datetime] = mapped_column(sa.DateTime(), default=utcnow, nullable=False)
