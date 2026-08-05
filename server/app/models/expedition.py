from datetime import date, datetime

import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column

from app.core.timeutil import utcnow
from app.models.base import Base, BigIntPK, PreciseDateTime


class ExpeditionRun(Base):
    __tablename__ = "expedition_runs"
    __table_args__ = (
        sa.CheckConstraint(
            "status IN ('active','completed','retreated','safe_returned')",
            name="ck_expedition_run_status",
        ),
        sa.CheckConstraint(
            "phase IN ('exploring','awaiting_event','camp')",
            name="ck_expedition_run_phase",
        ),
        sa.CheckConstraint(
            "trail_light BETWEEN 0 AND 12", name="ck_expedition_trail_light"
        ),
        sa.CheckConstraint("resolve BETWEEN 0 AND 6", name="ck_expedition_resolve"),
    )

    id: Mapped[int] = mapped_column(BigIntPK, primary_key=True, autoincrement=True)
    user_id: Mapped[int] = mapped_column(
        sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    region_code: Mapped[str] = mapped_column(sa.String(40), nullable=False)
    mode: Mapped[str] = mapped_column(sa.String(24), nullable=False)
    status: Mapped[str] = mapped_column(sa.String(24), nullable=False, default="active")
    phase: Mapped[str] = mapped_column(
        sa.String(24), nullable=False, default="exploring"
    )
    local_date: Mapped[date] = mapped_column(sa.Date, nullable=False)
    content_version: Mapped[str] = mapped_column(sa.String(32), nullable=False)
    map_seed: Mapped[str] = mapped_column(sa.String(64), nullable=False)
    map_snapshot: Mapped[dict] = mapped_column(sa.JSON, nullable=False)
    run_thread_snapshot: Mapped[dict] = mapped_column(sa.JSON, nullable=False)
    run_memory_snapshot: Mapped[dict] = mapped_column(sa.JSON, nullable=False)
    spotlight_snapshot: Mapped[list] = mapped_column(sa.JSON, nullable=False)
    runtime_effects_snapshot: Mapped[dict] = mapped_column(sa.JSON, nullable=False)
    current_node_code: Mapped[str] = mapped_column(sa.String(40), nullable=False)
    trail_light: Mapped[int] = mapped_column(
        sa.SmallInteger, nullable=False, default=10
    )
    resolve: Mapped[int] = mapped_column(sa.SmallInteger, nullable=False, default=6)
    objective_secured: Mapped[bool] = mapped_column(
        sa.Boolean, nullable=False, default=False, server_default=sa.false()
    )
    reward_eligible: Mapped[bool] = mapped_column(
        sa.Boolean, nullable=False, default=False, server_default=sa.false()
    )
    revision: Mapped[int] = mapped_column(sa.Integer, nullable=False, default=0)
    started_at: Mapped[datetime] = mapped_column(
        PreciseDateTime, nullable=False, default=utcnow
    )
    completed_at: Mapped[datetime | None] = mapped_column(
        PreciseDateTime, nullable=True
    )
    summary_snapshot: Mapped[dict | None] = mapped_column(sa.JSON, nullable=True)
    home_reflection_seen_at: Mapped[datetime | None] = mapped_column(
        PreciseDateTime, nullable=True
    )


class UserActiveExpedition(Base):
    __tablename__ = "user_active_expeditions"

    user_id: Mapped[int] = mapped_column(
        sa.ForeignKey("users.id", ondelete="CASCADE"), primary_key=True
    )
    run_id: Mapped[int] = mapped_column(
        sa.ForeignKey("expedition_runs.id", ondelete="CASCADE"),
        nullable=False,
        unique=True,
    )
    created_at: Mapped[datetime] = mapped_column(
        PreciseDateTime, nullable=False, default=utcnow
    )


class ExpeditionPartyMember(Base):
    __tablename__ = "expedition_party_members"
    __table_args__ = (
        sa.UniqueConstraint("run_id", "position", name="uq_expedition_party_position"),
        sa.UniqueConstraint("run_id", "plant_id", name="uq_expedition_party_plant"),
    )

    id: Mapped[int] = mapped_column(BigIntPK, primary_key=True, autoincrement=True)
    run_id: Mapped[int] = mapped_column(
        sa.ForeignKey("expedition_runs.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    position: Mapped[int] = mapped_column(sa.SmallInteger, nullable=False)
    plant_id: Mapped[int | None] = mapped_column(
        sa.ForeignKey("plants.id", ondelete="RESTRICT"), nullable=True
    )
    is_guide: Mapped[bool] = mapped_column(
        sa.Boolean, nullable=False, default=False, server_default=sa.false()
    )
    snapshot: Mapped[dict] = mapped_column(sa.JSON, nullable=False)
    signature_used: Mapped[bool] = mapped_column(
        sa.Boolean, nullable=False, default=False, server_default=sa.false()
    )
    form_used: Mapped[bool] = mapped_column(
        sa.Boolean, nullable=False, default=False, server_default=sa.false()
    )


class ExpeditionNodeState(Base):
    __tablename__ = "expedition_node_states"
    __table_args__ = (
        sa.UniqueConstraint("run_id", "node_code", name="uq_expedition_node"),
        sa.CheckConstraint(
            "status IN ('hidden','revealed','visited','resolved')",
            name="ck_expedition_node_status",
        ),
    )

    id: Mapped[int] = mapped_column(BigIntPK, primary_key=True, autoincrement=True)
    run_id: Mapped[int] = mapped_column(
        sa.ForeignKey("expedition_runs.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    node_code: Mapped[str] = mapped_column(sa.String(40), nullable=False)
    status: Mapped[str] = mapped_column(sa.String(20), nullable=False)
    event_code: Mapped[str | None] = mapped_column(sa.String(40), nullable=True)
    entered_at: Mapped[datetime | None] = mapped_column(PreciseDateTime, nullable=True)
    resolved_at: Mapped[datetime | None] = mapped_column(PreciseDateTime, nullable=True)
    outcome_code: Mapped[str | None] = mapped_column(sa.String(20), nullable=True)
    acting_member_id: Mapped[int | None] = mapped_column(
        sa.ForeignKey("expedition_party_members.id", ondelete="SET NULL"), nullable=True
    )
    story_snapshot: Mapped[dict | None] = mapped_column(sa.JSON, nullable=True)


class ExpeditionAction(Base):
    __tablename__ = "expedition_actions"
    __table_args__ = (
        sa.UniqueConstraint(
            "run_id", "action_index", name="uq_expedition_action_index"
        ),
        sa.UniqueConstraint(
            "run_id", "client_action_id", name="uq_expedition_client_action"
        ),
    )

    id: Mapped[int] = mapped_column(BigIntPK, primary_key=True, autoincrement=True)
    run_id: Mapped[int] = mapped_column(
        sa.ForeignKey("expedition_runs.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    action_index: Mapped[int] = mapped_column(sa.Integer, nullable=False)
    client_action_id: Mapped[str] = mapped_column(sa.String(64), nullable=False)
    expected_revision: Mapped[int] = mapped_column(sa.Integer, nullable=False)
    action_type: Mapped[str] = mapped_column(sa.String(24), nullable=False)
    request_payload: Mapped[dict] = mapped_column(sa.JSON, nullable=False)
    result_payload: Mapped[dict] = mapped_column(sa.JSON, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        PreciseDateTime, nullable=False, default=utcnow
    )


class ExpeditionLoot(Base):
    __tablename__ = "expedition_loot"
    __table_args__ = (
        sa.UniqueConstraint(
            "run_id", "node_code", "item_code", "loot_kind", name="uq_expedition_loot"
        ),
    )

    id: Mapped[int] = mapped_column(BigIntPK, primary_key=True, autoincrement=True)
    run_id: Mapped[int] = mapped_column(
        sa.ForeignKey("expedition_runs.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    node_code: Mapped[str] = mapped_column(sa.String(40), nullable=False)
    item_code: Mapped[str] = mapped_column(sa.String(40), nullable=False)
    quantity: Mapped[int] = mapped_column(sa.Integer, nullable=False, default=1)
    value_units: Mapped[int] = mapped_column(sa.SmallInteger, nullable=False, default=1)
    loot_kind: Mapped[str] = mapped_column(sa.String(20), nullable=False)
    disposition: Mapped[str] = mapped_column(
        sa.String(20), nullable=False, default="candidate"
    )
    granted_at: Mapped[datetime | None] = mapped_column(PreciseDateTime, nullable=True)


class ExpeditionContentExposure(Base):
    __tablename__ = "expedition_content_exposures"
    __table_args__ = (
        sa.UniqueConstraint(
            "run_id",
            "content_kind",
            "content_code",
            "exposure_index",
            name="uq_expedition_content_exposure",
        ),
        sa.Index(
            "ix_expedition_exposure_recent",
            "user_id",
            "content_kind",
            "context_code",
            "shown_at",
        ),
    )

    id: Mapped[int] = mapped_column(BigIntPK, primary_key=True, autoincrement=True)
    user_id: Mapped[int] = mapped_column(
        sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    run_id: Mapped[int] = mapped_column(
        sa.ForeignKey("expedition_runs.id", ondelete="CASCADE"), nullable=False
    )
    content_kind: Mapped[str] = mapped_column(sa.String(24), nullable=False)
    content_code: Mapped[str] = mapped_column(sa.String(96), nullable=False)
    context_code: Mapped[str | None] = mapped_column(sa.String(96), nullable=True)
    exposure_index: Mapped[int] = mapped_column(sa.Integer, nullable=False)
    shown_at: Mapped[datetime] = mapped_column(
        PreciseDateTime, nullable=False, default=utcnow
    )


class PlantAdventureBond(Base):
    __tablename__ = "plant_adventure_bonds"
    __table_args__ = (
        sa.CheckConstraint("bond_points >= 0", name="ck_plant_adventure_bond_points"),
    )

    plant_id: Mapped[int] = mapped_column(
        sa.ForeignKey("plants.id", ondelete="CASCADE"), primary_key=True
    )
    user_id: Mapped[int] = mapped_column(
        sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    bond_points: Mapped[int] = mapped_column(sa.Integer, nullable=False, default=0)
    last_bond_local_date: Mapped[date | None] = mapped_column(sa.Date, nullable=True)
    updated_at: Mapped[datetime] = mapped_column(
        PreciseDateTime, nullable=False, default=utcnow, onupdate=utcnow
    )


class UserRegionProgress(Base):
    __tablename__ = "user_region_progress"
    __table_args__ = (
        sa.CheckConstraint("clear_count >= 0", name="ck_user_region_clear_count"),
    )

    user_id: Mapped[int] = mapped_column(
        sa.ForeignKey("users.id", ondelete="CASCADE"), primary_key=True
    )
    region_code: Mapped[str] = mapped_column(sa.String(40), primary_key=True)
    first_cleared_at: Mapped[datetime | None] = mapped_column(
        PreciseDateTime, nullable=True
    )
    clear_count: Mapped[int] = mapped_column(sa.Integer, nullable=False, default=0)
    templates_seen: Mapped[list] = mapped_column(sa.JSON, nullable=False, default=list)
    events_seen: Mapped[list] = mapped_column(sa.JSON, nullable=False, default=list)
    knowledge_code: Mapped[str | None] = mapped_column(sa.String(40), nullable=True)
    updated_at: Mapped[datetime] = mapped_column(
        PreciseDateTime, nullable=False, default=utcnow, onupdate=utcnow
    )


class PlantRegionFamiliarity(Base):
    __tablename__ = "plant_region_familiarities"
    __table_args__ = (
        sa.CheckConstraint(
            "points BETWEEN 0 AND 6", name="ck_plant_region_familiarity_points"
        ),
        sa.CheckConstraint(
            "participation_count >= 0",
            name="ck_plant_region_familiarity_participation",
        ),
    )

    plant_id: Mapped[int] = mapped_column(
        sa.ForeignKey("plants.id", ondelete="CASCADE"), primary_key=True
    )
    region_code: Mapped[str] = mapped_column(sa.String(40), primary_key=True)
    user_id: Mapped[int] = mapped_column(
        sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    points: Mapped[int] = mapped_column(sa.SmallInteger, nullable=False, default=0)
    participation_count: Mapped[int] = mapped_column(
        sa.Integer, nullable=False, default=0
    )
    last_point_local_date: Mapped[date | None] = mapped_column(sa.Date, nullable=True)
    unlocked_scene_codes: Mapped[list] = mapped_column(
        sa.JSON, nullable=False, default=list
    )
    updated_at: Mapped[datetime] = mapped_column(
        PreciseDateTime, nullable=False, default=utcnow, onupdate=utcnow
    )
