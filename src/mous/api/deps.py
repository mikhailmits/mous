from mous.db.models import Account
from mous.db.utils import get_account, get_account_by_name

DEFAULT_ACCOUNT_NAME = "main"


async def resolve_account(account_id: int | None) -> Account:
    if account_id is not None:
        return await get_account(account_id)
    return await get_account_by_name(DEFAULT_ACCOUNT_NAME)
