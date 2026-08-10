"""식물 성장과 일기 기반 감정 표현형 도메인.

성장 단계는 보상 경험치에서 계산한다. 감정 분기에는 사용자가 고른 기분 점수,
태그, AI 라벨 교정/숨김 설정을 쓰지 않고, 식물을 심은 뒤 작성한 일기 본문을
분류기가 성공적으로 분석한 결과만 사용한다. 대표 라벨뿐 아니라 한 일기 안의
감정 점수 분포도 누적한다. 모든 분기는 같은 성장 속도와 보상을 가지며 어느
감정도 더 좋은 결과로 취급하지 않는다.
"""

from collections import Counter
from collections.abc import Iterable
from datetime import datetime
import math
from typing import Any

import sqlalchemy as sa
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.timeutil import utcnow
from app.models.enums import AnalysisStatus, PlantStatus
from app.models.mood import MoodEntry
from app.models.plant import Plant

# 플레이 스타일에 따라 첫 식물 완주가 20~100일까지 벌어지지 않도록,
# 첫 기록에서 새싹을 보고 기록 중심 이용자도 약 3주 안에 만개하도록 조정한다.
STAGE_THRESHOLDS = [0, 20, 100, 250, 450]
HARVEST_EXP = STAGE_THRESHOLDS[-1]
# 전투 레벨은 외형 성장 5단계보다 촘촘한 1~30 성장 보상 축이다.
# 인덱스가 레벨-1이고 값은 그 레벨에 진입하는 누적 EXP다.
LEVEL_EXP_THRESHOLDS = [
    0,
    10,
    20,
    35,
    50,
    65,
    80,
    90,
    100,
    120,
    140,
    160,
    185,
    210,
    230,
    250,
    280,
    310,
    340,
    370,
    400,
    425,
    450,
    500,
    550,
    610,
    670,
    740,
    815,
    900,
]
STAGE_NAMES = {1: "씨앗", 2: "새싹", 3: "줄기", 4: "개화", 5: "만개"}
MUSEUM_MAX_FEATURED = 10

# 3단계부터 분기가 보인다. 첫 결정은 분석 표본 3건, 60% 이상, 2위와 20%p
# 이상 차이가 필요하다. 이미 정한 분기는 표본 5건 이상에서 새 후보가 67% 이상,
# 기존 분기보다 25%p 이상 앞설 때만 바뀐다.
BRANCH_START_STAGE = 3
BRANCH_MIN_SAMPLES = 3
BRANCH_INITIAL_RATIO = 0.60
BRANCH_INITIAL_MARGIN = 0.20
BRANCH_SWITCH_MIN_SAMPLES = 5
BRANCH_SWITCH_RATIO = 0.67
BRANCH_SWITCH_MARGIN = 0.25
SECONDARY_REVEAL_STAGE = 4
SECONDARY_MIN_RATIO = 0.14

EMOTION_CATEGORIES = ("joy", "sadness", "anger", "anxiety", "surprise", "mixed")
FINAL_FORM_BY_EMOTION = {
    "joy": "sunny",
    "sadness": "rainy",
    "anger": "ember",
    "anxiety": "moonlit",
    "surprise": "sparkling",
    "mixed": "mosaic",
}
EMOTION_BY_FINAL_FORM = {value: key for key, value in FINAL_FORM_BY_EMOTION.items()}
PERSONALITY_BY_EMOTION = {
    "joy": {
        "persona_key": "sunny_optimist",
        "persona_name": "햇살결",
        "trait": "다정함·나눔",
        "voice_line": "햇빛 자리 찾았어. 오늘 잎을 넓게 펼칠래.",
        "silhouette": "넓게 퍼지는 잎과 둥근 꽃잎",
        "accent_pattern": "햇살 고리",
        "motion": "가볍게 좌우로 잎을 펼침",
    },
    "sadness": {
        "persona_key": "gentle_listener",
        "persona_name": "빗물결",
        "trait": "섬세함·경청",
        "voice_line": "잎 끝의 물방울, 떨어질 때까지 지켜볼래.",
        "silhouette": "물결처럼 길게 흐르는 잎",
        "accent_pattern": "투명한 빗방울 맥",
        "motion": "천천히 숨 쉬듯 잎이 내려앉음",
    },
    "anger": {
        "persona_key": "brave_guardian",
        "persona_name": "불씨결",
        "trait": "강인함·솔직함",
        "voice_line": "내 불씨는 작아도 또렷해. 길을 밝힐 수 있어.",
        "silhouette": "굵은 줄기와 불꽃처럼 치솟는 잎",
        "accent_pattern": "타오르는 잎맥",
        "motion": "힘 있게 자세를 세우고 불씨를 털어냄",
    },
    "anxiety": {
        "persona_key": "careful_observer",
        "persona_name": "달빛결",
        "trait": "신중함·준비",
        "voice_line": "달이 기울 때까지 주변을 한 번 더 살펴볼게.",
        "silhouette": "몸을 감싸는 겹잎과 단단한 봉오리",
        "accent_pattern": "은빛 초승달 맥",
        "motion": "주변을 살핀 뒤 조심스럽게 잎을 펼침",
    },
    "surprise": {
        "persona_key": "curious_explorer",
        "persona_name": "별빛결",
        "trait": "호기심·발견",
        "voice_line": "방금 반짝인 거 봤어? 저쪽도 확인하자!",
        "silhouette": "방향마다 튀어나온 별 모양 새잎",
        "accent_pattern": "불규칙한 별가루 점",
        "motion": "통통 튀며 새 방향을 빠르게 바라봄",
    },
    "mixed": {
        "persona_key": "free_spirit",
        "persona_name": "모아결",
        "trait": "유연함·다채로움",
        "voice_line": "오늘은 잎마다 다른 색이야. 어느 쪽도 숨기지 않을래.",
        "silhouette": "서로 다른 모양이 어우러진 비대칭 잎",
        "accent_pattern": "여러 마음의 조각보",
        "motion": "잎마다 다른 박자로 부드럽게 흔들림",
    },
}

# 감정은 사용자 성격을 판정하는 값이 아니다. 아래 값은 누적된 일기 감정의
# 분포를 식물 캐릭터의 말투와 움직임으로 번역하기 위한 가치중립적 연출 규칙이다.
EMOTION_CHARACTER_DETAILS = {
    "joy": {
        "emotion_name": "기쁨",
        "accent_name": "햇살",
        "signature_trait": "온기를 나누는",
        "chat_cadence": "가볍고 따뜻한 두세 문장",
        "chat_focus": "작지만 선명했던 기쁨과 남기고 싶은 순간",
        "question_style": "좋았던 장면을 과장 없이 한 가지 묻기",
        "secondary_modifier": "끝에 남은 작은 가능성도 살핀다",
    },
    "sadness": {
        "emotion_name": "슬픔",
        "accent_name": "빗물",
        "signature_trait": "여운을 오래 듣는",
        "chat_cadence": "조용하고 여백 있는 두세 문장",
        "chat_focus": "잃거나 놓친 것, 아쉬움이 머무는 지점",
        "question_style": "서둘러 해결하지 않고 가장 아쉬운 한 가지 묻기",
        "secondary_modifier": "사라진 것의 자리를 함부로 채우지 않는다",
    },
    "anger": {
        "emotion_name": "분노",
        "accent_name": "불씨",
        "signature_trait": "경계를 또렷이 세우는",
        "chat_cadence": "짧고 힘 있는 두세 문장",
        "chat_focus": "침범된 경계와 정말 바랐던 것",
        "question_style": "누가 옳은지 단정하지 않고 바람을 하나 묻기",
        "secondary_modifier": "중요한 경계와 바람을 또렷하게 짚는다",
    },
    "anxiety": {
        "emotion_name": "불안",
        "accent_name": "달빛",
        "signature_trait": "한 번 더 살피는",
        "chat_cadence": "차분하고 순서가 분명한 두세 문장",
        "chat_focus": "걱정되는 일과 지금 확인할 수 있는 사실",
        "question_style": "한 번에 확인 가능한 것 하나만 묻기",
        "secondary_modifier": "확실한 것과 아직 모르는 것을 나누어 본다",
    },
    "surprise": {
        "emotion_name": "놀람",
        "accent_name": "별빛",
        "signature_trait": "낯선 장면을 발견하는",
        "chat_cadence": "생기 있지만 재촉하지 않는 두세 문장",
        "chat_focus": "예상과 달랐던 순간과 새롭게 알아챈 것",
        "question_style": "가장 뜻밖이었던 지점을 하나 묻기",
        "secondary_modifier": "예상 밖의 작은 단서를 놓치지 않는다",
    },
    "mixed": {
        "emotion_name": "여러 감정",
        "accent_name": "조각빛",
        "signature_trait": "서로 다른 마음을 함께 두는",
        "chat_cadence": "유연하고 단정 짓지 않는 두세 문장",
        "chat_focus": "동시에 존재하는 여러 마음과 그 사이의 차이",
        "question_style": "상반된 마음 중 먼저 말하고 싶은 하나를 묻기",
        "secondary_modifier": "한 가지 이름으로 서둘러 묶지 않는다",
    },
}

# 에너지·감수성·호기심·숙고성은 캐릭터 연출 축이다. 높고 낮음에 우열은 없고,
# 값은 성장 속도나 보상에 절대 쓰지 않는다.
_TEMPERAMENT_WEIGHTS = {
    "joy": {
        "energy": 0.72,
        "sensitivity": 0.48,
        "curiosity": 0.68,
        "deliberation": 0.34,
    },
    "sadness": {
        "energy": 0.24,
        "sensitivity": 0.92,
        "curiosity": 0.42,
        "deliberation": 0.72,
    },
    "anger": {
        "energy": 0.94,
        "sensitivity": 0.64,
        "curiosity": 0.38,
        "deliberation": 0.46,
    },
    "anxiety": {
        "energy": 0.42,
        "sensitivity": 0.88,
        "curiosity": 0.50,
        "deliberation": 0.94,
    },
    "surprise": {
        "energy": 0.86,
        "sensitivity": 0.62,
        "curiosity": 0.96,
        "deliberation": 0.22,
    },
    "mixed": {
        "energy": 0.56,
        "sensitivity": 0.78,
        "curiosity": 0.74,
        "deliberation": 0.58,
    },
}

_TEMPERAMENT_LABELS = {
    "energy": ("고요한", "은은한", "생기찬"),
    "sensitivity": ("담백한", "세심한", "깊이 느끼는"),
    "curiosity": ("익숙함을 아끼는", "열린", "새로움을 좇는"),
    "deliberation": ("즉흥적인", "한 박자 살피는", "차분히 준비하는"),
}

_EMOTION_ALIASES = {
    "joy": "joy",
    "happy": "joy",
    "happiness": "joy",
    "기쁨": "joy",
    "행복": "joy",
    "즐거움": "joy",
    "sad": "sadness",
    "sadness": "sadness",
    "hurt": "sadness",
    "슬픔": "sadness",
    "상처": "sadness",
    "anger": "anger",
    "angry": "anger",
    "분노": "anger",
    "anxiety": "anxiety",
    "anxious": "anxiety",
    "fear": "anxiety",
    "불안": "anxiety",
    "surprise": "surprise",
    "surprised": "surprise",
    "당황": "surprise",
    "mixed": "mixed",
    "uncertain": "mixed",
    "혼합": "mixed",
}

_GENERIC_GROWTH_IDENTITY = {
    "seed_shape": "round_seed",
    "vessel_style": "soft_terracotta_pot",
    "rarity_effect": "none",
    "asset_namespace": "plants/generic",
}
_SPECIES_GROWTH_FALLBACKS = {
    "basic_sprout": {
        "seed_shape": "heart_speck_seed",
        "vessel_style": "round_terracotta_pot",
        "rarity_effect": "none",
        "asset_namespace": "plants/basic_sprout",
    },
    "cactus": {
        "seed_shape": "spined_star_seed",
        "vessel_style": "ribbed_desert_incubator",
        "rarity_effect": "warm_dust_glint",
        "asset_namespace": "plants/cactus",
    },
    "sunflower": {
        "seed_shape": "striped_sun_seed",
        "vessel_style": "sunbeam_bell_jar",
        "rarity_effect": "soft_sun_motes",
        "asset_namespace": "plants/sunflower",
    },
}


def stage_from_exp(exp: int) -> int:
    stage = 1
    for i, threshold in enumerate(STAGE_THRESHOLDS, start=1):
        if exp >= threshold:
            stage = i
    return stage


def level_from_exp(exp: int) -> int:
    """누적 EXP를 1~30 전투 레벨로 바꾼다."""

    level = 1
    for index, threshold in enumerate(LEVEL_EXP_THRESHOLDS, start=1):
        if exp >= threshold:
            level = index
        else:
            break
    return level


def next_stage_exp(exp: int) -> int | None:
    for threshold in STAGE_THRESHOLDS:
        if exp < threshold:
            return threshold
    return None


def is_harvestable(plant: Plant) -> bool:
    profile = plant.emotion_profile or empty_emotion_profile()
    # 안전 경로 또는 AI 비활성 상태로 분석할 수 없었던 본문은 수확을 막지 않는다.
    evidence_ready = (
        int(profile.get("total", 0)) >= BRANCH_MIN_SAMPLES
        or int(profile.get("unavailable_count", 0)) > 0
    )
    return (
        plant.status == PlantStatus.ACTIVE
        and plant.exp >= HARVEST_EXP
        and int(profile.get("pending_count", 0)) == 0
        and evidence_ready
    )


def _canonical_emotion(value: str | None) -> str | None:
    if value is None:
        return None
    return _EMOTION_ALIASES.get(value.strip().casefold())


def emotion_for_entry(entry: Any) -> str | None:
    """성장에 쓸 분류기 결과만 정규화한다.

    ``mood_level``, ``emotion_tags``, ``ai_emotion_override``와
    ``ai_label_hidden``은 의도적으로 읽지 않는다. 숨김은 표시 설정이고 교정값은
    사용자의 직접 선택이므로, 일기 본문에서 읽어낸 식물 감정과 분리한다.
    """
    has_content = getattr(entry, "has_content", None)
    if has_content is None:
        content = getattr(entry, "content", None)
        has_content = isinstance(content, str) and bool(content.strip())
    if not has_content:
        return None
    if getattr(entry, "analysis_status", None) != AnalysisStatus.SUCCEEDED:
        return None
    return _canonical_emotion(getattr(entry, "ai_emotion", None))


def emotion_weights_for_entry(entry: Any) -> dict[str, float]:
    """한 일기에서 함께 읽힌 감정을 합이 1인 분포로 정규화한다.

    구 분석 결과처럼 ``ai_scores``가 없으면 대표 라벨 한 표로 되돌아간다.
    알 수 없는 라벨·음수·NaN은 버리고, 상처처럼 같은 성장 결로 묶이는 라벨은
    합산한다. 점수 크기는 성장 속도나 보상에는 쓰지 않는다.
    """
    has_content = getattr(entry, "has_content", None)
    if has_content is None:
        content = getattr(entry, "content", None)
        has_content = isinstance(content, str) and bool(content.strip())
    if (
        not has_content
        or getattr(entry, "analysis_status", None) != AnalysisStatus.SUCCEEDED
    ):
        return {}
    primary = emotion_for_entry(entry)
    # 분류기가 저신뢰·동률로 abstain한 결과는 원 점수의 라벨 수 차이
    # (예: 슬픔+상처가 같은 성장 결로 합쳐짐)에 끌려가지 않게 mixed 한 표로 둔다.
    # 명확한 대표 라벨이 있을 때만 세부 점수 분포를 성장 외형에 사용한다.
    raw_primary = str(getattr(entry, "ai_emotion", "") or "").strip().lower()
    if raw_primary == "uncertain":
        return {"mixed": 1.0}
    scores = getattr(entry, "ai_scores", None)
    if not isinstance(scores, dict):
        return {primary: 1.0} if primary else {}

    weights: Counter[str] = Counter()
    for label, raw_score in scores.items():
        emotion = _canonical_emotion(str(label))
        if emotion is None or isinstance(raw_score, bool):
            continue
        try:
            score = float(raw_score)
        except (TypeError, ValueError):
            continue
        if not math.isfinite(score) or score <= 0:
            continue
        weights[emotion] += score

    total = sum(weights.values())
    if total <= 0:
        return {primary: 1.0} if primary else {}
    return {key: value / total for key, value in weights.items()}


def empty_emotion_profile() -> dict:
    return build_emotion_profile(())


def build_emotion_profile(entries: Iterable[Any]) -> dict:
    """대표 감정과 일기 안의 다중 감정 분포를 함께 집계한다."""
    counts: Counter[str] = Counter()
    weights: Counter[str] = Counter()
    pending_count = 0
    unavailable_count = 0
    empty_count = 0
    for entry in entries:
        has_content = getattr(entry, "has_content", None)
        if has_content is None:
            content = getattr(entry, "content", None)
            has_content = isinstance(content, str) and bool(content.strip())
        if not has_content:
            empty_count += 1
            continue
        status = getattr(entry, "analysis_status", None)
        if status in (AnalysisStatus.PENDING, AnalysisStatus.RUNNING):
            pending_count += 1
            continue
        distribution = emotion_weights_for_entry(entry)
        if not distribution:
            unavailable_count += 1
            continue
        emotion = emotion_for_entry(entry)
        if emotion is None:
            ranked = sorted(
                distribution.items(), key=lambda item: item[1], reverse=True
            )
            emotion = (
                ranked[0][0]
                if len(ranked) == 1
                or not math.isclose(ranked[0][1], ranked[1][1], abs_tol=1e-9)
                else "mixed"
            )
        counts[emotion] += 1
        weights.update(distribution)

    normalized_counts = {key: counts.get(key, 0) for key in EMOTION_CATEGORIES}
    total = sum(normalized_counts.values())
    ratios = {
        key: round(value / total, 4) if total else 0.0
        for key, value in normalized_counts.items()
    }
    normalized_weights = {
        key: round(float(weights.get(key, 0.0)), 4) for key in EMOTION_CATEGORIES
    }
    weight_total = sum(weights.values())
    weighted_ratios = {
        key: round(float(weights.get(key, 0.0)) / weight_total, 4)
        if weight_total
        else 0.0
        for key in EMOTION_CATEGORIES
    }
    return {
        "version": 3,
        "source": "diary_text_analysis_scores",
        "total": total,
        "pending_count": pending_count,
        "unavailable_count": unavailable_count,
        "empty_count": empty_count,
        "counts": normalized_counts,
        "ratios": ratios,
        "weights": normalized_weights,
        "weighted_ratios": weighted_ratios,
    }


def _profile_distribution(profile: dict) -> dict[str, float]:
    """Legacy 프로필까지 포함해 합이 1인 성장 감정 분포를 만든다."""
    candidates = (
        profile.get("weighted_ratios"),
        profile.get("weights"),
        profile.get("ratios"),
        profile.get("counts"),
    )
    for source in candidates:
        if not isinstance(source, dict):
            continue
        values: dict[str, float] = {}
        for emotion in EMOTION_CATEGORIES:
            raw = source.get(emotion, 0.0)
            if isinstance(raw, bool):
                continue
            try:
                value = float(raw or 0.0)
            except (TypeError, ValueError):
                continue
            if math.isfinite(value) and value > 0:
                values[emotion] = value
        total = sum(values.values())
        if total > 0:
            return {
                emotion: values.get(emotion, 0.0) / total
                for emotion in EMOTION_CATEGORIES
            }
    return {emotion: 0.0 for emotion in EMOTION_CATEGORIES}


def _ranked_distribution(profile: dict) -> list[tuple[str, float]]:
    distribution = _profile_distribution(profile)
    return sorted(
        distribution.items(),
        key=lambda item: (-item[1], EMOTION_CATEGORIES.index(item[0])),
    )


def _emotion_character_payload(emotion: str, ratio: float) -> dict:
    personality = PERSONALITY_BY_EMOTION[emotion]
    details = EMOTION_CHARACTER_DETAILS[emotion]
    return {
        "emotion": emotion,
        "emotion_name": details["emotion_name"],
        "form": FINAL_FORM_BY_EMOTION[emotion],
        "ratio": round(ratio, 4),
        "persona_code": personality["persona_key"],
        "persona_name": personality["persona_name"],
        "trait": personality["trait"],
        "accent_name": details["accent_name"],
        "signature_trait": details["signature_trait"],
    }


def _temperament_band(axis: str, value: float) -> str:
    labels = _TEMPERAMENT_LABELS[axis]
    if value < 0.39:
        return labels[0]
    if value < 0.68:
        return labels[1]
    return labels[2]


def _temperament_payload(profile: dict, *, revealed: bool) -> dict:
    distribution = _profile_distribution(profile)
    has_evidence = any(distribution.values())
    axes = {
        axis: round(
            sum(
                distribution[emotion] * _TEMPERAMENT_WEIGHTS[emotion][axis]
                for emotion in EMOTION_CATEGORIES
            ),
            4,
        )
        for axis in _TEMPERAMENT_LABELS
    }
    labels = {axis: _temperament_band(axis, value) for axis, value in axes.items()}
    return {
        "revealed": revealed and has_evidence,
        "fictional_character_axes": True,
        "affects_rewards": False,
        "axes": axes if revealed and has_evidence else {},
        "labels": labels if revealed and has_evidence else {},
        "summary": (
            f"{labels['energy']} 움직임 · {labels['sensitivity']} 반응 · "
            f"{labels['curiosity']} 시선 · {labels['deliberation']} 말걸음"
            if revealed and has_evidence
            else None
        ),
    }


def build_growth_traits(
    profile: dict,
    stage: int,
    branch: str | None,
    *,
    harvested: bool = False,
) -> dict:
    """누적 감정 분포를 단계적으로 공개되는 캐릭터 성질로 번역한다.

    결과는 사용자에 대한 성격 검사나 진단이 아니라 식물의 외형·말투 연출 계약이다.
    3단계에는 주결, 4단계에는 보조결과 기질 축, 5단계에는 완성된 대화 습관을
    공개한다. 감정 종류는 성장 속도·보상·희귀도에 영향을 주지 않는다.
    """
    stage = max(1, min(int(stage), len(STAGE_THRESHOLDS)))
    total = int(profile.get("total", 0) or 0)
    ranked = _ranked_distribution(profile)
    leader_emotion, leader_ratio = ranked[0]
    if len(ranked) > 1 and math.isclose(leader_ratio, ranked[1][1], abs_tol=1e-9):
        leader_emotion = "mixed"
    has_leader = leader_ratio > 0
    revealed_branch = branch if branch in EMOTION_CATEGORIES and stage >= 3 else None
    dominant = (
        _emotion_character_payload(
            revealed_branch,
            _profile_distribution(profile).get(revealed_branch, 0.0),
        )
        if revealed_branch
        else None
    )

    secondary = None
    if dominant and (harvested or stage >= SECONDARY_REVEAL_STAGE):
        for emotion, ratio in ranked:
            if emotion != revealed_branch and ratio >= SECONDARY_MIN_RATIO:
                secondary = _emotion_character_payload(emotion, ratio)
                break

    reveal_state = {
        1: "dormant",
        2: "sensing",
        3: "dominant_revealed",
        4: "secondary_revealed",
        5: "signature_complete",
    }[stage]
    next_reveal = {
        1: "새싹이 나면 일기에서 읽힌 첫 마음빛이 비쳐요.",
        2: "줄기가 자라면 주된 외형과 성격 결이 드러나요.",
        3: "꽃봉오리가 생기면 보조 감정의 색과 기질이 더해져요.",
        4: "만개하면 움직임과 대화 습관까지 완성돼요.",
        5: None,
    }[stage]

    if dominant is None:
        if stage >= BRANCH_START_STAGE:
            reveal_state = "awaiting_evidence"
            next_reveal = "일기 분석이 더 모이면 주된 외형과 성격 결이 드러나요."
        title = "잠든 마음씨앗" if stage == 1 else "마음빛을 듣는 새싹"
        traits: list[str] = []
        chat_style = None
    else:
        base = PERSONALITY_BY_EMOTION[revealed_branch]
        details = EMOTION_CHARACTER_DETAILS[revealed_branch]
        title = base["persona_name"]
        traits = [details["signature_trait"]]
        if secondary:
            title = f"{secondary['accent_name']} 품은 {title}"
            traits.append(secondary["signature_trait"])
        elif stage == SECONDARY_REVEAL_STAGE:
            reveal_state = "temperament_revealed"
        chat_style = {
            "cadence": details["chat_cadence"],
            "focus": details["chat_focus"],
            "question_style": details["question_style"],
            "secondary_modifier": (
                EMOTION_CHARACTER_DETAILS[secondary["emotion"]]["secondary_modifier"]
                if secondary
                else None
            ),
            "stage_expression": {
                3: "주된 결의 말투가 막 드러나 서툴지만 또렷하다",
                4: "주결에 보조결의 관찰 방식이 자연스럽게 섞인다",
                5: "완성된 고유 말버릇을 유지하되 같은 문장을 반복하지 않는다",
            }.get(stage),
        }

    cue = (
        _emotion_character_payload(leader_emotion, leader_ratio)
        if stage >= 2 and has_leader and dominant is None
        else None
    )
    temperament = _temperament_payload(
        profile,
        revealed=dominant is not None
        and (harvested or stage >= SECONDARY_REVEAL_STAGE),
    )
    return {
        "version": 1,
        "source": "diary_text_emotion_distribution",
        "fictional_character_profile": True,
        "user_personality_inference": False,
        "affects_growth_speed": False,
        "stage": stage,
        "stage_name": STAGE_NAMES[stage],
        "reveal_state": reveal_state,
        "next_reveal": next_reveal,
        "evidence_count": total,
        "title": title,
        "dominant": dominant,
        "secondary": secondary,
        "cue": cue,
        "traits": traits,
        "temperament": temperament,
        "chat_style": chat_style,
    }


def _leader(profile: dict) -> tuple[str | None, float, float]:
    total = int(profile.get("total", 0))
    counts = profile.get("counts") or {}
    if total <= 0:
        return None, 0.0, 0.0

    weights = profile.get("weights") or {}
    has_weighted_profile = isinstance(weights, dict) and any(
        float(weights.get(key, 0.0) or 0.0) > 0 for key in EMOTION_CATEGORIES
    )
    evidence = weights if has_weighted_profile else counts
    evidence_total = sum(
        float(evidence.get(key, 0.0) or 0.0) for key in EMOTION_CATEGORIES
    )
    if evidence_total <= 0:
        return None, 0.0, 0.0
    ranked = sorted(
        ((key, float(evidence.get(key, 0.0) or 0.0)) for key in EMOTION_CATEGORIES),
        key=lambda item: item[1],
        reverse=True,
    )
    if math.isclose(ranked[0][1], ranked[1][1], abs_tol=1e-9):
        return None, ranked[0][1] / evidence_total, 0.0
    ratio = ranked[0][1] / evidence_total
    margin = (ranked[0][1] - ranked[1][1]) / evidence_total
    return ranked[0][0], ratio, margin


def resolve_growth_branch(
    profile: dict,
    stage: int,
    current_branch: str | None = None,
    *,
    finalizing: bool = False,
) -> str | None:
    """최소 표본과 히스테리시스로 활성 식물의 감정 분기를 정한다."""
    total = int(profile.get("total", 0))
    current = current_branch if current_branch in EMOTION_CATEGORIES else None
    if stage < BRANCH_START_STAGE:
        return None
    if total <= 0:
        return "mixed" if finalizing else None

    candidate, ratio, margin = _leader(profile)
    counts = profile.get("counts") or {}
    weights = profile.get("weights") or {}
    evidence = (
        weights if isinstance(weights, dict) and any(weights.values()) else counts
    )
    # 현재 분기를 만들었던 일기가 모두 삭제·수정됐다면 히스테리시스로 유령
    # 성격을 붙들지 않고 새 프로필을 처음부터 판정한다.
    if current is not None and float(evidence.get(current, 0) or 0) == 0:
        current = None
    if current is None:
        if (
            candidate is not None
            and total >= BRANCH_MIN_SAMPLES
            and ratio >= BRANCH_INITIAL_RATIO
            and margin >= BRANCH_INITIAL_MARGIN
        ):
            return candidate
        return "mixed" if finalizing else None

    if candidate is None or candidate == current:
        return current

    evidence_total = sum(
        float(evidence.get(key, 0.0) or 0.0) for key in EMOTION_CATEGORIES
    )
    current_ratio = (
        float(evidence.get(current, 0.0) or 0.0) / evidence_total
        if evidence_total
        else 0.0
    )
    if (
        total >= BRANCH_SWITCH_MIN_SAMPLES
        and ratio >= BRANCH_SWITCH_RATIO
        and ratio - current_ratio >= BRANCH_SWITCH_MARGIN
    ):
        return candidate
    return current


def final_form_from_profile(profile: dict, current_branch: str | None = None) -> str:
    branch = resolve_growth_branch(
        profile, len(STAGE_THRESHOLDS), current_branch, finalizing=True
    )
    return FINAL_FORM_BY_EMOTION[branch or "mixed"]


async def _lifecycle_entries(
    db: AsyncSession, plant: Plant, observed_at: datetime, *, lock: bool = False
) -> list[Any]:
    # 암호문 본문을 SQL 함수로 검사하지 않고 저장 시 계산한 길이만 읽는다.
    has_content = (MoodEntry.content_length > 0).label("has_content")
    query = (
        sa.select(
            MoodEntry.id,
            has_content,
            MoodEntry.analysis_status,
            MoodEntry.ai_emotion,
            MoodEntry.ai_scores,
        )
        .where(
            MoodEntry.user_id == plant.user_id,
            MoodEntry.recorded_at_utc >= plant.planted_at,
            MoodEntry.recorded_at_utc <= observed_at,
        )
        .order_by(MoodEntry.recorded_at_utc, MoodEntry.id)
    )
    if lock:
        query = query.with_for_update()
    rows = await db.execute(query)
    return list(rows.all())


async def refresh_active_plant_growth(
    db: AsyncSession,
    user_id: int,
    *,
    plant: Plant | None = None,
    observed_at: datetime | None = None,
    rebuild_profile: bool = True,
    lock_entries: bool = False,
) -> Plant | None:
    """현재 분석 상태로 활성 식물의 누적 프로필과 안정 분기를 갱신한다."""
    if plant is None:
        plant = await db.scalar(
            sa.select(Plant)
            .where(
                Plant.user_id == user_id,
                Plant.status == PlantStatus.ACTIVE,
            )
            .with_for_update()
        )
    if plant is None or plant.status != PlantStatus.ACTIVE:
        return None

    now = observed_at or utcnow()
    profile = plant.emotion_profile or empty_emotion_profile()
    if rebuild_profile:
        profile = build_emotion_profile(
            await _lifecycle_entries(db, plant, now, lock=lock_entries)
        )
    branch = resolve_growth_branch(
        profile, stage_from_exp(plant.exp), plant.growth_branch
    )
    if branch != plant.growth_branch:
        plant.growth_branch = branch
        plant.branch_decided_at = now if branch is not None else None
    plant.emotion_profile = profile
    return plant


async def snapshot_final_form(
    db: AsyncSession,
    plant: Plant,
    harvested_at: datetime,
    *,
    profile: dict | None = None,
) -> tuple[str, dict, str]:
    if profile is None:
        profile = build_emotion_profile(
            await _lifecycle_entries(db, plant, harvested_at, lock=True)
        )
    # 수확 직전 refresh에서 강한 새 근거까지 반영한 뒤, 마지막으로 보이던 안정
    # 분기를 그대로 고정한다. 안정 분기가 끝까지 없을 때만 모아결로 수확한다.
    branch = (
        resolve_growth_branch(
            profile, stage_from_exp(plant.exp), plant.growth_branch, finalizing=False
        )
        or "mixed"
    )
    return FINAL_FORM_BY_EMOTION[branch], profile, branch


def _branch_fields(
    plant: Plant,
    stage: int,
    *,
    harvested: bool = False,
    resolved_branch: str | None = None,
) -> dict:
    profile = plant.emotion_profile or empty_emotion_profile()
    branch = (
        resolved_branch
        if resolved_branch in EMOTION_CATEGORIES
        else plant.growth_branch
    )
    if harvested and resolved_branch is None:
        # 수확 표본은 final_form이 외형의 source of truth다. legacy 행의 branch가
        # 없거나 불일치해도 form/persona가 final_form과 갈라지지 않게 한다.
        branch = EMOTION_BY_FINAL_FORM.get(plant.final_form or "") or branch
    if not harvested and stage < BRANCH_START_STAGE:
        branch = None
    # 만개의 모호한 프로필은 모아결을 미리 보여 주되 DB의 안정 분기로 저장하지
    # 않는다. 후속 일기가 명확해지면 최초 임계값으로 다른 결을 선택할 수 있다.
    if (
        not harvested
        and stage == len(STAGE_THRESHOLDS)
        and branch is None
        and int(profile.get("pending_count", 0)) == 0
        and (
            int(profile.get("total", 0)) >= BRANCH_MIN_SAMPLES
            or int(profile.get("unavailable_count", 0)) > 0
        )
    ):
        branch = "mixed"

    ratios = profile.get("weighted_ratios") or profile.get("ratios") or {}
    cue_emotion, leader_ratio, _ = _leader(profile)
    confidence = float(ratios.get(branch, 0.0)) if branch else leader_ratio
    if harvested or branch is not None:
        status = "stable"
        phase = "branched"
    elif stage == 1:
        status = "observing"
        phase = "unformed"
    else:
        status = "emerging"
        phase = "hinting"
    form = FINAL_FORM_BY_EMOTION.get(branch) if branch else None
    cue_form = FINAL_FORM_BY_EMOTION.get(cue_emotion) if cue_emotion else None
    growth_traits = build_growth_traits(
        profile,
        stage,
        branch,
        harvested=harvested,
    )
    persona = None
    if branch in PERSONALITY_BY_EMOTION:
        persona = dict(PERSONALITY_BY_EMOTION[branch])
        secondary = growth_traits.get("secondary")
        if secondary:
            persona["trait"] = f"{persona['trait']} · {secondary['signature_trait']} 결"
        persona.update(
            {
                "title": growth_traits["title"],
                "growth_stage": stage,
                "growth_stage_name": STAGE_NAMES[stage],
                "dominant_emotion": branch,
                "dominant_ratio": (growth_traits.get("dominant") or {}).get(
                    "ratio", 0.0
                ),
                "secondary_emotion": (secondary.get("emotion") if secondary else None),
                "secondary_name": (
                    secondary.get("emotion_name") if secondary else None
                ),
                "secondary_ratio": secondary.get("ratio") if secondary else None,
                "temperament": growth_traits["temperament"],
                "chat_style": growth_traits["chat_style"],
            }
        )
    pending = int(profile.get("pending_count", 0))
    if pending:
        profile_state = "analyzing"
    elif int(profile.get("total", 0)) >= BRANCH_MIN_SAMPLES:
        profile_state = "ready"
    else:
        profile_state = "limited"
    growth_phase = {
        1: "seed",
        2: "sprout",
        3: "branching",
        4: "bloom",
        5: "full_bloom",
    }[stage]
    return {
        "stage": stage,
        "growth_branch": branch,
        "growth_form": form,
        "dominant_form": form,
        "growth_persona": persona,
        "personality": (
            {"code": persona["persona_key"], "name": persona["persona_name"]}
            if persona
            else None
        ),
        "branch_status": status,
        "branch_phase": phase,
        "growth_phase": growth_phase,
        "profile_state": profile_state,
        "branch_confidence": round(confidence, 4),
        "emotion_profile": profile,
        "growth_profile": profile,
        "growth_traits": growth_traits,
        "dominant_emotion": ((growth_traits.get("dominant") or {}).get("emotion")),
        "secondary_emotion": ((growth_traits.get("secondary") or {}).get("emotion")),
        "secondary_form": ((growth_traits.get("secondary") or {}).get("form")),
        "temperament": growth_traits["temperament"],
        "conversation_profile": growth_traits["chat_style"],
        "growth_cue": (
            {
                "emotion": cue_emotion,
                "form": cue_form,
                "confidence": round(leader_ratio, 4),
            }
            if stage >= 2 and branch is None and cue_form is not None
            else None
        ),
        "visual_key": (
            f"stage_{stage}_{form or 'base'}"
            f"_{(growth_traits.get('secondary') or {}).get('form')}"
            if growth_traits.get("secondary")
            else f"stage_{stage}_{form or 'base'}"
        ),
    }


def _species_payload(species) -> dict:
    manifest = getattr(species, "asset_manifest", None)
    return {
        "id": species.id,
        "code": species.code,
        "name": species.name,
        "rarity": int(getattr(species, "rarity", 1) or 1),
        "asset_manifest": manifest if isinstance(manifest, dict) else {},
    }


def _species_growth_identity(species) -> dict[str, str]:
    manifest = getattr(species, "asset_manifest", None)
    growth = manifest.get("growth") if isinstance(manifest, dict) else None
    configured = growth if isinstance(growth, dict) else {}
    fallback = _SPECIES_GROWTH_FALLBACKS.get(
        str(getattr(species, "code", "")), _GENERIC_GROWTH_IDENTITY
    )
    return {
        key: str(configured.get(key) or fallback[key])
        for key in _GENERIC_GROWTH_IDENTITY
    }


def growth_visual_payload(
    species,
    stage: int,
    *,
    form: str | None = None,
    cue_form: str | None = None,
    secondary_form: str | None = None,
) -> dict:
    """렌더러가 품종·단계·감정 레이어를 독립 조합할 수 있는 계약."""
    phase = {
        1: "seed",
        2: "sprout",
        3: "branching",
        4: "bloom",
        5: "full_bloom",
    }[stage]
    identity = _species_growth_identity(species)
    namespace = identity["asset_namespace"].rstrip("/")
    base_asset_key = f"{namespace}/stages/{phase}"
    seed_asset_key = f"{namespace}/seeds/{identity['seed_shape']}"
    vessel_asset_key = f"{namespace}/vessels/{identity['vessel_style']}"
    cue_asset_key = (
        f"{namespace}/cues/{cue_form}/{phase}" if stage == 2 and cue_form else None
    )
    branch_asset_key = (
        f"{namespace}/branches/{form}/{phase}"
        if stage >= BRANCH_START_STAGE and form
        else None
    )
    secondary_asset_key = (
        f"{namespace}/accents/{secondary_form}/{phase}"
        if stage >= SECONDARY_REVEAL_STAGE and secondary_form
        else None
    )
    render_layers = [vessel_asset_key]
    if stage == 1:
        render_layers.append(seed_asset_key)
    else:
        render_layers.append(base_asset_key)
    if cue_asset_key:
        render_layers.append(cue_asset_key)
    if branch_asset_key:
        render_layers.append(branch_asset_key)
    if secondary_asset_key:
        render_layers.append(secondary_asset_key)
    return {
        "stage": stage,
        "phase": phase,
        **identity,
        "seed_visible": stage == 1,
        "branch_visible": branch_asset_key is not None,
        "secondary_accent_visible": secondary_asset_key is not None,
        "seed_asset_key": seed_asset_key,
        "vessel_asset_key": vessel_asset_key,
        "base_asset_key": base_asset_key,
        "cue_asset_key": cue_asset_key,
        "branch_asset_key": branch_asset_key,
        "secondary_asset_key": secondary_asset_key,
        "render_layers": render_layers,
        "render_key": "|".join(render_layers),
    }


def plant_payload(plant: Plant, species) -> dict:
    stage = stage_from_exp(plant.exp)
    growth = _branch_fields(plant, stage)
    cue = growth.get("growth_cue") or {}
    secondary = growth.get("growth_traits", {}).get("secondary") or {}
    return {
        "id": plant.id,
        "name": plant.name,
        "species": _species_payload(species),
        "exp": plant.exp,
        "stage": stage,
        "stage_name": STAGE_NAMES[stage],
        "stage_thresholds": STAGE_THRESHOLDS,
        "next_stage_exp": next_stage_exp(plant.exp),
        "harvestable": is_harvestable(plant),
        "planted_at": plant.planted_at,
        **growth,
        "growth_visual": growth_visual_payload(
            species,
            stage,
            form=growth.get("growth_form"),
            cue_form=cue.get("form"),
            secondary_form=secondary.get("form"),
        ),
    }


def growth_state_payload(plant: Plant) -> dict:
    """품종 정보가 필요 없는 보상 응답용 성장 상태."""
    return _branch_fields(
        plant,
        stage_from_exp(plant.exp),
        harvested=plant.status == PlantStatus.HARVESTED,
    )


def museum_plant_payload(plant: Plant, species) -> dict:
    profile = plant.emotion_profile or empty_emotion_profile()
    final_form = plant.final_form or final_form_from_profile(
        profile, plant.growth_branch
    )
    resolved_branch = EMOTION_BY_FINAL_FORM[final_form]
    growth = _branch_fields(
        plant,
        len(STAGE_THRESHOLDS),
        harvested=True,
        resolved_branch=resolved_branch,
    )
    secondary = growth.get("growth_traits", {}).get("secondary") or {}
    return {
        "id": plant.id,
        "name": plant.name,
        "species": _species_payload(species),
        "exp": plant.exp,
        "planted_at": plant.planted_at,
        "harvested_at": plant.harvested_at,
        "final_form": final_form,
        "museum_featured": plant.museum_featured,
        **growth,
        "growth_visual": growth_visual_payload(
            species,
            len(STAGE_THRESHOLDS),
            form=growth.get("growth_form"),
            secondary_form=secondary.get("form"),
        ),
    }
