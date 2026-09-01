"""장거리 개척이 HTTP 위에서 실제로 도는지 본다.

구간 안에서 걷고 싸우는 것은 이미 `test_interactive_expeditions.py`가 본다.
여기서 지키는 것은 **구간을 묶는 규칙**이다 — 해금, 한 캐릭터 한 구간, 길잡이만
있는 편성, 야영 중에도 잠기는 활성 슬롯, 그리고 보상이 마지막에 한 번뿐인 것.
"""

import uuid

import sqlalchemy as sa

from app.core.timeutil import utcnow
from app.models.expedition import (
    ExpeditionJourney,
    ExpeditionLoot,
    ExpeditionRun,
    UserStageProgress,
)
from app.models.plant import Plant, PlantSpecies
from app.models.reward import RewardEvent

from tests.conftest import auth_headers


STAGE_COUNT = 8


async def _clear_regions(session_factory, user_id: int, *region_codes: str) -> None:
    """그 지역들을 완주한 상태로 만든다."""
    async with session_factory() as db:
        for region_code in region_codes:
            for stage_no in range(1, STAGE_COUNT + 1):
                db.add(
                    UserStageProgress(
                        user_id=user_id,
                        region_code=region_code,
                        stage_no=stage_no,
                        cleared_at=utcnow(),
                        clear_count=1,
                        updated_at=utcnow(),
                    )
                )
        await db.commit()


async def _ready_plants(session_factory, user_id: int, count: int) -> list[int]:
    """탐험할 수 있는 캐릭터를 `count`명 만든다.

    `active` 화분은 사용자당 하나뿐이라 나머지는 수확한 캐릭터로 만든다.
    수확한 캐릭터도 편성에 설 수 있다.
    """
    async with session_factory() as db:
        first = await db.scalar(sa.select(Plant).where(Plant.user_id == user_id))
        first.exp = 450
        species = await db.scalar(sa.select(PlantSpecies).limit(1))
        ids = [first.id]
        for index in range(count - 1):
            extra = Plant(
                user_id=user_id,
                species_id=species.id,
                name=f"동행{index}",
                exp=450,
                status="harvested",
                planted_at=first.planted_at,
            )
            db.add(extra)
            await db.flush()
            ids.append(extra.id)
        await db.commit()
        return ids


async def _start_journey(client, headers, direction="beyond_the_well", mode="free_explore"):
    return await client.post(
        "/adventure/journeys",
        headers={**headers, "Idempotency-Key": uuid.uuid4().hex},
        json={"direction_code": direction, "mode": mode},
    )


async def _create_leg(client, headers, journey, route_code, plant_ids, key=None):
    return await client.post(
        f"/adventure/journeys/{journey['id']}/legs",
        headers={**headers, "Idempotency-Key": key or uuid.uuid4().hex},
        json={
            "route_choice_code": route_code,
            "plant_ids": plant_ids,
            "guide_count": 2 - len(plant_ids),
            "expected_revision": journey["revision"],
        },
    )


async def _secure(session_factory, run_id: int) -> None:
    """구간의 목표를 확보하고 귀환 지점에 세운다.

    지도를 실제로 걷는 것은 다른 검사가 본다. 여기서 필요한 것은 `구간이
    목표를 안고 끝났다`는 상태뿐이다.
    """
    async with session_factory() as db:
        run = await db.get(ExpeditionRun, run_id)
        run.objective_secured = True
        run.current_node_code = run.map_snapshot["entrance"]
        await db.commit()


async def _extract(client, headers, run_id: int, revision: int):
    return await client.post(
        f"/adventure/expeditions/{run_id}/extract",
        headers=headers,
        json={
            "expected_revision": revision,
            "client_action_id": uuid.uuid4().hex,
        },
    )


async def _run_revision(client, headers, run_id: int) -> int:
    response = await client.get(f"/adventure/expeditions/{run_id}", headers=headers)
    assert response.status_code == 200, response.text
    return response.json()["run"]["revision"]


async def _finish_leg(client, headers, session_factory, run_id: int) -> dict:
    await _secure(session_factory, run_id)
    revision = await _run_revision(client, headers, run_id)
    response = await _extract(client, headers, run_id, revision)
    assert response.status_code == 200, response.text
    return response.json()


async def _journey(client, headers) -> dict | None:
    response = await client.get("/adventure/journeys/active", headers=headers)
    assert response.status_code == 200, response.text
    return response.json()


async def test_direction_is_locked_until_its_region_is_finished(
    client, user_tokens, session_factory
):
    headers = auth_headers(user_tokens)
    entry = (await client.get("/adventure/journeys", headers=headers)).json()
    assert entry["unlocked"] is False
    assert [row["locked"] for row in entry["directions"]] == [True, True, True]
    assert entry["directions"][0]["lock_reason"]

    response = await _start_journey(client, headers)
    assert response.status_code == 409
    assert response.json()["code"] == "JOURNEY_DIRECTION_LOCKED"

    await _clear_regions(session_factory, user_tokens["user"]["id"], "echo_well")
    entry = (await client.get("/adventure/journeys", headers=headers)).json()
    assert entry["unlocked"] is True
    first = entry["directions"][0]
    assert first["locked"] is False
    assert first["max_legs"] == 2
    assert first["party_size"] == 2
    assert first["max_own_members"] == 4


async def test_a_character_walks_only_one_leg_of_the_same_journey(
    client, user_tokens, session_factory
):
    user_id = user_tokens["user"]["id"]
    headers = auth_headers(user_tokens)
    await _clear_regions(session_factory, user_id, "moss_archive", "echo_well")
    plant_ids = await _ready_plants(session_factory, user_id, 3)

    journey = (await _start_journey(client, headers)).json()
    assert journey["current_leg_index"] == 0
    assert [route["code"] for route in journey["next_routes"]] == [
        "well_mouth",
        "mossy_stair",
    ]

    created = await _create_leg(client, headers, journey, "well_mouth", plant_ids[:2])
    assert created.status_code == 201, created.text
    body = created.json()
    assert body["journey"]["used_plant_ids"] == sorted(plant_ids[:2])
    # 구간은 평범한 탐험 run이다. 부모만 매달려 있다.
    run_id = body["expedition"]["run"]["id"]
    async with session_factory() as db:
        run = await db.get(ExpeditionRun, run_id)
        assert run.journey_id == body["journey"]["id"]
        assert run.journey_leg_index == 0
        assert run.region_code == "echo_well"
        # 구간 하나하나에는 보상 자격이 없다. 지급은 귀환에서 한 번뿐이다.
        assert run.reward_eligible is False

    await _finish_leg(client, headers, session_factory, run_id)
    journey = await _journey(client, headers)
    assert journey["current_leg_index"] == 1
    assert journey["at_camp"] is True
    assert journey["deepest_secured_region"] == "echo_well"

    # 다녀온 캐릭터를 또 보내면 막힌다. 이게 이 콘텐츠의 존재 이유다.
    repeat = await _create_leg(client, headers, journey, "paper_drift", plant_ids[:1] + plant_ids[2:3])
    assert repeat.status_code == 409
    assert repeat.json()["code"] == "JOURNEY_MEMBER_ALREADY_USED"


async def test_two_guides_can_walk_a_leg_alone(client, user_tokens, session_factory):
    """캐릭터가 하나도 남지 않아도 끝까지 갈 수 있어야 한다(설계서 9.8)."""

    user_id = user_tokens["user"]["id"]
    headers = auth_headers(user_tokens)
    await _clear_regions(session_factory, user_id, "moss_archive", "echo_well")
    await _ready_plants(session_factory, user_id, 1)

    journey = (await _start_journey(client, headers)).json()
    created = await _create_leg(client, headers, journey, "mossy_stair", [])
    assert created.status_code == 201, created.text
    party = created.json()["expedition"]["party"]
    assert len(party) == 2
    assert all(member["is_guide"] for member in party)
    assert created.json()["journey"]["used_plant_ids"] == []


async def test_camp_holds_the_active_slot_so_nothing_else_can_start(
    client, user_tokens, session_factory
):
    user_id = user_tokens["user"]["id"]
    headers = auth_headers(user_tokens)
    await _clear_regions(session_factory, user_id, "moss_archive", "echo_well")
    plant_ids = await _ready_plants(session_factory, user_id, 2)

    journey = (await _start_journey(client, headers)).json()
    # 아직 구간을 하나도 만들지 않았는데도 슬롯은 이미 개척이 잡고 있다.
    blocked = await client.post(
        "/adventure/expeditions",
        headers={**headers, "Idempotency-Key": uuid.uuid4().hex},
        json={
            "region_code": "moss_archive",
            "mode": "free_explore",
            "plant_ids": plant_ids[:1],
            "guide_count": 1,
        },
    )
    assert blocked.status_code == 409
    assert blocked.json()["code"] == "JOURNEY_ALREADY_ACTIVE"

    # 같은 이유로 개척을 두 번 시작할 수도 없다.
    again = await _start_journey(client, headers)
    assert again.status_code == 409
    assert again.json()["code"] == "JOURNEY_ALREADY_ACTIVE"

    created = await _create_leg(client, headers, journey, "well_mouth", plant_ids[:2])
    run_id = created.json()["expedition"]["run"]["id"]
    await _finish_leg(client, headers, session_factory, run_id)

    # 야영 중에도 여전히 잠겨 있다.
    still = await client.post(
        "/adventure/expeditions",
        headers={**headers, "Idempotency-Key": uuid.uuid4().hex},
        json={
            "region_code": "moss_archive",
            "mode": "free_explore",
            "plant_ids": plant_ids[:1],
            "guide_count": 1,
        },
    )
    assert still.status_code == 409
    assert still.json()["code"] == "JOURNEY_ALREADY_ACTIVE"


async def test_reward_lands_once_on_the_deepest_band_at_the_end(
    client, user_tokens, session_factory
):
    """구간마다 합산하지 않고 **가장 먼 확보 지역**의 밴드로 한 번만 준다."""

    user_id = user_tokens["user"]["id"]
    headers = auth_headers(user_tokens)
    await _clear_regions(session_factory, user_id, "moss_archive", "echo_well")
    plant_ids = await _ready_plants(session_factory, user_id, 4)
    # 마음 공명으로 떠나려면 오늘 일기가 있어야 한다. 개척이라고 관문이
    # 느슨해지지 않는 것까지 함께 본다.
    diary = await client.post(
        "/moods",
        headers={**headers, "Idempotency-Key": uuid.uuid4().hex},
        json={"content": "오늘은 멀리까지 걸어 보기로 했다. " * 3},
    )
    assert diary.status_code == 201, diary.text

    journey = (
        await _start_journey(client, headers, mode="heart_resonance")
    ).json()
    assert journey["reward_eligible"] is True

    # 첫 구간은 서고(6/2), 둘째 구간은 우물정원(7/2). 우물정원이 더 멀다.
    created = await _create_leg(client, headers, journey, "mossy_stair", plant_ids[:2])
    await _finish_leg(
        client, headers, session_factory, created.json()["expedition"]["run"]["id"]
    )
    journey = await _journey(client, headers)
    assert journey["deepest_secured_region"] == "moss_archive"

    created = await _create_leg(client, headers, journey, "deeper_water", plant_ids[2:4])
    leg_run_id = created.json()["expedition"]["run"]["id"]
    await _finish_leg(client, headers, session_factory, leg_run_id)
    journey = await _journey(client, headers)
    assert journey["deepest_secured_region"] == "echo_well"
    assert journey["can_continue"] is False  # 두 구간짜리 방향이라 끝이다

    returned = await client.post(
        f"/adventure/journeys/{journey['id']}/return",
        headers={**headers, "Idempotency-Key": uuid.uuid4().hex},
        json={"expected_revision": journey["revision"]},
    )
    assert returned.status_code == 200, returned.text
    body = returned.json()
    assert body["status"] == "completed"
    assert body["summary"]["secured_count"] == 2
    assert body["summary"]["deepest_region_code"] == "echo_well"
    # 우물정원 밴드(7/2)로 한 번. 두 구간을 합산한 13/4이 아니다.
    events = body["summary"]["reward"]["events"]
    assert len(events) == 1
    assert (events[0]["exp_delta"], events[0]["seed_delta"]) == (7, 2)

    async with session_factory() as db:
        events = list(
            (
                await db.execute(
                    sa.select(RewardEvent).where(RewardEvent.user_id == user_id)
                )
            ).scalars()
        )
        # 일기 보상은 따로 있으니 탐험 쪽만 센다. 개척 한 줄뿐이고 구간 run은
        # 하나도 원장에 오르지 않았다.
        assert [
            event.source_type
            for event in events
            if event.source_type.startswith("expedition")
        ] == ["expedition_journey"]

    # 슬롯이 풀려서 이제 일반 탐험을 떠날 수 있다.
    freed = await client.post(
        "/adventure/expeditions",
        headers={**headers, "Idempotency-Key": uuid.uuid4().hex},
        json={
            "region_code": "moss_archive",
            "mode": "free_explore",
            "plant_ids": plant_ids[:1],
            "guide_count": 1,
        },
    )
    assert freed.status_code == 201, freed.text


async def test_retreating_a_leg_ends_the_journey_and_keeps_what_was_secured(
    client, user_tokens, session_factory
):
    user_id = user_tokens["user"]["id"]
    headers = auth_headers(user_tokens)
    await _clear_regions(session_factory, user_id, "moss_archive", "echo_well")
    plant_ids = await _ready_plants(session_factory, user_id, 4)

    journey = (await _start_journey(client, headers)).json()
    created = await _create_leg(client, headers, journey, "well_mouth", plant_ids[:2])
    await _finish_leg(
        client, headers, session_factory, created.json()["expedition"]["run"]["id"]
    )
    journey = await _journey(client, headers)

    created = await _create_leg(client, headers, journey, "paper_drift", plant_ids[2:4])
    run_id = created.json()["expedition"]["run"]["id"]
    revision = await _run_revision(client, headers, run_id)
    retreated = await client.post(
        f"/adventure/expeditions/{run_id}/retreat",
        headers=headers,
        json={"expected_revision": revision, "client_action_id": uuid.uuid4().hex},
    )
    assert retreated.status_code == 200, retreated.text

    assert await _journey(client, headers) is None
    async with session_factory() as db:
        journey_row = await db.scalar(
            sa.select(ExpeditionJourney).where(ExpeditionJourney.user_id == user_id)
        )
        assert journey_row.status == "retreated"
        # 확보한 구간의 기록은 남는다.
        assert journey_row.summary_snapshot["secured_count"] == 1
        assert journey_row.summary_snapshot["reward"] is None
        # 모아 둔 후보는 지급되지 않고 기록으로만 남는다.
        dispositions = {
            row.disposition
            for row in (
                await db.execute(
                    sa.select(ExpeditionLoot).where(
                        ExpeditionLoot.run_id.in_(
                            [entry["run_id"] for entry in journey_row.legs_snapshot]
                        )
                    )
                )
            ).scalars()
        }
        assert "granted" not in dispositions


async def test_writes_are_idempotent_and_guard_stale_revisions(
    client, user_tokens, session_factory
):
    user_id = user_tokens["user"]["id"]
    headers = auth_headers(user_tokens)
    await _clear_regions(session_factory, user_id, "moss_archive", "echo_well")
    plant_ids = await _ready_plants(session_factory, user_id, 2)

    key = uuid.uuid4().hex
    first = await client.post(
        "/adventure/journeys",
        headers={**headers, "Idempotency-Key": key},
        json={"direction_code": "beyond_the_well", "mode": "free_explore"},
    )
    again = await client.post(
        "/adventure/journeys",
        headers={**headers, "Idempotency-Key": key},
        json={"direction_code": "beyond_the_well", "mode": "free_explore"},
    )
    assert first.status_code == 201
    assert again.json() == first.json()

    journey = first.json()
    leg_key = uuid.uuid4().hex
    created = await _create_leg(
        client, headers, journey, "well_mouth", plant_ids[:2], key=leg_key
    )
    replay = await _create_leg(
        client, headers, journey, "well_mouth", plant_ids[:2], key=leg_key
    )
    assert created.status_code == 201, created.text
    assert replay.json() == created.json()

    # 낡은 revision으로는 다음 행동이 통과하지 않는다.
    stale = await _create_leg(client, headers, journey, "mossy_stair", [])
    assert stale.status_code == 409
    assert stale.json()["code"] in {
        "JOURNEY_REVISION_MISMATCH",
        "JOURNEY_LEG_IN_PROGRESS",
    }


async def test_cannot_open_a_new_leg_while_one_is_walking(
    client, user_tokens, session_factory
):
    user_id = user_tokens["user"]["id"]
    headers = auth_headers(user_tokens)
    await _clear_regions(session_factory, user_id, "moss_archive", "echo_well")
    plant_ids = await _ready_plants(session_factory, user_id, 4)

    journey = (await _start_journey(client, headers)).json()
    created = await _create_leg(client, headers, journey, "well_mouth", plant_ids[:2])
    assert created.status_code == 201
    walking = created.json()["journey"]

    blocked = await _create_leg(client, headers, walking, "mossy_stair", plant_ids[2:4])
    assert blocked.status_code == 409
    assert blocked.json()["code"] == "JOURNEY_LEG_IN_PROGRESS"

    # 귀환도 마찬가지다. 걷는 중에는 접을 수 없고 구간을 먼저 끝내야 한다.
    returned = await client.post(
        f"/adventure/journeys/{walking['id']}/return",
        headers={**headers, "Idempotency-Key": uuid.uuid4().hex},
        json={"expected_revision": walking["revision"]},
    )
    assert returned.status_code == 409
    assert returned.json()["code"] == "JOURNEY_LEG_IN_PROGRESS"


async def test_another_user_cannot_touch_someone_elses_journey(
    client, user_tokens, session_factory
):
    from tests.conftest import signup

    user_id = user_tokens["user"]["id"]
    headers = auth_headers(user_tokens)
    await _clear_regions(session_factory, user_id, "moss_archive", "echo_well")
    await _ready_plants(session_factory, user_id, 2)
    journey = (await _start_journey(client, headers)).json()

    other = auth_headers(await signup(client))
    peek = await client.get(f"/adventure/journeys/{journey['id']}", headers=other)
    assert peek.status_code == 404
    stolen = await client.post(
        f"/adventure/journeys/{journey['id']}/return",
        headers={**other, "Idempotency-Key": uuid.uuid4().hex},
        json={"expected_revision": journey["revision"]},
    )
    assert stolen.status_code == 404
