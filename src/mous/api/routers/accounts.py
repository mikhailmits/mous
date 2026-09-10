from fastapi import APIRouter, Query, Response

from mous.api.schemas import (
    AccountCreate,
    AccountOut,
    AccountPatch,
    BalanceOut,
    Collection,
    SpentOut,
    account_out,
    collection,
)
from mous.api.time import unix_to_utc_date, utc_date_to_unix, utc_today
from mous.db.utils import (
    create_account,
    delete_account,
    get_account,
    get_accounts,
    update_account_name,
)

router = APIRouter(prefix="/accounts", tags=["accounts"])


@router.get("", operation_id="list_accounts")
async def list_accounts() -> Collection[AccountOut]:
    accounts = await get_accounts()
    return collection([account_out(account) for account in accounts])


@router.post("", operation_id="create_account", status_code=201)
async def create_account_endpoint(body: AccountCreate) -> AccountOut:
    account = await create_account(name=body.name)
    return account_out(account)


@router.get("/{account_id}", operation_id="get_account")
async def get_account_endpoint(account_id: int) -> AccountOut:
    account = await get_account(account_id)
    return account_out(account)


@router.patch("/{account_id}", operation_id="update_account")
async def update_account_endpoint(account_id: int, body: AccountPatch) -> AccountOut:
    if body.name is not None:
        account = await update_account_name(account_id, body.name)
    else:
        account = await get_account(account_id)
    return account_out(account)


@router.delete("/{account_id}", operation_id="delete_account", status_code=204)
async def delete_account_endpoint(account_id: int) -> Response:
    await delete_account(account_id)
    return Response(status_code=204)


@router.get("/{account_id}/balance", operation_id="get_balance")
async def get_balance_endpoint(account_id: int) -> BalanceOut:
    account = await get_account(account_id)
    amount = await account.get_balance()
    return BalanceOut(account_id=account_id, amount=amount)


@router.get("/{account_id}/spent", operation_id="get_spent")
async def get_spent_endpoint(
    account_id: int,
    from_unix_time: int | None = Query(default=None),
    to_unix_time: int | None = Query(default=None),
) -> SpentOut:
    account = await get_account(account_id)
    today = utc_today()
    start = unix_to_utc_date(from_unix_time) if from_unix_time is not None else today
    end = unix_to_utc_date(to_unix_time) if to_unix_time is not None else today
    if start > end:
        start, end = end, start
    amount = await account.get_spent_on(start, end)
    return SpentOut(
        account_id=account_id,
        from_unix_time=utc_date_to_unix(start),
        to_unix_time=utc_date_to_unix(end),
        amount=amount,
    )
