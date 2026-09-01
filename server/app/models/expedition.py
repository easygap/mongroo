from datetime import date, datetime

import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column

from app.core.field_encryption import ProtectedJSON
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
    # 스테이지 지도에서 시작한 run만 값을 가진다. 완료 시 그 스테이지를 클리어로 남긴다.
    stage_no: Mapped[int | None] = mapped_column(sa.SmallInteger, nullable=True)
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
    summary_snapshot: Mapped[dict | None] = mapped_column(
        ProtectedJSON("expedition_runs.summary_snapshot"), nullable=True
    )
    home_reflection_seen_at: Mapped[datetime | None] = mapped_column(
        PreciseDateTime, nullable=True
    )
    # 장거리 개척의 한 구간이면 부모를 가리킨다. 일반 탐험은 둘 다 NULL이다.
    #
    # 구간이 끝났을 때 부모를 O(1)로 찾으려고 run 쪽에 둔다. 개척 행에도
    # 구간 목록이 있지만, 그쪽만 두면 run 하나가 끝날 때마다 개척을 훑어야 한다.
    journey_id: Mapped[int | None] = mapped_column(
        sa.ForeignKey("expedition_journeys.id", ondelete="CASCADE"),
        nullable=True,
        index=True,
    )
    journey_leg_index: Mapped[int | None] = mapped_column(
        sa.SmallInteger, nullable=True
    )


class ExpeditionJourney(Base):
    """장거리 개척 한 번. 구간 run 둘~셋을 하나의 원정 기록으로 묶는다.

    구간·참가자 목록은 JSON 한 칸씩이다. 설계서는 표를 셋으로 나눠 뒀지만
    (`legs`, `members`, `actions`) 둘 다 최대 여섯 줄이고 언제나 통째로만
    읽는다. 표를 늘리는 대신 여기에 두고, `UNIQUE(journey_id, plant_id)`가
    하던 일은 서비스가 대신 지킨다 — 합동 수호전이 판 상태를 run 한 줄에
    얹은 것과 같은 판단이다.
    """

    __tablename__ = "expedition_journeys"
    __table_args__ = (
        sa.CheckConstraint(
            "status IN ('active','completed','retreated','safe_returned')",
            name="ck_expedition_journey_status",
        ),
        sa.CheckConstraint(
            "max_legs BETWEEN 2 AND 3", name="ck_expedition_journey_max_legs"
        ),
    )

    id: Mapped[int] = mapped_column(BigIntPK, primary_key=True, autoincrement=True)
    user_id: Mapped[int] = mapped_column(
        sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    direction_code: Mapped[str] = mapped_column(sa.String(40), nullable=False)
    status: Mapped[str] = mapped_column(sa.String(24), nullable=False, default="active")
    mode: Mapped[str] = mapped_column(sa.String(24), nullable=False)
    local_date: Mapped[date] = mapped_column(sa.Date, nullable=False)
    content_version: Mapped[str] = mapped_column(sa.String(32), nullable=False)
    max_legs: Mapped[int] = mapped_column(sa.SmallInteger, nullable=False)
    #: 다음에 만들 구간의 번호. 구간을 시작할 때가 아니라 **끝났을 때** 오른다.
    current_leg_index: Mapped[int] = mapped_column(
        sa.SmallInteger, nullable=False, default=0
    )
    #: 지금까지 목표를 확보한 지역 중 가장 먼 곳. 귀환 보상 밴드의 기준이다.
    deepest_secured_region: Mapped[str | None] = mapped_column(
        sa.String(40), nullable=True
    )
    reward_eligible: Mapped[bool] = mapped_column(
        sa.Boolean, nullable=False, default=False, server_default=sa.false()
    )
    revision: Mapped[int] = mapped_column(sa.Integer, nullable=False, default=0)
    #: 구간마다 한 줄. `{leg_index, run_id, route_code, route_name, region_code,
    #: status, objective_secured, started_at, finished_at, party}`
    legs_snapshot: Mapped[list] = mapped_column(sa.JSON, nullable=False, default=list)
    #: 이미 나간 캐릭터. `{"<plant_id>": leg_index}`. 중복 출전을 막는 자리다.
    members_snapshot: Mapped[dict] = mapped_column(sa.JSON, nullable=False, default=dict)
    summary_snapshot: Mapped[dict | None] = mapped_column(sa.JSON, nullable=True)
    started_at: Mapped[datetime] = mapped_column(
        PreciseDateTime, nullable=False, default=utcnow
    )
    completed_at: Mapped[datetime | None] = mapped_column(
        PreciseDateTime, nullable=True
    )


class UserActiveExpedition(Base):
    __tablename__ = "user_active_expeditions"

    user_id: Mapped[int] = mapped_column(
        sa.ForeignKey("users.id", ondelete="CASCADE"), primary_key=True
    )
    # 야영 중인 개척은 진행 중인 run이 없다. 그래서 둘 다 NULL 허용이지만
    # 둘 다 NULL인 행은 두지 않는다(설계서 `expedition_runs` 절).
    run_id: Mapped[int | None] = mapped_column(
        sa.ForeignKey("expedition_runs.id", ondelete="CASCADE"),
        nullable=True,
        unique=True,
    )
    journey_id: Mapped[int | None] = mapped_column(
        sa.ForeignKey("expedition_journeys.id", ondelete="CASCADE"),
        nullable=True,
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
    snapshot: Mapped[dict] = mapped_column(
        ProtectedJSON("expedition_party_members.snapshot"), nullable=False
    )
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
    result_payload: Mapped[dict] = mapped_column(
        ProtectedJSON("expedition_actions.result_payload"), nullable=False
    )
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


class UserStageProgress(Base):
    """지역 스테이지(1~8)별 진행 기록.

    스테이지 하나가 독립 세션이므로 run이 아니라 사용자·지역·번호로 남긴다.
    보상은 기존 일일 원장이 담당하고 이 표는 진행 표시와 이야기 확인 여부만 센다.
    """

    __tablename__ = "user_stage_progress"
    __table_args__ = (
        sa.CheckConstraint("stage_no BETWEEN 1 AND 8", name="ck_user_stage_no"),
        sa.CheckConstraint("clear_count >= 1", name="ck_user_stage_clear_count"),
    )

    user_id: Mapped[int] = mapped_column(
        sa.ForeignKey("users.id", ondelete="CASCADE"), primary_key=True
    )
    region_code: Mapped[str] = mapped_column(sa.String(40), primary_key=True)
    stage_no: Mapped[int] = mapped_column(sa.SmallInteger, primary_key=True)
    cleared_at: Mapped[datetime] = mapped_column(
        PreciseDateTime, nullable=False, default=utcnow
    )
    clear_count: Mapped[int] = mapped_column(sa.Integer, nullable=False, default=1)
    story_seen: Mapped[bool] = mapped_column(
        sa.Boolean, nullable=False, default=False, server_default=sa.false()
    )
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
