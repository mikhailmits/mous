from fastapi import APIRouter, Query, Response

from mous.api.deps import resolve_account
from mous.api.schemas import (
    Collection,
    TransactionCreate,
    TransactionOut,
    TransactionPatch,
    collection,
    require_id,
    transaction_out,
)
from mous.api.time import unix_to_utc_date, utc_today
from mous.db.utils import (
    create_good,
    delete_good,
    get_good,
    get_goods,
    update_good_category,
    update_good_currency,
    update_good_name,
    update_good_occurred_on,
    update_good_value,
)

router = APIRouter(prefix="/transactions", tags=["transactions"])


@router.get("", operation_id="list_transactions")
async def list_transactions(
    account_id: int | None = Query(default=None),
    from_unix_time: int | None = Query(default=None),
    to_unix_time: int | None = Query(default=None),
    top_value: float | None = Query(default=None),
    btm_value: float | None = Query(default=None),
) -> Collection[TransactionOut]:
    account = await resolve_account(account_id)
    goods = await get_goods(
        account_id=account.id,
        occurred_on_from=(
            unix_to_utc_date(from_unix_time) if from_unix_time is not None else None
        ),
        occurred_on_to=(
            unix_to_utc_date(to_unix_time) if to_unix_time is not None else None
        ),
        top_value=top_value,
        btm_value=btm_value,
    )
    return collection([transaction_out(good) for good in goods])


@router.post("", operation_id="create_transaction", status_code=201)
async def create_transaction(body: TransactionCreate) -> TransactionOut:
    account = await resolve_account(body.account_id)
    occurred_on = (
        unix_to_utc_date(body.occurred_unix_time)
        if body.occurred_unix_time is not None
        else utc_today()
    )
    good = await create_good(
        name=body.name,
        value=body.value,
        currency_id=body.currency_id,
        account_id=require_id(account.id),
        occurred_on=occurred_on,
        category_id=body.category_id,
    )
    return transaction_out(await get_good(require_id(good.id)))


@router.get("/{transaction_id}", operation_id="get_transaction")
async def get_transaction(transaction_id: int) -> TransactionOut:
    return transaction_out(await get_good(transaction_id))


@router.patch("/{transaction_id}", operation_id="update_transaction")
async def update_transaction(
    transaction_id: int, body: TransactionPatch
) -> TransactionOut:
    if body.name is not None:
        await update_good_name(transaction_id, body.name)
    if body.value is not None:
        await update_good_value(transaction_id, body.value)
    if body.currency_id is not None:
        await update_good_currency(transaction_id, body.currency_id)
    if body.occurred_unix_time is not None:
        await update_good_occurred_on(
            transaction_id, unix_to_utc_date(body.occurred_unix_time)
        )
    if body.category_id is not None:
        await update_good_category(transaction_id, body.category_id)
    return transaction_out(await get_good(transaction_id))


@router.delete("/{transaction_id}", operation_id="delete_transaction", status_code=204)
async def delete_transaction(transaction_id: int) -> Response:
    await delete_good(transaction_id)
    return Response(status_code=204)
