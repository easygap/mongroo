"""장거리 개척 콘텐츠 — 방향 셋과 구간별 갈림길.

`docs/interactive_adventure_design.md` 9.8이 확정한 계약을 코드로 옮긴다. 이
모듈은 수치와 문구의 **단일 원본**이고 판정은 하지 않는다.

핵심 계약 넷만 다시 적는다.

1. 한 판을 억지로 늘리지 않는다. 2~3개의 **독립한 구간**을 하나의 원정 기록으로
   묶을 뿐이라, 각 구간은 지금까지의 탐험 run 그대로다.
2. 한 캐릭터는 한 개척에서 **한 구간에만** 선다. 이것이 이 콘텐츠의 존재
   이유다 — 잘 키운 한 명으로 전부 밀 수 없게 해서 여러 캐릭터에게 자리를 준다.
3. 빈자리는 **무료 길잡이**가 채운다. 캐릭터가 하나뿐이어도 끝까지 갈 수 있고,
   길잡이를 많이 썼다고 보상을 깎지 않는다.
4. 보상은 구간마다 합산하지 않는다. **가장 먼 확보 지역의 밴드 한 번**이다.
   그래서 구간 run은 `reward_eligible=False`로 만들고, 지급은 귀환에서 한다.

다음 구간은 미리 보여 주지 않는다(설계서 10.3). 야영지에 닿아야 그 자리에서
갈림길 둘이 열리고, 아직 쓰지 않은 캐릭터 중에서 새 조를 짠다.
"""

from typing import Any

from app.core.korean import korean_subject


JOURNEY_VERSION = "journey-v1"

#: 한 구간에 서는 사람 수. 캐릭터든 길잡이든 합쳐서 이 수다.
LEG_PARTY_SIZE = 2

#: 야영지마다 여는 갈림길 수. 셋 이상이면 고르는 일이 숙제가 된다.
ROUTES_PER_LEG = 2


def _route(code: str, name: str, region_code: str, hint: str) -> dict[str, str]:
    return {"code": code, "name": name, "region_code": region_code, "hint": hint}


#: 방향 셋(설계서 9.8의 표).
#:
#: `requires_region`을 완주해야 그 방향이 열린다. 구간 수와 예상 시간은 설계서
#: 표를 그대로 옮겼고, `자체 캐릭터 최대 사용`은 따로 적지 않는다 — 구간마다
#: 두 자리씩이므로 언제나 `구간 수 × 2`다.
DIRECTIONS: dict[str, dict[str, Any]] = {
    "beyond_the_well": {
        "name": "우물 너머 답사",
        "summary": "우물정원 바깥으로 반나절. 두 구간을 서로 다른 조가 맡아요.",
        "requires_region": "echo_well",
        "max_legs": 2,
        "minutes": (16, 24),
        "routes": [
            [
                _route(
                    "well_mouth",
                    "우물 아가리",
                    "echo_well",
                    "물소리가 제일 크게 도는 쪽이에요.",
                ),
                _route(
                    "mossy_stair",
                    "이끼 낀 계단",
                    "moss_archive",
                    "서고 뒤편으로 돌아 내려가는 길이에요.",
                ),
            ],
            [
                _route(
                    "deeper_water",
                    "더 깊은 물목",
                    "echo_well",
                    "발목까지 잠기지만 메아리가 곧게 서요.",
                ),
                _route(
                    "paper_drift",
                    "종이 눈길",
                    "moss_archive",
                    "흩어진 장이 쌓여 길이 된 곳이에요.",
                ),
            ],
        ],
    },
    "starlight_crossing": {
        "name": "별빛 종단",
        "summary": "보관고를 가로질러 사흘 치를 하루에. 세 구간이에요.",
        "requires_region": "starlight_seed_vault",
        "max_legs": 3,
        "minutes": (22, 32),
        "routes": [
            [
                _route(
                    "frost_gate",
                    "성에 낀 문",
                    "starlight_seed_vault",
                    "손잡이가 하얗게 얼어 있어요.",
                ),
                _route(
                    "well_mouth",
                    "우물 아가리",
                    "echo_well",
                    "익숙한 물소리부터 짚고 갈 수 있어요.",
                ),
            ],
            [
                _route(
                    "star_drift",
                    "별가루 모래벌",
                    "starlight_seed_vault",
                    "발자국이 오래 남는 자리예요.",
                ),
                _route(
                    "paper_drift",
                    "종이 눈길",
                    "moss_archive",
                    "돌아가지만 바닥이 단단해요.",
                ),
            ],
            [
                _route(
                    "vault_core",
                    "보관고 안쪽",
                    "starlight_seed_vault",
                    "가장 멀리까지 가는 길이에요.",
                ),
                _route(
                    "deeper_water",
                    "더 깊은 물목",
                    "echo_well",
                    "익숙한 만큼 덜 헤매요.",
                ),
            ],
        ],
    },
    "outside_the_greenhouse": {
        "name": "온실 바깥 개척",
        "summary": "관측실까지 내처. 세 구간 모두 다른 조가 필요해요.",
        "requires_region": "heartwood_observatory",
        "max_legs": 3,
        "minutes": (25, 35),
        "routes": [
            [
                _route(
                    "ring_road",
                    "나이테 길",
                    "heartwood_observatory",
                    "결을 따라가면 곧장 위로 올라가요.",
                ),
                _route(
                    "frost_gate",
                    "성에 낀 문",
                    "starlight_seed_vault",
                    "한 번 몸을 녹이고 갈 수 있어요.",
                ),
            ],
            [
                _route(
                    "knot_lantern",
                    "옹이등 아래",
                    "heartwood_observatory",
                    "등이 켜져 있어 밤에도 걸을 만해요.",
                ),
                _route(
                    "star_drift",
                    "별가루 모래벌",
                    "starlight_seed_vault",
                    "느리지만 잃을 것이 적어요.",
                ),
            ],
            [
                _route(
                    "canopy_window",
                    "우듬지 창",
                    "heartwood_observatory",
                    "여기까지 오면 온실이 아래로 보여요.",
                ),
                _route(
                    "vault_core",
                    "보관고 안쪽",
                    "starlight_seed_vault",
                    "여기서 접어도 기록은 남아요.",
                ),
            ],
        ],
    },
}


def direction(code: str) -> dict[str, Any] | None:
    return DIRECTIONS.get(code)


def routes_for(direction_code: str, leg_index: int) -> list[dict[str, str]]:
    """이 구간의 갈림길. 범위를 벗어나면 빈 목록이다."""

    spec = DIRECTIONS.get(direction_code)
    if spec is None:
        return []
    routes = spec["routes"]
    if not 0 <= leg_index < len(routes):
        return []
    return [dict(route) for route in routes[leg_index]]


def route_of(
    direction_code: str, leg_index: int, route_code: str
) -> dict[str, str] | None:
    for route in routes_for(direction_code, leg_index):
        if route["code"] == route_code:
            return route
    return None


def max_own_members(direction_code: str) -> int:
    """이 방향에서 쓸 수 있는 내 캐릭터의 최대 수.

    구간마다 두 자리이므로 언제나 `구간 수 × 2`다. 설계서 표의 `4 / 4~6 / 6`이
    이 계산과 같다.
    """

    spec = DIRECTIONS.get(direction_code)
    return 0 if spec is None else int(spec["max_legs"]) * LEG_PARTY_SIZE


def validate_journey_content(region_codes: frozenset[str] | None = None) -> list[str]:
    """콘텐츠가 스스로 어긋나지 않았는지 센다.

    표를 손으로 고치다 보면 조용히 깨지는 것들이 있다 — 없는 지역을 가리키거나,
    한 야영지의 갈림길 둘이 같은 지역이라 고르는 의미가 없어지거나, 구간 수와
    갈림길 표의 길이가 어긋나거나.
    """

    from app.services.expeditions import shipped_region_codes

    shipped = region_codes if region_codes is not None else shipped_region_codes()
    errors: list[str] = []
    for code, spec in DIRECTIONS.items():
        label = f"`{code}`"
        max_legs = int(spec["max_legs"])
        if not 2 <= max_legs <= 3:
            errors.append(
                f"{korean_subject(label)} 구간 수가 2~3이 아닙니다: {max_legs}"
            )
        if spec["requires_region"] not in shipped:
            errors.append(
                f"{korean_subject(label)} 없는 지역을 해금 조건으로 씁니다: "
                f"{spec['requires_region']}"
            )
        routes = spec["routes"]
        if len(routes) != max_legs:
            errors.append(
                f"{korean_subject(label)} 구간 수는 {max_legs}인데 갈림길 표는 "
                f"{len(routes)}줄입니다"
            )
        for index, leg_routes in enumerate(routes):
            if len(leg_routes) != ROUTES_PER_LEG:
                errors.append(
                    f"{korean_subject(label)} {index}번 구간의 갈림길이 "
                    f"{len(leg_routes)}개입니다"
                )
            regions = [route["region_code"] for route in leg_routes]
            if len(set(regions)) != len(regions):
                errors.append(
                    f"{korean_subject(label)} {index}번 구간의 갈림길이 같은 지역을 "
                    f"가리킵니다: {regions}"
                )
            for route in leg_routes:
                if route["region_code"] not in shipped:
                    errors.append(
                        f"{korean_subject(label)} {index}번 구간의 "
                        f"`{route['code']}`가 없는 지역을 가리킵니다: "
                        f"{route['region_code']}"
                    )
    return errors
