//! EUR-pivoted display FX. Ported verbatim from the Python `mous.fx` stub:
//! `EUR->USD` 1.1, `EUR->UAH` 40. Cross pairs go through EUR. Missing pairs
//! return `None` so totals never pretend a 1:1 rate.

pub const PIVOT: &str = "EUR";

const STUB_PAIRS: &[(&str, &str, f64)] = &[("EUR", "USD", 1.1), ("EUR", "UAH", 40.0)];

pub fn normalize(code: &str) -> String {
    code.trim().to_uppercase()
}

fn direct_rate(src: &str, dst: &str) -> Option<f64> {
    for &(base, quote, rate) in STUB_PAIRS {
        if base == src && quote == dst {
            return Some(rate);
        }
        if quote == src && base == dst {
            return Some(1.0 / rate);
        }
    }
    None
}

/// Quote units of `to` per one unit of `frm`, or `None` if unknown.
pub fn quote(frm: &str, to: &str) -> Option<f64> {
    let src = normalize(frm);
    let dst = normalize(to);
    if src.is_empty() || dst.is_empty() {
        return None;
    }
    if src == dst {
        return Some(1.0);
    }
    if let Some(direct) = direct_rate(&src, &dst) {
        if direct > 0.0 && direct.is_finite() {
            return Some(direct);
        }
    }
    if src != PIVOT && dst != PIVOT {
        if let (Some(to_pivot), Some(from_pivot)) =
            (direct_rate(&src, PIVOT), direct_rate(PIVOT, &dst))
        {
            let crossed = to_pivot * from_pivot;
            if crossed.is_finite() && crossed > 0.0 {
                return Some(crossed);
            }
        }
    }
    None
}

/// Convert `amount` from `frm` to `to`, or `None` if no quote exists.
pub fn convert(amount: f64, frm: &str, to: &str) -> Option<f64> {
    if !amount.is_finite() {
        return None;
    }
    let rate = quote(frm, to)?;
    let converted = amount * rate;
    if !converted.is_finite() {
        return None;
    }
    Some(converted)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn same_currency_is_identity() {
        assert_eq!(quote("eur", "EUR"), Some(1.0));
    }

    #[test]
    fn direct_and_inverse() {
        assert_eq!(quote("EUR", "USD"), Some(1.1));
        assert_eq!(convert(110.0, "usd", "eur"), Some(100.0));
    }

    #[test]
    fn cross_via_pivot() {
        // USD -> UAH goes USD->EUR->UAH = (1/1.1) * 40
        let r = quote("USD", "UAH").unwrap();
        assert!((r - (40.0 / 1.1)).abs() < 1e-9);
    }

    #[test]
    fn unknown_pair_is_none() {
        assert_eq!(quote("EUR", "GBP"), None);
        assert_eq!(convert(10.0, "EUR", "GBP"), None);
    }
}
