from datetime import date, datetime

import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column

from app.core.field_encryption import ProtectedText
from app.core.timeutil import utcnow
from app.models.base import Base, BigIntPK, PreciseDateTime


class AdventurePatrol(Base):
    __tablename__ = "adventure_patrols"
    __table_args__ = (
        sa.UniqueConstraint("user_id", "local_date", name="uq_adventure_patrol_day"),
        sa.CheckConstraint(
            "status IN ('active','claimed')", name="ck_adventure_patrol_status"
        ),
        sa.CheckConstraint(
            "reward_exp >= 0 AND reward_seeds >= 0",
            name="ck_adventure_patrol_reward_nonnegative",
        ),
    )

    id: Mapped[int] = mapped_column(BigIntPK, primary_key=True, autoincrement=True)
    user_id: Mapped[int] = mapped_column(
        sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    plant_id: Mapped[int] = mapped_column(
        sa.ForeignKey("plants.id", ondelete="RESTRICT"), nullable=False
    )
    route_code: Mapped[str] = mapped_column(sa.String(40), nullable=False)
    local_date: Mapped[date] = mapped_column(sa.Date, nullable=False)
    status: Mapped[str] = mapped_column(sa.String(20), nullable=False, default="active")
    started_at: Mapped[datetime] = mapped_column(
        PreciseDateTime, nullable=False, default=utcnow
    )
    returns_at: Mapped[datetime] = mapped_column(PreciseDateTime, nullable=False)
    claimed_at: Mapped[datetime | None] = mapped_column(PreciseDateTime, nullable=True)
    reward_exp: Mapped[int] = mapped_column(sa.Integer, nullable=False, default=0)
    reward_seeds: Mapped[int] = mapped_column(sa.Integer, nullable=False, default=3)
    discovery_code: Mapped[str | None] = mapped_column(sa.String(40), nullable=True)
    encounter_code: Mapped[str | None] = mapped_column(sa.String(40), nullable=True)
    encounter_title: Mapped[str | None] = mapped_column(sa.String(100), nullable=True)
    encounter_text: Mapped[str | None] = mapped_column(sa.Text, nullable=True)
    reaction_form: Mapped[str | None] = mapped_column(sa.String(20), nullable=True)
    reaction_speaker: Mapped[str | None] = mapped_column(
        ProtectedText("adventure_patrols.reaction_speaker"), nullable=True
    )
    reaction_text: Mapped[str | None] = mapped_column(sa.Text, nullable=True)
    found_item_code: Mapped[str] = mapped_column(sa.String(40), nullable=False)
    found_quantity: Mapped[int] = mapped_column(sa.Integer, nullable=False, default=1)
    performance_score: Mapped[int] = mapped_column(sa.Integer, nullable=False)


class UserDungeon(Base):
    __tablename__ = "user_dungeons"
    __table_args__ = (
        sa.UniqueConstraint("user_id", "dungeon_code", name="uq_user_dungeon"),
        sa.CheckConstraint("clear_count >= 0", name="ck_user_dungeon_clear_count"),
    )

    id: Mapped[int] = mapped_column(BigIntPK, primary_key=True, autoincrement=True)
    user_id: Mapped[int] = mapped_column(
        sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    dungeon_code: Mapped[str] = mapped_column(sa.String(40), nullable=False)
    discovered_at: Mapped[datetime] = mapped_column(
        PreciseDateTime, nullable=False, default=utcnow
    )
    clear_count: Mapped[int] = mapped_column(sa.Integer, nullable=False, default=0)
    last_cleared_at: Mapped[datetime | None] = mapped_column(
        PreciseDateTime, nullable=True
    )


class DungeonRun(Base):
    __tablename__ = "dungeon_runs"
    __table_args__ = (
        sa.UniqueConstraint("user_id", "local_date", name="uq_dungeon_run_day"),
        sa.CheckConstraint(
            "reward_exp >= 0 AND reward_seeds >= 0",
            name="ck_dungeon_run_reward_nonnegative",
        ),
    )

    id: Mapped[int] = mapped_column(BigIntPK, primary_key=True, autoincrement=True)
    user_id: Mapped[int] = mapped_column(
        sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    plant_id: Mapped[int] = mapped_column(
        sa.ForeignKey("plants.id", ondelete="RESTRICT"), nullable=False
    )
    user_dungeon_id: Mapped[int] = mapped_column(
        sa.ForeignKey("user_dungeons.id", ondelete="CASCADE"), nullable=False
    )
    local_date: Mapped[date] = mapped_column(sa.Date, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        PreciseDateTime, nullable=False, default=utcnow
    )
    reward_exp: Mapped[int] = mapped_column(sa.Integer, nullable=False, default=10)
    reward_seeds: Mapped[int] = mapped_column(sa.Integer, nullable=False, default=4)
    found_item_code: Mapped[str] = mapped_column(sa.String(40), nullable=False)
    found_quantity: Mapped[int] = mapped_column(sa.Integer, nullable=False, default=1)
    performance_score: Mapped[int] = mapped_column(sa.Integer, nullable=False)
    approach_code: Mapped[str] = mapped_column(
        sa.String(40), nullable=False, default="steady"
    )
    approach_stat: Mapped[str | None] = mapped_column(sa.String(20), nullable=True)
    outcome_code: Mapped[str] = mapped_column(
        sa.String(20), nullable=False, default="steady"
    )
    scene_code: Mapped[str | None] = mapped_column(sa.String(40), nullable=True)
    scene_title: Mapped[str | None] = mapped_column(sa.String(100), nullable=True)
    scene_text: Mapped[str | None] = mapped_column(sa.Text, nullable=True)


class UserAdventureItem(Base):
    __tablename__ = "user_adventure_items"
    __table_args__ = (
        sa.UniqueConstraint("user_id", "item_code", name="uq_user_adventure_item"),
        sa.CheckConstraint("quantity >= 0", name="ck_adventure_item_quantity"),
    )

    id: Mapped[int] = mapped_column(BigIntPK, primary_key=True, autoincrement=True)
    user_id: Mapped[int] = mapped_column(
        sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    item_code: Mapped[str] = mapped_column(sa.String(40), nullable=False)
    quantity: Mapped[int] = mapped_column(sa.Integer, nullable=False, default=0)
    updated_at: Mapped[datetime] = mapped_column(
        PreciseDateTime, nullable=False, default=utcnow, onupdate=utcnow
    )


class UserAdventureResearch(Base):
    __tablename__ = "user_adventure_research"
    __table_args__ = (
        sa.UniqueConstraint(
            "user_id", "project_code", name="uq_user_adventure_research"
        ),
    )

    id: Mapped[int] = mapped_column(BigIntPK, primary_key=True, autoincrement=True)
    user_id: Mapped[int] = mapped_column(
        sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    project_code: Mapped[str] = mapped_column(sa.String(40), nullable=False)
    completed_at: Mapped[datetime] = mapped_column(
        PreciseDateTime, nullable=False, default=utcnow
    )
