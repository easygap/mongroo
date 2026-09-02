import json
from pathlib import Path

from app.content.expeditions.combat import (
    SKILL_BOOK_CATALOG,
    SPECIES_SECONDARY_SKILLS,
    SPECIES_SKILLS,
    member_battle_kit,
)
from app.content.expeditions.combat_identity import (
    EMOTION_DISCIPLINES,
    FIELD_NOTE_SKILL,
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


def test_only_the_basic_attack_falls_back_to_a_shared_effect():
    """대원이 누를 수 있는 행동 중 공용 연출로 떨어지는 것은 기본 공격뿐이다.

    설계서 9장이 금지한 `공용 연출로 끝내는 것`을 한 줄로 지키는 검사다. 이걸
    안 걸어 두면 스킬이 늘 때마다 조용히 하나씩 공용 연출로 새고, 그건 실기에서
    네트워크 로그를 뒤져야 보인다(실제로 그렇게 찾았다).

    **기본 공격 6종은 일부러 뺀다.** 4.2가 그 자리를 `공격 glyph + 성장결`로
    정해 뒀다 — 거기서는 성장결 연출이 나가는 것이 맞다. 안 만든 것과 못 만든
    것을 같이 세지 않으려고 이름으로 적어 둔다.
    """

    manifest = json.loads((EFFECT_ROOT / "manifest.json").read_text(encoding="utf-8"))
    by_family = {entry["family"]: entry for entry in manifest["effects"]}

    # 성장결별 기본 공격. 설계상 성장결 공용 연출이 나가는 자리다.
    by_design = {
        str(discipline["basic_vfx_family"])
        for discipline in EMOTION_DISCIPLINES.values()
    }
    assert len(by_design) == 6

    families = {
        str(skill["vfx_family"])
        for skill in (
            *SPECIES_SKILLS.values(),
            *SPECIES_SECONDARY_SKILLS.values(),
            *FORM_COMBAT_SKILLS.values(),
            FIELD_NOTE_SKILL,
        )
    }
    missing = sorted(families - set(by_family) - by_design)
    assert missing == [], f"공용 연출로 떨어지는 행동이 남아 있습니다: {missing}"

    for family in sorted(families - by_design):
        entry = by_family[family]
        assert entry["production_ready"] is True, family
        assert entry["frame_count"] >= 7, family


def test_a_skill_book_keeps_the_effect_key_of_the_art_that_plays():
    """기록서를 장착해도 실제로 나가는 연출의 키가 간다.

    선택 슬롯은 기록서를 끼우면 **코드만** 그 책 것으로 바뀌고 연출은 바탕
    스킬 것을 그대로 물려받는다. 그래서 책 코드를 그대로 `effect_key`로 보내면
    manifest에 없는 키가 나가고, 앱은 family로 그림은 맞게 찾아도 키를 타는
    소리·타격 정지가 어긋난다.
    """

    manifest = json.loads((EFFECT_ROOT / "manifest.json").read_text(encoding="utf-8"))
    keys_by_family = {
        entry["family"]: entry["effect_keys"] for entry in manifest["effects"]
    }

    equipped = next(
        code
        for code, book in SKILL_BOOK_CATALOG.items()
        if book.get("combat_effect") is True
    )
    profile = _profile("baby-pot", 30)
    profile["snapshot"]["skill_loadout"] = {"selected_2": equipped}

    selected = member_battle_kit(profile)["selected_skills"]
    assert selected
    for entry in selected:
        family = str(entry["vfx_family"])
        # 연출이 있는 자리면, 보내는 키가 그 연출이 주장하는 키여야 한다.
        if family in keys_by_family:
            assert entry["effect_key"] in keys_by_family[family], family


def test_art_complete_means_the_whole_47_delivery_bundle_exists():
    """`art_complete:true`는 4.7이 요구한 일곱 가지가 다 있다는 뜻이어야 한다.

    4.7은 `RGBA master, 프레임 contact sheet, 0.25× onion-skin 영상, 실제 배경
    합성 영상, atlas/WebP, manifest, 프롬프트·참조 hash`를 한 묶음으로 요구하고
    `어느 하나가 없으면 art_complete=false`라고 적어 뒀다. 그런데 그 필드가
    manifest에 아예 없어서 아무도 그렇게 세지 않았다 — `production_ready`가
    이름값으로만 붙어 있던 것과 같은 종류의 일이다.

    이 검사는 **적어 둔 것이 실제로 있는지**만 본다. 파일을 지우거나 옮기면
    여기서 걸린다.
    """

    manifest = json.loads((EFFECT_ROOT / "manifest.json").read_text(encoding="utf-8"))

    for effect in manifest["effects"]:
        family = str(effect["family"])
        delivery = effect.get("delivery")
        assert delivery is not None, family
        for field in ("onion_025x", "on_backdrop"):
            path = REPOSITORY_ROOT / str(delivery[field])
            assert path.is_file(), f"{family}: {field}"
            assert path.stat().st_size > 2_000, f"{family}: {field}"
        if not effect.get("art_complete"):
            # 안 채워진 것은 왜 안 채워졌는지가 적혀 있어야 한다.
            assert delivery["missing"] or not effect["production_ready"], family
            continue
        assert delivery["missing"] == [], family
        assert delivery["prompt_sha256"], family
        assert delivery["reference_sha256"], family
        assert (REPOSITORY_ROOT / str(delivery["jobs_file"])).is_file(), family
        assert effect["production_ready"] is True, family


def test_every_effect_made_by_the_current_pipeline_is_art_complete():
    """지금 파이프라인으로 만든 것은 하나도 빠짐없이 묶음이 차 있어야 한다.

    프롬프트 기록이 없어 `art_complete`가 아닌 51종은 이 파이프라인이 생기기
    전에 다른 경로로 만들어진 것들이다. 그건 되살릴 수 없으니 그대로 둔다.
    다만 **`jobs*.json`이 있는 concept에서 나온 것은 전부 차 있어야** 한다 —
    앞으로 만드는 것이 조용히 빠지는 것을 여기서 막는다.
    """

    manifest = json.loads((EFFECT_ROOT / "manifest.json").read_text(encoding="utf-8"))
    jobs_ids: set[str] = set()
    for jobs_path in (REPOSITORY_ROOT / "design-system/concepts").glob("*/jobs*.json"):
        payload = json.loads(jobs_path.read_text(encoding="utf-8"))
        for job in payload.get("jobs", []):
            jobs_ids.add(str(job["id"]).replace("-", "_"))

    assert len(jobs_ids) >= 39
    covered = 0
    for effect in manifest["effects"]:
        keys = {str(key) for key in effect.get("effect_keys", [])}
        if not keys & jobs_ids:
            continue
        covered += 1
        assert effect["art_complete"] is True, effect["family"]
    assert covered == len(jobs_ids)
