from datetime import datetime

import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, BigIntPK
from app.core.timeutil import utcnow


class RewardEvent(Base):
    """보상 원장. 잔액·경험치의 유일한 근거 (design.md 7.3)."""

    __tablename__ = "reward_events"

    id: Mapped[int] = mapped_column(BigIntPK, primary_key=True, autoincrement=True)
    user_id: Mapped[int] = mapped_column(
        sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    plant_id: Mapped[int | None] = mapped_column(
        sa.ForeignKey("plants.id", ondelete="SET NULL"), nullable=True
    )
    event_type: Mapped[str] = mapped_column(sa.String(30), nullable=False)
    source_type: Mapped[str] = mapped_column(sa.String(30), nullable=False)
    source_id: Mapped[int | None] = mapped_column(sa.BigInteger, nullable=True)
    dedupe_key: Mapped[str] = mapped_column(sa.String(120), unique=True, nullable=False)
    exp_delta: Mapped[int] = mapped_column(sa.Integer, nullable=False, default=0)
    seed_delta: Mapped[int] = mapped_column(sa.Integer, nullable=False, default=0)
    seed_balance_after: Mapped[int] = mapped_column(sa.Integer, nullable=False)
    created_at: Mapped[datetime] = mapped_column(sa.DateTime(), default=utcnow, nullable=False)
