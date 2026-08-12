"""캐릭터·감정 성장·레벨을 분리한 수호전 정체성 카탈로그.

식물은 캐릭터의 생물학과 세계관이지 모든 공격의 재질이 아니다.  캐릭터 고유
스킬은 품종 판타지, 선택 스킬과 기본 공격은 감정 성장 계열, 레벨은 tier와 계수만
담당한다. 이 세 축을 합성해도 원본 family와 판정 값은 서버가 결정한다.
"""

from __future__ import annotations

from collections.abc import Mapping
from types import MappingProxyType
from typing import Any


CORE_AFFINITIES = ("care", "focus", "courage", "insight")
CORE_AFFINITY_LABELS = {
    "care": "돌봄",
    "focus": "집중",
    "courage": "용기",
    "insight": "관찰",
}

ELEMENT_LABELS = {
    "nature": "생명",
    "light": "빛",
    "heart": "하트",
    "water": "물",
    "ice": "얼음",
    "fire": "불",
    "strike": "격투",
    "wind": "바람",
    "moon": "달",
    "lightning": "번개",
    "sound": "음파",
    "steel": "강철",
    "force": "역장",
    "poison": "독",
    "shadow": "그림자",
    "gravity": "중력",
    "decay": "쇠락",
    "arcane": "마력",
    "ink": "먹빛",
    "seal": "봉인",
}

KEL_LABELS = {
    "sunny": "햇살결",
    "rainy": "빗물결",
    "ember": "불씨결",
    "moonlit": "달빛결",
    "sparkling": "별빛결",
    "mosaic": "모아결",
}

EMOTION_VFX_PALETTES: Mapping[str, Mapping[str, str]] = MappingProxyType(
    {
        "sunny": MappingProxyType({"primary": "#FFD48A", "secondary": "#FF8FA8"}),
        "rainy": MappingProxyType({"primary": "#8FD8F2", "secondary": "#B7C8FF"}),
        "ember": MappingProxyType({"primary": "#FF7B61", "secondary": "#FFC05C"}),
        "moonlit": MappingProxyType({"primary": "#9DA7E8", "secondary": "#71C6C8"}),
        "sparkling": MappingProxyType({"primary": "#C6A8FF", "secondary": "#FFE37A"}),
        "mosaic": MappingProxyType({"primary": "#A8C5BE", "secondary": "#D8C9B7"}),
    }
)

INITIAL_KEL_MAP_VERSION = 1
CURRENT_KEL_MAP_VERSION = 1

# 원소는 캐릭터의 시각·서사 정체성을 보존하고, 여섯 성장결만 약점·내성을
# 판정한다. 진행 중 전투를 재현할 수 있도록 과거 매핑은 수정·삭제하지 않는다.
ELEMENT_KEL_BY_VERSION: Mapping[int, Mapping[str, str]] = MappingProxyType(
    {
        1: MappingProxyType(
            {
                "light": "sunny",
                "nature": "sunny",
                "water": "rainy",
                "ice": "rainy",
                "poison": "rainy",
                "fire": "ember",
                "decay": "ember",
                "wind": "moonlit",
                "moon": "moonlit",
                "shadow": "moonlit",
                "lightning": "sparkling",
                "sound": "sparkling",
                "arcane": "sparkling",
                "heart": "sunny",
                "steel": "mosaic",
                "force": "mosaic",
                "gravity": "mosaic",
                "ink": "mosaic",
                "seal": "mosaic",
                "strike": "ember",
            }
        ),
    }
)

# 기존 호출부가 읽는 현재 버전 별칭이다. 새 전투 로직은 버전을 명시해 조회한다.
ELEMENT_KEL = ELEMENT_KEL_BY_VERSION[CURRENT_KEL_MAP_VERSION]


def element_kel_map(version: int | None = None) -> Mapping[str, str]:
    selected = CURRENT_KEL_MAP_VERSION if version is None else int(version)
    try:
        return ELEMENT_KEL_BY_VERSION[selected]
    except KeyError as error:
        raise ValueError(f"지원하지 않는 결 매핑 버전입니다: {selected}") from error


KEL_OPPOSITES: Mapping[str, str] = MappingProxyType(
    {
        "sunny": "moonlit",
        "moonlit": "sunny",
        "rainy": "ember",
        "ember": "rainy",
        "sparkling": "mosaic",
        "mosaic": "sparkling",
    }
)

TIER_POWER_BP = {1: 10_000, 2: 11_000, 3: 12_200}
MATCHUP_POWER_BP = {
    "weak": 15_000,
    "prism_weak": 13_000,
    "neutral": 10_000,
    "resist": 6_000,
}
EFFECT_POWER_BP = {
    "weakness_pierce": 12_500,
    "steady_read": 13_000,
    "last_stand": 14_500,
}

DAMAGE_TYPE_LABELS = {
    "support": "지원",
    "slash": "참격",
    "strike": "타격",
    "projectile": "투사체",
    "control": "제어",
    "magic": "마법",
    "curse": "주술",
}

COMBAT_STAT_KEYS = ("offense", "vitality", "support", "control")
COMBAT_STAT_LABELS = {
    "offense": "공격",
    "vitality": "생존",
    "support": "지원",
    "control": "제어",
}


def _role(
    code: str,
    label: str,
    base: tuple[int, int, int, int],
    growth: tuple[int, int, int, int],
) -> dict[str, Any]:
    """캐릭터 역할과 레벨당 0.1 단위 성장치를 한 묶음으로 만든다."""

    return {
        "code": code,
        "label": label,
        "base": dict(zip(COMBAT_STAT_KEYS, base, strict=True)),
        "growth_tenths": dict(zip(COMBAT_STAT_KEYS, growth, strict=True)),
    }


# 감정 능력치와 별개로 캐릭터 자체가 갖는 전투 체질이다. 같은 감정으로 자라도
# 역할이 겹치지 않도록 공격·생존·지원·제어의 시작점과 성장률을 다르게 둔다.
COMBAT_ROLE_PROFILES: dict[str, dict[str, Any]] = {
    "baby-pot": _role("guardian_support", "새싹 수호", (5, 9, 9, 5), (2, 4, 4, 2)),
    "handsome-pot": _role("tempo_striker", "지휘 검격", (9, 8, 6, 7), (4, 3, 2, 3)),
    "pretty-pot": _role("stage_healer", "무대 회복", (7, 6, 10, 7), (3, 2, 4, 3)),
    "tsundere-pot": _role("counter_tank", "반격 전위", (9, 10, 4, 6), (4, 4, 2, 2)),
    "zombie-pot": _role("last_stand", "불사 압박", (10, 11, 3, 7), (4, 5, 1, 3)),
    "gumiho-pot": _role("charm_controller", "매혹 제어", (8, 7, 7, 10), (3, 2, 3, 4)),
    "ninja-pot": _role("weakness_assassin", "약점 암살", (11, 6, 4, 9), (5, 2, 1, 4)),
    "magical-pot": _role("prism_burst", "상성 폭발", (11, 6, 6, 9), (5, 2, 2, 4)),
    "aloof-pot": _role("steady_controller", "안정 제어", (9, 9, 5, 10), (4, 3, 2, 4)),
    "student-pot": _role("focus_engine", "집중 순환", (7, 7, 9, 9), (2, 3, 4, 4)),
    "nurse-pot": _role("premium_healer", "백의 수호", (8, 11, 14, 8), (3, 4, 5, 3)),
    "maestro-pot": _role(
        "resonance_director", "공명 지휘", (9, 8, 11, 14), (3, 3, 4, 5)
    ),
    "restorer-pot": _role("patina_warden", "금빛 복원", (10, 11, 10, 11), (3, 4, 3, 4)),
    "marten-pot": _role("trail_vanguard", "발자국 전위", (8, 7, 5, 8), (3, 3, 2, 3)),
    "gal-pot": _role("runway_catalyst", "스타일 촉매", (13, 11, 12, 10), (5, 4, 4, 4)),
    "archive_guide": _role("archive_support", "기록 지원", (6, 9, 9, 8), (2, 3, 3, 3)),
}

# 아직 전용 스프라이트 계열이 없는 기술이 사용하는 시각 시제품이다.
# vfx_family는 반드시 고유하며 effect_key는 런타임 대체값일 뿐 출시 에셋 이름이 아니다.
ELEMENT_RUNTIME_EFFECTS = {
    "nature": "care_vines",
    "light": "prism_burst",
    "heart": "prism_burst",
    "water": "mist_dash",
    "ice": "mist_dash",
    "fire": "ember_arc",
    "strike": "ember_arc",
    "wind": "mist_dash",
    "moon": "insight_arc",
    "lightning": "prism_burst",
    "sound": "echo_wave",
    "steel": "insight_arc",
    "force": "echo_wave",
    "poison": "venom_seam",
    "shadow": "mist_dash",
    "gravity": "insight_arc",
    "decay": "mist_dash",
    "arcane": "prism_burst",
    "ink": "echo_wave",
    "seal": "insight_arc",
}


def _skill(
    code: str,
    name: str,
    description: str,
    *,
    power: int,
    focus_cost: int,
    cooldown_turns: int,
    effect: str,
    element: str,
    damage_type: str,
    motion_profile: str,
    vfx_family: str,
    tier_names: tuple[str, str, str],
    secondary_element: str | None = None,
) -> dict[str, Any]:
    skill = {
        "code": code,
        "name": name,
        "description": description,
        "power": power,
        "focus_cost": focus_cost,
        "cooldown_turns": cooldown_turns,
        "effect": effect,
        "element": element,
        "damage_type": damage_type,
        "motion_profile": motion_profile,
        "vfx_family": vfx_family,
        "tier_names": list(tier_names),
    }
    if secondary_element is not None:
        skill["secondary_element"] = secondary_element
    return skill


# 고유 I: 자주 쓰는 캐릭터 대표기. 고유 II: 더 긴 쿨타임의 결정기/전술기.
SPECIES_SKILLS: dict[str, dict[str, Any]] = {
    "baby-pot": _skill(
        "sprout_cheer",
        "새싹 응원",
        "살아 있는 덩굴을 날려 장벽을 묶고 모두에게 얕은 보호막을 줘요.",
        power=14,
        focus_cost=2,
        cooldown_turns=1,
        effect="shield_all",
        element="nature",
        damage_type="support",
        motion_profile="baby-pot.vine-cast",
        vfx_family="baby-pot.care-vines",
        tier_names=("새순", "굵은 줄기", "마음 만개"),
    ),
    "handsome-pot": _skill(
        "command_blade",
        "지휘검 일섬",
        "지휘선과 같은 검격으로 장벽을 가르고 집중력을 한 칸 되찾아요.",
        power=17,
        focus_cost=2,
        cooldown_turns=1,
        effect="focus_refund",
        element="steel",
        damage_type="slash",
        motion_profile="handsome-pot.command-draw",
        vfx_family="handsome-pot.command-blade",
        tier_names=("초진", "연계 지휘", "왕도 일섬"),
    ),
    "pretty-pot": _skill(
        "heart_spotlight",
        "하트 스포트라이트",
        "하트 조명이 장벽을 꿰뚫고 가장 지친 동료를 한 칸 회복해요.",
        power=15,
        focus_cost=2,
        cooldown_turns=1,
        effect="heal_lowest",
        element="heart",
        damage_type="magic",
        motion_profile="pretty-pot.spotlight-step",
        vfx_family="pretty-pot.heart-spotlight",
        tier_names=("첫 무대", "앙코르", "그랜드 피날레"),
    ),
    "tsundere-pot": _skill(
        "blazing_counter",
        "홍련 카운터",
        "불꽃을 두른 주먹으로 받아치고 자신에게 두 겹의 방어를 둘러요.",
        power=16,
        focus_cost=2,
        cooldown_turns=1,
        effect="guard_self",
        element="fire",
        damage_type="strike",
        motion_profile="tsundere-pot.counter-punch",
        vfx_family="tsundere-pot.blazing-counter",
        tier_names=("점화", "연타", "홍련 반격"),
    ),
    "zombie-pot": _skill(
        "grave_gravity",
        "묘지 중력장",
        "검은 중력으로 장벽을 붙잡고 체력이 한 칸이면 위력이 크게 올라요.",
        power=20,
        focus_cost=2,
        cooldown_turns=1,
        effect="last_stand",
        element="gravity",
        damage_type="control",
        motion_profile="zombie-pot.gravity-grab",
        vfx_family="zombie-pot.grave-gravity",
        tier_names=("잔류", "중력 우물", "불사의 특이점"),
    ),
    "gumiho-pot": _skill(
        "heart_moon_charm",
        "심월 매혹",
        "초승달 하트가 장벽을 홀려 이번 라운드 수호자의 위력을 낮춰요.",
        power=16,
        focus_cost=2,
        cooldown_turns=1,
        effect="weaken_intent",
        element="heart",
        damage_type="curse",
        motion_profile="gumiho-pot.heart-moon-charm",
        vfx_family="gumiho-pot.heart-moon-charm",
        tier_names=("심월", "두 꼬리 매혹", "구미 심월진"),
    ),
    "ninja-pot": _skill(
        "venom_seam",
        "맹독 틈베기",
        "독이 밴 단검으로 빈틈을 가르고 약점을 맞히면 추가 피해를 줘요.",
        power=18,
        focus_cost=2,
        cooldown_turns=1,
        effect="weakness_pierce",
        element="poison",
        damage_type="slash",
        motion_profile="ninja-pot.venom-draw",
        vfx_family="ninja-pot.venom-seam",
        tier_names=("독침", "맹독선", "무음 독살진"),
    ),
    "magical-pot": _skill(
        "prism_meteor",
        "프리즘 메테오",
        "마력 운석이 현재 드러난 약점의 속성으로 굴절해 떨어져요.",
        # 프리즘 약점은 항상 발동하는 대신 1.30배다. 일반 약점기(1.50배)의
        # 실제 기대 피해와 맞도록 낮은 배율을 기본 계수에서 보정한다.
        power=20,
        focus_cost=3,
        cooldown_turns=1,
        effect="prism_shift",
        element="arcane",
        damage_type="magic",
        motion_profile="magical-pot.meteor-cast",
        vfx_family="magical-pot.prism-meteor",
        tier_names=("혜성", "운석우", "프리즘 대충돌"),
    ),
    "aloof-pot": _skill(
        "absolute_zero_read",
        "절대영도 간파",
        "냉기로 움직임을 멈추고 불리한 상성의 피해 감소를 줄여요.",
        power=17,
        focus_cost=2,
        cooldown_turns=1,
        effect="steady_read",
        element="ice",
        damage_type="control",
        motion_profile="aloof-pot.zero-point",
        vfx_family="aloof-pot.absolute-zero",
        tier_names=("빙점", "결빙 해석", "절대영도"),
    ),
    "student-pot": _skill(
        "ink_formula_burst",
        "먹빛 공식탄",
        "공중에 쓴 전투 공식이 탄환이 되어 날아가고 집중력을 두 칸 돌려줘요.",
        power=14,
        focus_cost=2,
        cooldown_turns=1,
        effect="study_refund",
        element="ink",
        damage_type="projectile",
        motion_profile="student-pot.formula-write",
        vfx_family="student-pot.ink-formula",
        tier_names=("단식", "연립식", "완전 증명"),
    ),
    "nurse-pot": _skill(
        "triage_bloom",
        "응급 개화",
        "백색 앰플을 터뜨려 장벽을 가르고 가장 지친 동료를 즉시 치료해요.",
        power=16,
        focus_cost=2,
        cooldown_turns=1,
        effect="triage_heal",
        element="light",
        secondary_element="nature",
        damage_type="support",
        motion_profile="nurse-pot.triage-step",
        vfx_family="nurse-pot.triage-bloom",
        tier_names=("응급 처치", "백색 봉합", "생명선 개화"),
    ),
    "maestro-pot": _skill(
        "golden_downbeat",
        "황금 첫박",
        "짧은 첫박으로 장벽을 흔들고 뒤이어 행동하는 동료의 위력을 끌어올려요.",
        power=17,
        focus_cost=2,
        cooldown_turns=1,
        effect="resonance_boost",
        element="sound",
        secondary_element="light",
        damage_type="support",
        motion_profile="maestro-pot.downbeat",
        vfx_family="maestro-pot.golden-downbeat",
        tier_names=("첫박", "겹박", "완전 공명"),
    ),
    "restorer-pot": _skill(
        "patina_parry",
        "파티나 패리",
        "금빛 균열선을 손끝으로 짚어 충격을 흘리고 수호자의 다음 위력을 낮춰요.",
        power=13,
        focus_cost=3,
        cooldown_turns=2,
        effect="patina_parry",
        element="steel",
        secondary_element="light",
        damage_type="control",
        motion_profile="restorer-pot.patina-brace",
        vfx_family="restorer-pot.patina-parry",
        tier_names=("묵은빛", "겹막이", "황혼 반전"),
    ),
    "marten-pot": _skill(
        "softpaw_rush",
        "포실발 급습",
        "바람을 타고 달려 장벽의 빈틈을 표시하고 뒤따르는 공격이 더 깊게 파고들게 해요.",
        power=12,
        focus_cost=2,
        cooldown_turns=1,
        effect="softpaw_rush",
        element="wind",
        secondary_element="strike",
        damage_type="strike",
        motion_profile="marten-pot.softpaw-rush",
        vfx_family="marten-pot.softpaw-rush",
        tier_names=("첫 발자국", "추적 표식", "귀소 본능"),
    ),
    "gal-pot": _skill(
        "patchwork_relay",
        "패치워크 릴레이",
        "서로 다른 천 조각의 리듬을 연결해 뒤이어 행동하는 동료의 위력을 끌어올려요.",
        power=18,
        focus_cost=2,
        cooldown_turns=1,
        effect="patchwork_relay",
        element="lightning",
        secondary_element="heart",
        damage_type="support",
        motion_profile="gal-pot.patchwork-step",
        vfx_family="gal-pot.patchwork-relay",
        tier_names=("첫 조각", "커스텀 링크", "우리만의 룩"),
    ),
    "archive_guide": _skill(
        "archive_lantern",
        "기록 등불",
        "기록의 빛을 쏘아 탐험대 전체에 얕은 보호막을 둘러요.",
        power=12,
        focus_cost=2,
        cooldown_turns=1,
        effect="shield_all",
        element="light",
        damage_type="support",
        motion_profile="archive-guide.lantern-cast",
        vfx_family="archive-guide.lantern",
        tier_names=("점등", "기록광", "대서고의 빛"),
    ),
}


SPECIES_SECONDARY_SKILLS: dict[str, dict[str, Any]] = {
    "baby-pot": _skill(
        "root_embrace",
        "뿌리 포옹",
        "굵은 뿌리가 장벽과 동료를 함께 감싸 가장 지친 동료를 회복해요.",
        power=12,
        focus_cost=3,
        cooldown_turns=3,
        effect="heal_lowest",
        element="nature",
        damage_type="support",
        motion_profile="baby-pot.root-embrace",
        vfx_family="baby-pot.root-embrace",
        tier_names=("포옹", "땅울림", "생명의 품"),
    ),
    "handsome-pot": _skill(
        "command_crescendo",
        "지휘의 크레센도",
        "검과 음파를 동시에 지휘해 자신을 방어하고 대열의 박자를 되찾아요.",
        power=14,
        focus_cost=3,
        cooldown_turns=3,
        effect="guard_self",
        element="sound",
        damage_type="support",
        motion_profile="handsome-pot.crescendo-command",
        vfx_family="handsome-pot.command-crescendo",
        tier_names=("박자", "합주", "승전 교향"),
    ),
    "pretty-pot": _skill(
        "ribbon_encore",
        "리본 앙코르",
        "빛의 리본이 무대를 한 바퀴 돌아 동료에게 회복의 하트를 건네요.",
        power=13,
        focus_cost=3,
        cooldown_turns=3,
        effect="heal_lowest",
        element="light",
        damage_type="magic",
        motion_profile="pretty-pot.ribbon-finale",
        vfx_family="pretty-pot.ribbon-encore",
        tier_names=("리본", "커튼콜", "영원의 앙코르"),
    ),
    "tsundere-pot": _skill(
        "iron_uppercut",
        "철벽 어퍼컷",
        "강철 건틀릿으로 올려치며 약점의 균열을 한 번 더 파고들어요.",
        power=15,
        focus_cost=3,
        cooldown_turns=3,
        effect="weakness_pierce",
        element="strike",
        damage_type="strike",
        motion_profile="tsundere-pot.iron-uppercut",
        vfx_family="tsundere-pot.iron-uppercut",
        tier_names=("어퍼컷", "철벽 연계", "불퇴의 승룡"),
    ),
    "zombie-pot": _skill(
        "undying_chain",
        "불사의 사슬",
        "쇠락의 사슬이 끊어졌다 되감기며 마지막 체력에서 더 강해져요.",
        # 쇠락·중력 결은 현재 지역 약점 표에 적어 중립 운용의 하한을 보장한다.
        power=18,
        focus_cost=3,
        cooldown_turns=3,
        effect="last_stand",
        element="decay",
        damage_type="curse",
        motion_profile="zombie-pot.undying-chain",
        vfx_family="zombie-pot.undying-chain",
        tier_names=("사슬", "되감기", "불사 구속"),
    ),
    "gumiho-pot": _skill(
        "nine_tail_eclipse",
        "구미 월식",
        "아홉 달그림자가 겹쳐 적의 시야와 다음 공격의 위력을 흐려요.",
        power=13,
        focus_cost=3,
        cooldown_turns=3,
        effect="weaken_intent",
        element="moon",
        damage_type="curse",
        motion_profile="gumiho-pot.nine-tail-eclipse",
        vfx_family="gumiho-pot.nine-tail-eclipse",
        tier_names=("월영", "반월식", "구미 월식"),
    ),
    "ninja-pot": _skill(
        "shadow_execution",
        "무영 처형",
        "그림자 분신과 교차 베기한 뒤 집중력을 한 칸 되찾아요.",
        power=14,
        focus_cost=3,
        cooldown_turns=3,
        effect="focus_refund",
        element="shadow",
        damage_type="slash",
        motion_profile="ninja-pot.shadow-cross",
        vfx_family="ninja-pot.shadow-execution",
        tier_names=("잔상", "교차", "무영 처형"),
    ),
    "magical-pot": _skill(
        "timefold_comet",
        "시공 접힌 혜성",
        "접힌 시공에서 두 번째 혜성을 불러 현재 약점으로 굴절시켜요.",
        power=18,
        focus_cost=4,
        cooldown_turns=3,
        effect="prism_shift",
        element="arcane",
        damage_type="magic",
        motion_profile="magical-pot.timefold-comet",
        vfx_family="magical-pot.timefold-comet",
        tier_names=("접힘", "쌍혜성", "시공 붕괴"),
    ),
    "aloof-pot": _skill(
        "steel_verdict",
        "강철 판결",
        "차갑게 벼린 금속편이 상성에 흔들리지 않고 결론을 내려요.",
        power=15,
        focus_cost=3,
        cooldown_turns=3,
        effect="steady_read",
        element="steel",
        damage_type="slash",
        motion_profile="aloof-pot.steel-verdict",
        vfx_family="aloof-pot.steel-verdict",
        tier_names=("판정", "금속비", "최종 판결"),
    ),
    "student-pot": _skill(
        "seal_rewrite",
        "봉인식 재작성",
        "허공의 봉인식을 고쳐 써 공격하고 집중력을 두 칸 회복해요.",
        power=12,
        focus_cost=3,
        cooldown_turns=3,
        effect="study_refund",
        element="seal",
        damage_type="magic",
        motion_profile="student-pot.seal-rewrite",
        vfx_family="student-pot.seal-rewrite",
        tier_names=("초고", "교정", "완전 재작성"),
    ),
    "nurse-pot": _skill(
        "white_garden_oath",
        "백의정원 선서",
        "동료의 생명선을 잇고 성장할수록 전원 회복·보호·긴급 소생까지 펼쳐요.",
        power=12,
        focus_cost=4,
        cooldown_turns=4,
        effect="white_garden_oath",
        element="light",
        secondary_element="heart",
        damage_type="support",
        motion_profile="nurse-pot.white-oath",
        vfx_family="nurse-pot.white-garden-oath",
        tier_names=("백의 서약", "보호 병동", "생명선 귀환"),
    ),
    "maestro-pot": _skill(
        "silent_coda",
        "침묵의 코다",
        "마지막 박자를 끊어 수호자의 다음 공격을 낮추고 아군이 파고들 틈을 만들어요.",
        power=15,
        focus_cost=4,
        cooldown_turns=4,
        effect="silent_coda",
        element="sound",
        secondary_element="shadow",
        damage_type="control",
        motion_profile="maestro-pot.silent-coda",
        vfx_family="maestro-pot.silent-coda",
        tier_names=("쉼표", "무음 악장", "절대 종지"),
    ),
    "restorer-pot": _skill(
        "golden_seam",
        "금빛 이음새",
        "갈라진 기억을 금빛 선으로 이어 가장 지친 동료를 회복하고 모두를 보호해요.",
        power=11,
        focus_cost=5,
        cooldown_turns=5,
        effect="golden_seam",
        element="light",
        secondary_element="steel",
        damage_type="support",
        motion_profile="restorer-pot.golden-seam",
        vfx_family="restorer-pot.golden-seam",
        tier_names=("한 줄 봉합", "겹선 복원", "금빛 계승"),
    ),
    "marten-pot": _skill(
        "den_guardian_roar",
        "둥지지기 포효",
        "낮고 단단한 포효로 동료를 감싸고 다음 공격에 함께 달려들 힘을 나눠요.",
        power=13,
        focus_cost=4,
        cooldown_turns=4,
        effect="den_guardian_roar",
        element="nature",
        secondary_element="sound",
        damage_type="support",
        motion_profile="marten-pot.den-roar",
        vfx_family="marten-pot.den-guardian-roar",
        tier_names=("귀가 신호", "무리의 원", "둥지 수호령"),
    ),
    "gal-pot": _skill(
        "runway_reversal",
        "런웨이 리버설",
        "전장의 약점색에 맞춰 공격의 결을 즉시 뒤집고 동료의 다음 움직임까지 살려요.",
        power=18,
        focus_cost=4,
        cooldown_turns=4,
        effect="runway_reversal",
        element="light",
        secondary_element="lightning",
        damage_type="magic",
        motion_profile="gal-pot.runway-reversal",
        vfx_family="gal-pot.runway-reversal",
        tier_names=("룩 체인지", "리버스 워크", "프리즘 피날레"),
    ),
    "archive_guide": _skill(
        "archive_seal",
        "기록 봉인",
        "기록 띠를 펼쳐 공격하고 탐험대 전체에 얕은 보호막을 줘요.",
        power=11,
        focus_cost=3,
        cooldown_turns=3,
        effect="shield_all",
        element="seal",
        damage_type="support",
        motion_profile="archive-guide.archive-seal",
        vfx_family="archive-guide.archive-seal",
        tier_names=("띠", "장서진", "대봉인"),
    ),
}


# 감정은 전투 재질을 정하되 캐릭터 고유 판타지를 덮어쓰지 않는다.
EMOTION_DISCIPLINES: dict[str, dict[str, Any]] = {
    "sunny": {
        "emotion": "joy",
        "name": "햇살 심광",
        "primary_element": "light",
        "secondary_element": "heart",
        "affinity": "care",
        "basic_vfx_family": "emotion.sunny-light",
        "motion_profile": "emotion.open-radiant",
    },
    "rainy": {
        "emotion": "sadness",
        "name": "빗물 빙류",
        "primary_element": "water",
        "secondary_element": "ice",
        "affinity": "focus",
        "basic_vfx_family": "emotion.rainy-water",
        "motion_profile": "emotion.low-tidal",
    },
    "ember": {
        "emotion": "anger",
        "name": "불씨 투혼",
        "primary_element": "fire",
        "secondary_element": "strike",
        "affinity": "courage",
        "basic_vfx_family": "emotion.ember-fire",
        "motion_profile": "emotion.forward-brawler",
    },
    "moonlit": {
        "emotion": "anxiety",
        "name": "달그늘 폭풍",
        "primary_element": "wind",
        "secondary_element": "moon",
        "affinity": "insight",
        "basic_vfx_family": "emotion.moonlit-wind",
        "motion_profile": "emotion.circling-tempest",
    },
    "sparkling": {
        "emotion": "surprise",
        "name": "별빛 전격",
        "primary_element": "lightning",
        "secondary_element": "sound",
        "affinity": "focus",
        "basic_vfx_family": "emotion.sparkling-lightning",
        "motion_profile": "emotion.snap-voltage",
    },
    "mosaic": {
        "emotion": "neutral",
        "name": "무채 강철",
        "primary_element": "steel",
        "secondary_element": "force",
        "affinity": "insight",
        "basic_vfx_family": "emotion.mosaic-steel",
        "motion_profile": "emotion.steady-armor",
    },
}

# T3 고유기는 캐릭터 고유 family를 교체하지 않고 이 감정층을 두 번째 레이어로
# 합성한다. 실제 variant key는 species × form × unique slot으로 만들어 15×6×2
# 조합을 데이터에서 구분한다. production_ready는 해당 레이어의 실기 QA 뒤에만
# 별도 manifest에서 승격한다.
FUSION_LAYER_PROFILES: dict[str, dict[str, str]] = {
    "sunny": {
        "name": "햇살 심광층",
        "vfx_family": "emotion-fusion.sunny-radiance",
        "contact_material": "금빛 심광과 하트 광륜",
    },
    "rainy": {
        "name": "빗물 빙류층",
        "vfx_family": "emotion-fusion.rainy-frost-tide",
        "contact_material": "물막과 얇은 결빙 파편",
    },
    "ember": {
        "name": "불씨 투혼층",
        "vfx_family": "emotion-fusion.ember-impact-flame",
        "contact_material": "압축 화염과 격투 충격륜",
    },
    "moonlit": {
        "name": "달그늘 폭풍층",
        "vfx_family": "emotion-fusion.moonlit-gale",
        "contact_material": "초승달 바람과 긴 고독 잔광",
    },
    "sparkling": {
        "name": "별빛 전격층",
        "vfx_family": "emotion-fusion.sparkling-voltage",
        "contact_material": "번개 가지와 짧은 음파 고리",
    },
    "mosaic": {
        "name": "무채 강철층",
        "vfx_family": "emotion-fusion.mosaic-steel-force",
        "contact_material": "강철 편린과 안정 역장",
    },
}


FORM_COMBAT_SKILLS: dict[str, dict[str, Any]] = {
    "sunny": _skill(
        "sunny_radiant_heart",
        "찬란한 하트",
        "빛의 하트가 날아가 공격하고 가장 지친 동료를 한 칸 회복해요.",
        power=11,
        focus_cost=1,
        cooldown_turns=2,
        effect="heal_lowest",
        element="light",
        damage_type="support",
        motion_profile="emotion.open-radiant",
        vfx_family="emotion.sunny-radiant-heart",
        tier_names=("빛점", "하트 광선", "찬란한 심광"),
    ),
    "rainy": _skill(
        "rainy_frozen_tide",
        "얼어붙은 파도",
        "낮게 밀려온 물결이 얼어붙으며 공격하고 집중력을 한 칸 되찾아요.",
        power=13,
        focus_cost=2,
        cooldown_turns=2,
        effect="focus_refund",
        element="water",
        damage_type="control",
        motion_profile="emotion.low-tidal",
        vfx_family="emotion.rainy-frozen-tide",
        tier_names=("물결", "빙파", "고독의 해일"),
    ),
    "ember": _skill(
        "ember_rage_breaker",
        "분노 파쇄권",
        "불꽃을 압축한 정권으로 장벽을 부수고 자신에게 방어를 둘러요.",
        power=16,
        focus_cost=2,
        cooldown_turns=2,
        effect="guard_self",
        element="fire",
        damage_type="strike",
        motion_profile="emotion.forward-brawler",
        vfx_family="emotion.ember-rage-breaker",
        tier_names=("정권", "폭염 연타", "분노 파쇄"),
    ),
    "moonlit": _skill(
        "moonlit_lonesome_tempest",
        "고독의 돌풍",
        "달빛 바람이 빈틈을 찾아 불리한 상성의 피해 감소를 줄여요.",
        power=14,
        focus_cost=2,
        cooldown_turns=2,
        effect="steady_read",
        element="wind",
        damage_type="control",
        motion_profile="emotion.circling-tempest",
        vfx_family="emotion.moonlit-lonesome-tempest",
        tier_names=("산들", "월풍", "고독의 폭풍"),
    ),
    "sparkling": _skill(
        "sparkling_shock_wonder",
        "경이의 전격",
        "예측할 수 없는 번개가 약점을 만나면 한 번 더 파고들어요.",
        power=13,
        focus_cost=2,
        cooldown_turns=2,
        effect="weakness_pierce",
        element="lightning",
        damage_type="projectile",
        motion_profile="emotion.snap-voltage",
        vfx_family="emotion.sparkling-shock-wonder",
        tier_names=("스파크", "연쇄 전격", "경이의 낙뢰"),
    ),
    "mosaic": _skill(
        "mosaic_steel_equilibrium",
        "강철 평형장",
        "감정의 흔들림이 적은 강철 역장이 현재 약점에 맞춰 형태를 바꿔요.",
        power=12,
        focus_cost=2,
        cooldown_turns=2,
        effect="prism_shift",
        element="steel",
        damage_type="control",
        motion_profile="emotion.steady-armor",
        vfx_family="emotion.mosaic-steel-equilibrium",
        tier_names=("철편", "평형장", "무채 요새"),
    ),
}


FIELD_NOTE_SKILL = _skill(
    "field_note_echo",
    "현장 기록: 되울림",
    "기록한 파형을 먹빛 탄환으로 되돌려 보내고 집중력을 두 칸 회복해요.",
    power=10,
    focus_cost=2,
    cooldown_turns=3,
    effect="study_refund",
    element="ink",
    damage_type="projectile",
    motion_profile="skillbook.echo-script",
    vfx_family="skillbook.field-note-echo",
    tier_names=("현장본", "주석본", "완전 기록"),
    secondary_element="sound",
)


TANGLE_ELEMENT_MATCHUPS = {
    "tangled_ledger": ("steel", "lightning"),
    "drifting_pressings": ("wind", "light"),
    "shelf_snarl": ("fire", "water"),
    "knotted_echo": ("water", "fire"),
    "splashing_droplets": ("lightning", "steel"),
    "bell_knot_swirl": ("light", "wind"),
    "snarled_stardust": ("water", "fire"),
    "rolling_seedbox": ("fire", "water"),
    "backwound_clockspring": ("lightning", "steel"),
    "ring_shard_tangle": ("steel", "lightning"),
    "scattered_records": ("wind", "light"),
    "matted_observatory": ("light", "wind"),
}


RARITY_CURVES_BP = {
    1: (10_000, 2_000),
    2: (10_100, 2_300),
    3: (10_200, 2_600),
    4: (10_300, 3_000),
    5: (10_400, 3_500),
}

EMOTION_COMBAT_STAT_BONUSES: Mapping[str, Mapping[str, int]] = MappingProxyType(
    {
        "sunny": MappingProxyType({"support": 2}),
        "rainy": MappingProxyType({"vitality": 1, "control": 1}),
        "ember": MappingProxyType({"offense": 2}),
        "moonlit": MappingProxyType({"control": 2}),
        "sparkling": MappingProxyType({"offense": 1, "control": 1}),
        "mosaic": MappingProxyType({"vitality": 2}),
    }
)


def character_combat_stats(
    species_code: str,
    *,
    level: int,
    rarity: int,
    form: str,
) -> dict[str, Any]:
    """캐릭터 체질·레벨·희귀도·감정 성장결을 합성한 전투 스탯."""

    profile = COMBAT_ROLE_PROFILES.get(
        species_code, COMBAT_ROLE_PROFILES["archive_guide"]
    )
    safe_level = max(1, min(30, int(level)))
    safe_rarity = max(1, min(5, int(rarity)))
    rarity_bonus = (safe_rarity - 1) // 2
    form_bonus = EMOTION_COMBAT_STAT_BONUSES.get(form, {})
    values = {
        key: int(profile["base"][key])
        + ((safe_level - 1) * int(profile["growth_tenths"][key]) + 5) // 10
        + rarity_bonus
        + int(form_bonus.get(key, 0))
        for key in COMBAT_STAT_KEYS
    }
    return {
        "role": profile["code"],
        "role_label": profile["label"],
        "values": values,
        "labels": {key: COMBAT_STAT_LABELS[key] for key in COMBAT_STAT_KEYS},
    }


def combat_effect_values(
    effect: str,
    *,
    tier: int,
    combat_stats: Mapping[str, int],
) -> dict[str, int]:
    """티어가 오를 때 단순 피해가 아닌 실제 기믹 수치를 확장한다."""

    safe_tier = max(1, min(3, int(tier)))
    support_bonus = max(0, (int(combat_stats.get("support", 0)) - 14) // 8)
    control_bonus = max(0, (int(combat_stats.get("control", 0)) - 14) // 9)
    if effect == "shield_all":
        return {"party_guard": (1, 1, 2)[safe_tier - 1] + support_bonus}
    if effect == "focus_refund":
        return {"focus_refund": (1, 1, 2)[safe_tier - 1]}
    if effect == "heal_lowest":
        return {
            "heal_lowest": (1, 2, 2)[safe_tier - 1] + support_bonus,
            "target_guard": 1 if safe_tier >= 3 else 0,
        }
    if effect == "guard_self":
        return {"self_guard": (2, 3, 4)[safe_tier - 1]}
    if effect == "weaken_intent":
        return {"intent_power_delta": -min(3, (1, 1, 2)[safe_tier - 1] + control_bonus)}
    if effect == "study_refund":
        return {"focus_refund": (2, 2, 3)[safe_tier - 1]}
    if effect == "triage_heal":
        return {
            "heal_lowest": (2, 2, 3)[safe_tier - 1] + support_bonus,
            "target_guard": (0, 1, 2)[safe_tier - 1],
        }
    if effect == "white_garden_oath":
        return {
            "heal_lowest": 2 + support_bonus if safe_tier == 1 else 0,
            "heal_all": (0, 1, 2)[safe_tier - 1] + support_bonus,
            "party_guard": (1, 1, 2)[safe_tier - 1] + support_bonus,
            "revive_count": 1 if safe_tier >= 3 else 0,
            "revive_hp": 1 if safe_tier >= 3 else 0,
        }
    if effect == "resonance_boost":
        return {
            "party_power_bp": (11_000, 11_500, 12_200)[safe_tier - 1]
            + support_bonus * 200,
            "focus_refund": 1 if safe_tier >= 2 else 0,
        }
    if effect == "silent_coda":
        return {
            "intent_power_delta": -min(3, (1, 1, 2)[safe_tier - 1] + control_bonus),
            "enemy_vulnerability_bp": (11_000, 11_750, 12_750)[safe_tier - 1]
            + control_bonus * 250,
        }
    if effect == "patina_parry":
        return {
            "self_guard": (0, 1, 2)[safe_tier - 1],
            "intent_power_delta": (-min(2, 1 + control_bonus) if safe_tier >= 3 else 0),
        }
    if effect == "golden_seam":
        return {
            "heal_lowest": (1, 1, 2)[safe_tier - 1] + support_bonus,
            "party_guard": (0, 1, 1)[safe_tier - 1] + support_bonus,
            "focus_refund": 1 if safe_tier >= 3 else 0,
        }
    if effect == "softpaw_rush":
        return {
            # 저레벨부터 길잡이 두 명의 후속타까지 증폭하면 초반 엘리트가
            # 한 라운드에 끝난다. 취약 표식은 T3 성장 보상으로만 연다.
            "enemy_vulnerability_bp": (10_000, 10_000, 10_800)[safe_tier - 1]
            + control_bonus * 200,
            "self_guard": (0, 1, 1)[safe_tier - 1],
        }
    if effect == "den_guardian_roar":
        return {
            "party_guard": (1, 1, 2)[safe_tier - 1] + support_bonus,
            "party_power_bp": (10_500, 11_000, 11_750)[safe_tier - 1]
            + support_bonus * 150,
            "focus_refund": 1 if safe_tier >= 3 else 0,
        }
    if effect == "patchwork_relay":
        return {
            "party_power_bp": (10_800, 11_400, 12_300)[safe_tier - 1]
            + support_bonus * 200,
            "focus_refund": 1 if safe_tier >= 2 else 0,
        }
    if effect == "runway_reversal":
        return {
            "party_power_bp": (11_000, 11_750, 12_750)[safe_tier - 1]
            + support_bonus * 200,
        }
    return {}


def combat_effect_summary(effect: str, values: Mapping[str, int]) -> str:
    """상세 UI가 서버 판정과 같은 숫자를 설명하도록 짧은 문장으로 만든다."""

    parts: list[str] = []
    labels = {
        "party_guard": "전원 보호",
        "self_guard": "자신 보호",
        "target_guard": "대상 보호",
        "heal_lowest": "최저 체력 회복",
        "heal_all": "전원 회복",
        "focus_refund": "집중 회복",
        "revive_count": "긴급 소생",
    }
    for key, label in labels.items():
        value = int(values.get(key, 0))
        if value > 0:
            parts.append(f"{label} {value}")
    intent_delta = int(values.get("intent_power_delta", 0))
    if intent_delta < 0:
        parts.append(f"적 위력 {intent_delta}")
    party_power_bp = int(values.get("party_power_bp", 10_000))
    if party_power_bp > 10_000:
        parts.append(f"후속 위력 +{(party_power_bp - 10_000) / 100:.0f}%")
    vulnerability_bp = int(values.get("enemy_vulnerability_bp", 10_000))
    if vulnerability_bp > 10_000:
        parts.append(f"받는 피해 +{(vulnerability_bp - 10_000) / 100:.1f}%")
    return " · ".join(parts) if parts else effect.replace("_", " ")


def combat_tier(level: int) -> int:
    if level >= 25:
        return 3
    if level >= 16:
        return 2
    return 1


def rarity_scale_bp(level: int, rarity: int) -> int:
    safe_level = max(1, min(30, int(level)))
    base, slope = RARITY_CURVES_BP.get(max(1, min(5, int(rarity))), (10_000, 2_000))
    numerator = slope * (safe_level - 1)
    return base + (numerator * 2 + 29) // 58


def basic_scale_bp(level: int, rarity: int) -> int:
    scale = rarity_scale_bp(level, rarity)
    delta = scale - 10_000
    if delta >= 0:
        half_delta = (delta + 1) // 2
    else:
        half_delta = -((-delta) // 2)
    return 10_000 + half_delta


def scaled_power(raw_power: int, scale_bp: int) -> int:
    return max(1, (int(raw_power) * int(scale_bp) + 5_000) // 10_000)


def validate_combat_identity_catalog() -> None:
    user_species = set(SPECIES_SKILLS) - {"archive_guide"}
    if user_species != set(SPECIES_SECONDARY_SKILLS) - {"archive_guide"}:
        raise ValueError("unique I/II species coverage mismatch")
    if len(user_species) != 15:
        raise ValueError("exactly fifteen playable species are required")
    if user_species | {"archive_guide"} != set(COMBAT_ROLE_PROFILES):
        raise ValueError("every playable species and guide needs one combat role")

    all_unique = [
        *(SPECIES_SKILLS[code] for code in sorted(user_species)),
        *(SPECIES_SECONDARY_SKILLS[code] for code in sorted(user_species)),
    ]
    if len({skill["code"] for skill in all_unique}) != 30:
        raise ValueError("all thirty signature skill codes must be unique")
    if len({skill["vfx_family"] for skill in all_unique}) != 30:
        raise ValueError("all thirty signature VFX families must be unique")
    if CURRENT_KEL_MAP_VERSION not in ELEMENT_KEL_BY_VERSION:
        raise ValueError("current growth kel map version must exist")
    if INITIAL_KEL_MAP_VERSION not in ELEMENT_KEL_BY_VERSION:
        raise ValueError("initial growth kel map version must remain available")
    for version, mapping in ELEMENT_KEL_BY_VERSION.items():
        if set(mapping) != set(ELEMENT_LABELS):
            raise ValueError(
                f"all twenty elements must map to one growth kel in version {version}"
            )
        if set(mapping.values()) != set(KEL_LABELS):
            raise ValueError(
                f"all six growth kels must be represented in version {version}"
            )

    if {
        SPECIES_SKILLS["gumiho-pot"]["element"],
        SPECIES_SECONDARY_SKILLS["gumiho-pot"]["element"],
    } != {"heart", "moon"}:
        raise ValueError("gumiho identity must remain heart + moon")
    if {
        SPECIES_SKILLS["ninja-pot"]["element"],
        SPECIES_SECONDARY_SKILLS["ninja-pot"]["element"],
    } != {"poison", "shadow"}:
        raise ValueError("ninja identity must remain poison + shadow")

    primary_elements = {
        discipline["primary_element"] for discipline in EMOTION_DISCIPLINES.values()
    }
    if primary_elements != {"light", "water", "fire", "wind", "lightning", "steel"}:
        raise ValueError(
            "six emotion disciplines must have six distinct primary elements"
        )
    for form, discipline in EMOTION_DISCIPLINES.items():
        if (
            ELEMENT_KEL[discipline["primary_element"]] != form
            or ELEMENT_KEL[discipline["secondary_element"]] != form
        ):
            raise ValueError(
                "emotion primary and secondary elements must share its kel"
            )
    if set(FUSION_LAYER_PROFILES) != set(EMOTION_DISCIPLINES):
        raise ValueError("every emotion discipline needs one T3 fusion layer")
    if set(EMOTION_VFX_PALETTES) != set(EMOTION_DISCIPLINES):
        raise ValueError("every emotion discipline needs one restrained VFX palette")
    if len(
        {profile["vfx_family"] for profile in FUSION_LAYER_PROFILES.values()}
    ) != len(EMOTION_DISCIPLINES):
        raise ValueError("T3 emotion fusion VFX families must be unique")

    plant_words = ("잎", "뿌리", "덩굴", "꽃잎", "새싹")
    for species_code in user_species - {"baby-pot"}:
        for skill in (
            SPECIES_SKILLS[species_code],
            SPECIES_SECONDARY_SKILLS[species_code],
        ):
            text = f"{skill['name']} {skill['description']}"
            if any(word in text for word in plant_words):
                raise ValueError(
                    f"non-baby signature regressed to generic plant motif: {species_code}"
                )

    weak_counts = {element: 0 for element in primary_elements}
    resist_counts = {element: 0 for element in primary_elements}
    opposite_counts = {(kel, opposite): 0 for kel, opposite in KEL_OPPOSITES.items()}
    for weak, resist in TANGLE_ELEMENT_MATCHUPS.values():
        if weak == resist:
            raise ValueError("weak and resist elements must differ")
        weak_counts[weak] += 1
        resist_counts[resist] += 1
        weak_kel = ELEMENT_KEL[weak]
        resist_kel = ELEMENT_KEL[resist]
        if KEL_OPPOSITES[weak_kel] != resist_kel:
            raise ValueError("every tangle matchup must follow one opposing kel axis")
        opposite_counts[(weak_kel, resist_kel)] += 1
    if set(weak_counts.values()) != {2} or set(resist_counts.values()) != {2}:
        raise ValueError("each emotion primary must appear twice as weak and resist")
    if set(opposite_counts.values()) != {2}:
        raise ValueError("each directed opposing kel axis must appear exactly twice")


validate_combat_identity_catalog()
