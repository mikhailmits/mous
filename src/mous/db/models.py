"""Database models for mous.

Goods are signed transactions (positive income, negative expense). Recurring
goods attach a cron schedule to a good so it can be repeated automatically.
Accounts group goods; currencies denominate those values. Categories label
goods.
"""

from __future__ import annotations

from datetime import date, datetime

from oxyde import Field, Model

from mous.fx import convert as fx_convert

CURRENCY_SYMBOL_MAX_LENGTH = 8
CURRENCY_NAME_MAX_LENGTH = 64
GOOD_NAME_MAX_LENGTH = 128
ACCOUNT_NAME_MAX_LENGTH = 64
CRON_STAMP_MAX_LENGTH = 64
CTGRY_NAME_MAX_LENGTH = 30


class Primary(Model):
    """Abstract base model with a surrogate integer primary key."""

    id: int | None = Field(default=None, db_pk=True)


class Currency(Primary):
    """Currency metadata. Exchange rates are not stored here."""

    symbol: str = Field(max_length=CURRENCY_SYMBOL_MAX_LENGTH, db_unique=True)
    name: str = Field(max_length=CURRENCY_NAME_MAX_LENGTH, db_unique=True)
    is_default: bool = Field(default=False)
    goods: list[Good] = Field(db_reverse_fk="currency")

    class Meta:
        is_table = True

    @classmethod
    async def fx_context(cls) -> tuple[str, dict[int, str]]:
        """Default symbol plus id→symbol for converting stored amounts."""
        rows = await cls.objects.all()
        codes: dict[int, str] = {}
        default = "eur"
        for row in rows:
            if row.id is None:
                continue
            codes[row.id] = row.symbol
            if row.is_default:
                default = row.symbol
        return default, codes


class Account(Primary):
    """Spending or tracking account that owns goods."""

    name: str = Field(
        default="main",
        max_length=ACCOUNT_NAME_MAX_LENGTH,
        db_unique=True,
    )
    goods: list[Good] = Field(db_reverse_fk="account")

    class Meta:
        is_table = True

    async def get_balance(self) -> float:
        """Signed net in the default currency (EUR/USD/UAH stub FX).

        Unquoted currencies are omitted. ``get_balance_parts`` is still native.
        """
        total, _ = await self.get_balance_in_default()
        return total

    async def get_balance_in_default(self) -> tuple[float, str]:
        """Converted signed net plus the default currency symbol."""
        parts, _ = await self.get_balance_parts()
        default, codes = await Currency.fx_context()
        total = 0.0
        for currency_id, amount in parts:
            src = codes.get(currency_id)
            if src is None:
                continue
            converted = fx_convert(amount, src, default)
            if converted is None:
                continue
            total += converted
        return total, default

    async def get_balance_parts(self) -> tuple[list[tuple[int, float]], float]:
        """Per-currency signed nets (native) plus the naive mixed total."""
        goods = await self._goods_query().all()
        buckets: dict[int, float] = {}
        for good in goods:
            cid = good.currency_id
            if cid is None:
                continue
            buckets[cid] = buckets.get(cid, 0.0) + good.value
        parts = sorted(buckets.items())
        return parts, sum(amount for _, amount in parts)

    async def get_spent_on(
        self,
        from_: date | datetime | None = None,
        to_: date | datetime | None = None,
    ) -> float:
        """Expense magnitude in the default currency for ``[from_, to_]``.

        Income is ignored. Result is >= 0. Unquoted currencies are omitted.
        """
        amount, _ = await self.get_spent_in_default(from_, to_)
        return amount

    async def get_spent_in_default(
        self,
        from_: date | datetime | None = None,
        to_: date | datetime | None = None,
    ) -> tuple[float, str]:
        goods = await self._period_query(from_, to_).all()
        default, codes = await Currency.fx_context()
        spent = 0.0
        for good in goods:
            if good.value >= 0:
                continue
            src = codes.get(good.currency_id) if good.currency_id is not None else None
            if src is None:
                continue
            converted = fx_convert(good.value, src, default)
            if converted is None or converted >= 0:
                continue
            spent += -converted
        return spent, default

    async def get_goods(
        self,
        from_: date | datetime | None = None,
        to_: date | datetime | None = None,
        top_value: float | None = None,
        btm_value: float | None = None,
    ) -> list[Good]:
        """Goods in ``[from_, to_]``, optionally clamped to a value range, highest first."""
        query = self._period_query(from_, to_)
        if top_value is not None:
            query = query.filter(value__lte=top_value)
        if btm_value is not None:
            query = query.filter(value__gte=btm_value)
        return await query.order_by("-value").all()

    def _goods_query(self):
        return Good.objects.filter(account_id=self.id)

    def _period_query(
        self,
        from_: date | datetime | None = None,
        to_: date | datetime | None = None,
    ):
        today = date.today()
        start = self._as_date(from_) if from_ is not None else today
        end = self._as_date(to_) if to_ is not None else today
        if start > end:
            start, end = end, start
        return self._goods_query().filter(
            occurred_on__gte=start,
            occurred_on__lte=end,
        )

    @staticmethod
    def _as_date(value: date | datetime) -> date:
        if isinstance(value, datetime):
            return value.date()
        return value

    @staticmethod
    def _sum(goods: list[Good]) -> float:
        return sum(good.value for good in goods)

    @classmethod
    def _sum_spent(cls, goods: list[Good]) -> float:
        expenses = [good for good in goods if good.value < 0]
        return -cls._sum(expenses)


class Good(Primary):
    """A signed transaction recorded against an account.

    ``value`` is the amount in the good's currency: positive is income,
    negative is an expense. Zero is not a transaction.
    """

    name: str = Field(max_length=GOOD_NAME_MAX_LENGTH)
    value: float
    occurred_on: date = Field(default_factory=date.today, db_index=True)
    currency: Currency | None = Field(
        default=None, db_nullable=False, db_on_delete="RESTRICT"
    )
    account: Account | None = Field(
        default=None, db_nullable=False, db_on_delete="CASCADE"
    )
    category: GoodCategory | None = Field(default=None, db_on_delete="SET NULL")
    recurring_schedules: list[RecurringGood] = Field(db_reverse_fk="good")

    class Meta:
        is_table = True


class GoodCategory(Primary):
    """Label for grouping goods (for example food, rent, or salary)."""

    name: str = Field(max_length=CTGRY_NAME_MAX_LENGTH, db_unique=True)
    goods: list[Good] = Field(db_reverse_fk="category")

    class Meta:
        is_table = True


class RecurringGood(Primary):
    """Schedule for repeating a good on a cron expression."""

    good: Good | None = Field(default=None, db_nullable=False, db_on_delete="CASCADE")
    cron_stamp: str = Field(max_length=CRON_STAMP_MAX_LENGTH)

    class Meta:
        is_table = True
