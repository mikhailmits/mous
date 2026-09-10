from fastapi import APIRouter, Response

from mous.api.schemas import (
    Collection,
    CurrencyCreate,
    CurrencyOut,
    CurrencyPatch,
    collection,
    currency_out,
)
from mous.db.utils import (
    create_currency,
    delete_currency,
    get_currencies,
    get_currency,
    get_currency_by_symbol,
    update_currency_default,
    update_currency_name,
    update_currency_symbol,
)
from oxyde.exceptions import NotFoundError

router = APIRouter(prefix="/currencies", tags=["currencies"])


async def _get_by_id_or_symbol(id_or_symbol: str):
    if id_or_symbol.isdigit():
        try:
            return await get_currency(int(id_or_symbol))
        except NotFoundError:
            return await get_currency_by_symbol(id_or_symbol)
    return await get_currency_by_symbol(id_or_symbol)


@router.get("", operation_id="list_currencies")
async def list_currencies() -> Collection[CurrencyOut]:
    currencies = await get_currencies()
    return collection([currency_out(currency) for currency in currencies])


@router.post("", operation_id="create_currency", status_code=201)
async def create_currency_endpoint(body: CurrencyCreate) -> CurrencyOut:
    currency = await create_currency(
        symbol=body.symbol,
        name=body.name,
        is_default=body.is_default,
    )
    return currency_out(currency)


@router.get("/{id_or_symbol}", operation_id="get_currency")
async def get_currency_endpoint(id_or_symbol: str) -> CurrencyOut:
    return currency_out(await _get_by_id_or_symbol(id_or_symbol))


@router.patch("/{currency_id}", operation_id="update_currency")
async def update_currency_endpoint(
    currency_id: int, body: CurrencyPatch
) -> CurrencyOut:
    if body.symbol is not None:
        await update_currency_symbol(currency_id, body.symbol)
    if body.name is not None:
        await update_currency_name(currency_id, body.name)
    if body.is_default is not None:
        await update_currency_default(currency_id, body.is_default)
    return currency_out(await get_currency(currency_id))


@router.delete("/{currency_id}", operation_id="delete_currency", status_code=204)
async def delete_currency_endpoint(currency_id: int) -> Response:
    await delete_currency(currency_id)
    return Response(status_code=204)
