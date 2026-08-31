"""합동 수호전 라우터.

경로를 `/adventure/expeditions/…` 아래에 두지 않는다. 그 라우터에는 이미
`/{run_id}`가 있어서 `joint-guard`가 run 번호로 먼저 읽히고 422가 난다.
형제 경로로 두면 순서에 기대지 않아도 된다.
"""

from fastapi import APIRouter, Depends, Request
from sqlalchemy.ext.asyncio import AsyncSession

from app.api import idempotency
from app.api.deps import get_current_user
from app.core.db import get_db
from app.models.user import User
from app.schemas.requests import (
    JointGuardStartRequest,
    JointGuardSwapRequest,
    JointGuardTurnRequest,
)
from app.services import joint_guard as joint_guard_service


router = APIRouter(prefix="/adventure/joint-guard", tags=["joint-guard"])


@router.get("")
async def joint_guard_entry(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    return await joint_guard_service.entry_payload(db, user.id)


@router.get("/active")
async def active_joint_guard(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    return await joint_guard_service.active(db, user.id)


@router.post("")
async def start_joint_guard(
    body: JointGuardStartRequest,
    request: Request,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    key = idempotency.require_key(request)

    async def handler():
        result = await joint_guard_service.start(
            db,
            user.id,
            beast_code=body.beast_code,
            difficulty=body.difficulty,
            formation=[slot.model_dump() for slot in body.formation],
        )
        await db.flush()
        return 201, result

    return await idempotency.run_idempotent(
        db,
        user.id,
        "joint_guard_start",
        key,
        body.model_dump(),
        handler,
    )


@router.post("/{run_id}/turns")
async def submit_joint_guard_turn(
    run_id: int,
    body: JointGuardTurnRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await joint_guard_service.submit_turn(
        db,
        user.id,
        run_id,
        command=body.command.model_dump(),
        expected_revision=body.expected_revision,
        client_action_id=body.client_action_id,
    )
    await db.commit()
    return result


@router.post("/{run_id}/swap")
async def swap_joint_guard(
    run_id: int,
    body: JointGuardSwapRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await joint_guard_service.swap(
        db,
        user.id,
        run_id,
        out_member_id=body.out_member_id,
        in_member_id=body.in_member_id,
        expected_revision=body.expected_revision,
        client_action_id=body.client_action_id,
    )
    await db.commit()
    return result
