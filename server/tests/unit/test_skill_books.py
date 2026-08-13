"""마음결 기록서 카탈로그와 장착 판정 계약.

`docs/character_skill_growth_design.md` 7장이 획득·경제·장착·해금의 단일 원본이고,
`docs/adventure_100_point_execution_contract.md` 4.4가 선택 슬롯 해석 순서를 정한다.
두 문서의 문장을 그대로 검사한다.
"""

from app.content.expeditions.skill_books import (
    ACTIVATION_ROSTER,
    DEFAULT_LOADOUT,
    GRADE_ALLOWED_SLOTS,
    SKILL_BOOK_CATALOG,
    SLOT_UNLOCK_LEVEL,
    is_combat_skill_book,
    resolve_loadout,
    skill_book,
    validate_skill_book_catalog,
)


ALL_CODES = frozenset(SKILL_BOOK_CATALOG)


def test_combat_catalog_matches_the_design_contract():
    """전투 기록서 20종의 등급·모드 분포가 설계서 표와 같다."""

    assert validate_skill_book_catalog() == []
    assert len(SKILL_BOOK_CATALOG) == 20

    grades = [book["grade"] for book in SKILL_BOOK_CATALOG.values()]
    # 1등급 14종·2등급 14종의 절반이 전투형이고, 3등급 8종 중 6종이 전투형이다.
    assert grades.count(1) == 7
    assert grades.count(2) == 7
    assert grades.count(3) == 6

    # 7.5.1의 닫힌 목록과 정확히 일치해야 한다. 문구에서 모드를 추측하지 않는다.
    assert sum(len(codes) for codes in ACTIVATION_ROSTER.values()) == 20
    for mode, codes in ACTIVATION_ROSTER.items():
        actual = {
            code
            for code, book in SKILL_BOOK_CATALOG.items()
            if book["activation_mode"] == mode
        }
        assert actual == set(codes), mode


def test_every_book_is_reward_neutral_and_permanent():
    """기록서는 보상을 1도 바꾸지 않고 소모되지 않는다."""

    for code, book in SKILL_BOOK_CATALOG.items():
        assert book["reward_affecting"] is False, code
        # 소모·강화·합성·분해 개념 자체를 카탈로그에 두지 않는다.
        assert "charges" not in book, code
        assert "consumable" not in book, code


def test_grade_three_is_second_slot_only_and_cannot_be_bought():
    """가장 강한 도구는 가장 오래 키운 캐릭터에게만, 그리고 도전으로만 열린다."""

    assert GRADE_ALLOWED_SLOTS[3] == ("B2",)
    for code, book in SKILL_BOOK_CATALOG.items():
        if book["grade"] != 3:
            continue
        assert book["min_slot"] == "B2", code
        assert book["acquire_kind"] == "challenge", code
        assert book["price_seeds"] is None, code
        # 예산 2를 쓰는 대신 반드시 반대급부를 함께 가진다.
        assert book["tradeoff"], code


def test_catalog_hands_out_copies():
    """호출부가 카탈로그 원본을 바꿔 다음 전투에 새게 하지 않는다."""

    first = skill_book("clear_aim")
    assert first is not None
    first["effect_summary"] = "바꿔치기"
    assert SKILL_BOOK_CATALOG["clear_aim"]["effect_summary"] != "바꿔치기"
    assert skill_book("no_such_book") is None
    assert is_combat_skill_book("clear_aim")
    # 탐험 기록서는 이 카탈로그에 없다. 전투 슬롯 판정에 끼어들지 않는다.
    assert not is_combat_skill_book("retrace")
    assert not is_combat_skill_book(None)


def test_missing_loadout_falls_back_to_the_safe_default():
    """장착 기능을 아직 열지 않은 계정도 여섯 슬롯이 비지 않는다."""

    resolved = resolve_loadout(None, owned_codes=frozenset(), level=30)
    assert resolved["B1"]["source"] == "emotion"
    assert resolved["B1"]["code"] == DEFAULT_LOADOUT["B1"]
    assert resolved["B2"]["source"] == "default_book"
    assert resolved["B2"]["code"] == DEFAULT_LOADOUT["B2"]
    # 아무것도 저장하지 않은 상태는 `되돌려졌다`가 아니다.
    assert resolved["B1"]["fell_back"] is False
    assert resolved["B2"]["fell_back"] is False


def test_slots_open_at_their_unlock_levels():
    """B1은 Lv9, B2는 Lv23부터다. 잠긴 슬롯은 이유를 함께 돌려준다."""

    assert SLOT_UNLOCK_LEVEL == {"B1": 9, "B2": 23}
    low = resolve_loadout(
        {"slot_b1_code": "clear_aim", "slot_b2_code": "short_cheer"},
        owned_codes=ALL_CODES,
        level=5,
    )
    assert low["B1"]["locked"] is True
    assert low["B2"]["locked"] is True
    assert "Lv9" in low["B1"]["lock_reason"]
    assert "Lv23" in low["B2"]["lock_reason"]

    middle = resolve_loadout(
        {"slot_b1_code": "clear_aim", "slot_b2_code": "short_cheer"},
        owned_codes=ALL_CODES,
        level=9,
    )
    assert middle["B1"]["code"] == "clear_aim"
    assert middle["B2"]["locked"] is True


def test_owned_books_equip_and_unowned_books_fall_back():
    """소유와 장착은 분리된다. 보유하지 않은 책은 장착되지 않는다."""

    equipped = resolve_loadout(
        {"slot_b1_code": "clear_aim", "slot_b2_code": "short_cheer"},
        owned_codes=frozenset({"clear_aim", "short_cheer"}),
        level=30,
    )
    assert equipped["B1"]["source"] == "skillbook"
    assert equipped["B1"]["code"] == "clear_aim"
    assert equipped["B2"]["code"] == "short_cheer"
    assert equipped["B2"]["fell_back"] is False

    missing = resolve_loadout(
        {"slot_b2_code": "reviving_root"},
        owned_codes=frozenset({"clear_aim"}),
        level=30,
    )
    assert missing["B2"]["code"] == DEFAULT_LOADOUT["B2"]
    assert missing["B2"]["fell_back"] is True
    assert missing["B2"]["lock_reason"] == "아직 서고에 없어요"


def test_grade_three_in_the_first_slot_is_refused_without_blocking_departure():
    """3등급을 B1에 저장해도 출발을 막지 않고 기본값으로 내려온다."""

    resolved = resolve_loadout(
        {"slot_b1_code": "shadow_oath"},
        owned_codes=ALL_CODES,
        level=30,
    )
    assert resolved["B1"]["source"] == "emotion"
    assert resolved["B1"]["fell_back"] is True
    assert "두 번째 칸" in resolved["B1"]["lock_reason"]

    allowed = resolve_loadout(
        {"slot_b2_code": "shadow_oath"},
        owned_codes=ALL_CODES,
        level=30,
    )
    assert allowed["B2"]["code"] == "shadow_oath"
    assert allowed["B2"]["fell_back"] is False


def test_two_slots_cannot_share_a_stack_group():
    """같은 stack_group을 두 칸에 함께 두면 뒤 칸이 기본값으로 내려온다."""

    # clear_aim과 final_resolve는 둘 다 basic_power다.
    assert (
        SKILL_BOOK_CATALOG["clear_aim"]["stack_group"]
        == SKILL_BOOK_CATALOG["final_resolve"]["stack_group"]
    )
    resolved = resolve_loadout(
        {"slot_b1_code": "clear_aim", "slot_b2_code": "final_resolve"},
        owned_codes=ALL_CODES,
        level=30,
    )
    assert resolved["B1"]["code"] == "clear_aim"
    assert resolved["B2"]["code"] == DEFAULT_LOADOUT["B2"]
    assert "같은 결" in resolved["B2"]["lock_reason"]

    # 다른 그룹이면 둘 다 남는다.
    fine = resolve_loadout(
        {"slot_b1_code": "clear_aim", "slot_b2_code": "short_cheer"},
        owned_codes=ALL_CODES,
        level=30,
    )
    assert fine["B1"]["code"] == "clear_aim"
    assert fine["B2"]["code"] == "short_cheer"


def test_exploration_books_rest_in_combat_instead_of_erroring():
    """수호 프리셋에 탐험 기록서를 넣어도 출발을 막지 않는다."""

    resolved = resolve_loadout(
        {"slot_b2_code": "retrace"},
        owned_codes=frozenset({"retrace"}),
        level=30,
    )
    assert resolved["B2"]["code"] == DEFAULT_LOADOUT["B2"]
    assert resolved["B2"]["lock_reason"] == "이 기록서는 전투에서 쉬어요"


def test_only_command_books_take_a_member_action():
    """opening·trigger는 스스로 발동하므로 벨트에서 누를 수 없다."""

    for code, book in SKILL_BOOK_CATALOG.items():
        if book["grade"] == 3:
            slot, other = "slot_b2_code", "B2"
        else:
            slot, other = "slot_b1_code", "B1"
        resolved = resolve_loadout(
            {slot: code}, owned_codes=ALL_CODES, level=30
        )[other]
        assert resolved["code"] == code, code
        if book["activation_mode"] == "command":
            assert resolved["locked"] is False, code
            assert resolved["lock_reason"] is None, code
        else:
            # 자리를 비워 벨트 위치를 바꾸지 않고, 왜 못 누르는지 알려 준다.
            assert resolved["locked"] is True, code
            assert resolved["lock_reason"] == "때가 되면 스스로 펼쳐져요", code


def test_ownership_check_can_be_skipped_before_the_store_is_wired():
    """소유권 저장소를 붙이기 전 호출부는 카탈로그만으로 해석할 수 있다."""

    resolved = resolve_loadout(
        {"slot_b1_code": "clear_aim"}, owned_codes=None, level=30
    )
    assert resolved["B1"]["code"] == "clear_aim"
    assert resolved["B1"]["fell_back"] is False


def test_emotion_pointers_stay_in_either_slot():
    """감정 스킬 포인터는 두 칸 어디에나 둘 수 있다."""

    resolved = resolve_loadout(
        {"slot_b1_code": "emotion.secondary", "slot_b2_code": "emotion.primary"},
        owned_codes=frozenset(),
        level=30,
    )
    assert resolved["B1"]["source"] == "emotion"
    assert resolved["B1"]["code"] == "emotion.secondary"
    assert resolved["B2"]["source"] == "emotion"
    assert resolved["B2"]["code"] == "emotion.primary"
    assert resolved["B2"]["fell_back"] is False


def _profile(snapshot_extra: dict | None = None) -> dict:
    return {
        "id": 1,
        "snapshot": {
            "name": "달빛이",
            "species": {"code": "baby-pot"},
            "form": "sunny",
            "level": 30,
            "stage": 5,
            "rarity": 3,
            "stats": {"care": 7, "focus": 6, "courage": 5, "insight": 6},
            **(snapshot_extra or {}),
        },
    }


def test_battle_kit_uses_the_frozen_loadout_from_the_snapshot():
    """출발 시점에 얼린 장착이 실제 여섯 슬롯을 정한다."""

    from app.content.expeditions.combat import member_battle_kit

    equipped = member_battle_kit(
        _profile(
            {
                "skill_loadout": {
                    "preset_code": "guard",
                    "slots": {
                        "B1": {"source": "skillbook", "code": "clear_aim"},
                        "B2": {"source": "default_book", "code": "field_note_echo"},
                    },
                }
            }
        )
    )
    selected = {item["slot"]: item for item in equipped["selected_skills"]}
    assert selected["selected_1"]["equipped_book"]["code"] == "clear_aim"
    # 기믹이 아직 없으므로 누를 수 없는 상태로 정직하게 표시한다.
    assert selected["selected_1"]["available"] is False
    assert selected["selected_1"]["lock_reason"]
    assert "equipped_book" not in selected["selected_2"]


def test_battle_kit_without_a_snapshot_keeps_the_safe_default():
    """장착 기능 이전에 출발한 런은 지금까지와 똑같이 재생된다."""

    from app.content.expeditions.combat import member_battle_kit

    kit = member_battle_kit(_profile())
    selected = {item["slot"]: item for item in kit["selected_skills"]}
    assert selected["selected_1"]["source"] == "emotion"
    assert selected["selected_2"]["source"] == "skillbook"
    assert selected["selected_2"]["code"] == "field_note_echo"
    assert selected["selected_1"]["available"] is True
    assert "equipped_book" not in selected["selected_1"]


def test_catalog_and_effect_table_agree_on_what_is_wired():
    """카탈로그의 `combat_effect`와 실제 수치표가 어긋나면 안 된다."""

    from app.content.expeditions.skill_book_effects import IMPLEMENTED_CODES

    wired = {
        code for code, book in SKILL_BOOK_CATALOG.items() if book["combat_effect"]
    }
    assert wired == set(IMPLEMENTED_CODES)
    # 아직 연결하지 않은 책은 효과를 주장하지 않는다.
    for code, book in SKILL_BOOK_CATALOG.items():
        assert isinstance(book["combat_effect"], bool), code


def test_book_effects_are_flat_and_never_scale():
    """정액 계약 — 등급·tier·지원 능력치로 자라지 않는다."""

    from app.content.expeditions.combat import member_battle_kit

    def kit_with(code: str, *, stats: dict, rarity: int, level: int):
        return member_battle_kit(
            _profile(
                {
                    "stats": stats,
                    "rarity": rarity,
                    "level": level,
                    "skill_loadout": {
                        "preset_code": "guard",
                        "slots": {
                            "B1": {"source": "skillbook", "code": code},
                            "B2": {"source": "default_book", "code": "field_note_echo"},
                        },
                    },
                }
            )
        )

    weak = {"care": 3, "focus": 3, "courage": 3, "insight": 3}
    strong = {"care": 9, "focus": 9, "courage": 9, "insight": 9}

    # 잎사귀 각반 — 방어량 2 → 3. 어떤 캐릭터가 들어도 정확히 +1이다.
    for stats, rarity, level in ((weak, 1, 9), (strong, 5, 30)):
        bare = member_battle_kit(
            _profile({"stats": stats, "rarity": rarity, "level": level})
        )
        with_book = kit_with("leaf_greave", stats=stats, rarity=rarity, level=level)
        assert with_book["guard"]["guard"] - bare["guard"]["guard"] == 1

    # 또렷한 겨냥 — 기본 공격 위력 +3. 정액이라 등급 계수를 타지 않는다.
    for stats, rarity, level in ((weak, 1, 9), (strong, 5, 30)):
        bare = member_battle_kit(
            _profile({"stats": stats, "rarity": rarity, "level": level})
        )
        with_book = kit_with("clear_aim", stats=stats, rarity=rarity, level=level)
        assert with_book["basic"]["raw_power"] - bare["basic"]["raw_power"] == 3


def test_opening_books_change_the_battle_start_once():
    """전투 시작 보정은 파티 자원에 한 번만 더해지고 상한을 지킨다."""

    from app.content.expeditions.skill_book_effects import opening_modifiers

    def party(*codes):
        return [
            {
                "id": index + 1,
                "snapshot": {
                    "skill_loadout": {
                        "slots": {
                            "B1": {"source": "skillbook", "code": code},
                            "B2": {"source": "emotion", "code": "emotion.primary"},
                        }
                    }
                },
            }
            for index, code in enumerate(codes)
        ]

    assert opening_modifiers(party())["focus"] == 0
    assert opening_modifiers(party("first_breath"))["focus"] == 1
    # 발아 시계의 태엽 — 집중력 +2에 1라운드 스킬 사용 불가라는 반대급부.
    gear = opening_modifiers(party("germination_gear"))
    assert gear["focus"] == 2
    assert gear["first_round_skill_locked"] == [1]
    # 물결 종지기의 종 — 라운드 +1에 집중력 최대치 −1.
    chime = opening_modifiers(party("bellringer_chime"))
    assert chime["max_rounds"] == 1
    assert chime["max_focus"] == -1
    # 효과가 없는 책은 아무것도 더하지 않는다.
    assert opening_modifiers(party("short_cheer"))["books"] == []


def test_first_breath_actually_starts_the_battle_with_more_focus():
    """구매 → 장착 → 전투까지 한 권이 끝까지 이어진다."""

    from app.content.expeditions.combat import new_guardian_battle

    encounter = {
        "enemy_name": "돌비늘 장부지기",
        "enemy_max_guard": 100,
        "max_rounds": 6,
        "starting_focus": 3,
        "max_focus": 5,
        "weakness_cycle": ["insight", "care", "courage", "focus"],
        "intents": [
            {
                "code": "claw",
                "name": "장부 발톱",
                "telegraph": "노려요.",
                "target": "front",
                "power": 1,
            }
        ],
    }
    bare = new_guardian_battle("no-book", encounter, [_profile()])
    equipped = new_guardian_battle(
        "with-book",
        encounter,
        [
            _profile(
                {
                    "skill_loadout": {
                        "slots": {
                            "B1": {"source": "skillbook", "code": "first_breath"},
                            "B2": {"source": "emotion", "code": "emotion.primary"},
                        }
                    }
                }
            )
        ],
    )
    assert equipped["focus"] == bare["focus"] + 1
    assert equipped["focus"] <= equipped["max_focus"]
    assert equipped["skill_book_opening"]["books"] == ["first_breath"]


def test_starting_focus_never_passes_the_cap():
    """`상한 5 유지`는 책 문장에 적힌 조건이다."""

    from app.content.expeditions.combat import new_guardian_battle

    encounter = {
        "enemy_name": "돌비늘 장부지기",
        "enemy_max_guard": 100,
        "max_rounds": 6,
        # 이미 상한까지 찬 상태에서 시작하는 전투.
        "starting_focus": 5,
        "max_focus": 5,
        "weakness_cycle": ["insight", "care", "courage", "focus"],
        "intents": [
            {
                "code": "claw",
                "name": "장부 발톱",
                "telegraph": "노려요.",
                "target": "front",
                "power": 1,
            }
        ],
    }
    battle = new_guardian_battle(
        "capped",
        encounter,
        [
            _profile(
                {
                    "skill_loadout": {
                        "slots": {
                            "B1": {"source": "skillbook", "code": "germination_gear"},
                            "B2": {"source": "emotion", "code": "emotion.primary"},
                        }
                    }
                }
            )
        ],
    )
    assert battle["focus"] == battle["max_focus"] == 5


def _encounter_fixture() -> dict:
    return {
        "enemy_name": "돌비늘 장부지기",
        "enemy_max_guard": 400,
        "max_rounds": 6,
        "starting_focus": 3,
        "max_focus": 5,
        "weakness_cycle": ["insight", "care", "courage", "focus"],
        "intents": [
            {
                "code": "claw",
                "name": "장부 발톱",
                "telegraph": "노려요.",
                "target": "front",
                "power": 1,
            }
        ],
    }


def _party_with(code: str | None) -> list[dict]:
    slots = (
        {
            "B1": {"source": "skillbook", "code": code},
            "B2": {"source": "emotion", "code": "emotion.primary"},
        }
        if code
        else None
    )
    return [
        _profile({"skill_loadout": {"slots": slots}} if slots else None),
        {
            **_profile(),
            "id": 2,
            "snapshot": {**_profile()["snapshot"], "name": "볕이"},
        },
    ]


def test_germination_gear_locks_skills_in_the_first_round():
    """집중력 +2를 받은 대원은 1라운드에 스킬을 쓸 수 없다."""

    from app.content.expeditions.combat import (
        CombatRuleError,
        new_guardian_battle,
        submit_guardian_action,
    )

    encounter = _encounter_fixture()
    profiles = _party_with("germination_gear")
    battle = new_guardian_battle("gear", encounter, profiles)
    assert battle["skill_book_opening"]["first_round_skill_locked"] == [1]

    for action in ("unique_1", "unique_2", "selected_1", "selected_2"):
        try:
            submit_guardian_action(
                battle, {"member_id": 1, "action": action}, encounter, profiles
            )
        except CombatRuleError as error:
            assert error.code == "EXPEDITION_COMBAT_FIRST_ROUND_SKILL_LOCKED"
        else:  # pragma: no cover - 반대급부가 없으면 이득만 남는다
            raise AssertionError(f"{action}이 1라운드에 통과했습니다")

    # 밸런스 불변식 — 최소 한 행동은 언제나 합법이어야 한다.
    for action in ("attack", "guard"):
        fresh = new_guardian_battle("gear", encounter, profiles)
        assert submit_guardian_action(
            fresh, {"member_id": 1, "action": action}, encounter, profiles
        )

    # 대가를 지지 않은 다른 대원은 1라운드에도 자유롭다.
    assert submit_guardian_action(
        new_guardian_battle("gear", encounter, profiles),
        {"member_id": 2, "action": "unique_1"},
        encounter,
        profiles,
    )


def test_germination_gear_lock_lifts_after_the_first_round():
    """반대급부는 1라운드까지다. 그 뒤에는 평소처럼 쓴다."""

    from app.content.expeditions.combat import new_guardian_battle, submit_guardian_action

    encounter = _encounter_fixture()
    profiles = _party_with("germination_gear")
    state = new_guardian_battle("gear", encounter, profiles)
    for member_id in (1, 2):
        state = submit_guardian_action(
            state, {"member_id": member_id, "action": "attack"}, encounter, profiles
        )
    assert int(state["round"]) >= 2
    assert submit_guardian_action(
        state, {"member_id": 1, "action": "unique_1"}, encounter, profiles
    )


def test_bellringer_chime_pays_with_a_lower_focus_cap():
    """라운드 +1을 받은 대신 그 전투의 집중력 최대치가 1 줄어든다."""

    from app.content.expeditions.combat import new_guardian_battle, submit_guardian_action

    encounter = _encounter_fixture()
    bare = new_guardian_battle("bare", encounter, _party_with(None))
    profiles = _party_with("bellringer_chime")
    chimed = new_guardian_battle("chime", encounter, profiles)

    assert chimed["max_rounds"] == bare["max_rounds"] + 1
    assert chimed["max_focus"] == bare["max_focus"] - 1

    # 줄어든 상한이 실제 판정에서도 지켜진다. 지키기로 집중력을 계속 모아도
    # 원래 상한(5)까지 오르지 않는다.
    state = chimed
    for _ in range(3):
        if state.get("status") != "active":
            break
        for member_id in (1, 2):
            state = submit_guardian_action(
                state, {"member_id": member_id, "action": "guard"}, encounter, profiles
            )
    assert int(state["focus"]) <= int(chimed["max_focus"])
    assert int(chimed["max_focus"]) == 4


def _party_book(code: str) -> list[dict]:
    return [
        _profile(
            {
                "skill_loadout": {
                    "slots": {
                        "B1": {"source": "skillbook", "code": code},
                        "B2": {"source": "emotion", "code": "emotion.primary"},
                    }
                }
            }
        ),
        {
            **_profile(),
            "id": 2,
            "snapshot": {**_profile()["snapshot"], "name": "볕이"},
        },
    ]


def _battle_with(code: str, encounter: dict, profiles: list[dict], focus: int):
    """집중력에 여유를 둔 전투를 만든다.

    Lv30 파티는 시작 집중력이 이미 상한이라 +1이 상한에 먹혀 보이지 않는다.
    트리거가 실제로 더해지는지 보려면 여유가 있어야 한다.
    """

    from app.content.expeditions.combat import new_guardian_battle

    state = new_guardian_battle(code, encounter, profiles)
    state["focus"] = focus
    return state


def test_bracing_adds_one_focus_on_guard_once_per_battle():
    """전투 1회 — 두 번째 방어에는 더 붙지 않는다."""

    from app.content.expeditions.combat import submit_guardian_action

    encounter = _encounter_fixture()
    bare_profiles = _party_book("clear_aim")
    book_profiles = _party_book("bracing")

    bare = submit_guardian_action(
        _battle_with("bare", encounter, bare_profiles, 0),
        {"member_id": 1, "action": "guard"},
        encounter,
        bare_profiles,
    )
    braced = submit_guardian_action(
        _battle_with("braced", encounter, book_profiles, 0),
        {"member_id": 1, "action": "guard"},
        encounter,
        book_profiles,
    )
    # 지키기 기본 +1에 버티는 자세 +1이 더해진다.
    assert bare["focus"] == 1
    assert braced["focus"] == 2

    # 같은 대원이 다시 방어해도 이번에는 기본 +1뿐이다.
    second = submit_guardian_action(
        braced, {"member_id": 2, "action": "guard"}, encounter, book_profiles
    )
    third = submit_guardian_action(
        second, {"member_id": 1, "action": "guard"}, encounter, book_profiles
    )
    assert third["focus"] - second["focus"] == 1


def test_focus_knot_refunds_one_focus_after_a_skill():
    """스킬 비용을 낸 뒤 한 칸 돌려받는다. 비용 판정은 느슨해지지 않는다."""

    from app.content.expeditions.combat import (
        CombatRuleError,
        submit_guardian_action,
    )

    encounter = _encounter_fixture()
    bare_profiles = _party_book("clear_aim")
    book_profiles = _party_book("focus_knot")

    bare = submit_guardian_action(
        _battle_with("bare", encounter, bare_profiles, 3),
        {"member_id": 1, "action": "unique_1"},
        encounter,
        bare_profiles,
    )
    knotted = submit_guardian_action(
        _battle_with("knot", encounter, book_profiles, 3),
        {"member_id": 1, "action": "unique_1"},
        encounter,
        book_profiles,
    )
    assert knotted["focus"] == bare["focus"] + 1

    # 집중력이 모자라면 트리거가 있어도 쓸 수 없다.
    poor = _battle_with("poor", encounter, book_profiles, 0)
    try:
        submit_guardian_action(
            poor, {"member_id": 1, "action": "unique_1"}, encounter, book_profiles
        )
    except CombatRuleError as error:
        assert "집중력" in error.message
    else:  # pragma: no cover
        raise AssertionError("비용 판정이 트리거로 느슨해졌습니다")


def test_a_fired_trigger_is_remembered_in_the_battle_state():
    """저장된 런을 이어서 해도 같은 책이 두 번 터지지 않는다."""

    from app.content.expeditions.combat import submit_guardian_action

    encounter = _encounter_fixture()
    profiles = _party_book("bracing")
    state = submit_guardian_action(
        _battle_with("memory", encounter, profiles, 0),
        {"member_id": 1, "action": "guard"},
        encounter,
        profiles,
    )
    assert state["skill_book_triggers"] == {"1:bracing": True}


def test_command_book_becomes_a_real_action_with_grade_priced_focus():
    """7.5.1 — 대원 행동 1회를 쓰고, 비용은 등급을 따르며, 전투당 한 번이다."""

    from app.content.expeditions.combat import member_battle_kit

    kit = member_battle_kit(
        _profile(
            {
                "skill_loadout": {
                    "slots": {
                        "B1": {"source": "skillbook", "code": "short_cheer"},
                        "B2": {"source": "emotion", "code": "emotion.primary"},
                    }
                }
            }
        )
    )
    slot = next(
        item for item in kit["selected_skills"] if item["slot"] == "selected_1"
    )
    assert slot["available"] is True
    assert slot["lock_reason"] is None
    assert slot["code"] == "short_cheer"
    assert slot["name"] == "짧은 격려"
    # 1등급은 집중력 0으로 쓴다.
    assert slot["focus_cost"] == 0
    # 기록서는 피해를 주지 않는 지원 도구다.
    assert slot["power"] == 0
    # 전투당 1회 — 최대 라운드보다 긴 쿨타임으로 표현한다.
    assert slot["cooldown_turns"] > 7
    assert slot["equipped_book"]["grade"] == 1


def test_short_cheer_heals_exactly_one_and_never_scales():
    """정액 계약 — 어떤 캐릭터가 써도 정확히 1만 회복한다."""

    from app.content.expeditions.combat import (
        new_guardian_battle,
        submit_guardian_action,
    )

    encounter = _encounter_fixture()
    profiles = _party_book("short_cheer")
    for stats, rarity, level in (
        ({"care": 3, "focus": 3, "courage": 3, "insight": 3}, 1, 9),
        ({"care": 9, "focus": 9, "courage": 9, "insight": 9}, 5, 30),
    ):
        profiles[0]["snapshot"].update(
            {"stats": stats, "rarity": rarity, "level": level}
        )
        state = new_guardian_battle("cheer", encounter, profiles)
        # 회복을 확인하려면 다친 대원이 있어야 한다.
        state["party"][1]["hp"] = 1
        healed = submit_guardian_action(
            state, {"member_id": 1, "action": "selected_1"}, encounter, profiles
        )
        assert healed["party"][1]["hp"] == 2, (stats, rarity, level)


def test_short_cheer_can_only_be_used_once_per_battle():
    from app.content.expeditions.combat import (
        CombatRuleError,
        new_guardian_battle,
        submit_guardian_action,
    )

    encounter = _encounter_fixture()
    profiles = _party_book("short_cheer")
    state = new_guardian_battle("once", encounter, profiles)
    state["party"][1]["hp"] = 1
    state = submit_guardian_action(
        state, {"member_id": 1, "action": "selected_1"}, encounter, profiles
    )
    state = submit_guardian_action(
        state, {"member_id": 2, "action": "guard"}, encounter, profiles
    )
    try:
        submit_guardian_action(
            state, {"member_id": 1, "action": "selected_1"}, encounter, profiles
        )
    except CombatRuleError as error:
        assert error.code == "EXPEDITION_COMBAT_COOLDOWN"
        # 전투당 1회짜리는 남은 턴 수 대신 이 전투에서 끝났다고 알려 준다.
        assert "이 전투에서 한 번만" in error.message
        assert "턴 뒤" not in error.message
    else:  # pragma: no cover - 전투당 1회 계약 위반
        raise AssertionError("같은 전투에서 두 번 사용됐습니다")


def test_books_without_a_mechanic_stay_locked_and_say_so():
    """효과가 없는 command 책은 누를 수 없다. 있는 척하지 않는다."""

    from app.content.expeditions.combat import member_battle_kit

    kit = member_battle_kit(
        _profile(
            {
                "skill_loadout": {
                    "slots": {
                        "B1": {"source": "skillbook", "code": "nine_tail_afterimage"},
                        "B2": {"source": "emotion", "code": "emotion.primary"},
                    }
                }
            }
        )
    )
    slot = next(
        item for item in kit["selected_skills"] if item["slot"] == "selected_1"
    )
    assert slot["available"] is False
    assert slot["lock_reason"] == "효과를 준비하고 있어요"
    assert slot["equipped_book"]["code"] == "nine_tail_afterimage"


def test_reviving_root_brings_one_downed_member_back_at_one_hp():
    """설계서 7.4 — HP 0 대원 1명을 HP 1로 복귀. 정액이다."""

    from app.content.expeditions.combat import (
        new_guardian_battle,
        submit_guardian_action,
    )

    encounter = _encounter_fixture()
    profiles = _party_book("reviving_root")
    for stats, rarity in (
        ({"care": 3, "focus": 3, "courage": 3, "insight": 3}, 1),
        ({"care": 9, "focus": 9, "courage": 9, "insight": 9}, 5),
    ):
        profiles[0]["snapshot"].update({"stats": stats, "rarity": rarity})
        state = new_guardian_battle("revive", encounter, profiles)
        state["party"][1]["hp"] = 0
        revived = submit_guardian_action(
            state, {"member_id": 1, "action": "selected_1"}, encounter, profiles
        )
        # 어떤 캐릭터가 써도 정확히 1로 돌아온다. 능력치로 자라지 않는다.
        assert revived["party"][1]["hp"] == 1, (stats, rarity)


def test_reviving_root_costs_one_focus_as_a_grade_two_book():
    from app.content.expeditions.combat import member_battle_kit

    kit = member_battle_kit(
        _profile(
            {
                "skill_loadout": {
                    "slots": {
                        "B1": {"source": "skillbook", "code": "reviving_root"},
                        "B2": {"source": "emotion", "code": "emotion.primary"},
                    }
                }
            }
        )
    )
    slot = next(
        item for item in kit["selected_skills"] if item["slot"] == "selected_1"
    )
    assert slot["available"] is True
    # 7.5.1 — 2등급 command는 집중력 1이다.
    assert slot["focus_cost"] == 1


def test_double_leaf_carries_one_guard_into_the_next_round():
    """지키기 잔여 방어 1칸만 넘어간다. 나머지는 평소대로 사라진다."""

    from app.content.expeditions.combat import _begin_round_if_needed

    encounter = _encounter_fixture()
    profiles = _party_book("double_leaf")
    from app.content.expeditions.combat import new_guardian_battle

    state = new_guardian_battle("carry", encounter, profiles)
    assert state["skill_book_opening"]["guard_carry"] == {"1": 1}

    # 라운드가 끝난 상태를 만든다.
    state["pending"] = None
    state["party"][0]["guard"] = 3
    state["party"][1]["guard"] = 3
    _begin_round_if_needed(state)

    # 책을 든 대원만 1칸을 가져간다.
    assert state["party"][0]["guard"] == 1
    assert state["party"][1]["guard"] == 0


def test_double_leaf_cannot_carry_more_than_is_left():
    """남은 방어가 없으면 이월할 것도 없다."""

    from app.content.expeditions.combat import (
        _begin_round_if_needed,
        new_guardian_battle,
    )

    encounter = _encounter_fixture()
    profiles = _party_book("double_leaf")
    state = new_guardian_battle("carry-none", encounter, profiles)
    state["pending"] = None
    state["party"][0]["guard"] = 0
    _begin_round_if_needed(state)
    assert state["party"][0]["guard"] == 0


def test_a_party_without_the_book_never_carries_guard():
    from app.content.expeditions.combat import (
        _begin_round_if_needed,
        new_guardian_battle,
    )

    encounter = _encounter_fixture()
    profiles = _party_book("clear_aim")
    state = new_guardian_battle("no-carry", encounter, profiles)
    assert state["skill_book_opening"]["guard_carry"] == {}
    state["pending"] = None
    state["party"][0]["guard"] = 3
    _begin_round_if_needed(state)
    assert state["party"][0]["guard"] == 0


def test_echo_read_opens_the_next_round_intent_for_one_round():
    """전투 1회, 다음 라운드 예고를 미리 본다. 쓰지 않으면 나타나지 않는다."""

    from app.content.expeditions.combat import (
        guardian_battle_payload,
        new_guardian_battle,
        submit_guardian_action,
    )

    # 예고가 하나뿐인 적은 `다음 예고`도 같은 행동이라 미리 봐야 의미가 없다.
    # 두 예고를 번갈아 쓰는 적으로 확인한다.
    encounter = _encounter_fixture()
    encounter["intents"] = [
        *encounter["intents"],
        {
            "code": "wave",
            "name": "기록 파동",
            "telegraph": "모두를 노려요.",
            "target": "all",
            "power": 1,
        },
    ]
    profiles = _party_book("echo_read")

    plain = new_guardian_battle("plain", encounter, profiles)
    assert guardian_battle_payload(plain, encounter, profiles)["enemy"]["next_intent"] is None

    used = submit_guardian_action(
        plain, {"member_id": 1, "action": "selected_1"}, encounter, profiles
    )
    payload = guardian_battle_payload(used, encounter, profiles)
    preview = payload["enemy"]["next_intent"]
    assert preview is not None
    # 지금 예고와 다음 예고는 서로 다른 행동이다.
    assert preview["code"] != payload["enemy"]["intent"]["code"]
    # 예고를 읽는 데 필요한 정보가 함께 온다.
    assert preview["telegraph"]
    assert preview["target"] in {"front", "lowest", "all"}


def test_weakness_engrave_lands_only_on_a_weakness_hit_and_once():
    """기다리던 +3은 약점을 실제로 맞힌 공격에만, 한 번만 실린다."""

    from app.content.expeditions.combat import new_guardian_battle
    from app.content.expeditions.skill_book_effects import (
        book_state,
        take_weakness_bonus,
    )

    encounter = _encounter_fixture()
    state = new_guardian_battle("engrave", encounter, _party_book("weakness_engrave"))

    # 아직 쓰지 않았으면 실릴 것이 없다.
    assert take_weakness_bonus(state) == 0

    book_state(state)["weakness_bonus"] = 3
    # 처음 약점 공격이 가져가고,
    assert take_weakness_bonus(state) == 3
    # 그 뒤로는 남지 않는다.
    assert take_weakness_bonus(state) == 0


def test_choice_needing_books_are_declared_but_not_wired():
    """선택을 받아야 하는 책은 계약만 적어 두고 열지 않는다."""

    from app.content.expeditions.skill_book_effects import (
        CHOICE_REQUIRED,
        COMMAND_ACTIONS,
    )

    from app.content.expeditions.skill_book_effects import choice_kind

    for code in CHOICE_REQUIRED:
        assert SKILL_BOOK_CATALOG[code]["activation_mode"] == "command"
        if code in COMMAND_ACTIONS:
            # 열린 책은 무엇을 고르는지 반드시 밝혀야 한다. 고를 것을 모르면
            # 앱이 선택지를 만들 수 없고 사용자가 막힌다.
            assert choice_kind(code), code
            assert SKILL_BOOK_CATALOG[code]["combat_effect"] is True, code
        else:
            # 아직 안 연 책은 효과를 주장하지 않는다.
            assert SKILL_BOOK_CATALOG[code]["combat_effect"] is False, code


def _kel_encounter() -> dict:
    """성장결 약점이 실제로 있는 교전.

    기본 교전 fixture는 `weak_element`가 없어 모든 공격이 neutral이다. 조율기는
    상성을 바꾸는 책이라 바꿀 상성이 있어야 검증이 된다. 기본 캐릭터의 결이
    `sunny`이므로 약점을 `fire`(=ember)로 두면 고르기 전과 후가 갈린다.
    """

    return {**_encounter_fixture(), "weak_element": "fire"}


def test_resonance_tuner_shows_what_there_is_to_choose():
    """앱이 선택지를 스스로 만들지 않도록 서버가 후보까지 내려보낸다."""

    from app.content.expeditions.combat import member_battle_kit
    from app.content.expeditions.skill_book_effects import CHOICE_KELS

    kit = member_battle_kit(_party_book("resonance_tuner")[0])
    slot = [item for item in kit["selected_skills"] if item["slot"] == "selected_1"][0]

    assert slot["choice_kind"] == "kel"
    assert [option["value"] for option in slot["choice_options"]] == list(CHOICE_KELS)
    # 이름표까지 함께 준다. 앱이 코드→한글 표를 따로 들고 있으면 어긋난다.
    assert all(option["label"] for option in slot["choice_options"])

    # 고를 것이 없는 책은 빈 목록이라 앱이 선택 화면을 띄우지 않는다.
    plain = member_battle_kit(_party_book("short_cheer")[0])
    plain_slot = [
        item for item in plain["selected_skills"] if item["slot"] == "selected_1"
    ][0]
    assert plain_slot["choice_kind"] is None
    assert plain_slot["choice_options"] == []


def test_resonance_tuner_rejects_a_missing_or_pointless_choice():
    """고르지 않았거나 지금과 같은 결이면 집중력을 쓰기 전에 막는다."""

    import pytest

    from app.content.expeditions.combat import (
        CombatRuleError,
        new_guardian_battle,
        submit_guardian_action,
    )

    encounter = _kel_encounter()
    profiles = _party_book("resonance_tuner")

    for bad in (None, "", "ember_x", "sunny"):
        state = new_guardian_battle("tune", encounter, profiles)
        before = int(state["focus"])
        command = {"member_id": 1, "action": "selected_1"}
        if bad is not None:
            command["choice"] = bad
        with pytest.raises(CombatRuleError) as caught:
            submit_guardian_action(state, command, encounter, profiles)
        assert caught.value.code == "EXPEDITION_COMBAT_CHOICE_REQUIRED"
        # 막힌 명령은 집중력을 가져가지 않는다.
        assert int(state["focus"]) == before


def test_resonance_tuner_changes_the_next_attack_and_then_lets_go():
    """고른 결은 다음 공격 하나에만 실리고, 그 뒤에는 원래대로 돌아온다."""

    from app.content.expeditions.combat import (
        guardian_battle_payload,
        new_guardian_battle,
        submit_guardian_action,
    )

    encounter = _kel_encounter()
    profiles = _party_book("resonance_tuner")
    state = new_guardian_battle("tune", encounter, profiles)

    def basic_of(current: dict) -> dict:
        member = guardian_battle_payload(current, encounter, profiles)["party"][0]
        return member["kit"]["basic"]

    plain = basic_of(state)
    assert plain["kel"] == "sunny"
    assert plain["matchup"] == "neutral"

    state = submit_guardian_action(
        state,
        {"member_id": 1, "action": "selected_1", "choice": "ember"},
        encounter,
        profiles,
    )

    tuned = basic_of(state)
    # 확정 전에 바뀐 상성과 늘어난 예상 피해가 그대로 보인다.
    assert tuned["kel"] == "ember"
    assert tuned["matchup"] == "weak"
    assert tuned["power"] > plain["power"]

    state = submit_guardian_action(
        state, {"member_id": 2, "action": "attack"}, encounter, profiles
    )
    # 다른 대원이 때려도 내 결은 그대로 남아 있다. 조율은 나에게 건 것이다.
    assert basic_of(state)["kel"] == "ember"

    state = submit_guardian_action(
        state, {"member_id": 1, "action": "attack"}, encounter, profiles
    )
    # 한 번 쓰고 나면 원래 결로 돌아온다.
    assert basic_of(state)["kel"] == "sunny"
    assert basic_of(state)["matchup"] == "neutral"


def test_resonance_tuner_is_a_once_per_battle_command():
    """조율기도 전투 1회다. 매 라운드 상성을 갈아 끼우지 못한다."""

    import pytest

    from app.content.expeditions.combat import (
        CombatRuleError,
        new_guardian_battle,
        submit_guardian_action,
    )

    encounter = _kel_encounter()
    profiles = _party_book("resonance_tuner")
    state = new_guardian_battle("tune", encounter, profiles)
    state = submit_guardian_action(
        state,
        {"member_id": 1, "action": "selected_1", "choice": "ember"},
        encounter,
        profiles,
    )
    state = submit_guardian_action(
        state, {"member_id": 2, "action": "attack"}, encounter, profiles
    )
    with pytest.raises(CombatRuleError) as caught:
        submit_guardian_action(
            state,
            {"member_id": 1, "action": "selected_1", "choice": "rainy"},
            encounter,
            profiles,
        )
    assert caught.value.code == "EXPEDITION_COMBAT_COOLDOWN"
    assert "한 번만" in caught.value.message
