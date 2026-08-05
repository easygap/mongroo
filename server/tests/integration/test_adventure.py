from datetime import datetime, timedelta

import sqlalchemy as sa

from app.core.timeutil import local_date_of, utcnow
from app.models.adventure import (
    AdventurePatrol,
    DungeonRun,
    UserAdventureItem,
    UserAdventureResearch,
    UserDungeon,
)
from app.models.enums import RewardEventType
from app.models.game import FarmLayout, Item, UserItem
from app.models.mood import MoodEntry
from app.models.plant import Plant
from app.models.reward import RewardEvent
from app.services import adventure as adventure_service
from tests.conftest import auth_headers, signup


LONG_DIARY = (
    "오늘은 생각보다 마음이 자주 흔들렸다. 그래도 잠깐 멈춰서 어떤 감정인지 "
    "하나씩 적어 보니 지금 필요한 것이 무엇인지 조금은 알 것 같다."
)


async def test_weekly_board_prioritizes_diary_and_claims_each_reward_once(
    client,
    session_factory,
    monkeypatch,
):
    fixed_now = datetime(2026, 8, 7, 3, 0, 0)
    monkeypatch.setattr(adventure_service, "utcnow", lambda: fixed_now)
    today = local_date_of(fixed_now)
    week_start = today - timedelta(days=today.weekday())
    tokens = await signup(client)
    user_id = tokens["user"]["id"]

    async with session_factory() as db:
        plant = await db.scalar(sa.select(Plant).where(Plant.user_id == user_id))
        dungeon = UserDungeon(
            user_id=user_id,
            dungeon_code="moss_archive",
            discovered_at=fixed_now,
            clear_count=2,
        )
        db.add(dungeon)
        await db.flush()
        for offset in range(3):
            local_day = week_start + timedelta(days=offset)
            db.add(
                MoodEntry(
                    user_id=user_id,
                    local_date=local_day,
                    recorded_at_utc=fixed_now,
                    mood_level=3,
                    mood_level_explicit=False,
                    emotion_tags=[],
                    content=LONG_DIARY,
                )
            )
            db.add(
                AdventurePatrol(
                    user_id=user_id,
                    plant_id=plant.id,
                    route_code="greenhouse_edge",
                    local_date=local_day,
                    status="claimed",
                    started_at=fixed_now - timedelta(minutes=10),
                    returns_at=fixed_now,
                    claimed_at=fixed_now,
                    reward_exp=0,
                    reward_seeds=3,
                    discovery_code="moss_archive",
                    found_item_code="pressed_leaf_map",
                    found_quantity=1,
                    performance_score=12,
                )
            )
        for offset in range(2):
            db.add(
                DungeonRun(
                    user_id=user_id,
                    plant_id=plant.id,
                    user_dungeon_id=dungeon.id,
                    local_date=week_start + timedelta(days=offset),
                    created_at=fixed_now,
                    reward_exp=10,
                    reward_seeds=4,
                    found_item_code="moss_key",
                    found_quantity=1,
                    performance_score=12,
                    approach_code="steady",
                    outcome_code="steady",
                )
            )
        await db.commit()

    state = await client.get("/adventure", headers=auth_headers(tokens))
    assert state.status_code == 200
    board = state.json()["weekly_board"]
    assert board["week_start"] == "2026-08-03"
    assert board["week_end"] == "2026-08-09"
    goals = {goal["code"]: goal for goal in board["goals"]}
    assert goals["diary_3"] == {
        "code": "diary_3",
        "name": "마음 일기 3일",
        "description": "서로 다른 3일에 마음을 50자 이상 기록해요.",
        "progress": 3,
        "target": 3,
        "reward_exp": 0,
        "reward_seeds": 20,
        "completed": True,
        "claimed": False,
        "can_claim": True,
    }
    assert goals["patrol_3"]["progress"] == 3
    assert goals["patrol_3"]["reward_seeds"] == 8
    assert goals["dungeon_2"]["progress"] == 2
    assert goals["dungeon_2"]["reward_seeds"] == 6

    diary_headers = {
        **auth_headers(tokens),
        "Idempotency-Key": "weekly-diary-2026-08-03",
    }
    expected_balances = {"diary_3": 20, "patrol_3": 28, "dungeon_2": 34}
    for code, expected_balance in expected_balances.items():
        claim_headers = (
            diary_headers
            if code == "diary_3"
            else {
                **auth_headers(tokens),
                "Idempotency-Key": f"weekly-{code}-2026-08-03",
            }
        )
        claimed = await client.post(
            f"/adventure/weekly-goals/{code}/claim",
            headers=claim_headers,
        )
        assert claimed.status_code == 200, claimed.text
        reward = claimed.json()["reward"]
        assert reward["events"] == [
            {
                "event_type": "adventure_weekly",
                "exp_delta": 0,
                "seed_delta": goals[code]["reward_seeds"],
            }
        ]
        assert reward["seed_balance"] == expected_balance
        assert claimed.json()["goal"]["claimed"] is True

    replay = await client.post(
        "/adventure/weekly-goals/diary_3/claim",
        headers=diary_headers,
    )
    assert replay.status_code == 200
    assert replay.json()["reward"]["seed_balance"] == 20
    duplicate = await client.post(
        "/adventure/weekly-goals/diary_3/claim",
        headers=auth_headers(tokens, idem=True),
    )
    assert duplicate.status_code == 409
    assert duplicate.json()["code"] == "WEEKLY_GOAL_ALREADY_CLAIMED"

    async with session_factory() as db:
        events = list(
            (
                await db.execute(
                    sa.select(RewardEvent).where(
                        RewardEvent.user_id == user_id,
                        RewardEvent.event_type == RewardEventType.ADVENTURE_WEEKLY,
                    )
                )
            ).scalars()
        )
        assert len(events) == 3
        assert sum(event.seed_delta for event in events) == 34
        assert all(event.exp_delta == 0 for event in events)


async def test_donation_preserves_research_materials_and_uses_daily_limit(
    client,
    session_factory,
):
    tokens = await signup(client)
    user_id = tokens["user"]["id"]
    async with session_factory() as db:
        db.add_all(
            [
                UserAdventureItem(
                    user_id=user_id,
                    item_code="pressed_leaf_map",
                    quantity=6,
                ),
                UserAdventureItem(
                    user_id=user_id,
                    item_code="moon_dew",
                    quantity=6,
                ),
            ]
        )
        await db.commit()

    state = await client.get("/adventure", headers=auth_headers(tokens))
    assert state.status_code == 200
    assert state.json()["donation"] == {
        "available_today": True,
        "used_today": False,
        "has_eligible_item": True,
        "required_quantity": 3,
        "reward_exp": 0,
        "reward_seeds": 2,
        "message": "연구에 필요한 수량을 남기고 여분 표본만 기증할 수 있어요.",
    }
    inventory = {item["code"]: item for item in state.json()["inventory"]}
    assert inventory["pressed_leaf_map"]["reserved_quantity"] == 3
    assert inventory["pressed_leaf_map"]["donatable_quantity"] == 3
    assert inventory["pressed_leaf_map"]["can_donate"] is True
    assert inventory["moon_dew"]["reserved_quantity"] == 4
    assert inventory["moon_dew"]["donatable_quantity"] == 2
    assert inventory["moon_dew"]["can_donate"] is False

    protected = await client.post(
        "/adventure/donations",
        json={"item_code": "moon_dew"},
        headers=auth_headers(tokens, idem=True),
    )
    assert protected.status_code == 409
    assert protected.json()["code"] == "ADVENTURE_DONATION_EXCESS_REQUIRED"
    assert protected.json()["details"] == {
        "item_code": "moon_dew",
        "current_quantity": 6,
        "reserved_quantity": 4,
        "donatable_quantity": 2,
        "required_quantity": 3,
    }

    donation_headers = {
        **auth_headers(tokens),
        "Idempotency-Key": "donate-pressed-leaf-map",
    }
    donated = await client.post(
        "/adventure/donations",
        json={"item_code": "pressed_leaf_map"},
        headers=donation_headers,
    )
    assert donated.status_code == 200, donated.text
    assert donated.json()["donation"] == {
        "item_code": "pressed_leaf_map",
        "item_name": "눌러 말린 잎 지도",
        "quantity": 3,
    }
    assert donated.json()["reward"]["events"] == [
        {"event_type": "adventure_donated", "exp_delta": 0, "seed_delta": 2}
    ]
    assert donated.json()["reward"]["seed_balance"] == 2
    assert donated.json()["state"]["donation"]["used_today"] is True
    donated_inventory = {
        item["code"]: item for item in donated.json()["state"]["inventory"]
    }
    assert donated_inventory["pressed_leaf_map"]["quantity"] == 3
    assert donated_inventory["pressed_leaf_map"]["reserved_quantity"] == 3
    assert donated_inventory["pressed_leaf_map"]["donatable_quantity"] == 0
    assert all(not item["can_donate"] for item in donated_inventory.values())

    replay = await client.post(
        "/adventure/donations",
        json={"item_code": "pressed_leaf_map"},
        headers=donation_headers,
    )
    assert replay.status_code == 200
    assert replay.json()["reward"]["seed_balance"] == 2
    duplicate = await client.post(
        "/adventure/donations",
        json={"item_code": "moon_dew"},
        headers=auth_headers(tokens, idem=True),
    )
    assert duplicate.status_code == 409
    assert duplicate.json()["code"] == "ADVENTURE_DONATION_DAILY_LIMIT"

    async with session_factory() as db:
        event = await db.scalar(
            sa.select(RewardEvent).where(
                RewardEvent.user_id == user_id,
                RewardEvent.event_type == RewardEventType.ADVENTURE_DONATED,
            )
        )
        assert event is not None
        assert event.exp_delta == 0
        assert event.seed_delta == 2
        rows = {
            item.item_code: item.quantity
            for item in (
                await db.execute(
                    sa.select(UserAdventureItem).where(
                        UserAdventureItem.user_id == user_id
                    )
                )
            ).scalars()
        }
        assert rows == {"pressed_leaf_map": 3, "moon_dew": 6}


async def test_adventure_requires_diary_then_completes_patrol_and_dungeon(
    client, session_factory
):
    tokens = await signup(client)
    headers = auth_headers(tokens)

    state = await client.get("/adventure", headers=headers)
    assert state.status_code == 200
    assert state.json()["diary_ready"] is False
    assert state.json()["journal"] == {
        "discovered_count": 0,
        "total_dungeons": 4,
        "total_clear_count": 0,
        "recent_entries": [],
    }
    assert state.json()["story_collection"]["collected_count"] == 0
    assert state.json()["story_collection"]["total_count"] == 24
    assert state.json()["story_collection"]["completed"] is False
    assert [
        chapter["collected_count"]
        for chapter in state.json()["story_collection"]["chapters"]
    ] == [0, 0]
    assert all(
        item["title"] is None and item["text"] is None
        for chapter in state.json()["story_collection"]["chapters"]
        for item in chapter["items"]
    )
    assert state.json()["economy"][0] == {
        "code": "diary",
        "label": "마음 일기",
        "exp": 40,
        "seeds": 15,
    }
    assert state.json()["milestones"]["current_title"] == "첫 발자국"
    assert state.json()["milestones"]["unlocked_count"] == 0
    assert state.json()["milestones"]["items"][0]["progress"] == 0

    blocked = await client.post(
        "/adventure/patrols",
        json={"route_code": "greenhouse_edge"},
        headers=auth_headers(tokens, idem=True),
    )
    assert blocked.status_code == 409
    assert blocked.json()["code"] == "DIARY_REQUIRED"

    diary = await client.post(
        "/moods",
        json={"content": LONG_DIARY},
        headers=auth_headers(tokens, idem=True),
    )
    assert diary.status_code == 201
    assert diary.json()["reward"]["daily_exp_granted"] == 40
    assert diary.json()["reward"]["seed_balance"] == 15
    assert diary.json()["reward"]["plant"]["stage"] == 2

    started = await client.post(
        "/adventure/patrols",
        json={"route_code": "greenhouse_edge"},
        headers=auth_headers(tokens, idem=True),
    )
    assert started.status_code == 201, started.text
    patrol_id = started.json()["patrol"]["id"]
    assert started.json()["state"]["patrol"]["status"] == "active"
    assert started.json()["patrol"]["performance_score"] == 12
    assert started.json()["patrol"]["encounter_pending"] is True
    assert started.json()["patrol"]["encounter"] is None

    early = await client.post(
        f"/adventure/patrols/{patrol_id}/claim",
        headers=auth_headers(tokens, idem=True),
    )
    assert early.status_code == 409
    assert early.json()["code"] == "PATROL_NOT_READY"

    async with session_factory() as db:
        patrol = await db.get(AdventurePatrol, patrol_id)
        assert patrol.encounter_code
        assert patrol.encounter_title
        assert patrol.encounter_text
        assert patrol.reaction_form == "mosaic"
        assert patrol.reaction_speaker
        assert patrol.reaction_text
        patrol.returns_at = utcnow() - timedelta(seconds=1)
        await db.commit()

    claimed = await client.post(
        f"/adventure/patrols/{patrol_id}/claim",
        headers=auth_headers(tokens, idem=True),
    )
    assert claimed.status_code == 200, claimed.text
    body = claimed.json()
    assert body["reward"]["events"] == [
        {"event_type": "patrol_claimed", "exp_delta": 0, "seed_delta": 3}
    ]
    assert body["reward"]["seed_balance"] == 18
    assert body["discovery"] == {"code": "moss_archive", "is_new": True}
    assert set(body["encounter"]) == {"code", "title", "text", "reaction"}
    assert body["encounter"]["reaction"]["form"] == "mosaic"
    assert body["encounter"]["reaction"]["speaker"]
    assert body["encounter"]["reaction"]["text"]
    assert body["outcome_message"] == (
        f"{body['encounter']['title']}: {body['encounter']['text']}\n"
        f"{body['encounter']['reaction']['speaker']}: "
        f"“{body['encounter']['reaction']['text']}”"
    )
    assert body["patrol"]["encounter_pending"] is False
    assert body["patrol"]["encounter"] == body["encounter"]
    assert body["state"]["inventory"][0]["code"] == "pressed_leaf_map"
    patrol_entry = body["state"]["journal"]["recent_entries"][0]
    assert patrol_entry["title"] == body["encounter"]["title"]
    assert patrol_entry["description"].startswith(body["encounter"]["text"])
    assert body["encounter"]["reaction"]["text"] in patrol_entry["description"]
    milestone_progress = {
        item["code"]: item["progress"] for item in body["state"]["milestones"]["items"]
    }
    assert milestone_progress["seven_day_diary"] == 1
    assert milestone_progress["five_patrol_returns"] == 1
    assert (
        next(d for d in body["state"]["dungeons"] if d["code"] == "moss_archive")[
            "discovered"
        ]
        is True
    )

    ran = await client.post(
        "/adventure/dungeons/moss_archive/run",
        headers=auth_headers(tokens, idem=True),
    )
    assert ran.status_code == 200, ran.text
    assert ran.json()["reward"]["events"] == [
        {"event_type": "dungeon_cleared", "exp_delta": 10, "seed_delta": 4}
    ]
    assert ran.json()["reward"]["daily_exp_granted"] == 50
    assert ran.json()["reward"]["seed_balance"] == 22
    assert ran.json()["run"]["approach_code"] == "steady"
    assert ran.json()["run"]["outcome_code"] == "steady"
    assert set(ran.json()["run"]["scene"]) == {"code", "title", "text"}
    assert ran.json()["run"]["outcome_message"].startswith(
        f"{ran.json()['run']['scene']['title']}: "
    )
    collection = ran.json()["state"]["story_collection"]
    assert collection["collected_count"] == 2
    assert collection["total_count"] == 24
    patrol_chapter, dungeon_chapter = collection["chapters"]
    assert patrol_chapter["collected_count"] == 1
    assert dungeon_chapter["collected_count"] == 1
    saved_encounter = next(
        item
        for item in patrol_chapter["items"]
        if item["code"] == body["encounter"]["code"]
    )
    assert saved_encounter["title"] == body["encounter"]["title"]
    assert body["encounter"]["reaction"]["text"] in saved_encounter["detail"]
    saved_scene = next(
        item
        for item in dungeon_chapter["items"]
        if item["code"] == ran.json()["run"]["scene"]["code"]
    )
    assert saved_scene["title"] == ran.json()["run"]["scene"]["title"]
    assert saved_scene["detail"] == "차분히 둘러보기 · 차분한 발견"
    dungeon_milestone = next(
        item
        for item in ran.json()["state"]["milestones"]["items"]
        if item["code"] == "five_dungeon_runs"
    )
    assert dungeon_milestone["progress"] == 1

    second_run = await client.post(
        "/adventure/dungeons/moss_archive/run",
        headers=auth_headers(tokens, idem=True),
    )
    assert second_run.status_code == 409
    assert second_run.json()["code"] == "DUNGEON_DAILY_LIMIT"

    async with session_factory() as db:
        dungeon = await db.scalar(
            sa.select(UserDungeon).where(
                UserDungeon.user_id == tokens["user"]["id"],
                UserDungeon.dungeon_code == "moss_archive",
            )
        )
        assert dungeon.clear_count == 1
        run = await db.scalar(
            sa.select(DungeonRun).where(DungeonRun.user_id == tokens["user"]["id"])
        )
        assert run.approach_code == "steady"
        assert run.approach_stat is None
        assert run.scene_code
        assert run.scene_title
        assert run.scene_text
        events = list(
            (
                await db.execute(
                    sa.select(RewardEvent.event_type).where(
                        RewardEvent.user_id == tokens["user"]["id"],
                        RewardEvent.event_type.in_(
                            (
                                RewardEventType.PATROL_CLAIMED,
                                RewardEventType.DUNGEON_CLEARED,
                            )
                        ),
                    )
                )
            ).scalars()
        )
        assert events == ["patrol_claimed", "dungeon_cleared"]


async def test_patrol_is_limited_to_once_per_day(client):
    tokens = await signup(client)
    await client.post(
        "/moods",
        json={"content": LONG_DIARY},
        headers=auth_headers(tokens, idem=True),
    )
    first = await client.post(
        "/adventure/patrols",
        json={"route_code": "greenhouse_edge"},
        headers=auth_headers(tokens, idem=True),
    )
    assert first.status_code == 201
    second = await client.post(
        "/adventure/patrols",
        json={"route_code": "greenhouse_edge"},
        headers=auth_headers(tokens, idem=True),
    )
    assert second.status_code == 409
    assert second.json()["code"] == "PATROL_ALREADY_STARTED"


async def test_equipped_outfit_bonus_changes_collection_performance(
    client, session_factory
):
    tokens = await signup(client)
    user_id = tokens["user"]["id"]
    async with session_factory() as db:
        outfit = Item(
            code="wardrobe_test_patrol",
            type="wardrobe",
            name="테스트 순찰복",
            description="순찰 보너스 검증",
            price_seeds=0,
            rarity=1,
            asset_manifest={
                "wardrobe_layer_key": "test-patrol",
                "adventure_bonus": {
                    "context": "patrol",
                    "stat": "care",
                    "amount": 2,
                    "label": "순찰 돌봄 +2",
                },
            },
            is_active=True,
        )
        db.add(outfit)
        await db.flush()
        owned = UserItem(user_id=user_id, item_id=outfit.id)
        db.add(owned)
        await db.flush()
        db.add(
            FarmLayout(
                user_id=user_id,
                version=1,
                layout={"wardrobe_user_item_id": owned.id},
            )
        )
        await db.commit()

    await client.post(
        "/moods",
        json={"content": LONG_DIARY},
        headers=auth_headers(tokens, idem=True),
    )
    state = await client.get("/adventure", headers=auth_headers(tokens))
    assert state.status_code == 200
    assert state.json()["character"]["outfit"]["bonus"]["label"] == "순찰 돌봄 +2"
    edge = next(
        route for route in state.json()["routes"] if route["code"] == "greenhouse_edge"
    )
    assert edge["performance_score"] == 14
    assert edge["projected_quantity"] == 1
    assert edge["best_match"] is True

    started = await client.post(
        "/adventure/patrols",
        json={"route_code": "greenhouse_edge"},
        headers=auth_headers(tokens, idem=True),
    )
    assert started.status_code == 201
    assert started.json()["patrol"]["performance_score"] == 14


async def test_research_consumes_materials_and_improves_future_collection(
    client, session_factory
):
    tokens = await signup(client)
    user_id = tokens["user"]["id"]

    initial = await client.get("/adventure", headers=auth_headers(tokens))
    assert initial.status_code == 200
    atlas = next(
        project
        for project in initial.json()["research_projects"]
        if project["code"] == "pressed_leaf_atlas"
    )
    assert atlas["completed"] is False
    assert atlas["can_complete"] is False
    assert atlas["effect"]["label"] == "순찰 수집량 영구 +1"

    missing = await client.post(
        "/adventure/research/pressed_leaf_atlas/complete",
        headers=auth_headers(tokens, idem=True),
    )
    assert missing.status_code == 409
    assert missing.json()["code"] == "RESEARCH_MATERIALS_REQUIRED"
    assert {item["code"] for item in missing.json()["details"]["missing"]} == {
        "pressed_leaf_map",
        "moss_key",
    }

    async with session_factory() as db:
        db.add_all(
            [
                UserAdventureItem(
                    user_id=user_id, item_code="pressed_leaf_map", quantity=2
                ),
                UserAdventureItem(user_id=user_id, item_code="moss_key", quantity=1),
            ]
        )
        await db.commit()

    complete_headers = {
        **auth_headers(tokens),
        "Idempotency-Key": "research-complete-pressed-leaf-atlas",
    }
    completed = await client.post(
        "/adventure/research/pressed_leaf_atlas/complete",
        headers=complete_headers,
    )
    assert completed.status_code == 201, completed.text
    assert completed.json()["research"]["effect"]["context"] == "patrol"
    completed_atlas = next(
        project
        for project in completed.json()["state"]["research_projects"]
        if project["code"] == "pressed_leaf_atlas"
    )
    assert completed_atlas["completed"] is True
    assert completed.json()["state"]["inventory"] == []

    replay = await client.post(
        "/adventure/research/pressed_leaf_atlas/complete",
        headers=complete_headers,
    )
    assert replay.status_code == 201
    duplicate = await client.post(
        "/adventure/research/pressed_leaf_atlas/complete",
        headers=auth_headers(tokens, idem=True),
    )
    assert duplicate.status_code == 409
    assert duplicate.json()["code"] == "RESEARCH_ALREADY_COMPLETED"

    async with session_factory() as db:
        saved = await db.scalar(
            sa.select(UserAdventureResearch).where(
                UserAdventureResearch.user_id == user_id,
                UserAdventureResearch.project_code == "pressed_leaf_atlas",
            )
        )
        assert saved is not None

    diary = await client.post(
        "/moods",
        json={"content": LONG_DIARY},
        headers=auth_headers(tokens, idem=True),
    )
    assert diary.status_code == 201
    preview = await client.get("/adventure", headers=auth_headers(tokens))
    edge = next(
        route
        for route in preview.json()["routes"]
        if route["code"] == "greenhouse_edge"
    )
    assert edge["performance_score"] == 12
    assert edge["projected_quantity"] == 2
    assert edge["best_match"] is True
    started = await client.post(
        "/adventure/patrols",
        json={"route_code": "greenhouse_edge"},
        headers=auth_headers(tokens, idem=True),
    )
    assert started.status_code == 201
    assert started.json()["patrol"]["performance_score"] == 12
    assert started.json()["patrol"]["found_quantity"] == 2


async def test_dungeon_approach_uses_character_and_outfit_stats(
    client, session_factory
):
    tokens = await signup(client)
    user_id = tokens["user"]["id"]
    diary = await client.post(
        "/moods",
        json={"content": LONG_DIARY},
        headers=auth_headers(tokens, idem=True),
    )
    assert diary.status_code == 201

    async with session_factory() as db:
        outfit = Item(
            code="wardrobe_test_dungeon",
            type="wardrobe",
            name="테스트 탐험복",
            description="던전 접근 방식 검증",
            price_seeds=0,
            rarity=1,
            asset_manifest={
                "wardrobe_layer_key": "test-dungeon",
                "adventure_bonus": {
                    "context": "dungeon",
                    "stat": "focus",
                    "amount": 2,
                    "label": "던전 집중 +2",
                },
            },
            is_active=True,
        )
        db.add(outfit)
        await db.flush()
        owned = UserItem(user_id=user_id, item_id=outfit.id)
        db.add(owned)
        await db.flush()
        db.add_all(
            [
                FarmLayout(
                    user_id=user_id,
                    version=1,
                    layout={"wardrobe_user_item_id": owned.id},
                ),
                UserDungeon(
                    user_id=user_id,
                    dungeon_code="moss_archive",
                    discovered_at=utcnow(),
                ),
            ]
        )
        await db.commit()

    state = await client.get("/adventure", headers=auth_headers(tokens))
    dungeon = next(
        item for item in state.json()["dungeons"] if item["code"] == "moss_archive"
    )
    assert len(dungeon["approaches"]) == 4
    focus = next(
        approach for approach in dungeon["approaches"] if approach["code"] == "focus"
    )
    assert focus["recommended"] is True
    assert focus["performance_score"] >= 9
    assert focus["projected_quantity"] == 2
    assert focus["projected_outcome"] == "resonant"

    invalid = await client.post(
        "/adventure/dungeons/moss_archive/run",
        json={"approach_code": "unknown"},
        headers=auth_headers(tokens, idem=True),
    )
    assert invalid.status_code == 404
    assert invalid.json()["code"] == "DUNGEON_APPROACH_NOT_FOUND"

    ran = await client.post(
        "/adventure/dungeons/moss_archive/run",
        json={"approach_code": "focus"},
        headers=auth_headers(tokens, idem=True),
    )
    assert ran.status_code == 200, ran.text
    assert ran.json()["run"]["approach_code"] == "focus"
    assert ran.json()["run"]["approach_stat"] == "focus"
    assert ran.json()["run"]["outcome_code"] == "resonant"
    assert ran.json()["run"]["found_quantity"] == 2
    assert set(ran.json()["run"]["scene"]) == {"code", "title", "text"}
    assert "집중 성장" in ran.json()["run"]["outcome_message"]
    assert ran.json()["reward"]["daily_exp_granted"] == 50
    assert ran.json()["reward"]["seed_balance"] == 19

    async with session_factory() as db:
        saved = await db.scalar(
            sa.select(DungeonRun).where(DungeonRun.user_id == user_id)
        )
        assert saved.approach_code == "focus"
        assert saved.approach_stat == "focus"
        assert saved.outcome_code == "resonant"


async def test_stage_four_route_unlocks_dungeon_and_time_research(
    client, session_factory
):
    tokens = await signup(client)
    user_id = tokens["user"]["id"]
    diary = await client.post(
        "/moods",
        json={"content": LONG_DIARY},
        headers=auth_headers(tokens, idem=True),
    )
    assert diary.status_code == 201

    async with session_factory() as db:
        plant = await db.scalar(sa.select(Plant).where(Plant.user_id == user_id))
        plant.exp = 250
        db.add_all(
            [
                UserAdventureItem(
                    user_id=user_id,
                    item_code="glass_leaf_vein",
                    quantity=2,
                ),
                UserAdventureItem(
                    user_id=user_id,
                    item_code="starlight_pollen",
                    quantity=1,
                ),
                UserAdventureItem(
                    user_id=user_id,
                    item_code="moon_dew",
                    quantity=1,
                ),
            ]
        )
        await db.commit()

    state = await client.get("/adventure", headers=auth_headers(tokens))
    rooftop = next(
        route for route in state.json()["routes"] if route["code"] == "glass_rooftop"
    )
    assert rooftop["available"] is True
    assert rooftop["duration_minutes"] == 30
    assert rooftop["time_reduction_minutes"] == 0
    assert rooftop["best_match"] is True
    vault = next(
        dungeon
        for dungeon in state.json()["dungeons"]
        if dungeon["code"] == "starlight_seed_vault"
    )
    assert vault["discovered"] is False
    assert vault["asset_path"].endswith("dungeon-starlight-seed-vault.webp")

    research = await client.post(
        "/adventure/research/starlight_greenhouse_clock/complete",
        headers=auth_headers(tokens, idem=True),
    )
    assert research.status_code == 201, research.text
    reduced_route = next(
        route
        for route in research.json()["state"]["routes"]
        if route["code"] == "glass_rooftop"
    )
    assert reduced_route["base_duration_minutes"] == 30
    assert reduced_route["duration_minutes"] == 25
    assert reduced_route["time_reduction_minutes"] == 5

    started = await client.post(
        "/adventure/patrols",
        json={"route_code": "glass_rooftop"},
        headers=auth_headers(tokens, idem=True),
    )
    assert started.status_code == 201, started.text
    patrol_id = started.json()["patrol"]["id"]
    async with session_factory() as db:
        patrol = await db.get(AdventurePatrol, patrol_id)
        assert patrol.returns_at - patrol.started_at == timedelta(minutes=25)
        patrol.returns_at = utcnow() - timedelta(seconds=1)
        await db.commit()

    claimed = await client.post(
        f"/adventure/patrols/{patrol_id}/claim",
        headers=auth_headers(tokens, idem=True),
    )
    assert claimed.status_code == 200, claimed.text
    assert claimed.json()["discovery"] == {
        "code": "starlight_seed_vault",
        "is_new": True,
    }

    ran = await client.post(
        "/adventure/dungeons/starlight_seed_vault/run",
        json={"approach_code": "focus"},
        headers=auth_headers(tokens, idem=True),
    )
    assert ran.status_code == 200, ran.text
    assert ran.json()["run"]["outcome_code"] == "resonant"
    assert ran.json()["run"]["found_item_code"] == "starlight_pollen"
    assert ran.json()["run"]["found_quantity"] == 2
    pollen = next(
        item
        for item in ran.json()["state"]["inventory"]
        if item["code"] == "starlight_pollen"
    )
    assert pollen["quantity"] == 2


async def test_stage_five_completes_first_exploration_chapter(client, session_factory):
    tokens = await signup(client)
    user_id = tokens["user"]["id"]
    diary = await client.post(
        "/moods",
        json={"content": LONG_DIARY},
        headers=auth_headers(tokens, idem=True),
    )
    assert diary.status_code == 201

    async with session_factory() as db:
        plant = await db.scalar(sa.select(Plant).where(Plant.user_id == user_id))
        plant.exp = 450
        db.add_all(
            [
                UserAdventureItem(user_id=user_id, item_code="moss_key", quantity=1),
                UserAdventureItem(user_id=user_id, item_code="echo_seed", quantity=1),
                UserAdventureItem(
                    user_id=user_id,
                    item_code="starlight_pollen",
                    quantity=1,
                ),
            ]
        )
        await db.commit()

    state = await client.get("/adventure", headers=auth_headers(tokens))
    assert state.status_code == 200
    assert state.json()["research_summary"] == {
        "completed_count": 0,
        "total_count": 5,
        "chapter_completed": False,
        "chapter_name": "온실 밖 탐험 1장",
    }
    canopy = next(
        route for route in state.json()["routes"] if route["code"] == "dawn_canopy_walk"
    )
    assert canopy["available"] is True
    assert canopy["duration_minutes"] == 40
    observatory = next(
        dungeon
        for dungeon in state.json()["dungeons"]
        if dungeon["code"] == "heartwood_observatory"
    )
    assert observatory["discovered"] is False
    assert observatory["asset_path"].endswith("dungeon-heartwood-observatory.webp")

    started = await client.post(
        "/adventure/patrols",
        json={"route_code": "dawn_canopy_walk"},
        headers=auth_headers(tokens, idem=True),
    )
    assert started.status_code == 201, started.text
    assert started.json()["patrol"]["found_quantity"] == 2
    patrol_id = started.json()["patrol"]["id"]
    async with session_factory() as db:
        patrol = await db.get(AdventurePatrol, patrol_id)
        patrol.returns_at = utcnow() - timedelta(seconds=1)
        await db.commit()

    claimed = await client.post(
        f"/adventure/patrols/{patrol_id}/claim",
        headers=auth_headers(tokens, idem=True),
    )
    assert claimed.status_code == 200, claimed.text
    assert claimed.json()["discovery"] == {
        "code": "heartwood_observatory",
        "is_new": True,
    }
    canopy_encounter = claimed.json()["encounter"]

    ran = await client.post(
        "/adventure/dungeons/heartwood_observatory/run",
        json={"approach_code": "focus"},
        headers=auth_headers(tokens, idem=True),
    )
    assert ran.status_code == 200, ran.text
    assert ran.json()["run"]["outcome_code"] == "resonant"
    assert ran.json()["run"]["found_item_code"] == "heartwood_seed_sample"
    assert ran.json()["run"]["found_quantity"] == 2
    observatory_scene = ran.json()["run"]["scene"]
    inventory = {
        item["code"]: item["quantity"] for item in ran.json()["state"]["inventory"]
    }
    assert inventory["dawn_bark_rubbing"] == 2
    assert inventory["heartwood_seed_sample"] == 2
    journal = ran.json()["state"]["journal"]
    assert journal["discovered_count"] == 1
    assert journal["total_dungeons"] == 4
    assert journal["total_clear_count"] == 1
    assert [entry["kind"] for entry in journal["recent_entries"]] == [
        "dungeon",
        "patrol",
    ]
    assert journal["recent_entries"][0]["title"] == observatory_scene["title"]
    assert journal["recent_entries"][0]["description"].startswith(
        observatory_scene["text"]
    )
    assert journal["recent_entries"][0]["outcome_code"] == "resonant"
    assert journal["recent_entries"][1]["title"] == canopy_encounter["title"]
    assert journal["recent_entries"][1]["description"].startswith(
        canopy_encounter["text"]
    )

    completed = await client.post(
        "/adventure/research/outside_greenhouse_atlas/complete",
        headers=auth_headers(tokens, idem=True),
    )
    assert completed.status_code == 201, completed.text
    assert completed.json()["research"]["effect"] == {
        "context": "archive",
        "amount": 0,
        "label": "온실 밖 탐험 1장 완성",
    }
    completed_state = completed.json()["state"]
    assert completed_state["research_summary"] == {
        "completed_count": 1,
        "total_count": 5,
        "chapter_completed": True,
        "chapter_name": "온실 밖 탐험 1장",
    }
    final_project = next(
        project
        for project in completed_state["research_projects"]
        if project["code"] == "outside_greenhouse_atlas"
    )
    assert final_project["completed"] is True
    remaining = {
        item["code"]: item["quantity"] for item in completed_state["inventory"]
    }
    for consumed_code in (
        "dawn_bark_rubbing",
        "heartwood_seed_sample",
        "moss_key",
        "echo_seed",
        "starlight_pollen",
    ):
        assert consumed_code not in remaining
