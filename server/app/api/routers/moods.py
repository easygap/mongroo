import sqlalchemy as sa
from fastapi import APIRouter, Depends, Query, Request
from fastapi.responses import Response
from sqlalchemy.ext.asyncio import AsyncSession

from app.api import idempotency
from app.api.deps import decode_cursor, get_current_user, get_owned
from app.api.errors import AppError
from app.core.db import get_db
from app.models.mood import MoodEntry
from app.models.user import User
from app.schemas.requests import MoodCreateRequest, MoodPatchRequest
from app.services import moods as mood_service, plants as plant_service, rewards

router = APIRouter(tags=["moods"])

PAGE_SIZE = 20


@router.post("/moods")
async def create_mood(
    body: MoodCreateRequest,
    request: Request,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    key = idempotency.require_key(request)

    async def handler():
        entry, outcome, safety_action = await mood_service.create_mood(
            db, user.id, body.mood_level, body.emotion_tags, body.content
        )
        await db.flush()
        return 201, {
            "mood": mood_service.mood_payload(entry),
            "reward": outcome.payload(),
            "safety_action": safety_action,
        }

    return await idempotency.run_idempotent(
        db, user.id, "mood_create", key, body.model_dump(), handler
    )


@router.get("/moods/calendar")
async def calendar(
    year: int = Query(ge=2020, le=2100),
    month: int = Query(ge=1, le=12),
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    days = await mood_service.calendar_summary(db, user.id, year, month)
    return {"year": year, "month": month, "days": days}


@router.get("/moods")
async def list_moods(
    date: str,
    cursor: str | None = None,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    from datetime import date as date_type

    try:
        target = date_type.fromisoformat(date)
    except ValueError:
        raise AppError(422, "VALIDATION_ERROR", "date는 YYYY-MM-DD 형식이어야 합니다.")

    query = (
        sa.select(MoodEntry)
        .where(MoodEntry.user_id == user.id, MoodEntry.local_date == target)
        .order_by(MoodEntry.id.desc())
        .limit(PAGE_SIZE + 1)
    )
    cursor_id = decode_cursor(cursor)
    if cursor_id is not None:
        query = query.where(MoodEntry.id < cursor_id)
    rows = list((await db.execute(query)).scalars())
    next_cursor = str(rows[PAGE_SIZE - 1].id) if len(rows) > PAGE_SIZE else None
    return {
        "items": [mood_service.mood_payload(e) for e in rows[:PAGE_SIZE]],
        "next_cursor": next_cursor,
    }


@router.get("/moods/{mood_id}")
async def get_mood(
    mood_id: int,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    entry = await get_owned(db, MoodEntry, mood_id, user.id, "MOOD_NOT_FOUND")
    return mood_service.mood_payload(entry)


@router.patch("/moods/{mood_id}")
async def patch_mood(
    mood_id: int,
    body: MoodPatchRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    fields = body.model_dump(exclude_unset=True)
    expected_version = fields.pop("expected_version", None)
    async with mood_service.edit_lock(mood_id):
        # 모든 쓰기 경로의 잠금 순서를 user → active plant → mood로 맞춘다.
        await rewards.lock_user(db, user.id)
        plant = await rewards.lock_active_plant(db, user.id)
        entry = await mood_service.lock_mood_for_edit(
            db, mood_id, user.id, expected_version
        )
        if fields:
            await mood_service.advance_edit_version(db, entry)
        entry, outcome, safety_action = await mood_service.patch_mood(db, entry, fields)
        await db.flush()
        if "content" in fields and plant is not None:
            await plant_service.refresh_active_plant_growth(
                db, user.id, plant=plant, lock_entries=True
            )
        await db.commit()
    await db.refresh(entry)
    return {
        "mood": mood_service.mood_payload(entry),
        "reward": outcome.payload(),
        "safety_action": safety_action,
    }


@router.delete("/moods/{mood_id}", status_code=204)
async def delete_mood(
    mood_id: int,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    await rewards.lock_user(db, user.id)
    plant = await rewards.lock_active_plant(db, user.id)
    entry = await get_owned(db, MoodEntry, mood_id, user.id, "MOOD_NOT_FOUND")
    await db.delete(entry)
    await db.flush()
    if plant is not None:
        await plant_service.refresh_active_plant_growth(
            db, user.id, plant=plant, lock_entries=True
        )
    await db.commit()
    return Response(status_code=204)
