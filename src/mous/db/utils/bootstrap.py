from oxyde.exceptions import IntegrityError, NotFoundError

from mous.db.utils.accounts import create_account, get_account_by_name
from mous.db.utils.currencies import create_currency, get_currency_by_symbol

DEFAULT_ACCOUNT_NAME = "main"
DEFAULT_CURRENCY_SYMBOL = "eur"
DEFAULT_CURRENCY_NAME = "Euro"


async def ensure_defaults() -> None:
    """Create the ``main`` account and ``eur`` currency if they are missing."""
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
