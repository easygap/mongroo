"""스테이지 지도와 모험 허브가 읽는 진행 계약.

개편 설계서 3.1(8스테이지 구성), 3.3(엉킴 웨이브), 5.2(지도 표시),
7장(진행 저장)을 검증한다.
"""

from app.core.timeutil import utcnow
from app.models.expedition import UserStageProgress

from tests.conftest import auth_headers
from tests.integration.test_interactive_expeditions import (
    _action,
    _prepare_stage_two,
    _start,
)


async def _seed_cleared_stages(session_factory, user_id: int, upto: int) -> None:
    """앞 스테이지들을 완주한 상태를 만들어 뒤 스테이지를 연다."""

    now = utcnow()
    async with session_factory() as db:
        for stage_no in range(1, upto + 1):
            db.add(
                UserStageProgress(
                    user_id=user_id,
                    region_code="moss_archive",
                    stage_no=stage_no,
                    cleared_at=now,
                    clear_count=1,
                    updated_at=now,
                )
            )
        await db.commit()


async def _run_stage_to_completion(client, headers: dict, run: dict, key_prefix: str):
    """보행 필드부터 전투 승리와 현장 귀환까지 끝낸다."""

    run, _ = await _fight_stage_battle(client, headers, run, f"{key_prefix}-fight")
    return await _action(client, headers, run, "extract", {}, f"{key_prefix}-extract")


async def _enter_stage_field(client, headers: dict, run: dict, key: str) -> dict:
    """입구에서 실제 목적 랜드마크까지 걸어 사건을 연다."""

    if run.get("current_event") is not None or run["run"]["objective_secured"]:
        return run
    assert run["run"]["phase"] == "exploring"
    assert run["run"]["current_node_code"] == "stage_entry"
    assert run["map"]["edges"] == [["stage_entry", "stage_den"]]
    assert {node["code"] for node in run["map"]["nodes"]} == {
        "stage_entry",
        "stage_den",
    }
    assert run["memory"]["stage_field"]["destination_hint"]
    assert {action["type"] for action in run["available_actions"]} >= {"move"}
    return await _action(
        client,
        headers,
        run,
        "move",
        {"node_code": "stage_den"},
        key,
    )


async def _fight_stage_battle(client, headers: dict, run: dict, key_prefix: str):
    """일반 웨이브는 기본 공격, 수호전은 공개된 최적 합법 스킬로 진행한다."""

    run = await _enter_stage_field(
        client, headers, run, f"{key_prefix}-field-arrival"
    )
    turn = 1
    exchanges: list[dict] = []
    while (run.get("current_event") or {}).get("battle", {}).get("status") == "active":
        battle = run["current_event"]["battle"]
        focus = battle["focus"]
        commands = []
        for member in battle["party"]:
            if member["hp"] <= 0:
                continue
            action = "attack"
            if battle["enemy_kind"] == "guardian":
                skills = [
                    *member["kit"].get("unique_skills", []),
                    *member["kit"].get("selected_skills", []),
                ]
                usable = [
                    skill
                    for skill in skills
                    if skill.get("available", True)
                    and int(skill.get("cooldown_remaining", 0)) == 0
                    and int(skill.get("focus_cost", 0)) <= focus
                ]
                if usable:
                    chosen = max(
                        usable,
                        key=lambda skill: (
                            skill.get("matchup") == "weak",
                            int(skill.get("power", 0)),
                            -int(skill.get("focus_cost", 0)),
                        ),
                    )
                    action = chosen["slot"]
                    focus -= int(chosen.get("focus_cost", 0))
            if action == "attack":
                focus = min(
                    battle["max_focus"],
                    focus + int(member["kit"]["basic"].get("focus_delta", 1)),
                )
            commands.append({"member_id": member["member_id"], "action": action})
        run = await _action(
            client,
            headers,
            run,
            "combat/turns",
            {"commands": commands},
            f"{key_prefix}-{turn:04d}",
        )
        exchanges.extend(run["last_combat_exchange"])
        turn += 1
        assert turn <= 20
    return run, exchanges


async def _stage_map(client, headers: dict) -> dict:
    response = await client.get("/adventure/stages", headers=headers)
    assert response.status_code == 200, response.text
    return response.json()


async def test_stage_map_starts_with_only_the_first_point_open(
    client, user_tokens, session_factory
):
    headers = auth_headers(user_tokens)
    await _prepare_stage_two(session_factory, user_tokens["user"]["id"])

    payload = await _stage_map(client, headers)

    assert payload["region"]["short_name"] == "기억서고"
    assert payload["progress"] == {
        "cleared_count": 0,
        "total": 8,
        "next_stage_no": 1,
        "region_cleared": False,
    }
    assert payload["active_run"] is None

    stages = payload["stages"]
    assert [stage["no"] for stage in stages] == list(range(1, 9))
    assert [stage["kind"] for stage in stages] == [
        "battle",
        "event",
        "battle",
        "battle",
        "camp",
        "event",
        "battle",
        "boss",
    ]
    assert stages[0]["label"] == "기억서고 1"
    assert stages[0]["unlocked"] is True
    assert stages[0]["lock_reason"] is None
    assert stages[0]["tangles"][0]["name"] == "엉킨 장부 뭉치"
    # 큰 엉킴은 같은 전투 아이콘을 쓰되 중간 보스라는 표식만 더 붙는다.
    assert stages[3]["elite"] is True
    assert stages[7]["kind_label"] == "수호전"

    for stage in stages[1:]:
        assert stage["unlocked"] is False
        assert stage["lock_reason"]
        assert stage["cleared"] is False


async def test_locked_stage_cannot_be_started(client, user_tokens, session_factory):
    headers = auth_headers(user_tokens)
    plant_id = await _prepare_stage_two(session_factory, user_tokens["user"]["id"])

    response = await client.post(
        "/adventure/expeditions",
        headers={**headers, "Idempotency-Key": "stage-locked-0001"},
        json={
            "region_code": "moss_archive",
            "mode": "free_explore",
            "plant_ids": [plant_id],
            "guide_count": 1,
            "stage_no": 3,
        },
    )
    assert response.status_code == 409
    assert response.json()["code"] == "EXPEDITION_STAGE_LOCKED"


async def test_clearing_a_stage_opens_the_next_point(
    client, user_tokens, session_factory
):
    headers = auth_headers(user_tokens)
    plant_id = await _prepare_stage_two(session_factory, user_tokens["user"]["id"])

    run = await _start(
        client, headers, plant_id, mode="free_explore", stage_no=1, key="stage-run-0001"
    )
    assert run["run"]["stage_no"] == 1

    during = await _stage_map(client, headers)
    assert during["active_run"] == {"run_id": run["run"]["id"], "stage_no": 1}

    completed = await _run_stage_to_completion(client, headers, run, "stage-run")
    assert completed["summary"]["progress"]["stage"] == {
        "stage_no": 1,
        "first_clear": True,
        "cleared_count": 1,
        "total": 8,
        "region_cleared": False,
    }

    payload = await _stage_map(client, headers)
    assert payload["progress"]["cleared_count"] == 1
    assert payload["progress"]["next_stage_no"] == 2
    assert payload["stages"][0]["cleared"] is True
    assert payload["stages"][0]["clear_count"] == 1
    assert payload["stages"][0]["cleared_at"]
    # 다음 점이 열리고, 그다음은 여전히 잠겨 있다.
    assert payload["stages"][1]["unlocked"] is True
    assert payload["stages"][2]["unlocked"] is False


async def test_story_seen_is_recorded_only_for_cleared_stages(
    client, user_tokens, session_factory
):
    headers = auth_headers(user_tokens)
    plant_id = await _prepare_stage_two(session_factory, user_tokens["user"]["id"])

    # 아직 완주하지 않은 스테이지는 조용히 무시한다. 이야기를 못 본 것은 잘못이 아니다.
    before_clear = await client.post(
        "/adventure/stages/moss_archive/1/story-seen", headers=headers
    )
    assert before_clear.status_code == 200
    assert before_clear.json() == {"stage_no": 1, "story_seen": False}

    run = await _start(
        client,
        headers,
        plant_id,
        mode="free_explore",
        stage_no=1,
        key="stage-story-0001",
    )
    await _run_stage_to_completion(client, headers, run, "stage-story")

    seen = await client.post(
        "/adventure/stages/moss_archive/1/story-seen", headers=headers
    )
    assert seen.status_code == 200
    assert seen.json() == {"stage_no": 1, "story_seen": True}

    payload = await _stage_map(client, headers)
    assert payload["stages"][0]["story_seen"] is True

    missing = await client.post(
        "/adventure/stages/moss_archive/9/story-seen", headers=headers
    )
    assert missing.status_code == 404


async def test_battle_stage_walks_to_the_tangle_fight(
    client, user_tokens, session_factory
):
    headers = auth_headers(user_tokens)
    plant_id = await _prepare_stage_two(session_factory, user_tokens["user"]["id"])

    run = await _start(
        client,
        headers,
        plant_id,
        mode="free_explore",
        stage_no=1,
        key="stage-arena-0001",
    )
    # 모든 스테이지는 지역 원화의 들머리에서 시작해 목적지까지 직접 걷는다.
    assert run["run"]["phase"] == "exploring"
    assert run["current_event"] is None
    assert run["map"]["code"] == "stage_field_1"
    assert run["memory"]["stage_field"]["title"] == "서가 앞 첫 걸음"
    run = await _enter_stage_field(
        client, headers, run, "stage-arena-field-arrival"
    )
    battle = run["current_event"]["battle"]
    assert battle["enemy_kind"] == "tangle"
    assert battle["enemy"]["name"] == "엉킨 장부 뭉치"
    assert battle["wave"] == {
        "index": 1,
        "count": 1,
        "code": "tangled_ledger",
        "name": "엉킨 장부 뭉치",
    }
    assert battle["max_rounds"] == 4
    assert {action["type"] for action in run["available_actions"]} == {
        "combat_turn",
        "retreat",
    }

    run, _ = await _fight_stage_battle(client, headers, run, "stage-arena-fight")
    # 승리가 곧 목표 확보이고, 출구 없이 그 자리에서 귀환한다.
    assert run["run"]["objective_secured"] is True
    assert {action["type"] for action in run["available_actions"]} >= {"extract"}
    outcome = next(
        event for event in run["last_combat_exchange"] if event["type"] == "outcome"
    )
    assert outcome["caption"] == "엉킨 장부가 스르르 풀려 제자리 서가로 돌아갔어요."

    completed = await _action(
        client, headers, run, "extract", {}, "stage-arena-extract"
    )
    assert completed["run"]["status"] == "completed"
    assert completed["summary"]["progress"]["stage"] == {
        "stage_no": 1,
        "first_clear": True,
        "cleared_count": 1,
        "total": 8,
        "region_cleared": False,
    }


async def test_wave_stage_swaps_tangles_without_extra_rounds(
    client, user_tokens, session_factory
):
    headers = auth_headers(user_tokens)
    user_id = user_tokens["user"]["id"]
    plant_id = await _prepare_stage_two(session_factory, user_id)
    await _seed_cleared_stages(session_factory, user_id, upto=2)

    run = await _start(
        client,
        headers,
        plant_id,
        mode="free_explore",
        stage_no=3,
        key="stage-wave-0001",
    )
    run = await _enter_stage_field(client, headers, run, "stage-wave-field")
    battle = run["current_event"]["battle"]
    assert battle["wave"] == {
        "index": 1,
        "count": 2,
        "code": "tangled_ledger",
        "name": "엉킨 장부 뭉치",
    }
    assert battle["max_rounds"] == 8

    run, exchanges = await _fight_stage_battle(client, headers, run, "stage-wave-fight")
    types = [event["type"] for event in exchanges]
    # 첫 엉킴이 풀린 라운드는 거기서 끝나고 다음 웨이브가 등장한다.
    assert "wave_cleared" in types
    intro = next(event for event in exchanges if event["type"] == "wave_intro")
    assert intro["enemy_name"] == "표류 압화 떼"
    assert run["run"]["objective_secured"] is True

    completed = await _action(client, headers, run, "extract", {}, "stage-wave-extract")
    assert completed["summary"]["progress"]["stage"]["stage_no"] == 3


async def test_boss_stage_runs_the_guardian_in_the_arena(
    client, user_tokens, session_factory
):
    headers = auth_headers(user_tokens)
    user_id = user_tokens["user"]["id"]
    plant_id = await _prepare_stage_two(session_factory, user_id)
    await _seed_cleared_stages(session_factory, user_id, upto=7)

    run = await _start(
        client,
        headers,
        plant_id,
        mode="free_explore",
        stage_no=8,
        key="stage-boss-0001",
    )
    run = await _enter_stage_field(client, headers, run, "stage-boss-field")
    battle = run["current_event"]["battle"]
    # 보스 스테이지는 기존 수호전 사건을 그대로 아레나에서 치른다.
    assert battle["enemy_kind"] == "guardian"
    assert battle["enemy"]["name"] == "돌비늘 장부지기"
    assert battle["wave"] is None

    run, exchanges = await _fight_stage_battle(client, headers, run, "stage-boss-fight")
    assert any(event.get("action") in {"unique_1", "unique_2"} for event in exchanges)
    assert run["run"]["objective_secured"] is True
    completed = await _action(client, headers, run, "extract", {}, "stage-boss-extract")
    stage_result = completed["summary"]["progress"]["stage"]
    assert stage_result["stage_no"] == 8
    assert stage_result["region_cleared"] is True

    # 지역을 다 걸으면 지도는 다음 지역으로 넘어간다. 완주 화면에 갇히면
    # 두 번째 지역으로 갈 길이 앱 어디에도 없다.
    map_response = await client.get("/adventure/stages", headers=headers)
    payload = map_response.json()
    assert payload["region"]["code"] == "echo_well"
    assert payload["progress"]["next_stage_no"] == 1
    unlocked = {item["code"] for item in payload["regions"] if item["unlocked"]}
    assert unlocked == {"moss_archive", "echo_well"}

    # 지나온 지역도 골라서 다시 걸을 수 있고, 그쪽은 완주로 남는다.
    revisit = await client.get(
        "/adventure/stages", headers=headers, params={"region_code": "moss_archive"}
    )
    revisited = revisit.json()
    assert revisited["progress"]["region_cleared"] is True
    assert revisited["progress"]["next_stage_no"] is None

    # 아직 안 열린 지역은 골라도 막는다.
    locked = await client.get(
        "/adventure/stages",
        headers=headers,
        params={"region_code": "heartwood_observatory"},
    )
    assert locked.status_code == 403
    assert locked.json()["code"] == "EXPEDITION_REGION_LOCKED"


async def test_event_stage_walks_to_the_pack_event(
    client, user_tokens, session_factory
):
    headers = auth_headers(user_tokens)
    user_id = user_tokens["user"]["id"]
    plant_id = await _prepare_stage_two(session_factory, user_id)
    await _seed_cleared_stages(session_factory, user_id, upto=1)

    run = await _start(
        client,
        headers,
        plant_id,
        mode="free_explore",
        stage_no=2,
        key="stage-event-0001",
    )
    # 사건도 먼저 현장까지 걸은 뒤에만 선택이 열린다.
    assert run["run"]["phase"] == "exploring"
    assert run["current_event"] is None
    run = await _enter_stage_field(client, headers, run, "stage-event-field")
    assert run["run"]["phase"] == "awaiting_event"
    event = run["current_event"]
    assert event["code"] == "wet_label_order"
    assert len(event["choices"]) == 3
    den = next(node for node in run["map"]["nodes"] if node["code"] == "stage_den")
    assert den["scene_key"] == "flooded_cave"
    assert {action["type"] for action in run["available_actions"]} >= {"choice"}

    # 판정 선택으로 사건을 매듭짓는다. 어떤 결과여도 걸음은 완성된다.
    actor = run["party"][0]["id"]
    resolved = await _action(
        client,
        headers,
        run,
        "choices",
        {"choice_code": "trace_ink", "acting_member_id": actor},
        "stage-event-choice",
    )
    assert resolved["run"]["objective_secured"] is True
    assert resolved["last_resolution"]["event_code"] == "wet_label_order"
    assert {action["type"] for action in resolved["available_actions"]} >= {"extract"}

    completed = await _action(
        client, headers, resolved, "extract", {}, "stage-event-extract"
    )
    assert completed["summary"]["progress"]["stage"]["stage_no"] == 2


async def test_camp_stage_walks_to_the_fire_before_resting(
    client, user_tokens, session_factory
):
    headers = auth_headers(user_tokens)
    user_id = user_tokens["user"]["id"]
    plant_id = await _prepare_stage_two(session_factory, user_id)
    await _seed_cleared_stages(session_factory, user_id, upto=4)

    run = await _start(
        client,
        headers,
        plant_id,
        mode="free_explore",
        stage_no=5,
        key="stage-camp-0001",
    )
    # 쉼터도 들머리에서는 아직 완료되지 않고, 불가에 걸어가야 휴식한다.
    assert run["run"]["phase"] == "exploring"
    assert run["run"]["objective_secured"] is False
    assert run["current_event"] is None
    run = await _enter_stage_field(client, headers, run, "stage-camp-field")
    assert run["run"]["objective_secured"] is True
    den = next(node for node in run["map"]["nodes"] if node["code"] == "stage_den")
    assert den["type"] == "camp"
    assert den["status"] == "resolved"
    assert {action["type"] for action in run["available_actions"]} >= {"extract"}

    completed = await _action(client, headers, run, "extract", {}, "stage-camp-extract")
    stage_result = completed["summary"]["progress"]["stage"]
    assert stage_result["stage_no"] == 5
    assert stage_result["first_clear"] is True


async def test_replaying_a_cleared_stage_counts_without_new_rewards(
    client, user_tokens, session_factory
):
    headers = auth_headers(user_tokens)
    plant_id = await _prepare_stage_two(session_factory, user_tokens["user"]["id"])

    first = await _start(
        client,
        headers,
        plant_id,
        mode="free_explore",
        stage_no=1,
        key="stage-replay-0001",
    )
    completed = await _run_stage_to_completion(client, headers, first, "stage-replay-a")
    # 자유 탐험은 원래 경제 보상이 없다. 재도전이 보상을 만들지 않는지 함께 본다.
    assert completed["summary"]["reward"] is None

    second = await _start(
        client,
        headers,
        plant_id,
        mode="free_explore",
        stage_no=1,
        key="stage-replay-0002",
    )
    replayed = await _run_stage_to_completion(client, headers, second, "stage-replay-b")
    assert replayed["summary"]["progress"]["stage"] == {
        "stage_no": 1,
        "first_clear": False,
        "cleared_count": 1,
        "total": 8,
        "region_cleared": False,
    }
    assert replayed["summary"]["reward"] is None

    payload = await _stage_map(client, headers)
    assert payload["stages"][0]["clear_count"] == 2
    assert payload["progress"]["cleared_count"] == 1
