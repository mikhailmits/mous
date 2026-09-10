from mous.db.models import RecurringGood


async def get_recurring_good(recurring_good_id: int) -> RecurringGood:
    return await RecurringGood.objects.get(id=recurring_good_id)


async def get_recurring_goods(good_id: int | None = None) -> list[RecurringGood]:
    query = RecurringGood.objects
    if good_id is not None:
        query = query.filter(good_id=good_id)
    return await query.all()


async def create_recurring_good(good_id: int, cron_stamp: str) -> RecurringGood:
    return await RecurringGood.objects.create(good_id=good_id, cron_stamp=cron_stamp)


async def update_good_cron_stamp(
    recurring_good_id: int,
    cron_stamp: str,
) -> RecurringGood:
    recurring_good = await get_recurring_good(recurring_good_id)
    recurring_good.cron_stamp = cron_stamp
    await recurring_good.save(update_fields=["cron_stamp"])
    return recurring_good


async def delete_recurring_good(recurring_good_id: int) -> None:
    recurring_good = await get_recurring_good(recurring_good_id)
    await recurring_good.delete()
