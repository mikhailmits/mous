from oxyde.exceptions import IntegrityError, NotFoundError

from mous.db.utils.accounts import create_account, get_account_by_name
from mous.db.utils.categories import create_category, get_category_by_name
from mous.db.utils.currencies import create_currency, get_currency_by_symbol

DEFAULT_ACCOUNT_NAME = "main"
DEFAULT_CURRENCY_SYMBOL = "eur"
DEFAULT_CURRENCY_NAME = "Euro"

STARTER_CURRENCIES: tuple[tuple[str, str], ...] = (
    ("usd", "US Dollar"),
    ("uah", "Hryvnia"),
)

STARTER_CATEGORIES: tuple[str, ...] = (
    "groceries",
    "eating out",
    "transport",
    "rent",
    "salary",
    "health",
    "fun",
    "other",
)


async def ensure_defaults() -> None:
    """Create the ``main`` account, starter currencies, and categories if missing."""
    try:
        await get_account_by_name(DEFAULT_ACCOUNT_NAME)
    except NotFoundError:
        try:
            await create_account(DEFAULT_ACCOUNT_NAME)
        except IntegrityError:
            pass
    try:
        await get_currency_by_symbol(DEFAULT_CURRENCY_SYMBOL)
    except NotFoundError:
        try:
            await create_currency(
                symbol=DEFAULT_CURRENCY_SYMBOL,
                name=DEFAULT_CURRENCY_NAME,
                is_default=True,
            )
        except IntegrityError:
            pass
    for symbol, name in STARTER_CURRENCIES:
        try:
            await get_currency_by_symbol(symbol)
        except NotFoundError:
            try:
                await create_currency(symbol=symbol, name=name, is_default=False)
            except IntegrityError:
                pass
    for category_name in STARTER_CATEGORIES:
        try:
            await get_category_by_name(category_name)
        except NotFoundError:
            try:
                await create_category(category_name)
            except IntegrityError:
                pass
