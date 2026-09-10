from datetime import date, datetime, timezone


def unix_to_utc_date(unix_time: int) -> date:
    return datetime.fromtimestamp(unix_time, tz=timezone.utc).date()


def utc_date_to_unix(value: date) -> int:
    return int(datetime(value.year, value.month, value.day, tzinfo=timezone.utc).timestamp())


def utc_today() -> date:
    return datetime.now(timezone.utc).date()
