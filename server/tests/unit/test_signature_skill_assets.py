import json
from pathlib import Path

from app.content.expeditions.combat import (
    SPECIES_SECONDARY_SKILLS,
    SPECIES_SKILLS,
    member_battle_kit,
)
from app.content.expeditions.combat_identity import (
    EMOTION_DISCIPLINES,
    FORM_COMBAT_SKILLS,
)


REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
EFFECT_ROOT = REPOSITORY_ROOT / "app" / "assets" / "adventure" / "effects"
ICON_ROOT = REPOSITORY_ROOT / "app" / "assets" / "adventure" / "skill-icons"


def _profile(species: str, level: int, form: str = "sunny") -> dict:
    return {
        "id": 1,
        "position": 0,
        "is_guide": False,
        "snapshot": {
            "name": "전수 검수",
            "species": {"code": species},
            "form": form,
            "level": level,
            "rarity": 5,
            "stage": 5,
            "stats": {"care": 6, "focus": 6, "courage": 6, "insight": 6},
        },
    }


def _signature_definitions() -> list[tuple[str, dict]]:
    playable = sorted(set(SPECIES_SKILLS) - {"archive_guide"})
    return [
        *((species, SPECIES_SKILLS[species]) for species in playable),
        *((species, SPECIES_SECONDARY_SKILLS[species]) for species in playable),
    ]


def test_all_thirty_signature_skills_have_production_vfx_and_icons():
    manifest = json.loads((EFFECT_ROOT / "manifest.json").read_text(encoding="utf-8"))
    by_family = {entry["family"]: entry for entry in manifest["effects"]}
    definitions = _signature_definitions()

    assert len(definitions) == 30
    assert len({definition["code"] for _, definition in definitions}) == 30
    assert len({definition["vfx_family"] for _, definition in definitions}) == 30

    for species, definition in definitions:
        code = str(definition["code"])
        entry = by_family[str(definition["vfx_family"])]
        assert entry["production_ready"] is True, code
        assert entry["effect_keys"] == [code], code
        assert entry["frame_count"] >= 7, code
        directory = EFFECT_ROOT / str(entry["directory"])
        assert len(list(directory.glob("frame-*.webp"))) == entry["frame_count"], code
        icon = ICON_ROOT / species / f"{code.replace('_', '-')}-v1.webp"
        assert icon.is_file() and icon.stat().st_size > 2_000, code


def test_every_signature_gains_a_new_tactical_gimmick_at_t2_and_t3():
    for species in sorted(set(SPECIES_SKILLS) - {"archive_guide"}):
        tier_one = member_battle_kit(_profile(species, 15))["unique_skills"]
        tier_two = member_battle_kit(_profile(species, 16))["unique_skills"]
        tier_three = member_battle_kit(_profile(species, 25))["unique_skills"]
        for low, middle, high in zip(tier_one, tier_two, tier_three, strict=True):
            assert low["effect_values"] != middle["effect_values"], low["code"]
            assert middle["effect_values"] != high["effect_values"], low["code"]
            assert middle["audio_layer"] == "full", low["code"]
            assert high["audio_layer"] == "signature", low["code"]
            assert high["fusion_variant"], low["code"]
            assert high["fusion_production_ready"] is True, low["code"]


def test_all_six_emotion_fusion_layers_are_production_ready():
    manifest = json.loads((EFFECT_ROOT / "manifest.json").read_text(encoding="utf-8"))
    by_family = {entry["family"]: entry for entry in manifest["effects"]}
    assert set(EMOTION_DISCIPLINES) == {
        "sunny",
        "rainy",
        "ember",
        "moonlit",
        "sparkling",
        "mosaic",
    }
    for form in EMOTION_DISCIPLINES:
        entry = by_family[f"kel.{form}"]
        assert entry["production_ready"] is True, form
        assert (EFFECT_ROOT / entry["directory"] / "frame-00.webp").is_file()


def test_all_six_emotion_skills_have_their_own_vfx():
    """감정 스킬 여섯이 저마다의 연출을 쓴다.

    이 검사가 생기기 전까지 여섯 다 `emotion.*` family를 적어 두고도 그 family가
    manifest에 없어서, 앱이 성장결 공용 연출(`kel.*`)로 떨어뜨렸다. 서버가 보내는
    `effect_key`도 `prism_burst`처럼 **원소별** 공용 키였다 — 빛과 번개가 같은
    키라 `찬란한 하트`와 `경이의 전격`이 한 그림이었다.

    S3A의 `감정 스킬 6종 연출`이 이것이다.
    """

    manifest = json.loads((EFFECT_ROOT / "manifest.json").read_text(encoding="utf-8"))
    by_family = {entry["family"]: entry for entry in manifest["effects"]}

    assert len(FORM_COMBAT_SKILLS) == 6
    families = {str(skill["vfx_family"]) for skill in FORM_COMBAT_SKILLS.values()}
    assert len(families) == 6

    for form, skill in FORM_COMBAT_SKILLS.items():
        code = str(skill["code"])
        family = str(skill["vfx_family"])
        assert not family.startswith("kel."), code
        entry = by_family[family]
        assert entry["kel"] == form, code
        assert entry["effect_keys"] == [code], code
        assert entry["frame_count"] >= 8, code
        directory = EFFECT_ROOT / str(entry["directory"])
        assert len(list(directory.glob("frame-*.webp"))) == entry["frame_count"], code


def test_emotion_skills_send_their_own_effect_key_to_the_app():
    """전용 연출이 생겼으면 서버도 그 키를 보내야 한다.

    manifest만 채우고 서버가 계속 원소별 공용 키를 보내면, 앱은 family로 한 번
    더 찾아 주기는 해도 `effect_key` 경로로 들어오는 소리·타격 정지가 공용
    연출 쪽에 묶인다. 만들어 놓고 안 쓰는 상태가 조용히 남는다.
    """

    for form, skill in FORM_COMBAT_SKILLS.items():
        kit = member_battle_kit(_profile("baby-pot", 30, form=form))
        selected = [
            entry for entry in kit["selected_skills"] if entry["source"] == "emotion"
        ]
        assert selected, form
        for entry in selected:
            assert entry["code"] == skill["code"], form
            assert entry["effect_key"] == skill["code"], form
            assert entry["vfx_family"] == skill["vfx_family"], form
