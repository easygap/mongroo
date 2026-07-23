from fastapi import APIRouter, Depends, Request
from sqlalchemy.ext.asyncio import AsyncSession

from app.api import idempotency
from app.api.deps import get_current_user
from app.core.db import get_db
from app.models.user import User
from app.schemas.requests import FarmLayoutRequest
from app.services import game as game_service


router = APIRouter(tags=["game"])


@router.get("/quests/today")
async def today_quest(
    user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)
):
    return await game_service.get_or_assign_today(db, user.id)


@router.post("/user-quests/{user_quest_id}/complete")
async def complete_quest(
    user_quest_id: int,
    request: Request,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    key = idempotency.require_key(request)

    async def handler():
        result = await game_service.complete_quest(db, user.id, user_quest_id)
        await db.flush()
        return 200, result

    return await idempotency.run_idempotent(
        db, user.id, "quest_complete", key, {"user_quest_id": user_quest_id}, handler
    )


@router.post("/user-quests/{user_quest_id}/skip")
async def skip_quest(
    user_quest_id: int,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    return await game_service.skip_quest(db, user.id, user_quest_id)


@router.get("/shop/items")
async def shop_items(
    user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)
):
    return await game_service.shop_items(db, user)


@router.post("/shop/items/{item_id}/purchase")
async def purchase_item(
    item_id: int,
    request: Request,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    key = idempotency.require_key(request)

    async def handler():
        result = await game_service.purchase_item(db, user.id, item_id)
        await db.flush()
        return 200, result

    async with game_service.inventory_lock(user.id):
        # user FK를 가진 idempotency row보다 DB user 잠금을 먼저 잡아
        # 다중 프로세스의 S→X lock upgrade 교착을 피한다.
        await game_service.lock_inventory_user(db, user.id)
        return await idempotency.run_idempotent(
            db, user.id, "shop_item_purchase", key, {"item_id": item_id}, handler
        )


@router.post("/shop/items/{item_id}/claim")
async def claim_item(
    item_id: int,
    request: Request,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    key = idempotency.require_key(request)

    async def handler():
        result = await game_service.claim_item(db, user.id, item_id)
        await db.flush()
        return 200, result

    async with game_service.inventory_lock(user.id):
        await game_service.lock_inventory_user(db, user.id)
        return await idempotency.run_idempotent(
            db, user.id, "shop_item_claim", key, {"item_id": item_id}, handler
        )


@router.get("/shop/plant-species")
async def shop_plant_species(
    user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)
):
    return await game_service.shop_species(db, user.id)


@router.post("/shop/plant-species/{species_id}/purchase")
async def purchase_plant_species(
    species_id: int,
    request: Request,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    key = idempotency.require_key(request)

    async def handler():
        result = await game_service.purchase_species(db, user.id, species_id)
        await db.flush()
        return 200, result

    async with game_service.inventory_lock(user.id):
        await game_service.lock_inventory_user(db, user.id)
        return await idempotency.run_idempotent(
            db, user.id, "shop_species_purchase", key, {"species_id": species_id}, handler
        )


@router.get(
    "/collection",
    summary="보유 인벤토리와 전체 도감 조회",
    description=(
        "`items`는 보유 인벤토리, `catalog_items`는 잠금 항목을 포함한 전체 활성 "
        "아이템 도감입니다. 0003 캐릭터 카탈로그 10종을 포함하며, catalog_items "
        "항목의 `owned`/`locked`로 해금 상태를 표시합니다. `acquisition`은 "
        "`type`, `label`, `current`, `target`, `eligible`로 현재 획득 진행도를 제공합니다."
    ),
)
async def collection(
    user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)
):
    return await game_service.collection_payload(db, user)


@router.get("/farm")
async def farm(
    user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)
):
    return await game_service.farm_payload(db, user.id)


@router.put("/farm/layout")
async def save_farm_layout(
    body: FarmLayoutRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    return await game_service.save_farm_layout(db, user.id, body)
