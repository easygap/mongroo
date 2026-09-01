"""지역 보상 밴드가 설계서 9.1의 표와 같은지 센다.

이 표는 조용히 어긋난 적이 있다. 설계서는 `6·8·9·10 / 2·3·4·5`인데 콘텐츠
팩은 `6·7·8·9 / 2·2·3·3`으로 실려 있었고, 어느 검사도 그 차이를 보지 않아
아무도 몰랐다. 지역을 하나 더 넣거나 밴드를 손볼 때 여기가 먼저 걸린다.
"""

import pytest

from app.core.config import get_settings
from app.services.adventure import DAILY_ECONOMY
from app.services.expeditions import load_content, region_order, shipped_region_codes


#: 설계서 9.1의 `일일 경제` 표. (XP, 씨앗, 가치 예산, 최대 칸)
DESIGN_BANDS = {
    "moss_archive": (6, 2, 1, 1),
    "echo_well": (8, 3, 2, 2),
    "starlight_seed_vault": (9, 4, 3, 3),
    "heartwood_observatory": (10, 5, 4, 3),
}


def _band(region_code: str) -> tuple[int, int, int, int]:
    reward = load_content(region_code)["region"]["reward"]
    return (
        int(reward["exp"]),
        int(reward["seeds"]),
        int(reward["loot_value_units"]),
        int(reward["loot_slots"]),
    )


def test_every_shipped_region_has_a_designed_band():
    # 표에 없는 지역을 싣거나, 실려 있지 않은 지역을 표에 적어 두지 않는다.
    assert set(DESIGN_BANDS) == set(shipped_region_codes())


@pytest.mark.parametrize("region_code", sorted(DESIGN_BANDS))
def test_band_matches_the_design_table(region_code):
    assert _band(region_code) == DESIGN_BANDS[region_code]


def test_bands_rise_with_distance():
    """멀수록 완만하게 오른다. 어느 축도 뒤로 가지 않는다."""

    previous = None
    for region_code in region_order():
        current = _band(region_code)
        if previous is not None:
            assert all(now >= before for now, before in zip(current, previous)), (
                region_code,
                current,
                previous,
            )
            assert current != previous, f"{region_code}가 앞 지역과 같은 밴드입니다"
        previous = current


def test_a_diary_still_beats_the_farthest_expedition():
    """9.1이 지키겠다고 적은 순서.

    `가장 먼 관측실과 자동 순찰을 같은 날 완료해도 XP 10·씨앗 8이라 일기 한 편의
    XP 40·씨앗 15보다 작다.` 이 문장이 이 콘텐츠의 존재 이유에 가깝다 — 본편은
    마음 일기이고 탐험은 곁가지다.
    """

    economy = {row["code"]: row for row in DAILY_ECONOMY}
    diary = economy["diary"]
    patrol = economy["patrol"]
    farthest = max(_band(code)[:2] for code in DESIGN_BANDS)

    assert farthest[0] + patrol["exp"] < diary["exp"]
    assert farthest[1] + patrol["seeds"] < diary["seeds"]


def test_the_farthest_run_and_a_diary_fit_inside_the_daily_cap():
    """일기 40 + 관측실 10 = 50. 하루 상한과 정확히 같다(9.1)."""

    diary = next(row for row in DAILY_ECONOMY if row["code"] == "diary")
    farthest = max(_band(code)[0] for code in DESIGN_BANDS)
    assert diary["exp"] + farthest == get_settings().daily_exp_cap
