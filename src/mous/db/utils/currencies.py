from mous.db.models import Currency


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
    if is_default:
        await _clear_default_flags()
    elif await Currency.objects.count() == 0:
        is_default = True
    return await Currency.objects.create(
        symbol=symbol,
        name=name,
        is_default=is_default,
    )


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
        await _clear_default_flags()
    currency.is_default = is_default
    await currency.save(update_fields=["is_default"])
    return currency


async def delete_currency(currency_id: int) -> None:
    currency = await get_currency(currency_id)
    await currency.delete()


async def _clear_default_flags() -> None:
    for currency in await Currency.objects.filter(is_default=True).all():
        currency.is_default = False
        await currency.save(update_fields=["is_default"])
