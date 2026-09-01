"""장거리 개척 서비스 — 구간 run 둘~셋을 하나의 원정으로 묶는다.

규칙은 `content/expeditions/journey.py`가 들고 있고, 여기서는 그것을 DB에
얹는다. **구간은 새 게임 모드가 아니다.** `expeditions.start_run`이 만드는
평범한 탐험 run이고, 다른 것은 `journey_id`가 붙는다는 것뿐이다. 그래서 걷기·
사건·전투·귀환이 전부 지금까지의 코드 그대로 동작한다.

이 서비스가 실제로 지키는 것은 넷이다.

1. **한 캐릭터는 한 구간에만.** `members_snapshot`이 이미 나간 사람을 기억한다.
2. **빈자리는 길잡이.** 캐릭터 0명 + 길잡이 2명도 정상 편성이다.
3. **보상은 마지막에 한 번.** 구간 run은 `reward_eligible=False`로 만들고,
   귀환에서 **가장 먼 확보 지역**의 밴드로 한 번만 지급한다.
4. **개척 중에는 다른 탐험을 시작할 수 없다.** 야영 중이라 진행 중인 run이
   없어도 활성 슬롯을 개척이 잡고 있다.
"""

from typing import Any

import sqlalchemy as sa
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.errors import AppError
from app.content.expeditions.loot_budget import (
    LootBudgetError,
    budget_of,
    select_within_budget,
)
from app.content.expeditions.journey import (
    DIRECTIONS,
    JOURNEY_VERSION,
    LEG_PARTY_SIZE,
    direction as direction_spec,
    max_own_members,
    route_of,
    routes_for,
)
from app.core.korean import korean_object
from app.core.timeutil import local_date_of, utcnow
from app.models.expedition import (
    ExpeditionJourney,
    ExpeditionLoot,
    ExpeditionRun,
    UserActiveExpedition,
)
from app.models.enums import RewardEventType
from app.services import expeditions as expedition_service
from app.services import rewards


#: 구간 run이 쓰는 모드. `heart_resonance`가 아니므로 run 하나하나는 보상
#: 자격이 없다 — 지급은 개척 귀환에서 한 번뿐이다.
LEG_MODE = "free_explore"


def _iso(value: Any) -> str | None:
    return None if value is None else value.isoformat()


async def _active_journey(
    db: AsyncSession, user_id: int, *, lock: bool = False
) -> ExpeditionJourney | None:
    query = sa.select(ExpeditionJourney).where(
        ExpeditionJourney.user_id == user_id,
        ExpeditionJourney.status == "active",
    )
    if lock:
        query = query.with_for_update()
    return await db.scalar(query.order_by(ExpeditionJourney.id.desc()))


async def _journey_or_404(
    db: AsyncSession, user_id: int, journey_id: int
) -> ExpeditionJourney:
    journey = await db.scalar(
        sa.select(ExpeditionJourney)
        .where(
            ExpeditionJourney.id == journey_id,
            ExpeditionJourney.user_id == user_id,
        )
        .with_for_update()
    )
    if journey is None:
        raise AppError(404, "JOURNEY_NOT_FOUND", "개척을 찾을 수 없습니다.")
    return journey


def _check_revision(journey: ExpeditionJourney, expected_revision: int) -> None:
    if journey.revision != expected_revision:
        raise AppError(
            409,
            "JOURNEY_REVISION_MISMATCH",
            "다른 곳에서 개척이 먼저 진행됐어요. 새로고침해 주세요.",
        )


async def _current_leg_run(
    db: AsyncSession, journey: ExpeditionJourney
) -> ExpeditionRun | None:
    return await db.scalar(
        sa.select(ExpeditionRun)
        .where(
            ExpeditionRun.journey_id == journey.id,
            ExpeditionRun.status == "active",
        )
        .order_by(ExpeditionRun.id.desc())
    )


def _leg_payload(entry: dict[str, Any]) -> dict[str, Any]:
    return {
        "leg_index": entry["leg_index"],
        "run_id": entry["run_id"],
        "route_code": entry["route_code"],
        "route_name": entry["route_name"],
        "region_code": entry["region_code"],
        "region_name": entry["region_name"],
        "status": entry["status"],
        "objective_secured": entry["objective_secured"],
        "party": entry["party"],
        "started_at": entry["started_at"],
        "finished_at": entry["finished_at"],
    }


def _band_of(region_code: str | None) -> dict[str, int] | None:
    if region_code is None:
        return None
    reward = expedition_service.load_content(region_code)["region"]["reward"]
    return {"exp": int(reward["exp"]), "seeds": int(reward["seeds"])}


def _region_name(region_code: str) -> str:
    return str(expedition_service.load_content(region_code)["region"]["name"])


def _deeper(first: str | None, second: str) -> str:
    """둘 중 더 먼 지역. 순서는 지역 진행 순서를 그대로 쓴다."""

    order = expedition_service.region_order()

    def rank(code: str | None) -> int:
        if code is None:
            return -1
        return order.index(code) if code in order else -1

    return second if rank(second) > rank(first) else (first or second)


async def journey_payload(
    db: AsyncSession, journey: ExpeditionJourney
) -> dict[str, Any]:
    spec = direction_spec(journey.direction_code) or {}
    legs = [_leg_payload(entry) for entry in journey.legs_snapshot]
    run = await _current_leg_run(db, journey)
    at_camp = run is None and journey.status == "active"
    remaining = journey.max_legs - journey.current_leg_index
    budget, slots = _journey_budget(journey)
    candidates = await _candidates(db, journey) if at_camp else []
    return {
        "id": journey.id,
        "direction_code": journey.direction_code,
        "direction_name": spec.get("name", journey.direction_code),
        "status": journey.status,
        "mode": journey.mode,
        "max_legs": journey.max_legs,
        "current_leg_index": journey.current_leg_index,
        "revision": journey.revision,
        "reward_eligible": journey.reward_eligible,
        "deepest_secured_region": journey.deepest_secured_region,
        "deepest_secured_region_name": (
            _region_name(journey.deepest_secured_region)
            if journey.deepest_secured_region
            else None
        ),
        "reward_band": _band_of(journey.deepest_secured_region),
        "legs": legs,
        "used_plant_ids": sorted(int(key) for key in journey.members_snapshot),
        "max_own_members": max_own_members(journey.direction_code),
        "party_size": LEG_PARTY_SIZE,
        "active_run_id": run.id if run is not None else None,
        # 야영지에서만 다음 갈림길이 열린다. 다음 구간을 미리 보여 주지
        # 않는 것이 이 콘텐츠의 계약이다(설계서 10.3).
        "at_camp": at_camp,
        "can_continue": at_camp and remaining > 0,
        "next_routes": (
            routes_for(journey.direction_code, journey.current_leg_index)
            if at_camp and remaining > 0
            else []
        ),
        # 귀환 sheet가 담을 조합을 고르려면 후보와 예산이 함께 있어야 한다.
        # 아직 걷는 중이면 고를 자리가 아니므로 비워 둔다.
        "return_budget": {"value_units": budget, "slots": slots},
        "return_candidates": (
            [expedition_service.loot_payload(loot) for loot in candidates]
            if at_camp
            else []
        ),
        "summary": journey.summary_snapshot,
    }


async def _direction_rows(db: AsyncSession, user_id: int) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for code, spec in DIRECTIONS.items():
        cleared = await expedition_service.region_cleared(
            db, user_id, spec["requires_region"]
        )
        rows.append(
            {
                "code": code,
                "name": spec["name"],
                "summary": spec["summary"],
                "max_legs": spec["max_legs"],
                "party_size": LEG_PARTY_SIZE,
                "max_own_members": max_own_members(code),
                "minutes": list(spec["minutes"]),
                "region_name": _region_name(spec["requires_region"]),
                "locked": not cleared,
                "lock_reason": (
                    None
                    if cleared
                    else f"{korean_object(_region_name(spec['requires_region']))} "
                    "완주하면 열려요."
                ),
            }
        )
    return rows


async def entry_payload(db: AsyncSession, user_id: int) -> dict[str, Any]:
    journey = await _active_journey(db, user_id)
    directions = await _direction_rows(db, user_id)
    return {
        "content_version": JOURNEY_VERSION,
        "unlocked": any(not row["locked"] for row in directions),
        "directions": directions,
        "active": await journey_payload(db, journey) if journey else None,
    }


async def active(db: AsyncSession, user_id: int) -> dict[str, Any] | None:
    journey = await _active_journey(db, user_id)
    return await journey_payload(db, journey) if journey else None


async def get(db: AsyncSession, user_id: int, journey_id: int) -> dict[str, Any]:
    journey = await db.scalar(
        sa.select(ExpeditionJourney).where(
            ExpeditionJourney.id == journey_id,
            ExpeditionJourney.user_id == user_id,
        )
    )
    if journey is None:
        raise AppError(404, "JOURNEY_NOT_FOUND", "개척을 찾을 수 없습니다.")
    return await journey_payload(db, journey)


async def start(
    db: AsyncSession,
    user_id: int,
    *,
    direction_code: str,
    mode: str,
) -> dict[str, Any]:
    spec = direction_spec(direction_code)
    if spec is None:
        raise AppError(404, "JOURNEY_DIRECTION_NOT_FOUND", "그 방향을 찾을 수 없습니다.")
    if mode not in ("heart_resonance", "free_explore"):
        raise AppError(422, "INVALID_JOURNEY_MODE", "지원하지 않는 출발 방식입니다.")
    if not await expedition_service.region_cleared(db, user_id, spec["requires_region"]):
        raise AppError(
            409,
            "JOURNEY_DIRECTION_LOCKED",
            f"{korean_object(_region_name(spec['requires_region']))} "
            "완주하면 이 방향이 열려요.",
        )
    await _assert_slot_free(db, user_id)

    today = local_date_of(utcnow())
    reward_eligible = False
    if mode == "heart_resonance":
        # 일반 탐험과 같은 관문을 지난다. 개척이라고 하루 보상을 더 주지 않는다.
        if not await expedition_service._diary_ready(db, user_id, today):
            raise AppError(
                409,
                "DIARY_REQUIRED",
                "오늘 마음 일기를 50자 이상 기록하면 마음 공명 개척을 시작할 수 있어요.",
            )
        if await expedition_service._reward_used(db, user_id, today):
            raise AppError(
                409,
                "EXPEDITION_REWARD_USED",
                "오늘의 마음 공명 보상은 이미 받았습니다.",
            )
        reward_eligible = True

    journey = ExpeditionJourney(
        user_id=user_id,
        direction_code=direction_code,
        status="active",
        mode=mode,
        local_date=today,
        content_version=JOURNEY_VERSION,
        max_legs=int(spec["max_legs"]),
        current_leg_index=0,
        deepest_secured_region=None,
        reward_eligible=reward_eligible,
        revision=0,
        legs_snapshot=[],
        members_snapshot={},
    )
    db.add(journey)
    await db.flush()
    # 야영 중에도 슬롯을 잡는다. 이게 없으면 구간 사이에 일반 탐험을 따로
    # 시작할 수 있고, 그러면 돌아올 개척이 미아가 된다.
    db.add(UserActiveExpedition(user_id=user_id, journey_id=journey.id))
    return await journey_payload(db, journey)


async def _assert_slot_free(db: AsyncSession, user_id: int) -> None:
    slot = await db.scalar(
        sa.select(UserActiveExpedition).where(UserActiveExpedition.user_id == user_id)
    )
    if slot is None:
        return
    if slot.journey_id is not None:
        raise AppError(409, "JOURNEY_ALREADY_ACTIVE", "진행 중인 개척이 있습니다.")
    raise AppError(409, "EXPEDITION_ALREADY_ACTIVE", "진행 중인 탐험이 있습니다.")


async def create_leg(
    db: AsyncSession,
    user_id: int,
    journey_id: int,
    *,
    route_choice_code: str,
    plant_ids: list[int],
    guide_count: int,
    expected_revision: int,
) -> dict[str, Any]:
    journey = await _journey_or_404(db, user_id, journey_id)
    if journey.status != "active":
        raise AppError(409, "JOURNEY_FINISHED", "이미 끝난 개척입니다.")
    _check_revision(journey, expected_revision)
    if await _current_leg_run(db, journey) is not None:
        raise AppError(
            409, "JOURNEY_LEG_IN_PROGRESS", "진행 중인 구간을 먼저 마쳐 주세요."
        )
    leg_index = journey.current_leg_index
    if leg_index >= journey.max_legs:
        raise AppError(409, "JOURNEY_LEGS_EXHAUSTED", "더 갈 구간이 없어요.")
    route = route_of(journey.direction_code, leg_index, route_choice_code)
    if route is None:
        raise AppError(404, "JOURNEY_ROUTE_NOT_FOUND", "그 갈림길을 찾을 수 없습니다.")

    if len(plant_ids) != len(set(plant_ids)):
        raise AppError(422, "INVALID_JOURNEY_PARTY", "같은 캐릭터를 두 번 넣을 수 없어요.")
    if len(plant_ids) + guide_count != LEG_PARTY_SIZE:
        raise AppError(
            422,
            "INVALID_JOURNEY_PARTY",
            f"한 구간은 {LEG_PARTY_SIZE}명이에요. 빈자리는 길잡이가 채워요.",
        )
    used = {int(key) for key in journey.members_snapshot}
    repeated = sorted(used.intersection(plant_ids))
    if repeated:
        raise AppError(
            409,
            "JOURNEY_MEMBER_ALREADY_USED",
            "이번 개척에서 이미 다녀온 캐릭터예요. 아직 쉬고 있는 캐릭터를 보내 주세요.",
        )

    run_payload = await expedition_service.start_run(
        db,
        user_id,
        region_code=route["region_code"],
        mode=LEG_MODE,
        plant_ids=plant_ids,
        guide_count=guide_count,
        journey_id=journey.id,
        journey_leg_index=leg_index,
    )
    run_id = int(run_payload["run"]["id"])
    party = [
        {
            "name": member["name"],
            "is_guide": bool(member["is_guide"]),
            "plant_id": member.get("plant_id"),
        }
        for member in run_payload.get("party", [])
    ]
    # JSON 칸은 **새 값을 대입해야** 저장된다. 안에서 append만 하면
    # SQLAlchemy가 바뀐 줄 모르고 조용히 넘어간다.
    journey.legs_snapshot = [
        *journey.legs_snapshot,
        {
            "leg_index": leg_index,
            "run_id": run_id,
            "route_code": route["code"],
            "route_name": route["name"],
            "region_code": route["region_code"],
            "region_name": _region_name(route["region_code"]),
            "status": "active",
            "objective_secured": False,
            "party": party,
            "started_at": _iso(utcnow()),
            "finished_at": None,
        },
    ]
    journey.members_snapshot = {
        **journey.members_snapshot,
        **{str(plant_id): leg_index for plant_id in plant_ids},
    }
    journey.revision += 1
    return {
        "journey": await journey_payload(db, journey),
        "expedition": run_payload,
    }


async def on_leg_finished(db: AsyncSession, run: ExpeditionRun) -> None:
    """구간 run이 끝났을 때 부모 개척을 갱신한다.

    `expeditions.extract`와 `expeditions.retreat`이 마지막에 부른다. 목표를
    확보하고 끝났으면 야영지에서 다음 갈림길이 열리고, 목표 전에 접었으면
    개척도 함께 끝난다(설계서 9.8).
    """

    if run.journey_id is None:
        return
    journey = await db.scalar(
        sa.select(ExpeditionJourney)
        .where(ExpeditionJourney.id == run.journey_id)
        .with_for_update()
    )
    if journey is None or journey.status != "active":
        return

    secured = run.status == "completed"
    journey.legs_snapshot = [
        {
            **entry,
            "status": run.status,
            "objective_secured": secured,
            "finished_at": _iso(utcnow()),
        }
        if entry["run_id"] == run.id
        else entry
        for entry in journey.legs_snapshot
    ]
    if secured:
        journey.deepest_secured_region = _deeper(
            journey.deepest_secured_region, run.region_code
        )
        journey.current_leg_index = min(journey.current_leg_index + 1, journey.max_legs)
    journey.revision += 1

    # `extract`/`retreat`이 슬롯 행을 통째로 지운 뒤에 여기가 불린다. 개척이
    # 계속되면 **개척만 잡는 행으로 다시 세운다** — 야영 중에도 다른 탐험이
    # 끼어들면 돌아올 개척이 미아가 된다.
    await db.execute(
        sa.delete(UserActiveExpedition).where(
            UserActiveExpedition.user_id == journey.user_id
        )
    )
    if secured:
        db.add(UserActiveExpedition(user_id=journey.user_id, journey_id=journey.id))
        await db.flush()
    else:
        # 목표 전에 접었다. 지금까지 확보한 구간의 기록만 남기고 끝낸다.
        # 안전 지원으로 돌아온 구간이면 부모도 같은 이름으로 끝난다 —
        # 스스로 접은 것과 안전 지원은 같은 일이 아니다(설계서 `expedition_journeys`).
        await _finish(
            db,
            journey,
            status="safe_returned" if run.status == "safe_returned" else "retreated",
            grant=False,
        )


def _summary_of(
    journey: ExpeditionJourney,
    reward: dict | None,
    loot: dict[str, Any] | None = None,
) -> dict[str, Any]:
    secured = [entry for entry in journey.legs_snapshot if entry["objective_secured"]]
    return {
        "title": (
            "원정 기록을 안고 돌아왔어요"
            if secured
            else "오늘은 여기까지 기록했어요"
        ),
        "reward": reward,
        "loot": loot,
        "leg_count": len(journey.legs_snapshot),
        "secured_count": len(secured),
        "deepest_region_code": journey.deepest_secured_region,
        "deepest_region_name": (
            _region_name(journey.deepest_secured_region)
            if journey.deepest_secured_region
            else None
        ),
        "legs": [_leg_payload(entry) for entry in journey.legs_snapshot],
    }


async def _finish(
    db: AsyncSession,
    journey: ExpeditionJourney,
    *,
    status: str,
    grant: bool,
    selected_loot_ids: list[int] | None = None,
) -> dict[str, Any]:
    reward_payload = None
    if grant and journey.reward_eligible and journey.deepest_secured_region:
        band = _band_of(journey.deepest_secured_region)
        outcome = rewards.RewardOutcome()
        user = await rewards.lock_user(db, journey.user_id)
        lead = await rewards.lock_active_plant(db, journey.user_id)
        await rewards.grant(
            db,
            user,
            lead,
            RewardEventType.EXPEDITION_COMPLETED,
            # 일반 탐험과 **같은 하루 원장 열쇠**를 쓴다. 구간을 여러 개 돌아도,
            # 오늘 이미 탐험 보상을 받았어도 하루 한 번이다.
            f"active_expedition_daily:{journey.user_id}:{journey.local_date.isoformat()}",
            "expedition_journey",
            journey.id,
            journey.local_date,
            outcome,
            reward_amounts=(band["exp"], band["seeds"]),
        )
        reward_payload = outcome.payload()

    loot_result = await _settle_loot(
        db, journey, grant=grant, selected_loot_ids=selected_loot_ids
    )

    journey.status = status
    journey.completed_at = utcnow()
    journey.summary_snapshot = _summary_of(journey, reward_payload, loot_result)
    journey.revision += 1
    await db.execute(
        sa.delete(UserActiveExpedition).where(
            UserActiveExpedition.journey_id == journey.id
        )
    )
    return await journey_payload(db, journey)


async def _candidates(
    db: AsyncSession, journey: ExpeditionJourney
) -> list[ExpeditionLoot]:
    run_ids = [entry["run_id"] for entry in journey.legs_snapshot]
    if not run_ids:
        return []
    return list(
        (
            await db.execute(
                sa.select(ExpeditionLoot)
                .where(
                    ExpeditionLoot.run_id.in_(run_ids),
                    ExpeditionLoot.disposition == "candidate",
                )
                .order_by(ExpeditionLoot.id)
            )
        ).scalars()
    )


def _journey_budget(journey: ExpeditionJourney) -> tuple[int, int]:
    """가장 먼 확보 지역의 가치 예산과 칸 수.

    구간마다 예산을 따로 주지 않는다 — 보상이 한 번뿐인 것과 같은 이유로,
    담아 올 수 있는 양도 **가장 멀리 간 곳** 하나가 정한다(설계서 9.8).
    """

    if journey.deepest_secured_region is None:
        return (0, 0)
    reward = expedition_service.load_content(journey.deepest_secured_region)[
        "region"
    ]["reward"]
    return budget_of(reward)


async def _settle_loot(
    db: AsyncSession,
    journey: ExpeditionJourney,
    *,
    grant: bool,
    selected_loot_ids: list[int] | None,
) -> dict[str, Any] | None:
    """구간마다 모아 둔 귀환 후보를 가치 예산 안에서 정리한다.

    구간 run은 그 자리에서 지급하지 않아 loot가 `candidate`로 쌓여 있다.
    여기서 예산만큼 넘기고(`granted`) 나머지는 기록으로 남긴다(`recorded`).
    """

    loots = await _candidates(db, journey)
    if not loots:
        return None
    budget, slots = _journey_budget(journey)
    if not grant or budget <= 0:
        for loot in loots:
            loot.disposition = "recorded"
        return None

    try:
        selection = select_within_budget(
            loots,
            budget=budget,
            slots=slots,
            selected_ids=selected_loot_ids,
        )
    except LootBudgetError as error:
        raise AppError(422, error.code, error.message) from error

    for loot in selection.granted:
        await expedition_service.grant_loot(db, journey.user_id, loot)
    for loot in selection.recorded:
        loot.disposition = "recorded"
    return {
        "value_units": budget,
        "slots": slots,
        "spent_units": selection.spent_units,
        "granted": [expedition_service.loot_payload(loot) for loot in selection.granted],
        "recorded": [
            expedition_service.loot_payload(loot) for loot in selection.recorded
        ],
    }


async def return_home(
    db: AsyncSession,
    user_id: int,
    journey_id: int,
    *,
    expected_revision: int,
    selected_loot_ids: list[int] | None = None,
) -> dict[str, Any]:
    journey = await _journey_or_404(db, user_id, journey_id)
    if journey.status != "active":
        raise AppError(409, "JOURNEY_FINISHED", "이미 끝난 개척입니다.")
    _check_revision(journey, expected_revision)
    if await _current_leg_run(db, journey) is not None:
        raise AppError(
            409, "JOURNEY_LEG_IN_PROGRESS", "진행 중인 구간을 먼저 마쳐 주세요."
        )
    secured = any(entry["objective_secured"] for entry in journey.legs_snapshot)
    return await _finish(
        db,
        journey,
        # 확보한 구간이 하나도 없으면 완주가 아니다. 경고로 보여 주지 않을 뿐,
        # 상태는 갈라 둔다.
        status="completed" if secured else "retreated",
        grant=secured,
        selected_loot_ids=selected_loot_ids,
    )
