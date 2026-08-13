from datetime import date, datetime

import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column

from app.core.timeutil import utcnow
from app.models.base import Base, BigIntPK


class Quest(Base):
    __tablename__ = "quests"

    id: Mapped[int] = mapped_column(BigIntPK, primary_key=True, autoincrement=True)
    code: Mapped[str] = mapped_column(sa.String(40), unique=True, nullable=False)
    title: Mapped[str] = mapped_column(sa.String(80), nullable=False)
    description: Mapped[str] = mapped_column(sa.String(300), nullable=False)
    trigger_rule: Mapped[str] = mapped_column(sa.String(40), nullable=False, default="daily_neutral")
    category: Mapped[str] = mapped_column(sa.String(30), nullable=False)
    burden_level: Mapped[int] = mapped_column(sa.SmallInteger, nullable=False, default=1)
    estimated_minutes: Mapped[int] = mapped_column(sa.Integer, nullable=False)
    safety_tags: Mapped[list] = mapped_column(sa.JSON, nullable=False, default=list)
    reward_exp: Mapped[int] = mapped_column(sa.Integer, nullable=False, default=20)
    reward_seeds: Mapped[int] = mapped_column(sa.Integer, nullable=False, default=5)
    is_active: Mapped[bool] = mapped_column(sa.Boolean, nullable=False, default=True)


class UserQuest(Base):
    __tablename__ = "user_quests"
    __table_args__ = (
        sa.UniqueConstraint("user_id", "quest_date", name="uq_user_quest_day"),
        sa.CheckConstraint(
            "status IN ('assigned','completed','skipped')", name="ck_user_quest_status"
        ),
    )

    id: Mapped[int] = mapped_column(BigIntPK, primary_key=True, autoincrement=True)
    user_id: Mapped[int] = mapped_column(
        sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    quest_id: Mapped[int] = mapped_column(
        sa.ForeignKey("quests.id", ondelete="RESTRICT"), nullable=False
    )
    quest_date: Mapped[date] = mapped_column(sa.Date, nullable=False)
    status: Mapped[str] = mapped_column(sa.String(20), nullable=False, default="assigned")
    completed_at: Mapped[datetime | None] = mapped_column(sa.DateTime(), nullable=True)


class Item(Base):
    __tablename__ = "items"
    __table_args__ = (
        sa.CheckConstraint(
            "type IN ('deco','room_theme','main_character','companion',"
            "'species_unlock','wardrobe','skill_book')",
            name="ck_item_type",
        ),
        sa.CheckConstraint("price_seeds >= 0", name="ck_item_price_nonnegative"),
    )

    id: Mapped[int] = mapped_column(BigIntPK, primary_key=True, autoincrement=True)
    code: Mapped[str] = mapped_column(sa.String(40), unique=True, nullable=False)
    type: Mapped[str] = mapped_column(sa.String(30), nullable=False)
    name: Mapped[str] = mapped_column(sa.String(80), nullable=False)
    description: Mapped[str] = mapped_column(sa.String(300), nullable=False, default="")
    price_seeds: Mapped[int] = mapped_column(sa.Integer, nullable=False)
    rarity: Mapped[int] = mapped_column(sa.SmallInteger, nullable=False, default=1)
    asset_manifest: Mapped[dict] = mapped_column(sa.JSON, nullable=False, default=dict)
    is_active: Mapped[bool] = mapped_column(sa.Boolean, nullable=False, default=True)


class UserItem(Base):
    __tablename__ = "user_items"
    __table_args__ = (
        sa.UniqueConstraint("user_id", "item_id", name="uq_user_item_catalog"),
    )

    id: Mapped[int] = mapped_column(BigIntPK, primary_key=True, autoincrement=True)
    user_id: Mapped[int] = mapped_column(
        sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    item_id: Mapped[int] = mapped_column(
        sa.ForeignKey("items.id", ondelete="RESTRICT"), nullable=False
    )
    acquired_at: Mapped[datetime] = mapped_column(sa.DateTime(), default=utcnow, nullable=False)


class FarmLayout(Base):
    __tablename__ = "farm_layouts"

    user_id: Mapped[int] = mapped_column(
        sa.ForeignKey("users.id", ondelete="CASCADE"), primary_key=True
    )
    version: Mapped[int] = mapped_column(sa.Integer, nullable=False, default=0)
    layout: Mapped[dict] = mapped_column(sa.JSON, nullable=False, default=dict)
    updated_at: Mapped[datetime] = mapped_column(
        sa.DateTime(), default=utcnow, onupdate=utcnow, nullable=False
    )


class UserSpeciesUnlock(Base):
    __tablename__ = "user_species_unlocks"
    __table_args__ = (
        sa.UniqueConstraint("user_id", "species_id", name="uq_user_species_unlock"),
    )

    id: Mapped[int] = mapped_column(BigIntPK, primary_key=True, autoincrement=True)
    user_id: Mapped[int] = mapped_column(
        sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    species_id: Mapped[int] = mapped_column(
        sa.ForeignKey("plant_species.id", ondelete="RESTRICT"), nullable=False
    )
    unlocked_at: Mapped[datetime] = mapped_column(sa.DateTime(), default=utcnow, nullable=False)
