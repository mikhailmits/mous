"""Database models for mous.

Goods are signed transactions (positive income, negative expense). Recurring
goods attach a cron schedule to a good so it can be repeated automatically.
Accounts group goods; currencies denominate those values. Categories label
goods.
"""

from __future__ import annotations

from datetime import date, datetime

from oxyde import Field, Model

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
        """Signed net of this account's goods, in each good's own currency.

        Positive goods (income) add; negative goods (expenses) subtract.
        Mixed currencies are not converted.
        """
        goods = await self._goods_query().all()
        return self._sum(goods)

    async def get_spent_on(
        self,
        from_: date | datetime | None = None,
        to_: date | datetime | None = None,
    ) -> float:
        """Expense magnitude in ``[from_, to_]`` (today if omitted).

        Goods are signed transactions: ``value < 0`` is an expense, ``value > 0``
        is income. Only expenses count here. Income is ignored. Result is >= 0.
        Mixed currencies are not converted.
        """
        goods = await self._period_query(from_, to_).all()
        return self._sum_spent(goods)

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
