from fastapi import APIRouter, Response

from mous.api.schemas import (
    CategoryCreate,
    CategoryOut,
    CategoryPatch,
    Collection,
    category_out,
    collection,
)
from mous.db.utils import (
    create_category,
    delete_category,
    get_categories,
    get_category,
    get_category_by_name,
    update_category_name,
)
from oxyde.exceptions import NotFoundError

router = APIRouter(prefix="/categories", tags=["categories"])


async def _get_by_id_or_name(id_or_name: str):
    if id_or_name.isdigit():
        try:
            return await get_category(int(id_or_name))
        except NotFoundError:
            return await get_category_by_name(id_or_name)
    return await get_category_by_name(id_or_name)


@router.get("", operation_id="list_categories")
async def list_categories() -> Collection[CategoryOut]:
    categories = await get_categories()
    return collection([category_out(category) for category in categories])


@router.post("", operation_id="create_category", status_code=201)
async def create_category_endpoint(body: CategoryCreate) -> CategoryOut:
    return category_out(await create_category(name=body.name))


@router.get("/{id_or_name}", operation_id="get_category")
async def get_category_endpoint(id_or_name: str) -> CategoryOut:
    return category_out(await _get_by_id_or_name(id_or_name))


@router.patch("/{category_id}", operation_id="update_category")
async def update_category_endpoint(
    category_id: int, body: CategoryPatch
) -> CategoryOut:
    if body.name is not None:
        await update_category_name(category_id, body.name)
    return category_out(await get_category(category_id))


@router.delete("/{category_id}", operation_id="delete_category", status_code=204)
async def delete_category_endpoint(category_id: int) -> Response:
    await delete_category(category_id)
    return Response(status_code=204)
