from datetime import date

import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column

from app.core.field_encryption import ProtectedJSON
from app.models.base import Base, BigIntPK, TimestampMixin
from app.models.enums import ReportStatus


class Report(TimestampMixin, Base):
    __tablename__ = "reports"
    __table_args__ = (
        sa.UniqueConstraint(
            "user_id", "period_type", "period_start", "input_hash", name="uq_report_input"
        ),
    )

    id: Mapped[int] = mapped_column(BigIntPK, primary_key=True, autoincrement=True)
    user_id: Mapped[int] = mapped_column(
        sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    period_type: Mapped[str] = mapped_column(sa.String(10), nullable=False)  # weekly | monthly
    period_start: Mapped[date] = mapped_column(sa.Date, nullable=False)
    period_end: Mapped[date] = mapped_column(sa.Date, nullable=False)
    input_hash: Mapped[str] = mapped_column(sa.String(64), nullable=False)
    status: Mapped[str] = mapped_column(sa.String(20), nullable=False, default=ReportStatus.PENDING)
    stats: Mapped[dict] = mapped_column(
        ProtectedJSON("reports.stats"), nullable=False, default=dict
    )
    analysis_coverage: Mapped[float] = mapped_column(sa.Float, nullable=False, default=0.0)
    summary: Mapped[dict | None] = mapped_column(
        ProtectedJSON("reports.summary"), nullable=True
    )
    summary_model_version: Mapped[str | None] = mapped_column(sa.String(80), nullable=True)
    error_code: Mapped[str | None] = mapped_column(sa.String(40), nullable=True)
