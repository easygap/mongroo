"""숙련 기록과 그것을 근거로 한 기록서 해금.

숙련은 **성능을 1도 바꾸지 않는다**(설계서 11.6). 위력·비용·쿨타임 어디에도
들어가지 않고, 회상 문장을 여는 기록일 뿐이다. 다만 `마음 지키기 누적 30회`처럼
`무엇을 얼마나 해 봤는가`를 묻는 해금 조건이 이미 이 기록을 필요로 하므로,
조건마다 새 카운터를 만들지 않고 여기 하나를 함께 읽는다.

해금은 확률이 아니다. 조건을 채우면 결정적으로, 그리고 한 번만 들어온다.
"""

from __future__ import annotations

from typing import Any, Iterable

import sqlalchemy as sa
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.errors import AppError
from app.core.timeutil import utcnow
from app.models.expedition import ExpeditionRun
from app.models.plant import Plant, PlantSpecies
from app.content.expeditions.skill_books import SKILL_BOOK_CATALOG
from app.models.skill_book import PlantSkillMastery, UserSkillBook
from app.services.skill_books import grant_skill_book


# 5단계까지, 단계마다 회상 문장 하나. 성능과 무관하므로 곡선을 크게 만들지 않는다.
MASTERY_THRESHOLDS = (5, 15, 40, 90, 180)
MAX_MASTERY_LEVEL = len(MASTERY_THRESHOLDS)


def mastery_level_for(use_count: int) -> int:
    level = 0
    for threshold in MASTERY_THRESHOLDS:
        if use_count >= threshold:
            level += 1
        else:
            break
    return min(MAX_MASTERY_LEVEL, level)


# 행동 코드 옆에 함께 쌓는 **성취 기록**. 해금 조건이 `무엇을 얼마나 해 봤는가`를
# 묻는데, 조건마다 카운터 테이블을 새로 만들면 같은 모양이 여섯 벌 생긴다.
# 그래서 `plant_skill_mastery` 하나에 함께 적는다(모듈 도입부의 결정 그대로).
#
# 여섯 행동 코드와 섞이지 않게 `@` 접두사를 쓴다. 접두사가 붙은 코드는 숙련
# 단계 계산에서 빠지므로, 회상 문장이 `약점 일치 3단계` 같은 말로 오염되지 않는다.
ACHIEVEMENT_PREFIX = "@"

# 약점을 실제로 맞힌 공격 한 번.
WEAKNESS_HIT_CODE = f"{ACHIEVEMENT_PREFIX}weakness_hit"
# 그 공격으로 수호자 장벽이 열린 순간.
BARRIER_OPEN_CODE = f"{ACHIEVEMENT_PREFIX}barrier_open"
# 어떤 결의 장벽을 열었는지. `3종 열기`는 횟수가 아니라 **가짓수**를 묻는다.
BARRIER_KIND_PREFIX = f"{ACHIEVEMENT_PREFIX}barrier_kel:"


def is_achievement_code(skill_code: str) -> bool:
    """숙련 단계를 매기지 않는 성취 기록인가."""

    return skill_code.startswith(ACHIEVEMENT_PREFIX)


def _used_actions(
    events: Iterable[dict[str, Any]],
    plant_by_member: dict[int, int],
) -> list[tuple[int, str]]:
    """이번 교전에서 누가 무엇을 했는지 (plant_id, action)으로 모은다.

    전투 이벤트의 `member_id`는 파티 자리 번호라 런이 끝나면 사라진다. 숙련은
    캐릭터에 남아야 하므로 여기서 plant_id로 바꾼다.

    기록하는 키는 여섯 행동 코드(`attack`·`unique_1`…`guard`)다. 이 어휘는
    캐릭터가 바뀌어도 뜻이 같고, 해금 조건이 묻는 `마음 지키기를 몇 번 했나`와
    정확히 일치한다. 슬롯 안에 실제로 무엇이 들어 있었는지까지 세려면 전투
    이벤트가 해석된 스킬 코드를 함께 실어야 하고, 그건 별도 작업이다.
    """

    used: list[tuple[int, str]] = []
    for event in events:
        if event.get("type") != "party_action":
            continue
        member_id = event.get("member_id")
        action = event.get("action")
        if not isinstance(member_id, int) or not isinstance(action, str):
            continue
        plant_id = plant_by_member.get(member_id)
        if plant_id is None:
            # 길잡이는 캐릭터가 아니라 숙련이 쌓이지 않는다.
            continue
        used.append((plant_id, action))

        # 같은 이벤트에서 성취도 함께 읽는다. 전투가 이미 싣고 있는 값이라
        # 새로 계산하지 않는다 — 판정과 기록이 어긋날 여지를 안 만든다.
        if event.get("weakness_hit"):
            used.append((plant_id, WEAKNESS_HIT_CODE))
        # 이 공격으로 장벽이 0이 된 순간만 센다. `열었다`는 마지막 한 방이다.
        if int(event.get("enemy_guard_before", 0)) > 0 and (
            int(event.get("enemy_guard_after", 1)) <= 0
        ):
            used.append((plant_id, BARRIER_OPEN_CODE))
            if kel := event.get("enemy_weak_kel"):
                used.append((plant_id, f"{BARRIER_KIND_PREFIX}{kel}"))
    return used


async def record_skill_uses(
    db: AsyncSession,
    events: Iterable[dict[str, Any]],
    plant_by_member: dict[int, int],
) -> None:
    """교전 결과에서 사용 횟수를 누적한다."""

    counts: dict[tuple[int, str], int] = {}
    for key in _used_actions(events, plant_by_member):
        counts[key] = counts.get(key, 0) + 1
    if not counts:
        return

    rows = await db.execute(
        sa.select(PlantSkillMastery).where(
            sa.tuple_(
                PlantSkillMastery.plant_id, PlantSkillMastery.skill_code
            ).in_(list(counts))
        )
    )
    existing = {(row.plant_id, row.skill_code): row for row in rows.scalars().all()}
    for (plant_id, skill_code), delta in counts.items():
        row = existing.get((plant_id, skill_code))
        if row is None:
            row = PlantSkillMastery(
                plant_id=plant_id,
                skill_code=skill_code,
                use_count=0,
                mastery_level=0,
                updated_at=utcnow(),
            )
            db.add(row)
        row.use_count = int(row.use_count) + delta
        # 성취 기록에는 단계를 매기지 않는다. 숙련은 여섯 행동의 회상 문장을
        # 여는 것이지 `약점 일치 3단계` 같은 말을 만드는 것이 아니다.
        row.mastery_level = (
            0 if is_achievement_code(skill_code) else mastery_level_for(row.use_count)
        )
        row.updated_at = utcnow()


async def account_skill_use_count(
    db: AsyncSession, user_id: int, skill_code: str
) -> int:
    """계정이 가진 모든 캐릭터의 같은 스킬 사용 횟수를 더한다.

    해금 조건은 캐릭터 한 명이 아니라 `내가 그 행동을 얼마나 해 봤는가`를 묻는다.
    캐릭터를 수확해도 쌓아 온 경험이 사라지지 않아야 한다.
    """

    total = await db.scalar(
        sa.select(sa.func.coalesce(sa.func.sum(PlantSkillMastery.use_count), 0))
        .select_from(PlantSkillMastery)
        .join(Plant, Plant.id == PlantSkillMastery.plant_id)
        .where(Plant.user_id == user_id, PlantSkillMastery.skill_code == skill_code)
    )
    return int(total or 0)


async def account_species_count(
    db: AsyncSession, user_id: int, skill_code: str, species_code: str
) -> int:
    """특정 품종의 캐릭터들만 모아 그 기록을 더한다.

    `여우비로 장벽 10회`처럼 **누가 했는지**를 묻는 조건이 있다. 캐릭터를
    수확해도 그 품종으로 쌓아 온 경험은 남는다.
    """

    total = await db.scalar(
        sa.select(sa.func.coalesce(sa.func.sum(PlantSkillMastery.use_count), 0))
        .select_from(PlantSkillMastery)
        .join(Plant, Plant.id == PlantSkillMastery.plant_id)
        .join(PlantSpecies, PlantSpecies.id == Plant.species_id)
        .where(
            Plant.user_id == user_id,
            PlantSkillMastery.skill_code == skill_code,
            PlantSpecies.code == species_code,
        )
    )
    return int(total or 0)


async def account_barrier_kinds(db: AsyncSession, user_id: int) -> int:
    """연 적 있는 장벽의 **가짓수**. 횟수가 아니다."""

    total = await db.scalar(
        sa.select(sa.func.count(sa.distinct(PlantSkillMastery.skill_code)))
        .select_from(PlantSkillMastery)
        .join(Plant, Plant.id == PlantSkillMastery.plant_id)
        .where(
            Plant.user_id == user_id,
            PlantSkillMastery.skill_code.startswith(BARRIER_KIND_PREFIX),
        )
    )
    return int(total or 0)


async def account_safe_returns(db: AsyncSession, user_id: int) -> int:
    """무사히 돌아온 탐험 횟수.

    `safe_returned`는 목표를 두고 스스로 돌아온 run이다. 도중에 물러난
    `retreated`는 세지 않는다 — `안전 귀환`이 묻는 것과 다르다.
    """

    total = await db.scalar(
        sa.select(sa.func.count())
        .select_from(ExpeditionRun)
        .where(
            ExpeditionRun.user_id == user_id,
            ExpeditionRun.status == "safe_returned",
        )
    )
    return int(total or 0)


# 해금·도전 조건 중 **지금 근거를 가진 것**만 여기 있다. 나머지는 조건을 세는
# 기록이 아직 없어 넣지 않는다 — 영원히 안 열릴 조건을 열린 척하지 않는다.
#
# 각 항목은 (기록서 코드, 획득 경로, 세는 스킬, 목표치)다.
MASTERY_UNLOCKS = (
    # 마음 지키기 누적 30회
    ("double_leaf", "unlock", "guard", 30),
)

# 품종을 함께 보는 조건. (코드, 획득 경로, 세는 기록, 품종, 목표치)
SPECIES_UNLOCKS = (
    # 여우비로 수호자 장벽 10회 열기
    ("nine_tail_afterimage", "challenge", BARRIER_OPEN_CODE, "gumiho-pot", 10),
    # 그림싹으로 약점 일치 공격 30회
    ("shadow_oath", "challenge", WEAKNESS_HIT_CODE, "ninja-pot", 30),
)

# 가짓수를 묻는 조건. (코드, 획득 경로, 목표 가짓수)
BARRIER_KIND_UNLOCKS = (
    # 수호자 장벽 3종 열기
    ("weakness_engrave", "unlock", 3),
)

# 런 결과를 묻는 조건. (코드, 획득 경로, 목표 횟수)
SAFE_RETURN_UNLOCKS = (
    # 안전 귀환 5회
    ("reviving_root", "unlock", 5),
)

# 지역 깊은 조사 최초 완주로 열리는 조건. (코드, 획득 경로, 지역 코드)
#
# **지역 콘텐츠가 있는 것만 사전 공개한다.** 아직 만들지 않은 지역의 조건을
# 내보내면 진행도 0/1이 영영 멈춰 있고, 사용자는 채울 수 없는 목표를 본다.
# 지역이 실리는 날 코드를 고칠 필요 없이 저절로 나타난다.
DEEP_SURVEY_UNLOCKS = (
    ("bellringer_chime", "challenge", "echo_well"),
    ("germination_gear", "challenge", "starlight_seed_vault"),
    ("ringcount_record", "challenge", "heartwood_observatory"),
)


async def account_deep_clears(
    db: AsyncSession, user_id: int, region_code: str
) -> int:
    """그 지역 깊은 조사를 완주한 횟수.

    새 카운터를 만들지 않는다 — 완주한 깊은 조사는 이미 `expedition_runs`에
    `mode='deep'` · `status='completed'`로 남아 있다. 안전 귀환을 세는 방식과 같다.
    """

    total = await db.scalar(
        sa.select(sa.func.count())
        .select_from(ExpeditionRun)
        .where(
            ExpeditionRun.user_id == user_id,
            ExpeditionRun.region_code == region_code,
            ExpeditionRun.mode == "deep",
            ExpeditionRun.status == "completed",
        )
    )
    return int(total or 0)


def _shipped_regions() -> frozenset[str]:
    """지금 콘텐츠가 실려 있는 지역. 없는 지역의 조건은 광고하지 않는다."""

    # 지연 import — `expeditions`가 이 모듈을 부르므로 위에서 부르면 순환한다.
    from app.services.expeditions import shipped_region_codes

    return shipped_region_codes()


# 깊은 조사로 열리는 세 권(`bellringer_chime`·`germination_gear`·
# `ringcount_record`)은 위 DEEP_SURVEY_UNLOCKS에 등록돼 있다. 예전에는 `deep`
# 모드도 없고 지역도 기억서고 하나뿐이라 영원히 참이 될 수 없어 빼 뒀는데,
# 그 뒤 네 지역과 깊은 조사가 들어오면서 조건이 실제로 채워진다. `shipped`
# 검사가 남아 있어 콘텐츠를 뺀 지역의 조건은 여전히 광고하지 않는다.

# 보유 권수로 열리는 조건. 스킬 사용이 아니라 서고 크기를 본다.
COLLECTION_UNLOCKS = (
    # 기록서 24종 보유
    ("heart_encyclopedia", "challenge", 24),
)


async def evaluate_skill_book_unlocks(
    db: AsyncSession, user_id: int
) -> list[dict[str, Any]]:
    """조건을 채운 기록서를 서고에 넣는다.

    이미 가진 책은 조용히 건너뛴다. 지급이 멱등이라 같은 전투 결과가 두 번
    처리돼도 두 장이 되지 않는다. 돌려주는 값은 `이번에 새로 열린 것`뿐이라
    호출부가 그대로 안내 문구에 쓸 수 있다.
    """

    owned = set(
        (
            await db.execute(
                sa.select(UserSkillBook.skill_book_code).where(
                    UserSkillBook.user_id == user_id
                )
            )
        )
        .scalars()
        .all()
    )
    granted: list[dict[str, Any]] = []

    for code, source, skill_code, goal in MASTERY_UNLOCKS:
        if code in owned:
            continue
        progress = await account_skill_use_count(db, user_id, skill_code)
        if progress < goal:
            continue
        await _grant_quietly(db, user_id, code, source, f"{skill_code}:{goal}")
        granted.append(_unlocked_payload(code, source, progress))

    for code, source, skill_code, species_code, goal in SPECIES_UNLOCKS:
        if code in owned:
            continue
        progress = await account_species_count(db, user_id, skill_code, species_code)
        if progress < goal:
            continue
        await _grant_quietly(
            db, user_id, code, source, f"{species_code}:{skill_code}:{goal}"
        )
        granted.append(_unlocked_payload(code, source, progress))

    for code, source, goal in BARRIER_KIND_UNLOCKS:
        if code in owned:
            continue
        progress = await account_barrier_kinds(db, user_id)
        if progress < goal:
            continue
        await _grant_quietly(db, user_id, code, source, f"barrier_kinds:{goal}")
        granted.append(_unlocked_payload(code, source, progress))

    for code, source, goal in SAFE_RETURN_UNLOCKS:
        if code in owned:
            continue
        progress = await account_safe_returns(db, user_id)
        if progress < goal:
            continue
        await _grant_quietly(db, user_id, code, source, f"safe_returned:{goal}")
        granted.append(_unlocked_payload(code, source, progress))

    shipped = _shipped_regions()
    for code, source, region_code in DEEP_SURVEY_UNLOCKS:
        if code in owned or region_code not in shipped:
            continue
        if await account_deep_clears(db, user_id, region_code) < 1:
            continue
        await _grant_quietly(db, user_id, code, source, f"deep:{region_code}")
        granted.append(_unlocked_payload(code, source, 1))

    for code, source, goal in COLLECTION_UNLOCKS:
        if code in owned or len(owned) < goal:
            continue
        await _grant_quietly(db, user_id, code, source, f"owned:{goal}")
        granted.append(_unlocked_payload(code, source, len(owned)))

    return granted


def _unlocked_payload(code: str, source: str, progress: int) -> dict[str, Any]:
    """앱이 그대로 안내에 쓸 수 있게 이름과 효과까지 함께 보낸다.

    코드만 보내면 앱이 카탈로그 사본을 따로 들고 있어야 하고, 그러면 두 곳이
    어긋난다. 서버가 이미 아는 값을 함께 실어 보낸다.
    """

    book = SKILL_BOOK_CATALOG.get(code) or {}
    return {
        "code": code,
        "source": source,
        "progress": progress,
        "name": book.get("name", code),
        "effect_summary": book.get("effect_summary", ""),
        "grade": book.get("grade"),
    }


async def _grant_quietly(
    db: AsyncSession, user_id: int, code: str, source: str, source_ref: str
) -> None:
    try:
        await grant_skill_book(
            db,
            user_id=user_id,
            code=code,
            acquire_source=source,
            source_ref=source_ref,
        )
    except AppError as error:
        # 다른 경로로 방금 들어왔으면 그대로 둔다. 해금이 전투를 막지 않는다.
        if error.code != "SKILL_BOOK_ALREADY_OWNED":
            raise


async def unlock_progress(db: AsyncSession, user_id: int) -> list[dict[str, Any]]:
    """조건을 사전 공개한다. 얼마나 남았는지 숨기지 않는다."""

    owned = set(
        (
            await db.execute(
                sa.select(UserSkillBook.skill_book_code).where(
                    UserSkillBook.user_id == user_id
                )
            )
        )
        .scalars()
        .all()
    )
    progress: list[dict[str, Any]] = []
    for code, source, skill_code, goal in MASTERY_UNLOCKS:
        progress.append(
            {
                "code": code,
                "source": source,
                "goal": goal,
                "current": min(goal, await account_skill_use_count(db, user_id, skill_code)),
                "owned": code in owned,
            }
        )
    for code, source, skill_code, species_code, goal in SPECIES_UNLOCKS:
        progress.append(
            {
                "code": code,
                "source": source,
                "goal": goal,
                "current": min(
                    goal,
                    await account_species_count(
                        db, user_id, skill_code, species_code
                    ),
                ),
                "owned": code in owned,
            }
        )
    for code, source, goal in BARRIER_KIND_UNLOCKS:
        progress.append(
            {
                "code": code,
                "source": source,
                "goal": goal,
                "current": min(goal, await account_barrier_kinds(db, user_id)),
                "owned": code in owned,
            }
        )
    for code, source, goal in SAFE_RETURN_UNLOCKS:
        progress.append(
            {
                "code": code,
                "source": source,
                "goal": goal,
                "current": min(goal, await account_safe_returns(db, user_id)),
                "owned": code in owned,
            }
        )
    shipped = _shipped_regions()
    for code, source, region_code in DEEP_SURVEY_UNLOCKS:
        if region_code not in shipped:
            continue
        progress.append(
            {
                "code": code,
                "source": source,
                "goal": 1,
                "current": min(1, await account_deep_clears(db, user_id, region_code)),
                "owned": code in owned,
                "region_code": region_code,
            }
        )
    for code, source, goal in COLLECTION_UNLOCKS:
        progress.append(
            {
                "code": code,
                "source": source,
                "goal": goal,
                "current": min(goal, len(owned)),
                "owned": code in owned,
            }
        )
    return progress
