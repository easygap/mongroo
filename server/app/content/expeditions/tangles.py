"""엉킴 12종 카탈로그 — 스테이지 전투의 상대.

개편 설계서(stage-battle-v2.0) 3.3의 계약을 코드로 옮긴다. 엉킴은 관리인의
손이 못 닿아 엉켜 버린 지역의 물건들이며, 전투는 무찌르기가 아니라 풀어 주기다.
그래서 처치·소멸 문구가 없고 장벽이 0이 되면 원래 물건으로 돌아간다.

지역당 3종(일반 2 + 큰 엉킴 1) × 4지역 = 12종. 아직 열리지 않은 지역의 엉킴도
여기 함께 정의해 이름·수치·문구의 단일 원본을 유지한다. 예고는 한 번에 1개이고
위력은 지역·난이도 밴드의 1~3 정수만 쓴다. 아래 validate가 이 범위를 지킨다.
"""

import copy
from typing import Any

from app.content.expeditions.combat_balance import validate_tangle_balance
from app.content.expeditions.combat_difficulty import validate_enemy_mechanic_code
from app.content.expeditions.combat_motion import combat_motion, kel_fallback_family


TANGLE_CATALOG: dict[str, dict[str, Any]] = {
    # ── 이끼 기억서고 ──────────────────────────────────────────────
    "tangled_ledger": {
        "region_code": "moss_archive",
        "name": "엉킨 장부 뭉치",
        "description": "분류하다 만 장부들이 실처럼 서로 얽혔어요.",
        "elite": False,
        "barrier": 34,
        "weakness_cycle": ["insight", "care", "courage", "focus"],
        "intents": [
            {
                "code": "paper_flurry",
                "name": "종잇장 회오리",
                "telegraph": "낱장들이 맨 앞 대원 쪽으로 몰려가요.",
                "target": "front",
                "power": 1,
            },
            {
                "code": "ink_mist",
                "name": "잉크 안개",
                "telegraph": "번진 잉크가 모두에게 퍼져요.",
                "target": "all",
                "power": 1,
            },
        ],
        "appear_caption": "엉킨 장부 뭉치가 길을 반쯤 막고 웅크렸어요.",
        "release_caption": "엉킨 장부가 스르르 풀려 제자리 서가로 돌아갔어요.",
    },
    "drifting_pressings": {
        "region_code": "moss_archive",
        "name": "표류 압화 떼",
        "description": "제자리를 잃은 압화가 무리 지어 떠다녀요.",
        "elite": False,
        "barrier": 38,
        "weakness_cycle": ["care", "insight", "focus", "courage"],
        "intents": [
            {
                "code": "petal_gust",
                "name": "꽃잎 돌풍",
                "telegraph": "마른 꽃잎이 모두를 향해 흩날려요.",
                "target": "all",
                "power": 1,
            },
            {
                "code": "petal_dart",
                "name": "꽃잎 살촉",
                "telegraph": "뾰족하게 모인 꽃잎이 지친 대원을 노려요.",
                "target": "lowest",
                "power": 1,
            },
        ],
        "appear_caption": "표류 압화 떼가 바람도 없이 몰려와 시야를 가려요.",
        "release_caption": "압화들이 풀려나 표본첩 갈피마다 얌전히 내려앉았어요.",
    },
    "shelf_snarl": {
        "region_code": "moss_archive",
        "name": "서가 뒤엉킴",
        "description": "선반과 목록이 통째로 엉켜 큰 매듭이 됐어요.",
        "elite": True,
        "barrier": 76,
        "weakness_cycle": ["courage", "focus", "insight", "care"],
        "intents": [
            {
                "code": "shelf_sweep",
                "name": "선반 휘두르기",
                "telegraph": "긴 선반 팔이 맨 앞 대원 쪽으로 기울어요.",
                "target": "front",
                "power": 2,
            },
            {
                "code": "catalogue_rain",
                "name": "목록 소나기",
                "telegraph": "목록 카드가 우수수 쏟아지려 해요.",
                "target": "all",
                "power": 1,
            },
        ],
        "appear_caption": "서가 뒤엉킴이 선반 세 칸을 끌어안은 채 버티고 섰어요.",
        "release_caption": "큰 매듭이 풀리며 선반들이 삐걱삐걱 제자리를 찾았어요.",
    },
    # ── 메아리 우물정원 ────────────────────────────────────────────
    "knotted_echo": {
        "region_code": "echo_well",
        "name": "매듭진 메아리",
        "description": "주인을 못 찾은 메아리가 서로 엉켜 웅웅거려요.",
        "elite": False,
        "barrier": 44,
        "weakness_cycle": ["focus", "care", "insight", "courage"],
        "intents": [
            {
                "code": "echo_ring",
                "name": "겹울림",
                "telegraph": "겹친 울림이 모두의 귓가로 번져요.",
                "target": "all",
                "power": 2,
            },
            {
                "code": "sharp_note",
                "name": "날카로운 한 음",
                "telegraph": "높은 음 하나가 맨 앞 대원을 겨눠요.",
                "target": "front",
                "power": 1,
            },
        ],
        "appear_caption": "매듭진 메아리가 우물가를 웅웅 울리며 떠올랐어요.",
        "release_caption": "매듭이 풀린 메아리가 저마다의 주인을 찾아 흩어졌어요.",
    },
    "splashing_droplets": {
        "region_code": "echo_well",
        "name": "튀는 물방울 떼",
        "description": "물길을 벗어난 물방울들이 신나게 튀어 다녀요.",
        "elite": False,
        "barrier": 50,
        "weakness_cycle": ["courage", "insight", "care", "focus"],
        "intents": [
            {
                "code": "splash_wave",
                "name": "물보라",
                "telegraph": "물방울들이 한꺼번에 튀어 오르려 해요.",
                "target": "all",
                "power": 2,
            },
            {
                "code": "water_pop",
                "name": "물방울 터뜨리기",
                "telegraph": "큰 방울 하나가 지친 대원 위에서 흔들려요.",
                "target": "lowest",
                "power": 1,
            },
        ],
        "appear_caption": "튀는 물방울 떼가 수로 밖으로 쏟아져 나왔어요.",
        "release_caption": "물방울들이 얌전해져 졸졸 제 물길로 돌아갔어요.",
    },
    "bell_knot_swirl": {
        "region_code": "echo_well",
        "name": "소용돌이 종매듭",
        "description": "종줄과 소리가 한데 감겨 큰 소용돌이가 됐어요.",
        "elite": True,
        "barrier": 96,
        "weakness_cycle": ["care", "courage", "focus", "insight"],
        "intents": [
            {
                "code": "bell_spin",
                "name": "종줄 휘감기",
                "telegraph": "감긴 종줄이 맨 앞 대원 쪽으로 풀려 나가요.",
                "target": "front",
                "power": 2,
            },
            {
                "code": "deep_toll",
                "name": "깊은 울림",
                "telegraph": "낮은 종소리가 바닥을 타고 모두에게 번져요.",
                "target": "all",
                "power": 2,
            },
        ],
        "appear_caption": "소용돌이 종매듭이 우물 위에서 크게 감돌기 시작했어요.",
        "release_caption": "종매듭이 풀리며 종들이 하나씩 맑은 제 소리를 되찾았어요.",
    },
    # ── 별빛 씨앗 보관고 ───────────────────────────────────────────
    "snarled_stardust": {
        "region_code": "starlight_seed_vault",
        "name": "뒤엉킨 별가루",
        "description": "선반을 벗어난 별가루가 실타래처럼 뭉쳤어요.",
        "elite": False,
        "barrier": 56,
        "weakness_cycle": ["insight", "focus", "care", "courage"],
        "intents": [
            {
                "code": "dust_flare",
                "name": "별가루 반짝임",
                "telegraph": "눈부신 가루가 모두의 앞을 가려요.",
                "target": "all",
                "power": 2,
            },
            {
                "code": "dust_lash",
                "name": "가루 채찍",
                "telegraph": "가늘게 꼰 별가루가 맨 앞 대원을 향해요.",
                "target": "front",
                "power": 2,
            },
        ],
        "appear_caption": "뒤엉킨 별가루가 반짝이며 길목을 메웠어요.",
        "release_caption": "별가루가 풀려나 선반 위 제 별자리로 돌아갔어요.",
    },
    "rolling_seedbox": {
        "region_code": "starlight_seed_vault",
        "name": "구르는 씨앗함",
        "description": "잠에서 덜 깬 씨앗함이 데굴데굴 굴러다녀요.",
        "elite": False,
        "barrier": 64,
        "weakness_cycle": ["care", "courage", "insight", "focus"],
        "intents": [
            {
                "code": "box_roll",
                "name": "돌진 구르기",
                "telegraph": "씨앗함이 맨 앞 대원 쪽으로 구를 준비를 해요.",
                "target": "front",
                "power": 2,
            },
            {
                "code": "seed_scatter",
                "name": "씨앗 흩뿌리기",
                "telegraph": "뚜껑 틈으로 씨앗이 모두에게 튀어요.",
                "target": "all",
                "power": 2,
            },
        ],
        "appear_caption": "구르는 씨앗함이 덜컹거리며 앞을 가로막았어요.",
        "release_caption": "씨앗함이 구르기를 멈추고 얌전히 제 선반에 올라갔어요.",
    },
    "backwound_clockspring": {
        "region_code": "starlight_seed_vault",
        "name": "거꾸로 선 시계태엽",
        "description": "발아 시계의 태엽이 거꾸로 감겨 튀어나왔어요.",
        "elite": True,
        "barrier": 120,
        "weakness_cycle": ["focus", "insight", "courage", "care"],
        "intents": [
            {
                "code": "spring_snap",
                "name": "태엽 튕기기",
                "telegraph": "감긴 태엽 끝이 맨 앞 대원을 향해 떨려요.",
                "target": "front",
                "power": 3,
            },
            {
                "code": "gear_grind",
                "name": "톱니 맞물림",
                "telegraph": "어긋난 톱니 소리가 모두를 짓눌러요.",
                "target": "all",
                "power": 2,
            },
        ],
        "appear_caption": "거꾸로 선 시계태엽이 째깍째깍 거슬러 돌기 시작했어요.",
        "release_caption": "태엽이 바로 감기며 발아 시계가 제 박자를 되찾았어요.",
    },
    # ── 마음나무 관측실 ────────────────────────────────────────────
    "ring_shard_tangle": {
        "region_code": "heartwood_observatory",
        "name": "얽힌 나이테 조각",
        "description": "떨어져 나온 나이테 조각들이 서로 얽혀 굴러요.",
        "elite": False,
        "barrier": 70,
        "weakness_cycle": ["courage", "care", "focus", "insight"],
        "intents": [
            {
                "code": "ring_spin",
                "name": "나이테 굴리기",
                "telegraph": "둥근 조각이 맨 앞 대원 쪽으로 기울어요.",
                "target": "front",
                "power": 2,
            },
            {
                "code": "shard_scatter",
                "name": "조각 흩날리기",
                "telegraph": "잔조각들이 모두에게 흩어지려 해요.",
                "target": "all",
                "power": 3,
            },
        ],
        "appear_caption": "얽힌 나이테 조각이 데구루루 굴러와 길을 막았어요.",
        "release_caption": "조각들이 풀려나 나이테 표본의 빈 겹을 채웠어요.",
    },
    "scattered_records": {
        "region_code": "heartwood_observatory",
        "name": "흩어진 기록 낱장",
        "description": "묶이지 못한 관측 기록이 낱장으로 흩날려요.",
        "elite": False,
        "barrier": 80,
        "weakness_cycle": ["insight", "courage", "care", "focus"],
        "intents": [
            {
                "code": "page_storm",
                "name": "낱장 폭풍",
                "telegraph": "기록 낱장이 모두의 시야를 덮으려 해요.",
                "target": "all",
                "power": 3,
            },
            {
                "code": "paper_cut",
                "name": "종이 모서리",
                "telegraph": "빳빳한 모서리가 지친 대원을 스치려 해요.",
                "target": "lowest",
                "power": 2,
            },
        ],
        "appear_caption": "흩어진 기록 낱장이 회오리처럼 일어났어요.",
        "release_caption": "낱장들이 차분히 내려앉아 한 권의 기록으로 묶였어요.",
    },
    "matted_observatory": {
        "region_code": "heartwood_observatory",
        "name": "헝클어진 관측기",
        "description": "렌즈와 줄자와 기록끈이 한 몸처럼 헝클어졌어요.",
        "elite": True,
        "barrier": 148,
        "weakness_cycle": ["insight", "care", "courage", "focus"],
        "intents": [
            {
                "code": "lens_glare",
                "name": "렌즈 눈부심",
                "telegraph": "굴절된 빛이 모두의 눈앞에서 번쩍이려 해요.",
                "target": "all",
                "power": 3,
            },
            {
                "code": "tape_whip",
                "name": "줄자 휘두르기",
                "telegraph": "긴 줄자가 맨 앞 대원 쪽으로 풀려 나가요.",
                "target": "front",
                "power": 3,
            },
        ],
        "appear_caption": "헝클어진 관측기가 삐걱대며 몸을 일으켰어요.",
        "release_caption": "관측기가 말끔히 풀려 다시 하늘 쪽으로 렌즈를 돌렸어요.",
    },
}


# 접촉 재질 — `design-system/ADVENTURE_AUDIO.md`의 `contact-{재질}` 6종 중
# guard를 뺀 5종이다. guard는 엉킴이 아니라 우리 쪽 방어가 만드는 소리라
# 카탈로그가 아니라 앱이 방어 결과에서 고른다. 색·이름이 아니라 "무엇에 닿았나"를
# 귀로 구분하게 하는 값이므로 VFX family와 별개로 관리한다.
CONTACT_MATERIALS = ("leaf", "paper", "water", "wood", "stone")

# 엉킴 몸체의 재질 — 우리 공격이 닿는 대상이다.
TANGLE_CONTACT_MATERIAL: dict[str, str] = {
    "tangled_ledger": "paper",
    "drifting_pressings": "leaf",
    "shelf_snarl": "wood",
    "knotted_echo": "water",
    "splashing_droplets": "water",
    "bell_knot_swirl": "stone",
    "snarled_stardust": "leaf",
    "rolling_seedbox": "wood",
    "backwound_clockspring": "stone",
    "ring_shard_tangle": "wood",
    "scattered_records": "paper",
    "matted_observatory": "stone",
}

# 예고의 재질 — 적 공격이 대원에게 닿을 때 나는 소리다. 같은 엉킴이라도 예고마다
# 날아오는 물건이 달라 몸체 재질과 다를 수 있다.
TANGLE_INTENT_CONTACT_MATERIAL: dict[str, str] = {
    "paper_flurry": "paper",
    "ink_mist": "water",
    "petal_gust": "leaf",
    "petal_dart": "leaf",
    "shelf_sweep": "wood",
    "catalogue_rain": "paper",
    "echo_ring": "stone",
    "sharp_note": "stone",
    "splash_wave": "water",
    "water_pop": "water",
    "bell_spin": "wood",
    "deep_toll": "stone",
    "dust_flare": "leaf",
    "dust_lash": "leaf",
    "box_roll": "wood",
    "seed_scatter": "wood",
    "spring_snap": "stone",
    "gear_grind": "stone",
    "ring_spin": "wood",
    "shard_scatter": "wood",
    "page_storm": "paper",
    "paper_cut": "paper",
    "lens_glare": "stone",
    "tape_whip": "paper",
}


# 각 예고는 이름과 무관하게 고유 VFX와 모션 원형을 가진다. 전용 스프라이트가
# 준비되기 전까지는 kel_fallback_family가 같은 재질의 검증된 공용 연출을 고른다.
TANGLE_INTENT_PRESENTATION: dict[str, tuple[str, str, str]] = {
    "paper_flurry": ("moonlit", "leap", "tangled-ledger.paper-flurry"),
    "ink_mist": ("mosaic", "channel", "tangled-ledger.ink-mist"),
    "petal_gust": ("moonlit", "leap", "drifting-pressings.petal-gust"),
    "petal_dart": ("ember", "draw", "drifting-pressings.petal-dart"),
    "shelf_sweep": ("mosaic", "dash", "shelf-snarl.shelf-sweep"),
    "catalogue_rain": ("moonlit", "cast", "shelf-snarl.catalogue-rain"),
    "echo_ring": ("sparkling", "channel", "knotted-echo.echo-ring"),
    "sharp_note": ("sparkling", "cast", "knotted-echo.sharp-note"),
    "splash_wave": ("rainy", "channel", "splashing-droplets.splash-wave"),
    "water_pop": ("rainy", "cast", "splashing-droplets.water-pop"),
    "bell_spin": ("moonlit", "leap", "bell-knot-swirl.bell-spin"),
    "deep_toll": ("sparkling", "channel", "bell-knot-swirl.deep-toll"),
    "dust_flare": ("sparkling", "cast", "snarled-stardust.dust-flare"),
    "dust_lash": ("sparkling", "dash", "snarled-stardust.dust-lash"),
    "box_roll": ("mosaic", "dash", "rolling-seedbox.box-roll"),
    "seed_scatter": ("sunny", "cast", "rolling-seedbox.seed-scatter"),
    "spring_snap": ("mosaic", "draw", "backwound-clockspring.spring-snap"),
    "gear_grind": ("mosaic", "brace", "backwound-clockspring.gear-grind"),
    "ring_spin": ("mosaic", "dash", "ring-shard-tangle.ring-spin"),
    "shard_scatter": ("ember", "cast", "ring-shard-tangle.shard-scatter"),
    "page_storm": ("moonlit", "leap", "scattered-records.page-storm"),
    "paper_cut": ("ember", "draw", "scattered-records.paper-cut"),
    "lens_glare": ("sunny", "cast", "matted-observatory.lens-glare"),
    "tape_whip": ("mosaic", "draw", "matted-observatory.tape-whip"),
}

# 기믹은 첫 지역에서 순서대로 학습되고, 이후 지역에서 조합된다. unlock_level은
# 스테이지 위협 프로필의 mechanic_level(1~3)이며 이름이 아니라 code로 판정한다.
TANGLE_INTENT_MECHANICS: dict[str, tuple[str, int]] = {
    "paper_flurry": ("expose", 2),
    "ink_mist": ("focus_leak", 1),
    "petal_gust": ("guard_check", 1),
    "petal_dart": ("expose", 2),
    "shelf_sweep": ("weakness_check", 2),
    "catalogue_rain": ("repairing_index", 2),
    "echo_ring": ("resonant_pressure", 1),
    "sharp_note": ("expose", 1),
    "splash_wave": ("focus_leak", 1),
    "water_pop": ("guard_check", 2),
    "bell_spin": ("weakness_check", 2),
    "deep_toll": ("resonant_pressure", 2),
    "dust_flare": ("focus_leak", 1),
    "dust_lash": ("expose", 2),
    "box_roll": ("guard_check", 1),
    "seed_scatter": ("repairing_index", 2),
    "spring_snap": ("reverse_winding", 2),
    "gear_grind": ("guard_check", 2),
    "ring_spin": ("weakness_check", 1),
    "shard_scatter": ("expose", 2),
    "page_storm": ("focus_leak", 1),
    "paper_cut": ("weakness_check", 2),
    "lens_glare": ("double_exposure", 2),
    "tape_whip": ("reverse_winding", 2),
}

_IMPACT_SHAKE_BY_POWER = {1: 2.2, 2: 3.0, 3: 3.8}

for _tangle_code, _tangle in TANGLE_CATALOG.items():
    _tangle["contact_material"] = TANGLE_CONTACT_MATERIAL[_tangle_code]
    for _intent in _tangle["intents"]:
        _code = str(_intent["code"])
        _intent["contact_material"] = TANGLE_INTENT_CONTACT_MATERIAL[_code]
        _kel, _archetype, _vfx_family = TANGLE_INTENT_PRESENTATION[_code]
        _motion_profile = f"tangle.{_code.replace('_', '-')}"
        _mechanic_code, _mechanic_unlock = TANGLE_INTENT_MECHANICS[_code]
        _intent.update(
            {
                "kel": _kel,
                "vfx_family": _vfx_family,
                "kel_fallback_family": kel_fallback_family(_kel),
                # 의도 코드가 곧 이펙트 키다.
                #
                # 예전에는 고유 연출이 있는 여섯 의도만 자기 코드를 쓰고, 나머지
                # 열여덟은 성장결별 공용 키(`prism_burst` 같은 것)로 떨어졌다.
                # 그 열여덟에도 고유 연출이 생겼으므로 예외를 둘 이유가 없다 —
                # 설계서 9장이 금지한 `적 12종을 공용 연출로 끝내는 것`이 바로
                # 그 상태였다.
                "effect_key": _code,
                "motion_profile": _motion_profile,
                "archetype": _archetype,
                "mechanic_code": _mechanic_code,
                "mechanic_unlock": _mechanic_unlock,
                "motion": combat_motion(
                    _motion_profile,
                    archetype=_archetype,
                    facing="left",
                    impact_shake_px=_IMPACT_SHAKE_BY_POWER[int(_intent["power"])],
                ),
            }
        )


def tangle_definition(code: str) -> dict[str, Any]:
    return copy.deepcopy(TANGLE_CATALOG[code])


def tangles_of_region(region_code: str) -> dict[str, dict[str, Any]]:
    return {
        code: tangle
        for code, tangle in TANGLE_CATALOG.items()
        if tangle["region_code"] == region_code
    }


def validate_tangle_catalog() -> list[str]:
    """카탈로그 자체의 계약 위반을 찾는다. 콘텐츠 validator가 함께 부른다."""

    errors: list[str] = []
    allowed_stats = {"care", "focus", "courage", "insight"}
    by_region: dict[str, list[str]] = {}
    for code, tangle in TANGLE_CATALOG.items():
        prefix = f"tangles.{code}"
        by_region.setdefault(tangle.get("region_code", "?"), []).append(code)
        for key in ("name", "description", "appear_caption", "release_caption"):
            if not isinstance(tangle.get(key), str) or not tangle[key].strip():
                errors.append(f"{prefix}.{key}: 비어 있지 않은 문장이 필요합니다")
        barrier = tangle.get("barrier")
        if not isinstance(barrier, int) or not 20 <= barrier <= 160:
            errors.append(f"{prefix}.barrier: 20~160 사이 정수가 필요합니다")
        if tangle.get("contact_material") not in CONTACT_MATERIALS:
            errors.append(
                f"{prefix}.contact_material: {'|'.join(CONTACT_MATERIALS)} 중 하나여야 합니다"
            )
        cycle = tangle.get("weakness_cycle")
        if (
            not isinstance(cycle, list)
            or len(cycle) != 4
            or set(cycle) != allowed_stats
        ):
            errors.append(f"{prefix}.weakness_cycle: 네 공명을 한 번씩 순환해야 합니다")
        intents = tangle.get("intents")
        if not isinstance(intents, list) or not 1 <= len(intents) <= 2:
            errors.append(f"{prefix}.intents: 1~2개의 예고가 필요합니다")
            intents = []
        for index, intent in enumerate(intents):
            where = f"{prefix}.intents[{index}]"
            if intent.get("target") not in {"front", "lowest", "all"}:
                errors.append(f"{where}.target: front|lowest|all 중 하나여야 합니다")
            power = intent.get("power")
            if not isinstance(power, int) or not 1 <= power <= 3:
                errors.append(f"{where}.power: 1~3 사이 정수가 필요합니다")
            for key in ("code", "name", "telegraph"):
                if not isinstance(intent.get(key), str) or not intent[key].strip():
                    errors.append(f"{where}.{key}: 값이 필요합니다")
            for key in (
                "kel",
                "vfx_family",
                "kel_fallback_family",
                "effect_key",
                "motion_profile",
                "archetype",
                "mechanic_code",
            ):
                if not isinstance(intent.get(key), str) or not intent[key].strip():
                    errors.append(f"{where}.{key}: 전투 표현 값이 필요합니다")
            mechanic_unlock = intent.get("mechanic_unlock")
            if (
                not isinstance(mechanic_unlock, int)
                or isinstance(mechanic_unlock, bool)
                or not 1 <= mechanic_unlock <= 3
            ):
                errors.append(f"{where}.mechanic_unlock: 1~3 정수가 필요합니다")
            if not validate_enemy_mechanic_code(intent.get("mechanic_code")):
                errors.append(f"{where}.mechanic_code: 지원하지 않는 적 기믹입니다")
            if intent.get("archetype") not in {
                "dash",
                "draw",
                "cast",
                "brace",
                "channel",
                "leap",
            }:
                errors.append(f"{where}.archetype: 지원하지 않는 모션 원형입니다")
            if intent.get("contact_material") not in CONTACT_MATERIALS:
                errors.append(
                    f"{where}.contact_material: "
                    f"{'|'.join(CONTACT_MATERIALS)} 중 하나여야 합니다"
                )
            motion = intent.get("motion")
            if not isinstance(motion, dict) or len(motion.get("phases", [])) != 6:
                errors.append(f"{where}.motion: 6구간 모션 계약이 필요합니다")
        # 처치·소멸 언어 금지 — 스토리 설계서 1.3의 canonical 표를 코드로 지킨다.
        for key in ("appear_caption", "release_caption", "description"):
            text = tangle.get(key) or ""
            for banned in ("처치", "소멸", "죽", "쓰러뜨"):
                if banned in text:
                    errors.append(f"{prefix}.{key}: 금지 표현 '{banned}'")

    for region_code, codes in by_region.items():
        elites = [code for code in codes if TANGLE_CATALOG[code]["elite"]]
        if len(codes) != 3 or len(elites) != 1:
            errors.append(
                f"tangles.{region_code}: 일반 2 + 큰 엉킴 1 구성이어야 합니다 "
                f"(현재 {len(codes)}종, 큰 엉킴 {len(elites)})"
            )
    intent_codes = {
        str(intent["code"])
        for tangle in TANGLE_CATALOG.values()
        for intent in tangle["intents"]
    }
    if intent_codes != set(TANGLE_INTENT_PRESENTATION):
        errors.append(
            "tangles.intents: 24개 표현 카탈로그와 예고 코드가 일치해야 합니다"
        )
    families = [
        str(intent["vfx_family"])
        for tangle in TANGLE_CATALOG.values()
        for intent in tangle["intents"]
    ]
    if len(families) != 24 or len(set(families)) != 24:
        errors.append("tangles.intents: 24개 예고는 서로 다른 VFX family가 필요합니다")
    errors.extend(validate_tangle_balance(TANGLE_CATALOG))
    return errors
