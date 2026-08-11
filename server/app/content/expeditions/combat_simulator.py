"""결정론적 탐험 전투 밸런스 전수 시뮬레이터.

현재 전투 엔진에는 난수가 없다. 같은 입력을 seed만 바꿔 반복하는 대신 품종, 감정,
등급, 권장 레벨 경계, 지역, 스테이지 형태를 전수 계산한다. 정책만 분리해 수치와
상성 선택의 영향을 같은 입력끼리 비교한다.
"""

from __future__ import annotations

from collections import Counter, defaultdict
from collections.abc import Iterable, Mapping, Sequence
from dataclasses import dataclass
from datetime import UTC, datetime
from typing import Any, Literal

from app.content.expeditions.combat import (
    guardian_battle_payload,
    new_guardian_battle,
    submit_guardian_action,
)
from app.content.expeditions.combat_balance import (
    COMBAT_BALANCE_VERSION,
    REGION_COMBAT_BANDS,
)
from app.content.expeditions.combat_identity import (
    EMOTION_DISCIPLINES,
    SPECIES_SKILLS,
)
from app.content.expeditions.tangles import TANGLE_CATALOG


PolicyCode = Literal["max_damage", "weakness_first", "survival"]
POLICIES: tuple[PolicyCode, ...] = (
    "max_damage",
    "weakness_first",
    "survival",
)
SLOT_ORDER = {
    "attack": 0,
    "selected_1": 1,
    "unique_1": 2,
    "selected_2": 3,
    "unique_2": 4,
}


@dataclass(frozen=True)
class SimulationCase:
    species: str
    form: str
    rarity: int
    level: int
    region_code: str
    stage_shape: str
    waves: tuple[str, ...]

    @property
    def key(self) -> str:
        return ":".join(
            (
                self.species,
                self.form,
                str(self.rarity),
                str(self.level),
                self.region_code,
                self.stage_shape,
            )
        )


@dataclass
class SimulationResult:
    case: SimulationCase
    policy: PolicyCode
    victory: bool
    rounds: int
    max_rounds: int
    actions: Counter[str]
    opportunities: Counter[str]
    weakness_hits: int
    damage_actions: int
    total_damage: int
    weak_neutral_damage: int
    weak_bonus_damage: int
    remaining_hp: int
    maximum_hp: int

    @property
    def score_rounds(self) -> int:
        """패배를 제한 라운드 다음 값으로 두어 정책 간 paired 비교에 포함한다."""

        return self.rounds if self.victory else self.max_rounds + 1


def _profile(
    member_id: int,
    *,
    species: str,
    form: str,
    level: int,
    rarity: int,
    guide: bool = False,
) -> dict[str, Any]:
    stats = (
        {"care": 6, "focus": 6, "courage": 5, "insight": 7}
        if guide
        else {"care": 6, "focus": 6, "courage": 6, "insight": 6}
    )
    return {
        "id": member_id,
        "position": member_id - 1,
        "is_guide": guide,
        "snapshot": {
            "name": f"시뮬 대원 {member_id}",
            "species": {"code": species},
            "form": form,
            "level": level,
            "rarity": rarity,
            "stage": 2 if guide else 5,
            "stats": stats,
        },
    }


def party_for_case(case: SimulationCase) -> list[dict[str, Any]]:
    """무료 기준인 실소유 대원 1명 + Lv16 길잡이 2명을 만든다."""

    return [
        _profile(
            1,
            species=case.species,
            form=case.form,
            level=case.level,
            rarity=case.rarity,
        ),
        _profile(
            2,
            species="archive_guide",
            form="mosaic",
            level=16,
            rarity=1,
            guide=True,
        ),
        _profile(
            3,
            species="archive_guide",
            form="mosaic",
            level=16,
            rarity=1,
            guide=True,
        ),
    ]


def encounter_for_case(case: SimulationCase) -> dict[str, Any]:
    return {
        "waves": list(case.waves),
        "max_rounds": 4 * len(case.waves),
        "starting_focus": 3,
        "max_focus": 5,
    }


def _region_stage_shapes(region_code: str) -> Mapping[str, tuple[str, ...]]:
    tangles = [
        (code, tangle)
        for code, tangle in TANGLE_CATALOG.items()
        if tangle["region_code"] == region_code
    ]
    normal = [code for code, tangle in tangles if not bool(tangle["elite"])]
    elite = [code for code, tangle in tangles if bool(tangle["elite"])]
    if len(normal) != 2 or len(elite) != 1:
        raise ValueError(f"{region_code}: 일반 2종과 큰 엉킴 1종이 필요합니다")
    return {
        "tutorial": (normal[0],),
        "standard": (normal[0], normal[1]),
        "elite": (elite[0],),
        "mixed": (normal[1], elite[0]),
    }


def simulation_cases() -> Iterable[SimulationCase]:
    species_codes = sorted(set(SPECIES_SKILLS) - {"archive_guide"})
    forms = tuple(EMOTION_DISCIPLINES)
    for species in species_codes:
        for form in forms:
            for rarity in range(1, 6):
                for region_code, band in REGION_COMBAT_BANDS.items():
                    for level in dict.fromkeys(band["recommended_level"]):
                        for stage_shape, waves in _region_stage_shapes(
                            region_code
                        ).items():
                            yield SimulationCase(
                                species=species,
                                form=form,
                                rarity=rarity,
                                level=level,
                                region_code=region_code,
                                stage_shape=stage_shape,
                                waves=waves,
                            )


def _living_payload_members(payload: Mapping[str, Any]) -> list[dict[str, Any]]:
    acted = set(payload.get("pending_round", {}).get("acted", []))
    return [
        member
        for member in payload.get("party", [])
        if int(member["hp"]) > 0 and int(member["member_id"]) not in acted
    ]


def _current_intent(payload: Mapping[str, Any]) -> Mapping[str, Any]:
    return payload.get("enemy", {}).get("intent", {})


def _survival_actor(
    payload: Mapping[str, Any],
    available_members: Sequence[dict[str, Any]],
) -> dict[str, Any]:
    intent = _current_intent(payload)
    target = intent.get("target", "front")
    if target == "lowest":
        return min(
            available_members,
            key=lambda member: (int(member["hp"]), int(member["member_id"])),
        )
    if target == "front" and not payload.get("pending_round", {}).get("acted"):
        return max(
            available_members,
            key=lambda member: (int(member["hp"]), -int(member["member_id"])),
        )
    return available_members[0]


def _skill_candidates(
    member: Mapping[str, Any],
    *,
    focus: int,
) -> list[dict[str, Any]]:
    kit = member["kit"]
    candidates = [{"slot": "attack", **kit["basic"]}]
    for skill in [*kit["unique_skills"], *kit["selected_skills"]]:
        if (
            bool(skill.get("available"))
            and int(skill.get("cooldown_remaining", 0)) == 0
            and int(skill.get("focus_cost", 0)) <= focus
        ):
            candidates.append({"slot": str(skill["slot"]), **skill})
    return candidates


def _would_be_targeted(
    payload: Mapping[str, Any],
    actor: Mapping[str, Any],
) -> bool:
    intent = _current_intent(payload)
    target = intent.get("target", "front")
    if target == "all":
        return True
    living = [member for member in payload.get("party", []) if int(member["hp"]) > 0]
    if target == "lowest":
        lowest = min(
            living,
            key=lambda member: (int(member["hp"]), int(member["member_id"])),
        )
        return int(actor["member_id"]) == int(lowest["member_id"])
    acted = payload.get("pending_round", {}).get("acted", [])
    if not acted:
        return True
    return int(actor["member_id"]) == int(living[0]["member_id"])


def _choose_action(
    payload: Mapping[str, Any],
    actor: Mapping[str, Any],
    *,
    policy: PolicyCode,
) -> tuple[str, list[str]]:
    focus = int(payload.get("focus", 0))
    candidates = _skill_candidates(actor, focus=focus)
    opportunities = [str(candidate["slot"]) for candidate in candidates]
    intent_power = int(_current_intent(payload).get("power", 0))

    if policy == "survival":
        weakeners = [
            candidate
            for candidate in candidates
            if candidate.get("effect") == "weaken_intent"
        ]
        if intent_power >= 2 and weakeners:
            choice = max(
                weakeners,
                key=lambda item: (
                    int(item["power"]),
                    SLOT_ORDER[str(item["slot"])],
                ),
            )
            return str(choice["slot"]), [*opportunities, "guard"]
        if (
            _would_be_targeted(payload, actor)
            and intent_power >= int(actor["hp"])
        ):
            return "guard", [*opportunities, "guard"]

    ranked_pool = candidates
    if policy in {"weakness_first", "survival"}:
        weak = [item for item in candidates if item.get("matchup") == "weak"]
        if weak:
            ranked_pool = weak
    # max_damage는 이름 그대로 상성을 모르는 비교군이다. 최종 power를 보면 약점
    # 배수가 이미 반영되어 weakness_first와 같은 결정을 하므로 중립 위력을 쓴다.
    power_key = "power_neutral" if policy == "max_damage" else "power"
    choice = max(
        ranked_pool,
        key=lambda item: (
            int(item.get(power_key, item["power"])),
            -int(item.get("focus_cost", 0)),
            SLOT_ORDER[str(item["slot"])],
        ),
    )
    return str(choice["slot"]), [*opportunities, "guard"]


def simulate_case(case: SimulationCase, policy: PolicyCode) -> SimulationResult:
    profiles = party_for_case(case)
    encounter = encounter_for_case(case)
    state = new_guardian_battle(f"sim:{case.key}", encounter, profiles)
    actions: Counter[str] = Counter()
    opportunities: Counter[str] = Counter()
    weakness_hits = 0
    damage_actions = 0
    total_damage = 0
    weak_neutral_damage = 0
    weak_bonus_damage = 0
    command_count = 0

    while state["status"] == "active":
        payload = guardian_battle_payload(state, encounter, profiles)
        available_members = _living_payload_members(payload)
        if not available_members:
            break
        actor = (
            _survival_actor(payload, available_members)
            if policy == "survival"
            else available_members[0]
        )
        action, available_slots = _choose_action(payload, actor, policy=policy)
        opportunities.update(available_slots)
        state = submit_guardian_action(
            state,
            {"member_id": int(actor["member_id"]), "action": action},
            encounter,
            profiles,
        )
        actions[action] += 1
        command_count += 1
        for event in state.get("last_exchange", []):
            if event.get("type") != "party_action":
                continue
            if int(event.get("damage", 0)) > 0:
                damage_actions += 1
                total_damage += int(event["damage"])
            if bool(event.get("weakness_hit")):
                weakness_hits += 1
                neutral_damage = int(event.get("power_neutral", event["damage"]))
                weak_neutral_damage += neutral_damage
                weak_bonus_damage += max(0, int(event["damage"]) - neutral_damage)
        if command_count > 3 * (int(encounter["max_rounds"]) + len(case.waves)):
            raise RuntimeError(f"{case.key}: 전투 명령 안전 한도를 넘었습니다")

    maximum_hp = sum(int(member["max_hp"]) for member in state["party"])
    remaining_hp = sum(int(member["hp"]) for member in state["party"])
    return SimulationResult(
        case=case,
        policy=policy,
        victory=state["status"] == "victory",
        rounds=int(state["round"]),
        max_rounds=int(state["max_rounds"]),
        actions=actions,
        opportunities=opportunities,
        weakness_hits=weakness_hits,
        damage_actions=damage_actions,
        total_damage=total_damage,
        weak_neutral_damage=weak_neutral_damage,
        weak_bonus_damage=weak_bonus_damage,
        remaining_hp=remaining_hp,
        maximum_hp=maximum_hp,
    )


def _percentile(values: Sequence[int | float], percentile: float) -> float | None:
    if not values:
        return None
    ordered = sorted(float(value) for value in values)
    position = (len(ordered) - 1) * percentile
    lower = int(position)
    upper = min(len(ordered) - 1, lower + 1)
    fraction = position - lower
    return round(ordered[lower] * (1 - fraction) + ordered[upper] * fraction, 2)


def _summarize_results(results: Sequence[SimulationResult]) -> dict[str, Any]:
    victories = [result for result in results if result.victory]
    actions: Counter[str] = Counter()
    opportunities: Counter[str] = Counter()
    for result in results:
        actions.update(result.actions)
        opportunities.update(result.opportunities)
    slot_codes = sorted(
        set(actions) | set(opportunities),
        key=lambda code: SLOT_ORDER.get(code, 99),
    )
    weak_neutral_damage = sum(result.weak_neutral_damage for result in results)
    weak_bonus_damage = sum(result.weak_bonus_damage for result in results)
    total_damage = sum(result.total_damage for result in results)
    slot_use = {
        slot: {
            "uses": actions[slot],
            "available_opportunities": opportunities[slot],
            "use_rate_when_available_pct": round(
                100 * actions[slot] / opportunities[slot], 2
            )
            if opportunities[slot]
            else 0.0,
        }
        for slot in slot_codes
    }
    return {
        "cases": len(results),
        "victories": len(victories),
        "win_rate_pct": round(100 * len(victories) / len(results), 2),
        "clear_rounds": {
            "p10": _percentile([result.rounds for result in victories], 0.10),
            "p50": _percentile([result.rounds for result in victories], 0.50),
            "p90": _percentile([result.rounds for result in victories], 0.90),
        },
        "one_round_clears": sum(
            result.victory and result.rounds == 1 for result in results
        ),
        "weakness_hit_rate_pct": round(
            100
            * sum(result.weakness_hits for result in results)
            / max(1, sum(result.damage_actions for result in results)),
            2,
        ),
        "weak_action_uplift_pct": round(
            100 * weak_bonus_damage / max(1, weak_neutral_damage),
            2,
        ),
        "weak_bonus_share_of_damage_pct": round(
            100 * weak_bonus_damage / max(1, total_damage),
            2,
        ),
        "remaining_hp_pct": round(
            100
            * sum(result.remaining_hp for result in results)
            / max(1, sum(result.maximum_hp for result in results)),
            2,
        ),
        "slot_use": slot_use,
    }


def _paired_matchup_report(
    by_policy: Mapping[PolicyCode, Sequence[SimulationResult]],
) -> dict[str, Any]:
    maximum = {result.case.key: result for result in by_policy["max_damage"]}
    weakness = {result.case.key: result for result in by_policy["weakness_first"]}
    paired = [
        maximum[key].score_rounds - weakness[key].score_rounds
        for key in sorted(maximum)
    ]
    by_region: dict[str, list[int]] = defaultdict(list)
    for key, maximum_result in maximum.items():
        by_region[maximum_result.case.region_code].append(
            maximum_result.score_rounds - weakness[key].score_rounds
        )
    return {
        "definition": "max_damage score rounds - weakness_first score rounds",
        "positive_case_rate_pct": round(
            100 * sum(value > 0 for value in paired) / len(paired), 2
        ),
        "negative_case_rate_pct": round(
            100 * sum(value < 0 for value in paired) / len(paired), 2
        ),
        "round_delta": {
            "p10": _percentile(paired, 0.10),
            "p50": _percentile(paired, 0.50),
            "p90": _percentile(paired, 0.90),
            "mean": round(sum(paired) / len(paired), 3),
        },
        "region_p50": {
            region: _percentile(values, 0.50)
            for region, values in sorted(by_region.items())
        },
    }


def _species_gap(results: Sequence[SimulationResult]) -> dict[str, Any]:
    counts: dict[str, list[bool]] = defaultdict(list)
    for result in results:
        counts[result.case.species].append(result.victory)
    rates = {
        species: round(100 * sum(values) / len(values), 2)
        for species, values in sorted(counts.items())
    }
    score_rounds: dict[str, list[int]] = defaultdict(list)
    for result in results:
        score_rounds[result.case.species].append(result.score_rounds)
    mean_scores = {
        species: round(sum(values) / len(values), 3)
        for species, values in sorted(score_rounds.items())
    }
    return {
        "win_rate_pct": rates,
        "max_gap_pp": round(max(rates.values()) - min(rates.values()), 2),
        "mean_score_rounds": mean_scores,
        "max_mean_score_round_gap": round(
            max(mean_scores.values()) - min(mean_scores.values()), 3
        ),
    }


def _between(value: float | int | None, low: float, high: float) -> bool:
    return value is not None and low <= float(value) <= high


def _balance_gates(report: Mapping[str, Any]) -> dict[str, Any]:
    """스테이지 역할별 출시 게이트를 계산한다.

    튜토리얼 단일 웨이브와 일반+큰 엉킴 2웨이브를 같은 라운드 밴드로 묶지
    않는다. 사용자가 상성을 읽는 기준 정책과 생존 판단 정책을 목적에 맞게 쓴다.
    """

    weakness_stages = report["stage_summary"]["weakness_first"]
    survival_stages = report["stage_summary"]["survival"]
    tutorial = weakness_stages["tutorial"]
    standard = weakness_stages["standard"]
    elite = weakness_stages["elite"]
    mixed = survival_stages["mixed"]
    matchup = report["policy_summary"]["weakness_first"]
    neutral_policy = report["policy_summary"]["max_damage"]
    survival_policy = report["policy_summary"]["survival"]
    matchup_pair = report["matchup_contribution"]
    species = report["species_gap"]["weakness_first"]
    reference_slots = {
        slot: details["use_rate_when_available_pct"]
        for slot, details in matchup["slot_use"].items()
        if slot != "guard"
    }
    reference_slots["guard"] = survival_policy["slot_use"]["guard"][
        "use_rate_when_available_pct"
    ]
    matchup_selection_lift = round(
        matchup["weakness_hit_rate_pct"]
        - neutral_policy["weakness_hit_rate_pct"],
        2,
    )

    checks = {
        "tutorial_completion": {
            "pass": tutorial["win_rate_pct"] == 100.0
            and _between(tutorial["clear_rounds"]["p90"], 1, 2),
            "actual": {
                "win_rate_pct": tutorial["win_rate_pct"],
                "p90": tutorial["clear_rounds"]["p90"],
            },
            "target": "승률 100%, P90 1~2라운드",
        },
        "standard_pacing": {
            "pass": _between(standard["win_rate_pct"], 95, 100)
            and _between(standard["clear_rounds"]["p50"], 2, 4)
            and standard["one_round_clears"] == 0,
            "actual": {
                "win_rate_pct": standard["win_rate_pct"],
                "p50": standard["clear_rounds"]["p50"],
                "one_round_clears": standard["one_round_clears"],
            },
            "target": "승률 95~100%, P50 2~4라운드, 1라운드 완료 0건",
        },
        "elite_pacing": {
            "pass": _between(elite["win_rate_pct"], 90, 100)
            and _between(elite["clear_rounds"]["p50"], 2, 4)
            and elite["one_round_clears"] == 0,
            "actual": {
                "win_rate_pct": elite["win_rate_pct"],
                "p50": elite["clear_rounds"]["p50"],
                "one_round_clears": elite["one_round_clears"],
            },
            "target": "승률 90~100%, P50 2~4라운드, 1라운드 완료 0건",
        },
        "mixed_mastery": {
            "pass": _between(mixed["win_rate_pct"], 70, 85)
            and _between(mixed["clear_rounds"]["p50"], 3, 6)
            and mixed["one_round_clears"] == 0,
            "actual": {
                "win_rate_pct": mixed["win_rate_pct"],
                "p50": mixed["clear_rounds"]["p50"],
                "one_round_clears": mixed["one_round_clears"],
            },
            "target": "생존 정책 승률 70~85%, P50 3~6라운드",
        },
        "matchup_damage": {
            "pass": _between(matchup["weak_action_uplift_pct"], 40, 50),
            "actual": {
                "weak_action_uplift_pct": matchup["weak_action_uplift_pct"],
                "weakness_hit_rate_pct": matchup["weakness_hit_rate_pct"],
            },
            "target": "일반 약점 1.50배·프리즘 약점 1.30배 혼합 실피해 상승 40~50%",
        },
        "matchup_selection": {
            "pass": matchup_selection_lift >= 10
            and matchup_pair["positive_case_rate_pct"]
            >= matchup_pair["negative_case_rate_pct"],
            "actual": {
                "weakness_hit_lift_pp": matchup_selection_lift,
                "faster_case_rate_pct": matchup_pair["positive_case_rate_pct"],
                "slower_case_rate_pct": matchup_pair["negative_case_rate_pct"],
            },
            "target": "약점 우선 시 적중률 +10%p 이상, 빨라지는 셀이 느려지는 셀 이상",
        },
        "slot_coverage": {
            "pass": all(rate >= 5 for rate in reference_slots.values()),
            "actual": reference_slots,
            "target": "사용 가능한 기본·고유·선택·방어 슬롯 선택률 각각 5% 이상",
        },
        "species_coverage_gap": {
            "pass": species["max_gap_pp"] <= 5.0,
            "actual": {
                "max_gap_pp": species["max_gap_pp"],
                "max_mean_score_round_gap": species[
                    "max_mean_score_round_gap"
                ],
            },
            "target": "동일 전수 셀 품종 승률 격차 5%p 이하",
        },
    }
    return {
        "all_passed": all(check["pass"] for check in checks.values()),
        "checks": checks,
    }


def run_balance_matrix() -> dict[str, Any]:
    cases = list(simulation_cases())
    by_policy: dict[PolicyCode, list[SimulationResult]] = {
        policy: [] for policy in POLICIES
    }
    for policy in POLICIES:
        by_policy[policy] = [simulate_case(case, policy) for case in cases]

    stage_summary: dict[str, dict[str, Any]] = {}
    for policy, results in by_policy.items():
        stage_summary[policy] = {}
        for stage_shape in ("tutorial", "standard", "elite", "mixed"):
            stage_summary[policy][stage_shape] = _summarize_results(
                [result for result in results if result.case.stage_shape == stage_shape]
            )

    report = {
        "schema_version": 1,
        "combat_balance_version": COMBAT_BALANCE_VERSION,
        "generated_at": datetime.now(UTC).isoformat(),
        "engine": "deterministic-exact-enumeration",
        "party_fixture": "owned identity 1 + Lv16 archive guide 2",
        "dimensions": {
            "species": len(set(case.species for case in cases)),
            "forms": len(set(case.form for case in cases)),
            "rarities": len(set(case.rarity for case in cases)),
            "recommended_levels_per_region": 2,
            "regions": len(REGION_COMBAT_BANDS),
            "stage_shapes": 4,
            "cases_per_policy": len(cases),
            "total_battles": len(cases) * len(POLICIES),
        },
        "policy_summary": {
            policy: _summarize_results(results)
            for policy, results in by_policy.items()
        },
        "stage_summary": stage_summary,
        "matchup_contribution": _paired_matchup_report(by_policy),
        "species_gap": {
            policy: _species_gap(results) for policy, results in by_policy.items()
        },
    }
    report["balance_gates"] = _balance_gates(report)
    return report
