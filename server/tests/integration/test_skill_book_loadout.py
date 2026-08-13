"""기록서 소유·장착의 저장과 API 계약.

설계서 11.4·11.5와 실행 계약 4.4를 실제 저장소 위에서 확인한다. 핵심은
**소유와 장착이 서로 다른 축**이라는 것이다. 보유해도 자동 장착되지 않고,
장착은 캐릭터·프리셋마다 따로 남는다.
"""

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

    assert rows, "전투를 마쳤는데 숙련 기록이 하나도 남지 않았습니다"
    counts = {code: count for code, count in rows}
    # 여섯 행동 코드만 쌓인다.
    assert set(counts) <= {
        "attack",
        "unique_1",
        "unique_2",
        "selected_1",
        "selected_2",
        "guard",
    }
    assert all(count >= 1 for count in counts.values())
