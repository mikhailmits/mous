"""Prompts for the three diagram tasks: reports, optimize, forecasts."""

from __future__ import annotations

TASKS = ("reports", "optimize", "forecasts")

SYSTEM_BASE = """You are the mous finance agent.
You receive a personal ledger encoding plus a decode legend.
Produce ONLY compact JSON for the requested task. No markdown.
Money is signed in the source: negative = expense, positive = income.
Round money to 2 decimals. Counts are integers.
If a field is unknown, use null rather than guessing wildly.
"""

REPORTS_USER = """Task: reports
Return JSON:
{
  "reports": {
    "n_transactions": int,
    "n_income": int,
    "n_expense": int,
    "total_income": number,
    "total_expense": number,
    "net": number,
    "top_category_by_spend": string,
    "top_category_spend": number,
    "top5_categories": [{"category": string, "spend": number}]
  }
}
Spend magnitude is positive. total_expense is the sum of -value for expenses.
"""

OPTIMIZE_USER = """Task: what and how to optimize
Discretionary categories: restaurants, entertainment, coffee, shopping, travel, gifts.
Necessary: rent, groceries, transport, utilities, insurance, healthcare.
Return JSON:
{
  "optimize": {
    "best_single_cut": {"category": string, "spend": number, "cut_20pct_saves": number},
    "discretionary_share": number,
    "subscription_annual_cost": number,
    "playbook": [string]
  }
}
best_single_cut is the discretionary category with the highest spend.
subscription_annual_cost = sum of (-value * 12) for recurring subscriptions with negative value.
"""

FORECAST_USER = """Task: forecasts
Use the last 3 calendar months present in the ledger (or all months if fewer).
Naive forecast = mean of those months.
Return JSON:
{
  "forecasts": {
    "avg_monthly_spend_last3": number,
    "avg_monthly_income_last3": number,
    "next_month_spend_naive": number,
    "next_month_income_naive": number,
    "next_month_net_naive": number
  }
}
"""

TASK_PROMPTS = {
    "reports": REPORTS_USER,
    "optimize": OPTIMIZE_USER,
    "forecasts": FORECAST_USER,
}

PROMPT_VARIANTS = {
    "schema_then_data": "Decode the encoding first, then compute. Schema/legend precedes data.",
    "tool_result": "Treat the ledger block as a tool result named get_transactions. Do not rewrite it.",
    "scan_categories": "First list unique categories, then sum in one pass. Do not store every row in your reply.",
}


def wrap_payload(decode_instructions: str, payload: str, variant: str = "schema_then_data") -> str:
    hint = PROMPT_VARIANTS.get(variant, PROMPT_VARIANTS["schema_then_data"])
    return (
        f"{hint}\n\nDECODE:\n{decode_instructions or 'plain text ledger'}\n\nLEDGER:\n{payload}"
    )
