from datetime import date, datetime

import pytest

from app.core.timeutil import local_date_of, month_period, time_of_day_bucket, week_period


def test_week_period_requires_monday():
    start, end = week_period(date(2026, 7, 6))  # 월요일
    assert (start, end) == (date(2026, 7, 6), date(2026, 7, 13))
    with pytest.raises(ValueError):
        week_period(date(2026, 7, 7))


def test_month_period():
    start, end = month_period(date(2026, 7, 1))
    assert (start, end) == (date(2026, 7, 1), date(2026, 8, 1))
    start, end = month_period(date(2026, 12, 1))
    assert end == date(2027, 1, 1)
    with pytest.raises(ValueError):
        month_period(date(2026, 7, 2))


def test_local_date_kst():
    # UTC 16:00 = KST 다음날 01:00
    assert local_date_of(datetime(2026, 7, 10, 16, 0)) == date(2026, 7, 11)
    assert local_date_of(datetime(2026, 7, 10, 14, 59)) == date(2026, 7, 10)


def test_time_of_day_bucket():
    # UTC 00:00 = KST 09:00 → morning
    assert time_of_day_bucket(datetime(2026, 7, 10, 0, 0)) == "morning"
    # UTC 15:00 = KST 24:00 → night
    assert time_of_day_bucket(datetime(2026, 7, 10, 15, 0)) == "night"
