import Foundation

/// Fiat and crypto codes the calculator recognizes. Lookup is a set hit.
/// Rates live in `FXBook`; a known code with no quote still fails closed.
public enum FxSymbols {
    /// Decimal places when printing a converted amount. Fiat follows minor units;
    /// crypto keeps 8 so a small coin does not round to zero.
    public static func fractionDigits(_ code: String) -> Int {
        let key = code.lowercased()
        if crypto.contains(key) { return 8 }
        if zeroDecimal.contains(key) { return 0 }
        if threeDecimal.contains(key) { return 3 }
        return 2
    }

    public static func isCrypto(_ code: String) -> Bool {
        crypto.contains(code.lowercased())
    }

    /// Canonical lowercase code when `raw` is exactly a known ticker.
    public static func exact(_ raw: String) -> String? {
        let key = raw.lowercased()
        if let alias = aliases[key] { return alias }
        return codes.contains(key) ? key : nil
    }

    /// True when `raw` is a proper prefix of a longer code (`eu` → `eur`).
    public static func isStrictPrefix(_ raw: String) -> Bool {
        let key = raw.lowercased()
        guard !key.isEmpty, exact(key) == nil else { return false }
        return properPrefixes.contains(key)
    }

    /// Code at the start of `raw`, only when it ends the token (end or whitespace).
    public static func matchToken(_ raw: Substring) -> (code: String, rest: Substring)? {
        let token = raw.prefix { $0.isLetter || $0.isNumber }
        guard (2...8).contains(token.count), let code = exact(String(token)) else { return nil }
        let cut = raw.index(raw.startIndex, offsetBy: token.count)
        let after = raw[cut...]
        guard after.isEmpty || after.first?.isWhitespace == true else { return nil }
        return (code, after)
    }

    /// Spend lines skip tickers that are common English so `-50 try coffee` stays euros.
    public static func matchSpendToken(_ raw: Substring) -> (code: String, rest: Substring)? {
        guard let match = matchToken(raw), !ambiguousSpend.contains(match.code) else { return nil }
        return match
    }

    public static func isTicker(_ raw: String) -> Bool {
        guard (2...8).contains(raw.count) else { return false }
        return raw.allSatisfy { $0.isLetter || $0.isNumber }
    }

    /// Words that are also tickers. Calculator still converts them; spend does not.
    private static let ambiguousSpend: Set<String> = [
        "all", "try", "top", "cup", "mad", "gel", "one", "not", "move", "flow",
        "cake", "link", "near", "atom", "dash", "sand", "rune", "magic", "blur",
        "bat", "ens", "waves", "neo", "eos",
    ]

    private static let aliases: [String: String] = [
        "xbt": "btc",
    ]

    private static let zeroDecimal: Set<String> = [
        "bif", "clp", "djf", "gnf", "isk", "jpy", "kmf", "krw",
        "pyg", "rwf", "ugx", "vnd", "vuv", "xaf", "xof", "xpf",
    ]

    private static let threeDecimal: Set<String> = [
        "bhd", "iqd", "jod", "kwd", "lyd", "omr", "tnd",
    ]

    /// CoinGecko id for each crypto ticker. One request prices all of them.
    public static let cryptoIDs: [String: String] = [
        "btc": "bitcoin",
        "eth": "ethereum",
        "usdt": "tether",
        "usdc": "usd-coin",
        "bnb": "binancecoin",
        "xrp": "ripple",
        "sol": "solana",
        "ada": "cardano",
        "doge": "dogecoin",
        "trx": "tron",
        "ton": "toncoin",
        "dot": "polkadot",
        "avax": "avalanche-2",
        "shib": "shiba-inu",
        "link": "chainlink",
        "bch": "bitcoin-cash",
        "ltc": "litecoin",
        "atom": "cosmos",
        "uni": "uniswap",
        "xlm": "stellar",
        "etc": "ethereum-classic",
        "near": "near",
        "apt": "aptos",
        "fil": "filecoin",
        "arb": "arbitrum",
        "op": "optimism",
        "inj": "injective-protocol",
        "hbar": "hedera-hashgraph",
        "vet": "vechain",
        "algo": "algorand",
        "icp": "internet-computer",
        "aave": "aave",
        "mkr": "maker",
        "grt": "the-graph",
        "stx": "stacks",
        "rune": "thorchain",
        "sui": "sui",
        "pepe": "pepe",
        "imx": "immutable-x",
        "ldo": "lido-dao",
        "crv": "curve-dao-token",
        "sand": "the-sandbox",
        "mana": "decentraland",
        "axs": "axie-infinity",
        "xtz": "tezos",
        "eos": "eos",
        "neo": "neo",
        "cro": "crypto-com-chain",
        "okb": "okb",
        "dai": "dai",
        "wbtc": "wrapped-bitcoin",
        "xmr": "monero",
        "zec": "zcash",
        "dash": "dash",
        "tia": "celestia",
        "wld": "worldcoin-wld",
        "sei": "sei-network",
        "strk": "starknet",
        "pol": "polygon-ecosystem-token",
        "render": "render-token",
        "fet": "fetch-ai",
        "tao": "bittensor",
        "kas": "kaspa",
        "ondo": "ondo-finance",
        "jup": "jupiter-exchange-solana",
        "pyth": "pyth-network",
        "ena": "ethena",
        "pendle": "pendle",
        "gmx": "gmx",
        "aero": "aerodrome-finance",
        "cake": "pancakeswap-token",
        "chz": "chiliz",
        "gala": "gala",
        "comp": "compound-governance-token",
        "snx": "havven",
        "yfi": "yearn-finance",
        "ens": "ethereum-name-service",
        "lrc": "loopring",
        "bat": "basic-attention-token",
        "1inch": "1inch",
        "osmo": "osmosis",
        "kava": "kava",
        "zil": "zilliqa",
        "qtum": "qtum",
        "waves": "waves",
        "icx": "icon",
        "one": "harmony",
        "flow": "flow",
        "egld": "elrond-erd-2",
        "ftm": "fantom",
        "flr": "flare-networks",
        "xdc": "xdce-crowd-sale",
        "cfx": "conflux-token",
        "pyusd": "paypal-usd",
        "eurc": "euro-coin",
        "usde": "ethena-usde",
        "fdusd": "first-digital-usd",
        "tusd": "true-usd",
        "paxg": "pax-gold",
        "xaut": "tether-gold",
        "ray": "raydium",
        "jto": "jito-governance-token",
        "wif": "dogwifcoin",
        "bonk": "bonk",
        "floki": "floki",
        "not": "notcoin",
        "brett": "based-brett",
        "popcat": "popcat",
        "trump": "official-trump",
        "hype": "hyperliquid",
        "move": "movement",
        "eigen": "eigenlayer",
        "ethfi": "ether-fi",
        "blur": "blur",
        "magic": "magic",
        "dydx": "dydx-chain",
    ]

    private static let crypto: Set<String> = Set(cryptoIDs.keys)

    private static let fiat = """
    aed afn all amd ang aoa ars aud awg azn bam bbd bdt bgn bhd bif bmd bnd bob brl bsd \
    btn bwp byn bzd cad cdf chf clp cny cop crc cup cve czk djf dkk dop dzd egp ern etb \
    eur fjd fkp gbp gel ghs gip gmd gnf gtq gyd hkd hnl htg huf idr ils inr iqd irr isk \
    jmd jod jpy kes kgs khr kmf kpw krw kwd kyd kzt lak lbp lkr lrd lsl lyd mad mdl mga \
    mkd mmk mnt mop mru mur mvr mwk mxn myr mzn nad ngn nio nok npr nzd omr pab pen pgk \
    php pkr pln pyg qar ron rsd rub rwf sar sbd scr sdg sek sgd shp sle sos srd stn syp \
    szl thb tjs tmt tnd top try ttd twd tzs uah ugx usd uyu uzs ves vnd vuv wst xaf xcd \
    xof xpf yer zar zmw zwl
    """

    private static let codes: Set<String> = {
        var set = crypto
        for word in fiat.split(separator: " ") {
            set.insert(String(word))
        }
        return set
    }()

    private static let properPrefixes: Set<String> = {
        var set = Set<String>()
        for code in codes {
            var prefix = ""
            for character in code.dropLast() {
                prefix.append(character)
                if !codes.contains(prefix) {
                    set.insert(prefix)
                }
            }
        }
        return set
    }()
}
