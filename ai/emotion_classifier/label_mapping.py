"""AI Hub 감성 대화 말뭉치의 감정 라벨을 서비스 6개 대분류로 매핑한다.

말뭉치의 세부 감정 60종은 E10~E69 코드 체계를 쓰며, 십의 자리(E1x~E6x)가
대분류 계열을 나타낸다. 세부 감정명 문자열 표기는 배포본에 따라 다를 수 있어
코드 프리픽스를 매핑 기준으로 삼는다.

주의: 아래 프리픽스 -> 대분류 대응은 말뭉치 소개 자료에서 통용되는 배치를
따른 잠정값이다. 내려받은 원본의 라벨표(감정 분류 체계)와 대조해 확정하기
전까지 PREFIX_MAPPING_VERIFIED=False를 유지하고, prepare_data.py는 이 플래그가
False면 경고를 출력하고 메타 JSON에 기록한다. 대조 절차는 README 참고.
"""

from __future__ import annotations

import re

# 매핑 규칙이 바뀌면 반드시 올린다. 학습/평가 산출물 메타에 함께 기록된다.
MAPPING_VERSION = "0.1.0-unverified"

# 원본 라벨표와 대조를 마치면 True로 바꾸고 MAPPING_VERSION을 올린다.
PREFIX_MAPPING_VERIFIED = False

# 서비스 대분류. mood_entries.ai_emotion에 저장되는 값과 동일한 표기를 쓴다.
MAJOR_LABELS: tuple[str, ...] = ("기쁨", "슬픔", "분노", "불안", "상처", "당황")

LABEL2ID: dict[str, int] = {label: i for i, label in enumerate(MAJOR_LABELS)}
ID2LABEL: dict[int, str] = {i: label for label, i in LABEL2ID.items()}

# E코드 십의 자리 -> 대분류 (잠정, 원본 라벨표 대조 필요)
CODE_PREFIX_TO_MAJOR: dict[str, str] = {
    "E1": "분노",
    "E2": "슬픔",
    "E3": "불안",
    "E4": "상처",
    "E5": "당황",
    "E6": "기쁨",
}

_CODE_RE = re.compile(r"(E[1-6]\d)\s*$", re.IGNORECASE)


class UnknownEmotionLabelError(ValueError):
    """매핑할 수 없는 감정 라벨."""


def normalize_code(raw: str) -> str:
    """'S06_D02_E18', ' e18 ' 같은 표기에서 E코드만 뽑아 대문자로 돌려준다."""
    if not isinstance(raw, str):
        raise UnknownEmotionLabelError(f"감정 코드가 문자열이 아님: {raw!r}")
    m = _CODE_RE.search(raw.strip())
    if not m:
        raise UnknownEmotionLabelError(f"E10~E69 형식의 감정 코드를 찾지 못함: {raw!r}")
    return m.group(1).upper()


def map_label(raw: str) -> str:
    """세부 감정 코드(E10~E69) 또는 대분류명을 6개 대분류 중 하나로 매핑한다."""
    if isinstance(raw, str) and raw.strip() in LABEL2ID:
        return raw.strip()
    code = normalize_code(raw)
    prefix = code[:2]
    try:
        return CODE_PREFIX_TO_MAJOR[prefix]
    except KeyError as exc:
        raise UnknownEmotionLabelError(f"대분류를 알 수 없는 코드: {code}") from exc


def full_code_table() -> dict[str, str]:
    """E10~E69 전체 60개 코드의 매핑표. 원본 라벨표와의 대조 검토용."""
    return {
        f"E{major}{minor}": CODE_PREFIX_TO_MAJOR[f"E{major}"]
        for major in range(1, 7)
        for minor in range(10)
    }
