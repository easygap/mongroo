"""보상 트랜잭션 (design.md 7.3).

user/활성 식물 row 잠금 → dedupe_key insert → 일일 상한 반영 → 잔액 갱신.
commit은 호출자(요청 트랜잭션)가 담당한다.
"""

from dataclasses import dataclass, field
from datetime import date, timedelta

import sqlalchemy as sa
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.core.timeutil import local_day_bounds_utc
from app.models.enums import REWARD_AMOUNTS, PlantStatus, RewardEventType
from app.models.plant import Plant
from app.models.reward import RewardEvent
from app.models.user import User
from app.services.plants import (
    growth_state_payload,
    is_harvestable,
    refresh_active_plant_growth,
    stage_from_exp,
)


@dataclass
class RewardOutcome:
    events: list[dict] = field(default_factory=list)
    plant: Plant | None = None
    stage_changed: bool = False
    daily_exp_granted: int = 0
    seed_balance: int = 0
    daily_exp_cap: int | None = None

    @property
    def granted(self) -> bool:
        return bool(self.events)

    def payload(self) -> dict | None:
        if not self.granted:
            return None
        plant_part = None
        if self.plant is not None:
            plant_part = {
                "id": self.plant.id,
                "exp": self.plant.exp,
                "stage": stage_from_exp(self.plant.exp),
                "stage_changed": self.stage_changed,
                "harvestable": is_harvestable(self.plant),
                **growth_state_payload(self.plant),
            }
        return {
            "events": self.events,
            "plant": plant_part,
            "daily_exp_granted": self.daily_exp_granted,
            "daily_exp_cap": self.daily_exp_cap or get_settings().daily_exp_cap,
            "seed_balance": self.seed_balance,
        }


async def _daily_exp_granted(db: AsyncSession, user_id: int, local_day: date) -> int:
    start, end = local_day_bounds_utc(local_day)
    result = await db.execute(
        sa.select(sa.func.coalesce(sa.func.sum(RewardEvent.exp_delta), 0)).where(
            RewardEvent.user_id == user_id,
            RewardEvent.created_at >= start,
            RewardEvent.created_at < end,
        )
    )
    return int(result.scalar_one())


async def lock_user(db: AsyncSession, user_id: int) -> User:
    result = await db.execute(
        sa.select(User)
        .where(User.id == user_id)
        .with_for_update()
        .execution_options(populate_existing=True)
    )
    return result.scalar_one()


async def lock_active_plant(db: AsyncSession, user_id: int) -> Plant | None:
    result = await db.execute(
        sa.select(Plant)
        .where(Plant.user_id == user_id, Plant.status == PlantStatus.ACTIVE)
        .with_for_update()
    )
    return result.scalar_one_or_none()


async def grant(
    db: AsyncSession,
    user: User,
    plant: Plant | None,
    event_type: str,
    dedupe_key: str,
    source_type: str,
    source_id: int | None,
    local_day: date,
    outcome: RewardOutcome,
    exp_cap: int | None = None,
    reward_amounts: tuple[int, int] | None = None,
) -> bool:
    """단일 보상 지급. 이미 지급된 dedupe_key면 건너뛰고 False.

    요청 트랜잭션을 깨뜨리지 않도록 SAVEPOINT 안에서 insert한다.
    user/plant는 잠금 상태로 전달할 것.
    """
    exp_amount, seed_amount = reward_amounts or REWARD_AMOUNTS[event_type]
    if plant is None or plant.status != PlantStatus.ACTIVE:
        # 성장 XP는 특정 활성 식물에 붙는 보상이다. 받을 식물이 없을 때
        # 원장에만 기록하면 일일 상한이 소모되고 XP는 영구히 사라진다.
        exp_amount = 0

    already_granted = await _daily_exp_granted(db, user.id, local_day)
    cap = exp_cap or get_settings().daily_exp_cap
    exp_delta = min(exp_amount, max(0, cap - already_granted)) if exp_amount else 0

    event = RewardEvent(
        user_id=user.id,
        plant_id=plant.id if plant is not None else None,
        event_type=event_type,
        source_type=source_type,
        source_id=source_id,
        dedupe_key=dedupe_key,
        exp_delta=exp_delta,
        seed_delta=seed_amount,
        seed_balance_after=user.seed_balance + seed_amount,
    )
    try:
        async with db.begin_nested():
            db.add(event)
            await db.flush()
    except IntegrityError:
        # 같은 dedupe_key가 이미 있음 → 이미 지급된 보상. SAVEPOINT만 롤백된다
        return False

    if exp_delta and plant is not None and plant.status == PlantStatus.ACTIVE:
        before = stage_from_exp(plant.exp)
        plant.exp += exp_delta
        if stage_from_exp(plant.exp) != before:
            outcome.stage_changed = True
            # stage 2에서 이미 모인 분석 증거가 stage 3 진입과 동시에 분기로
            # 드러나게 한다. 누적 프로필은 worker가 저장했으므로 다시 조회하지 않는다.
            await refresh_active_plant_growth(
                db, user.id, plant=plant, rebuild_profile=False
            )
        outcome.plant = plant
    elif plant is not None:
        outcome.plant = plant

    if seed_amount:
        user.seed_balance += seed_amount

    outcome.events.append(
        {"event_type": event_type, "exp_delta": exp_delta, "seed_delta": seed_amount}
    )
    outcome.daily_exp_granted = already_granted + exp_delta
    outcome.seed_balance = user.seed_balance
    outcome.daily_exp_cap = cap
    return True


def update_streak(user: User, local_day: date) -> bool:
    """연속 기록 표시는 갱신하되, 새 기록 날짜일 때만 True를 반환한다."""
    if user.last_recorded_local_date == local_day:
        return False
    if user.last_recorded_local_date == local_day - timedelta(days=1):
        user.streak_days += 1
    else:
        user.streak_days = 1
    user.last_recorded_local_date = local_day
    return True


DEDUPE = {
    RewardEventType.MOOD_FIRST_DAILY: "mood_daily:{user_id}:{local_date}",
    RewardEventType.DIARY_FIRST_DAILY: "diary_daily:{user_id}:{local_date}",
    RewardEventType.CHAT_FIRST_DAILY: "chat_first:{user_id}:{local_date}",
    # event type은 기존 DB 계약을 유지하고, 중복 키만 누적 기록일 기준으로 바꾼다.
    RewardEventType.STREAK_WEEK: "record_week:{user_id}:{recorded_days}",
}


def dedupe_key(event_type: str, **kwargs) -> str:
    return DEDUPE[event_type].format(**kwargs)
