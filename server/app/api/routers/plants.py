from typing import Literal

import sqlalchemy as sa
from fastapi import APIRouter, Depends, Query, Request
from sqlalchemy.ext.asyncio import AsyncSession

from app.api import idempotency
from app.api.deps import decode_cursor, get_current_user
from app.api.errors import AppError
from app.core.db import get_db
from app.core.timeutil import to_utc_iso, utcnow
from app.models.enums import PlantStatus
from app.models.game import UserSpeciesUnlock
from app.models.plant import Plant, PlantSpecies
from app.models.user import User
from app.schemas.requests import PlantCreateRequest, PlantMuseumFeatureRequest
from app.services import plants as plant_service
from app.services.rewards import lock_active_plant, lock_user

router = APIRouter(tags=["plants"])

PAGE_SIZE = 20


def _museum_payload(plant: Plant, species: PlantSpecies) -> dict:
    payload = plant_service.museum_plant_payload(plant, species)
    payload["planted_at"] = to_utc_iso(payload["planted_at"])
    payload["harvested_at"] = to_utc_iso(payload["harvested_at"])
    return payload


@router.get("/plant-species")
async def list_species(
    user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)
):
    rows = await db.execute(sa.select(PlantSpecies).order_by(PlantSpecies.id))
    unlocked_ids = set((await db.execute(
        sa.select(UserSpeciesUnlock.species_id).where(UserSpeciesUnlock.user_id == user.id)
    )).scalars())
    return {
        "items": [
            {
                "id": s.id, "code": s.code, "name": s.name,
                "rarity": s.rarity, "unlock_price": s.unlock_price,
                "asset_manifest": s.asset_manifest,
                "is_unlocked": s.unlock_price == 0 or s.id in unlocked_ids,
            }
            for s in rows.scalars()
        ]
    }


@router.get("/plants/me")
async def my_plant(user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    plant = await db.scalar(
        sa.select(Plant).where(
            Plant.user_id == user.id, Plant.status == PlantStatus.ACTIVE
        )
    )
    if plant is None:
        return {"plant": None}
    species = await db.get(PlantSpecies, plant.species_id)
    payload = plant_service.plant_payload(plant, species)
    payload["planted_at"] = to_utc_iso(payload["planted_at"])
    return {"plant": payload}


@router.get("/plants")
async def list_plants(
    status: str = "harvested",
    cursor: str | None = None,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    if status != PlantStatus.HARVESTED:
        raise AppError(422, "VALIDATION_ERROR", "status는 harvested만 지원합니다.")
    query = (
        sa.select(Plant)
        .where(Plant.user_id == user.id, Plant.status == PlantStatus.HARVESTED)
        .order_by(Plant.id.desc())
        .limit(PAGE_SIZE + 1)
    )
    cursor_id = decode_cursor(cursor)
    if cursor_id is not None:
        query = query.where(Plant.id < cursor_id)
    rows = list((await db.execute(query)).scalars())

    species_map = {}
    if rows:
        species_rows = await db.execute(
            sa.select(PlantSpecies).where(
                PlantSpecies.id.in_({p.species_id for p in rows})
            )
        )
        species_map = {s.id: s for s in species_rows.scalars()}

    items = [_museum_payload(p, species_map[p.species_id]) for p in rows[:PAGE_SIZE]]
    next_cursor = str(rows[PAGE_SIZE - 1].id) if len(rows) > PAGE_SIZE else None
    return {"items": items, "next_cursor": next_cursor}


@router.get("/plants/museum")
async def plant_museum(
    mode: Literal["recent", "featured"] = "recent",
    limit: int = Query(default=10, ge=1, le=10),
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    query = sa.select(Plant).where(
        Plant.user_id == user.id,
        Plant.status == PlantStatus.HARVESTED,
    )
    if mode == "featured":
        query = query.where(Plant.museum_featured.is_(True))
    rows = list(
        (
            await db.execute(
                query.order_by(Plant.harvested_at.desc(), Plant.id.desc()).limit(limit)
            )
        ).scalars()
    )

    species_map = {}
    if rows:
        species_rows = await db.execute(
            sa.select(PlantSpecies).where(
                PlantSpecies.id.in_({plant.species_id for plant in rows})
            )
        )
        species_map = {species.id: species for species in species_rows.scalars()}

    return {
        "items": [
            _museum_payload(plant, species_map[plant.species_id]) for plant in rows
        ],
        "mode": mode,
        "limit": limit,
        "max_featured": plant_service.MUSEUM_MAX_FEATURED,
    }


@router.patch("/plants/{plant_id}/museum")
async def set_museum_featured(
    plant_id: int,
    body: PlantMuseumFeatureRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    candidate = await db.get(Plant, plant_id)
    if candidate is None:
        raise AppError(404, "PLANT_NOT_FOUND", "식물을 찾을 수 없습니다.")
    if candidate.user_id != user.id:
        raise AppError(403, "FORBIDDEN", "접근 권한이 없습니다.")

    # 소유권 확인 뒤 사용자 row를 잠가 같은 사용자의 여러 선택 요청을 직렬화한다.
    # 이후 식물 row까지 잠그므로 제한 확인과 변경이 한 트랜잭션에서 확정된다.
    await lock_user(db, user.id)
    plant = (
        await db.execute(
            sa.select(Plant)
            .where(Plant.id == plant_id, Plant.user_id == user.id)
            .with_for_update()
        )
    ).scalar_one_or_none()
    if plant is None:
        raise AppError(404, "PLANT_NOT_FOUND", "식물을 찾을 수 없습니다.")
    if plant.status != PlantStatus.HARVESTED:
        raise AppError(409, "PLANT_NOT_HARVESTED", "수확한 식물만 박물관에 전시할 수 있어요.")

    if body.is_featured and not plant.museum_featured:
        featured_count = int(
            await db.scalar(
                sa.select(sa.func.count(Plant.id)).where(
                    Plant.user_id == user.id,
                    Plant.status == PlantStatus.HARVESTED,
                    Plant.museum_featured.is_(True),
                )
            )
            or 0
        )
        if featured_count >= plant_service.MUSEUM_MAX_FEATURED:
            raise AppError(
                409,
                "MUSEUM_FEATURED_LIMIT",
                "전시 식물은 최대 10개까지 고를 수 있어요.",
                {"max_featured": plant_service.MUSEUM_MAX_FEATURED},
            )

    plant.museum_featured = body.is_featured
    await db.flush()
    featured_count = int(
        await db.scalar(
            sa.select(sa.func.count(Plant.id)).where(
                Plant.user_id == user.id,
                Plant.status == PlantStatus.HARVESTED,
                Plant.museum_featured.is_(True),
            )
        )
        or 0
    )
    species = await db.get(PlantSpecies, plant.species_id)
    payload = _museum_payload(plant, species)
    await db.commit()
    return {
        "plant": payload,
        "featured_count": featured_count,
        "max_featured": plant_service.MUSEUM_MAX_FEATURED,
    }


@router.post("/plants", status_code=201)
async def plant_new(
    body: PlantCreateRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    # 활성 식물이 없는 간격에서의 동시 insert도 사용자 row로 직렬화한다.
    await lock_user(db, user.id)
    existing = await lock_active_plant(db, user.id)
    if existing is not None:
        raise AppError(409, "PLANT_ACTIVE_EXISTS", "이미 키우고 있는 식물이 있어요.")

    if body.species_id is not None:
        species = await db.get(PlantSpecies, body.species_id)
        if species is None:
            raise AppError(404, "SPECIES_NOT_FOUND", "품종을 찾을 수 없습니다.")
        if species.unlock_price > 0:
            unlocked = await db.scalar(
                sa.select(UserSpeciesUnlock.id).where(
                    UserSpeciesUnlock.user_id == user.id,
                    UserSpeciesUnlock.species_id == species.id,
                )
            )
            if unlocked is None:
                raise AppError(422, "SPECIES_LOCKED", "아직 해금되지 않은 품종입니다.")
    else:
        species = await db.scalar(
            sa.select(PlantSpecies).where(PlantSpecies.unlock_price == 0).order_by(PlantSpecies.id)
        )
        if species is None:
            raise AppError(404, "SPECIES_NOT_FOUND", "기본 품종이 없습니다.")

    plant = Plant(
        user_id=user.id,
        species_id=species.id,
        name=(body.name or species.name),
        status=PlantStatus.ACTIVE,
        planted_at=utcnow(),
        emotion_profile=plant_service.empty_emotion_profile(),
    )
    db.add(plant)
    await db.commit()
    await db.refresh(plant)
    payload = plant_service.plant_payload(plant, species)
    payload["planted_at"] = to_utc_iso(payload["planted_at"])
    return payload


@router.post("/plants/{plant_id}/harvest")
async def harvest(
    plant_id: int,
    request: Request,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    key = idempotency.require_key(request)

    async def handler():
        # 기록 생성/수정/삭제와 같은 user → plant 잠금 순서를 사용한다.
        await lock_user(db, user.id)
        result = await db.execute(
            sa.select(Plant).where(Plant.id == plant_id).with_for_update()
        )
        plant = result.scalar_one_or_none()
        if plant is None:
            raise AppError(404, "PLANT_NOT_FOUND", "식물을 찾을 수 없습니다.")
        if plant.user_id != user.id:
            raise AppError(403, "FORBIDDEN", "접근 권한이 없습니다.")
        observed_at = utcnow()
        # MySQL REPEATABLE READ에서도 lifecycle FOR UPDATE를 current read로 실행해
        # idempotency 사전 조회가 만든 오래된 snapshot에 기대지 않는다.
        await plant_service.refresh_active_plant_growth(
            db,
            user.id,
            plant=plant,
            observed_at=observed_at,
            lock_entries=True,
        )
        profile = plant.emotion_profile or plant_service.empty_emotion_profile()
        pending_count = int(profile.get("pending_count", 0))
        if plant.exp >= plant_service.HARVEST_EXP and pending_count:
            raise AppError(
                409,
                "PLANT_ANALYSIS_PENDING",
                "아직 읽고 있는 일기가 있어요. 분석이 끝나면 수확할 수 있어요.",
                {"pending_count": pending_count},
            )
        if (
            plant.exp >= plant_service.HARVEST_EXP
            and int(profile.get("total", 0)) < plant_service.BRANCH_MIN_SAMPLES
            and int(profile.get("unavailable_count", 0)) == 0
        ):
            raise AppError(
                409,
                "PLANT_EMOTION_EVIDENCE_REQUIRED",
                "이 식물과 함께 쓴 일기 분석이 조금 더 필요해요.",
                {
                    "analyzed_count": int(profile.get("total", 0)),
                    "required_count": plant_service.BRANCH_MIN_SAMPLES,
                },
            )
        if not plant_service.is_harvestable(plant):
            raise AppError(409, "PLANT_NOT_HARVESTABLE", "아직 수확할 수 없어요.")

        plant.status = PlantStatus.HARVESTED
        plant.harvested_at = observed_at
        (
            plant.final_form,
            plant.emotion_profile,
            final_branch,
        ) = await plant_service.snapshot_final_form(
            db, plant, plant.harvested_at, profile=profile
        )
        if final_branch != plant.growth_branch:
            plant.growth_branch = final_branch
            plant.branch_decided_at = plant.harvested_at
        species = await db.get(PlantSpecies, plant.species_id)
        payload = _museum_payload(plant, species)
        payload["status"] = plant.status
        return 200, {
            "plant": payload,
            "active_plant": None,
        }

    return await idempotency.run_idempotent(
        db, user.id, "plant_harvest", key, {"plant_id": plant_id}, handler
    )
