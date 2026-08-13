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
from app.models.plant import Plant
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
        row.mastery_level = mastery_level_for(row.use_count)
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


# 해금·도전 조건 중 **지금 근거를 가진 것**만 여기 있다. 나머지는 조건을 세는
# 기록이 아직 없어 넣지 않는다 — 영원히 안 열릴 조건을 열린 척하지 않는다.
#
# 각 항목은 (기록서 코드, 획득 경로, 세는 스킬, 목표치)다.
MASTERY_UNLOCKS = (
    # 마음 지키기 누적 30회
    ("double_leaf", "unlock", "guard", 30),
)

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
