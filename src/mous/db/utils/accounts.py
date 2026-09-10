from mous.db.models import Account
from mous.db.utils.errors import LastAccountError


async def get_account(account_id: int) -> Account:
    return await Account.objects.get(id=account_id)


async def get_account_by_name(name: str) -> Account:
    return await Account.objects.get(name=name)


async def get_accounts() -> list[Account]:
    return await Account.objects.all()


async def create_account(name: str = "main") -> Account:
    return await Account.objects.create(name=name)


async def update_account_name(account_id: int, name: str) -> Account:
    account = await get_account(account_id)
    account.name = name
    await account.save(update_fields=["name"])
    return account


async def delete_account(account_id: int) -> None:
    if await Account.objects.count() <= 1:
        raise LastAccountError("cannot delete the last remaining account")
    account = await get_account(account_id)
    await account.delete()
