from datetime import timedelta

import sqlalchemy as sa

from app.core.timeutil import utcnow
from app.models.adventure import (
    AdventurePatrol,
    UserAdventureItem,
    UserAdventureResearch,
    UserDungeon,
)
from app.models.enums import RewardEventType
from app.models.game import FarmLayout, Item, UserItem
from app.models.reward import RewardEvent
from tests.conftest import auth_headers, signup


LONG_DIARY = (
    "오늘은 생각보다 마음이 자주 흔들렸다. 그래도 잠깐 멈춰서 어떤 감정인지 "
    "하나씩 적어 보니 지금 필요한 것이 무엇인지 조금은 알 것 같다."
)


async def test_adventure_requires_diary_then_completes_patrol_and_dungeon(
    client, session_factory
):
    tokens = await signup(client)
    headers = auth_headers(tokens)

    state = await client.get("/adventure", headers=headers)
    assert state.status_code == 200
    assert state.json()["diary_ready"] is False
    assert state.json()["economy"][0] == {
        "code": "diary",
        "label": "마음 일기",
        "exp": 40,
        "seeds": 15,
    }

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

    early = await client.post(
        f"/adventure/patrols/{patrol_id}/claim",
        headers=auth_headers(tokens, idem=True),
    )
    assert early.status_code == 409
    assert early.json()["code"] == "PATROL_NOT_READY"

    async with session_factory() as db:
        patrol = await db.get(AdventurePatrol, patrol_id)
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
    assert body["state"]["inventory"][0]["code"] == "pressed_leaf_map"
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
    started = await client.post(
        "/adventure/patrols",
        json={"route_code": "greenhouse_edge"},
        headers=auth_headers(tokens, idem=True),
    )
    assert started.status_code == 201
    assert started.json()["patrol"]["performance_score"] == 12
    assert started.json()["patrol"]["found_quantity"] == 2
