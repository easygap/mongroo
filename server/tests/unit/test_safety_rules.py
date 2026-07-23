from app.ai import safety


def test_normal_text():
    result = safety.check_text("오늘은 산책을 해서 기분이 좋았다.")
    assert result.route == "normal"
    assert not result.flagged


def test_imminent_direct():
    result = safety.check_text("이제 자살하려고 준비를 다 해뒀어")
    assert result.route == "imminent"


def test_concern_passive():
    result = safety.check_text("요즘 자꾸 사라지고 싶다는 생각이 들어")
    assert result.route == "concern"


def test_self_harm_concern():
    assert safety.check_text("어제 또 자해를 했다").route == "concern"


def test_negation_softens():
    result = safety.check_text("죽고 싶다는 생각은 들지 않아요. 그냥 피곤할 뿐이에요.")
    assert result.route == "normal"
    assert "SOFTENED" in result.reason_codes


def test_quote_softens_but_not_imminent():
    # 인용이라도 즉각 위험 신호는 concern 밑으로 낮추지 않는다
    result = safety.check_text("친구가 '죽으려고 약을 모아서 먹겠다'라고 하더라")
    assert result.route == "concern"


def test_third_party_softens():
    result = safety.check_text("드라마 주인공이 죽고 싶다고 말하는 장면이 슬펐다")
    assert result.route == "normal"


def test_strong_everyday_anger_with_profanity_stays_normal():
    result = safety.check_text(
        "아 회사 동기 진짜 개빡치네 ㅅㅂ 오늘도 일을 나한테 개같이 맡겼어. "
        "진짜 죽이고 싶지만 내가 돈 벌어야 하니까 참는다."
    )

    assert result.route == "normal"


def test_non_actionable_violent_wish_is_not_treated_as_a_plan():
    result = safety.check_text("상사가 너무 억울하게 해서 죽이고 싶을 만큼 화가 난다.")

    assert result.route == "normal"


def test_targeted_future_violence_routes_to_concern():
    result = safety.check_text("오늘 퇴근하면 그 동료를 찾아가 죽일 거야.")

    assert result.route == "concern"
    assert "VIOLENCE_INTENT" in result.reason_codes


def test_declarative_violence_intent_routes_to_concern():
    result = safety.check_text("오늘 퇴근하고 회사 동기를 죽이겠다.")

    assert result.route == "concern"
    assert "VIOLENCE_INTENT" in result.reason_codes


def test_destructive_future_violence_intent_routes_to_concern():
    result = safety.check_text("내일 회사에 찾아가 그 동료를 죽여버릴 거야.")

    assert result.route == "concern"
    assert "VIOLENCE_INTENT" in result.reason_codes


def test_unrelated_absence_phrase_does_not_soften_later_violence_intent():
    result = safety.check_text(
        "망설임은 없다. 오늘 퇴근하면 그 동료를 찾아가 죽일 거야."
    )

    assert result.route == "concern"
    assert "SOFTENED" not in result.reason_codes


def test_unrelated_later_negation_does_not_soften_violence_intent():
    result = safety.check_text(
        "오늘 퇴근하면 그 동료를 죽일 거야. 점심을 거를 생각은 없어."
    )

    assert result.route == "concern"
    assert "SOFTENED" not in result.reason_codes


def test_third_party_in_previous_sentence_does_not_soften_self_harm_signal():
    result = safety.check_text("친구가 옆에 있었다. 나는 죽고 싶다.")

    assert result.route == "concern"
    assert "SOFTENED" not in result.reason_codes


def test_quoted_signal_does_not_soften_direct_plan_in_next_sentence():
    result = safety.check_text('친구가 "죽고 싶다"고 했다. 나는 자살하려고 준비했다.')

    assert result.route == "imminent"
    assert "SI_PLAN" in result.reason_codes


def test_weapon_and_action_plan_routes_to_imminent():
    result = safety.check_text("칼을 챙겨서 그 동료를 찌를 거야.")

    assert result.route == "imminent"
    assert "VIOLENCE_PLAN_MEANS" in result.reason_codes


def test_restraint_softens_future_violence_intent():
    result = safety.check_text(
        "그 동료를 죽일 거라고 생각했지만 실제로는 그러지 않고 참았다."
    )

    assert result.route == "normal"
    assert "VIOLENCE_RESTRAINT" in result.reason_codes


def test_violence_support_copy_does_not_condemn_anger():
    payload = safety.safety_action_payload("concern", ["VIOLENCE_INTENT"])

    assert payload["resources"][0]["phone"] == "112"
    assert "분노 자체를 잘못된 감정으로 판단하지 않아요" in payload["message"]


def test_softened_violence_does_not_hide_self_harm_concern():
    result = safety.check_text(
        "나는 죽고 싶고 동료를 죽일 거라고 생각했지만 그러지 않고 참았다."
    )

    assert result.route == "concern"
    assert "SI_PASSIVE" in result.reason_codes

    payload = safety.safety_action_payload(result.route, result.reason_codes)
    assert payload["resources"][0]["phone"] == "109"
    assert any(resource["phone"] == "1577-0199" for resource in payload["resources"])


def test_prior_state_keeps_concern():
    result = safety.check_text("오늘은 괜찮아", prior_state="concern")
    assert result.route == "concern"
    assert "PRIOR_STATE" in result.reason_codes


def test_prior_state_only_payload_keeps_neutral_emergency_resources():
    result = safety.check_text("오늘은 괜찮아", prior_state="concern")
    payload = safety.safety_action_payload(result.route, result.reason_codes)

    assert [item["phone"] for item in payload["resources"][:2]] == ["112", "119"]
    assert any(item["phone"] == "109" for item in payload["resources"])
    assert "본인이나 다른 사람" in payload["message"]


def test_prior_state_is_lower_bound_even_when_current_text_is_softened():
    result = safety.check_text("죽고 싶다는 생각은 들지 않아요.", prior_state="concern")
    assert result.route == "concern"
    assert "SOFTENED" in result.reason_codes
    assert "PRIOR_STATE" in result.reason_codes


def test_prior_imminent_state_does_not_downgrade():
    result = safety.check_text("지금은 괜찮아", prior_state="imminent")
    assert result.route == "imminent"
    assert "PRIOR_STATE" in result.reason_codes


def test_output_guard_bans_diagnosis():
    ok, codes = safety.guard_output("내가 보기에 너는 우울증이야. 약을 먹어야 해.")
    assert not ok
    assert "DIAGNOSIS" in codes


def test_output_guard_bans_false_reassurance():
    ok, codes = safety.guard_output("걱정 마, 반드시 좋아질 거야!")
    assert not ok
    assert "FALSE_REASSURANCE" in codes


def test_output_guard_bans_secrecy_and_avoidance():
    ok, codes = safety.guard_output("이건 우리만의 비밀이야. 병원은 갈 필요 없어.")
    assert not ok
    assert "SECRECY" in codes and "AVOID_HELP" in codes


def test_output_guard_passes_normal_reply():
    ok, codes = safety.guard_output("그랬구나. 오늘 어떤 일이 가장 마음에 남았어?")
    assert ok
    assert codes == []


def test_output_guard_rejects_empty():
    ok, codes = safety.guard_output("   ")
    assert not ok
