"""탐험 기본 스킬 카탈로그.

스킬은 보상 총량을 바꾸지 않고 판정, 자원, 지도 정보 중 하나만 바꾸는
수평 선택지로 유지한다.
"""

from __future__ import annotations

from typing import Any


def _modes(*pairs: tuple[str, str]) -> list[dict[str, str]]:
    return [{"code": code, "label": label} for code, label in pairs]


def _skill(
    code: str,
    name: str,
    description: str,
    phases: tuple[str, ...],
    modes: list[dict[str, str]],
) -> dict[str, Any]:
    return {
        "code": code,
        "name": name,
        "description": description,
        "phases": list(phases),
        "modes": modes,
    }


SIGNATURE_SKILLS = {
    "baby-pot": _skill(
        "baby-pot.sprout-cheer",
        "새싹 응원",
        "이번 우회의 결의 손실을 한 번 막아요.",
        ("awaiting_event",),
        _modes(("guard", "결의 지키기")),
    ),
    "handsome-pot": _skill(
        "handsome-pot.composed-command",
        "정돈된 지휘",
        "이번 판정에 +2를 더해요.",
        ("awaiting_event",),
        _modes(("command", "판정 +2")),
    ),
    "pretty-pot": _skill(
        "pretty-pot.scene-change",
        "무대 전환",
        "관계·발표 사건을 해결 단계로 바꿔요.",
        ("awaiting_event",),
        _modes(("scene_change", "장면 전환")),
    ),
    "tsundere-pot": _skill(
        "tsundere-pot.thorn-fence",
        "가시 울타리",
        "이번 우회의 결의 손실을 막고 안전 선택을 확인해요.",
        ("awaiting_event",),
        _modes(("guard", "손실 막기")),
    ),
    "zombie-pot": _skill(
        "zombie-pot.night-sense",
        "야간 감각",
        "다음 처음 가는 방의 길빛 비용을 없애고 길 하나를 더 보여줘요.",
        ("exploring",),
        _modes(("night_sense", "밤길 살피기")),
    ),
    "gumiho-pot": _skill(
        "gumiho-pot.foxfire-lure",
        "여우불 유인",
        "숨은 길을 하나 열거나 수호자의 우회 비용을 줄여요.",
        ("exploring", "awaiting_event"),
        _modes(("hidden_path", "숨은 길 열기"), ("guardian_safe", "수호자 우회")),
    ),
    "ninja-pot": _skill(
        "ninja-pot.shadow-scout",
        "그림자 답사",
        "두 칸 안의 방 종류와 비용을 방문 없이 보여줘요.",
        ("exploring",),
        _modes(("scout", "두 칸 앞 답사")),
    ),
    "magical-pot": _skill(
        "magical-pot.leaf-transmute",
        "별잎 변환",
        "현재 선택의 필요 능력치를 고른 능력치로 바꿔요.",
        ("awaiting_event",),
        _modes(
            ("care", "돌봄으로 변환"),
            ("focus", "집중으로 변환"),
            ("courage", "용기로 변환"),
            ("insight", "관찰로 변환"),
        ),
    ),
    "aloof-pot": _skill(
        "aloof-pot.specimen-analysis",
        "표본 분석",
        "현재 기준을 2 낮추고 남을 기록 종류를 미리 보여줘요.",
        ("awaiting_event",),
        _modes(("analyze", "기준 -2")),
    ),
    "student-pot": _skill(
        "student-pot.field-organize",
        "현장 정리",
        "자신의 성장형 스킬을 회복하거나 길빛 2를 회복해요.",
        ("exploring", "awaiting_event"),
        _modes(("restore_form", "성장형 스킬 회복"), ("restore_light", "길빛 2 회복")),
    ),
}


FORM_SKILLS = {
    "sunny": _skill(
        "sunny.share-warmth",
        "온기 나누기",
        "돌봄 판정에 +3을 더하거나 결의 1을 회복해요.",
        ("exploring", "awaiting_event"),
        _modes(("care_bonus", "돌봄 +3"), ("restore_resolve", "결의 1 회복")),
    ),
    "rainy": _skill(
        "rainy.listen-echo",
        "잔향 듣기",
        "집중·관찰 판정에 +3을 더하고 길 하나를 더 보여줘요.",
        ("awaiting_event",),
        _modes(("echo", "집중·관찰 +3")),
    ),
    "ember": _skill(
        "ember.open-path",
        "막힌 길 열기",
        "용기 판정에 +3을 더하고 이번 우회 손실을 막아요.",
        ("awaiting_event",),
        _modes(("breakthrough", "용기 +3")),
    ),
    "moonlit": _skill(
        "moonlit.look-ahead",
        "미리 살피기",
        "관찰 판정에 +3을 더하고 앞의 방을 미리 보여줘요.",
        ("awaiting_event",),
        _modes(("look_ahead", "관찰 +3")),
    ),
    "sparkling": _skill(
        "sparkling.side-path",
        "뜻밖의 샛길",
        "집중·용기 판정에 +3을 더하고 숨은 길을 하나 찾아요.",
        ("awaiting_event",),
        _modes(("side_path", "집중·용기 +3")),
    ),
    "mosaic": _skill(
        "mosaic.join-heart",
        "마음결 잇기",
        "현재 선택의 필요 능력치를 고른 능력치로 바꾸고 +1을 더해요.",
        ("awaiting_event",),
        _modes(
            ("care", "돌봄으로 잇기"),
            ("focus", "집중으로 잇기"),
            ("courage", "용기로 잇기"),
            ("insight", "관찰로 잇기"),
        ),
    ),
}


def skill_definition(species_code: str, form: str, skill_type: str) -> dict[str, Any]:
    source = SIGNATURE_SKILLS if skill_type == "signature" else FORM_SKILLS
    key = species_code if skill_type == "signature" else form
    return source.get(key) or _skill(
        f"{key}.basic",
        "탐험 돕기",
        "이번 판정에 힘을 보태요.",
        ("awaiting_event",),
        _modes(("basic", "판정 +2")),
    )
