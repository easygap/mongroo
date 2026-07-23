from datetime import datetime

import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, BigIntPK, PreciseDateTime, TimestampMixin
from app.models.enums import PlantStatus


class PlantSpecies(Base):
    __tablename__ = "plant_species"

    id: Mapped[int] = mapped_column(BigIntPK, primary_key=True, autoincrement=True)
    code: Mapped[str] = mapped_column(sa.String(40), unique=True, nullable=False)
    name: Mapped[str] = mapped_column(sa.String(40), nullable=False)
    persona_key: Mapped[str] = mapped_column(sa.String(40), nullable=False)
    asset_manifest: Mapped[dict] = mapped_column(sa.JSON, nullable=False, default=dict)
    rarity: Mapped[int] = mapped_column(sa.SmallInteger, nullable=False, default=1)
    unlock_price: Mapped[int] = mapped_column(sa.Integer, nullable=False, default=0)


class Plant(TimestampMixin, Base):
    __tablename__ = "plants"
    __table_args__ = (
        sa.Index(
            "ix_plants_museum",
            "user_id",
            "museum_featured",
            "harvested_at",
        ),
    )
    # 활성 식물 1개 제약은 마이그레이션에서 dialect별로 강제한다 (design.md 4.1)

    id: Mapped[int] = mapped_column(BigIntPK, primary_key=True, autoincrement=True)
    user_id: Mapped[int] = mapped_column(
        sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    species_id: Mapped[int] = mapped_column(
        sa.ForeignKey("plant_species.id", ondelete="RESTRICT"), nullable=False
    )
    name: Mapped[str] = mapped_column(sa.String(20), nullable=False)
    exp: Mapped[int] = mapped_column(sa.Integer, nullable=False, default=0)
    status: Mapped[str] = mapped_column(
        sa.String(20), nullable=False, default=PlantStatus.ACTIVE
    )
    planted_at: Mapped[datetime] = mapped_column(PreciseDateTime, nullable=False)
    harvested_at: Mapped[datetime | None] = mapped_column(
        PreciseDateTime, nullable=True
    )
    # 활성 식물에서는 분석이 끝난 일기 본문만 누적한 현재 프로필이고, 수확 뒤에는
    # 생애 마지막 스냅샷이다. 점수·태그·사용자 교정값은 이 값에 들어가지 않는다.
    final_form: Mapped[str | None] = mapped_column(sa.String(20), nullable=True)
    emotion_profile: Mapped[dict | None] = mapped_column(sa.JSON, nullable=True)
    # 3단계부터 충분한 본문 분석 표본이 모이면 정한다. 새 감정이 조금 추가되는
    # 정도로 외형과 성격이 오락가락하지 않도록 서비스 계층에서 히스테리시스를 둔다.
    growth_branch: Mapped[str | None] = mapped_column(sa.String(20), nullable=True)
    branch_decided_at: Mapped[datetime | None] = mapped_column(
        PreciseDateTime, nullable=True
    )
    museum_featured: Mapped[bool] = mapped_column(
        sa.Boolean, nullable=False, default=False, server_default=sa.false()
    )
