import pytest
import sqlalchemy as sa

from app.models.expedition import ExpeditionPartyMember, ExpeditionRun, ExpeditionLoot
from tests.conftest import auth_headers
from tests.integration.test_interactive_expeditions import (
    _prepare_stage_two,
    _start,
    _action,
)
from tests.integration.test_expedition_stages import (
    _seed_cleared_stages,
    _enter_stage_field,
)


@pytest.mark.parametrize(
    "code,finding,light_gain,field_loot",
    [
        ("trace_ink", "주소 조각", 0, True),
        ("sort_slowly", None, 2, False),
        ("mark_return", None, 0, False),
    ],
)
async def test_decisions_have_distinct_persisted_results_and_replay_once(
    client, user_tokens, session_factory, code, finding, light_gain, field_loot
):
    uid = user_tokens["user"]["id"]
    headers = auth_headers(user_tokens)
    plant_id = await _prepare_stage_two(session_factory, uid)
    await _seed_cleared_stages(session_factory, uid, 1)
    run = await _start(client, headers, plant_id, mode="free_explore", stage_no=2)
    actor_id = run["party"][0]["id"]
    async with session_factory() as db:
        actor = await db.get(ExpeditionPartyMember, actor_id)
        actor.snapshot = {
            **actor.snapshot,
            "stats": {key: 7 for key in actor.snapshot["stats"]},
        }
        saved = await db.get(ExpeditionRun, run["run"]["id"])
        saved.trail_light = 7
        await db.commit()
    run = await _enter_stage_field(client, headers, run, "walk-to-decision")
    choice = next(
        item for item in run["current_event"]["choices"] if item["code"] == code
    )
    preview = next(item for item in choice["previews"] if item["member_id"] == actor_id)
    assert preview["success_chance"] == 100
    assert choice["consequence"]
    payload = {"choice_code": code, "acting_member_id": actor_id}
    result = await _action(client, headers, run, "choices", payload, "decision-once")
    replay = await _action(client, headers, run, "choices", payload, "decision-once")
    assert replay == result
    assert result["run"]["trail_light"] == run["run"]["trail_light"] + light_gain
    assert result["last_resolution"]["finding"] == finding
    assert result["last_resolution"]["result_text"]
    assert result["memory"]["outcomes"][-1]["finding"] == finding
    async with session_factory() as db:
        count = await db.scalar(
            sa.select(sa.func.count())
            .select_from(ExpeditionLoot)
            .where(
                ExpeditionLoot.run_id == run["run"]["id"],
                ExpeditionLoot.loot_kind == "field",
            )
        )
    assert bool(count) is field_loot
