from fastapi import APIRouter, Query, Response

from mous.api.deps import resolve_account
from mous.api.schemas import (
    Collection,
    SubscriptionCreate,
    SubscriptionOut,
    SubscriptionPatch,
    collection,
    require_id,
    subscription_out,
)
from mous.api.time import unix_to_utc_date, utc_today
from mous.db.models import RecurringGood
from mous.db.utils import (
    create_good,
    create_recurring_good,
    delete_recurring_good,
    get_good,
    get_goods,
    get_recurring_good,
    get_recurring_goods,
    update_good_cron_stamp,
)

router = APIRouter(prefix="/subscriptions", tags=["subscriptions"])


async def _subscription_out(item: RecurringGood) -> SubscriptionOut:
    good = item.good
    if good is None:
        good = await get_good(require_id(item.good_id))
    return subscription_out(item, good)


@router.get("", operation_id="list_subscriptions")
async def list_subscriptions(
    account_id: int | None = Query(default=None),
    good_id: int | None = Query(default=None),
) -> Collection[SubscriptionOut]:
    items = await get_recurring_goods(good_id=good_id)
    if account_id is not None:
        account_goods = await get_goods(account_id=account_id)
        allowed = {good.id for good in account_goods}
        items = [item for item in items if item.good_id in allowed]
    return collection([await _subscription_out(item) for item in items])


@router.post("", operation_id="create_subscription", status_code=201)
async def create_subscription(body: SubscriptionCreate) -> SubscriptionOut:
    if body.good_id is not None:
        good_id = body.good_id
    else:
        assert (
            body.name is not None
            and body.value is not None
            and body.currency_id is not None
        )
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
        )
        good_id = require_id(good.id)
    item = await create_recurring_good(good_id=good_id, cron_stamp=body.cron_stamp)
    return await _subscription_out(item)


@router.get("/{subscription_id}", operation_id="get_subscription")
async def get_subscription(subscription_id: int) -> SubscriptionOut:
    return await _subscription_out(await get_recurring_good(subscription_id))


@router.patch("/{subscription_id}", operation_id="update_subscription")
async def update_subscription(
    subscription_id: int, body: SubscriptionPatch
) -> SubscriptionOut:
    if body.cron_stamp is not None:
        item = await update_good_cron_stamp(subscription_id, body.cron_stamp)
    else:
        item = await get_recurring_good(subscription_id)
    return await _subscription_out(item)


@router.delete("/{subscription_id}", operation_id="delete_subscription", status_code=204)
async def delete_subscription(subscription_id: int) -> Response:
    await delete_recurring_good(subscription_id)
    return Response(status_code=204)
