"""합동 수호전 밸런스 시뮬레이터 — 설계서 5.2의 합격선을 수치로 확인한다.

`combat_simulator`와 같은 방식이다. 이 전투에는 난수가 없으므로(설계서가 확률
0을 못 박는다) `시드 10,000회`라는 표현은 이 저장소에 그대로 옮겨지지 않는다.
대신 **편성 공간을 빠짐없이 훑는다** — 승률은 확률이 아니라 `끝까지 간 편성의
비율`이고, 같은 편성은 언제 돌려도 같은 결과가 나온다.

행동 정책도 `combat_simulator`의 것을 그대로 가져다 쓴다. 사본을 만들면 두
밸런스 리포트를 나란히 놓고 비교할 수 없다.

역할 축(지킴·돌봄·이음·달램·밝힘·매듭)은 판정 코드가 읽지 않는 분류 라벨이라
(성장 설계서 6.6 원칙 1) 시뮬레이터가 읽을 값이 없다. 대신 결정적 순간이
실제로 요구하는 **효과**를 축으로 쓴다 — 전원 방어·회복·달램·집중 환급·약점
공개·결정타. 설계서 5.2가 묻는 것도 `역할이 없다는 이유로 밴드를 벗어나는
조합이 있는가`이고, 그 `없음`은 코드에서 효과 없음으로 나타난다.
"""

from collections.abc import Iterable, Mapping, Sequence
from dataclasses import dataclass
from typing import Any

from app.content.expeditions.combat import CombatRuleError, member_battle_kit
from app.content.expeditions.combat_identity import (
    EMOTION_DISCIPLINES,
    SPECIES_SKILLS,
)
from app.content.expeditions.combat_simulator import (
    POLICIES,
    PolicyCode,
    _choose_action,
    _living_payload_members,
    _survival_actor,
)
from app.content.expeditions.joint_guard import (
    BEAST_CATALOG,
    DIFFICULTIES,
    JOINT_GUARD_VERSION,
    LAYER_BARRIERS,
)
from app.content.expeditions.joint_guard_run import (
    FRONT_SIZE,
    PARTY_SIZE,
    joint_guard_payload,
    new_joint_guard,
    submit_joint_guard_command,
    swap_joint_guard_member,
)


#: 밴드를 재는 기준 손.
#:
#: 앱의 AUTO(`_autoActionFor`)는 **위험하면 방어하고, 아니면 약점에 맞는 가장
#: 센 스킬을, 없으면 기본 공격**을 고른다. 시뮬레이터의 `weakness_first`가 같은
#: 손이라 이것을 기준으로 삼는다. 실제로 앱에 들어 있는 유일한 자동 손이고,
#: 사람은 최소한 이만큼은 하므로 승률의 **하한**으로 읽을 수 있다.
REFERENCE_POLICY: PolicyCode = "weakness_first"

#: 상성을 안 읽고 눈앞의 숫자만 보는 손. 상성 체계가 실제로 값을 하는지
#: 확인하는 대조군이다.
NAIVE_POLICY: PolicyCode = "max_damage"

#: 연출이 차지하는 시간. 앱의 `ExpeditionCombatTimeline`과 콘텐츠 모션 총합에서
#: 그대로 가져왔다. 사람이 무엇을 고를지 **생각하는 시간**은 여기 없다.
PARTY_CUE_MS = 700 + 110
ENEMY_CUE_MS = 820 + 210

#: 결정적 순간 셋이 실제로 요구하는 대응 효과(설계서 4.4의 `optimal`).
#: 역할 이름이 아니라 슬롯에 붙은 effect code로 적는다 - 판정 코드가 읽는 것이
#: 그쪽이기 때문이다.
#:
#: `study_refund`는 거의 모든 명단이 기록서로 들고 있어서 축을 나누지 못한다.
#: 그래서 **품종이 가져오는 고유 효과만** 센다.
MOMENT_ANSWER_EFFECTS = frozenset(
    {
        # 전원 방어 · 받아 내고 돌려주기 (크게 뒤척이기)
        "shield_all",
        "den_guardian_roar",
        "patina_parry",
        # 달램 · 회복 (꼭 끌어안기)
        "weaken_intent",
        "heal_lowest",
        "triage_heal",
        "white_garden_oath",
        # 집중 환급 · 약점 밝힘 (깊은 잠꼬대)
        "resonance_boost",
        "prism_shift",
        "steady_read",
        # 열린 기회의 결정타
        "last_stand",
        "weakness_pierce",
        "golden_seam",
    }
)

SPECIES_CODES: tuple[str, ...] = tuple(
    sorted(set(SPECIES_SKILLS) - {"archive_guide"})
)
FORMS: tuple[str, ...] = tuple(EMOTION_DISCIPLINES)


@dataclass(frozen=True)
class JointGuardCase:
    beast_code: str
    difficulty: str
    species: str
    form: str
    level: int
    rarity: int
    #: 실제 보유 캐릭터 수. 나머지는 길잡이가 채운다.
    real_members: int

    @property
    def key(self) -> str:
        return ":".join(
            (
                self.beast_code,
                self.difficulty,
                self.species,
                self.form,
                str(self.level),
                str(self.rarity),
                str(self.real_members),
            )
        )


@dataclass
class JointGuardResult:
    case: JointGuardCase
    policy: PolicyCode
    awake: bool
    layers_opened: int
    layer_count: int
    rounds: int
    commands: int
    swaps: int
    #: 이 편성이 들고 간 결정적 순간 대응 효과들.
    effects: frozenset[str]

    @property
    def animation_seconds(self) -> float:
        """연출만 재생하는 데 걸리는 시간. 생각하는 시간은 빠져 있다."""
        return (
            self.commands * PARTY_CUE_MS + self.rounds * ENEMY_CUE_MS
        ) / 1000.0


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
        {"care": 6, "focus": 6, "courage": 6, "insight": 6}
        if guide
        else {"care": 6, "focus": 6, "courage": 6, "insight": 6}
    )
    return {
        "id": member_id,
        "position": member_id - 1,
        "is_guide": guide,
        "snapshot": {
            "name": f"시뮬 대원 {member_id}",
            "species": {"code": "archive_guide" if guide else species},
            "form": "mosaic" if guide else form,
            "level": 10 if guide else level,
            "rarity": 1 if guide else rarity,
            "stage": 3 if guide else 5,
            "stats": stats,
        },
    }


def roster_for(case: JointGuardCase) -> list[dict[str, Any]]:
    """실제 캐릭터 N명 + 길잡이로 여섯 자리를 채운다.

    실제 캐릭터를 **앞에서부터** 세운다. 전열이 곧 명령을 받는 자리라, 뒤에
    몰아 두면 편성 크기가 아니라 배치를 재는 것이 된다.
    """
    roster: list[dict[str, Any]] = []
    for index in range(PARTY_SIZE):
        guide = index >= case.real_members
        roster.append(
            {
                "profile": _profile(
                    index + 1,
                    species=case.species,
                    form=case.form,
                    level=case.level,
                    rarity=case.rarity,
                    guide=guide,
                ),
                "formation": "front" if index < FRONT_SIZE else "back",
            }
        )
    return roster


def _party_effects(roster: Sequence[Mapping[str, Any]]) -> frozenset[str]:
    """이 명단이 들고 간 결정적 순간 대응 효과.

    역할 라벨 대신 쓰는 축이다. 슬롯에 붙은 effect code를 읽는다.

    전투 상태의 `party`가 아니라 **프로필에서 직접** 키트를 만든다. 전투 상태에
    담기는 것은 HP와 쿨타임뿐이고 키트는 payload를 만들 때 붙는다 — 상태 쪽을
    읽었더니 어느 명단도 효과가 없는 것으로 나왔다.
    """
    found: set[str] = set()
    for entry in roster:
        kit = member_battle_kit(entry["profile"])
        for action in [*kit["unique_skills"], *kit["selected_skills"]]:
            effect = str(action.get("effect", ""))
            if effect in MOMENT_ANSWER_EFFECTS:
                found.add(effect)
    return frozenset(found)


def _forced_swap(state: dict[str, Any]) -> bool:
    """물러난 자리를 메운다. 라운드당 한 번뿐이라 필요할 때만 쓴다."""
    if int(state.get("swaps_used_this_round", 0)) > 0:
        return False
    front = [e for e in state["roster"] if e["formation"] == "front"]
    reserves = [
        e
        for e in state["roster"]
        if e["formation"] == "back" and int(e["hp"] or 0) > 0
    ]
    downed = [e for e in front if int(e["hp"] or 0) <= 0]
    if not downed or not reserves:
        return False
    healthiest = max(reserves, key=lambda e: int(e["hp"] or 0))
    try:
        swap_joint_guard_member(
            state,
            out_member_id=int(downed[0]["member_id"]),
            in_member_id=int(healthiest["member_id"]),
        )
    except CombatRuleError:
        return False
    return True


def simulate(case: JointGuardCase, policy: PolicyCode) -> JointGuardResult:
    roster = roster_for(case)
    effects = _party_effects(roster)
    state = new_joint_guard(case.beast_code, case.difficulty, roster)
    commands = 0
    swaps = 0
    rounds = 0
    seen_layer_rounds: set[tuple[int, int]] = set()
    guard = 0

    while state["status"] == "active":
        guard += 1
        if guard > 400:
            raise RuntimeError(f"{case.key}: 명령 안전 한도를 넘었습니다")

        battle = state["battle"]
        if battle.get("status") != "active":
            # 전열이 모두 물러났다. 뒤에 설 사람이 있으면 메우고 이어 간다.
            if _forced_swap(state):
                swaps += 1
                continue
            break

        seen_layer_rounds.add(
            (int(state["layer_index"]), int(battle.get("round", 1)))
        )
        payload = joint_guard_payload(state)["battle"]
        available = _living_payload_members(payload)
        if not available:
            if _forced_swap(state):
                swaps += 1
                continue
            break
        actor = (
            _survival_actor(payload, available)
            if policy == "survival"
            else available[0]
        )
        action, _ = _choose_action(payload, actor, policy=policy)
        try:
            state = submit_joint_guard_command(
                state, {"member_id": int(actor["member_id"]), "action": action}
            )
        except CombatRuleError:
            break
        commands += 1

    rounds = len(seen_layer_rounds)
    return JointGuardResult(
        case=case,
        policy=policy,
        awake=state["status"] == "awake",
        layers_opened=int(state["layer_index"]) + (1 if state["status"] == "awake" else 0),
        layer_count=len(state["layers"]),
        rounds=rounds,
        commands=commands,
        swaps=swaps,
        effects=effects,
    )


def cases(
    *,
    species: Sequence[str] | None = None,
    real_members: Sequence[int] = (1, 6),
    rarities: Sequence[int] = (1, 5),
    levels: Sequence[int] = (23,),
) -> Iterable[JointGuardCase]:
    """편성 공간. 밴드를 재는 축만 남기고 나머지는 고정한다.

    짐승 넷은 수치가 같지만 **겹별 상성표가 다르다.** 그래서 결과가 결에 따라
    갈리는지 보려면 넷을 다 돌아야 한다.
    """
    for beast_code in sorted(BEAST_CATALOG):
        for difficulty in sorted(DIFFICULTIES):
            for code in species or SPECIES_CODES:
                for form in FORMS:
                    for rarity in rarities:
                        for level in levels:
                            for count in real_members:
                                yield JointGuardCase(
                                    beast_code=beast_code,
                                    difficulty=difficulty,
                                    species=code,
                                    form=form,
                                    level=level,
                                    rarity=rarity,
                                    real_members=count,
                                )


def _rate(hits: int, total: int) -> float | None:
    return None if total == 0 else round(100.0 * hits / total, 2)


def _slice(results: Sequence[JointGuardResult], **match: Any) -> list[JointGuardResult]:
    out = []
    for result in results:
        if all(getattr(result.case, key) == value for key, value in match.items()):
            out.append(result)
    return out


def _summarize(results: Sequence[JointGuardResult]) -> dict[str, Any]:
    if not results:
        return {"runs": 0}
    awake = sum(1 for r in results if r.awake)
    rounds = [r.rounds for r in results]
    seconds = [r.animation_seconds for r in results]
    return {
        "runs": len(results),
        "clear_rate": _rate(awake, len(results)),
        "average_rounds": round(sum(rounds) / len(rounds), 2),
        "max_rounds": max(rounds),
        "average_swaps": round(sum(r.swaps for r in results) / len(results), 2),
        "average_animation_seconds": round(sum(seconds) / len(seconds), 1),
    }


def run_joint_guard_matrix(**kwargs: Any) -> dict[str, Any]:
    """전 편성을 두 정책으로 돌리고 설계서 5.2의 합격선을 함께 매긴다."""
    all_cases = list(cases(**kwargs))
    results: list[JointGuardResult] = []
    for case in all_cases:
        for policy in (REFERENCE_POLICY, NAIVE_POLICY):
            results.append(simulate(case, policy))

    manual = [r for r in results if r.policy == REFERENCE_POLICY]
    report: dict[str, Any] = {
        "runs": len(results),
        "cases": len(all_cases),
        "policies": {
            "reference": REFERENCE_POLICY,
            "naive": NAIVE_POLICY,
        },
        "difficulty": {
            difficulty: _summarize(_slice(manual, difficulty=difficulty))
            for difficulty in sorted(DIFFICULTIES)
        },
        "beast": {
            beast: _summarize(_slice(manual, beast_code=beast))
            for beast in sorted(BEAST_CATALOG)
        },
        "form": {
            form: _summarize([r for r in manual if r.case.form == form])
            for form in FORMS
        },
        # 난이도별로 갈라서도 본다. 합쳐 놓으면 한쪽 난이도에서만 쏠린 결이
        # 다른 쪽에 묻힌다 - 상성표의 행 쏠림이 정확히 그렇게 숨어 있었다.
        "form_by_difficulty": {
            difficulty: {
                form: _summarize(
                    [
                        r
                        for r in manual
                        if r.case.difficulty == difficulty and r.case.form == form
                    ]
                )
                for form in FORMS
            }
            for difficulty in sorted(DIFFICULTIES)
        },
        "solo": _summarize(
            _slice(manual, difficulty="three_layers", real_members=1)
        ),
        "auto_vs_manual": {},
        "effects": {},
    }

    for difficulty in sorted(DIFFICULTIES):
        manual_slice = _slice(manual, difficulty=difficulty)
        auto_slice = _slice(
            [r for r in results if r.policy == NAIVE_POLICY], difficulty=difficulty
        )
        manual_rate = _summarize(manual_slice).get("clear_rate")
        auto_rate = _summarize(auto_slice).get("clear_rate")
        report["auto_vs_manual"][difficulty] = {
            "reference_clear_rate": manual_rate,
            "naive_clear_rate": auto_rate,
            "gap_points": (
                None
                if manual_rate is None or auto_rate is None
                else round(auto_rate - manual_rate, 2)
            ),
        }

    # 결정적 순간 대응 효과를 하나도 안 들고 간 편성과 들고 간 편성을 나눈다.
    bare = [r for r in manual if not r.effects]
    armed = [r for r in manual if r.effects]
    report["effects"] = {
        "with_answers": _summarize(armed),
        "without_answers": _summarize(bare),
        "observed": sorted({effect for r in manual for effect in r.effects}),
    }

    report["gates"] = _gates(report)
    return report


def _between(value: float | None, low: float, high: float) -> bool:
    return value is not None and low <= value <= high


def _gates(report: Mapping[str, Any]) -> dict[str, Any]:
    """설계서 5.1·5.2의 합격선.

    측정할 수 없는 항목은 통과로 적지 않고 `unmeasurable`로 남긴다.
    """
    outer = report["difficulty"].get("outer_walk", {})
    three = report["difficulty"].get("three_layers", {})
    solo = report.get("solo", {})
    bare = report["effects"]["without_answers"]
    armed = report["effects"]["with_answers"]

    form_rates = [
        summary.get("clear_rate")
        for summary in report["form"].values()
        if summary.get("clear_rate") is not None
    ]
    form_spread = (
        None if not form_rates else round(max(form_rates) - min(form_rates), 2)
    )

    round_gap = (
        None
        if not bare.get("runs") or not armed.get("runs")
        else round(bare["average_rounds"] - armed["average_rounds"], 2)
    )

    auto_gaps = [
        entry["gap_points"]
        for entry in report["auto_vs_manual"].values()
        if entry["gap_points"] is not None
    ]

    return {
        "outer_walk_band_85_95": _between(outer.get("clear_rate"), 85.0, 95.0),
        "three_layers_band_50_70": _between(three.get("clear_rate"), 50.0, 70.0),
        "solo_three_layers_at_least_45": (
            solo.get("clear_rate") is not None and solo["clear_rate"] >= 45.0
        ),
        # 효과를 못 들고 간 편성이 라운드를 더 쓰는 것은 정상이다. 다만
        # 그 차이가 2.5라운드를 넘으면 `없으면 조금 오래 걸릴 뿐`이 거짓이 된다.
        "no_answer_round_penalty_within_2_5": (
            round_gap is not None and round_gap <= 2.5
        ),
        # 어떤 결도 유리하거나 불리하지 않아야 한다. 여섯 결의 클리어율 폭.
        "form_spread_within_10_points": (
            form_spread is not None and form_spread <= 10.0
        ),
        # 상성을 읽는 손이 안 읽는 손보다 나아야 한다. 같거나 뒤지면 겹별
        # 상성표가 장식이 된다.
        "matchup_reading_pays_off": all(gap <= 0.0 for gap in auto_gaps),
        # 설계서 5.2의 `수동 대 AUTO`는 **사람**과 자동을 견준다. 시뮬레이터에는
        # 사람 손이 없다 - 남은 두 정책은 숙련도가 아니라 조율 대상이 달라서,
        # 그 차이를 사람 대 자동으로 읽으면 없는 결론을 만들어 낸다.
        "manual_vs_auto": "unmeasurable",
        # 실기기 벽시계 시간은 사람이 고르는 시간을 포함한다. 시뮬레이터는
        # 연출 시간만 잴 수 있어 합격 여부를 여기서 적지 않는다.
        "run_length_seconds": "unmeasurable",
        # 역할 축은 판정 코드에 없다(성장 설계서 6.6 원칙 1). 효과 축으로
        # 대신 재고, 역할 이름으로는 적지 않는다.
        "role_axis": "unmeasurable",
    }


def gate_failures(report: Mapping[str, Any]) -> list[str]:
    """불합격 항목만 추린다. 측정 불가는 불합격이 아니다."""
    failures = []
    for name, passed in report["gates"].items():
        if passed is False:
            failures.append(name)
    return failures


def format_report(report: Mapping[str, Any]) -> str:
    lines = [
        f"runs={report['runs']} cases={report['cases']}",
        "",
        "난이도별 (기준 정책 = 앱 AUTO와 같은 손)",
    ]
    for difficulty, summary in report["difficulty"].items():
        lines.append(
            f"  {difficulty:14s} clear={summary.get('clear_rate')}% "
            f"rounds={summary.get('average_rounds')} "
            f"swaps={summary.get('average_swaps')} "
            f"anim={summary.get('average_animation_seconds')}s "
            f"({summary.get('runs')} runs)"
        )
    lines += ["", "짐승별"]
    for beast, summary in report["beast"].items():
        lines.append(
            f"  {beast:16s} clear={summary.get('clear_rate')}% "
            f"rounds={summary.get('average_rounds')}"
        )
    lines += ["", "성장결별 (난이도별)"]
    for difficulty, forms in report["form_by_difficulty"].items():
        rates = [s.get("clear_rate") for s in forms.values() if s.get("clear_rate")]
        spread = round(max(rates) - min(rates), 2) if rates else None
        lines.append(f"  {difficulty} (폭 {spread}p)")
        for form, summary in forms.items():
            lines.append(f"    {form:11s} clear={summary.get('clear_rate')}%")
    solo = report["solo"]
    lines += [
        "",
        f"캐릭터 1 + 길잡이 5 · 세 겹의 꿈: clear={solo.get('clear_rate')}% "
        f"rounds={solo.get('average_rounds')}",
        "",
        "상성을 읽는 손 대 안 읽는 손",
    ]
    for difficulty, entry in report["auto_vs_manual"].items():
        lines.append(
            f"  {difficulty:14s} 상성읽음={entry['reference_clear_rate']}% "
            f"안읽음={entry['naive_clear_rate']}% gap={entry['gap_points']}p"
        )
    effects = report["effects"]
    lines += [
        "",
        "결정적 순간 대응 효과",
        f"  들고 감  clear={effects['with_answers'].get('clear_rate')}% "
        f"rounds={effects['with_answers'].get('average_rounds')}",
        f"  없이 감  clear={effects['without_answers'].get('clear_rate')}% "
        f"rounds={effects['without_answers'].get('average_rounds')}",
        f"  관측된 효과: {', '.join(effects['observed']) or '없음'}",
        "",
        "합격선",
    ]
    for name, passed in report["gates"].items():
        mark = "PASS" if passed is True else ("FAIL" if passed is False else str(passed))
        lines.append(f"  {name:38s} {mark}")
    return "\n".join(lines)


def build_report() -> dict[str, Any]:
    """저장소에 체크인하는 리포트. 숫자와 함께 **어떻게 쟀는지**를 담는다."""
    report = run_joint_guard_matrix()
    return {
        "schema_version": 1,
        "joint_guard_version": JOINT_GUARD_VERSION,
        "engine": "deterministic-exact-enumeration",
        "reference_policy": REFERENCE_POLICY,
        "naive_policy": NAIVE_POLICY,
        "layer_barriers": list(LAYER_BARRIERS),
        "difficulty_barrier_scale_bp": {
            code: int(spec.get("barrier_scale_bp", 10_000))
            for code, spec in DIFFICULTIES.items()
        },
        "dimensions": {
            "cases_per_policy": report["cases"],
            "total_battles": report["runs"],
            "species": len(SPECIES_CODES),
            "forms": len(FORMS),
            "beasts": len(BEAST_CATALOG),
        },
        **{
            key: report[key]
            for key in (
                "difficulty",
                "beast",
                "form",
                "form_by_difficulty",
                "solo",
                "auto_vs_manual",
                "effects",
                "gates",
            )
        },
    }


def main() -> int:
    import json
    import pathlib

    report = build_report()
    out = (
        pathlib.Path(__file__).resolve().parents[4]
        / "docs"
        / "joint_guard_balance_report.json"
    )
    out.write_text(
        json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(format_report(run_joint_guard_matrix()))
    failures = gate_failures(report)
    print("불합격:", ", ".join(failures) if failures else "없음")
    return 1 if failures else 0


__all__ = [
    "JointGuardCase",
    "build_report",
    "JointGuardResult",
    "POLICIES",
    "cases",
    "format_report",
    "gate_failures",
    "roster_for",
    "run_joint_guard_matrix",
    "simulate",
]
