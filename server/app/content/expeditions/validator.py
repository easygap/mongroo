"""탐험 콘텐츠의 그래프·사건·안전 경로 정적 검증."""

from __future__ import annotations

import argparse
import copy
import heapq
import json
from pathlib import Path
from typing import Any

from app.content.expeditions.combat_difficulty import (
    STAGE_THREAT_PROFILES,
    validate_enemy_mechanic_code,
)
from app.content.expeditions.combat_identity import ELEMENT_LABELS
from app.content.expeditions.joint_guard import validate_joint_guard_content
from app.content.expeditions.skill_books import validate_skill_book_catalog
from app.content.expeditions.tangles import (
    TANGLE_CATALOG,
    validate_tangle_catalog,
)


ALLOWED_STATS = {"care", "focus", "courage", "insight"}
ALLOWED_SCENE_KEYS = {
    "dungeon_gate",
    "flooded_cave",
    "root_tunnel",
    "echo_well",
    "treasure_vault",
    "monster_den",
    "moon_tower",
}
ALLOWED_COMBAT_EFFECT_KEYS = {"insight_arc", "care_vines", "safe_guard"}

# 개편 설계서 3.1 — 지역당 8스테이지, 전투 4 · 이벤트 2 · 쉼터 1 · 보스 1.
STAGE_COUNT = 8
ALLOWED_STAGE_KINDS = {"battle", "event", "camp", "boss"}
STAGE_KIND_COUNTS = {"battle": 4, "event": 2, "camp": 1, "boss": 1}
ALLOWED_STORY_PHASES = {"setup", "rising", "turn", "truth", "climax", "resolution"}
ALLOWED_STORY_ASSETS = {"archive_postcard_reveal_v1"}
ALLOWED_STORY_AUDIO_CUES = {"story_postcard_reveal"}


class ContentValidationError(ValueError):
    def __init__(self, errors: list[str]):
        self.errors = errors
        super().__init__("\n".join(errors))


def expand_map_templates(content: dict[str, Any]) -> list[dict[str, Any]]:
    """기준 튜토리얼 지도에 간선·좌표 override를 적용해 독립 스냅샷을 만든다."""
    base = content.get("map")
    if not isinstance(base, dict):
        return []
    maps = [copy.deepcopy(base)]
    for override in content.get("map_templates", []):
        if not isinstance(override, dict):
            continue
        expanded = copy.deepcopy(base)
        expanded["code"] = override.get("code")
        expanded["name"] = override.get("name")
        expanded["edges"] = copy.deepcopy(override.get("edges", []))
        coordinate_overrides = override.get("coordinate_overrides", {})
        if isinstance(coordinate_overrides, dict):
            for node in expanded.get("nodes", []):
                values = coordinate_overrides.get(node.get("code"))
                if isinstance(values, dict):
                    node.update(values)
        maps.append(expanded)
    return maps


def validate_content(content: dict[str, Any]) -> None:
    errors: list[str] = []
    if content.get("schema_version") != 1:
        errors.append("schema_version: 지원하는 버전은 1입니다")
    if not isinstance(content.get("content_version"), str):
        errors.append("content_version: 문자열이 필요합니다")
    region = content.get("region")
    if not isinstance(region, dict) or not region.get("code"):
        errors.append("region: code가 있는 객체가 필요합니다")
    else:
        reward = region.get("reward")
        if not isinstance(reward, dict) or any(
            not isinstance(reward.get(key), int) or reward[key] < 0
            for key in ("exp", "seeds")
        ):
            errors.append("region.reward: 0 이상의 exp와 seeds가 필요합니다")

    events = content.get("events")
    if not isinstance(events, dict) or not events:
        errors.append("events: 사건 객체가 하나 이상 필요합니다")
        events = {}
    for event_code, event in events.items():
        _validate_event(event_code, event, errors)

    discoveries = content.get("discoveries")
    if not isinstance(discoveries, dict):
        errors.append("discoveries: 객체가 필요합니다")
        discoveries = {}

    maps = expand_map_templates(content)
    if len(maps) < 3:
        errors.append(
            f"map_templates: 기준 지도를 포함해 3종 이상이어야 합니다 (현재 {len(maps)})"
        )
    codes = [item.get("code") for item in maps]
    if len(codes) != len(set(codes)):
        errors.append("maps: 지도 code가 중복됩니다")
    for map_data in maps:
        _validate_map(map_data, events, discoveries, errors)

    _validate_stages(content, events, errors)

    threads = content.get("run_threads")
    if not isinstance(threads, list) or len(threads) != 3:
        errors.append("run_threads: 지역마다 정확히 3개의 완결 thread가 필요합니다")
    else:
        thread_codes: set[str] = set()
        for index, thread in enumerate(threads):
            prefix = f"run_threads[{index}]"
            if not isinstance(thread, dict):
                errors.append(f"{prefix}: 객체가 필요합니다")
                continue
            code = thread.get("code")
            if not isinstance(code, str) or not code:
                errors.append(f"{prefix}.code: 값이 필요합니다")
            elif code in thread_codes:
                errors.append(f"{prefix}.code: {code}가 중복됩니다")
            thread_codes.add(code)
            title = thread.get("title")
            if not isinstance(title, str) or not title.strip():
                errors.append(f"{prefix}.title: 비어 있지 않은 제목이 필요합니다")
            for key in ("seed_variants", "echo_variants"):
                variants = thread.get(key)
                if (
                    not isinstance(variants, list)
                    or len(variants) != 2
                    or any(
                        not isinstance(item, str) or not item.strip()
                        for item in variants
                    )
                ):
                    errors.append(f"{prefix}.{key}: 정확히 2개의 문장이 필요합니다")
            payoff_variants = thread.get("payoff_variants")
            if not isinstance(payoff_variants, dict) or set(payoff_variants) != {
                "careful",
                "bold",
                "relational",
            }:
                errors.append(
                    f"{prefix}.payoff_variants: careful/bold/relational 문장이 필요합니다"
                )
            elif any(
                not isinstance(item, str) or not item.strip()
                for item in payoff_variants.values()
            ):
                errors.append(f"{prefix}.payoff_variants: 빈 문장을 쓸 수 없습니다")

    if errors:
        raise ContentValidationError(errors)


def _validate_stages(
    content: dict[str, Any], events: dict[str, Any], errors: list[str]
) -> None:
    """지역당 8스테이지 구성을 강제한다.

    개편 설계서 3.1의 전투 4 · 이벤트 2 · 쉼터 1 · 보스 1 구성을 콘텐츠에서
    깨뜨리면 지도 화면이 진행도를 셀 수 없으므로 배포 전에 막는다. 엉킴의
    단일 원본은 tangles 카탈로그이며 pack은 code로만 참조한다.
    """

    errors.extend(validate_tangle_catalog())
    # 기록서 카탈로그도 같은 관문을 지난다. 등급·슬롯·activation 계약이
    # 깨진 채 배포되면 장착 화면이 고를 수 없는 책을 보여 주게 된다.
    errors.extend(validate_skill_book_catalog())
    # 합동 수호전은 지역 pack 밖에 있지만 같은 배포 관문을 지나야 한다.
    # 겹별 상성이 여섯 결에 고르게 퍼져 있는지, 결정적 순간마다 우회가
    # 있는지를 여기서 함께 센다.
    errors.extend(validate_joint_guard_content())

    stages = content.get("stages")
    if not isinstance(stages, list) or len(stages) != STAGE_COUNT:
        errors.append(f"stages: 지역당 정확히 {STAGE_COUNT}개가 필요합니다")
        return

    region_code = (content.get("region") or {}).get("code")
    kind_counts: dict[str, int] = {}
    story_codes: set[str] = set()
    for index, stage in enumerate(stages):
        prefix = f"stages[{index}]"
        if not isinstance(stage, dict):
            errors.append(f"{prefix}: 객체가 필요합니다")
            continue
        if stage.get("no") != index + 1:
            errors.append(f"{prefix}.no: {index + 1}이어야 합니다")
        kind = stage.get("kind")
        if kind not in ALLOWED_STAGE_KINDS:
            errors.append(
                f"{prefix}.kind: {sorted(ALLOWED_STAGE_KINDS)} 중 하나여야 합니다"
            )
        else:
            kind_counts[kind] = kind_counts.get(kind, 0) + 1
        for key in ("title", "summary"):
            if not isinstance(stage.get(key), str) or not stage[key].strip():
                errors.append(f"{prefix}.{key}: 비어 있지 않은 문장이 필요합니다")
        seconds = stage.get("estimated_seconds")
        if not isinstance(seconds, int) or not 20 <= seconds <= 180:
            errors.append(f"{prefix}.estimated_seconds: 20~180 사이 정수가 필요합니다")
        event_code = stage.get("event_code")
        if event_code is not None and event_code not in events:
            errors.append(f"{prefix}.event_code: 알 수 없는 사건 {event_code}")
        if kind in {"event", "boss"} and not event_code:
            errors.append(f"{prefix}.event_code: {kind} 스테이지에는 사건이 필요합니다")
        wave_codes = stage.get("tangles") or []
        for code in wave_codes:
            if code not in TANGLE_CATALOG:
                errors.append(f"{prefix}.tangles: 알 수 없는 엉킴 {code}")
            elif TANGLE_CATALOG[code]["region_code"] != region_code:
                errors.append(f"{prefix}.tangles: {code}는 다른 지역의 엉킴입니다")
        if kind == "battle" and not 1 <= len(wave_codes) <= 3:
            errors.append(
                f"{prefix}.tangles: 전투 스테이지는 웨이브 1~3개가 필요합니다"
            )
        if kind == "battle" and wave_codes:
            first = TANGLE_CATALOG.get(wave_codes[0]) or {}
            expected = (first.get("weakness_cycle") or [None])[0]
            # 지도 시트의 약점 힌트는 첫 웨이브의 첫 약점과 같아야 사기가 아니다.
            if stage.get("weakness") != expected:
                errors.append(
                    f"{prefix}.weakness: 첫 웨이브의 첫 약점({expected})과 일치해야 합니다"
                )
        difficulty_code = stage.get("difficulty_code", f"stage_{index + 1}")
        if difficulty_code not in STAGE_THREAT_PROFILES:
            errors.append(
                f"{prefix}.difficulty_code: 알 수 없는 위협 프로필 {difficulty_code}"
            )
        weakness = stage.get("weakness")
        if weakness is not None and weakness not in ALLOWED_STATS:
            errors.append(
                f"{prefix}.weakness: {sorted(ALLOWED_STATS)} 중 하나여야 합니다"
            )
        _validate_stage_story(
            stage.get("story"),
            expected_chapter=index + 1,
            prefix=f"{prefix}.story",
            seen_codes=story_codes,
            errors=errors,
        )

    for kind, expected in STAGE_KIND_COUNTS.items():
        if kind_counts.get(kind, 0) != expected:
            errors.append(
                f"stages.kind: {kind}가 {expected}개여야 합니다 "
                f"(현재 {kind_counts.get(kind, 0)})"
            )
    if stages and stages[-1].get("kind") != "boss":
        errors.append("stages: 마지막 스테이지는 수호짐승 보스여야 합니다")


def _validate_stage_story(
    story: Any,
    *,
    expected_chapter: int,
    prefix: str,
    seen_codes: set[str],
    errors: list[str],
) -> None:
    """최초 클리어 컷을 짧고 결정적인 한 장면으로 유지한다."""

    if not isinstance(story, dict):
        errors.append(f"{prefix}: 최초 클리어 이야기 객체가 필요합니다")
        return
    code = story.get("code")
    if not isinstance(code, str) or not code.strip():
        errors.append(f"{prefix}.code: 값이 필요합니다")
    elif code in seen_codes:
        errors.append(f"{prefix}.code: {code}가 중복됩니다")
    else:
        seen_codes.add(code)
    if story.get("chapter") != expected_chapter:
        errors.append(f"{prefix}.chapter: {expected_chapter}이어야 합니다")
    if story.get("phase") not in ALLOWED_STORY_PHASES:
        errors.append(
            f"{prefix}.phase: {sorted(ALLOWED_STORY_PHASES)} 중 하나여야 합니다"
        )
    for key, limit in (("title", 28), ("caption", 100), ("codex_entry", 80)):
        value = story.get(key)
        if not isinstance(value, str) or not value.strip():
            errors.append(f"{prefix}.{key}: 비어 있지 않은 문장이 필요합니다")
        elif len(value) > limit:
            errors.append(f"{prefix}.{key}: {limit}자 이하여야 합니다")
    if story.get("scene_key") not in ALLOWED_SCENE_KEYS:
        errors.append(f"{prefix}.scene_key: 지원하지 않는 장면입니다")
    visual_asset = story.get("visual_asset")
    if visual_asset is not None and visual_asset not in ALLOWED_STORY_ASSETS:
        errors.append(f"{prefix}.visual_asset: 지원하지 않는 스토리 에셋입니다")
    audio_cue = story.get("audio_cue")
    if audio_cue is not None and audio_cue not in ALLOWED_STORY_AUDIO_CUES:
        errors.append(f"{prefix}.audio_cue: 지원하지 않는 오디오 cue입니다")
    if audio_cue is not None and visual_asset is None:
        errors.append(f"{prefix}: 오디오 cue는 검수된 시각 에셋과 함께 써야 합니다")


def _validate_event(event_code: str, event: Any, errors: list[str]) -> None:
    prefix = f"events.{event_code}"
    if not isinstance(event, dict):
        errors.append(f"{prefix}: 객체가 필요합니다")
        return
    choices = event.get("choices")
    if not isinstance(choices, list) or len(choices) < 3:
        errors.append(f"{prefix}.choices: 능력치 선택 2개와 안전 선택이 필요합니다")
        return
    encounter = event.get("encounter")
    if encounter is not None:
        if not isinstance(encounter, dict):
            errors.append(f"{prefix}.encounter: 객체가 필요합니다")
        else:
            if encounter.get("kind") != "guardian":
                errors.append(f"{prefix}.encounter.kind: guardian이어야 합니다")
            for field in (
                "enemy_name",
                "attack_name",
                "telegraph",
                "damage_target",
            ):
                if (
                    not isinstance(encounter.get(field), str)
                    or not encounter[field].strip()
                ):
                    errors.append(f"{prefix}.encounter.{field}: 값이 필요합니다")
            max_guard = encounter.get("enemy_max_guard")
            if (
                not isinstance(max_guard, int)
                or isinstance(max_guard, bool)
                or max_guard <= 0
            ):
                errors.append(
                    f"{prefix}.encounter.enemy_max_guard: 1 이상의 정수가 필요합니다"
                )
            for field, minimum in (
                ("max_rounds", 2),
                ("starting_focus", 0),
                ("max_focus", 1),
            ):
                value = encounter.get(field)
                if (
                    not isinstance(value, int)
                    or isinstance(value, bool)
                    or value < minimum
                ):
                    errors.append(
                        f"{prefix}.encounter.{field}: {minimum} 이상의 정수가 필요합니다"
                    )
            difficulty_code = encounter.get("difficulty_code")
            if difficulty_code not in STAGE_THREAT_PROFILES:
                errors.append(
                    f"{prefix}.encounter.difficulty_code: 지원하지 않는 위협 프로필입니다"
                )
            if (
                isinstance(encounter.get("starting_focus"), int)
                and isinstance(encounter.get("max_focus"), int)
                and encounter["starting_focus"] > encounter["max_focus"]
            ):
                errors.append(
                    f"{prefix}.encounter.starting_focus: max_focus 이하여야 합니다"
                )
            weaknesses = encounter.get("weakness_cycle")
            if (
                not isinstance(weaknesses, list)
                or len(weaknesses) < 2
                or any(item not in ALLOWED_STATS for item in weaknesses)
            ):
                errors.append(
                    f"{prefix}.encounter.weakness_cycle: 서로 다른 감정 상성 2개 이상이 필요합니다"
                )
            elif len(weaknesses) != len(set(weaknesses)):
                errors.append(
                    f"{prefix}.encounter.weakness_cycle: 같은 상성을 중복할 수 없습니다"
                )
            intents = encounter.get("intents")
            if not isinstance(intents, list) or len(intents) < 2:
                errors.append(
                    f"{prefix}.encounter.intents: 예고 공격이 2개 이상 필요합니다"
                )
            else:
                intent_codes: set[str] = set()
                for index, intent in enumerate(intents):
                    intent_prefix = f"{prefix}.encounter.intents[{index}]"
                    if not isinstance(intent, dict):
                        errors.append(f"{intent_prefix}: 객체가 필요합니다")
                        continue
                    code = intent.get("code")
                    if not isinstance(code, str) or not code:
                        errors.append(f"{intent_prefix}.code: 값이 필요합니다")
                    elif code in intent_codes:
                        errors.append(f"{intent_prefix}.code: {code}가 중복됩니다")
                    intent_codes.add(code)
                    for field in ("name", "telegraph"):
                        if (
                            not isinstance(intent.get(field), str)
                            or not intent[field].strip()
                        ):
                            errors.append(f"{intent_prefix}.{field}: 값이 필요합니다")
                    if intent.get("target") not in {"front", "all", "lowest"}:
                        errors.append(
                            f"{intent_prefix}.target: front, all, lowest 중 하나여야 합니다"
                        )
                    power = intent.get("power")
                    if (
                        not isinstance(power, int)
                        or isinstance(power, bool)
                        or power < 1
                    ):
                        errors.append(f"{intent_prefix}.power: 1 이상이어야 합니다")
            boss_phases = encounter.get("boss_phases")
            if boss_phases is not None:
                if not isinstance(boss_phases, list) or len(boss_phases) != 3:
                    errors.append(
                        f"{prefix}.encounter.boss_phases: 정확히 3개 페이즈가 필요합니다"
                    )
                else:
                    thresholds: list[int] = []
                    phase_codes: set[str] = set()
                    for index, phase in enumerate(boss_phases):
                        phase_prefix = f"{prefix}.encounter.boss_phases[{index}]"
                        if not isinstance(phase, dict):
                            errors.append(f"{phase_prefix}: 객체가 필요합니다")
                            continue
                        for field in ("code", "name", "intro_caption"):
                            if (
                                not isinstance(phase.get(field), str)
                                or not phase[field].strip()
                            ):
                                errors.append(
                                    f"{phase_prefix}.{field}: 값이 필요합니다"
                                )
                        for field in ("rule_name", "rule_summary"):
                            if (
                                not isinstance(phase.get(field), str)
                                or not phase[field].strip()
                            ):
                                errors.append(
                                    f"{phase_prefix}.{field}: 값이 필요합니다"
                                )
                        if phase.get("phase_gate") not in {None, "resolve_intent"}:
                            errors.append(
                                f"{phase_prefix}.phase_gate: resolve_intent만 지원합니다"
                            )
                        code = phase.get("code")
                        if isinstance(code, str) and code in phase_codes:
                            errors.append(f"{phase_prefix}.code: 중복할 수 없습니다")
                        if isinstance(code, str):
                            phase_codes.add(code)
                        threshold = phase.get("threshold_bp")
                        if (
                            not isinstance(threshold, int)
                            or isinstance(threshold, bool)
                            or not 1 <= threshold <= 10_000
                        ):
                            errors.append(
                                f"{phase_prefix}.threshold_bp: 1~10000 정수가 필요합니다"
                            )
                        else:
                            thresholds.append(threshold)
                        weak_element = phase.get("weak_element")
                        resist_element = phase.get("resist_element")
                        if weak_element not in ELEMENT_LABELS:
                            errors.append(
                                f"{phase_prefix}.weak_element: 지원 원소가 아닙니다"
                            )
                        if resist_element not in ELEMENT_LABELS:
                            errors.append(
                                f"{phase_prefix}.resist_element: 지원 원소가 아닙니다"
                            )
                        if weak_element == resist_element:
                            errors.append(
                                f"{phase_prefix}: 약점과 내성 원소가 달라야 합니다"
                            )
                        phase_cycle = phase.get("weakness_cycle")
                        if (
                            not isinstance(phase_cycle, list)
                            or len(phase_cycle) < 2
                            or any(item not in ALLOWED_STATS for item in phase_cycle)
                        ):
                            errors.append(
                                f"{phase_prefix}.weakness_cycle: 상성 2개 이상이 필요합니다"
                            )
                        for field in ("intent_power_bonus", "focus_reward"):
                            value = phase.get(field)
                            if (
                                not isinstance(value, int)
                                or isinstance(value, bool)
                                or value < 0
                            ):
                                errors.append(
                                    f"{phase_prefix}.{field}: 0 이상의 정수가 필요합니다"
                                )
                        phase_intents = phase.get("intents")
                        if (
                            not isinstance(phase_intents, list)
                            or len(phase_intents) < 2
                        ):
                            errors.append(
                                f"{phase_prefix}.intents: 페이즈 전용 예고 2개 이상이 필요합니다"
                            )
                        else:
                            for intent_index, phase_intent in enumerate(phase_intents):
                                where = f"{phase_prefix}.intents[{intent_index}]"
                                if not isinstance(phase_intent, dict):
                                    errors.append(f"{where}: 객체가 필요합니다")
                                    continue
                                if not validate_enemy_mechanic_code(
                                    phase_intent.get("mechanic_code")
                                ):
                                    errors.append(
                                        f"{where}.mechanic_code: 지원하지 않는 적 기믹입니다"
                                    )
                                unlock = phase_intent.get("mechanic_unlock")
                                if (
                                    not isinstance(unlock, int)
                                    or isinstance(unlock, bool)
                                    or not 1 <= unlock <= 3
                                ):
                                    errors.append(
                                        f"{where}.mechanic_unlock: 1~3 정수가 필요합니다"
                                    )
                    if thresholds and (
                        thresholds[0] != 10_000
                        or thresholds != sorted(thresholds, reverse=True)
                        or len(thresholds) != len(set(thresholds))
                    ):
                        errors.append(
                            f"{prefix}.encounter.boss_phases: 임계치는 10000부터 내림차순이어야 합니다"
                        )
    choice_codes: set[str] = set()
    stats: set[str] = set()
    safe_count = 0
    for index, choice in enumerate(choices):
        choice_prefix = f"{prefix}.choices[{index}]"
        if not isinstance(choice, dict):
            errors.append(f"{choice_prefix}: 객체가 필요합니다")
            continue
        code = choice.get("code")
        if not isinstance(code, str) or not code:
            errors.append(f"{choice_prefix}.code: 값이 필요합니다")
        elif code in choice_codes:
            errors.append(f"{choice_prefix}.code: {code}가 중복됩니다")
        choice_codes.add(code)
        if choice.get("safe") is True:
            safe_count += 1
            if choice.get("stat") is not None or choice.get("resolve_cost") != 0:
                errors.append(
                    f"{choice_prefix}: 안전 선택은 stat=null, resolve_cost=0이어야 합니다"
                )
        elif encounter is not None:
            guard_damage = choice.get("guard_damage")
            if (
                not isinstance(guard_damage, int)
                or isinstance(guard_damage, bool)
                or guard_damage <= 0
            ):
                errors.append(
                    f"{choice_prefix}.guard_damage: 전투 선택에는 1 이상의 정수가 필요합니다"
                )
        if encounter is not None:
            effect_key = choice.get("effect_key")
            if effect_key not in ALLOWED_COMBAT_EFFECT_KEYS:
                errors.append(
                    f"{choice_prefix}.effect_key: 지원하지 않는 전투 이펙트입니다"
                )
        if choice.get("safe") is True:
            if encounter is not None and choice.get("guard_damage") != 0:
                errors.append(
                    f"{choice_prefix}.guard_damage: 안전 선택은 0이어야 합니다"
                )
            continue
        stat = choice.get("stat")
        if stat not in ALLOWED_STATS:
            errors.append(f"{choice_prefix}.stat: 지원하지 않는 능력치입니다")
        else:
            stats.add(stat)
        difficulty = choice.get("difficulty")
        if not isinstance(difficulty, int) or difficulty <= 0:
            errors.append(f"{choice_prefix}.difficulty: 1 이상의 정수가 필요합니다")
    if len(stats) < 2:
        errors.append(f"{prefix}: 서로 다른 능력치 해결법이 2개 이상 필요합니다")
    if safe_count != 1:
        errors.append(f"{prefix}: 안전 선택이 정확히 하나여야 합니다")


def _validate_map(
    map_data: Any,
    events: dict[str, Any],
    discoveries: dict[str, Any],
    errors: list[str],
) -> None:
    if not isinstance(map_data, dict):
        errors.append("maps: 지도 객체가 필요합니다")
        return
    code = map_data.get("code") or "<unknown>"
    prefix = f"maps.{code}"
    nodes = map_data.get("nodes")
    if not isinstance(nodes, list) or len(nodes) < 4:
        errors.append(f"{prefix}.nodes: 네 개 이상의 노드가 필요합니다")
        return
    by_code: dict[str, dict] = {}
    type_counts: dict[str, int] = {}
    for index, node in enumerate(nodes):
        node_prefix = f"{prefix}.nodes[{index}]"
        if not isinstance(node, dict):
            errors.append(f"{node_prefix}: 객체가 필요합니다")
            continue
        node_code = node.get("code")
        if not isinstance(node_code, str) or not node_code:
            errors.append(f"{node_prefix}.code: 값이 필요합니다")
            continue
        if node_code in by_code:
            errors.append(f"{node_prefix}.code: {node_code}가 중복됩니다")
        by_code[node_code] = node
        node_type = node.get("type")
        type_counts[node_type] = type_counts.get(node_type, 0) + 1
        if not isinstance(node.get("x"), (int, float)) or not 0 <= node["x"] <= 1:
            errors.append(f"{node_prefix}.x: 0~1 좌표가 필요합니다")
        if not isinstance(node.get("y"), (int, float)) or not 0 <= node["y"] <= 1:
            errors.append(f"{node_prefix}.y: 0~1 좌표가 필요합니다")
        if not isinstance(node.get("cost"), int) or node["cost"] < 0:
            errors.append(f"{node_prefix}.cost: 0 이상의 정수가 필요합니다")
        scene_key = node.get("scene_key")
        if scene_key not in ALLOWED_SCENE_KEYS:
            errors.append(f"{node_prefix}.scene_key: 지원하지 않는 장면입니다")
        for field in ("scene_label", "scene_description", "depth_label"):
            if not isinstance(node.get(field), str) or not node[field].strip():
                errors.append(
                    f"{node_prefix}.{field}: 비어 있지 않은 문장이 필요합니다"
                )
        threat_level = node.get("threat_level")
        if (
            not isinstance(threat_level, int)
            or isinstance(threat_level, bool)
            or not 0 <= threat_level <= 3
        ):
            errors.append(f"{node_prefix}.threat_level: 0~3 정수가 필요합니다")
        event_code = node.get("event_code")
        if event_code is not None and event_code not in events:
            errors.append(f"{node_prefix}.event_code: {event_code} 사건이 없습니다")
        if node_type == "discovery" and node_code not in discoveries:
            errors.append(f"{node_prefix}: 발견 문장이 없습니다")

    for required_type in ("entrance", "objective", "exit"):
        if type_counts.get(required_type) != 1:
            errors.append(f"{prefix}: {required_type} 노드가 정확히 하나여야 합니다")
    entrance = map_data.get("entrance")
    if entrance not in by_code or by_code.get(entrance, {}).get("type") != "entrance":
        errors.append(f"{prefix}.entrance: entrance 노드를 가리켜야 합니다")

    adjacency = {node_code: set() for node_code in by_code}
    seen_edges: set[tuple[str, str]] = set()
    edges = map_data.get("edges")
    if not isinstance(edges, list):
        errors.append(f"{prefix}.edges: 배열이 필요합니다")
        edges = []
    for index, edge in enumerate(edges):
        if not isinstance(edge, list) or len(edge) != 2:
            errors.append(f"{prefix}.edges[{index}]: 노드 code 두 개가 필요합니다")
            continue
        left, right = edge
        if left not in by_code or right not in by_code:
            errors.append(f"{prefix}.edges[{index}]: 존재하지 않는 노드를 참조합니다")
            continue
        if left == right:
            errors.append(f"{prefix}.edges[{index}]: 자기 자신을 연결할 수 없습니다")
            continue
        normalized = tuple(sorted((left, right)))
        if normalized in seen_edges:
            errors.append(f"{prefix}.edges[{index}]: 중복 간선입니다")
            continue
        seen_edges.add(normalized)
        adjacency[left].add(right)
        adjacency[right].add(left)

    if entrance in adjacency:
        reachable = _reachable(adjacency, entrance)
        missing = set(by_code) - reachable
        if missing:
            errors.append(f"{prefix}: 입구에서 갈 수 없는 노드 {sorted(missing)}")
    objective = next(
        (
            node_code
            for node_code, node in by_code.items()
            if node.get("type") == "objective"
        ),
        None,
    )
    exit_code = next(
        (
            node_code
            for node_code, node in by_code.items()
            if node.get("type") == "exit"
        ),
        None,
    )
    if entrance in adjacency and objective in adjacency:
        if _path_count(adjacency, entrance, objective, limit=2) < 2:
            errors.append(
                f"{prefix}: 입구에서 목표까지 서로 다른 경로가 2개 이상 필요합니다"
            )
        minimum_cost = _minimum_cost(adjacency, by_code, entrance, objective)
        if minimum_cost > 10:
            errors.append(f"{prefix}: 시작 길빛 10으로 목표에 도달할 수 없습니다")
    if entrance in adjacency and exit_code in adjacency and objective is not None:
        without_objective = {
            node: {neighbor for neighbor in neighbors if neighbor != objective}
            for node, neighbors in adjacency.items()
            if node != objective
        }
        if exit_code in _reachable(without_objective, entrance):
            errors.append(f"{prefix}: 목표를 거치지 않고 출구에 도달할 수 있습니다")
    initial = map_data.get("initial_revealed")
    if not isinstance(initial, list) or entrance not in initial:
        errors.append(f"{prefix}.initial_revealed: 입구를 포함해야 합니다")
    elif any(node_code not in by_code for node_code in initial):
        errors.append(f"{prefix}.initial_revealed: 존재하지 않는 노드가 있습니다")


def _reachable(adjacency: dict[str, set[str]], start: str) -> set[str]:
    if start not in adjacency:
        return set()
    seen = {start}
    pending = [start]
    while pending:
        current = pending.pop()
        for neighbor in adjacency.get(current, set()):
            if neighbor not in seen:
                seen.add(neighbor)
                pending.append(neighbor)
    return seen


def _path_count(
    adjacency: dict[str, set[str]], start: str, target: str, *, limit: int
) -> int:
    count = 0

    def visit(current: str, seen: set[str]) -> None:
        nonlocal count
        if count >= limit:
            return
        if current == target:
            count += 1
            return
        for neighbor in adjacency.get(current, set()):
            if neighbor not in seen:
                visit(neighbor, seen | {neighbor})

    visit(start, {start})
    return count


def _minimum_cost(
    adjacency: dict[str, set[str]], nodes: dict[str, dict], start: str, target: str
) -> int:
    distances = {start: 0}
    queue: list[tuple[int, str]] = [(0, start)]
    while queue:
        distance, current = heapq.heappop(queue)
        if current == target:
            return distance
        if distance != distances[current]:
            continue
        for neighbor in adjacency.get(current, set()):
            next_distance = distance + int(nodes[neighbor].get("cost", 0))
            if next_distance < distances.get(neighbor, 1_000_000):
                distances[neighbor] = next_distance
                heapq.heappush(queue, (next_distance, neighbor))
    return 1_000_000


def main() -> int:
    parser = argparse.ArgumentParser(description="직접 탐험 콘텐츠 계약 검증")
    parser.add_argument("paths", nargs="+", type=Path)
    args = parser.parse_args()
    failed = False
    for path in args.paths:
        try:
            with path.open(encoding="utf-8") as file:
                validate_content(json.load(file))
            print(f"OK {path}")
        except (OSError, json.JSONDecodeError, ContentValidationError) as error:
            failed = True
            print(f"FAIL {path}\n{error}")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
