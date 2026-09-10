from __future__ import annotations

from typing import Generic, TypeVar

from pydantic import BaseModel, Field, field_validator, model_validator

from mous.api.time import utc_date_to_unix
from mous.db.models import (
    ACCOUNT_NAME_MAX_LENGTH,
    CRON_STAMP_MAX_LENGTH,
    CTGRY_NAME_MAX_LENGTH,
    CURRENCY_NAME_MAX_LENGTH,
    CURRENCY_SYMBOL_MAX_LENGTH,
    GOOD_NAME_MAX_LENGTH,
    Account,
    Currency,
    Good,
    GoodCategory,
    RecurringGood,
)

T = TypeVar("T")


def require_nonzero_money(value: float) -> float:
    """Goods are signed transactions: positive income, negative expense, never zero."""
    if value == 0:
        raise ValueError("value must be non-zero")
    return value


class Collection(BaseModel, Generic[T]):
    items: list[T]
    count: int


class AccountCreate(BaseModel):
    name: str = Field(max_length=ACCOUNT_NAME_MAX_LENGTH)


class AccountPatch(BaseModel):
    name: str | None = Field(default=None, max_length=ACCOUNT_NAME_MAX_LENGTH)


class AccountOut(BaseModel):
    id: int
    name: str


class BalanceOut(BaseModel):
    account_id: int
    amount: float


class SpentOut(BaseModel):
    """Expense magnitude (>= 0). Income is not included. Not converted."""

    account_id: int
    from_unix_time: int
    to_unix_time: int
    amount: float


class TransactionCreate(BaseModel):
    name: str = Field(max_length=GOOD_NAME_MAX_LENGTH)
    value: float = Field(
        allow_inf_nan=False,
        description="Signed amount in the currency: >0 income, <0 expense.",
    )
    currency_id: int
    account_id: int | None = None
    occurred_unix_time: int | None = None
    category_id: int | None = None

    @field_validator("value")
    @classmethod
    def value_nonzero(cls, value: float) -> float:
        return require_nonzero_money(value)


class TransactionPatch(BaseModel):
    name: str | None = Field(default=None, max_length=GOOD_NAME_MAX_LENGTH)
    value: float | None = Field(
        default=None,
        allow_inf_nan=False,
        description="Signed amount in the currency: >0 income, <0 expense.",
    )
    currency_id: int | None = None
    occurred_unix_time: int | None = None
    category_id: int | None = None

    @field_validator("value")
    @classmethod
    def value_nonzero(cls, value: float | None) -> float | None:
        if value is None:
            return None
        return require_nonzero_money(value)


class TransactionOut(BaseModel):
    id: int
    name: str
    value: float = Field(description="Signed amount: >0 income, <0 expense.")
    currency_id: int
    account_id: int
    occurred_unix_time: int
    category_id: int | None = None


class SubscriptionCreate(BaseModel):
    cron_stamp: str = Field(max_length=CRON_STAMP_MAX_LENGTH)
    good_id: int | None = None
    name: str | None = Field(default=None, max_length=GOOD_NAME_MAX_LENGTH)
    value: float | None = Field(
        default=None,
        allow_inf_nan=False,
        description="Signed amount: >0 income, <0 expense.",
    )
    currency_id: int | None = None
    account_id: int | None = None
    occurred_unix_time: int | None = None

    @model_validator(mode="after")
    def require_good_or_transaction_fields(self) -> SubscriptionCreate:
        if self.good_id is not None:
            return self
        if self.name is None or self.value is None or self.currency_id is None:
            raise ValueError("provide good_id, or name, value, and currency_id")
        return self

    @field_validator("value")
    @classmethod
    def value_nonzero(cls, value: float | None) -> float | None:
        if value is None:
            return None
        return require_nonzero_money(value)


class SubscriptionPatch(BaseModel):
    cron_stamp: str | None = Field(default=None, max_length=CRON_STAMP_MAX_LENGTH)


class SubscriptionOut(BaseModel):
    id: int
    good_id: int
    cron_stamp: str
    account_id: int | None = None
    name: str | None = None
    value: float | None = Field(
        default=None,
        description="Signed amount: >0 income, <0 expense.",
    )


class CurrencyCreate(BaseModel):
    symbol: str = Field(max_length=CURRENCY_SYMBOL_MAX_LENGTH)
    name: str = Field(max_length=CURRENCY_NAME_MAX_LENGTH)
    is_default: bool = False


class CurrencyPatch(BaseModel):
    symbol: str | None = Field(default=None, max_length=CURRENCY_SYMBOL_MAX_LENGTH)
    name: str | None = Field(default=None, max_length=CURRENCY_NAME_MAX_LENGTH)
    is_default: bool | None = None


class CurrencyOut(BaseModel):
    id: int
    symbol: str
    name: str
    is_default: bool


class CategoryCreate(BaseModel):
    name: str = Field(max_length=CTGRY_NAME_MAX_LENGTH)


class CategoryPatch(BaseModel):
    name: str | None = Field(default=None, max_length=CTGRY_NAME_MAX_LENGTH)


class CategoryOut(BaseModel):
    id: int
    name: str


def require_id(value: int | None) -> int:
    if value is None:
        raise RuntimeError("expected persisted id")
    return value


def account_out(account: Account) -> AccountOut:
    return AccountOut(id=require_id(account.id), name=account.name)


def transaction_out(good: Good) -> TransactionOut:
    return TransactionOut(
        id=require_id(good.id),
        name=good.name,
        value=good.value,
        currency_id=require_id(good.currency_id),
        account_id=require_id(good.account_id),
        occurred_unix_time=utc_date_to_unix(good.occurred_on),
        category_id=good.category_id,
    )


def subscription_out(item: RecurringGood, good: Good | None = None) -> SubscriptionOut:
    linked = good if good is not None else item.good
    return SubscriptionOut(
        id=require_id(item.id),
        good_id=require_id(item.good_id),
        cron_stamp=item.cron_stamp,
        account_id=linked.account_id if linked is not None else None,
        name=linked.name if linked is not None else None,
        value=linked.value if linked is not None else None,
    )


def currency_out(currency: Currency) -> CurrencyOut:
    return CurrencyOut(
        id=require_id(currency.id),
        symbol=currency.symbol,
        name=currency.name,
        is_default=currency.is_default,
    )


def category_out(category: GoodCategory) -> CategoryOut:
    return CategoryOut(id=require_id(category.id), name=category.name)


def collection(items: list[T]) -> Collection[T]:
    return Collection(items=items, count=len(items))
