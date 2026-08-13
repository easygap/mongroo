"""마음결 기록서의 소유와 장착 서비스.

두 가지를 나눠서 다룬다.

* **소유** — 계정이 무엇을 가졌나. 지급은 멱등이고, 같은 책을 두 번 주려는
  시도는 행을 늘리지 않고 409로 막는다. 씨앗을 차감하기 전에 여기서 먼저
  걸러야 중복 구매로 재화가 새지 않는다.
* **장착** — 어느 캐릭터의 어느 프리셋에 넣었나. 보유해도 자동 장착하지 않고,
  같은 책을 여러 캐릭터·프리셋에 저장하는 것도 허용한다. 계정 라이선스이기
  때문이다. 실제로 함께 출발하는 파티 안에서만 중복을 막는다.

판정 규칙의 단일 원본은 `app/content/expeditions/skill_books.py`이고, 이 모듈은
저장소와 그 규칙을 잇는다.
"""

from __future__ import annotations

from typing import Any, Iterable

import sqlalchemy as sa
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.errors import AppError
from app.content.expeditions.skill_books import (
    GRADE_ALLOWED_SLOTS,
    SKILL_BOOK_CATALOG,
    SLOT_UNLOCK_LEVEL,
    EMOTION_POINTERS,
    resolve_loadout,
)
from app.core.timeutil import utcnow
from app.models.plant import Plant
from app.models.skill_book import PlantSkillLoadout, UserSkillBook
from app.services.plants import level_from_exp


# 11.5 — 세 가지 프리셋. 늘리려면 설계서를 먼저 고친다.
PRESET_CODES = ("explore", "guard", "personal")
DEFAULT_PRESET = "guard"

ACQUIRE_SOURCES = (
    "shop",
    "unlock",
    "challenge",
    "starter_choice",
    "balance_replacement",
    "refund_restore",
)


async def owned_book_codes(session: AsyncSession, user_id: int) -> set[str]:
    rows = await session.execute(
        sa.select(UserSkillBook.skill_book_code).where(
            UserSkillBook.user_id == user_id
        )
    )
    return set(rows.scalars().all())


async def list_owned_books(
    session: AsyncSession, user_id: int
) -> list[dict[str, Any]]:
    """보유 목록을 카탈로그 정보와 함께 돌려준다.

    카탈로그에서 사라진 코드(운영 중 비활성)도 보유는 유지되므로 함께 내려
    보내되 `catalog_missing`으로 표시한다. 기존 보유는 계속 쓸 수 있어야 한다.
    """

    rows = await session.execute(
        sa.select(UserSkillBook)
        .where(UserSkillBook.user_id == user_id)
        .order_by(UserSkillBook.acquired_at.asc(), UserSkillBook.id.asc())
    )
    owned: list[dict[str, Any]] = []
    for row in rows.scalars().all():
        book = SKILL_BOOK_CATALOG.get(row.skill_book_code)
        owned.append(
            {
                "code": row.skill_book_code,
                "acquired_at": row.acquired_at,
                "acquire_source": row.acquire_source,
                "source_ref": row.source_ref,
                "catalog_missing": book is None,
                "book": dict(book) if book is not None else None,
            }
        )
    return owned


async def grant_skill_book(
    session: AsyncSession,
    *,
    user_id: int,
    code: str,
    acquire_source: str,
    source_ref: str | None = None,
) -> UserSkillBook:
    """기록서 한 권을 계정에 넣는다. 중복은 409로 막는다.

    씨앗 차감·해금 기록 같은 부수 효과보다 **먼저** 불러야 한다. 중복 구매로
    재화가 새는 것을 여기서 끊는다. 유일 제약이 최종 방어선이라 경쟁 상태에서도
    두 장이 되지 않는다.
    """

    if code not in SKILL_BOOK_CATALOG:
        raise AppError(404, "SKILL_BOOK_NOT_FOUND", "알 수 없는 기록서입니다.")
    if acquire_source not in ACQUIRE_SOURCES:
        raise AppError(422, "SKILL_BOOK_SOURCE_INVALID", "알 수 없는 획득 경로입니다.")

    existing = await session.scalar(
        sa.select(UserSkillBook).where(
            UserSkillBook.user_id == user_id,
            UserSkillBook.skill_book_code == code,
        )
    )
    if existing is not None:
        raise AppError(
            409,
            "SKILL_BOOK_ALREADY_OWNED",
            "이미 서고에 있는 기록서예요.",
            {"code": code},
        )

    row = UserSkillBook(
        user_id=user_id,
        skill_book_code=code,
        acquired_at=utcnow(),
        acquire_source=acquire_source,
        source_ref=source_ref,
    )
    session.add(row)
    try:
        await session.flush()
    except IntegrityError as error:
        # 같은 요청이 동시에 두 번 들어온 경우. 유일 제약이 잡아 준다.
        await session.rollback()
        raise AppError(
            409,
            "SKILL_BOOK_ALREADY_OWNED",
            "이미 서고에 있는 기록서예요.",
            {"code": code},
        ) from error
    return row


async def _owned_plant(session: AsyncSession, user_id: int, plant_id: int) -> Plant:
    plant = await session.scalar(
        sa.select(Plant).where(Plant.id == plant_id, Plant.user_id == user_id)
    )
    if plant is None:
        raise AppError(404, "PLANT_NOT_FOUND", "캐릭터를 찾을 수 없습니다.")
    return plant


def _plant_level(plant: Plant) -> int:
    """장착 검사에 쓰는 전투 레벨.

    레벨은 컬럼이 아니라 누적 EXP에서 파생된다. 캐릭터 상세가 보여 주는 레벨과
    장착 화면이 여는 슬롯이 어긋나면 사용자는 이유를 알 수 없으므로, 화면과
    같은 `level_from_exp`를 그대로 쓴다.
    """

    return max(1, min(30, level_from_exp(int(plant.exp or 0))))


async def get_loadout(
    session: AsyncSession,
    *,
    user_id: int,
    plant_id: int,
    preset_code: str = DEFAULT_PRESET,
) -> dict[str, Any]:
    """저장된 장착과, 그것을 실제로 해석한 결과를 함께 돌려준다.

    앱은 두 가지를 모두 알아야 한다. 무엇을 저장했는지(사용자가 고른 것)와
    지금 그것이 어떻게 읽히는지(레벨·보유 상태에 따른 결과)다. 둘이 다를 때
    `fell_back`과 이유가 왜 다른지 설명한다.
    """

    if preset_code not in PRESET_CODES:
        raise AppError(422, "LOADOUT_PRESET_INVALID", "알 수 없는 프리셋입니다.")
    plant = await _owned_plant(session, user_id, plant_id)
    row = await session.scalar(
        sa.select(PlantSkillLoadout).where(
            PlantSkillLoadout.plant_id == plant_id,
            PlantSkillLoadout.preset_code == preset_code,
        )
    )
    stored = {
        "slot_b1_code": row.slot_b1_code if row else None,
        "slot_b2_code": row.slot_b2_code if row else None,
    }
    owned = await owned_book_codes(session, user_id)
    level = _plant_level(plant)
    return {
        "plant_id": plant_id,
        "preset_code": preset_code,
        "revision": int(row.revision) if row else 0,
        "level": level,
        "stored": stored,
        "resolved": resolve_loadout(stored, owned_codes=owned, level=level),
        "slot_unlock_level": dict(SLOT_UNLOCK_LEVEL),
    }


def _validate_slot(
    slot: str,
    code: str | None,
    *,
    owned: set[str],
    level: int,
) -> None:
    """저장 요청 하나를 검사한다.

    해석 단계는 잘못된 장착을 막지 않고 기본값으로 내려오지만, **저장은 막는다.**
    출발 직전에 조용히 다른 스킬이 나가는 것보다, 고르는 순간에 왜 안 되는지
    알려 주는 편이 낫다.
    """

    if code is None or code in EMOTION_POINTERS:
        return
    book = SKILL_BOOK_CATALOG.get(code)
    if book is None:
        raise AppError(
            422,
            "LOADOUT_BOOK_NOT_COMBAT",
            "이 기록서는 전투에서 쉬어요.",
            {"slot": slot, "code": code},
        )
    if code not in owned:
        raise AppError(
            403,
            "LOADOUT_BOOK_NOT_OWNED",
            "아직 서고에 없는 기록서예요.",
            {"slot": slot, "code": code},
        )
    if slot not in GRADE_ALLOWED_SLOTS[int(book["grade"])]:
        raise AppError(
            422,
            "LOADOUT_SLOT_GRADE",
            "3등급 기록서는 두 번째 칸에서만 펼쳐져요.",
            {"slot": slot, "code": code},
        )
    if level < SLOT_UNLOCK_LEVEL[slot]:
        raise AppError(
            422,
            "LOADOUT_SLOT_LOCKED",
            f"Lv{SLOT_UNLOCK_LEVEL[slot]}부터 열리는 칸이에요.",
            {"slot": slot, "code": code},
        )


async def save_loadout(
    session: AsyncSession,
    *,
    user_id: int,
    plant_id: int,
    preset_code: str,
    slot_b1_code: str | None,
    slot_b2_code: str | None,
    expected_revision: int | None = None,
) -> dict[str, Any]:
    """장착을 저장한다. 전투 중에는 부르지 않는다(출발 전·캐릭터 화면 전용)."""

    if preset_code not in PRESET_CODES:
        raise AppError(422, "LOADOUT_PRESET_INVALID", "알 수 없는 프리셋입니다.")
    plant = await _owned_plant(session, user_id, plant_id)
    owned = await owned_book_codes(session, user_id)
    level = _plant_level(plant)

    _validate_slot("B1", slot_b1_code, owned=owned, level=level)
    _validate_slot("B2", slot_b2_code, owned=owned, level=level)

    # 같은 책을 한 캐릭터의 두 칸에 넣을 수 없다. 계정에 한 장뿐이다.
    #
    # 이 검사가 stack_group보다 **먼저** 와야 한다. 같은 책은 당연히 같은
    # stack_group이라, 순서를 바꾸면 `같은 결` 안내가 먼저 나가고 정작 무엇이
    # 문제인지(같은 책을 두 번 넣었다) 알려 주지 못한다.
    if (
        slot_b1_code is not None
        and slot_b1_code == slot_b2_code
        and slot_b1_code not in EMOTION_POINTERS
    ):
        raise AppError(
            422,
            "LOADOUT_DUPLICATE_BOOK",
            "같은 기록서를 두 칸에 둘 수 없어요.",
            {"code": slot_b1_code},
        )

    # 두 칸이 같은 결을 쓰면 효과가 겹쳐 예산을 벗어난다.
    books = [
        SKILL_BOOK_CATALOG[code]
        for code in (slot_b1_code, slot_b2_code)
        if code in SKILL_BOOK_CATALOG
    ]
    groups = [str(book["stack_group"]) for book in books]
    if len(groups) != len(set(groups)):
        raise AppError(
            422,
            "LOADOUT_STACK_CONFLICT",
            "같은 결의 기록서를 두 칸에 함께 둘 수 없어요.",
            {"stack_group": groups[0] if groups else None},
        )

    row = await session.scalar(
        sa.select(PlantSkillLoadout).where(
            PlantSkillLoadout.plant_id == plant_id,
            PlantSkillLoadout.preset_code == preset_code,
        )
    )
    current_revision = int(row.revision) if row else 0
    if expected_revision is not None and expected_revision != current_revision:
        raise AppError(
            409,
            "LOADOUT_REVISION_CONFLICT",
            "다른 화면에서 먼저 바뀌었어요. 다시 불러오고 저장해 주세요.",
            {"revision": current_revision},
        )

    if row is None:
        row = PlantSkillLoadout(
            plant_id=plant_id,
            preset_code=preset_code,
            user_id=user_id,
            slot_b1_code=slot_b1_code,
            slot_b2_code=slot_b2_code,
            revision=1,
            updated_at=utcnow(),
        )
        session.add(row)
    else:
        row.slot_b1_code = slot_b1_code
        row.slot_b2_code = slot_b2_code
        row.revision = current_revision + 1
        row.updated_at = utcnow()
    await session.flush()

    stored = {"slot_b1_code": slot_b1_code, "slot_b2_code": slot_b2_code}
    return {
        "plant_id": plant_id,
        "preset_code": preset_code,
        "revision": int(row.revision),
        "level": level,
        "stored": stored,
        "resolved": resolve_loadout(stored, owned_codes=owned, level=level),
        "slot_unlock_level": dict(SLOT_UNLOCK_LEVEL),
    }


def assert_party_books_unique(loadouts: Iterable[dict[str, Any]]) -> None:
    """출발하는 파티 안에서 같은 기록서를 두 번 쓰지 못하게 막는다.

    저장 단계에서는 허용한다 — 계정 라이선스라 여러 캐릭터의 프리셋에 같은 책을
    담아 둘 수 있다. 실제로 그 캐릭터들이 **함께 출발할 때만** 막는다.
    서로 다른 캐릭터의 같은 감정 family는 허용한다.
    """

    seen: dict[str, int] = {}
    for loadout in loadouts:
        stored = loadout.get("stored") or loadout
        for key in ("slot_b1_code", "slot_b2_code"):
            code = stored.get(key)
            if code is None or code in EMOTION_POINTERS:
                continue
            if code not in SKILL_BOOK_CATALOG:
                continue
            seen[code] = seen.get(code, 0) + 1
            if seen[code] > 1:
                raise AppError(
                    422,
                    "PARTY_DUPLICATE_SKILL_BOOK",
                    "한 파티에서 같은 기록서를 두 번 쓸 수 없어요.",
                    {"code": code},
                )
