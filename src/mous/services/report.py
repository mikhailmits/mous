"""Capture `mous summary` stdout on a timer, parse it, and keep the last report.

The last capture is written next to config.json so a restart only runs again
when `report_period` has actually elapsed.
"""

from __future__ import annotations

import asyncio
import json
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

from mous.config.utils import config_dir, is_frozen, report_period
from mous.services.summary import (
    GoodSpend,
    PeriodParseError,
    SubscriptionCharge,
    Summary,
    parse_period,
)

_CAPTURE_TIMEOUT = 30.0
_RETRY_SECONDS = 15.0
_SECONDS_PER_DAY = 24 * 60 * 60
_FIELD = re.compile(
    r"^    (currency|n|in|out|saved|top|runway|next_month_spent_predictions) = (.*)$"
)
_KEEP_ROW = re.compile(r"^      (.+) = (\S+)(?:\s+(\S+))?$")
_TOTAL_LABEL = "Total spent on subscriptions"


class SummaryParseError(ValueError):
    """CLI stdout did not match the `mous summary` layout."""


class SummaryCaptureError(Exception):
    """`mous summary` did not produce usable stdout."""


@dataclass
class SummaryReport:
    """Parses `mous summary` stdout and holds the last successful capture."""

    raw: str = ""
    summary: Summary | None = None
    captured_at: datetime | None = None
    period: str | None = None
    error: str | None = None

    def ingest(
        self,
        stdout: str,
        *,
        period: str | None = None,
        captured_at: datetime | None = None,
    ) -> Summary:
        parsed = parse_summary_stdout(stdout)
        self.raw = stdout
        self.summary = parsed
        self.captured_at = _as_utc(captured_at) or datetime.now(timezone.utc)
        self.period = period
        self.error = None
        return parsed

    def fail(self, message: str) -> None:
        self.error = message


summary_report = SummaryReport()
_REPORT_FILE = "summary_report.json"


def summary_report_path() -> Path:
    return config_dir() / _REPORT_FILE


def load_summary_report(report: SummaryReport | None = None) -> SummaryReport:
    """Restore the last capture from disk into `report` (or the process singleton)."""
    holder = report or summary_report
    path = summary_report_path()
    if not path.is_file():
        return holder
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return holder
    if not isinstance(raw, dict):
        return holder
    captured_at = _parse_captured_at(raw.get("captured_at"))
    period = raw.get("period")
    stdout = raw.get("stdout")
    if isinstance(period, str) and period.strip():
        holder.period = " ".join(period.split())
    else:
        period = None
    if captured_at is not None:
        holder.captured_at = captured_at
    if not isinstance(stdout, str) or not stdout.strip():
        return holder
    try:
        holder.ingest(stdout, period=holder.period, captured_at=captured_at)
        if captured_at is None:
            holder.captured_at = None
    except SummaryParseError as exc:
        holder.raw = stdout
        holder.captured_at = captured_at
        holder.fail(str(exc))
    return holder


def save_summary_report(report: SummaryReport) -> None:
    """Write stdout + capture time next to config.json."""
    if report.captured_at is None or not report.raw:
        return
    path = summary_report_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "captured_at": report.captured_at.astimezone(timezone.utc).isoformat(),
        "period": report.period,
        "stdout": report.raw,
    }
    data = json.dumps(payload, indent=2) + "\n"
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(data, encoding="utf-8")
    tmp.replace(path)


def parse_summary_stdout(text: str) -> Summary:
    """Turn `mous summary` stdout into a `Summary`."""
    lines = text.splitlines()
    if not lines or lines[0].strip() != "summary":
        raise SummaryParseError("stdout does not start with 'summary'")
    if len(lines) < 2 or not lines[1].startswith("  "):
        raise SummaryParseError("missing period line")
    period = lines[1][2:]
    fields: dict[str, str] = {}
    keep_lines: list[str] = []
    in_keep = False
    for line in lines[2:]:
        if in_keep:
            keep_lines.append(line)
            continue
        if line.strip() == "if you keep up you will spend money on:":
            in_keep = True
            continue
        if not line.strip():
            continue
        match = _FIELD.match(line)
        if match is None:
            raise SummaryParseError(f"unrecognized summary line: {line!r}")
        fields[match.group(1)] = match.group(2)
    required = (
        "currency",
        "n",
        "in",
        "out",
        "saved",
        "top",
        "runway",
        "next_month_spent_predictions",
    )
    missing = [name for name in required if name not in fields]
    if missing:
        raise SummaryParseError(f"missing fields: {', '.join(missing)}")
    currency = fields["currency"]
    income, _ = _amount(fields["in"], currency)
    expense, _ = _amount(fields["out"], currency)
    saved, _ = _amount(fields["saved"], currency)
    predicted, _ = _amount(fields["next_month_spent_predictions"], currency)
    subs, goods = _parse_keep_up(keep_lines, currency)
    return Summary(
        period=period,
        n=_int_field(fields["n"], "n"),
        currency=currency,
        income=income,
        expense=expense,
        saved=saved,
        top=_parse_top(fields["top"]),
        runway=_parse_runway(fields["runway"]),
        next_month_spent_predictions=predicted,
        keep_up_subscriptions=subs,
        keep_up_goods=goods,
    )


def fetch_summary_stdout(period: str | None = None) -> str:
    """Run `mous summary` and return stdout."""
    cmd = _summary_command(period)
    try:
        completed = subprocess.run(
            cmd,
            check=False,
            capture_output=True,
            text=True,
            timeout=_CAPTURE_TIMEOUT,
        )
    except FileNotFoundError as exc:
        raise SummaryCaptureError("mous CLI is not installed") from exc
    except subprocess.TimeoutExpired as exc:
        raise SummaryCaptureError("mous summary timed out") from exc
    if completed.returncode != 0:
        err = (completed.stderr or completed.stdout or "mous summary failed").strip()
        raise SummaryCaptureError(err)
    if not completed.stdout.strip():
        raise SummaryCaptureError("mous summary printed nothing")
    return completed.stdout


async def run_summary_schedule(report: SummaryReport | None = None) -> None:
    """Capture `mous summary` when the stored period has elapsed."""
    holder = report or summary_report
    load_summary_report(holder)
    await asyncio.sleep(1)
    while True:
        period = _configured_period()
        remaining = _remaining_seconds(holder.captured_at, period)
        if remaining > 0:
            await asyncio.sleep(remaining)
            continue
        try:
            stdout = await asyncio.to_thread(fetch_summary_stdout, period)
            holder.ingest(stdout, period=period)
        except asyncio.CancelledError:
            raise
        except Exception as exc:
            holder.fail(str(exc))
            await asyncio.sleep(_RETRY_SECONDS)
            continue
        try:
            save_summary_report(holder)
        except OSError as exc:
            holder.fail(f"could not persist report: {exc}")


def _configured_period() -> str:
    text = report_period()
    try:
        parse_period(text)
    except PeriodParseError:
        return "14 days"
    return text


def _period_seconds(period: str) -> float:
    first, last = parse_period(period)
    days = (last - first).days + 1
    return max(days, 1) * _SECONDS_PER_DAY


def _remaining_seconds(captured_at: datetime | None, period: str) -> float:
    moment = _as_utc(captured_at)
    if moment is None:
        return 0.0
    elapsed = (datetime.now(timezone.utc) - moment).total_seconds()
    return max(_period_seconds(period) - elapsed, 0.0)


def _as_utc(value: datetime | None) -> datetime | None:
    if value is None:
        return None
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)


def _parse_captured_at(raw: object) -> datetime | None:
    if not isinstance(raw, str) or not raw:
        return None
    text = raw.replace("Z", "+00:00") if raw.endswith("Z") else raw
    try:
        return _as_utc(datetime.fromisoformat(text))
    except ValueError:
        return None


def _summary_command(period: str | None) -> list[str]:
    if is_frozen():
        cmd = [sys.executable, "summary"]
    else:
        sibling = Path(sys.executable).resolve().parent / "mous"
        if sibling.is_file():
            cmd = [str(sibling), "summary"]
        else:
            found = shutil.which("mous")
            if found is None:
                raise SummaryCaptureError("mous CLI is not installed")
            cmd = [found, "summary"]
    if period:
        cmd.extend(period.split())
    return cmd


def _int_field(raw: str, name: str) -> int:
    try:
        return int(raw)
    except ValueError as exc:
        raise SummaryParseError(f"invalid {name}: {raw!r}") from exc


def _amount(raw: str, currency: str) -> tuple[float, str]:
    parts = raw.split()
    if not parts:
        raise SummaryParseError("missing amount")
    try:
        value = float(parts[0])
    except ValueError as exc:
        raise SummaryParseError(f"invalid amount: {raw!r}") from exc
    symbol = parts[1] if len(parts) > 1 else currency
    return value, symbol


def _parse_top(raw: str) -> list[str]:
    text = raw.strip()
    if text == "[]":
        return []
    if not (text.startswith("[") and text.endswith("]")):
        raise SummaryParseError(f"invalid top: {raw!r}")
    inner = text[1:-1].strip()
    if not inner:
        return []
    return [name.strip() for name in inner.split(", ") if name.strip()]


def _parse_runway(raw: str) -> float | None:
    if raw.strip() == "...":
        return None
    try:
        return float(raw)
    except ValueError as exc:
        raise SummaryParseError(f"invalid runway: {raw!r}") from exc


def _parse_keep_up(
    lines: list[str],
    currency: str,
) -> tuple[list[SubscriptionCharge], list[GoodSpend]]:
    subs: list[SubscriptionCharge] = []
    goods: list[GoodSpend] = []
    after_total = False
    for line in lines:
        if not line.strip():
            continue
        match = _KEEP_ROW.match(line)
        if match is None:
            raise SummaryParseError(f"unrecognized keep-up line: {line!r}")
        name, amount_text = match.group(1), match.group(2)
        value, _ = _amount(f"{amount_text} {match.group(3) or currency}", currency)
        if name == _TOTAL_LABEL:
            after_total = True
            continue
        if after_total:
            goods.append(GoodSpend(name=name, spent=value))
        else:
            subs.append(SubscriptionCharge(name=name, value=value))
    return subs, goods
