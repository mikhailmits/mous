from mous.db.models import GoodCategory


async def get_category(category_id: int) -> GoodCategory:
    return await GoodCategory.objects.get(id=category_id)


async def get_category_by_name(name: str) -> GoodCategory:
    return await GoodCategory.objects.get(name=name)


async def get_categories() -> list[GoodCategory]:
    return await GoodCategory.objects.order_by("name").all()


async def create_category(name: str) -> GoodCategory:
    return await GoodCategory.objects.create(name=name)


async def update_category_name(category_id: int, name: str) -> GoodCategory:
    category = await get_category(category_id)
    category.name = name
    await category.save(update_fields=["name"])
    return category


async def delete_category(category_id: int) -> None:
    category = await get_category(category_id)
    await category.delete()
