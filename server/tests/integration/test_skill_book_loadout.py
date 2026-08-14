"""기록서 소유·장착의 저장과 API 계약.

설계서 11.4·11.5와 실행 계약 4.4를 실제 저장소 위에서 확인한다. 핵심은
**소유와 장착이 서로 다른 축**이라는 것이다. 보유해도 자동 장착되지 않고,
장착은 캐릭터·프리셋마다 따로 남는다.
"""

import pytest
import sqlalchemy as sa

from app.api.errors import AppError
from app.models.plant import Plant
from app.services import skill_books as service
from tests.conftest import auth_headers


async def _plant_id(client, tokens) -> int:
    res = await client.get("/plants/me", headers=auth_headers(tokens))
    assert res.status_code == 200, res.text
    return int(res.json()["plant"]["id"])


async def _grow_to(session_factory, plant_id: int, exp: int) -> None:
    """슬롯 해금 레벨까지 캐릭터를 키운다. 레벨은 누적 EXP에서 파생된다."""

    async with session_factory() as db:
        plant = await db.scalar(sa.select(Plant).where(Plant.id == plant_id))
        plant.exp = exp
        await db.commit()


async def _grant(session_factory, user_id: int, *codes: str) -> None:
    async with session_factory() as db:
        for code in codes:
            await service.grant_skill_book(
                db, user_id=user_id, code=code, acquire_source="shop"
            )
        await db.commit()


async def test_library_lists_the_whole_catalog_with_owned_flags(client, user_tokens):
    """획득 경로를 사전 공개한다. 아직 없는 책도 어디서 얻는지 보여 준다."""

    res = await client.get("/skill-books", headers=auth_headers(user_tokens))
    assert res.status_code == 200, res.text
    body = res.json()
    assert len(body["catalog"]) == 20
    assert body["owned"] == []
    assert all(entry["owned"] is False for entry in body["catalog"])
    # 3등급은 구매할 수 없고 반대급부를 함께 보여 준다.
    grade_three = [item for item in body["catalog"] if item["grade"] == 3]
    assert grade_three and all(item["price_seeds"] is None for item in grade_three)
    assert all(item["tradeoff"] for item in grade_three)
    assert body["presets"] == ["explore", "guard", "personal"]


async def test_owning_a_book_does_not_equip_it(
    client, user_tokens, session_factory
):
    """보유는 장착이 아니다. 획득해도 슬롯은 안전 기본값 그대로다."""

    plant_id = await _plant_id(client, user_tokens)
    await _grow_to(session_factory, plant_id, 100000)
    await _grant(session_factory, user_tokens["user"]["id"], "clear_aim")

    res = await client.get("/skill-books", headers=auth_headers(user_tokens))
    assert [entry["code"] for entry in res.json()["owned"]] == ["clear_aim"]

    loadout = await client.get(
        f"/skill-books/loadouts/{plant_id}", headers=auth_headers(user_tokens)
    )
    assert loadout.status_code == 200, loadout.text
    body = loadout.json()
    assert body["revision"] == 0
    assert body["stored"] == {"slot_b1_code": None, "slot_b2_code": None}
    # 저장한 것이 없으면 안전 기본값으로 읽힌다.
    assert body["resolved"]["B1"]["code"] == "emotion.primary"
    assert body["resolved"]["B2"]["code"] == "field_note_echo"
    assert body["resolved"]["B1"]["fell_back"] is False


async def test_saving_a_loadout_persists_and_bumps_revision(
    client, user_tokens, session_factory
):
    plant_id = await _plant_id(client, user_tokens)
    await _grow_to(session_factory, plant_id, 100000)
    await _grant(session_factory, user_tokens["user"]["id"], "clear_aim", "short_cheer")

    res = await client.put(
        f"/skill-books/loadouts/{plant_id}",
        headers=auth_headers(user_tokens),
        json={
            "preset_code": "guard",
            "slot_b1_code": "clear_aim",
            "slot_b2_code": "short_cheer",
            "expected_revision": 0,
        },
    )
    assert res.status_code == 200, res.text
    body = res.json()
    assert body["revision"] == 1
    assert body["resolved"]["B1"]["code"] == "clear_aim"
    # opening·trigger는 대원 행동을 소비하지 않으므로 누를 수 없는 자리다.
    assert body["resolved"]["B1"]["locked"] is True
    assert body["resolved"]["B2"]["code"] == "short_cheer"
    assert body["resolved"]["B2"]["locked"] is False

    again = await client.get(
        f"/skill-books/loadouts/{plant_id}", headers=auth_headers(user_tokens)
    )
    assert again.json()["stored"]["slot_b1_code"] == "clear_aim"
    assert again.json()["revision"] == 1


async def test_presets_are_saved_independently(
    client, user_tokens, session_factory
):
    """세 프리셋은 서로 다른 저장이다. 같은 책을 여러 프리셋에 둘 수 있다."""

    plant_id = await _plant_id(client, user_tokens)
    await _grow_to(session_factory, plant_id, 100000)
    await _grant(session_factory, user_tokens["user"]["id"], "clear_aim")

    for preset in ("guard", "explore"):
        res = await client.put(
            f"/skill-books/loadouts/{plant_id}",
            headers=auth_headers(user_tokens),
            json={"preset_code": preset, "slot_b1_code": "clear_aim"},
        )
        assert res.status_code == 200, res.text

    personal = await client.get(
        f"/skill-books/loadouts/{plant_id}?preset_code=personal",
        headers=auth_headers(user_tokens),
    )
    # 저장하지 않은 프리셋은 건드려지지 않는다.
    assert personal.json()["stored"]["slot_b1_code"] is None


async def test_unowned_book_is_refused_at_save_time(
    client, user_tokens, session_factory
):
    """해석은 조용히 내려오지만 저장은 막는다 — 고르는 순간에 알려 준다."""

    plant_id = await _plant_id(client, user_tokens)
    await _grow_to(session_factory, plant_id, 100000)

    res = await client.put(
        f"/skill-books/loadouts/{plant_id}",
        headers=auth_headers(user_tokens),
        json={"preset_code": "guard", "slot_b1_code": "clear_aim"},
    )
    assert res.status_code == 403, res.text
    assert res.json()["code"] == "LOADOUT_BOOK_NOT_OWNED"


async def test_slot_rules_are_enforced_on_save(
    client, user_tokens, session_factory
):
    plant_id = await _plant_id(client, user_tokens)
    await _grow_to(session_factory, plant_id, 100000)
    await _grant(
        session_factory,
        user_tokens["user"]["id"],
        "clear_aim",
        "final_resolve",
        "shadow_oath",
        "short_cheer",
    )

    # 3등급은 B2 전용이다.
    grade = await client.put(
        f"/skill-books/loadouts/{plant_id}",
        headers=auth_headers(user_tokens),
        json={"preset_code": "guard", "slot_b1_code": "shadow_oath"},
    )
    assert grade.status_code == 422
    assert grade.json()["code"] == "LOADOUT_SLOT_GRADE"

    # 같은 stack_group을 두 칸에 함께 둘 수 없다.
    stack = await client.put(
        f"/skill-books/loadouts/{plant_id}",
        headers=auth_headers(user_tokens),
        json={
            "preset_code": "guard",
            "slot_b1_code": "clear_aim",
            "slot_b2_code": "final_resolve",
        },
    )
    assert stack.status_code == 422
    assert stack.json()["code"] == "LOADOUT_STACK_CONFLICT"

    # 같은 책을 두 칸에 둘 수 없다. 계정에 한 장뿐이다.
    same = await client.put(
        f"/skill-books/loadouts/{plant_id}",
        headers=auth_headers(user_tokens),
        json={
            "preset_code": "guard",
            "slot_b1_code": "clear_aim",
            "slot_b2_code": "clear_aim",
        },
    )
    assert same.status_code == 422
    assert same.json()["code"] == "LOADOUT_DUPLICATE_BOOK"


async def test_locked_slot_refuses_until_the_character_grows(
    client, user_tokens, session_factory
):
    """B1은 Lv9, B2는 Lv23부터다."""

    plant_id = await _plant_id(client, user_tokens)
    await _grant(session_factory, user_tokens["user"]["id"], "clear_aim")

    early = await client.put(
        f"/skill-books/loadouts/{plant_id}",
        headers=auth_headers(user_tokens),
        json={"preset_code": "guard", "slot_b1_code": "clear_aim"},
    )
    assert early.status_code == 422
    assert early.json()["code"] == "LOADOUT_SLOT_LOCKED"

    await _grow_to(session_factory, plant_id, 100000)
    grown = await client.put(
        f"/skill-books/loadouts/{plant_id}",
        headers=auth_headers(user_tokens),
        json={"preset_code": "guard", "slot_b1_code": "clear_aim"},
    )
    assert grown.status_code == 200, grown.text


async def test_stale_revision_is_refused(client, user_tokens, session_factory):
    """다른 화면이 먼저 바꿨으면 덮어쓰지 않고 되돌린다."""

    plant_id = await _plant_id(client, user_tokens)
    await _grow_to(session_factory, plant_id, 100000)
    await _grant(session_factory, user_tokens["user"]["id"], "clear_aim")

    first = await client.put(
        f"/skill-books/loadouts/{plant_id}",
        headers=auth_headers(user_tokens),
        json={"preset_code": "guard", "slot_b1_code": "clear_aim"},
    )
    assert first.status_code == 200

    stale = await client.put(
        f"/skill-books/loadouts/{plant_id}",
        headers=auth_headers(user_tokens),
        json={
            "preset_code": "guard",
            "slot_b1_code": None,
            "expected_revision": 0,
        },
    )
    assert stale.status_code == 409
    assert stale.json()["code"] == "LOADOUT_REVISION_CONFLICT"


async def test_another_account_cannot_read_or_write_the_loadout(
    client, user_tokens, session_factory
):
    from tests.conftest import signup

    plant_id = await _plant_id(client, user_tokens)
    other = await signup(client)

    read = await client.get(
        f"/skill-books/loadouts/{plant_id}", headers=auth_headers(other)
    )
    assert read.status_code == 404
    write = await client.put(
        f"/skill-books/loadouts/{plant_id}",
        headers=auth_headers(other),
        json={"preset_code": "guard", "slot_b1_code": None},
    )
    assert write.status_code == 404


async def test_duplicate_grant_is_refused_without_creating_a_second_copy(
    client, user_tokens, session_factory
):
    """중복 획득은 409로 막는다. 씨앗을 차감하기 전에 여기서 끊는다."""

    user_id = user_tokens["user"]["id"]
    await _grant(session_factory, user_id, "clear_aim")

    async with session_factory() as db:
        try:
            await service.grant_skill_book(
                db, user_id=user_id, code="clear_aim", acquire_source="shop"
            )
        except AppError as error:
            assert error.http_status == 409
            assert error.code == "SKILL_BOOK_ALREADY_OWNED"
        else:  # pragma: no cover - 중복이 통과하면 계약 위반이다
            raise AssertionError("중복 획득이 막히지 않았습니다")

    res = await client.get("/skill-books", headers=auth_headers(user_tokens))
    assert len(res.json()["owned"]) == 1


async def test_party_departure_refuses_the_same_book_twice():
    """같은 책을 여러 캐릭터에 저장하는 것은 되지만 함께 출발할 수는 없다."""

    saved = [
        {"stored": {"slot_b1_code": "clear_aim", "slot_b2_code": None}},
        {"stored": {"slot_b1_code": "clear_aim", "slot_b2_code": None}},
    ]
    try:
        service.assert_party_books_unique(saved)
    except AppError as error:
        assert error.http_status == 422
        assert error.code == "PARTY_DUPLICATE_SKILL_BOOK"
    else:  # pragma: no cover
        raise AssertionError("파티 중복이 막히지 않았습니다")

    # 서로 다른 캐릭터의 같은 감정 family는 허용한다.
    service.assert_party_books_unique(
        [
            {"stored": {"slot_b1_code": "emotion.primary", "slot_b2_code": None}},
            {"stored": {"slot_b1_code": "emotion.primary", "slot_b2_code": None}},
        ]
    )


async def _add_shop_book(session_factory, code: str, price: int) -> int:
    """상점 항목을 직접 넣는다. 통합 테스트 DB는 모델에서 스키마를 만들므로
    마이그레이션이 넣는 행이 없다. 마이그레이션 자체는 별도 테스트가 확인한다."""

    from app.models.game import Item

    async with session_factory() as db:
        item = Item(
            code=f"skill_book_{code}",
            type="skill_book",
            name="또렷한 겨냥",
            description="기본 공격 위력 +3",
            price_seeds=price,
            rarity=1,
            asset_manifest={"skill_book_code": code},
            is_active=True,
        )
        db.add(item)
        await db.commit()
        return int(item.id)


async def _set_seeds(session_factory, user_id: int, balance: int) -> None:
    from app.models.user import User

    async with session_factory() as db:
        await db.execute(
            sa.update(User).where(User.id == user_id).values(seed_balance=balance)
        )
        await db.commit()


async def test_buying_a_book_puts_it_in_the_library(
    client, user_tokens, session_factory
):
    """상점 구매가 서고 보유로 이어진다. 씨앗도 정확히 차감된다."""

    user_id = user_tokens["user"]["id"]
    item_id = await _add_shop_book(session_factory, "clear_aim", 40)
    await _set_seeds(session_factory, user_id, 100)

    purchase = await client.post(
        f"/shop/items/{item_id}/purchase",
        headers=auth_headers(user_tokens, idem=True),
    )
    assert purchase.status_code == 200, purchase.text
    assert purchase.json()["seed_balance"] == 60

    library = await client.get("/skill-books", headers=auth_headers(user_tokens))
    owned = library.json()["owned"]
    assert [entry["code"] for entry in owned] == ["clear_aim"]
    assert owned[0]["acquire_source"] == "shop"
    # 환불이 현재 가격이 아니라 실제 지불액을 쓰도록 원장 entry를 가리킨다.
    assert owned[0]["source_ref"] == f"purchase:item:{user_id}:{item_id}"

    # 산 책은 바로 장착할 수 있다.
    plant_id = await _plant_id(client, user_tokens)
    await _grow_to(session_factory, plant_id, 100000)
    equip = await client.put(
        f"/skill-books/loadouts/{plant_id}",
        headers=auth_headers(user_tokens),
        json={"preset_code": "guard", "slot_b1_code": "clear_aim"},
    )
    assert equip.status_code == 200, equip.text
    assert equip.json()["resolved"]["B1"]["code"] == "clear_aim"


async def test_buying_the_same_book_twice_is_refused_before_seeds_move(
    client, user_tokens, session_factory
):
    """중복 구매로 씨앗이 새지 않는다."""

    user_id = user_tokens["user"]["id"]
    item_id = await _add_shop_book(session_factory, "clear_aim", 40)
    await _set_seeds(session_factory, user_id, 100)

    first = await client.post(
        f"/shop/items/{item_id}/purchase",
        headers=auth_headers(user_tokens, idem=True),
    )
    assert first.status_code == 200

    second = await client.post(
        f"/shop/items/{item_id}/purchase",
        headers=auth_headers(user_tokens, idem=True),
    )
    assert second.status_code == 409
    assert second.json()["code"] == "ITEM_ALREADY_OWNED"

    me = await client.get("/users/me", headers=auth_headers(user_tokens))
    assert me.json()["seed_balance"] == 60


async def test_a_book_earned_elsewhere_cannot_be_bought_again(
    client, user_tokens, session_factory
):
    """해금·도전으로 이미 얻은 책은 상점에서 씨앗을 차감하지 않는다."""

    user_id = user_tokens["user"]["id"]
    item_id = await _add_shop_book(session_factory, "clear_aim", 40)
    await _set_seeds(session_factory, user_id, 100)
    async with session_factory() as db:
        await service.grant_skill_book(
            db, user_id=user_id, code="clear_aim", acquire_source="challenge"
        )
        await db.commit()

    purchase = await client.post(
        f"/shop/items/{item_id}/purchase",
        headers=auth_headers(user_tokens, idem=True),
    )
    assert purchase.status_code == 409
    assert purchase.json()["code"] == "SKILL_BOOK_ALREADY_OWNED"

    me = await client.get("/users/me", headers=auth_headers(user_tokens))
    assert me.json()["seed_balance"] == 100


async def test_guard_uses_accumulate_and_unlock_double_leaf(
    client, user_tokens, session_factory
):
    """마음 지키기를 30번 하면 `두 겹 잎방패`가 조건대로 열린다."""

    from app.models.skill_book import PlantSkillMastery
    from app.services import skill_mastery

    user_id = user_tokens["user"]["id"]
    plant_id = await _plant_id(client, user_tokens)

    async with session_factory() as db:
        # 29회까지는 열리지 않는다.
        db.add(
            PlantSkillMastery(
                plant_id=plant_id,
                skill_code="guard",
                use_count=29,
                mastery_level=skill_mastery.mastery_level_for(29),
            )
        )
        await db.commit()

    library = await client.get("/skill-books", headers=auth_headers(user_tokens))
    progress = next(
        item
        for item in library.json()["unlock_progress"]
        if item["code"] == "double_leaf"
    )
    # 조건과 남은 진행도를 미리 공개한다.
    assert progress == {
        "code": "double_leaf",
        "source": "unlock",
        "goal": 30,
        "current": 29,
        "owned": False,
    }

    async with session_factory() as db:
        granted = await skill_mastery.evaluate_skill_book_unlocks(db, user_id)
        await db.commit()
    assert granted == []

    async with session_factory() as db:
        row = await db.get(PlantSkillMastery, (plant_id, "guard"))
        row.use_count = 30
        await db.commit()
        granted = await skill_mastery.evaluate_skill_book_unlocks(db, user_id)
        await db.commit()

    assert [item["code"] for item in granted] == ["double_leaf"]

    after = await client.get("/skill-books", headers=auth_headers(user_tokens))
    owned = {entry["code"]: entry for entry in after.json()["owned"]}
    assert owned["double_leaf"]["acquire_source"] == "unlock"
    assert owned["double_leaf"]["source_ref"] == "guard:30"

    # 다시 판정해도 두 번 들어오지 않는다.
    async with session_factory() as db:
        assert await skill_mastery.evaluate_skill_book_unlocks(db, user_id) == []
        await db.commit()


async def test_mastery_from_one_character_counts_for_the_account(
    client, user_tokens, session_factory
):
    """캐릭터를 여럿 키워도 `내가 얼마나 해 봤는가`로 합산한다."""

    from app.models.plant import Plant
    from app.models.skill_book import PlantSkillMastery
    from app.services import skill_mastery

    user_id = user_tokens["user"]["id"]
    first = await _plant_id(client, user_tokens)

    async with session_factory() as db:
        base = await db.get(Plant, first)
        second = Plant(
            user_id=user_id,
            species_id=base.species_id,
            name="볕이",
            exp=0,
            status="harvested",
            planted_at=base.planted_at,
        )
        db.add(second)
        await db.flush()
        db.add_all(
            [
                PlantSkillMastery(
                    plant_id=first, skill_code="guard", use_count=18, mastery_level=2
                ),
                # 수확한 캐릭터가 쌓은 경험도 사라지지 않는다.
                PlantSkillMastery(
                    plant_id=second.id,
                    skill_code="guard",
                    use_count=12,
                    mastery_level=2,
                ),
            ]
        )
        await db.commit()

        assert await skill_mastery.account_skill_use_count(db, user_id, "guard") == 30
        granted = await skill_mastery.evaluate_skill_book_unlocks(db, user_id)
        await db.commit()

    assert [item["code"] for item in granted] == ["double_leaf"]


async def test_real_battle_records_mastery_for_the_actions_taken(
    client, user_tokens, session_factory
):
    """실제 전투 한 판이 숙련 기록을 남기는지 끝에서 끝까지 확인한다.

    다른 테스트는 숙련 행을 직접 넣어 조건 판정만 본다. 여기서는 전투 API를
    거쳐 기록이 실제로 쌓이는지를 본다 — 훅이 빠지면 조건이 영원히 안 채워진다.
    """

    import sqlalchemy as sa_

    from app.models.skill_book import PlantSkillMastery
    from tests.integration.test_expedition_stages import (
        _fight_stage_battle,
        _prepare_stage_two,
        _start,
    )

    headers = auth_headers(user_tokens)
    plant_id = await _prepare_stage_two(session_factory, user_tokens["user"]["id"])
    run = await _start(
        client, headers, plant_id, mode="free_explore", stage_no=1
    )
    await _fight_stage_battle(client, headers, run, "mastery")

    async with session_factory() as db:
        rows = (
            await db.execute(
                sa_.select(
                    PlantSkillMastery.skill_code, PlantSkillMastery.use_count
                )
            )
        ).all()

    from app.services.skill_mastery import is_achievement_code

    assert rows, "전투를 마쳤는데 숙련 기록이 하나도 남지 않았습니다"
    counts = {code: count for code, count in rows}
    actions = {
        "attack",
        "unique_1",
        "unique_2",
        "selected_1",
        "selected_2",
        "guard",
    }
    # 여섯 행동 코드와 `@` 접두 성취 기록만 쌓인다. 성취는 해금 조건이 묻는
    # `무엇을 얼마나 해 봤는가`의 근거이고, 접두사로 행동과 갈라 둔다.
    unexpected = {
        code
        for code in counts
        if code not in actions and not is_achievement_code(code)
    }
    assert not unexpected, unexpected
    assert actions & set(counts), "행동 기록이 하나도 없습니다"
    assert all(count >= 1 for count in counts.values())


async def _progress_for(client, user_tokens, code: str) -> dict:
    library = await client.get("/skill-books", headers=auth_headers(user_tokens))
    assert library.status_code == 200
    return next(
        item
        for item in library.json()["unlock_progress"]
        if item["code"] == code
    )


async def test_barrier_kinds_count_variety_not_repetition(
    client, user_tokens, session_factory
):
    """`장벽 3종`은 가짓수를 묻는다. 같은 결을 열 번 열어도 1종이다."""

    from app.models.skill_book import PlantSkillMastery
    from app.services import skill_mastery

    user_id = user_tokens["user"]["id"]
    plant_id = await _plant_id(client, user_tokens)

    async with session_factory() as db:
        # 같은 결만 여러 번 — 가짓수는 하나다.
        db.add(
            PlantSkillMastery(
                plant_id=plant_id,
                skill_code=f"{skill_mastery.BARRIER_KIND_PREFIX}sunny",
                use_count=10,
                mastery_level=0,
            )
        )
        await db.commit()

    assert (await _progress_for(client, user_tokens, "weakness_engrave"))["current"] == 1

    async with session_factory() as db:
        for kel in ("rainy", "ember"):
            db.add(
                PlantSkillMastery(
                    plant_id=plant_id,
                    skill_code=f"{skill_mastery.BARRIER_KIND_PREFIX}{kel}",
                    use_count=1,
                    mastery_level=0,
                )
            )
        await db.commit()

    progress = await _progress_for(client, user_tokens, "weakness_engrave")
    assert progress["current"] == progress["goal"] == 3
    assert progress["owned"] is False

    async with session_factory() as db:
        granted = await skill_mastery.evaluate_skill_book_unlocks(db, user_id)
        await db.commit()
    assert [item["code"] for item in granted] == ["weakness_engrave"]
    assert granted[0]["name"] == "약점 각인"

    # 두 번 평가해도 두 장이 되지 않는다.
    async with session_factory() as db:
        assert await skill_mastery.evaluate_skill_book_unlocks(db, user_id) == []
        await db.commit()
    assert (await _progress_for(client, user_tokens, "weakness_engrave"))["owned"] is True


async def test_species_conditions_only_count_that_species(
    client, user_tokens, session_factory
):
    """`여우비로 10회`는 여우비가 한 것만 센다. 다른 캐릭터 몫은 안 들어간다."""

    import sqlalchemy as sa_

    from app.models.plant import Plant, PlantSpecies
    from app.models.skill_book import PlantSkillMastery
    from app.services import skill_mastery

    user_id = user_tokens["user"]["id"]
    plant_id = await _plant_id(client, user_tokens)

    async with session_factory() as db:
        plant = await db.get(Plant, plant_id)
        species = await db.get(PlantSpecies, plant.species_id)
        # 기본 캐릭터는 여우비가 아니다. 그 캐릭터가 10번 열어도 조건은 0이다.
        assert species.code != "gumiho-pot"
        db.add(
            PlantSkillMastery(
                plant_id=plant_id,
                skill_code=skill_mastery.BARRIER_OPEN_CODE,
                use_count=10,
                mastery_level=0,
            )
        )
        await db.commit()

    assert (await _progress_for(client, user_tokens, "nine_tail_afterimage"))[
        "current"
    ] == 0

    # 같은 캐릭터를 여우비로 바꾸면 그제서야 세어진다 — 품종이 기준이다.
    async with session_factory() as db:
        gumiho = (
            await db.execute(
                sa_.select(PlantSpecies).where(PlantSpecies.code == "gumiho-pot")
            )
        ).scalar_one_or_none()
        if gumiho is None:
            # 시드에 없으면 만들어서 검증한다. skip은 검증이 아니다 — 조건이
            # 실제로 품종을 보는지 확인하는 것이 이 테스트의 목적이다.
            gumiho = PlantSpecies(
                code="gumiho-pot",
                name="여우비",
                persona_key="gumiho",
                asset_manifest={},
                rarity=4,
            )
            db.add(gumiho)
            await db.flush()
        plant = await db.get(Plant, plant_id)
        plant.species_id = gumiho.id
        await db.commit()

    progress = await _progress_for(client, user_tokens, "nine_tail_afterimage")
    assert progress["current"] == progress["goal"] == 10

    async with session_factory() as db:
        granted = await skill_mastery.evaluate_skill_book_unlocks(db, user_id)
        await db.commit()
    assert "nine_tail_afterimage" in {item["code"] for item in granted}


async def test_safe_returns_count_only_runs_that_came_home(
    client, user_tokens, session_factory
):
    """`안전 귀환 5회`는 돌아온 run만 센다. 도중에 물러난 run은 아니다."""

    from app.models.expedition import ExpeditionRun
    from app.services import skill_mastery

    user_id = user_tokens["user"]["id"]

    def _run(status: str) -> ExpeditionRun:
        from datetime import date

        return ExpeditionRun(
            user_id=user_id,
            region_code="moss_archive",
            mode="free_explore",
            status=status,
            phase="exploring",
            local_date=date(2026, 8, 13),
            content_version="test",
            map_seed="seed",
            map_snapshot={},
            run_thread_snapshot={},
            run_memory_snapshot={},
            spotlight_snapshot=[],
            runtime_effects_snapshot={},
            current_node_code="entry",
        )

    async with session_factory() as db:
        # 물러난 run 다섯 개로는 열리지 않는다.
        for _ in range(5):
            db.add(_run("retreated"))
        await db.commit()

    assert (await _progress_for(client, user_tokens, "reviving_root"))["current"] == 0

    async with session_factory() as db:
        for _ in range(5):
            db.add(_run("safe_returned"))
        await db.commit()

    progress = await _progress_for(client, user_tokens, "reviving_root")
    assert progress["current"] == progress["goal"] == 5

    async with session_factory() as db:
        granted = await skill_mastery.evaluate_skill_book_unlocks(db, user_id)
        await db.commit()
    assert "reviving_root" in {item["code"] for item in granted}


async def test_conditions_without_evidence_are_not_advertised(client, user_tokens):
    """근거를 셀 수 없는 조건은 사전 공개하지 않는다.

    깊은 조사 세 권은 `deep` 모드와 나머지 지역이 없어 영원히 참이 될 수 없다.
    진행도 0/1을 영영 붙잡아 두느니 아예 내보내지 않는다.
    """

    library = await client.get("/skill-books", headers=auth_headers(user_tokens))
    advertised = {item["code"] for item in library.json()["unlock_progress"]}

    from app.services import skill_mastery
    from app.services.expeditions import shipped_region_codes

    # 항상 세는 조건 — 근거가 지역과 무관하다.
    always = {
        "double_leaf",
        "nine_tail_afterimage",
        "shadow_oath",
        "weakness_engrave",
        "reviving_root",
        "heart_encyclopedia",
    }
    # 지역 깊은 조사 조건은 **그 지역이 실려 있을 때만** 나타난다. 목록을 손으로
    # 박아 두면 지역을 실은 날 이 테스트가 `틀린 이유로` 실패한다.
    shipped = shipped_region_codes()
    deep = {
        code
        for code, _source, region_code in skill_mastery.DEEP_SURVEY_UNLOCKS
        if region_code in shipped
    }
    unshipped = {
        code
        for code, _source, region_code in skill_mastery.DEEP_SURVEY_UNLOCKS
        if region_code not in shipped
    }

    assert advertised == always | deep
    for code in unshipped:
        assert code not in advertised, code

    # 사전 공개하는 조건은 전부 목표와 현재를 함께 말한다.
    for item in library.json()["unlock_progress"]:
        assert item["goal"] > 0, item
        assert 0 <= item["current"] <= item["goal"], item



async def _grow_for_expedition(session_factory, plant_id: int) -> None:
    """탐험 편성 가능한 단계까지 키운다.

    `새싹 단계부터 탐험할 수 있습니다`가 깊은 조사 관문보다 먼저 걸린다. 여기서
    보려는 것은 그 검사가 아니므로 전제만 맞춰 둔다.
    """

    from app.models.plant import Plant

    async with session_factory() as db:
        plant = await db.get(Plant, plant_id)
        plant.exp = 450
        await db.commit()


async def test_deep_survey_is_locked_until_the_region_is_finished(
    client, user_tokens, session_factory
):
    """깊은 조사는 8스테이지를 다 마쳐야 열린다. 잠긴 이유도 함께 말한다."""

    from datetime import datetime

    from app.models.expedition import UserStageProgress
    from app.services import expeditions as expedition_service

    user_id = user_tokens["user"]["id"]

    catalog = await client.get(
        "/adventure/expeditions/catalog", headers=auth_headers(user_tokens)
    )
    entry = catalog.json()["entry"]
    assert entry["deep_available"] is False
    assert "8스테이지" in entry["deep_locked_reason"]
    # 잠겼어도 목록에는 남는다 — 빼 버리면 있는 줄도 모른다.
    assert "deep" in catalog.json()["regions"][0]["modes"]
    assert catalog.json()["regions"][0]["deep_available"] is False
    # 어려운 쪽이 벌이도 좋으면 편안한 난이도가 손해가 된다.
    assert catalog.json()["rules"]["deep_reward"] is False

    plant_id = await _plant_id(client, user_tokens)
    await _grow_for_expedition(session_factory, plant_id)
    blocked = await client.post(
        "/adventure/expeditions",
        headers={**auth_headers(user_tokens), "Idempotency-Key": "deep-locked-1"},
        json={
            "region_code": "moss_archive",
            "mode": "deep",
            "plant_ids": [plant_id],
            "guide_count": 1,
        },
    )
    assert blocked.status_code == 422
    assert blocked.json()["code"] == "EXPEDITION_DEEP_LOCKED"

    # 일곱 스테이지로는 아직 열리지 않는다 — 경계를 정확히 지킨다.
    async with session_factory() as db:
        for stage_no in range(1, 8):
            db.add(
                UserStageProgress(
                    user_id=user_id,
                    region_code="moss_archive",
                    stage_no=stage_no,
                    cleared_at=datetime(2026, 8, 13),
                    clear_count=1,
                    updated_at=datetime(2026, 8, 13),
                )
            )
        await db.commit()
        assert (
            await expedition_service.region_cleared(db, user_id, "moss_archive")
        ) is False

    catalog = await client.get(
        "/adventure/expeditions/catalog", headers=auth_headers(user_tokens)
    )
    assert catalog.json()["entry"]["deep_available"] is False

    async with session_factory() as db:
        db.add(
            UserStageProgress(
                user_id=user_id,
                region_code="moss_archive",
                stage_no=8,
                cleared_at=datetime(2026, 8, 13),
                clear_count=1,
                updated_at=datetime(2026, 8, 13),
            )
        )
        await db.commit()
        assert (
            await expedition_service.region_cleared(db, user_id, "moss_archive")
        ) is True

    catalog = await client.get(
        "/adventure/expeditions/catalog", headers=auth_headers(user_tokens)
    )
    assert catalog.json()["entry"]["deep_available"] is True
    assert catalog.json()["entry"]["deep_locked_reason"] is None


async def test_deep_run_freezes_its_difficulty_and_earns_no_extra_reward(
    client, user_tokens, session_factory
):
    """깊은 조사는 출발 시점에 난이도를 굳히고, 반복 재화를 늘리지 않는다."""

    from datetime import datetime

    from app.models.expedition import ExpeditionRun, UserStageProgress

    user_id = user_tokens["user"]["id"]
    async with session_factory() as db:
        for stage_no in range(1, 9):
            db.add(
                UserStageProgress(
                    user_id=user_id,
                    region_code="moss_archive",
                    stage_no=stage_no,
                    cleared_at=datetime(2026, 8, 13),
                    clear_count=1,
                    updated_at=datetime(2026, 8, 13),
                )
            )
        await db.commit()

    plant_id = await _plant_id(client, user_tokens)
    await _grow_for_expedition(session_factory, plant_id)
    started = await client.post(
        "/adventure/expeditions",
        headers={**auth_headers(user_tokens), "Idempotency-Key": "deep-open-1"},
        json={
            "region_code": "moss_archive",
            "mode": "deep",
            "plant_ids": [plant_id],
            "guide_count": 1,
        },
    )
    assert started.status_code == 201, started.text
    run_id = started.json()["run"]["id"]

    async with session_factory() as db:
        run = await db.get(ExpeditionRun, run_id)
        assert run.mode == "deep"
        # 반복 재화를 늘리지 않는다(9.2).
        assert run.reward_eligible is False
        # 난이도가 스냅샷에 굳어 있다 — 진행 중 run이 밸런스 조정에 안 흔들린다.
        encounters = [
            event["encounter"]
            for event in run.map_snapshot["events"].values()
            if isinstance(event.get("encounter"), dict)
        ]
        assert encounters, "사건이 하나도 없는 지도입니다"
        assert all(e.get("difficulty_code") == "deep" for e in encounters)


async def test_deep_difficulty_hits_harder_without_a_thicker_wall():
    """깊은 조사는 벽을 더 두껍게 하지 않고 한 대를 더 아프게 만든다.

    장벽만 키우면 전투가 길어지기만 하고 어려워지지 않는다. 실패는 `읽고
    감수한 선택`에서 나와야 한다.
    """

    from app.content.expeditions.combat_difficulty import STAGE_THREAT_PROFILES

    boss = STAGE_THREAT_PROFILES["stage_8"]
    deep = STAGE_THREAT_PROFILES["deep"]

    assert deep["barrier_bp"] < boss["barrier_bp"]
    assert deep["single_hit_cap_bp"] > boss["single_hit_cap_bp"]
    assert deep["mechanic_level"] == boss["mechanic_level"]


async def test_deep_unlocks_only_advertise_regions_that_exist(client, user_tokens):
    """만들지 않은 지역의 조건은 사전 공개하지 않는다.

    진행도 0/1이 영영 멈춰 있는 목표를 보여 주느니 아예 내보내지 않는다.
    지역이 실리는 날 코드를 고치지 않아도 저절로 나타난다.
    """

    from app.services import skill_mastery
    from app.services.expeditions import shipped_region_codes

    shipped = shipped_region_codes()
    assert "moss_archive" in shipped

    library = await client.get("/skill-books", headers=auth_headers(user_tokens))
    advertised = {item["code"] for item in library.json()["unlock_progress"]}

    for code, _source, region_code in skill_mastery.DEEP_SURVEY_UNLOCKS:
        if region_code in shipped:
            assert code in advertised, code
        else:
            assert code not in advertised, code


# ── 새 지역 3종을 실제로 걸어 본다 ──────────────────────────────────────────
#
# 지역 팩은 생성기가 만들고 정적 검증기가 통과시켰지만, **엔진에서 한 번도 돌아
# 본 적이 없었다.** 검증기는 그래프가 이어지는지·필드가 있는지를 보지, 그 지도에서
# 실제로 이동하고 수호자를 이기고 귀환할 수 있는지는 모른다. 이 테스트가 그것을 본다.
#
# 기억서고만 통합 테스트가 있었다. 지역이 넷이 된 지금 그 하나로는 부족하다.

from tests.integration.test_interactive_expeditions import (  # noqa: E402
    _action,
)


async def _walk_to(client, headers, run, target: str, key_prefix: str) -> dict:
    """그래프를 따라 목표 노드까지 걸어간다.

    기억서고 헬퍼는 노드 이름(`wet_labels`·`quiet_camp`)을 박아 두고 있어 다른
    지역에서는 못 쓴다. 여기서는 **지도를 읽어** 최단 경로를 찾는다 — 지역이
    늘어도 그대로 돌고, 지도 모양이 바뀌어도 테스트를 고칠 필요가 없다.
    """

    from collections import deque

    edges: dict[str, set[str]] = {}
    for left, right in run["map"]["edges"]:
        edges.setdefault(left, set()).add(right)
        edges.setdefault(right, set()).add(left)

    def route(start: str) -> list[str]:
        queue = deque([[start]])
        seen = {start}
        while queue:
            path = queue.popleft()
            if path[-1] == target:
                return path[1:]
            for nxt in sorted(edges.get(path[-1], ())):
                if nxt not in seen:
                    seen.add(nxt)
                    queue.append(path + [nxt])
        raise AssertionError(f"{target}까지 가는 길이 없습니다")

    step = 0
    for node_code in route(run["run"]["current_node_code"]):
        step += 1
        run = await _action(
            client, headers, run, "move", {"node_code": node_code},
            f"{key_prefix}-move{step}",
        )
        # 사건 노드는 고르기 전에는 다음으로 못 간다. 가장 안전한 선택으로 넘긴다
        # — 여기서 보려는 것은 판정 결과가 아니라 **길이 이어지는가**다.
        event = run.get("current_event")
        if event and (event.get("encounter") or {}).get("kind") != "guardian":
            safe = next(
                (c for c in event.get("choices") or [] if c.get("safe")),
                None,
            )
            if safe is not None:
                run = await _action(
                    client, headers, run, "choices",
                    {
                        "choice_code": safe["code"],
                        "acting_member_id": run["party"][0]["id"],
                    },
                    f"{key_prefix}-choice{step}",
                )
    return run

NEW_REGIONS = ("echo_well", "starlight_seed_vault", "heartwood_observatory")


async def _unlock_through(session_factory, user_id: int, region_code: str) -> None:
    """그 지역까지 걸어올 수 있도록 앞 지역들을 완주 처리한다.

    앞 지역을 실제로 여덟 번 깨는 것은 이 테스트가 보려는 것이 아니다. 여기서
    보려는 것은 **그 지역의 지도가 실제로 걸어지는가**이지 해금 규칙이 아니다.
    """

    from datetime import datetime

    from app.models.expedition import UserStageProgress
    from app.services.expeditions import region_order

    order = region_order()
    async with session_factory() as db:
        for code in order[: order.index(region_code)]:
            for stage_no in range(1, 9):
                db.add(
                    UserStageProgress(
                        user_id=user_id,
                        region_code=code,
                        stage_no=stage_no,
                        cleared_at=datetime(2026, 8, 13),
                        clear_count=1,
                        updated_at=datetime(2026, 8, 13),
                    )
                )
        await db.commit()


async def _fight_like_a_player(client, headers, run, key_prefix: str) -> dict:
    """예고를 읽고 위험하면 몸을 빼는, 앱 AUTO와 같은 수준의 판단으로 싸운다.

    기존 헬퍼는 **한 번도 방어하지 않는다.** 그래서 `방어를 안 하면 위력이 오르는`
    기믹(`guard_check`·`resonant_pressure`)을 단 수호자에게는 반드시 진다. 그건
    콘텐츠가 나쁜 것이 아니라 시험하는 쪽이 비현실적인 것이다 — 앱 AUTO도 죽을
    것 같으면 방어한다. 이 지역이 **읽고 대응하는 사람에게** 넘어갈 수 있는지를
    보려면 그 수준으로 싸워야 한다.
    """

    turn = 1
    while (run.get("current_event") or {}).get("battle", {}).get("status") == "active":
        battle = run["current_event"]["battle"]
        focus = battle["focus"]
        intent = battle["enemy"]["intent"]
        power = int(intent.get("power", 1))
        target = intent.get("target", "front")
        living = [m for m in battle["party"] if m["hp"] > 0]
        commands = []
        for index, member in enumerate(living):
            # 이번 예고에 맞으면 쓰러지는가. 맞으면 몸을 뺀다.
            targeted = (
                target == "all"
                or (target == "front" and index == 0)
                or (
                    target == "lowest"
                    and member["hp"] == min(m["hp"] for m in living)
                )
            )
            if targeted and member["hp"] <= power:
                commands.append(
                    {"member_id": member["member_id"], "action": "guard"}
                )
                continue
            skills = [
                *member["kit"].get("unique_skills", []),
                *member["kit"].get("selected_skills", []),
            ]
            usable = [
                s
                for s in skills
                if s.get("available", True)
                and int(s.get("cooldown_remaining", 0)) == 0
                and int(s.get("focus_cost", 0)) <= focus
                and int(s.get("power", 0)) > 0
            ]
            if usable:
                chosen = max(
                    usable,
                    key=lambda s: (
                        s.get("matchup") == "weak",
                        int(s.get("power", 0)),
                        -int(s.get("focus_cost", 0)),
                    ),
                )
                commands.append(
                    {"member_id": member["member_id"], "action": chosen["slot"]}
                )
                focus -= int(chosen.get("focus_cost", 0))
            else:
                commands.append(
                    {"member_id": member["member_id"], "action": "attack"}
                )
                focus = min(battle["max_focus"], focus + 1)
        run = await _action(
            client, headers, run, "combat/turns", {"commands": commands},
            f"{key_prefix}-fight{turn:03d}",
        )
        turn += 1
        assert turn <= 12, "12라운드 안에 끝나지 않았습니다"
    # 패배하면 사건이 통째로 사라져 `battle`이 비고, 상태를 못 읽는다. 런 상태로
    # 확인해야 진 것이 조용히 통과하지 않는다 — 실제로 그렇게 놓쳤다.
    assert run["run"]["status"] != "safe_returned", (
        f"{key_prefix}: 수호전에서 졌습니다(guardian_defeat)"
    )
    final = (run.get("current_event") or {}).get("battle") or {}
    assert final.get("status") in (None, "victory"), (
        f"{key_prefix}: 전투가 {final.get('status')}로 끝났습니다 "
        f"(라운드 {final.get('round')}, 장벽 {final.get('enemy_guard')}/"
        f"{final.get('enemy_max_guard')}, "
        f"파티 {[(m['member_id'], m['hp']) for m in final.get('party', [])]})"
    )
    return run


@pytest.mark.parametrize("region_code", NEW_REGIONS)
async def test_new_region_can_actually_be_walked(
    client, user_tokens, session_factory, region_code
):
    """생성한 지역 팩이 정말 플레이되는가.

    출발 → 수호자까지 이동 → 수호전 → 귀환까지 한 번에 지난다. 하나라도
    끊기면 그 지역은 콘텐츠가 있는 척만 하는 것이다.
    """

    headers = auth_headers(user_tokens)
    user_id = user_tokens["user"]["id"]
    plant_id = await _plant_id(client, user_tokens)
    await _grow_for_expedition(session_factory, plant_id)
    await _unlock_through(session_factory, user_id, region_code)

    started = await client.post(
        "/adventure/expeditions",
        headers={**headers, "Idempotency-Key": f"walk-{region_code}"},
        json={
            "region_code": region_code,
            "mode": "free_explore",
            "plant_ids": [plant_id],
            "guide_count": 1,
        },
    )
    assert started.status_code == 201, started.text
    run = started.json()

    # 지도가 그 지역의 것이어야 한다 — 첫 지역 지도를 돌려주면 안 된다.
    assert run["run"]["region_code"] == region_code
    assert run["map"]["code"].startswith(region_code)
    assert len(run["map"]["nodes"]) == 8

    # 입구에서 모든 노드에 닿을 수 있어야 걸을 수 있다.
    codes = {node["code"] for node in run["map"]["nodes"]}
    assert run["run"]["current_node_code"] == "entrance"
    assert "guardian" in codes

    # 수호자까지 걸어간다.
    run = await _walk_to(client, headers, run, "guardian", f"walk-{region_code}")
    assert run["run"]["current_node_code"] == "guardian"

    event = run["current_event"]
    assert event is not None, f"{region_code}: 수호자 자리에 사건이 없습니다"
    assert event["encounter"]["kind"] == "guardian"
    # 생성기가 넣은 수호자가 그대로 나와야 한다.
    assert event["encounter"]["enemy_name"] in {
        "물결 종지기",
        "발아 시계",
        "나이테 관측자",
    }
    # 세 단계가 다 실려 있어야 한다.
    assert len(event["encounter"]["boss_phases"]) == 3

    # 실제로 싸워 이긴다.
    run = await _fight_like_a_player(client, headers, run, f"walk-{region_code}")

    # 수호자를 이기면 전투가 정리된다. 가 곧바로 이 되는지는
    # 지역마다 다르다(다음 노드에 사건이 걸려 있으면 로 남는다).
    # 여기서 볼 것은 상태 이름이 아니라 **계속 걸을 수 있는가**다.
    assert (run.get("current_event") or {}).get("battle") is None

    # 목표는 수호자를 이길 때가 아니라 **목표 노드에 닿을 때** 확보된다.
    run = await _walk_to(
        client, headers, run, "objective", f"walk-{region_code}-obj"
    )
    assert run["run"]["objective_secured"] is True

    # 확보한 것을 들고 출구까지 걸어 나와야 지역이 완결된다.
    run = await _walk_to(client, headers, run, "exit", f"walk-{region_code}-exit")
    assert run["run"]["current_node_code"] == "exit"
    run = await _action(
        client, headers, run, "extract", {}, f"walk-{region_code}-extract"
    )
    assert run["run"]["status"] == "completed"


@pytest.mark.parametrize("region_code", NEW_REGIONS)
async def test_new_region_battle_stages_start_in_their_own_fight(
    client, user_tokens, session_factory, region_code
):
    """스테이지 1이 그 지역 엉킴으로 시작하는가.

    생성기가 스테이지에 적은 엉킴 코드가 실제 전투로 이어지는지 본다. 여기가
    끊기면 지도만 있고 싸울 것이 없는 지역이 된다.
    """

    from app.content.expeditions.tangles import TANGLE_CATALOG
    from app.services.expeditions import load_content

    headers = auth_headers(user_tokens)
    user_id = user_tokens["user"]["id"]
    plant_id = await _plant_id(client, user_tokens)
    await _grow_for_expedition(session_factory, plant_id)
    await _unlock_through(session_factory, user_id, region_code)

    pack = load_content(region_code)
    first_battle = next(s for s in pack["stages"] if s["kind"] == "battle")

    started = await client.post(
        "/adventure/expeditions",
        headers={**headers, "Idempotency-Key": f"stage-{region_code}"},
        json={
            "region_code": region_code,
            "mode": "free_explore",
            "plant_ids": [plant_id],
            "guide_count": 1,
            "stage_no": first_battle["no"],
        },
    )
    assert started.status_code == 201, started.text
    run = started.json()

    battle = run["current_event"]["battle"]
    assert battle is not None, f"{region_code}: 전투 스테이지인데 전투가 없습니다"

    # 그 지역 엉킴이어야 한다. 다른 지역 것이 나오면 콘텐츠가 섞인 것이다.
    expected = TANGLE_CATALOG[first_battle["tangles"][0]]
    assert battle["enemy"]["name"] == expected["name"]
    assert expected["region_code"] == region_code

    # 스테이지가 예고한 약점이 실제 전투의 약점과 같아야 한다 — 다르면
    # 사용자가 잘못된 준비를 하고 들어간다.
    assert battle["weakness"] == first_battle["weakness"]
