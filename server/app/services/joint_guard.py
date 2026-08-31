"""합동 수호전 서비스 — 판을 만들고, 명령을 받고, 상태를 저장한다.

판의 규칙은 `content/expeditions/joint_guard_run.py`가 들고 있고, 여기서는
그것을 DB 한 줄에 얹는다. 새 테이블을 만들지 않는다 — 합동 수호전도
`ExpeditionRun` 한 판이고, 진행 상태는 이미 있는
`runtime_effects_snapshot.joint_guard`에 들어간다(설계서 9장).

경제와 완전히 분리돼 있다. `reward_eligible=False`로 시작하고, 응답에도 재화가
없으며, 하루 보상 원장에 참여하지 않는다.
"""

import copy
from typing import Any

import sqlalchemy as sa
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.errors import AppError
from app.content.expeditions.combat import CombatRuleError
from app.content.expeditions.joint_guard import BEAST_CATALOG, DIFFICULTIES
from app.content.expeditions.joint_guard_run import (
    joint_guard_payload,
    new_joint_guard,
    submit_joint_guard_command,
    swap_joint_guard_member,
)
from app.core.timeutil import local_date_of, utcnow
from app.models.enums import PlantStatus
from app.models.expedition import (
    ExpeditionAction,
    ExpeditionRun,
    UserStageProgress,
)
from app.models.plant import Plant, PlantSpecies
from app.services import expedition_runs


MODE = "joint_guard"

#: 지역 8스테이지가 그 지역 수호짐승의 장벽이다. 한 번 열어 본 사람에게만
#: 관리인이 편지를 보낸다(설계서 3장).
GUARDIAN_STAGE_NO = 8


def _beast_for_region(region_code: str) -> str | None:
    for code, beast in BEAST_CATALOG.items():
        if beast["region_code"] == region_code:
            return code
    return None


async def _guardian_opened(db: AsyncSession, user_id: int, region_code: str) -> bool:
    return bool(
        await db.scalar(
            sa.select(sa.func.count(UserStageProgress.stage_no)).where(
                UserStageProgress.user_id == user_id,
                UserStageProgress.region_code == region_code,
                UserStageProgress.stage_no == GUARDIAN_STAGE_NO,
            )
        )
    )


async def _active_joint_run(db: AsyncSession, user_id: int) -> ExpeditionRun | None:
    return await db.scalar(
        sa.select(ExpeditionRun)
        .where(
            ExpeditionRun.user_id == user_id,
            ExpeditionRun.mode == MODE,
            ExpeditionRun.status == "active",
        )
        .order_by(ExpeditionRun.id.desc())
    )


async def _profiles_for(
    db: AsyncSession, user_id: int, plant_ids: list[int]
) -> dict[int, dict[str, Any]]:
    from app.services.expeditions import _plant_snapshot

    rows = (
        await db.execute(
            sa.select(Plant, PlantSpecies)
            .join(PlantSpecies, PlantSpecies.id == Plant.species_id)
            .where(
                Plant.user_id == user_id,
                Plant.id.in_(plant_ids),
                Plant.status.in_((PlantStatus.ACTIVE, PlantStatus.HARVESTED)),
            )
        )
    ).all()
    profiles: dict[int, dict[str, Any]] = {}
    for position, (plant, species) in enumerate(rows):
        snapshot = _plant_snapshot(plant, species)
        if int(snapshot["stage"]) < 2:
            raise AppError(
                422,
                "JOINT_GUARD_STAGE_REQUIRED",
                "새싹 단계부터 함께 갈 수 있어요.",
            )
        profiles[int(plant.id)] = {
            "id": int(plant.id),
            "position": position,
            "is_guide": False,
            "snapshot": snapshot,
        }
    return profiles


def _guide_profile(position: int, index: int) -> dict[str, Any]:
    """빈자리를 채우는 길잡이. 능력치 6, 고유 스킬 없음(설계서 3장)."""
    return {
        "id": -index,
        "position": position,
        "is_guide": True,
        "snapshot": {
            "name": "기록 안내자",
            "species": {"code": "archive_guide", "name": "기록 안내자"},
            "level": 10,
            "rarity": 1,
            "stage": 3,
            "form": "mosaic",
            "stats": {"care": 6, "focus": 6, "courage": 6, "insight": 6},
        },
    }


def _build_roster(
    formation: list[dict[str, Any]],
    profiles: dict[int, dict[str, Any]],
) -> list[dict[str, Any]]:
    """앱이 보낸 여섯 자리를 프로필이 붙은 명단으로 만든다.

    빈자리는 길잡이로 채운다. 역할이나 품종을 요구하지 않으므로 뽀또 하나에
    길잡이 다섯으로도 명단이 선다.
    """
    roster: list[dict[str, Any]] = []
    guides = 0
    for position, slot in enumerate(formation):
        plant_id = slot.get("plant_id")
        if plant_id is None:
            guides += 1
            profile = _guide_profile(position, guides)
        else:
            profile = profiles.get(int(plant_id))
            if profile is None:
                raise AppError(
                    422,
                    "JOINT_GUARD_UNKNOWN_MEMBER",
                    "보유한 캐릭터만 함께 갈 수 있어요.",
                )
        roster.append({"profile": profile, "formation": str(slot.get("formation"))})
    return roster


def _snapshot(run: ExpeditionRun) -> dict[str, Any]:
    """저장된 판 상태를 **복사해서** 돌려준다.

    복사하지 않으면 판을 제자리에서 고치게 되고, 그러면 SQLAlchemy가 보는
    `이전 값`이 방금 고친 바로 그 객체가 된다. 달라진 것이 없다고 판단해서
    아무것도 쓰지 않는다 - 교대가 응답에는 반영되는데 다음 요청에서 사라졌다.
    """
    state = (run.runtime_effects_snapshot or {}).get("joint_guard")
    if not state:
        raise AppError(409, "JOINT_GUARD_MISSING", "진행 중인 합동 수호전이 없습니다.")
    return copy.deepcopy(state)


def _store(run: ExpeditionRun, state: dict[str, Any]) -> None:
    effects = dict(run.runtime_effects_snapshot or {})
    effects["joint_guard"] = state
    run.runtime_effects_snapshot = effects
    if state["status"] != "active":
        run.status = "completed"
        run.completed_at = utcnow()


def _payload(run: ExpeditionRun, state: dict[str, Any]) -> dict[str, Any]:
    return {
        "run": {
            "id": int(run.id),
            "region_code": str(run.region_code),
            "revision": int(run.revision),
            "status": str(run.status),
        },
        "joint_guard": joint_guard_payload(state),
    }


async def _finish(
    db: AsyncSession,
    run: ExpeditionRun,
    *,
    action_type: str,
    client_action_id: str,
    request_payload: dict,
    expected_revision: int,
    state: dict[str, Any],
) -> dict:
    run.revision += 1
    await db.flush()
    result = _payload(run, state)
    db.add(
        ExpeditionAction(
            run_id=run.id,
            action_index=run.revision,
            client_action_id=client_action_id,
            expected_revision=expected_revision,
            action_type=action_type,
            request_payload=request_payload,
            result_payload=result,
        )
    )
    await db.flush()
    return result


async def start(
    db: AsyncSession,
    user_id: int,
    *,
    beast_code: str,
    difficulty: str,
    formation: list[dict[str, Any]],
) -> dict:
    if beast_code not in BEAST_CATALOG:
        raise AppError(404, "JOINT_GUARD_UNKNOWN_BEAST", "그런 수호짐승은 없어요.")
    if difficulty not in DIFFICULTIES:
        raise AppError(422, "JOINT_GUARD_UNKNOWN_DIFFICULTY", "그런 난이도는 없어요.")

    region_code = str(BEAST_CATALOG[beast_code]["region_code"])
    if not await _guardian_opened(db, user_id, region_code):
        raise AppError(
            422,
            "JOINT_GUARD_LOCKED",
            "그 지역의 수호짐승을 한 번 만나고 나면 열려요.",
        )
    if await _active_joint_run(db, user_id) is not None:
        raise AppError(
            409, "JOINT_GUARD_ALREADY_ACTIVE", "진행 중인 합동 수호전이 있습니다."
        )

    plant_ids = [
        int(slot["plant_id"]) for slot in formation if slot.get("plant_id") is not None
    ]
    if len(set(plant_ids)) != len(plant_ids):
        raise AppError(
            422, "JOINT_GUARD_DUPLICATE_MEMBER", "같은 캐릭터를 두 번 넣을 수 없어요."
        )
    profiles = await _profiles_for(db, user_id, plant_ids)
    if len(profiles) != len(plant_ids):
        raise AppError(
            422, "JOINT_GUARD_UNKNOWN_MEMBER", "보유한 캐릭터만 함께 갈 수 있어요."
        )

    try:
        state = new_joint_guard(beast_code, difficulty, _build_roster(formation, profiles))
    except CombatRuleError as error:
        raise AppError(422, error.code, error.message) from error

    run = ExpeditionRun(
        user_id=user_id,
        region_code=region_code,
        mode=MODE,
        stage_no=None,
        phase="awaiting_event",
        local_date=local_date_of(utcnow()),
        content_version=str(state.get("content_version", "joint-guard-v1.1")),
        map_seed="",
        map_snapshot={},
        run_thread_snapshot={},
        run_memory_snapshot={},
        spotlight_snapshot=[],
        runtime_effects_snapshot={"joint_guard": state},
        current_node_code="dream",
        trail_light=0,
        resolve=0,
        # 경제와 완전히 분리돼 있다. 보상 원장에 아예 참여하지 않는다.
        reward_eligible=False,
    )
    db.add(run)
    await db.flush()
    # 판을 만드는 요청은 헤더의 `Idempotency-Key`가 지킨다. run 안에서 일어나는
    # 행동만 `client_action_id`로 기록한다 - 기존 탐험과 같은 계약이다.
    return _payload(run, state)


async def _mutate(
    db: AsyncSession,
    user_id: int,
    run_id: int,
    *,
    action_type: str,
    request_payload: dict,
    expected_revision: int,
    client_action_id: str,
    apply,
) -> dict:
    run = await expedition_runs.lock_run(db, user_id, run_id)
    if run.mode != MODE:
        raise AppError(409, "JOINT_GUARD_MISSING", "진행 중인 합동 수호전이 없습니다.")
    replay = await expedition_runs.existing_action(
        db, run, client_action_id, action_type, request_payload
    )
    if replay is not None:
        return replay
    expedition_runs.check_revision(run, expected_revision)

    state = _snapshot(run)
    try:
        state = apply(state)
    except CombatRuleError as error:
        raise AppError(422, error.code, error.message) from error
    _store(run, state)
    return await _finish(
        db,
        run,
        action_type=action_type,
        client_action_id=client_action_id,
        request_payload=request_payload,
        expected_revision=expected_revision,
        state=state,
    )


async def submit_turn(
    db: AsyncSession,
    user_id: int,
    run_id: int,
    *,
    command: dict[str, Any],
    expected_revision: int,
    client_action_id: str,
) -> dict:
    return await _mutate(
        db,
        user_id,
        run_id,
        action_type="joint_guard_turn",
        request_payload={"command": command, "expected_revision": expected_revision},
        expected_revision=expected_revision,
        client_action_id=client_action_id,
        apply=lambda state: submit_joint_guard_command(state, command),
    )


async def swap(
    db: AsyncSession,
    user_id: int,
    run_id: int,
    *,
    out_member_id: int,
    in_member_id: int,
    expected_revision: int,
    client_action_id: str,
) -> dict:
    return await _mutate(
        db,
        user_id,
        run_id,
        action_type="joint_guard_swap",
        request_payload={
            "out_member_id": out_member_id,
            "in_member_id": in_member_id,
            "expected_revision": expected_revision,
        },
        expected_revision=expected_revision,
        client_action_id=client_action_id,
        apply=lambda state: swap_joint_guard_member(
            state, out_member_id=out_member_id, in_member_id=in_member_id
        ),
    )


async def active(db: AsyncSession, user_id: int) -> dict | None:
    """진행 중인 판. 없으면 null이라 앱이 입구만 그린다."""
    run = await _active_joint_run(db, user_id)
    if run is None:
        return None
    return _payload(run, _snapshot(run))


async def entry_payload(db: AsyncSession, user_id: int) -> dict:
    """입구 화면 — 어떤 짐승이 열려 있고 어떤 난이도가 있는지."""
    beasts = []
    for code, beast in BEAST_CATALOG.items():
        opened = await _guardian_opened(db, user_id, str(beast["region_code"]))
        beasts.append(
            {
                "code": code,
                "name": beast["name"],
                "region_code": beast["region_code"],
                "dream_scene": beast["dream_scene"],
                "holding": beast["holding"],
                "unlocked": opened,
                "locked_reason": (
                    None if opened else "그 지역의 수호짐승을 한 번 만나고 나면 열려요."
                ),
            }
        )
    return {
        "beasts": beasts,
        "difficulties": [
            {"code": code, **{k: spec[k] for k in ("name", "summary", "layers", "tutorial")}}
            for code, spec in DIFFICULTIES.items()
        ],
        "active_run_id": (
            int(run.id) if (run := await _active_joint_run(db, user_id)) else None
        ),
    }
