"""장거리 개척 라우터.

합동 수호전과 같은 이유로 `/adventure/expeditions/…` 아래에 두지 않는다.
그 라우터에는 `/{run_id}`가 있어서 `journeys`가 run 번호로 먼저 읽힌다.
"""

from fastapi import APIRouter, Depends, Request
from sqlalchemy.ext.asyncio import AsyncSession

from app.api import idempotency
from app.api.deps import get_current_user
from app.core.db import get_db
from app.models.user import User
from app.schemas.requests import (
    JourneyLegRequest,
    JourneyReturnRequest,
    JourneyStartRequest,
)
from app.services import journeys as journey_service


router = APIRouter(prefix="/adventure/journeys", tags=["journeys"])


@router.get("")
async def journey_entry(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    return await journey_service.entry_payload(db, user.id)


@router.get("/active")
async def active_journey(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    return await journey_service.active(db, user.id)


@router.get("/{journey_id}")
async def get_journey(
    journey_id: int,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    return await journey_service.get(db, user.id, journey_id)


@router.post("")
async def start_journey(
    body: JourneyStartRequest,
    request: Request,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    key = idempotency.require_key(request)

    async def handler():
        result = await journey_service.start(
            db,
            user.id,
            direction_code=body.direction_code,
            mode=body.mode,
        )
        await db.flush()
        return 201, result

    return await idempotency.run_idempotent(
        db, user.id, "journey_start", key, body.model_dump(), handler
    )


@router.post("/{journey_id}/legs")
async def create_journey_leg(
    journey_id: int,
    body: JourneyLegRequest,
    request: Request,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    key = idempotency.require_key(request)

    async def handler():
        result = await journey_service.create_leg(
            db,
            user.id,
            journey_id,
            route_choice_code=body.route_choice_code,
            plant_ids=list(body.plant_ids),
            guide_count=body.guide_count,
            expected_revision=body.expected_revision,
        )
        await db.flush()
        return 201, result

    return await idempotency.run_idempotent(
        db,
        user.id,
        "journey_leg",
        key,
        {"journey_id": journey_id, **body.model_dump()},
        handler,
    )


@router.post("/{journey_id}/return")
async def return_journey(
    journey_id: int,
    body: JourneyReturnRequest,
    request: Request,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    key = idempotency.require_key(request)

    async def handler():
        result = await journey_service.return_home(
            db,
            user.id,
            journey_id,
            expected_revision=body.expected_revision,
            selected_loot_ids=body.selected_loot_ids,
        )
        await db.flush()
        return 200, result

    return await idempotency.run_idempotent(
        db,
        user.id,
        "journey_return",
        key,
        {"journey_id": journey_id, **body.model_dump()},
        handler,
    )
