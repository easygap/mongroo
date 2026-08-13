from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.content.expeditions.skill_books import SKILL_BOOK_CATALOG
from app.core.db import get_db
from app.models.user import User
from app.schemas.requests import SkillBookLoadoutRequest
from app.services import skill_books as skill_book_service
from app.services import skill_mastery


router = APIRouter(prefix="/skill-books", tags=["skill-books"])


@router.get("")
async def skill_book_library(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """서고 화면의 단일 응답 — 카탈로그 전체와 내가 가진 것.

    카탈로그를 통째로 내려보내는 이유는 획득 경로를 **사전 공개**해야 하기
    때문이다. 아직 없는 책도 어디서 얻는지 보여 준다. 확률이 없는 게임이라
    숨길 이유가 없다.
    """

    owned = await skill_book_service.list_owned_books(db, user.id)
    owned_codes = {entry["code"] for entry in owned}
    return {
        "catalog": [
            {**book, "owned": code in owned_codes}
            for code, book in SKILL_BOOK_CATALOG.items()
        ],
        "owned": owned,
        "presets": list(skill_book_service.PRESET_CODES),
        # 해금·도전 조건은 사전 공개한다. 얼마나 남았는지 숨기지 않는다.
        "unlock_progress": await skill_mastery.unlock_progress(db, user.id),
    }


@router.get("/loadouts/{plant_id}")
async def read_loadout(
    plant_id: int,
    preset_code: str = Query(default=skill_book_service.DEFAULT_PRESET),
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    return await skill_book_service.get_loadout(
        db,
        user_id=user.id,
        plant_id=plant_id,
        preset_code=preset_code,
    )


@router.put("/loadouts/{plant_id}")
async def write_loadout(
    plant_id: int,
    body: SkillBookLoadoutRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """장착을 저장한다.

    멱등 키를 요구하지 않는다. 같은 내용을 두 번 저장해도 결과가 같은 덮어쓰기이고,
    재화가 움직이지 않기 때문이다. 대신 `expected_revision`으로 다른 화면이
    먼저 바꾼 경우를 잡는다.
    """

    result = await skill_book_service.save_loadout(
        db,
        user_id=user.id,
        plant_id=plant_id,
        preset_code=body.preset_code,
        slot_b1_code=body.slot_b1_code,
        slot_b2_code=body.slot_b2_code,
        expected_revision=body.expected_revision,
    )
    await db.commit()
    return result
