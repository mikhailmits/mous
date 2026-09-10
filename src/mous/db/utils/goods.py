from datetime import date

from mous.db.models import Good


async def get_good(good_id: int) -> Good:
    return await Good.objects.get(id=good_id)


async def get_goods(
    account_id: int | None = None,
    currency_id: int | None = None,
    occurred_on_from: date | None = None,
    occurred_on_to: date | None = None,
    top_value: float | None = None,
    btm_value: float | None = None,
) -> list[Good]:
    query = Good.objects
    if account_id is not None:
        query = query.filter(account_id=account_id)
    if currency_id is not None:
        query = query.filter(currency_id=currency_id)
    if occurred_on_from is not None:
        query = query.filter(occurred_on__gte=occurred_on_from)
    if occurred_on_to is not None:
        query = query.filter(occurred_on__lte=occurred_on_to)
    if top_value is not None:
        query = query.filter(value__lte=top_value)
    if btm_value is not None:
        query = query.filter(value__gte=btm_value)
    return await query.order_by("-value").all()


async def create_good(
    name: str,
    value: float,
    currency_id: int,
    account_id: int,
    occurred_on: date | None = None,
    category_id: int | None = None,
) -> Good:
    """Persist a signed transaction (``value > 0`` income, ``value < 0`` expense)."""
    if occurred_on is None:
        return await Good.objects.create(
            name=name,
            value=value,
            currency_id=currency_id,
            account_id=account_id,
            category_id=category_id,
        )
    return await Good.objects.create(
        name=name,
        value=value,
        currency_id=currency_id,
        account_id=account_id,
        occurred_on=occurred_on,
        category_id=category_id,
    )


async def update_good_name(good_id: int, name: str) -> Good:
    good = await get_good(good_id)
    good.name = name
    await good.save(update_fields=["name"])
    return good


async def update_good_value(good_id: int, value: float) -> Good:
    good = await get_good(good_id)
    good.value = value
    await good.save(update_fields=["value"])
    return good


async def update_good_currency(good_id: int, currency_id: int) -> Good:
    good = await get_good(good_id)
    good.currency_id = currency_id
    await good.save(update_fields=["currency_id"])
    return good


async def update_good_occurred_on(good_id: int, occurred_on: date) -> Good:
    good = await get_good(good_id)
    good.occurred_on = occurred_on
    await good.save(update_fields=["occurred_on"])
    return good


async def update_good_category(good_id: int, category_id: int | None) -> Good:
    good = await get_good(good_id)
    good.category_id = category_id
    await good.save(update_fields=["category_id"])
    return good


async def delete_good(good_id: int) -> None:
    good = await get_good(good_id)
    await good.delete()
