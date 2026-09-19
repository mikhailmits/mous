from mous.db.models import Currency
from mous.db.utils.errors import LastDefaultError


async def get_currency(currency_id: int) -> Currency:
    return await Currency.objects.get(id=currency_id)


async def get_currencies() -> list[Currency]:
    return await Currency.objects.all()


async def get_currency_by_symbol(symbol: str) -> Currency:
    return await Currency.objects.get(symbol=symbol)


async def create_currency(
    symbol: str,
    name: str,
    is_default: bool = False,
) -> Currency:
    if await Currency.objects.count() == 0:
        is_default = True
    created = await Currency.objects.create(
        symbol=symbol,
        name=name,
        is_default=is_default,
    )
    if created.is_default and created.id is not None:
        await _promote_default(created.id)
    return created


async def update_currency_symbol(currency_id: int, symbol: str) -> Currency:
    currency = await get_currency(currency_id)
    currency.symbol = symbol
    await currency.save(update_fields=["symbol"])
    return currency


async def update_currency_name(currency_id: int, name: str) -> Currency:
    currency = await get_currency(currency_id)
    currency.name = name
    await currency.save(update_fields=["name"])
    return currency


async def update_currency_default(currency_id: int, is_default: bool) -> Currency:
    currency = await get_currency(currency_id)
    if is_default:
        if not currency.is_default:
            currency.is_default = True
            await currency.save(update_fields=["is_default"])
        await _promote_default(currency_id)
        return await get_currency(currency_id)
    if currency.is_default:
        if await Currency.objects.filter(is_default=True).count() <= 1:
            raise LastDefaultError("cannot clear the last remaining default currency")
    currency.is_default = is_default
    await currency.save(update_fields=["is_default"])
    return currency


async def delete_currency(currency_id: int) -> None:
    currency = await get_currency(currency_id)
    if currency.is_default:
        raise LastDefaultError("cannot delete the default currency")
    await currency.delete()


async def _promote_default(currency_id: int) -> None:
    for currency in await Currency.objects.filter(is_default=True).all():
        if currency.id == currency_id:
            continue
        currency.is_default = False
        await currency.save(update_fields=["is_default"])
