"""전투 모션과 VFX 대체 규칙의 서버 단일 원본.

클라이언트는 스킬 이름을 해석하지 않는다. 서버가 여섯 모션 원형과 구간별
시간을 확정해 내려주고, 전용 이펙트가 없을 때 사용할 성장결 family도 함께
스냅샷한다. 덕분에 저장 중인 전투는 카탈로그가 바뀌어도 같은 연출을 재현한다.
"""

from __future__ import annotations

from typing import Any


MOTION_PHASE_NAMES = (
    "anticipation",
    "release",
    "travel",
    "contact",
    "reaction",
    "recovery",
)

MOTION_ARCHETYPES: dict[str, dict[str, Any]] = {
    "dash": {
        "travel_ratio": 0.90,
        "normal_ms": (100, 90, 220, 70, 180, 200),
        "ultimate_ms": (150, 130, 320, 100, 240, 320),
    },
    "draw": {
        "travel_ratio": 0.35,
        "normal_ms": (140, 100, 150, 70, 100, 160),
        "ultimate_ms": (200, 140, 220, 100, 150, 230),
    },
    "cast": {
        "travel_ratio": 0.18,
        "normal_ms": (150, 110, 180, 80, 100, 160),
        "ultimate_ms": (220, 150, 260, 110, 150, 230),
    },
    "brace": {
        "travel_ratio": 0.00,
        "normal_ms": (120, 100, 100, 80, 130, 170),
        "ultimate_ms": (180, 140, 170, 110, 190, 250),
    },
    "channel": {
        "travel_ratio": 0.08,
        "normal_ms": (170, 100, 130, 80, 120, 160),
        "ultimate_ms": (250, 140, 180, 100, 180, 250),
    },
    "leap": {
        "travel_ratio": 0.75,
        "normal_ms": (130, 100, 240, 80, 120, 150),
        "ultimate_ms": (190, 150, 360, 110, 170, 240),
    },
}


MOTION_ARCHETYPE_BY_PROFILE = {
    # 캐릭터 고유 I
    "baby-pot.vine-cast": "channel",
    "handsome-pot.command-draw": "draw",
    "pretty-pot.spotlight-step": "cast",
    "tsundere-pot.counter-punch": "dash",
    "zombie-pot.gravity-grab": "brace",
    "gumiho-pot.heart-moon-charm": "leap",
    "ninja-pot.venom-draw": "draw",
    "magical-pot.meteor-cast": "cast",
    "aloof-pot.zero-point": "brace",
    "student-pot.formula-write": "cast",
    "archive-guide.lantern-cast": "cast",
    # 캐릭터 고유 II
    "baby-pot.root-embrace": "channel",
    "handsome-pot.crescendo-command": "channel",
    "pretty-pot.ribbon-finale": "leap",
    "tsundere-pot.iron-uppercut": "dash",
    "zombie-pot.undying-chain": "dash",
    "gumiho-pot.nine-tail-eclipse": "leap",
    "ninja-pot.shadow-cross": "dash",
    "magical-pot.timefold-comet": "cast",
    "aloof-pot.steel-verdict": "cast",
    "student-pot.seal-rewrite": "brace",
    "archive-guide.archive-seal": "brace",
    # 감정 성장기·공용 행동
    "emotion.open-radiant": "cast",
    "emotion.low-tidal": "brace",
    "emotion.forward-brawler": "dash",
    "emotion.circling-tempest": "leap",
    "emotion.snap-voltage": "cast",
    "emotion.steady-armor": "brace",
    "skillbook.echo-script": "cast",
    "guard.channel": "brace",
}


KEL_FALLBACK_FAMILIES = {
    "sunny": "kel.sunny",
    "rainy": "kel.rainy",
    "ember": "kel.ember",
    "moonlit": "kel.moonlit",
    "sparkling": "kel.sparkling",
    "mosaic": "kel.mosaic",
}


def kel_fallback_family(kel: str | None) -> str | None:
    """성장결에 대응하는 안전한 VFX family를 돌려준다."""

    return KEL_FALLBACK_FAMILIES.get(str(kel)) if kel is not None else None


def combat_motion(
    profile: str,
    *,
    archetype: str | None = None,
    ultimate: bool = False,
    facing: str = "right",
    impact_shake_px: float | None = None,
) -> dict[str, Any]:
    """클라이언트가 그대로 재생할 수 있는 완결된 6구간 모션을 만든다."""

    resolved_archetype = archetype or MOTION_ARCHETYPE_BY_PROFILE.get(profile, "cast")
    if resolved_archetype not in MOTION_ARCHETYPES:
        resolved_archetype = "cast"
    source = MOTION_ARCHETYPES[resolved_archetype]
    duration_key = "ultimate_ms" if ultimate else "normal_ms"
    durations = source[duration_key]
    default_shake = 0.0 if resolved_archetype == "brace" else (4.0 if ultimate else 2.5)
    return {
        "profile": profile,
        "archetype": resolved_archetype,
        "facing": facing if facing in {"left", "right"} else "right",
        "travel_ratio": float(source["travel_ratio"]),
        "impact_shake_px": (
            default_shake if impact_shake_px is None else max(0.0, impact_shake_px)
        ),
        "phases": [
            {"name": name, "ms": int(duration)}
            for name, duration in zip(MOTION_PHASE_NAMES, durations, strict=True)
        ],
        "total_ms": sum(durations),
    }


def present_intent(intent: dict[str, Any]) -> dict[str, Any]:
    """구형 수호자 예고도 신규 표현 계약으로 승격한다.

    엉킴 24개 의도는 카탈로그에 모든 필드를 명시한다. 이 기본값은 오래된
    저장 run과 아직 전용 연출이 없는 일반 수호자만을 위한 호환 계층이다.
    """

    presented = dict(intent)
    code = str(presented.get("code", "guardian_strike"))
    is_claw = code in {"claw", "ledger_claw"}
    presented.setdefault(
        "vfx_family", "guardian.ledger-claw" if is_claw else "guardian.enemy-wave"
    )
    presented.setdefault("effect_key", "ledger_claw" if is_claw else "enemy_wave")
    presented.setdefault("kel", "mosaic")
    presented.setdefault("kel_fallback_family", "kel.mosaic")
    presented.setdefault(
        "motion_profile", "guardian.ledger-claw" if is_claw else "guardian.enemy-wave"
    )
    presented.setdefault("archetype", "draw" if is_claw else "cast")
    presented.setdefault(
        "motion",
        combat_motion(
            str(presented["motion_profile"]),
            archetype=str(presented["archetype"]),
            facing="left",
        ),
    )
    return presented


def validate_motion_catalog() -> None:
    """모션 원형의 시간대와 6구간 계약을 import 시점에 검증한다."""

    normal_ranges = {
        "dash": (820, 900),
        "draw": (680, 760),
        "cast": (720, 820),
        "brace": (660, 740),
        "channel": (700, 800),
        "leap": (780, 860),
    }
    ultimate_ranges = {
        "dash": (1150, 1400),
        "draw": (950, 1150),
        "cast": (1000, 1250),
        "brace": (950, 1150),
        "channel": (1000, 1200),
        "leap": (1100, 1300),
    }
    for archetype, source in MOTION_ARCHETYPES.items():
        for duration_key, ranges in (
            ("normal_ms", normal_ranges),
            ("ultimate_ms", ultimate_ranges),
        ):
            durations = source[duration_key]
            if len(durations) != len(MOTION_PHASE_NAMES) or min(durations) <= 0:
                raise ValueError(f"invalid motion phases: {archetype}.{duration_key}")
            low, high = ranges[archetype]
            if not low <= sum(durations) <= high:
                raise ValueError(f"invalid motion duration: {archetype}.{duration_key}")


validate_motion_catalog()
