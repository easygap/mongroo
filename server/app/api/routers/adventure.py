from fastapi import APIRouter, Depends, Request
from sqlalchemy.ext.asyncio import AsyncSession

from app.api import idempotency
from app.api.deps import get_current_user
from app.core.db import get_db
from app.models.user import User
from app.schemas.requests import PatrolStartRequest
from app.services import adventure as adventure_service
from app.services import game as game_service


router = APIRouter(prefix="/adventure", tags=["adventure"])


@router.get("")
async def adventure_state(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    return await adventure_service.state_payload(db, user.id)


@router.post("/patrols")
async def start_patrol(
    body: PatrolStartRequest,
    request: Request,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    key = idempotency.require_key(request)

    async def handler():
        result = await adventure_service.start_patrol(db, user.id, body.route_code)
        await db.flush()
        return 201, result

    async with game_service.inventory_lock(user.id):
        return await idempotency.run_idempotent(
            db,
            user.id,
            "adventure_patrol_start",
            key,
            body.model_dump(),
            handler,
        )


@router.post("/patrols/{patrol_id}/claim")
async def claim_patrol(
    patrol_id: int,
    request: Request,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    key = idempotency.require_key(request)

    async def handler():
        result = await adventure_service.claim_patrol(db, user.id, patrol_id)
        await db.flush()
        return 200, result

    async with game_service.inventory_lock(user.id):
        return await idempotency.run_idempotent(
            db,
            user.id,
            "adventure_patrol_claim",
            key,
            {"patrol_id": patrol_id},
            handler,
        )


@router.post("/dungeons/{dungeon_code}/run")
async def run_dungeon(
    dungeon_code: str,
    request: Request,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    key = idempotency.require_key(request)

    async def handler():
        result = await adventure_service.run_dungeon(db, user.id, dungeon_code)
        await db.flush()
        return 200, result

    async with game_service.inventory_lock(user.id):
        return await idempotency.run_idempotent(
            db,
            user.id,
            "adventure_dungeon_run",
            key,
            {"dungeon_code": dungeon_code},
            handler,
        )
