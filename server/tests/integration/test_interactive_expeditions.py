import sqlalchemy as sa

from app.models.adventure import UserAdventureItem
from app.models.expedition import ExpeditionAction, ExpeditionPartyMember, ExpeditionRun
from app.models.expedition import (
    PlantAdventureBond,
    PlantRegionFamiliarity,
    UserRegionProgress,
)
from app.models.game import FarmLayout, Item, UserItem
from app.models.plant import Plant
from app.models.reward import RewardEvent

from tests.conftest import auth_headers


async def _prepare_stage_two(session_factory, user_id: int) -> int:
    async with session_factory() as db:
        plant = await db.scalar(sa.select(Plant).where(Plant.user_id == user_id))
        plant.exp = 20
        await db.commit()
        return plant.id


async def _start(
    client,
    headers: dict,
    plant_id: int,
    mode: str = "tutorial",
    stage_no: int | None = None,
    key: str | None = None,
) -> dict:
    response = await client.post(
        "/adventure/expeditions",
        headers={**headers, "Idempotency-Key": key or f"start-{mode}-0001"},
        json={
            "region_code": "moss_archive",
            "mode": mode,
            "plant_ids": [plant_id],
            "guide_count": 1,
            **({"stage_no": stage_no} if stage_no is not None else {}),
        },
    )
    assert response.status_code == 201, response.text
    return response.json()


async def _action(
    client, headers: dict, run: dict, path: str, payload: dict, key: str
) -> dict:
    response = await client.post(
        f"/adventure/expeditions/{run['run']['id']}/{path}",
        headers=headers,
        json={
            **payload,
            "expected_revision": run["run"]["revision"],
            "client_action_id": key,
        },
    )
    assert response.status_code == 200, response.text
    return response.json()


async def _fight_guardian(client, headers: dict, run: dict, key_prefix: str) -> dict:
    """테스트도 실제 클라이언트처럼 대원별 행동을 순서대로 예약한다."""

    turn = 1
    while (run.get("current_event") or {}).get("battle", {}).get("status") == "active":
        battle = run["current_event"]["battle"]
        focus = battle["focus"]
        commands = []
        for member in battle["party"]:
            if member["hp"] <= 0:
                continue
            skill_cost = member["kit"]["skill"]["focus_cost"]
            if focus >= skill_cost:
                action = "skill"
                focus -= skill_cost
            else:
                action = "attack"
                focus = min(battle["max_focus"], focus + 1)
            commands.append({"member_id": member["member_id"], "action": action})
        run = await _action(
            client,
            headers,
            run,
            "combat/turns",
            {"commands": commands},
            f"{key_prefix}-{turn:04d}",
        )
        assert run["last_combat_exchange"]
        turn += 1
        assert turn <= 7
    return run


async def _reach_guardian(client, headers: dict, run: dict, key_prefix: str) -> dict:
    run = await _action(
        client,
        headers,
        run,
        "move",
        {"node_code": "wet_labels"},
        f"{key_prefix}-wet",
    )
    actor = run["party"][0]["id"]
    run = await _action(
        client,
        headers,
        run,
        "choices",
        {"choice_code": "mark_return", "acting_member_id": actor},
        f"{key_prefix}-choice",
    )
    run = await _action(
        client,
        headers,
        run,
        "move",
        {"node_code": "quiet_camp"},
        f"{key_prefix}-camp",
    )
    return await _action(
        client,
        headers,
        run,
        "move",
        {"node_code": "ledger_keeper"},
        f"{key_prefix}-keeper",
    )


async def _complete_run(client, headers: dict, run: dict) -> dict:
    run = await _action(
        client, headers, run, "move", {"node_code": "wet_labels"}, "move-wet-0001"
    )
    actor = run["party"][0]["id"]
    run = await _action(
        client,
        headers,
        run,
        "skills",
        {"member_id": actor, "skill_type": "signature"},
        "skill-signature-0001",
    )
    run = await _action(
        client,
        headers,
        run,
        "choices",
        {"choice_code": "trace_ink", "acting_member_id": actor},
        "choice-wet-0001",
    )
    run = await _action(
        client, headers, run, "move", {"node_code": "quiet_camp"}, "move-camp-0001"
    )
    run = await _action(
        client, headers, run, "move", {"node_code": "ledger_keeper"}, "move-keeper-0001"
    )
    assert {action["type"] for action in run["available_actions"]} == {
        "combat_turn",
        "retreat",
    }
    run = await _fight_guardian(client, headers, run, "combat-keeper")
    resolution = run["last_resolution"]
    assert resolution["event_code"] == "ledger_keeper"
    assert resolution["actor_name"]
    assert resolution["battle_status"] == "victory"
    assert resolution["score"] == 100
    assert run["last_combat_exchange"][-1] == {
        "sequence": run["last_combat_exchange"][-1]["sequence"],
        "type": "outcome",
        "outcome": "victory",
        "caption": "수호 장벽이 부서지고 장부지기가 길을 열었어요!",
    }
    run = await _action(
        client,
        headers,
        run,
        "move",
        {"node_code": "memory_drawer"},
        "move-objective-0001",
    )
    assert run["run"]["objective_secured"] is True
    run = await _action(
        client, headers, run, "move", {"node_code": "exit"}, "move-exit-0001"
    )
    return await _action(client, headers, run, "extract", {}, "extract-run-0001")


async def test_expedition_map_actions_are_authoritative_and_replayable(
    client, user_tokens, session_factory
):
    headers = auth_headers(user_tokens)
    user_id = user_tokens["user"]["id"]
    plant_id = await _prepare_stage_two(session_factory, user_id)

    guide_only = await client.post(
        "/adventure/expeditions",
        headers={**headers, "Idempotency-Key": "guide-only-party-0001"},
        json={
            "region_code": "moss_archive",
            "mode": "tutorial",
            "plant_ids": [],
            "guide_count": 1,
        },
    )
    assert guide_only.status_code == 422

    roster = await client.get("/adventure/expeditions/roster", headers=headers)
    assert roster.status_code == 200
    assert roster.json()["items"][0]["eligible"] is True

    run = await _start(client, headers, plant_id, mode="free_explore")
    assert run["run"]["revision"] == 0
    entrance = next(node for node in run["map"]["nodes"] if node["code"] == "entrance")
    assert entrance["scene_key"] == "dungeon_gate"
    assert entrance["scene_label"] == "폐허 던전"
    assert entrance["depth_label"] == "지하 1층 · 관문"
    assert entrance["threat_level"] == 1
    hidden = next(
        node for node in run["map"]["nodes"] if node["code"] == "ledger_keeper"
    )
    assert hidden == {"code": "ledger_keeper", "status": "hidden", "type": "unknown"}

    move_body = {
        "node_code": "wet_labels",
        "expected_revision": 0,
        "client_action_id": "replay-move-0001",
    }
    first = await client.post(
        f"/adventure/expeditions/{run['run']['id']}/move",
        headers=headers,
        json=move_body,
    )
    replay = await client.post(
        f"/adventure/expeditions/{run['run']['id']}/move",
        headers=headers,
        json=move_body,
    )
    assert first.status_code == replay.status_code == 200
    assert first.json() == replay.json()
    run = first.json()
    assert run["run"]["phase"] == "awaiting_event"
    flooded_cave = next(
        node for node in run["map"]["nodes"] if node["code"] == "wet_labels"
    )
    assert flooded_cave["scene_key"] == "flooded_cave"
    assert flooded_cave["depth_label"] == "지하 2층 · 수몰 구역"
    assert run["current_event"]["choices"][0]["previews"][0]["difficulty"] == 8

    stale = await client.post(
        f"/adventure/expeditions/{run['run']['id']}/skills",
        headers=headers,
        json={
            "member_id": run["party"][0]["id"],
            "skill_type": "form",
            "expected_revision": 0,
            "client_action_id": "stale-skill-0001",
        },
    )
    assert stale.status_code == 409
    assert stale.json()["code"] == "EXPEDITION_REVISION_CONFLICT"

    retreat = await _action(client, headers, run, "retreat", {}, "retreat-run-0001")
    assert retreat["run"]["status"] == "retreated"
    active = await client.get("/adventure/expeditions/active", headers=headers)
    assert active.json() == {"expedition": None}

    async with session_factory() as db:
        action_count = await db.scalar(
            sa.select(sa.func.count(ExpeditionAction.id)).where(
                ExpeditionAction.run_id == run["run"]["id"]
            )
        )
        assert action_count == 2


async def test_tutorial_uses_fixed_visible_map_and_active_character_with_guide(
    client, user_tokens, session_factory
):
    headers = auth_headers(user_tokens)
    user_id = user_tokens["user"]["id"]
    plant_id = await _prepare_stage_two(session_factory, user_id)

    async with session_factory() as db:
        outfit = Item(
            code="wardrobe_expedition_snapshot",
            type="wardrobe",
            name="탐험 의상",
            description="탐험 스냅샷 검증용 의상",
            price_seeds=0,
            rarity=1,
            asset_manifest={
                "wardrobe_layer_key": "garden-daily",
                "compatible_species": ["basic_sprout"],
            },
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

    invalid_party = await client.post(
        "/adventure/expeditions",
        headers={**headers, "Idempotency-Key": "tutorial-without-guide-0001"},
        json={
            "region_code": "moss_archive",
            "mode": "tutorial",
            "plant_ids": [plant_id],
            "guide_count": 0,
        },
    )
    assert invalid_party.status_code == 422
    assert invalid_party.json()["code"] == "TUTORIAL_PARTY_FIXED"

    run = await _start(client, headers, plant_id, mode="tutorial")

    assert run["map"]["code"] == "archive_loop_a"
    assert all(node["status"] != "hidden" for node in run["map"]["nodes"])
    assert len(run["party"]) == 2
    assert run["party"][0]["is_guide"] is False
    assert run["party"][0]["plant_id"] == plant_id
    assert run["party"][0]["outfit_key"] == "garden-daily"
    assert run["party"][1]["is_guide"] is True
    assert run["party"][1]["outfit_key"] is None

    guide_skill = await client.post(
        f"/adventure/expeditions/{run['run']['id']}/skills",
        headers=headers,
        json={
            "member_id": run["party"][1]["id"],
            "skill_type": "signature",
            "expected_revision": 0,
            "client_action_id": "tutorial-guide-skill-0001",
        },
    )
    assert guide_skill.status_code == 422
    assert guide_skill.json()["code"] == "EXPEDITION_MEMBER_INVALID"

    catalog = await client.get("/adventure/expeditions/catalog", headers=headers)
    assert catalog.json()["entry"]["tutorial_completed"] is False
    completed = await _complete_run(client, headers, run)
    assert completed["run"]["status"] == "completed"
    catalog = await client.get("/adventure/expeditions/catalog", headers=headers)
    assert catalog.json()["entry"]["tutorial_completed"] is True


async def test_species_signature_skill_uses_its_own_name_and_effect(
    client, user_tokens, session_factory
):
    headers = auth_headers(user_tokens)
    user_id = user_tokens["user"]["id"]
    plant_id = await _prepare_stage_two(session_factory, user_id)
    run = await _start(client, headers, plant_id, mode="free_explore")

    async with session_factory() as db:
        member = await db.get(ExpeditionPartyMember, run["party"][0]["id"])
        snapshot = dict(member.snapshot)
        snapshot["species"] = {"code": "handsome-pot", "name": "로제온"}
        member.snapshot = snapshot
        await db.commit()

    run = await _action(
        client,
        headers,
        run,
        "move",
        {"node_code": "wet_labels"},
        "skill-move-0001",
    )
    actor = run["party"][0]
    assert actor["skills"]["signature"]["name"] == "정돈된 지휘"
    before = run["current_event"]["choices"][0]["previews"][0]["value"]

    run = await _action(
        client,
        headers,
        run,
        "skills",
        {"member_id": actor["id"], "skill_type": "signature"},
        "skill-command-0001",
    )

    preview = run["current_event"]["choices"][0]["previews"][0]
    assert preview["value"] == before + 2
    assert preview["skill_bonus"] == 2
    assert {action["type"] for action in run["available_actions"]} == {"choice"}
    assert all(
        skill["available"] is False
        for member in run["party"]
        for skill in member["skills"].values()
    )

    run = await _action(
        client,
        headers,
        run,
        "choices",
        {"choice_code": "trace_ink", "acting_member_id": actor["id"]},
        "skill-command-choice-0001",
    )
    run = await _action(
        client,
        headers,
        run,
        "move",
        {"node_code": "quiet_camp"},
        "skill-command-camp-0001",
    )
    run = await _action(
        client,
        headers,
        run,
        "move",
        {"node_code": "ledger_keeper"},
        "skill-command-keeper-0001",
    )
    refreshed_actor = next(member for member in run["party"] if not member["is_guide"])
    assert refreshed_actor["skills"]["signature"]["used"] is True
    assert refreshed_actor["skills"]["form"]["available"] is True
    assert {action["type"] for action in run["available_actions"]} == {
        "combat_turn",
        "retreat",
    }
    assert (
        run["current_event"]["battle"]["party"][0]["kit"]["skill"]["name"]
        == "온기 지휘"
    )


async def test_region_cap_preserves_raw_stats_and_uses_effective_stats(
    client, user_tokens, session_factory
):
    headers = auth_headers(user_tokens)
    user_id = user_tokens["user"]["id"]
    plant_id = await _prepare_stage_two(session_factory, user_id)
    async with session_factory() as db:
        plant = await db.get(Plant, plant_id)
        plant.exp = 450
        await db.commit()

    run = await _start(client, headers, plant_id, mode="free_explore")
    actor = run["party"][0]
    assert max(actor["raw_stats"].values()) > 7
    assert max(actor["effective_stats"].values()) == 7
    assert actor["stats"] == actor["effective_stats"]
    assert actor["stat_cap"] == 7

    run = await _action(
        client,
        headers,
        run,
        "move",
        {"node_code": "wet_labels"},
        "cap-move-0001",
    )
    preview = run["current_event"]["choices"][0]["previews"][0]
    assert preview["raw_value"] >= preview["effective_value"]
    assert preview["effective_value"] <= 7
    assert "원래" in preview["label"]


async def test_heart_resonance_rewards_only_after_objective_and_return(
    client, user_tokens, session_factory
):
    headers = auth_headers(user_tokens)
    user_id = user_tokens["user"]["id"]
    diary = await client.post(
        "/moods",
        headers={**headers, "Idempotency-Key": "diary-expedition-0001"},
        json={
            "mood_level": 4,
            "emotion_tags": ["기대"],
            "content": "오늘은 마음이 조금 복잡했지만 작은 일을 하나씩 끝내며 안정을 찾았다. 이 감정을 캐릭터와 함께 천천히 살펴보고 싶다.",
        },
    )
    assert diary.status_code == 201, diary.text
    plant = await client.get("/plants/me", headers=headers)
    plant_id = plant.json()["plant"]["id"]

    catalog = await client.get("/adventure/expeditions/catalog", headers=headers)
    assert catalog.json()["entry"]["heart_resonance_available"] is True
    run = await _start(client, headers, plant_id, mode="heart_resonance")
    completed = await _complete_run(client, headers, run)

    assert completed["run"]["status"] == "completed"
    assert completed["summary"]["reward"]["events"] == [
        {"event_type": "expedition_completed", "exp_delta": 6, "seed_delta": 2}
    ]
    assert completed["loot"][0]["item_code"] == "moss_key"
    assert completed["loot"][0]["disposition"] == "granted"
    assert completed["summary"]["progress"] == {
        "first_clear": True,
        "clear_count": 1,
        "knowledge_code": "moss_archive.first_path",
        "bonds": [
            {
                "plant_id": plant_id,
                "bond_gained": True,
                "bond_points": 1,
                "familiarity_gained": True,
                "familiarity_points": 1,
            }
        ],
        # 스테이지 지도를 거치지 않은 run은 스테이지 진행을 남기지 않는다.
        "stage": None,
    }
    assert completed["summary"]["return_scene"]["title"] == "함께 돌아온 탐험대"
    returned = completed["summary"]["return_scene"]["members"]
    assert any(member["plant_id"] == plant_id for member in returned)
    assert all(member["contribution"] for member in returned)

    catalog = await client.get("/adventure/expeditions/catalog", headers=headers)
    assert catalog.json()["entry"]["heart_resonance_available"] is False
    async with session_factory() as db:
        reward_count = await db.scalar(
            sa.select(sa.func.count(RewardEvent.id)).where(
                RewardEvent.user_id == user_id,
                RewardEvent.event_type == "expedition_completed",
            )
        )
        assert reward_count == 1
        item = await db.scalar(
            sa.select(UserAdventureItem).where(
                UserAdventureItem.user_id == user_id,
                UserAdventureItem.item_code == "moss_key",
            )
        )
        assert item.quantity == 1
        stored = await db.get(ExpeditionRun, completed["run"]["id"])
        assert stored.status == "completed"
        bond = await db.get(PlantAdventureBond, plant_id)
        assert bond.bond_points == 1
        progress = await db.get(UserRegionProgress, (user_id, "moss_archive"))
        assert progress.clear_count == 1
        assert progress.templates_seen == [completed["map"]["code"]]
        assert progress.events_seen == ["ledger_keeper", "wet_label_order"]
        familiarity = await db.get(PlantRegionFamiliarity, (plant_id, "moss_archive"))
        assert familiarity.points == 1
        assert familiarity.participation_count == 1


async def test_free_explore_keeps_choices_but_does_not_create_economy_rewards(
    client, user_tokens, session_factory
):
    headers = auth_headers(user_tokens)
    user_id = user_tokens["user"]["id"]
    plant_id = await _prepare_stage_two(session_factory, user_id)

    run = await _start(client, headers, plant_id, mode="free_explore")
    completed = await _complete_run(client, headers, run)

    assert completed["run"]["status"] == "completed"
    assert completed["summary"]["reward"] is None
    assert completed["loot"][0]["disposition"] == "recorded"
    async with session_factory() as db:
        plant = await db.get(Plant, plant_id)
        assert plant.exp == 20
        expedition_rewards = await db.scalar(
            sa.select(sa.func.count(RewardEvent.id)).where(
                RewardEvent.user_id == user_id,
                RewardEvent.event_type == "expedition_completed",
            )
        )
        assert expedition_rewards == 0
        item = await db.scalar(
            sa.select(UserAdventureItem).where(
                UserAdventureItem.user_id == user_id,
                UserAdventureItem.item_code == "moss_key",
            )
        )
        assert item is None


async def test_guardian_requires_manual_commands_and_replays_each_round(
    client, user_tokens, session_factory
):
    headers = auth_headers(user_tokens)
    plant_id = await _prepare_stage_two(
        session_factory,
        user_tokens["user"]["id"],
    )
    run = await _reach_guardian(
        client,
        headers,
        await _start(client, headers, plant_id),
        "manual-contract",
    )
    battle = run["current_event"]["battle"]
    assert battle["round"] == 1
    assert battle["enemy"]["intent"]["target"] == "front"
    assert {action["type"] for action in run["available_actions"]} == {
        "combat_turn",
        "retreat",
    }

    legacy = await client.post(
        f"/adventure/expeditions/{run['run']['id']}/choices",
        headers=headers,
        json={
            "choice_code": "answer_together",
            "acting_member_id": run["party"][0]["id"],
            "expected_revision": run["run"]["revision"],
            "client_action_id": "manual-legacy-choice",
        },
    )
    assert legacy.status_code == 409
    assert legacy.json()["code"] == "EXPEDITION_COMBAT_COMMAND_REQUIRED"

    revision = run["run"]["revision"]
    commands = [
        {"member_id": member["member_id"], "action": "attack"}
        for member in battle["party"]
        if member["hp"] > 0
    ]
    body = {
        "commands": commands,
        "expected_revision": revision,
        "client_action_id": "manual-turn-replay-0001",
    }
    first = await client.post(
        f"/adventure/expeditions/{run['run']['id']}/combat/turns",
        headers=headers,
        json=body,
    )
    replay = await client.post(
        f"/adventure/expeditions/{run['run']['id']}/combat/turns",
        headers=headers,
        json=body,
    )
    assert first.status_code == replay.status_code == 200
    assert first.json() == replay.json()
    assert first.json()["current_event"]["battle"]["round"] == 2
    assert any(
        event["type"] == "enemy_action"
        for event in first.json()["last_combat_exchange"]
    )


async def test_guardian_accepts_sequential_partial_commands(
    client, user_tokens, session_factory
):
    """스테이지 개편의 순차 명령: 대원 한 명씩 제출해도 같은 라운드 계약을 지킨다."""

    headers = auth_headers(user_tokens)
    plant_id = await _prepare_stage_two(
        session_factory,
        user_tokens["user"]["id"],
    )
    run = await _reach_guardian(
        client,
        headers,
        await _start(client, headers, plant_id),
        "manual-partial",
    )
    battle = run["current_event"]["battle"]
    living = [member for member in battle["party"] if member["hp"] > 0]
    assert len(living) >= 2

    first = await client.post(
        f"/adventure/expeditions/{run['run']['id']}/combat/turns",
        headers=headers,
        json={
            "commands": [
                {"member_id": living[0]["member_id"], "action": "attack"}
            ],
            "partial": True,
            "expected_revision": run["run"]["revision"],
            "client_action_id": "manual-partial-0001",
        },
    )
    assert first.status_code == 200
    payload = first.json()
    mid_battle = payload["current_event"]["battle"]
    # 첫 대원만 행동했으므로 라운드는 그대로이고 적은 아직 움직이지 않는다.
    assert mid_battle["round"] == 1
    assert mid_battle["pending_round"]["acted"] == [living[0]["member_id"]]
    assert mid_battle["pending_round"]["awaiting"] == [
        member["member_id"] for member in living[1:]
    ]
    assert [event["type"] for event in payload["last_combat_exchange"]] == [
        "party_action"
    ]

    revision = payload["run"]["revision"]
    for index, member in enumerate(living[1:], start=2):
        response = await client.post(
            f"/adventure/expeditions/{run['run']['id']}/combat/turns",
            headers=headers,
            json={
                "commands": [
                    {"member_id": member["member_id"], "action": "attack"}
                ],
                "partial": True,
                "expected_revision": revision,
                "client_action_id": f"manual-partial-{index:04d}",
            },
        )
        assert response.status_code == 200
        payload = response.json()
        revision = payload["run"]["revision"]

    final_battle = payload["current_event"]["battle"]
    # 마지막 대원의 제출과 같은 응답에서 적 행동과 라운드 전환까지 해결된다.
    assert final_battle["round"] == 2
    assert final_battle["pending_round"]["acted"] == []
    assert any(
        event["type"] == "enemy_action"
        for event in payload["last_combat_exchange"]
    )


async def test_guardian_defeat_forces_safe_return_and_loses_carried_rewards(
    client, user_tokens, session_factory
):
    headers = auth_headers(user_tokens)
    plant_id = await _prepare_stage_two(
        session_factory,
        user_tokens["user"]["id"],
    )
    run = await _reach_guardian(
        client,
        headers,
        await _start(client, headers, plant_id),
        "manual-defeat",
    )
    for turn in range(1, 7):
        battle = run["current_event"]["battle"]
        run = await _action(
            client,
            headers,
            run,
            "combat/turns",
            {
                "commands": [
                    {"member_id": member["member_id"], "action": "guard"}
                    for member in battle["party"]
                    if member["hp"] > 0
                ]
            },
            f"manual-defeat-turn-{turn:04d}",
        )
        if run["run"]["status"] != "active":
            break

    assert run["run"]["status"] == "safe_returned"
    assert run["summary"]["reason"] == "guardian_defeat"
    assert run["summary"]["reward"] is None
    active = await client.get("/adventure/expeditions/active", headers=headers)
    assert active.status_code == 200
    assert active.json()["expedition"] is None
