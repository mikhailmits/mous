"""Full-ledger multilingual codecs (languages specialist).

Category-only translation loses because merchant names stay English. These
codecs translate or re-script every merchant, category, and account, and they
pack amounts/dates where that is cheaper on o200k_base.

Every compact codec embeds an English gold legend so a model can map labels
back to rent/shopping/… without outside knowledge.
"""

from __future__ import annotations

from collections import defaultdict
from datetime import date

from experiments.tokenization.bundle import Bundle, Transaction
from experiments.tokenization.codecs.base import fn_codec
from experiments.tokenization.codecs.languages import CAT_AR, CAT_DE, CAT_JA, CAT_RU, CAT_ZH

EPOCH = date(2025, 1, 1)

# ---------------------------------------------------------------------------
# Full dictionaries: every merchant + category + account
# ---------------------------------------------------------------------------

ACC_DE = {"main": "Haupt", "savings": "Spar", "credit": "Kredit"}
ACC_RU = {"main": "основной", "savings": "накопления", "credit": "кредит"}
ACC_ZH = {"main": "主户", "savings": "储蓄", "credit": "信用"}
ACC_JA = {"main": "本座", "savings": "貯金", "credit": "カード"}
ACC_KO = {"main": "주계", "savings": "저축", "credit": "신용"}
ACC_PY = {"main": "zhu", "savings": "xu", "credit": "dai"}

NAME_DE = {
    "airbnb weekend": "Airbnb",
    "aldi": "Aldi",
    "amazon order": "Amazon",
    "apartment rent": "Wohnungsmiete",
    "bakery coffee": "Baeckerei",
    "bio company": "Biofirma",
    "birthday gift": "Geburtstagsgeschenk",
    "bolt ride": "Bolt",
    "books": "Buecher",
    "burger joint": "Burgerladen",
    "bvg ticket": "BVG",
    "cinema": "Kino",
    "concert": "Konzert",
    "consulting fee": "Beratungshonorar",
    "dentist": "Zahnarzt",
    "design invoice": "Designrechnung",
    "electricity": "Strom",
    "espresso": "Espresso",
    "flat white": "FlatWhite",
    "flixbus": "Flixbus",
    "flowers": "Blumen",
    "fuel": "Tanken",
    "github pro": "GitHub",
    "gp visit": "Hausarzt",
    "gym": "Fitnessstudio",
    "health insurance": "Krankenkasse",
    "icloud+": "iCloud",
    "ikea": "Ikea",
    "internet": "Internet",
    "language class": "Sprachkurs",
    "lidl": "Lidl",
    "lufthansa": "Lufthansa",
    "media markt": "MediaMarkt",
    "monthly salary": "Monatsgehalt",
    "museum": "Museum",
    "netflix": "Netflix",
    "online course": "Onlinekurs",
    "pharmacy": "Apotheke",
    "ramen bar": "Ramenbar",
    "rewe": "Rewe",
    "spotify": "Spotify",
    "steam game": "SteamSpiel",
    "sushi place": "Sushi",
    "trattoria roma": "Trattoria",
    "uber ride": "Uber",
    "water bill": "Wasserrechnung",
    "wedding gift": "Hochzeitsgeschenk",
    "weekend gig": "Nebenjob",
    "weekly groceries": "Wocheneinkauf",
    "zara": "Zara",
}

NAME_RU = {
    "airbnb weekend": "Airbnb",
    "aldi": "Альди",
    "amazon order": "Амазон",
    "apartment rent": "аренда жилья",
    "bakery coffee": "пекарня",
    "bio company": "биокомпания",
    "birthday gift": "день рождения",
    "bolt ride": "Болт",
    "books": "книги",
    "burger joint": "бургерная",
    "bvg ticket": "БВГ",
    "cinema": "кино",
    "concert": "концерт",
    "consulting fee": "консалтинг",
    "dentist": "стоматолог",
    "design invoice": "дизайн счёт",
    "electricity": "электричество",
    "espresso": "эспрессо",
    "flat white": "флэт уайт",
    "flixbus": "Фликсбус",
    "flowers": "цветы",
    "fuel": "бензин",
    "github pro": "Гитхаб",
    "gp visit": "терапевт",
    "gym": "зал",
    "health insurance": "медстрах",
    "icloud+": "айклауд",
    "ikea": "Икеа",
    "internet": "интернет",
    "language class": "языки",
    "lidl": "Лидл",
    "lufthansa": "Люфтганза",
    "media markt": "Медиамаркт",
    "monthly salary": "зарплата",
    "museum": "музей",
    "netflix": "Нетфликс",
    "online course": "онлайнкурс",
    "pharmacy": "аптека",
    "ramen bar": "рамэн",
    "rewe": "Реве",
    "spotify": "Спотифай",
    "steam game": "Стим",
    "sushi place": "суши",
    "trattoria roma": "траттория",
    "uber ride": "Убер",
    "water bill": "вода",
    "wedding gift": "свадьба",
    "weekend gig": "подработка",
    "weekly groceries": "закупка",
    "zara": "Зара",
}

NAME_ZH = {
    "airbnb weekend": "民宿",
    "aldi": "奥乐",
    "amazon order": "亚马逊",
    "apartment rent": "房租",
    "bakery coffee": "面包咖啡",
    "bio company": "生科",
    "birthday gift": "生日礼",
    "bolt ride": "闪电出行",
    "books": "书籍",
    "burger joint": "汉堡店",
    "bvg ticket": "公交票",
    "cinema": "电影",
    "concert": "演出",
    "consulting fee": "咨询费",
    "dentist": "牙医",
    "design invoice": "设计费",
    "electricity": "电费",
    "espresso": "浓缩",
    "flat white": "白咖",
    "flixbus": "长途巴",
    "flowers": "鲜花",
    "fuel": "加油",
    "github pro": "代码仓",
    "gp visit": "问诊",
    "gym": "健身",
    "health insurance": "医保",
    "icloud+": "云盘",
    "ikea": "宜家",
    "internet": "宽带",
    "language class": "语言课",
    "lidl": "利德",
    "lufthansa": "汉莎",
    "media markt": "电超",
    "monthly salary": "月薪",
    "museum": "博物馆",
    "netflix": "奈飞",
    "online course": "网课",
    "pharmacy": "药店",
    "ramen bar": "拉面",
    "rewe": "雷沃",
    "spotify": "声破",
    "steam game": "蒸汽游戏",
    "sushi place": "寿司",
    "trattoria roma": "意餐",
    "uber ride": "优步",
    "water bill": "水费",
    "wedding gift": "婚礼",
    "weekend gig": "兼职",
    "weekly groceries": "周菜",
    "zara": "扎拉",
}

NAME_JA = {
    "airbnb weekend": "民泊",
    "aldi": "アルディ",
    "amazon order": "アマゾン",
    "apartment rent": "家賃",
    "bakery coffee": "パン屋",
    "bio company": "バイオ",
    "birthday gift": "誕生日",
    "bolt ride": "ボルト",
    "books": "本",
    "burger joint": "バーガー",
    "bvg ticket": "交通券",
    "cinema": "映画",
    "concert": "ライブ",
    "consulting fee": "顧問料",
    "dentist": "歯科",
    "design invoice": "デザイン料",
    "electricity": "電気代",
    "espresso": "エスプレッソ",
    "flat white": "フラット",
    "flixbus": "長距離バス",
    "flowers": "花",
    "fuel": "給油",
    "github pro": "ギットハブ",
    "gp visit": "診療",
    "gym": "ジム",
    "health insurance": "健康保険",
    "icloud+": "アイクラウド",
    "ikea": "イケア",
    "internet": "回線",
    "language class": "語学",
    "lidl": "リドル",
    "lufthansa": "ルフトハンザ",
    "media markt": "家電店",
    "monthly salary": "給料",
    "museum": "博物館",
    "netflix": "ネットフリックス",
    "online course": "講座",
    "pharmacy": "薬局",
    "ramen bar": "ラーメン",
    "rewe": "レーヴェ",
    "spotify": "スポティファイ",
    "steam game": "スチーム",
    "sushi place": "寿司屋",
    "trattoria roma": "食堂",
    "uber ride": "ウーバー",
    "water bill": "水道",
    "wedding gift": "結婚祝",
    "weekend gig": "副業",
    "weekly groceries": "週食",
    "zara": "ザラ",
}

NAME_KO = {
    "airbnb weekend": "민박",
    "aldi": "알디",
    "amazon order": "아마존",
    "apartment rent": "월세",
    "bakery coffee": "빵집",
    "bio company": "바이오",
    "birthday gift": "생일선물",
    "bolt ride": "볼트",
    "books": "책",
    "burger joint": "버거",
    "bvg ticket": "교통권",
    "cinema": "영화",
    "concert": "공연",
    "consulting fee": "컨설팅",
    "dentist": "치과",
    "design invoice": "디자인비",
    "electricity": "전기요금",
    "espresso": "에스프레소",
    "flat white": "플랫화이트",
    "flixbus": "장거리버스",
    "flowers": "꽃",
    "fuel": "주유",
    "github pro": "깃허브",
    "gp visit": "진료",
    "gym": "헬스",
    "health insurance": "건강보험",
    "icloud+": "아이클라우드",
    "ikea": "이케아",
    "internet": "인터넷",
    "language class": "어학",
    "lidl": "리들",
    "lufthansa": "루프트한자",
    "media markt": "전자상",
    "monthly salary": "월급",
    "museum": "박물관",
    "netflix": "넷플릭스",
    "online course": "강의",
    "pharmacy": "약국",
    "ramen bar": "라면",
    "rewe": "레베",
    "spotify": "스포티파이",
    "steam game": "스팀",
    "sushi place": "초밥",
    "trattoria roma": "식당",
    "uber ride": "우버",
    "water bill": "수도요금",
    "wedding gift": "결혼식",
    "weekend gig": "부업",
    "weekly groceries": "주간장",
    "zara": "자라",
}

CAT_KO = {
    "rent": "월세",
    "groceries": "식료",
    "restaurants": "외식",
    "transport": "교통",
    "salary": "급여",
    "freelance": "외주",
    "subscriptions": "구독",
    "entertainment": "여가",
    "healthcare": "의료",
    "utilities": "공과",
    "shopping": "쇼핑",
    "travel": "여행",
    "coffee": "커피",
    "insurance": "보험",
    "education": "교육",
    "gifts": "선물",
}

CAT_PY = {
    "rent": "zu",
    "groceries": "shi",
    "restaurants": "can",
    "transport": "che",
    "salary": "xin",
    "freelance": "jian",
    "subscriptions": "ding",
    "entertainment": "yu",
    "healthcare": "yi",
    "utilities": "dian",
    "shopping": "gou",
    "travel": "lv",
    "coffee": "kafei",
    "insurance": "bao",
    "education": "jiao",
    "gifts": "li",
}

NAME_PY = {
    "airbnb weekend": "minshu",
    "aldi": "aodi",
    "amazon order": "yamaxun",
    "apartment rent": "fangzu",
    "bakery coffee": "mianbao",
    "bio company": "shengke",
    "birthday gift": "shengri",
    "bolt ride": "shandian",
    "books": "shuji",
    "burger joint": "hanbao",
    "bvg ticket": "gongjiao",
    "cinema": "dianying",
    "concert": "yanchu",
    "consulting fee": "zixun",
    "dentist": "yayi",
    "design invoice": "sheji",
    "electricity": "dianfei",
    "espresso": "nongsuo",
    "flat white": "baika",
    "flixbus": "changba",
    "flowers": "xianhua",
    "fuel": "jiayou",
    "github pro": "dacang",
    "gp visit": "wenzhen",
    "gym": "jianshen",
    "health insurance": "yibao",
    "icloud+": "yunpan",
    "ikea": "yijia",
    "internet": "kuandai",
    "language class": "yuyan",
    "lidl": "lide",
    "lufthansa": "hansha",
    "media markt": "dianchao",
    "monthly salary": "yuexin",
    "museum": "bowuguan",
    "netflix": "naifei",
    "online course": "wangka",
    "pharmacy": "yaodian",
    "ramen bar": "lamian",
    "rewe": "leiwo",
    "spotify": "shengpo",
    "steam game": "zhengqi",
    "sushi place": "shousi",
    "trattoria roma": "yican",
    "uber ride": "youbu",
    "water bill": "shuifei",
    "wedding gift": "hunli",
    "weekend gig": "jianzhi",
    "weekly groceries": "zhoucai",
    "zara": "zhala",
}

# One mnemonic CJK char per label (o200k: these are 1 token each).
# Names and categories are separate fields so a glyph may be reused across fields.
CAT_IDEO = {
    "rent": "租",
    "groceries": "菜",
    "restaurants": "餐",
    "transport": "车",
    "salary": "薪",
    "freelance": "兼",
    "subscriptions": "订",
    "entertainment": "娱",
    "healthcare": "医",
    "utilities": "电",
    "shopping": "购",
    "travel": "旅",
    "coffee": "咖",
    "insurance": "保",
    "education": "教",
    "gifts": "礼",
}

NAME_IDEO = {
    "airbnb weekend": "宿",
    "aldi": "奥",
    "amazon order": "亚",
    "apartment rent": "房",
    "bakery coffee": "包",
    "bio company": "生",
    "birthday gift": "寿",
    "books": "书",
    "bolt ride": "闪",
    "burger joint": "堡",
    "bvg ticket": "轨",
    "cinema": "影",
    "concert": "演",
    "consulting fee": "顾",
    "dentist": "牙",
    "design invoice": "设",
    "electricity": "力",
    "espresso": "浓",
    "flat white": "白",
    "flixbus": "巴",
    "flowers": "花",
    "fuel": "油",
    "github pro": "码",
    "gp visit": "诊",
    "gym": "健",
    "health insurance": "险",
    "icloud+": "云",
    "ikea": "宜",
    "internet": "网",
    "language class": "语",
    "lidl": "利",
    "lufthansa": "航",
    "media markt": "媒",
    "monthly salary": "工",
    "museum": "博",
    "netflix": "奈",
    "online course": "课",
    "pharmacy": "药",
    "ramen bar": "面",
    "rewe": "雷",
    "spotify": "声",
    "steam game": "游",
    "sushi place": "鲜",
    "trattoria roma": "意",
    "uber ride": "优",
    "water bill": "水",
    "wedding gift": "婚",
    "weekend gig": "零",
    "weekly groceries": "周",
    "zara": "扎",
}

ACC_IDEO = {"main": "主", "savings": "储", "credit": "贷"}

# One Hangul syllable per label (common syllables; 1 token on o200k).
CAT_KO_IDEO = {
    "rent": "월",
    "groceries": "식",
    "restaurants": "외",
    "transport": "차",
    "salary": "급",
    "freelance": "겸",
    "subscriptions": "구",
    "entertainment": "락",
    "healthcare": "의",
    "utilities": "공",
    "shopping": "쇼",
    "travel": "여",
    "coffee": "커",
    "insurance": "보",
    "education": "육",
    "gifts": "선",
}

NAME_KO_IDEO = {
    "airbnb weekend": "숙",
    "aldi": "알",
    "amazon order": "아",
    "apartment rent": "셋",
    "bakery coffee": "빵",
    "bio company": "생",
    "birthday gift": "생",  # field-local; disambiguated in legend as 생일
    "books": "책",
    "bolt ride": "볼",
    "burger joint": "버",
    "bvg ticket": "티",
    "cinema": "영",
    "concert": "공",
    "consulting fee": "컨",
    "dentist": "치",
    "design invoice": "디",
    "electricity": "전",
    "espresso": "에",
    "flat white": "플",
    "flixbus": "플",  # will uniquify below
    "flowers": "꽃",
    "fuel": "기",
    "github pro": "깃",
    "gp visit": "진",
    "gym": "헬",
    "health insurance": "건",
    "icloud+": "클",
    "ikea": "이",
    "internet": "넷",
    "language class": "어",
    "lidl": "리",
    "lufthansa": "루",
    "media markt": "매",
    "monthly salary": "봉",
    "museum": "박",
    "netflix": "넷",
    "online course": "강",
    "pharmacy": "약",
    "ramen bar": "면",
    "rewe": "레",
    "spotify": "스",
    "steam game": "팀",
    "sushi place": "초",
    "trattoria roma": "식",
    "uber ride": "우",
    "water bill": "수",
    "wedding gift": "혼",
    "weekend gig": "부",
    "weekly groceries": "장",
    "zara": "자",
}

# Unique Hangul name glyphs — collisions above are fixed here.
NAME_KO_IDEO = {
    "airbnb weekend": "숙",
    "aldi": "알",
    "amazon order": "아",
    "apartment rent": "셋",
    "bakery coffee": "빵",
    "bio company": "바",
    "birthday gift": "생",
    "books": "책",
    "bolt ride": "볼",
    "burger joint": "버",
    "bvg ticket": "티",
    "cinema": "영",
    "concert": "연",
    "consulting fee": "컨",
    "dentist": "치",
    "design invoice": "디",
    "electricity": "전",
    "espresso": "에",
    "flat white": "흰",
    "flixbus": "플",
    "flowers": "꽃",
    "fuel": "기름",  # 2 chars if 기 collides; prefer 1-char 주
    "github pro": "깃",
    "gp visit": "진",
    "gym": "헬",
    "health insurance": "보",
    "icloud+": "클",
    "ikea": "케",
    "internet": "웹",
    "language class": "어",
    "lidl": "리",
    "lufthansa": "루",
    "media markt": "매",
    "monthly salary": "봉",
    "museum": "박",
    "netflix": "넷",
    "online course": "강",
    "pharmacy": "약",
    "ramen bar": "면",
    "rewe": "레",
    "spotify": "팟",
    "steam game": "팀",
    "sushi place": "초",
    "trattoria roma": "롬",
    "uber ride": "우",
    "water bill": "물",
    "wedding gift": "혼",
    "weekend gig": "잡",
    "weekly groceries": "장",
    "zara": "자",
}
NAME_KO_IDEO["fuel"] = "주"

ACC_KO_IDEO = {"main": "주", "savings": "저", "credit": "카"}
# main 주 collides with fuel 주 — accounts are a different field; OK.
# But 주 as account default is omitted anyway.

# Japanese 1-kanji merchants / cats
CAT_JA_IDEO = {
    "rent": "賃",
    "groceries": "食",
    "restaurants": "飯",
    "transport": "乗",
    "salary": "給",
    "freelance": "委",
    "subscriptions": "定",
    "entertainment": "遊",
    "healthcare": "病",
    "utilities": "光",
    "shopping": "買",
    "travel": "旅",
    "coffee": "珈",
    "insurance": "険",
    "education": "学",
    "gifts": "祝",
}

NAME_JA_IDEO = {
    "airbnb weekend": "泊",
    "aldi": "阿",
    "amazon order": "亜",
    "apartment rent": "屋",
    "bakery coffee": "パン",
    "bio company": "生",
    "birthday gift": "誕",
    "books": "本",
    "bolt ride": "迅",
    "burger joint": "肉",
    "bvg ticket": "券",
    "cinema": "映",
    "concert": "演",
    "consulting fee": "顧",
    "dentist": "歯",
    "design invoice": "設",
    "electricity": "電",
    "espresso": "濃",
    "flat white": "白",
    "flixbus": "バス",
    "flowers": "花",
    "fuel": "油",
    "github pro": "符",
    "gp visit": "診",
    "gym": "体",
    "health insurance": "健",
    "icloud+": "雲",
    "ikea": "家具",
    "internet": "網",
    "language class": "語",
    "lidl": "莉",
    "lufthansa": "空",
    "media markt": "家電",
    "monthly salary": "俸",
    "museum": "博",
    "netflix": "ネ",
    "online course": "講",
    "pharmacy": "薬",
    "ramen bar": "麺",
    "rewe": "蕾",
    "spotify": "音",
    "steam game": "蒸",
    "sushi place": "鮨",
    "trattoria roma": "伊",
    "uber ride": "優",
    "water bill": "水",
    "wedding gift": "婚",
    "weekend gig": "副",
    "weekly groceries": "週",
    "zara": "ザ",
}

# Force 1-char Japanese names (katakana/kanji); multi-char ones get a single kata.
NAME_JA_IDEO["bakery coffee"] = "パ"
NAME_JA_IDEO["flixbus"] = "バ"
NAME_JA_IDEO["ikea"] = "イ"
NAME_JA_IDEO["media markt"] = "媒"
NAME_JA_IDEO["netflix"] = "ネ"
NAME_JA_IDEO["sushi place"] = "寿"
NAME_JA_IDEO["zara"] = "ザ"

ACC_JA_IDEO = {"main": "本", "savings": "貯", "credit": "卡"}

# First 80 Hangul syllables that are 1 token on o200k_base (measured).
HANGUL_80 = (
    "가각간갈감갑값강같개객거건걸검겁것게겠겨격견결겼경계고곡곤골곳공과관광괴교"
    "구국군굴궁권귀규균그극근글금급기긴길김까깔깨꺼께껴꽃꾸꿈끄끌끔끝끼낌나난날남납났내낸낼"
)

CJK_DIGIT_TABLE = str.maketrans("0123456789.-", "零一二三四五六七八九負點")
HANGUL_DIGIT_TABLE = str.maketrans("0123456789.-", "영일이삼사오육칠팔구음쩜")

assert len(NAME_IDEO) == 50, len(NAME_IDEO)
assert len(set(NAME_IDEO.values())) == 50, set(k for k, v in NAME_IDEO.items() if list(NAME_IDEO.values()).count(v) > 1)
assert len(set(CAT_IDEO.values())) == 16
assert len(set(NAME_KO_IDEO.values())) == 50, [v for v in NAME_KO_IDEO.values() if list(NAME_KO_IDEO.values()).count(v) > 1]
assert len(set(CAT_KO_IDEO.values())) == 16
assert len(HANGUL_80) == 80, len(HANGUL_80)


def _cents(value: float) -> int:
    return int(round(value * 100))


def _legend_pairs(title: str, mapping: dict[str, str], reverse: bool = True) -> str:
    """Compact glyph→English legend. reverse=True means mapping is english→glyph."""
    if reverse:
        items = [f"{glyph}={eng}" for eng, glyph in mapping.items()]
    else:
        items = [f"{k}={v}" for k, v in mapping.items()]
    return title + " " + " ".join(items)


def _full_legend(
    *,
    names: dict[str, str],
    cats: dict[str, str],
    accs: dict[str, str],
    extra: str,
) -> str:
    return "\n".join(
        [
            extra,
            _legend_pairs("N", names),
            _legend_pairs("C", cats),
            _legend_pairs("A", accs),
        ]
    )


def _map_line(
    tx: Transaction,
    names: dict[str, str],
    cats: dict[str, str],
    accs: dict[str, str],
    *,
    amount: str | None = None,
) -> str:
    name = names.get(tx.name, tx.name)
    cat = cats.get(tx.category or "", tx.category or "-")
    acc = accs.get(tx.account, tx.account)
    val = amount if amount is not None else f"{tx.value}"
    return f"{tx.occurred_on} {name} {val} {tx.currency} {acc} {cat}"


def _render_mapped(
    bundle: Bundle,
    names: dict[str, str],
    cats: dict[str, str],
    accs: dict[str, str],
    *,
    extra_legend: str,
    amount_fn=None,
) -> str:
    legend = _full_legend(names=names, cats=cats, accs=accs, extra=extra_legend)
    lines = []
    for tx in bundle.transactions:
        amt = amount_fn(tx) if amount_fn else None
        lines.append(_map_line(tx, names, cats, accs, amount=amt))
    return legend + "\n" + "\n".join(lines)


def _flags(tx: Transaction, accs: dict[str, str]) -> str:
    """Omit default eur/main; emit 1-char flags otherwise."""
    bits = ""
    if tx.currency != "eur":
        bits += "$"
    if tx.account != "main":
        bits += accs.get(tx.account, tx.account[0])
    return bits


def _compact_rows(
    bundle: Bundle,
    names: dict[str, str],
    cats: dict[str, str],
    accs: dict[str, str],
    *,
    monthly: bool,
    amount_fn,
) -> str:
    if not monthly:
        rows = []
        for tx in bundle.transactions:
            d = tx.occurred_on.replace("-", "")[2:]
            rows.append(
                f"{d}{names[tx.name]}{amount_fn(tx)}{cats[tx.category or '-']}{_flags(tx, accs)}"
            )
        return "\n".join(rows)

    grouped: dict[str, list[Transaction]] = defaultdict(list)
    for tx in bundle.transactions:
        grouped[tx.occurred_on[:7]].append(tx)
    parts: list[str] = []
    for month, txs in grouped.items():
        parts.append(month[2:].replace("-", ""))  # YYMM, 2 o200k tokens
        for tx in txs:
            dd = tx.occurred_on[8:]
            parts.append(
                f"{dd}{names[tx.name]}{amount_fn(tx)}{cats[tx.category or '-']}{_flags(tx, accs)}"
            )
    return "\n".join(parts)


def _ascii_cents(tx: Transaction) -> str:
    return str(_cents(tx.value))


def _cjk_amount(tx: Transaction) -> str:
    return f"{tx.value:.2f}".translate(CJK_DIGIT_TABLE)


def _hangul_digits_amount(tx: Transaction) -> str:
    return f"{tx.value:.2f}".translate(HANGUL_DIGIT_TABLE)


def _hangul_pack_cents(tx: Transaction) -> str:
    """3 Hangul syllables, base-80, unsigned cents+121390 (covers this corpus)."""
    n = _cents(tx.value) + 121390
    base = 80
    chars = []
    for _ in range(3):
        chars.append(HANGUL_80[n % base])
        n //= base
    if n:
        raise ValueError(f"cents overflow hangul pack: {tx.value}")
    return "".join(reversed(chars))


# ---------------------------------------------------------------------------
# (1) Full natural translations — same line shape as lang_de, but every field
# ---------------------------------------------------------------------------

@fn_codec(
    "lang_de_full",
    "languages",
    "Full German ledger (merchants+cats+accounts) plus English legend.",
)
def lang_de_full(bundle: Bundle) -> str:
    return _render_mapped(
        bundle,
        NAME_DE,
        CAT_DE,
        ACC_DE,
        extra_legend="DE full ledger. Gold English maps below. amounts=float ccy=iso.",
    )


@fn_codec(
    "lang_ru_full",
    "languages",
    "Full Russian ledger (merchants+cats+accounts) plus English legend.",
)
def lang_ru_full(bundle: Bundle) -> str:
    return _render_mapped(
        bundle,
        NAME_RU,
        CAT_RU,
        ACC_RU,
        extra_legend="RU full ledger. Gold English maps below. amounts=float ccy=iso.",
    )


@fn_codec(
    "lang_zh_full",
    "languages",
    "Full Chinese 2-char merchants/cats/accounts. Beats category-only zh because names shrink.",
)
def lang_zh_full(bundle: Bundle) -> str:
    return _render_mapped(
        bundle,
        NAME_ZH,
        CAT_ZH,
        ACC_ZH,
        extra_legend="ZH full ledger. Glyphs are real words; legend maps to English gold.",
    )


@fn_codec(
    "lang_ja_full",
    "languages",
    "Full Japanese merchants/cats/accounts plus English legend.",
)
def lang_ja_full(bundle: Bundle) -> str:
    return _render_mapped(
        bundle,
        NAME_JA,
        CAT_JA,
        ACC_JA,
        extra_legend="JA full ledger. Legend maps to English gold.",
    )


@fn_codec(
    "lang_ko_full",
    "languages",
    "Full Korean merchants/cats/accounts plus English legend.",
)
def lang_ko_full(bundle: Bundle) -> str:
    return _render_mapped(
        bundle,
        NAME_KO,
        CAT_KO,
        ACC_KO,
        extra_legend="KO full ledger. Legend maps to English gold.",
    )


@fn_codec(
    "lang_pinyin",
    "languages",
    "Pinyin (no tones) for every merchant/category/account. Latin script, often worse than hanzi.",
)
def lang_pinyin(bundle: Bundle) -> str:
    return _render_mapped(
        bundle,
        NAME_PY,
        CAT_PY,
        ACC_PY,
        extra_legend="Pinyin full ledger. Legend maps pinyin → English gold.",
    )


# ---------------------------------------------------------------------------
# (2) Mixed: English names, CJK / Hangul amounts
# ---------------------------------------------------------------------------

@fn_codec(
    "lang_mixed_en_cjkamt",
    "languages",
    "English merchants; CJK digit amounts; 1-char CJK categories. Mixed script.",
)
def lang_mixed_en_cjkamt(bundle: Bundle) -> str:
    legend = _full_legend(
        names={n: n for n in NAME_IDEO},
        cats=CAT_IDEO,
        accs=ACC_IDEO,
        extra="Mixed: English names, CJK digits 零一二三四五六七八九負點, C=1 ideograph. Default A=main Y=eur.",
    )
    lines = [
        f"{tx.occurred_on} {tx.name} {_cjk_amount(tx)} {CAT_IDEO[tx.category or '-']}"
        + ("" if tx.account == "main" and tx.currency == "eur" else f" {_flags(tx, ACC_IDEO)}")
        for tx in bundle.transactions
    ]
    return legend + "\n" + "\n".join(lines)


@fn_codec(
    "lang_hangul_digits",
    "languages",
    "Hangul digits 영일이삼사오육칠팔구음쩜 for amounts; English names; 1-char Hangul cats.",
)
def lang_hangul_digits(bundle: Bundle) -> str:
    legend = _full_legend(
        names={n: n for n in NAME_KO_IDEO},
        cats=CAT_KO_IDEO,
        accs=ACC_KO_IDEO,
        extra="Hangul digits 영=0 일=1 … 구=9 음=- 쩜=.; English names; C=1 Hangul. Default A=main Y=eur.",
    )
    lines = [
        f"{tx.occurred_on} {tx.name} {_hangul_digits_amount(tx)} {CAT_KO_IDEO[tx.category or '-']}"
        + ("" if tx.account == "main" and tx.currency == "eur" else f" {_flags(tx, ACC_KO_IDEO)}")
        for tx in bundle.transactions
    ]
    return legend + "\n" + "\n".join(lines)


@fn_codec(
    "lang_hangul_pack",
    "languages",
    "3-syllable base-80 Hangul packing of cents+121390. Alphabet in legend. English names.",
)
def lang_hangul_pack(bundle: Bundle) -> str:
    extra = (
        "V=3 Hangul syllables base80 of (cents+121390); H="
        + HANGUL_80
        + " ; ASCII names; C=1 CJK ideograph; D=ISO; default A=main Y=eur."
    )
    legend = _full_legend(names={n: n for n in NAME_IDEO}, cats=CAT_IDEO, accs=ACC_IDEO, extra=extra)
    lines = [
        f"{tx.occurred_on} {tx.name} {_hangul_pack_cents(tx)} {CAT_IDEO[tx.category or '-']}"
        + ("" if tx.account == "main" and tx.currency == "eur" else f" {_flags(tx, ACC_IDEO)}")
        for tx in bundle.transactions
    ]
    return legend + "\n" + "\n".join(lines)


# ---------------------------------------------------------------------------
# (3) Finance ideographs — one CJK char per merchant/category/account
# ---------------------------------------------------------------------------

IDEO_RULES = (
    "Finance ideographs. D=YYMMDD V=signed cents. Default Y=eur A=主. "
    "Non-eur → trailing $ ; non-main → trailing 储/贷. "
    "N/C/A map glyph→English gold."
)

IDEO_MONTHLY_RULES = (
    "Finance ideographs, monthly groups. Header=YYMM. Row=DD N V C [flags]. "
    "V=signed cents. Default Y=eur A=主. Non-eur → $ ; non-main → 储/贷. "
    "N/C/A map glyph→English gold."
)


@fn_codec(
    "lang_ideo",
    "languages",
    "One mnemonic CJK char per merchant/category/account; spaced ISO lines; English legend.",
)
def lang_ideo(bundle: Bundle) -> str:
    return _render_mapped(
        bundle,
        NAME_IDEO,
        CAT_IDEO,
        ACC_IDEO,
        extra_legend="1 CJK char / label (mnemonic). ISO date, float amount, iso ccy. Legend=English gold.",
    )


@fn_codec(
    "lang_ideo_compact",
    "languages",
    "Glued YYMMDD+ideograph+cents+cat; omit default eur/main. Reversible via legend.",
)
def lang_ideo_compact(bundle: Bundle) -> str:
    legend = _full_legend(names=NAME_IDEO, cats=CAT_IDEO, accs=ACC_IDEO, extra=IDEO_RULES)
    body = _compact_rows(
        bundle, NAME_IDEO, CAT_IDEO, ACC_IDEO, monthly=False, amount_fn=_ascii_cents
    )
    return legend + "\n" + body


@fn_codec(
    "lang_ideo_monthly",
    "languages",
    "Monthly YYMM groups + 1-char CJK names/cats + cents. Full ledger (ccy/account flags). Best language attack.",
)
def lang_ideo_monthly(bundle: Bundle) -> str:
    legend = _full_legend(names=NAME_IDEO, cats=CAT_IDEO, accs=ACC_IDEO, extra=IDEO_MONTHLY_RULES)
    body = _compact_rows(
        bundle, NAME_IDEO, CAT_IDEO, ACC_IDEO, monthly=True, amount_fn=_ascii_cents
    )
    return legend + "\n" + body


@fn_codec(
    "lang_ideo_monthly_cjkamt",
    "languages",
    "Monthly ideographs with CJK-digit amounts instead of ASCII cents (usually worse).",
)
def lang_ideo_monthly_cjkamt(bundle: Bundle) -> str:
    extra = IDEO_MONTHLY_RULES + " Amounts use 零一二三四五六七八九負點 (float, not cents)."
    legend = _full_legend(names=NAME_IDEO, cats=CAT_IDEO, accs=ACC_IDEO, extra=extra)
    body = _compact_rows(
        bundle, NAME_IDEO, CAT_IDEO, ACC_IDEO, monthly=True, amount_fn=_cjk_amount
    )
    return legend + "\n" + body


@fn_codec(
    "lang_ideo_monthly_hangulpack",
    "languages",
    "Monthly ideographs + 3-syllable Hangul-packed cents. Alphabet in legend.",
)
def lang_ideo_monthly_hangulpack(bundle: Bundle) -> str:
    extra = (
        IDEO_MONTHLY_RULES
        + " V=3 Hangul base80 (cents+121390) H="
        + HANGUL_80
    )
    legend = _full_legend(names=NAME_IDEO, cats=CAT_IDEO, accs=ACC_IDEO, extra=extra)
    body = _compact_rows(
        bundle, NAME_IDEO, CAT_IDEO, ACC_IDEO, monthly=True, amount_fn=_hangul_pack_cents
    )
    return legend + "\n" + body


@fn_codec(
    "lang_ko_ideo_monthly",
    "languages",
    "Same compact monthly layout but Hangul 1-syllable labels instead of CJK.",
)
def lang_ko_ideo_monthly(bundle: Bundle) -> str:
    extra = (
        "Hangul finance syllables, monthly groups. Header=YYMM. Row=DD N V C [flags]. "
        "V=signed cents. Default Y=eur A=주. N/C/A map syllable→English gold."
    )
    legend = _full_legend(
        names=NAME_KO_IDEO, cats=CAT_KO_IDEO, accs=ACC_KO_IDEO, extra=extra
    )
    body = _compact_rows(
        bundle, NAME_KO_IDEO, CAT_KO_IDEO, ACC_KO_IDEO, monthly=True, amount_fn=_ascii_cents
    )
    return legend + "\n" + body


@fn_codec(
    "lang_ja_ideo_monthly",
    "languages",
    "Same compact monthly layout with 1-kanji/kata Japanese labels.",
)
def lang_ja_ideo_monthly(bundle: Bundle) -> str:
    extra = (
        "Japanese 1-char labels, monthly groups. Header=YYMM. Row=DD N V C [flags]. "
        "V=signed cents. Default Y=eur A=本. N/C/A map glyph→English gold."
    )
    legend = _full_legend(
        names=NAME_JA_IDEO, cats=CAT_JA_IDEO, accs=ACC_JA_IDEO, extra=extra
    )
    body = _compact_rows(
        bundle, NAME_JA_IDEO, CAT_JA_IDEO, ACC_JA_IDEO, monthly=True, amount_fn=_ascii_cents
    )
    return legend + "\n" + body


@fn_codec(
    "lang_zh_monthly",
    "languages",
    "Readable 2-char Chinese names + monthly grouping + cents. Human-recoverable words, not 1-char codes.",
)
def lang_zh_monthly(bundle: Bundle) -> str:
    extra = (
        "Readable ZH words, monthly groups. Header=YYMM. Row=DD name cents cat [flags]. "
        "Default Y=eur A=主户. Legend maps Chinese→English gold."
    )
    legend = _full_legend(names=NAME_ZH, cats=CAT_ZH, accs=ACC_ZH, extra=extra)
    body = _compact_rows(
        bundle, NAME_ZH, CAT_ZH, ACC_ZH, monthly=True, amount_fn=_ascii_cents
    )
    return legend + "\n" + body
