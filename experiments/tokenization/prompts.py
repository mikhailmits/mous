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
discretionary_share is a MONEY total (sum of spend in discretionary categories), not a percentage.
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
    "eight_fields": "Return only the JSON keys named in the task. Do not echo the ledger.",
    "ignore_rest": "Compute the listed fields only. Ignore merchants, accounts, playbooks, and extra keys.",
}

# Compact overlays — TASK_PROMPTS above stays the eval-harness default.
SYSTEM_COMPACT = """Mous finance agent. Compact JSON only — no markdown, no prose.
Signed ledger: negative=expense, positive=income. Report spend as a positive magnitude.
Sum every amount; do not sample or round to thousands. Money to 2 decimals. Counts are integers.
"""

REPORTS_EIGHT_USER = """Compute these 8 fields from the ledger. Ignore top5, playbooks, accounts, names, and every other key.

Emit exactly:
{"reports":{"n_transactions":int,"n_income":int,"n_expense":int,"total_income":n,"total_expense":n,"net":n,"top_category_by_spend":str,"top_category_spend":n}}

Rules:
- Scan every amount. Do not sample, skip months, or round to thousands.
- Keep money to 2 decimals (cent precision). 3243.94 stays 3243.94.
- n_income = count of +amounts; n_expense = count of -amounts.
- *k means that amount appears k times (k rows, not k+1).
- total_income = sum of positives. total_expense = sum of -negatives (positive). net = total_income - total_expense.
- top_category_by_spend = category with the largest spend magnitude; top_category_spend = that magnitude.
- SUB lines are metadata already included in the amounts — do not add them again.
"""

OPTIMIZE_COMPACT_USER = """Emit only:
{"optimize":{"best_single_cut":{"category":str,"spend":n,"cut_20pct_saves":n},"discretionary_share":n,"subscription_annual_cost":n}}
Discretionary: restaurants, entertainment, coffee, shopping, travel, gifts.
best_single_cut = discretionary category with the highest spend (positive). cut_20pct_saves = 0.2*spend.
discretionary_share = money sum of spend in those 6 categories, not a percent.
subscription_annual_cost = sum(-value*12) over SUB rows with value<0 (already in the ledger — do not double-count).
"""

FORECAST_COMPACT_USER = """Emit only:
{"forecasts":{"avg_monthly_spend_last3":n,"avg_monthly_income_last3":n,"next_month_spend_naive":n,"next_month_income_naive":n,"next_month_net_naive":n}}
Use the last 3 calendar months present. Monthly spend = sum of -negatives; income = sum of positives.
Naive next month = mean of those 3. next_month_net_naive = income - spend.
"""

TASK_PROMPTS_COMPACT = {
    "reports": REPORTS_EIGHT_USER,
    "optimize": OPTIMIZE_COMPACT_USER,
    "forecasts": FORECAST_COMPACT_USER,
}

TASK_PROMPT_SETS = {
    "default": TASK_PROMPTS,
    "compact": TASK_PROMPTS_COMPACT,
    "eight": TASK_PROMPTS_COMPACT,
}

SYSTEM_PROMPTS = {
    "base": SYSTEM_BASE,
    "compact": SYSTEM_COMPACT,
}


def wrap_payload(decode_instructions: str, payload: str, variant: str = "schema_then_data") -> str:
    hint = PROMPT_VARIANTS.get(variant, PROMPT_VARIANTS["schema_then_data"])
    return (
        f"{hint}\n\nDECODE:\n{decode_instructions or 'plain text ledger'}\n\nLEDGER:\n{payload}"
    )


def select_task_prompt(task: str, prompt_set: str = "default") -> str:
    prompts = TASK_PROMPT_SETS.get(prompt_set) or TASK_PROMPTS
    return prompts[task]


def instruction_text(
    task: str,
    *,
    system: str = "compact",
    prompt_set: str = "eight",
    variant: str = "ignore_rest",
    decode_instructions: str = "",
) -> str:
    """System + task + wrap hint + optional decode. No ledger. For overhead counts."""
    sys_text = SYSTEM_PROMPTS.get(system, SYSTEM_COMPACT)
    user_task = select_task_prompt(task, prompt_set)
    hint = PROMPT_VARIANTS.get(variant, PROMPT_VARIANTS["schema_then_data"])
    decode = decode_instructions or ""
    decode_block = f"\n\nDECODE:\n{decode}" if decode else ""
    return f"{sys_text}\n{user_task}\n{hint}{decode_block}"


def messages_for(
    task: str,
    decode_instructions: str,
    payload: str,
    *,
    variant: str = "schema_then_data",
    system: str = "base",
    prompt_set: str = "default",
) -> list[dict[str, str]]:
    """Build chat messages. Default args match evaluate_llm (TASK_PROMPTS + SYSTEM_BASE)."""
    sys_text = SYSTEM_PROMPTS.get(system, SYSTEM_BASE)
    user_task = select_task_prompt(task, prompt_set)
    return [
        {"role": "system", "content": sys_text},
        {
            "role": "user",
            "content": user_task + "\n\n" + wrap_payload(decode_instructions, payload, variant),
        },
    ]
