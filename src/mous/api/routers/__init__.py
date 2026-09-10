from mous.api.routers.accounts import router as accounts_router
from mous.api.routers.categories import router as categories_router
from mous.api.routers.currencies import router as currencies_router
from mous.api.routers.subscriptions import router as subscriptions_router
from mous.api.routers.transactions import router as transactions_router

__all__ = [
    "accounts_router",
    "categories_router",
    "currencies_router",
    "subscriptions_router",
    "transactions_router",
]
