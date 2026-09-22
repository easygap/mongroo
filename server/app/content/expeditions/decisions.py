"""Authored field decisions; old saved expeditions keep their original rules."""

from typing import Any


def failure_cost(choice: dict[str, Any], pending: dict[str, Any]) -> int:
    if choice.get("safe") or pending.get("resolve_guard"):
        return 0
    return max(
        0,
        int(choice.get("resolve_cost", 1)) + int(pending.get("resolve_cost_delta", 0)),
    )


def success_chance(value: int, difficulty: int, *, guaranteed: bool = False) -> int:
    """The server rolls 1..4 once per action identity, never once per retry."""
    if guaranteed:
        return 100
    return sum(value + roll >= difficulty for roll in range(1, 5)) * 25


def decision_result(
    choice: dict[str, Any], outcome: str, *, resolve: int, trail_light: int
) -> dict[str, Any]:
    effect = (
        choice.get("success_effect", {}) if outcome in ("clear", "flourish") else {}
    )
    next_resolve = min(6, resolve + int(effect.get("resolve", 0)))
    next_light = min(12, trail_light + int(effect.get("trail_light", 0)))
    return {
        "result_text": choice.get("outcome_text", {}).get(outcome, ""),
        "finding": effect.get("finding"),
        "resolve": next_resolve,
        "trail_light": next_light,
        "resource_changes": {
            "resolve": next_resolve - resolve,
            "trail_light": next_light - trail_light,
        },
        "collects_loot": outcome != "detour" and choice.get("collects_loot", True),
    }
