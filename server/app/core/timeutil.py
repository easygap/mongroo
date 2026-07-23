"""시간 규칙: DB는 naive UTC, 사용자 기준 날짜는 Asia/Seoul (design.md 4.1).

주 시작은 월요일, 기간은 [start, end) 반개구간.
"""
from datetime import date, datetime, timedelta, timezone
from zoneinfo import ZoneInfo

KST = ZoneInfo("Asia/Seoul")


def utcnow() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None)


def to_utc_iso(dt: datetime | None) -> str | None:
    if dt is None:
        return None
    return dt.replace(microsecond=0).isoformat() + "Z"


def local_date_of(utc_dt: datetime, tz: ZoneInfo = KST) -> date:
    return utc_dt.replace(tzinfo=timezone.utc).astimezone(tz).date()


def local_day_bounds_utc(local_day: date, tz: ZoneInfo = KST) -> tuple[datetime, datetime]:
    start = datetime(local_day.year, local_day.month, local_day.day, tzinfo=tz)
    end = start + timedelta(days=1)
    return (
        start.astimezone(timezone.utc).replace(tzinfo=None),
        end.astimezone(timezone.utc).replace(tzinfo=None),
    )


def week_period(start: date) -> tuple[date, date]:
    if start.weekday() != 0:
        raise ValueError("주간 리포트 시작일은 월요일이어야 한다")
    return start, start + timedelta(days=7)


def month_period(start: date) -> tuple[date, date]:
    if start.day != 1:
        raise ValueError("월간 리포트 시작일은 1일이어야 한다")
    if start.month == 12:
        return start, date(start.year + 1, 1, 1)
    return start, date(start.year, start.month + 1, 1)


def time_of_day_bucket(utc_dt: datetime, tz: ZoneInfo = KST) -> str:
    hour = utc_dt.replace(tzinfo=timezone.utc).astimezone(tz).hour
    if 5 <= hour < 12:
        return "morning"
    if 12 <= hour < 18:
        return "afternoon"
    if 18 <= hour < 23:
        return "evening"
    return "night"
