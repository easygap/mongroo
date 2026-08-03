import asyncio
import math
import uuid
from datetime import timedelta

import sqlalchemy as sa

from app.core.timeutil import local_date_of, utcnow
from app.models.enums import AnalysisStatus, PlantStatus
from app.models.game import Item, Quest, UserItem, UserQuest, UserSpeciesUnlock
from app.models.mood import MoodEntry
from app.models.plant import Plant, PlantSpecies
from app.models.reward import RewardEvent
from app.models.user import User
from app.workers.ai_worker import run_pending_once
from tests.conftest import auth_headers, signup


async def _set_seed_balance(session_factory, user_id: int, balance: int) -> None:
    async with session_factory() as db:
        await db.execute(
            sa.update(User).where(User.id == user_id).values(seed_balance=balance)
        )
        await db.commit()


async def _create_acquisition_item(
    session_factory,
    code: str,
    acquisition: dict,
    *,
    price_seeds: int = 0,
) -> int:
    async with session_factory() as db:
        item = Item(
            code=code,
            type="room_theme",
            name=f"{code} 테스트 테마",
            description="획득 조건 통합 테스트 아이템",
            price_seeds=price_seeds,
            rarity=3,
            asset_manifest={
                "asset_key": f"rooms/{code}",
                "acquisition": acquisition,
            },
            is_active=True,
        )
        db.add(item)
        await db.commit()
        await db.refresh(item)
        return item.id


async def _grant_wardrobe(
    session_factory,
    user_id: int,
    code: str,
    compatible_species: list[str],
) -> int:
    async with session_factory() as db:
        item = Item(
            code=code,
            type="wardrobe",
            name=f"{code} 테스트 의상",
            description="품종 호환성 통합 테스트 의상",
            price_seeds=0,
            rarity=1,
            asset_manifest={
                "asset_key": f"wardrobe/{code}",
                "wardrobe_layer_key": code,
                "compatible_species": compatible_species,
            },
            is_active=True,
        )
        db.add(item)
        await db.flush()
        user_item = UserItem(user_id=user_id, item_id=item.id)
        db.add(user_item)
        await db.commit()
        await db.refresh(user_item)
        return user_item.id


async def test_daily_quest_complete_rewards_once(client):
    tokens = await signup(client)
    headers = auth_headers(tokens)

    assigned = await client.get("/quests/today", headers=headers)
    assert assigned.status_code == 200
    assert assigned.json()["suspended"] is False
    assert len(assigned.json()["items"]) == 1
    user_quest_id = assigned.json()["items"][0]["id"]

    completed = await client.post(
        f"/user-quests/{user_quest_id}/complete",
        headers=auth_headers(tokens, idem=True),
    )
    assert completed.status_code == 200
    assert completed.json()["user_quest"]["status"] == "completed"
    reward = completed.json()["reward"]
    assert reward["events"] == [
        {"event_type": "quest_completed", "exp_delta": 20, "seed_delta": 5}
    ]
    assert reward["daily_exp_cap"] == 50
    assert reward["seed_balance"] == 5

    duplicate = await client.post(
        f"/user-quests/{user_quest_id}/complete",
        headers=auth_headers(tokens, idem=True),
    )
    assert duplicate.status_code == 409
    assert duplicate.json()["code"] == "QUEST_ALREADY_RESOLVED"

    again = await client.get("/quests/today", headers=headers)
    assert again.json()["items"][0]["status"] == "completed"


async def test_daily_quest_journey_tracks_loop_and_next_unlock(client, session_factory):
    record_item_id = await _create_acquisition_item(
        session_factory,
        "room_test_journey_record",
        {
            "type": "record_count",
            "target": 2,
            "label": "마음을 기록한 날 누적 2일",
        },
    )
    quest_item_id = await _create_acquisition_item(
        session_factory,
        "room_test_journey_quest",
        {
            "type": "quest_count",
            "target": 1,
            "label": "일일 퀘스트 1회 완료",
        },
    )
    tokens = await signup(client)
    headers = auth_headers(tokens)

    recorded = await client.post(
        "/moods",
        json={"mood_level": 3},
        headers=auth_headers(tokens, idem=True),
    )
    assert recorded.status_code == 201

    assigned = await client.get("/quests/today", headers=headers)
    assert assigned.status_code == 200
    journey = assigned.json()["journey"]
    assert set(journey) == {
        "recorded_day_count",
        "completed_quest_count",
        "weekly_recorded_days",
        "weekly_completed_quests",
        "next_unlock",
    }
    assert journey | {"next_unlock": None} == {
        "recorded_day_count": 1,
        "completed_quest_count": 0,
        "weekly_recorded_days": 1,
        "weekly_completed_quests": 0,
        "next_unlock": None,
    }
    assert journey["next_unlock"] == {
        "item_id": record_item_id,
        "code": "room_test_journey_record",
        "name": "room_test_journey_record 테스트 테마",
        "item_type": "room_theme",
        "acquisition_type": "record_count",
        "label": "마음을 기록한 날 누적 2일",
        "current": 1,
        "target": 2,
        "eligible": False,
    }

    user_quest_id = assigned.json()["items"][0]["id"]
    completed = await client.post(
        f"/user-quests/{user_quest_id}/complete",
        headers=auth_headers(tokens, idem=True),
    )
    assert completed.status_code == 200
    assert completed.json()["journey"] == {
        "recorded_day_count": 1,
        "completed_quest_count": 1,
        "weekly_recorded_days": 1,
        "weekly_completed_quests": 1,
        "next_unlock": {
            "item_id": quest_item_id,
            "code": "room_test_journey_quest",
            "name": "room_test_journey_quest 테스트 테마",
            "item_type": "room_theme",
            "acquisition_type": "quest_count",
            "label": "일일 퀘스트 1회 완료",
            "current": 1,
            "target": 1,
            "eligible": True,
        },
    }


async def test_journey_prefers_the_fewest_remaining_actions_over_ratio(
    client, session_factory
):
    await _create_acquisition_item(
        session_factory,
        "room_test_first_record",
        {
            "type": "record_count",
            "target": 1,
            "label": "첫 마음 기록을 남기면 받아요",
        },
    )
    await _create_acquisition_item(
        session_factory,
        "room_test_collection_ratio",
        {
            "type": "collection_count",
            "target": 5,
            "label": "아이템 5종 수집",
        },
    )
    tokens = await signup(client)

    assigned = await client.get("/quests/today", headers=auth_headers(tokens))

    assert assigned.status_code == 200
    assert assigned.json()["journey"]["next_unlock"]["code"] == (
        "room_test_first_record"
    )


async def test_journey_defers_unmet_owned_item_dependency_until_it_is_eligible(
    client, session_factory
):
    dependency_goal_id = await _create_acquisition_item(
        session_factory,
        "room_test_companion_dependency",
        {
            "type": "own_item",
            "item_code": "companion_dewdrop",
            "label": "이슬이를 먼저 만나면 받아요",
        },
    )
    direct_goal_id = await _create_acquisition_item(
        session_factory,
        "room_test_direct_record_goal",
        {
            "type": "record_count",
            "target": 7,
            "label": "마음을 기록한 날 누적 7일",
        },
    )
    tokens = await signup(client)
    user_id = tokens["user"]["id"]
    headers = auth_headers(tokens)

    assigned = await client.get("/quests/today", headers=headers)
    assert assigned.status_code == 200
    next_unlock = assigned.json()["journey"]["next_unlock"]
    assert {
        key: next_unlock[key]
        for key in (
            "item_id",
            "code",
            "acquisition_type",
            "current",
            "target",
            "eligible",
        )
    } == {
        "item_id": direct_goal_id,
        "code": "room_test_direct_record_goal",
        "acquisition_type": "record_count",
        "current": 0,
        "target": 7,
        "eligible": False,
    }

    async with session_factory() as db:
        dependency = await db.scalar(
            sa.select(Item).where(Item.code == "companion_dewdrop")
        )
        db.add(UserItem(user_id=user_id, item_id=dependency.id))
        await db.commit()

    refreshed = await client.get("/quests/today", headers=headers)
    assert refreshed.status_code == 200
    next_unlock = refreshed.json()["journey"]["next_unlock"]
    assert next_unlock["item_id"] == dependency_goal_id
    assert next_unlock["code"] == "room_test_companion_dependency"
    assert next_unlock["acquisition_type"] == "own_item"
    assert next_unlock["eligible"] is True


async def test_unfinished_quest_follows_latest_diary_emotion_after_analysis(
    client, session_factory
):
    tokens = await signup(client)
    headers = auth_headers(tokens)

    initial = await client.get("/quests/today", headers=headers)
    initial_item = initial.json()["items"][0]
    assert initial.json()["context_status"] == "record_optional"

    async with session_factory() as db:
        user = await db.scalar(sa.select(User))
        db.add(
            Quest(
                code="QST_CONTEXT_MOVEMENT",
                title="손끝 힘 털어내기",
                description="손을 편하게 두고 힘을 한 번 풀어보세요.",
                trigger_rule="diary_context",
                category="movement",
                burden_level=1,
                estimated_minutes=1,
                safety_tags=[],
                reward_exp=20,
                reward_seeds=5,
                is_active=True,
            )
        )
        db.add(
            MoodEntry(
                user_id=user.id,
                local_date=local_date_of(utcnow()),
                recorded_at_utc=utcnow(),
                mood_level=3,
                mood_level_explicit=False,
                emotion_tags=[],
                content="계획이 계속 바뀌어서 화가 났고 마음이 복잡했던 하루였다.",
                analysis_status=AnalysisStatus.SUCCEEDED,
                ai_emotion="분노",
            )
        )
        await db.commit()

    refreshed = await client.get("/quests/today", headers=headers)
    body = refreshed.json()
    assert body["context_status"] == "diary_matched"
    assert body["context_emotion"] == "분노"
    assert body["items"][0]["id"] == initial_item["id"]
    assert body["items"][0]["quest"]["category"] == "movement"


async def test_daily_quest_uses_catalog_reward_values(client, session_factory):
    tokens = await signup(client)
    async with session_factory() as db:
        await db.execute(sa.update(Quest).values(reward_exp=7, reward_seeds=3))
        await db.commit()

    assigned = await client.get("/quests/today", headers=auth_headers(tokens))
    completed = await client.post(
        f"/user-quests/{assigned.json()['items'][0]['id']}/complete",
        headers=auth_headers(tokens, idem=True),
    )
    assert completed.status_code == 200
    assert completed.json()["reward"]["events"] == [
        {"event_type": "quest_completed", "exp_delta": 7, "seed_delta": 3}
    ]


async def test_expired_daily_quest_cannot_be_skipped(client, session_factory):
    tokens = await signup(client)
    assigned = await client.get("/quests/today", headers=auth_headers(tokens))
    user_quest_id = assigned.json()["items"][0]["id"]
    async with session_factory() as db:
        await db.execute(
            sa.update(UserQuest)
            .where(UserQuest.id == user_quest_id)
            .values(quest_date=local_date_of(utcnow()) - timedelta(days=1))
        )
        await db.commit()

    skipped = await client.post(
        f"/user-quests/{user_quest_id}/skip", headers=auth_headers(tokens)
    )
    assert skipped.status_code == 409
    assert skipped.json()["code"] == "QUEST_EXPIRED"


async def test_p1_daily_exp_cap_is_independent_of_action_order(client):
    tokens = await signup(client)
    assigned = await client.get("/quests/today", headers=auth_headers(tokens))
    user_quest_id = assigned.json()["items"][0]["id"]
    completed = await client.post(
        f"/user-quests/{user_quest_id}/complete",
        headers=auth_headers(tokens, idem=True),
    )
    assert completed.status_code == 200

    diary = "오늘의 마음과 주변을 천천히 살피며 솔직하게 기록한 쉰 자 이상의 일기입니다. 감정을 좋고 나쁨으로 나누지 않았습니다."
    mood = await client.post(
        "/moods",
        json={"mood_level": 2, "content": diary},
        headers=auth_headers(tokens, idem=True),
    )
    assert mood.status_code == 201
    reward = mood.json()["reward"]
    assert reward["daily_exp_cap"] == 50
    assert reward["daily_exp_granted"] == 50
    assert {event["event_type"]: event["exp_delta"] for event in reward["events"]} == {
        "mood_first_daily": 10,
        "diary_first_daily": 20,
    }


async def test_daily_quest_skip_has_no_reward(client):
    tokens = await signup(client)
    assigned = await client.get("/quests/today", headers=auth_headers(tokens))
    user_quest_id = assigned.json()["items"][0]["id"]
    skipped = await client.post(
        f"/user-quests/{user_quest_id}/skip", headers=auth_headers(tokens)
    )
    assert skipped.status_code == 200
    assert skipped.json()["user_quest"]["status"] == "skipped"
    me = await client.get("/users/me", headers=auth_headers(tokens))
    assert me.json()["seed_balance"] == 0


async def test_safety_event_suspends_today_quest(client):
    tokens = await signup(client)
    mood = await client.post(
        "/moods",
        json={"mood_level": 1, "content": "요즘 계속 죽고 싶다는 생각이 든다"},
        headers=auth_headers(tokens, idem=True),
    )
    assert mood.status_code == 201
    today = await client.get("/quests/today", headers=auth_headers(tokens))
    assert today.status_code == 200
    assert today.json()["suspended"] is True
    assert today.json()["suspension_reason"] == "safety_support_active"
    assert today.json()["items"] == []


async def test_item_purchase_collection_and_optimistic_farm_layout(
    client, session_factory
):
    tokens = await signup(client)
    user_id = tokens["user"]["id"]
    await _set_seed_balance(session_factory, user_id, 100)

    shop = await client.get("/shop/items", headers=auth_headers(tokens))
    item = next(i for i in shop.json()["items"] if i["type"] == "deco")
    key = uuid.uuid4().hex
    purchase_headers = {**auth_headers(tokens), "Idempotency-Key": key}
    purchase = await client.post(
        f"/shop/items/{item['id']}/purchase", headers=purchase_headers
    )
    assert purchase.status_code == 200
    assert purchase.json()["seed_balance"] == 75
    user_item_id = purchase.json()["user_item"]["id"]

    retry = await client.post(
        f"/shop/items/{item['id']}/purchase", headers=purchase_headers
    )
    assert retry.status_code == 200
    assert retry.json() == purchase.json()

    collection = await client.get("/collection", headers=auth_headers(tokens))
    owned_items = collection.json()["items"]
    assert {i["item"]["code"] for i in owned_items} == {
        "character_baby_pot",
        "deco_cushion_leaf",
    }
    assert any(i["id"] == user_item_id for i in owned_items)

    layout_body = {
        "expected_version": 0,
        "decorations": [
            {
                "user_item_id": user_item_id,
                "x": 0.3,
                "y": 0.6,
                "rotation": math.pi,
                "z_index": 2,
            }
        ],
    }
    saved = await client.put(
        "/farm/layout", json=layout_body, headers=auth_headers(tokens)
    )
    assert saved.status_code == 200
    assert saved.json()["layout"]["version"] == 1
    assert math.isclose(saved.json()["layout"]["decorations"][0]["rotation"], math.pi)

    invalid_rotation = {
        **layout_body,
        "expected_version": 1,
        "decorations": [{**layout_body["decorations"][0], "rotation": math.pi + 0.01}],
    }
    invalid = await client.put(
        "/farm/layout", json=invalid_rotation, headers=auth_headers(tokens)
    )
    assert invalid.status_code == 422

    conflict = await client.put(
        "/farm/layout", json=layout_body, headers=auth_headers(tokens)
    )
    assert conflict.status_code == 409
    assert conflict.json()["code"] == "FARM_LAYOUT_VERSION_CONFLICT"


async def test_wardrobe_species_compatibility_and_replant_auto_unequip(
    client, session_factory
):
    tokens = await signup(client)
    headers = auth_headers(tokens)
    user_id = tokens["user"]["id"]
    incompatible_id = await _grant_wardrobe(
        session_factory,
        user_id,
        "cactus_only",
        ["cactus"],
    )

    rejected = await client.put(
        "/farm/layout",
        json={
            "expected_version": 0,
            "wardrobe_user_item_id": incompatible_id,
        },
        headers=headers,
    )
    assert rejected.status_code == 422
    assert rejected.json()["code"] == "FARM_WARDROBE_SPECIES_INCOMPATIBLE"
    assert rejected.json()["details"] == {
        "species_code": "basic_sprout",
        "wardrobe_user_item_id": incompatible_id,
    }

    farm = await client.get("/farm", headers=headers)
    assert farm.json()["layout"]["version"] == 0
    assert farm.json()["layout"]["wardrobe_user_item_id"] is None

    basic_sprout_wardrobe_id = await _grant_wardrobe(
        session_factory,
        user_id,
        "basic_sprout_only",
        ["basic_sprout"],
    )
    equipped = await client.put(
        "/farm/layout",
        json={
            "expected_version": 0,
            "wardrobe_user_item_id": basic_sprout_wardrobe_id,
        },
        headers=headers,
    )
    assert equipped.status_code == 200
    assert equipped.json()["layout"]["version"] == 1

    async with session_factory() as db:
        active_plant = await db.scalar(
            sa.select(Plant).where(
                Plant.user_id == user_id,
                Plant.status == PlantStatus.ACTIVE,
            )
        )
        active_plant.status = PlantStatus.HARVESTED
        cactus = await db.scalar(
            sa.select(PlantSpecies).where(PlantSpecies.code == "cactus")
        )
        db.add(UserSpeciesUnlock(user_id=user_id, species_id=cactus.id))
        await db.commit()
        cactus_id = cactus.id

    planted = await client.post(
        "/plants",
        json={"species_id": cactus_id},
        headers=headers,
    )
    assert planted.status_code == 201
    assert planted.json()["species"]["code"] == "cactus"

    farm = await client.get("/farm", headers=headers)
    assert farm.json()["layout"]["version"] == 2
    assert farm.json()["layout"]["wardrobe_user_item_id"] is None


async def test_concurrent_same_key_purchase_replays_first_response(
    client, session_factory, monkeypatch
):
    from app.services import game as game_service

    tokens = await signup(client)
    user_id = tokens["user"]["id"]
    await _set_seed_balance(session_factory, user_id, 100)
    shop = await client.get("/shop/items", headers=auth_headers(tokens))
    item = next(i for i in shop.json()["items"] if i["type"] == "deco")

    original_purchase = game_service.purchase_item
    handler_started = asyncio.Event()
    release_handler = asyncio.Event()
    handler_calls = 0

    async def delayed_purchase(db, requested_user_id, requested_item_id):
        nonlocal handler_calls
        handler_calls += 1
        if handler_calls == 1:
            handler_started.set()
            await release_handler.wait()
        return await original_purchase(db, requested_user_id, requested_item_id)

    monkeypatch.setattr(game_service, "purchase_item", delayed_purchase)
    headers = {
        **auth_headers(tokens),
        "Idempotency-Key": uuid.uuid4().hex,
    }
    path = f"/shop/items/{item['id']}/purchase"

    first_task = asyncio.create_task(client.post(path, headers=headers))
    await handler_started.wait()
    second_task = asyncio.create_task(client.post(path, headers=headers))
    await asyncio.sleep(0.05)
    assert not second_task.done()
    assert handler_calls == 1

    release_handler.set()
    first, second = await asyncio.gather(first_task, second_task)
    assert first.status_code == second.status_code == 200
    assert first.json() == second.json()
    assert handler_calls == 1

    async with session_factory() as db:
        owned_count = await db.scalar(
            sa.select(sa.func.count())
            .select_from(UserItem)
            .where(
                UserItem.user_id == user_id,
                UserItem.item_id == item["id"],
            )
        )
        purchase_count = await db.scalar(
            sa.select(sa.func.count())
            .select_from(RewardEvent)
            .where(
                RewardEvent.user_id == user_id,
                RewardEvent.source_type == "item",
                RewardEvent.source_id == item["id"],
            )
        )
        balance = await db.scalar(
            sa.select(User.seed_balance).where(User.id == user_id)
        )
    assert owned_count == 1
    assert purchase_count == 1
    assert balance == 75


async def test_signup_grants_starter_and_collection_exposes_locked_catalog(client):
    tokens = await signup(client)
    headers = auth_headers(tokens)

    shop = await client.get("/shop/items", headers=headers)
    baby = next(i for i in shop.json()["items"] if i["code"] == "character_baby_pot")
    assert baby["owned"] is True
    assert baby["price_seeds"] == 0
    assert baby["asset_manifest"]["motion_key"] == "baby_bounce"

    collection = await client.get("/collection", headers=headers)
    assert collection.status_code == 200
    body = collection.json()
    assert [i["item"]["code"] for i in body["items"]] == ["character_baby_pot"]
    assert len(body["catalog_items"]) == 4

    catalog = {i["code"]: i for i in body["catalog_items"]}
    assert catalog["character_baby_pot"]["owned"] is True
    assert catalog["character_baby_pot"]["locked"] is False
    assert catalog["character_baby_pot"]["user_item_id"] == body["items"][0]["id"]
    assert catalog["character_baby_pot"]["acquired_at"] is not None
    assert catalog["deco_cushion_leaf"]["owned"] is False
    assert catalog["deco_cushion_leaf"]["locked"] is True
    assert catalog["deco_cushion_leaf"]["user_item_id"] is None
    assert catalog["deco_cushion_leaf"]["acquired_at"] is None

    farm = await client.get("/farm", headers=headers)
    starter_user_item_id = body["items"][0]["id"]
    assert farm.json()["layout"]["version"] == 0
    assert farm.json()["layout"]["main_character_user_item_id"] == starter_user_item_id


async def test_species_item_unlock_allows_planting(client, session_factory):
    tokens = await signup(client)
    user_id = tokens["user"]["id"]
    await _set_seed_balance(session_factory, user_id, 150)

    shop = await client.get("/shop/items", headers=auth_headers(tokens))
    item = next(i for i in shop.json()["items"] if i["type"] == "species_unlock")
    bought = await client.post(
        f"/shop/items/{item['id']}/purchase", headers=auth_headers(tokens, idem=True)
    )
    assert bought.status_code == 200

    species = await client.get("/plant-species", headers=auth_headers(tokens))
    cactus = next(s for s in species.json()["items"] if s["code"] == "cactus")
    assert cactus["is_unlocked"] is True

    for index in range(3):
        await client.post(
            "/moods",
            json={"content": f"새 화분을 기다리며 즐겁고 행복한 마음을 적었다 {index}"},
            headers=auth_headers(tokens, idem=True),
        )
    await run_pending_once(session_factory)

    async with session_factory() as db:
        await db.execute(
            sa.update(Plant)
            .where(Plant.user_id == user_id, Plant.status == "active")
            .values(exp=1000)
        )
        await db.commit()
    active = (await client.get("/plants/me", headers=auth_headers(tokens))).json()[
        "plant"
    ]
    await client.post(
        f"/plants/{active['id']}/harvest", headers=auth_headers(tokens, idem=True)
    )
    planted = await client.post(
        "/plants", json={"species_id": cactus["id"]}, headers=auth_headers(tokens)
    )
    assert planted.status_code == 201
    assert planted.json()["species"]["code"] == "cactus"


async def test_direct_species_purchase_is_owned_consistently_in_collection(
    client, session_factory
):
    tokens = await signup(client)
    await _set_seed_balance(session_factory, tokens["user"]["id"], 150)
    species_shop = await client.get("/shop/plant-species", headers=auth_headers(tokens))
    cactus = next(i for i in species_shop.json()["items"] if i["code"] == "cactus")
    purchased = await client.post(
        f"/shop/plant-species/{cactus['id']}/purchase",
        headers=auth_headers(tokens, idem=True),
    )
    assert purchased.status_code == 200

    collection = await client.get("/collection", headers=auth_headers(tokens))
    catalog_item = next(
        i for i in collection.json()["catalog_items"] if i["code"] == "species_cactus"
    )
    assert catalog_item["owned"] is True
    assert catalog_item["locked"] is False
    assert catalog_item["user_item_id"] is None


async def test_shop_acquisition_purchase_fallback_reports_affordability(
    client, session_factory
):
    tokens = await signup(client)
    headers = auth_headers(tokens)

    shop = await client.get("/shop/items", headers=headers)
    deco = next(
        item for item in shop.json()["items"] if item["code"] == "deco_cushion_leaf"
    )
    assert deco["acquisition"] == {
        "type": "purchase",
        "label": "씨앗 25개로 구매",
        "current": 0,
        "target": 25,
        "eligible": False,
    }

    await _set_seed_balance(session_factory, tokens["user"]["id"], 25)
    affordable = await client.get("/shop/items", headers=headers)
    deco = next(
        item
        for item in affordable.json()["items"]
        if item["code"] == "deco_cushion_leaf"
    )
    assert set(deco["acquisition"]) == {
        "type",
        "label",
        "current",
        "target",
        "eligible",
    }
    assert deco["acquisition"]["current"] == 25
    assert deco["acquisition"]["eligible"] is True


async def test_condition_claim_checks_progress_and_replays_same_key(
    client, session_factory
):
    room_id = await _create_acquisition_item(
        session_factory,
        "room_test_quest_claim",
        {
            "type": "quest_count",
            "target": 2,
            "label": "일일 퀘스트 2회 완료",
        },
    )
    tokens = await signup(client)
    user_id = tokens["user"]["id"]
    today = local_date_of(utcnow())

    async with session_factory() as db:
        quest_ids = list(
            (await db.execute(sa.select(Quest.id).order_by(Quest.id))).scalars()
        )
        db.add(
            UserQuest(
                user_id=user_id,
                quest_id=quest_ids[0],
                quest_date=today - timedelta(days=1),
                status="completed",
                completed_at=utcnow(),
            )
        )
        # assigned/skipped 행은 완료 총수에 포함되지 않는다.
        db.add(
            UserQuest(
                user_id=user_id,
                quest_id=quest_ids[1],
                quest_date=today - timedelta(days=2),
                status="skipped",
            )
        )
        await db.commit()

    claim_key = uuid.uuid4().hex
    claim_headers = {**auth_headers(tokens), "Idempotency-Key": claim_key}
    unmet = await client.post(f"/shop/items/{room_id}/claim", headers=claim_headers)
    assert unmet.status_code == 409
    assert unmet.json()["code"] == "ITEM_ACQUISITION_NOT_MET"
    assert unmet.json()["details"]["acquisition"] == {
        "type": "quest_count",
        "label": "일일 퀘스트 2회 완료",
        "current": 1,
        "target": 2,
        "eligible": False,
    }

    missing_key = await client.post(
        f"/shop/items/{room_id}/claim", headers=auth_headers(tokens)
    )
    assert missing_key.status_code == 400
    assert missing_key.json()["code"] == "IDEMPOTENCY_KEY_REQUIRED"

    async with session_factory() as db:
        db.add(
            UserQuest(
                user_id=user_id,
                quest_id=quest_ids[1],
                quest_date=today - timedelta(days=3),
                status="completed",
                completed_at=utcnow(),
            )
        )
        await db.commit()

    # 실패한 claim은 멱등 키를 저장하지 않아 조건 달성 후 같은 키를 재사용할 수 있다.
    claimed = await client.post(f"/shop/items/{room_id}/claim", headers=claim_headers)
    assert claimed.status_code == 200
    assert claimed.json()["user_item"]["item"]["code"] == "room_test_quest_claim"
    assert claimed.json()["seed_balance"] == 0
    assert claimed.json()["acquisition"] == {
        "type": "quest_count",
        "label": "일일 퀘스트 2회 완료",
        "current": 2,
        "target": 2,
        "eligible": False,
    }

    replay = await client.post(f"/shop/items/{room_id}/claim", headers=claim_headers)
    assert replay.status_code == 200
    assert replay.json() == claimed.json()

    other_room_id = await _create_acquisition_item(
        session_factory,
        "room_test_same_key_conflict",
        {
            "type": "own_item",
            "item_code": "character_baby_pot",
            "label": "아기 화분을 만나면 해금",
        },
    )
    key_conflict = await client.post(
        f"/shop/items/{other_room_id}/claim", headers=claim_headers
    )
    assert key_conflict.status_code == 409
    assert key_conflict.json()["code"] == "IDEMPOTENCY_KEY_CONFLICT"

    collection = await client.get("/collection", headers=auth_headers(tokens))
    catalog_room = next(
        item
        for item in collection.json()["catalog_items"]
        if item["code"] == "room_test_quest_claim"
    )
    assert catalog_room["acquisition"] == claimed.json()["acquisition"]

    async with session_factory() as db:
        owned_count = await db.scalar(
            sa.select(sa.func.count())
            .select_from(UserItem)
            .where(UserItem.user_id == user_id, UserItem.item_id == room_id)
        )
        item_events = await db.scalar(
            sa.select(sa.func.count())
            .select_from(RewardEvent)
            .where(
                RewardEvent.user_id == user_id,
                RewardEvent.source_type == "item",
                RewardEvent.source_id == room_id,
            )
        )
    assert owned_count == 1
    assert item_events == 0


async def test_harvest_form_claim_requires_matching_final_form(client, session_factory):
    sunny_id = await _create_acquisition_item(
        session_factory,
        "deco_test_resonance_sunny",
        {
            "type": "harvest_form",
            "form": "sunny",
            "target": 1,
            "label": "햇살결 식물을 1회 수확하면 받기",
        },
    )
    rainy_id = await _create_acquisition_item(
        session_factory,
        "deco_test_resonance_rainy",
        {
            "type": "harvest_form",
            "form": "rainy",
            "target": 1,
            "label": "빗방울결 식물을 1회 수확하면 받기",
        },
    )
    tokens = await signup(client)
    user_id = tokens["user"]["id"]
    headers = auth_headers(tokens)

    initial = await client.get("/shop/items", headers=headers)
    initial_by_code = {item["code"]: item for item in initial.json()["items"]}
    assert initial_by_code["deco_test_resonance_sunny"]["acquisition"] == {
        "type": "harvest_form",
        "label": "햇살결 식물을 1회 수확하면 받기",
        "current": 0,
        "target": 1,
        "eligible": False,
    }

    async with session_factory() as db:
        active = await db.scalar(
            sa.select(Plant).where(
                Plant.user_id == user_id,
                Plant.status == "active",
            )
        )
        observed_at = utcnow()
        db.add(
            Plant(
                user_id=user_id,
                species_id=active.species_id,
                name="첫 햇살결",
                exp=1000,
                status="harvested",
                planted_at=observed_at - timedelta(days=3),
                harvested_at=observed_at,
                final_form="sunny",
                emotion_profile={"version": 2, "total": 3},
                growth_branch="joy",
                branch_decided_at=observed_at,
            )
        )
        await db.commit()

    progressed = await client.get("/shop/items", headers=headers)
    by_code = {item["code"]: item for item in progressed.json()["items"]}
    sunny = by_code["deco_test_resonance_sunny"]["acquisition"]
    rainy = by_code["deco_test_resonance_rainy"]["acquisition"]
    assert sunny == {
        "type": "harvest_form",
        "label": "햇살결 식물을 1회 수확하면 받기",
        "current": 1,
        "target": 1,
        "eligible": True,
    }
    assert rainy["current"] == 0
    assert rainy["eligible"] is False

    claimed = await client.post(
        f"/shop/items/{sunny_id}/claim",
        headers=auth_headers(tokens, idem=True),
    )
    assert claimed.status_code == 200
    assert claimed.json()["user_item"]["item"]["code"] == ("deco_test_resonance_sunny")
    assert claimed.json()["seed_balance"] == 0
    assert claimed.json()["acquisition"] == {**sunny, "eligible": False}

    unmatched = await client.post(
        f"/shop/items/{rainy_id}/claim",
        headers=auth_headers(tokens, idem=True),
    )
    assert unmatched.status_code == 409
    assert unmatched.json()["code"] == "ITEM_ACQUISITION_NOT_MET"

    collection = await client.get("/collection", headers=headers)
    catalog = {item["code"]: item for item in collection.json()["catalog_items"]}
    assert catalog["deco_test_resonance_sunny"]["owned"] is True
    assert catalog["deco_test_resonance_sunny"]["locked"] is False
    assert catalog["deco_test_resonance_rainy"]["locked"] is True


async def test_purchase_and_claim_routes_are_type_exclusive(client, session_factory):
    condition_id = await _create_acquisition_item(
        session_factory,
        "room_test_streak_locked",
        {"type": "streak", "target": 2, "label": "마음 기록 2일 연속 달성"},
    )
    tokens = await signup(client)
    user_id = tokens["user"]["id"]
    await _set_seed_balance(session_factory, user_id, 100)

    purchase_unlock = await client.post(
        f"/shop/items/{condition_id}/purchase",
        headers=auth_headers(tokens, idem=True),
    )
    assert purchase_unlock.status_code == 409
    assert purchase_unlock.json()["code"] == "ITEM_NOT_PURCHASABLE"

    shop = await client.get("/shop/items", headers=auth_headers(tokens))
    purchase_item = next(
        item for item in shop.json()["items"] if item["code"] == "deco_cushion_leaf"
    )
    claim_purchase = await client.post(
        f"/shop/items/{purchase_item['id']}/claim",
        headers=auth_headers(tokens, idem=True),
    )
    assert claim_purchase.status_code == 409
    assert claim_purchase.json()["code"] == "ITEM_NOT_CLAIMABLE"

    async with session_factory() as db:
        balance = await db.scalar(
            sa.select(User.seed_balance).where(User.id == user_id)
        )
        owned = await db.scalar(
            sa.select(sa.func.count())
            .select_from(UserItem)
            .where(UserItem.user_id == user_id, UserItem.item_id == condition_id)
        )
        purchase_events = await db.scalar(
            sa.select(sa.func.count())
            .select_from(RewardEvent)
            .where(
                RewardEvent.user_id == user_id,
                RewardEvent.source_type == "item",
                RewardEvent.source_id == condition_id,
            )
        )
    assert balance == 100
    assert owned == 0
    assert purchase_events == 0


async def test_cumulative_record_days_unlock_without_streak_pressure(
    client, session_factory
):
    room_id = await _create_acquisition_item(
        session_factory,
        "room_test_record_days",
        {
            "type": "record_count",
            "target": 2,
            "label": "마음을 기록한 날 누적 2일",
        },
    )
    tokens = await signup(client)
    user_id = tokens["user"]["id"]
    today = local_date_of(utcnow())

    async with session_factory() as db:
        for day_offset in (0, 3):
            db.add(
                MoodEntry(
                    user_id=user_id,
                    local_date=today - timedelta(days=day_offset),
                    recorded_at_utc=utcnow() - timedelta(days=day_offset),
                    mood_level=3,
                    mood_level_explicit=False,
                    emotion_tags=[],
                    content="연속이 아니어도 쌓이는 기록",
                    analysis_status=AnalysisStatus.NOT_REQUESTED,
                )
            )
        await db.commit()

    shop = await client.get("/shop/items", headers=auth_headers(tokens))
    room = next(
        item for item in shop.json()["items"] if item["code"] == "room_test_record_days"
    )
    assert room["acquisition"]["current"] == 2
    assert room["acquisition"]["eligible"] is True

    claimed = await client.post(
        f"/shop/items/{room_id}/claim",
        headers=auth_headers(tokens, idem=True),
    )
    assert claimed.status_code == 200


async def test_acquisition_uses_logical_collection_streak_and_owned_item(
    client, session_factory
):
    await _create_acquisition_item(
        session_factory,
        "room_test_streak",
        {"type": "streak", "target": 4, "label": "마음 기록 4일 연속 달성"},
    )
    await _create_acquisition_item(
        session_factory,
        "room_test_own_species",
        {
            "type": "own_item",
            "item_code": "species_cactus",
            "label": "가시니 씨앗 보유",
        },
    )
    await _create_acquisition_item(
        session_factory,
        "room_test_collection",
        {"type": "collection_count", "target": 3, "label": "아이템 3종 수집"},
    )
    tokens = await signup(client)
    user_id = tokens["user"]["id"]

    async with session_factory() as db:
        await db.execute(
            sa.update(User)
            .where(User.id == user_id)
            .values(seed_balance=150, streak_days=3)
        )
        await db.commit()

    species_shop = await client.get("/shop/plant-species", headers=auth_headers(tokens))
    cactus = next(
        item for item in species_shop.json()["items"] if item["code"] == "cactus"
    )
    bought_species = await client.post(
        f"/shop/plant-species/{cactus['id']}/purchase",
        headers=auth_headers(tokens, idem=True),
    )
    assert bought_species.status_code == 200

    shop = await client.get("/shop/items", headers=auth_headers(tokens))
    by_code = {item["code"]: item for item in shop.json()["items"]}
    for code in (
        "room_test_streak",
        "room_test_own_species",
        "room_test_collection",
    ):
        assert set(by_code[code]["acquisition"]) == {
            "type",
            "label",
            "current",
            "target",
            "eligible",
        }
    assert by_code["species_cactus"]["owned"] is True
    assert by_code["room_test_own_species"]["acquisition"]["current"] == 1
    assert by_code["room_test_own_species"]["acquisition"]["target"] == 1
    assert by_code["room_test_own_species"]["acquisition"]["eligible"] is True
    # 스타터 캐릭터 + 직접 품종 해금은 논리적 도감 보유 2종이다.
    assert by_code["room_test_collection"]["acquisition"]["current"] == 2
    assert by_code["room_test_collection"]["acquisition"]["eligible"] is False
    assert by_code["room_test_streak"]["acquisition"]["current"] == 3
    assert by_code["room_test_streak"]["acquisition"]["eligible"] is False

    collection = await client.get("/collection", headers=auth_headers(tokens))
    collection_by_code = {
        item["code"]: item for item in collection.json()["catalog_items"]
    }
    for code in (
        "room_test_streak",
        "room_test_own_species",
        "room_test_collection",
    ):
        assert collection_by_code[code]["acquisition"] == by_code[code]["acquisition"]
    assert collection_by_code["species_cactus"]["owned"] is True
    assert collection_by_code["species_cactus"]["locked"] is False

    deco = by_code["deco_cushion_leaf"]
    bought_deco = await client.post(
        f"/shop/items/{deco['id']}/purchase",
        headers=auth_headers(tokens, idem=True),
    )
    assert bought_deco.status_code == 200
    async with session_factory() as db:
        await db.execute(
            sa.update(User).where(User.id == user_id).values(streak_days=4)
        )
        await db.commit()

    progressed = await client.get("/shop/items", headers=auth_headers(tokens))
    by_code = {item["code"]: item for item in progressed.json()["items"]}
    assert by_code["room_test_collection"]["acquisition"]["current"] == 3
    assert by_code["room_test_collection"]["acquisition"]["eligible"] is True
    assert by_code["room_test_streak"]["acquisition"]["current"] == 4
    assert by_code["room_test_streak"]["acquisition"]["eligible"] is True

    progressed_collection = await client.get(
        "/collection", headers=auth_headers(tokens)
    )
    collection_by_code = {
        item["code"]: item for item in progressed_collection.json()["catalog_items"]
    }
    assert (
        collection_by_code["room_test_collection"]["acquisition"]
        == by_code["room_test_collection"]["acquisition"]
    )
    assert (
        collection_by_code["room_test_streak"]["acquisition"]
        == by_code["room_test_streak"]["acquisition"]
    )


async def test_concurrent_distinct_key_claim_creates_one_user_item(
    client, session_factory
):
    room_id = await _create_acquisition_item(
        session_factory,
        "room_test_concurrent_claim",
        {
            "type": "own_item",
            "item_code": "character_baby_pot",
            "label": "아기 화분을 만나면 해금",
        },
    )
    tokens = await signup(client)

    async def claim():
        return await client.post(
            f"/shop/items/{room_id}/claim",
            headers=auth_headers(tokens, idem=True),
        )

    first, second = await asyncio.gather(claim(), claim())
    assert sorted([first.status_code, second.status_code]) == [200, 409]
    rejected = first if first.status_code == 409 else second
    assert rejected.json()["code"] == "ITEM_ALREADY_OWNED"

    async with session_factory() as db:
        owned_count = await db.scalar(
            sa.select(sa.func.count())
            .select_from(UserItem)
            .where(
                UserItem.user_id == tokens["user"]["id"],
                UserItem.item_id == room_id,
            )
        )
    assert owned_count == 1


async def test_claim_locks_user_before_idempotency_row(
    client, session_factory, monkeypatch
):
    from app.api import idempotency
    from app.services import game as game_service

    room_id = await _create_acquisition_item(
        session_factory,
        "room_test_lock_order",
        {
            "type": "own_item",
            "item_code": "character_baby_pot",
            "label": "아기 화분을 만나면 해금",
        },
    )
    tokens = await signup(client)
    events = []
    original_lock = game_service.lock_inventory_user
    original_idempotent = idempotency.run_idempotent

    async def observed_lock(db, user_id):
        events.append("user_lock")
        return await original_lock(db, user_id)

    async def observed_idempotent(*args, **kwargs):
        events.append("idempotency")
        return await original_idempotent(*args, **kwargs)

    monkeypatch.setattr(game_service, "lock_inventory_user", observed_lock)
    monkeypatch.setattr(idempotency, "run_idempotent", observed_idempotent)

    claimed = await client.post(
        f"/shop/items/{room_id}/claim",
        headers=auth_headers(tokens, idem=True),
    )
    assert claimed.status_code == 200
    assert events == ["user_lock", "idempotency"]


async def test_malformed_acquisition_metadata_fails_closed(client, session_factory):
    await _create_acquisition_item(
        session_factory,
        "room_test_invalid_acquisition",
        {"type": "quest_count", "target": True, "label": "잘못된 조건"},
    )
    tokens = await signup(client)
    shop = await client.get("/shop/items", headers=auth_headers(tokens))
    assert shop.status_code == 503
    assert shop.json()["code"] == "SHOP_CATALOG_INVALID"


async def test_unknown_harvest_form_metadata_fails_closed(client, session_factory):
    await _create_acquisition_item(
        session_factory,
        "room_test_unknown_harvest_form",
        {
            "type": "harvest_form",
            "form": "golden_superior",
            "target": 1,
            "label": "알 수 없는 마음결 수확",
        },
    )
    tokens = await signup(client)
    shop = await client.get("/shop/items", headers=auth_headers(tokens))
    assert shop.status_code == 503
    assert shop.json()["code"] == "SHOP_CATALOG_INVALID"


async def test_localhost_cors_preflight(client):
    response = await client.options(
        "/quests/today",
        headers={
            "Origin": "http://localhost:5173",
            "Access-Control-Request-Method": "GET",
            "Access-Control-Request-Headers": "authorization",
        },
    )
    assert response.status_code == 200
    assert response.headers["access-control-allow-origin"] == "http://localhost:5173"
    assert response.headers["access-control-allow-credentials"] == "true"
