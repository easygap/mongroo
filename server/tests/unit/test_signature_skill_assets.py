import json
from pathlib import Path

from app.content.expeditions.combat import (
    SPECIES_SECONDARY_SKILLS,
    SPECIES_SKILLS,
    member_battle_kit,
)
from app.content.expeditions.combat_identity import EMOTION_DISCIPLINES


REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
EFFECT_ROOT = REPOSITORY_ROOT / "app" / "assets" / "adventure" / "effects"
ICON_ROOT = REPOSITORY_ROOT / "app" / "assets" / "adventure" / "skill-icons"


def _profile(species: str, level: int) -> dict:
    return {
        "id": 1,
        "position": 0,
        "is_guide": False,
        "snapshot": {
            "name": "전수 검수",
            "species": {"code": species},
            "form": "sunny",
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
