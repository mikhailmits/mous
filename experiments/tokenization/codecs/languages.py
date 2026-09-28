"""(c) Replace English labels with other languages / scripts."""

from __future__ import annotations

from experiments.tokenization.bundle import Bundle, Transaction
from experiments.tokenization.codecs.base import fn_codec

CAT_ZH = {
    "rent": "房租",
    "groceries": "食品",
    "restaurants": "餐饮",
    "transport": "交通",
    "salary": "工资",
    "freelance": "自由职业",
    "subscriptions": "订阅",
    "entertainment": "娱乐",
    "healthcare": "医疗",
    "utilities": "水电",
    "shopping": "购物",
    "travel": "旅行",
    "coffee": "咖啡",
    "insurance": "保险",
    "education": "教育",
    "gifts": "礼物",
}
CAT_DE = {
    "rent": "Miete",
    "groceries": "Lebensmittel",
    "restaurants": "Restaurant",
    "transport": "Transport",
    "salary": "Gehalt",
    "freelance": "Freelance",
    "subscriptions": "Abo",
    "entertainment": "Freizeit",
    "healthcare": "Gesundheit",
    "utilities": "Nebenkosten",
    "shopping": "Einkauf",
    "travel": "Reise",
    "coffee": "Kaffee",
    "insurance": "Versicherung",
    "education": "Bildung",
    "gifts": "Geschenk",
}
CAT_RU = {
    "rent": "аренда",
    "groceries": "продукты",
    "restaurants": "ресторан",
    "transport": "транспорт",
    "salary": "зарплата",
    "freelance": "фриланс",
    "subscriptions": "подписка",
    "entertainment": "развлечения",
    "healthcare": "здоровье",
    "utilities": "коммуналка",
    "shopping": "покупки",
    "travel": "поездка",
    "coffee": "кофе",
    "insurance": "страховка",
    "education": "учеба",
    "gifts": "подарок",
}
CAT_JA = {
    "rent": "家賃",
    "groceries": "食料品",
    "restaurants": "外食",
    "transport": "交通",
    "salary": "給料",
    "freelance": "業務委託",
    "subscriptions": "定期課金",
    "entertainment": "娯楽",
    "healthcare": "医療",
    "utilities": "光熱費",
    "shopping": "買い物",
    "travel": "旅行",
    "coffee": "コーヒー",
    "insurance": "保険",
    "education": "教育",
    "gifts": "贈り物",
}
CAT_AR = {
    "rent": "إيجار",
    "groceries": "بقالة",
    "restaurants": "مطعم",
    "transport": "مواصلات",
    "salary": "راتب",
    "freelance": "عمل حر",
    "subscriptions": "اشتراك",
    "entertainment": "ترفيه",
    "healthcare": "صحة",
    "utilities": "فواتير",
    "shopping": "تسوق",
    "travel": "سفر",
    "coffee": "قهوة",
    "insurance": "تأمين",
    "education": "تعليم",
    "gifts": "هدية",
}
CAT_EMOJI = {
    "rent": "🏠",
    "groceries": "🥬",
    "restaurants": "🍽️",
    "transport": "🚇",
    "salary": "💰",
    "freelance": "🧑‍💻",
    "subscriptions": "🔁",
    "entertainment": "🎬",
    "healthcare": "💊",
    "utilities": "💡",
    "shopping": "🛍️",
    "travel": "✈️",
    "coffee": "☕",
    "insurance": "🛡️",
    "education": "📚",
    "gifts": "🎁",
}

NAME_ZH = {
    "lidl": "利德尔",
    "rewe": "雷沃",
    "aldi": "阿尔迪",
    "weekly groceries": "周采购",
    "apartment rent": "房租",
    "monthly salary": "月薪",
    "netflix": "奈飞",
    "gym": "健身房",
    "espresso": "浓缩咖啡",
    "flat white": "白咖啡",
}


def _map_tx(tx: Transaction, cats: dict[str, str], names: dict[str, str] | None = None) -> str:
    cat = cats.get(tx.category or "", tx.category or "-")
    name = (names or {}).get(tx.name, tx.name)
    return f"{tx.occurred_on} {name} {tx.value} {tx.currency} {tx.account} {cat}"


def _render(bundle: Bundle, cats: dict[str, str], names: dict[str, str] | None = None) -> str:
    return "\n".join(_map_tx(tx, cats, names) for tx in bundle.transactions)


@fn_codec("lang_zh", "languages", "Chinese category/merchant labels. CJK is often cheaper on o200k.")
def lang_zh(bundle: Bundle) -> str:
    return _render(bundle, CAT_ZH, NAME_ZH)


@fn_codec("lang_de", "languages", "German labels. Compound nouns can be 1-2 tokens or many.")
def lang_de(bundle: Bundle) -> str:
    return _render(bundle, CAT_DE)


@fn_codec("lang_ru", "languages", "Cyrillic labels.")
def lang_ru(bundle: Bundle) -> str:
    return _render(bundle, CAT_RU)


@fn_codec("lang_ja", "languages", "Japanese labels.")
def lang_ja(bundle: Bundle) -> str:
    return _render(bundle, CAT_JA)


@fn_codec("lang_ar", "languages", "Arabic labels.")
def lang_ar(bundle: Bundle) -> str:
    return _render(bundle, CAT_AR)


@fn_codec("lang_emoji", "languages", "Emoji standing in for categories.")
def lang_emoji(bundle: Bundle) -> str:
    return _render(bundle, CAT_EMOJI)
