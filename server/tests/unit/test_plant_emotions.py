from types import SimpleNamespace

import pytest

from app.models.enums import AnalysisStatus, PlantStatus
from app.services.plants import (
    build_emotion_profile,
    build_growth_traits,
    emotion_for_entry,
    final_form_from_profile,
    growth_visual_payload,
    is_harvestable,
    growth_state_payload,
    museum_plant_payload,
    plant_payload,
    resolve_growth_branch,
)


def entry(
    *,
    content="오늘 마음을 적은 일기",
    mood_level=3,
    tags=None,
    override=None,
    ai_emotion=None,
    ai_scores=None,
    status=AnalysisStatus.NOT_REQUESTED,
    hidden=False,
):
    return SimpleNamespace(
        content=content,
        mood_level=mood_level,
        emotion_tags=tags or [],
        ai_emotion_override=override,
        ai_emotion=ai_emotion,
        ai_scores=ai_scores,
        analysis_status=status,
        ai_label_hidden=hidden,
    )


@pytest.mark.parametrize(
    ("record", "expected"),
    [
        (entry(ai_emotion="상처", status=AnalysisStatus.SUCCEEDED), "sadness"),
        (entry(ai_emotion="분노", status=AnalysisStatus.SUCCEEDED), "anger"),
        (entry(ai_emotion="불안", status=AnalysisStatus.SUCCEEDED), "anxiety"),
        (entry(ai_emotion="당황", status=AnalysisStatus.SUCCEEDED), "surprise"),
        (entry(ai_emotion="uncertain", status=AnalysisStatus.SUCCEEDED), "mixed"),
        (entry(content=None, ai_emotion="기쁨", status=AnalysisStatus.SUCCEEDED), None),
        (entry(ai_emotion="기쁨", status=AnalysisStatus.PENDING), None),
        (entry(ai_emotion="새 감정", status=AnalysisStatus.SUCCEEDED), None),
    ],
)
def test_only_succeeded_diary_classifier_result_is_growth_evidence(record, expected):
    assert emotion_for_entry(record) == expected


def test_direct_inputs_override_and_hidden_setting_never_change_growth_emotion():
    record = entry(
        mood_level=1,
        tags=["슬픔"],
        override="분노",
        ai_emotion="기쁨",
        status=AnalysisStatus.SUCCEEDED,
        hidden=True,
    )
    assert emotion_for_entry(record) == "joy"


def test_profile_counts_evidence_pending_unavailable_and_empty_separately():
    profile = build_emotion_profile(
        [
            entry(ai_emotion="기쁨", status=AnalysisStatus.SUCCEEDED),
            entry(ai_emotion="기쁨", status=AnalysisStatus.SUCCEEDED, mood_level=1),
            entry(ai_emotion="불안", status=AnalysisStatus.SUCCEEDED),
            entry(ai_emotion="분노", status=AnalysisStatus.PENDING),
            entry(ai_emotion="분노", status=AnalysisStatus.FAILED),
            entry(content="", status=AnalysisStatus.NOT_REQUESTED),
        ]
    )
    assert profile == {
        "version": 3,
        "source": "diary_text_analysis_scores",
        "total": 3,
        "pending_count": 1,
        "unavailable_count": 1,
        "empty_count": 1,
        "counts": {
            "joy": 2,
            "sadness": 0,
            "anger": 0,
            "anxiety": 1,
            "surprise": 0,
            "mixed": 0,
        },
        "ratios": {
            "joy": 0.6667,
            "sadness": 0.0,
            "anger": 0.0,
            "anxiety": 0.3333,
            "surprise": 0.0,
            "mixed": 0.0,
        },
        "weights": {
            "joy": 2.0,
            "sadness": 0.0,
            "anger": 0.0,
            "anxiety": 1.0,
            "surprise": 0.0,
            "mixed": 0.0,
        },
        "weighted_ratios": {
            "joy": 0.6667,
            "sadness": 0.0,
            "anger": 0.0,
            "anxiety": 0.3333,
            "surprise": 0.0,
            "mixed": 0.0,
        },
    }


def test_profile_accumulates_multiple_emotions_found_in_each_diary():
    profile = build_emotion_profile(
        [
            entry(
                ai_emotion="분노",
                ai_scores={"분노": 0.7, "불안": 0.2, "상처": 0.1},
                status=AnalysisStatus.SUCCEEDED,
            ),
            entry(
                ai_emotion="기쁨",
                ai_scores={"기쁨": 0.5, "분노": 0.3, "당황": 0.2},
                status=AnalysisStatus.SUCCEEDED,
            ),
        ]
    )

    assert profile["total"] == 2
    assert profile["counts"]["anger"] == 1
    assert profile["counts"]["joy"] == 1
    assert profile["weights"] == {
        "joy": 0.5,
        "sadness": 0.1,
        "anger": 1.0,
        "anxiety": 0.2,
        "surprise": 0.2,
        "mixed": 0.0,
    }
    assert profile["weighted_ratios"]["anger"] == 0.5


def test_uncertain_classifier_result_stays_mixed_despite_duplicate_label_family():
    profile = build_emotion_profile(
        [
            entry(
                ai_emotion="uncertain",
                ai_scores={
                    "기쁨": 0.167,
                    "슬픔": 0.167,
                    "분노": 0.167,
                    "불안": 0.167,
                    "상처": 0.166,
                    "당황": 0.166,
                },
                status=AnalysisStatus.SUCCEEDED,
            )
        ]
    )

    assert profile["counts"]["mixed"] == 1
    assert profile["weighted_ratios"]["mixed"] == 1.0
    assert profile["weighted_ratios"]["sadness"] == 0.0


def test_branch_uses_emotion_distribution_instead_of_primary_label_votes_only():
    nuanced = build_emotion_profile(
        [
            entry(
                ai_emotion="분노",
                ai_scores={"분노": 0.4, "기쁨": 0.35, "슬픔": 0.25},
                status=AnalysisStatus.SUCCEEDED,
            )
            for _ in range(3)
        ]
    )
    assert nuanced["counts"]["anger"] == 3
    assert resolve_growth_branch(nuanced, stage=3) is None

    clear = build_emotion_profile(
        [
            entry(
                ai_emotion="분노",
                ai_scores={"분노": 0.75, "불안": 0.15, "기쁨": 0.1},
                status=AnalysisStatus.SUCCEEDED,
            )
            for _ in range(3)
        ]
    )
    assert resolve_growth_branch(clear, stage=3) == "anger"


def test_growth_traits_reveal_primary_then_secondary_without_judging_user():
    nuanced = build_emotion_profile(
        [
            entry(
                ai_emotion="슬픔",
                ai_scores={"슬픔": 0.65, "당황": 0.2, "불안": 0.15},
                status=AnalysisStatus.SUCCEEDED,
            )
            for _ in range(4)
        ]
    )

    branching = build_growth_traits(nuanced, stage=3, branch="sadness")
    assert branching["reveal_state"] == "dominant_revealed"
    assert branching["dominant"]["persona_name"] == "빗물결"
    assert branching["secondary"] is None
    assert branching["temperament"]["revealed"] is False

    blooming = build_growth_traits(nuanced, stage=4, branch="sadness")
    assert blooming["reveal_state"] == "secondary_revealed"
    assert blooming["secondary"]["emotion"] == "surprise"
    assert blooming["secondary"]["ratio"] == 0.2
    assert blooming["title"] == "별빛 품은 빗물결"
    assert blooming["temperament"]["revealed"] is True
    assert blooming["fictional_character_profile"] is True
    assert blooming["user_personality_inference"] is False
    assert blooming["affects_growth_speed"] is False


def test_growth_traits_keep_small_secondary_signal_latent_until_it_is_meaningful():
    subtle = build_emotion_profile(
        [
            entry(
                ai_emotion="기쁨",
                ai_scores={"기쁨": 0.8, "슬픔": 0.13, "당황": 0.07},
                status=AnalysisStatus.SUCCEEDED,
            )
            for _ in range(4)
        ]
    )
    traits = build_growth_traits(subtle, stage=5, branch="joy")
    assert traits["dominant"]["emotion"] == "joy"
    assert traits["secondary"] is None


def test_growth_traits_do_not_reveal_temperament_before_branch_is_stable():
    ambiguous = build_emotion_profile(
        [
            entry(
                ai_emotion="uncertain",
                ai_scores={"기쁨": 0.5, "슬픔": 0.5},
                status=AnalysisStatus.SUCCEEDED,
            )
            for _ in range(4)
        ]
    )
    traits = build_growth_traits(ambiguous, stage=4, branch=None)
    assert traits["reveal_state"] == "awaiting_evidence"
    assert traits["dominant"] is None
    assert traits["secondary"] is None
    assert traits["temperament"]["revealed"] is False
    assert "일기 분석이 더 모이면" in traits["next_reveal"]


def profile(**counts):
    values = {
        key: counts.get(key, 0)
        for key in ("joy", "sadness", "anger", "anxiety", "surprise", "mixed")
    }
    total = sum(values.values())
    return {
        "version": 2,
        "total": total,
        "counts": values,
        "ratios": {
            key: value / total if total else 0.0 for key, value in values.items()
        },
    }


def test_branch_is_hidden_before_stage_three_and_requires_three_clear_samples():
    clear = profile(joy=3)
    assert resolve_growth_branch(clear, stage=2) is None
    assert resolve_growth_branch(profile(joy=2), stage=3) is None
    assert resolve_growth_branch(profile(joy=2, sadness=1), stage=3) == "joy"
    assert resolve_growth_branch(profile(joy=2, sadness=1, anger=1), stage=3) is None


def test_ambiguous_or_unavailable_full_bloom_previews_mosaic_before_harvest():
    ambiguous = {
        **profile(joy=2, sadness=1, anger=1),
        "pending_count": 0,
        "unavailable_count": 0,
    }
    assert resolve_growth_branch(ambiguous, stage=4) is None
    assert resolve_growth_branch(ambiguous, stage=5) is None
    plant = SimpleNamespace(
        status=PlantStatus.ACTIVE,
        exp=1000,
        growth_branch=None,
        final_form=None,
        emotion_profile=ambiguous,
    )
    state = growth_state_payload(plant)
    assert state["growth_branch"] == "mixed"
    assert state["growth_form"] == "mosaic"
    assert plant.growth_branch is None

    # preview mixed는 sticky하지 않아 후속 일기가 명확해지면 최초 기준으로 분기한다.
    clearer = profile(joy=3, sadness=2)
    assert (
        resolve_growth_branch(clearer, stage=5, current_branch=plant.growth_branch)
        == "joy"
    )


def test_existing_branch_uses_hysteresis_before_switching():
    # 약한 역전으로는 이미 드러난 외형/성격이 바뀌지 않는다.
    assert (
        resolve_growth_branch(profile(joy=3, sadness=4), stage=4, current_branch="joy")
        == "joy"
    )
    # 충분한 표본과 강한 우세가 생기면 새 생애 흐름을 반영한다.
    assert (
        resolve_growth_branch(profile(joy=1, sadness=6), stage=4, current_branch="joy")
        == "sadness"
    )


def test_branch_is_redecided_when_all_of_its_evidence_is_removed():
    assert (
        resolve_growth_branch(
            profile(joy=0, sadness=3, anxiety=2), stage=4, current_branch="joy"
        )
        == "sadness"
    )
    assert (
        resolve_growth_branch(
            profile(joy=0, sadness=2, anxiety=2), stage=4, current_branch="joy"
        )
        is None
    )


@pytest.mark.parametrize(
    ("counts", "expected"),
    [
        ({}, "mosaic"),
        ({"joy": 3}, "sunny"),
        ({"sadness": 3, "joy": 1}, "rainy"),
        ({"anger": 3, "joy": 1}, "ember"),
        ({"anxiety": 3, "sadness": 1}, "moonlit"),
        ({"surprise": 3, "mixed": 1}, "sparkling"),
        ({"joy": 1, "sadness": 1}, "mosaic"),
        ({"joy": 2, "sadness": 1, "anger": 1}, "mosaic"),
    ],
)
def test_final_form_uses_whole_lifecycle_clear_majority(counts, expected):
    assert final_form_from_profile(profile(**counts)) == expected


def test_final_form_freezes_the_last_stable_live_branch():
    # 수확 버튼만 눌렀다고 외형이 점프하지 않고 마지막 안정 분기를 보존한다.
    lifecycle = profile(joy=3, sadness=5)
    assert resolve_growth_branch(lifecycle, 5, "joy") == "joy"
    assert final_form_from_profile(lifecycle, "joy") == "sunny"


def test_legacy_museum_fallback_keeps_form_branch_and_persona_consistent():
    plant = SimpleNamespace(
        id=7,
        name="옛 표본",
        exp=1000,
        status=PlantStatus.HARVESTED,
        planted_at=None,
        harvested_at=None,
        final_form=None,
        emotion_profile=profile(sadness=3, joy=1),
        growth_branch=None,
        museum_featured=False,
    )
    species = SimpleNamespace(id=1, code="basic_sprout", name="새싹몬")
    payload = museum_plant_payload(plant, species)
    assert payload["final_form"] == "rainy"
    assert payload["growth_branch"] == "sadness"
    assert payload["growth_form"] == "rainy"
    assert payload["growth_persona"]["persona_name"] == "빗물결"
    assert payload["visual_key"] == "stage_5_rainy_sunny"
    assert payload["secondary_emotion"] == "joy"
    assert payload["dominant_form"] == "rainy"
    assert payload["secondary_form"] == "sunny"
    assert payload["temperament"]["fictional_character_axes"] is True
    assert payload["conversation_profile"]["question_style"]
    assert payload["growth_visual"]["secondary_accent_visible"] is True
    assert payload["growth_visual"]["secondary_asset_key"].endswith(
        "/accents/sunny/full_bloom"
    )


def test_museum_final_form_is_source_of_truth_for_inconsistent_legacy_branch():
    plant = SimpleNamespace(
        id=8,
        name="보정 표본",
        exp=1000,
        status=PlantStatus.HARVESTED,
        planted_at=None,
        harvested_at=None,
        final_form="rainy",
        emotion_profile=profile(joy=3),
        growth_branch="joy",
        museum_featured=False,
    )
    species = SimpleNamespace(id=1, code="basic_sprout", name="새싹몬")
    payload = museum_plant_payload(plant, species)
    assert payload["final_form"] == payload["growth_form"] == "rainy"
    assert payload["growth_branch"] == "sadness"


def test_species_growth_visual_starts_as_seed_and_uses_distinct_vessels():
    plant = SimpleNamespace(
        id=9,
        name="씨앗",
        exp=0,
        status=PlantStatus.ACTIVE,
        planted_at=None,
        harvested_at=None,
        final_form=None,
        emotion_profile=profile(anger=3),
        growth_branch="anger",
        museum_featured=False,
    )
    basic = SimpleNamespace(
        id=1,
        code="basic_sprout",
        name="새싹몬",
        rarity=1,
        asset_manifest={},
    )
    cactus = SimpleNamespace(
        id=2,
        code="cactus",
        name="가시니",
        rarity=2,
        asset_manifest={},
    )

    basic_payload = museum_plant_payload(
        SimpleNamespace(**{**plant.__dict__, "status": PlantStatus.HARVESTED}),
        basic,
    )
    seed_payload = plant_payload(plant, cactus)
    assert seed_payload["growth_branch"] is None
    assert seed_payload["growth_form"] is None
    assert seed_payload["growth_visual"]["phase"] == "seed"
    assert seed_payload["growth_visual"]["seed_visible"] is True
    assert seed_payload["growth_visual"]["branch_visible"] is False
    assert seed_payload["growth_visual"]["seed_shape"] == "spined_star_seed"
    assert seed_payload["growth_visual"]["vessel_style"] == "ribbed_desert_incubator"
    assert basic_payload["growth_visual"]["vessel_style"] == "round_terracotta_pot"


def test_unknown_species_uses_safe_generic_growth_identity():
    unknown = SimpleNamespace(
        id=99,
        code="future_species",
        name="미래 품종",
        rarity=5,
        asset_manifest={},
    )
    visual = growth_visual_payload(unknown, 1)
    assert visual["seed_shape"] == "round_seed"
    assert visual["vessel_style"] == "soft_terracotta_pot"
    assert visual["render_layers"] == [
        "plants/generic/vessels/soft_terracotta_pot",
        "plants/generic/seeds/round_seed",
    ]


def test_harvest_requires_three_analyses_and_no_pending_but_keeps_unavailable_fallback():
    plant = SimpleNamespace(status=PlantStatus.ACTIVE, exp=1000)
    plant.emotion_profile = {
        **profile(joy=2),
        "pending_count": 0,
        "unavailable_count": 0,
    }
    assert not is_harvestable(plant)

    plant.emotion_profile = {
        **profile(joy=3),
        "pending_count": 1,
        "unavailable_count": 0,
    }
    assert not is_harvestable(plant)

    plant.emotion_profile = {
        **profile(joy=3),
        "pending_count": 0,
        "unavailable_count": 0,
    }
    assert is_harvestable(plant)

    plant.emotion_profile = {**profile(), "pending_count": 0, "unavailable_count": 1}
    assert is_harvestable(plant)
