from fastapi import APIRouter, Depends, Query, Request
from sqlalchemy.ext.asyncio import AsyncSession

from app.api import idempotency
from app.api.deps import get_current_user
from app.core.db import get_db
from app.models.user import User
from app.schemas.requests import (
    ExpeditionChoiceRequest,
    ExpeditionCombatTurnRequest,
    ExpeditionFinishRequest,
    ExpeditionMoveRequest,
    ExpeditionSkillRequest,
    ExpeditionStartRequest,
)
from app.services import expeditions as expedition_service
from app.services import game as game_service


router = APIRouter(prefix="/adventure/expeditions", tags=["expeditions"])


@router.get("/catalog")
async def expedition_catalog(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    return await expedition_service.catalog_payload(db, user.id)


@router.get("/roster")
async def expedition_roster(
    cursor: str | None = None,
    limit: int = Query(default=30, ge=1, le=50),
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    return await expedition_service.roster_payload(db, user.id, cursor, limit)


@router.get("/active")
async def active_expedition(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    return {"expedition": await expedition_service.active_payload(db, user.id)}


@router.get("/{run_id}")
async def expedition_detail(
    run_id: int,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    return await expedition_service.get_run_payload(db, user.id, run_id)


@router.post("")
async def start_expedition(
    body: ExpeditionStartRequest,
    request: Request,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    key = idempotency.require_key(request)

    async def handler():
        result = await expedition_service.start_run(
            db,
            user.id,
            region_code=body.region_code,
            mode=body.mode,
            plant_ids=body.plant_ids,
            guide_count=body.guide_count,
        )
        await db.flush()
        return 201, result

    async with game_service.inventory_lock(user.id):
        return await idempotency.run_idempotent(
            db,
            user.id,
            "interactive_expedition_start",
            key,
            body.model_dump(),
            handler,
        )


@router.post("/{run_id}/move")
async def move_expedition(
    run_id: int,
    body: ExpeditionMoveRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await expedition_service.move(
        db,
        user.id,
        run_id,
        node_code=body.node_code,
        expected_revision=body.expected_revision,
        client_action_id=body.client_action_id,
    )
    await db.commit()
    return result


@router.post("/{run_id}/choices")
async def choose_expedition_event(
    run_id: int,
    body: ExpeditionChoiceRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await expedition_service.choose(
        db,
        user.id,
        run_id,
        choice_code=body.choice_code,
        acting_member_id=body.acting_member_id,
        expected_revision=body.expected_revision,
        client_action_id=body.client_action_id,
    )
    await db.commit()
    return result


@router.post("/{run_id}/skills")
async def use_expedition_skill(
    run_id: int,
    body: ExpeditionSkillRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await expedition_service.use_skill(
        db,
        user.id,
        run_id,
        member_id=body.member_id,
        skill_type=body.skill_type,
        mode_code=body.mode_code,
        expected_revision=body.expected_revision,
        client_action_id=body.client_action_id,
    )
    await db.commit()
    return result


@router.post("/{run_id}/combat/turns")
async def resolve_expedition_combat_turn(
    run_id: int,
    body: ExpeditionCombatTurnRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await expedition_service.resolve_combat_turn(
        db,
        user.id,
        run_id,
        commands=[command.model_dump() for command in body.commands],
        partial=body.partial,
        expected_revision=body.expected_revision,
        client_action_id=body.client_action_id,
    )
    await db.commit()
    return result


@router.post("/{run_id}/extract")
async def extract_expedition(
    run_id: int,
    body: ExpeditionFinishRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    async with game_service.inventory_lock(user.id):
        result = await expedition_service.extract(
            db,
            user.id,
            run_id,
            expected_revision=body.expected_revision,
            client_action_id=body.client_action_id,
        )
        await db.commit()
        return result


@router.post("/{run_id}/retreat")
async def retreat_expedition(
    run_id: int,
    body: ExpeditionFinishRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await expedition_service.retreat(
        db,
        user.id,
        run_id,
        expected_revision=body.expected_revision,
        client_action_id=body.client_action_id,
    )
    await db.commit()
    return result
