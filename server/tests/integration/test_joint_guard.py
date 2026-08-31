"""합동 수호전이 HTTP 위에서 실제로 도는지 본다.

판의 규칙은 단위 검사가 본다. 여기서 지키는 것은 전송 계약이다 - 해금 관문,
멱등, revision 충돌, 남의 판에 손댈 수 없는 것, 그리고 **응답 어디에도 재화가
없는 것**.
"""

import uuid

import sqlalchemy as sa

from app.core.timeutil import utcnow
from app.models.expedition import UserStageProgress
from app.models.plant import Plant, PlantSpecies

from tests.conftest import auth_headers, signup


async def _unlock_guardian(session_factory, user_id: int) -> None:
    """그 지역 수호짐승의 장벽을 한 번 연 상태로 만든다."""
    async with session_factory() as db:
        db.add(
            UserStageProgress(
                user_id=user_id,
                region_code="moss_archive",
                stage_no=8,
                cleared_at=utcnow(),
                clear_count=1,
                updated_at=utcnow(),
            )
        )
        await db.commit()


async def _two_plants(session_factory, user_id: int) -> list[int]:
    """탐험할 수 있는 캐릭터 둘. 나머지 넷은 길잡이가 채운다.

    한 사용자에게 `active` 화분은 하나뿐이라(부분 유니크 인덱스) 둘째는
    수확한 캐릭터로 만든다. 수확한 캐릭터도 명단에 설 수 있다.
    """
    async with session_factory() as db:
        first = await db.scalar(sa.select(Plant).where(Plant.user_id == user_id))
        first.exp = 450
        species = await db.scalar(sa.select(PlantSpecies).limit(1))
        second = Plant(
            user_id=user_id,
            species_id=species.id,
            name="둘째",
            exp=450,
            status="harvested",
            planted_at=first.planted_at,
        )
        db.add(second)
        await db.commit()
        return [first.id, second.id]


def _formation(plant_ids: list[int]) -> list[dict]:
    slots = [
        {"plant_id": plant_ids[0], "formation": "front"},
        {"plant_id": plant_ids[1], "formation": "front"},
        {"plant_id": None, "formation": "front"},
        {"plant_id": None, "formation": "back"},
        {"plant_id": None, "formation": "back"},
        {"plant_id": None, "formation": "back"},
    ]
    return slots


async def _start(client, headers, plant_ids, difficulty="three_layers", key=None):
    return await client.post(
        "/adventure/joint-guard",
        headers={**headers, "Idempotency-Key": key or uuid.uuid4().hex},
        json={
            "beast_code": "ledger_keeper",
            "difficulty": difficulty,
            "formation": _formation(plant_ids),
        },
    )


async def test_locked_until_the_guardian_has_been_met(client, session_factory):
    """장벽을 한 번도 열지 않았으면 들어갈 수 없다(설계서 3장)."""
    tokens = await signup(client)
    headers = auth_headers(tokens)
    plant_ids = await _two_plants(session_factory, tokens["user"]["id"])

    response = await _start(client, headers, plant_ids)

    assert response.status_code == 422, response.text
    assert response.json()["code"] == "JOINT_GUARD_LOCKED"


async def test_entry_reads_which_beasts_are_open(client, session_factory):
    tokens = await signup(client)
    headers = auth_headers(tokens)
    await _unlock_guardian(session_factory, tokens["user"]["id"])

    body = (await client.get("/adventure/joint-guard", headers=headers)).json()

    assert len(body["beasts"]) == 4
    opened = [beast for beast in body["beasts"] if beast["unlocked"]]
    assert [beast["code"] for beast in opened] == ["ledger_keeper"]
    locked = next(beast for beast in body["beasts"] if not beast["unlocked"])
    assert locked["locked_reason"]
    assert {d["code"] for d in body["difficulties"]} == {"outer_walk", "three_layers"}
    assert body["active_run_id"] is None


async def test_start_puts_six_on_the_field(client, session_factory):
    tokens = await signup(client)
    headers = auth_headers(tokens)
    await _unlock_guardian(session_factory, tokens["user"]["id"])
    plant_ids = await _two_plants(session_factory, tokens["user"]["id"])

    response = await _start(client, headers, plant_ids)

    assert response.status_code == 201, response.text
    body = response.json()["joint_guard"]
    assert body["status"] == "active"
    assert len(body["front"]) == 3
    assert len(body["reserves"]) == 3
    assert body["layer"]["name"] == "겉꿈"
    assert body["layer"]["count"] == 3
    assert body["swaps_left"] == 1


async def test_the_front_line_must_be_three(client, session_factory):
    tokens = await signup(client)
    headers = auth_headers(tokens)
    await _unlock_guardian(session_factory, tokens["user"]["id"])

    # 길잡이만 여섯이어도 편성 자체는 설 수 있다. 여기서 막히는 것은 전열이
    # 셋이 아니라는 점뿐이다.
    response = await client.post(
        "/adventure/joint-guard",
        headers={**headers, "Idempotency-Key": uuid.uuid4().hex},
        json={
            "beast_code": "ledger_keeper",
            "difficulty": "three_layers",
            "formation": [
                {"plant_id": None, "formation": "front"} for _ in range(6)
            ],
        },
    )
    assert response.status_code == 422, response.text


async def test_a_turn_advances_the_revision_and_replays(client, session_factory):
    """같은 행동 키로 다시 보내면 판이 두 번 진행되지 않는다."""
    tokens = await signup(client)
    headers = auth_headers(tokens)
    await _unlock_guardian(session_factory, tokens["user"]["id"])
    plant_ids = await _two_plants(session_factory, tokens["user"]["id"])
    run = (await _start(client, headers, plant_ids)).json()

    member_id = run["joint_guard"]["front"][0]["member_id"]
    payload = {
        "command": {"member_id": member_id, "action": "guard"},
        "expected_revision": run["run"]["revision"],
        "client_action_id": "joint-turn-0001",
    }
    first = await client.post(
        f"/adventure/joint-guard/{run['run']['id']}/turns",
        headers=headers,
        json=payload,
    )
    assert first.status_code == 200, first.text
    assert first.json()["run"]["revision"] == run["run"]["revision"] + 1

    replay = await client.post(
        f"/adventure/joint-guard/{run['run']['id']}/turns",
        headers=headers,
        json=payload,
    )
    assert replay.status_code == 200
    assert replay.json() == first.json()


async def test_a_stale_revision_is_refused(client, session_factory):
    tokens = await signup(client)
    headers = auth_headers(tokens)
    await _unlock_guardian(session_factory, tokens["user"]["id"])
    plant_ids = await _two_plants(session_factory, tokens["user"]["id"])
    run = (await _start(client, headers, plant_ids)).json()
    member_id = run["joint_guard"]["front"][0]["member_id"]

    await client.post(
        f"/adventure/joint-guard/{run['run']['id']}/turns",
        headers=headers,
        json={
            "command": {"member_id": member_id, "action": "guard"},
            "expected_revision": run["run"]["revision"],
            "client_action_id": "joint-turn-0002",
        },
    )
    stale = await client.post(
        f"/adventure/joint-guard/{run['run']['id']}/turns",
        headers=headers,
        json={
            "command": {"member_id": member_id, "action": "guard"},
            "expected_revision": run["run"]["revision"],
            "client_action_id": "joint-turn-0003",
        },
    )
    assert stale.status_code == 409
    assert stale.json()["code"] == "EXPEDITION_REVISION_CONFLICT"


async def test_swapping_is_once_a_round(client, session_factory):
    tokens = await signup(client)
    headers = auth_headers(tokens)
    await _unlock_guardian(session_factory, tokens["user"]["id"])
    plant_ids = await _two_plants(session_factory, tokens["user"]["id"])
    run = (await _start(client, headers, plant_ids)).json()
    front = run["joint_guard"]["front"]
    reserves = run["joint_guard"]["reserves"]

    first = await client.post(
        f"/adventure/joint-guard/{run['run']['id']}/swap",
        headers=headers,
        json={
            "out_member_id": front[0]["member_id"],
            "in_member_id": reserves[0]["member_id"],
            "expected_revision": run["run"]["revision"],
            "client_action_id": "joint-swap-0001",
        },
    )
    assert first.status_code == 200, first.text
    assert first.json()["joint_guard"]["swaps_left"] == 0

    second = await client.post(
        f"/adventure/joint-guard/{run['run']['id']}/swap",
        headers=headers,
        json={
            "out_member_id": front[1]["member_id"],
            "in_member_id": reserves[1]["member_id"],
            "expected_revision": first.json()["run"]["revision"],
            "client_action_id": "joint-swap-0002",
        },
    )
    assert second.status_code == 422
    assert second.json()["code"] == "JOINT_SWAP_LIMIT"


async def test_active_reads_the_run_and_blocks_a_second_one(client, session_factory):
    tokens = await signup(client)
    headers = auth_headers(tokens)
    await _unlock_guardian(session_factory, tokens["user"]["id"])
    plant_ids = await _two_plants(session_factory, tokens["user"]["id"])
    run = (await _start(client, headers, plant_ids)).json()

    active = (await client.get("/adventure/joint-guard/active", headers=headers)).json()
    assert active["run"]["id"] == run["run"]["id"]

    again = await _start(client, headers, plant_ids)
    assert again.status_code == 409
    assert again.json()["code"] == "JOINT_GUARD_ALREADY_ACTIVE"


async def test_another_user_cannot_touch_the_run(client, session_factory):
    owner = await signup(client)
    owner_headers = auth_headers(owner)
    await _unlock_guardian(session_factory, owner["user"]["id"])
    plant_ids = await _two_plants(session_factory, owner["user"]["id"])
    run = (await _start(client, owner_headers, plant_ids)).json()

    stranger = await signup(client)
    response = await client.post(
        f"/adventure/joint-guard/{run['run']['id']}/turns",
        headers=auth_headers(stranger),
        json={
            "command": {"member_id": run["joint_guard"]["front"][0]["member_id"], "action": "guard"},
            "expected_revision": run["run"]["revision"],
            "client_action_id": "joint-turn-0009",
        },
    )
    assert response.status_code == 404


async def test_the_response_carries_no_currency(client, session_factory):
    """경제 보상 0이 전송 계약에서도 지켜진다(설계서 6장)."""
    tokens = await signup(client)
    headers = auth_headers(tokens)
    await _unlock_guardian(session_factory, tokens["user"]["id"])
    plant_ids = await _two_plants(session_factory, tokens["user"]["id"])
    body = (await _start(client, headers, plant_ids)).json()

    banned = {"exp", "xp", "seeds", "seed_balance", "reward", "rewards", "currency"}

    def walk(node, path=""):
        if isinstance(node, dict):
            for key, value in node.items():
                assert key not in banned, f"{path}.{key}"
                walk(value, f"{path}.{key}")
        elif isinstance(node, list):
            for index, value in enumerate(node):
                walk(value, f"{path}[{index}]")

    walk(body)


async def test_a_turn_survives_the_next_request(client, session_factory):
    """고친 판이 실제로 저장되는지 본다.

    처음엔 저장된 상태를 그 자리에서 고쳤는데, 그러면 SQLAlchemy가 보는
    `이전 값`이 방금 고친 그 객체라 달라진 게 없다고 판단해 아무것도 쓰지
    않는다. 응답에는 반영되는데 다음 요청에서 사라지는, 한 요청 안에서는
    절대 안 보이는 종류의 버그다.
    """
    tokens = await signup(client)
    headers = auth_headers(tokens)
    await _unlock_guardian(session_factory, tokens["user"]["id"])
    plant_ids = await _two_plants(session_factory, tokens["user"]["id"])
    run = (await _start(client, headers, plant_ids)).json()

    turned = await client.post(
        f"/adventure/joint-guard/{run['run']['id']}/turns",
        headers=headers,
        json={
            "command": {
                "member_id": run["joint_guard"]["front"][0]["member_id"],
                "action": "guard",
            },
            "expected_revision": run["run"]["revision"],
            "client_action_id": "joint-persist-0001",
        },
    )
    assert turned.status_code == 200, turned.text

    reloaded = (
        await client.get("/adventure/joint-guard/active", headers=headers)
    ).json()
    assert reloaded["run"]["revision"] == turned.json()["run"]["revision"]
    assert (
        reloaded["joint_guard"]["battle"]["party"]
        == turned.json()["joint_guard"]["battle"]["party"]
    )
