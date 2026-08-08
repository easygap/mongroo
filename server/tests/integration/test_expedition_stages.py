"""스테이지 지도와 모험 허브가 읽는 진행 계약.

개편 설계서 3.1(8스테이지 구성), 5.2(지도 표시), 7장(진행 저장)을 검증한다.
"""

from tests.conftest import auth_headers
from tests.integration.test_interactive_expeditions import (
    _complete_run,
    _prepare_stage_two,
    _start,
)


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

    completed = await _complete_run(client, headers, run)
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
    await _complete_run(client, headers, run)

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
    completed = await _complete_run(client, headers, first)
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
    replayed = await _complete_run(client, headers, second)
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
