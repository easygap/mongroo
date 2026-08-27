"""스테이지 지도와 모험 허브가 읽는 진행 상태.

개편 설계서(stage-battle-v2.0) 3.1·5.1·5.2의 계약을 서버 쪽에서 담당한다.
지역 하나는 8개 스테이지로 나뉘고, 스테이지 하나가 곧 독립 세션이다. 보상은
기존 일일 원장이 그대로 담당하므로 이 모듈은 진행 표시와 해금 판단만 계산한다.
"""

from typing import Any

import sqlalchemy as sa
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.errors import AppError
from app.content.expeditions.tangles import tangle_definition
from app.content.expeditions.validator import STAGE_COUNT
from app.core.korean import korean_object
from app.core.timeutil import to_utc_iso, utcnow
from app.models.expedition import ExpeditionRun, UserStageProgress
from app.services.expeditions import load_content, region_cleared, region_order


_STAT_LABELS = {"care": "돌봄", "focus": "집중", "courage": "용기", "insight": "관찰"}
_KIND_LABELS = {
    "battle": "전투",
    "event": "사건",
    "camp": "쉼터",
    "boss": "수호전",
}


def _region_of(content: dict[str, Any]) -> dict[str, Any]:
    return content["region"]


def stage_label(content: dict[str, Any], stage_no: int) -> str:
    """`기억서고 3`처럼 어디의 몇 번째인지 한 번에 읽히는 표기."""

    region = _region_of(content)
    return f"{region.get('short_name') or region['name']} {stage_no}"


async def _progress_rows(
    db: AsyncSession, user_id: int, region_code: str
) -> dict[int, UserStageProgress]:
    rows = (
        await db.execute(
            sa.select(UserStageProgress).where(
                UserStageProgress.user_id == user_id,
                UserStageProgress.region_code == region_code,
            )
        )
    ).scalars()
    return {row.stage_no: row for row in rows}


async def unlocked_region_codes(db: AsyncSession, user_id: int) -> list[str]:
    """지금 걸을 수 있는 지역 — 앞 지역을 완주할 때마다 하나씩 늘어난다.

    카탈로그가 쓰는 해금 규칙과 같은 규칙이다. 두 곳이 각자 세면 지도에서는
    열려 있는데 출발은 막히는 날이 온다.
    """

    order = region_order()
    unlocked = order[:1]
    for previous, code in zip(order, order[1:]):
        if not await region_cleared(db, user_id, previous):
            break
        unlocked.append(code)
    return unlocked


async def resolve_region_code(
    db: AsyncSession, user_id: int, region_code: str | None
) -> str:
    """지도가 보여 줄 지역을 정한다.

    지역을 고르지 않으면 **아직 완주하지 않은 첫 해금 지역**을 준다. 그래야
    첫 지역을 다 걸은 사람이 지도를 열었을 때 `완주 8/8`에 갇히지 않고 다음
    지역 1스테이지에서 이어 걷는다. 전부 완주했으면 마지막 지역에 머문다.
    """

    unlocked = await unlocked_region_codes(db, user_id)
    if region_code is not None:
        if region_code not in unlocked:
            # 없는 지역은 load_content가 404로 막는다. 여기서는 아직 안 열린
            # 지역만 걸러 낸다.
            load_content(region_code)
            raise AppError(
                403, "EXPEDITION_REGION_LOCKED", "앞 지역을 완주하면 열려요."
            )
        return region_code
    for code in unlocked:
        if not await region_cleared(db, user_id, code):
            return code
    return unlocked[-1]


async def _region_summaries(
    db: AsyncSession, user_id: int, unlocked: list[str]
) -> list[dict[str, Any]]:
    """지도 위 지역 전환기가 읽는 목록. 잠긴 지역도 이유와 함께 남긴다."""

    summaries: list[dict[str, Any]] = []
    for code in region_order():
        pack = _region_of(load_content(code))
        cleared_count = len(await _progress_rows(db, user_id, code))
        is_unlocked = code in unlocked
        summaries.append(
            {
                "code": code,
                "name": pack["name"],
                "short_name": pack.get("short_name") or pack["name"],
                "unlocked": is_unlocked,
                # 같은 응답의 스테이지 항목과 이름을 맞춘다. 한 payload 안에서
                # `lock_reason`과 `locked_reason`이 섞이면 읽는 쪽이 흘린다.
                "lock_reason": None if is_unlocked else "앞 지역을 완주하면 열려요.",
                "cleared_count": cleared_count,
                "total": STAGE_COUNT,
            }
        )
    return summaries


async def stage_map_payload(
    db: AsyncSession, user_id: int, region_code: str | None = None
) -> dict[str, Any]:
    unlocked_codes = await unlocked_region_codes(db, user_id)
    code = await resolve_region_code(db, user_id, region_code)
    content = load_content(code)
    region = _region_of(content)
    progress = await _progress_rows(db, user_id, region["code"])
    catalogued_tangles = {
        code
        for stage in content["stages"]
        if int(stage["no"]) in progress
        for code in stage.get("tangles") or []
    }
    active = await db.scalar(
        sa.select(ExpeditionRun).where(
            ExpeditionRun.user_id == user_id, ExpeditionRun.status == "active"
        )
    )

    stages: list[dict[str, Any]] = []
    for stage in content["stages"]:
        stage_no = int(stage["no"])
        record = progress.get(stage_no)
        cleared = record is not None
        # 앞 스테이지를 지나야 다음 점이 열린다. 잠긴 이유는 숨기지 않고 문장으로 준다.
        unlocked = stage_no == 1 or (stage_no - 1) in progress
        weakness = stage.get("weakness")
        stages.append(
            {
                "no": stage_no,
                "kind": stage["kind"],
                "kind_label": _KIND_LABELS[stage["kind"]],
                "elite": bool(stage.get("elite")),
                "label": stage_label(content, stage_no),
                "title": stage["title"],
                "summary": stage["summary"],
                "estimated_seconds": int(stage["estimated_seconds"]),
                "weakness": weakness,
                "weakness_label": _STAT_LABELS.get(weakness) if weakness else None,
                "tangles": [
                    {
                        "code": code,
                        "name": tangle_definition(code)["name"],
                        "description": (
                            tangle_definition(code)["description"]
                            if code in catalogued_tangles
                            else "첫 조우 뒤 도서관에서 생태 기록과 공격 목록이 열려요."
                        ),
                        "elite": bool(tangle_definition(code)["elite"]),
                        "knowledge_level": (
                            "catalogued" if code in catalogued_tangles else "silhouette"
                        ),
                        "skills": (
                            [
                                intent["name"]
                                for intent in tangle_definition(code)["intents"]
                            ]
                            if code in catalogued_tangles
                            else []
                        ),
                    }
                    for code in stage.get("tangles") or []
                ],
                "cleared": cleared,
                "clear_count": record.clear_count if record else 0,
                "cleared_at": to_utc_iso(record.cleared_at) if record else None,
                "story_seen": bool(record.story_seen) if record else False,
                # 전문은 최초 클리어 뒤에만 지도/도서관 UI로 보낸다. 전투 전에는
                # 약점과 예상 시간만 공개해 이야기 스포일러와 텍스트 과밀을 막는다.
                "story": dict(stage["story"]) if cleared else None,
                "unlocked": unlocked,
                "lock_reason": None
                if unlocked
                else (
                    f"{korean_object(stage_label(content, stage_no - 1))}"
                    " 먼저 완주하면 열려요."
                ),
            }
        )

    cleared_count = len(progress)
    next_stage_no = next(
        (item["no"] for item in stages if not item["cleared"] and item["unlocked"]),
        None,
    )
    return {
        "content_version": content["content_version"],
        "region": {
            "code": region["code"],
            "name": region["name"],
            "short_name": region.get("short_name") or region["name"],
            "description": region["description"],
            "recommended_stage": region["recommended_stage"],
        },
        "progress": {
            "cleared_count": cleared_count,
            "total": STAGE_COUNT,
            "next_stage_no": next_stage_no,
            "region_cleared": cleared_count >= STAGE_COUNT,
        },
        "active_run": {
            "run_id": active.id,
            "stage_no": active.stage_no,
        }
        if active
        else None,
        "regions": await _region_summaries(db, user_id, unlocked_codes),
        "stages": stages,
    }


async def mark_story_seen(
    db: AsyncSession, user_id: int, *, region_code: str, stage_no: int
) -> dict[str, Any]:
    """스테이지 전후 이야기 컷을 읽었다고 남긴다.

    아직 완주하지 않은 스테이지에도 컷이 붙을 수 있으므로 진행 행이 없으면
    만들지 않고 조용히 무시한다. 이야기를 못 본 것은 잘못이 아니라 지도에
    책갈피 표시로만 남는다.
    """

    content = load_content()
    if region_code != content["region"]["code"]:
        raise AppError(404, "EXPEDITION_REGION_NOT_FOUND", "탐험 지역을 찾을 수 없습니다.")
    if not 1 <= stage_no <= STAGE_COUNT:
        raise AppError(404, "EXPEDITION_STAGE_NOT_FOUND", "스테이지를 찾을 수 없습니다.")
    record = await db.scalar(
        sa.select(UserStageProgress)
        .where(
            UserStageProgress.user_id == user_id,
            UserStageProgress.region_code == region_code,
            UserStageProgress.stage_no == stage_no,
        )
        .with_for_update()
    )
    if record is not None and not record.story_seen:
        record.story_seen = True
        record.updated_at = utcnow()
    return {"stage_no": stage_no, "story_seen": record.story_seen if record else False}
