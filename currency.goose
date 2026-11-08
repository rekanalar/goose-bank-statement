// The ISO 4217 currency table of the bank_statement package.
//
// The table holds the 178 active codes of the list one file of the
// SIX group of 2026-09-17, sorted by code. The exponent is the count
// of minor digits. The 13 codes whose ISO minor unit is not
// applicable hold 0: they have no minor unit. The file was read with
// a generator; edit the ISO file and generate again, never by hand.
namespace bank_statement;

const CURRENCY_CODES: const u8[:][] = [
    "AED", "AFN", "ALL", "AMD", "AOA", "ARS", "AUD", "AWG", "AZN", "BAM",
    "BBD", "BDT", "BHD", "BIF", "BMD", "BND", "BOB", "BOV", "BRL", "BSD",
    "BTN", "BWP", "BYN", "BZD", "CAD", "CDF", "CHE", "CHF", "CHW", "CLF",
    "CLP", "CNY", "COP", "COU", "CRC", "CUP", "CVE", "CZK", "DJF", "DKK",
    "DOP", "DZD", "EGP", "ERN", "ETB", "EUR", "FJD", "FKP", "GBP", "GEL",
    "GHS", "GIP", "GMD", "GNF", "GTQ", "GYD", "HKD", "HNL", "HTG", "HUF",
    "IDR", "ILS", "INR", "IQD", "IRR", "ISK", "JMD", "JOD", "JPY", "KES",
    "KGS", "KHR", "KMF", "KPW", "KRW", "KWD", "KYD", "KZT", "LAK", "LBP",
    "LKR", "LRD", "LSL", "LYD", "MAD", "MDL", "MGA", "MKD", "MMK", "MNT",
    "MOP", "MRU", "MUR", "MVR", "MWK", "MXN", "MXV", "MYR", "MZN", "NAD",
    "NGN", "NIO", "NOK", "NPR", "NZD", "OMR", "PAB", "PEN", "PGK", "PHP",
    "PKR", "PLN", "PYG", "QAR", "RON", "RSD", "RUB", "RWF", "SAR", "SBD",
    "SCR", "SDG", "SEK", "SGD", "SHP", "SLE", "SOS", "SRD", "SSP", "STN",
    "SVC", "SYP", "SZL", "THB", "TJS", "TMT", "TND", "TOP", "TRY", "TTD",
    "TWD", "TZS", "UAH", "UGX", "USD", "USN", "UYI", "UYU", "UYW", "UZS",
    "VED", "VES", "VND", "VUV", "WST", "XAD", "XAF", "XAG", "XAU", "XBA",
    "XBB", "XBC", "XBD", "XCD", "XCG", "XDR", "XOF", "XPD", "XPF", "XPT",
    "XSU", "XTS", "XUA", "XXX", "YER", "ZAR", "ZMW", "ZWG",
];

const CURRENCY_EXPONENTS: i32[] = [
    2, 2, 2, 2, 2, 2, 2, 2, 2, 2,
    2, 2, 3, 0, 2, 2, 2, 2, 2, 2,
    2, 2, 2, 2, 2, 2, 2, 2, 2, 4,
    0, 2, 2, 2, 2, 2, 2, 2, 0, 2,
    2, 2, 2, 2, 2, 2, 2, 2, 2, 2,
    2, 2, 2, 0, 2, 2, 2, 2, 2, 2,
    2, 2, 2, 3, 2, 0, 2, 3, 0, 2,
    2, 2, 0, 2, 0, 3, 2, 2, 2, 2,
    2, 2, 2, 3, 2, 2, 2, 2, 2, 2,
    2, 2, 2, 2, 2, 2, 2, 2, 2, 2,
    2, 2, 2, 2, 2, 3, 2, 2, 2, 2,
    2, 2, 0, 2, 2, 2, 2, 0, 2, 2,
    2, 2, 2, 2, 2, 2, 2, 2, 2, 2,
    2, 2, 2, 2, 2, 2, 3, 2, 2, 2,
    2, 2, 2, 0, 2, 2, 0, 2, 4, 2,
    2, 2, 0, 0, 2, 2, 0, 0, 0, 0,
    0, 0, 0, 2, 2, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 2, 2, 2, 2,
];

// compare_bytes gives -1, 0 or 1. The value is the order of the two
// texts. A shorter text comes first when it is a prefix of the longer
// one.
fn compare_bytes(a: const u8[:], b: const u8[:]) -> i64 {
    let n = if a.len < b.len { a.len } else { b.len };
    var i: i64 = 0;
    while i < n {
        if a[i] != b[i] {
            if a[i] < b[i] { return -1; }
            return 1;
        }
        i += 1;
    }
    if a.len < b.len { return -1; }
    if a.len > b.len { return 1; }
    return 0;
}

// currency_known gives true for a code of the ISO table.
fn currency_known(code: const u8[:]) -> bool {
    return currency_index(code) >= 0;
}

// currency_index finds a code in the sorted table by bisection. It
// gives -1 for a code the table does not hold.
fn currency_index(code: const u8[:]) -> i64 {
    // Every entry of the table holds three bytes.
    if code.len != 3 { return -1; }
    var lo: i64 = 0;
    var hi: i64 = CURRENCY_CODES.len - 1;
    while lo <= hi {
        let mid = lo + (hi - lo) / 2;
        let order = compare_bytes(CURRENCY_CODES[mid], code);
        if order == 0 { return mid; }
        if order < 0 { lo = mid + 1; } else { hi = mid - 1; }
    }
    return -1;
}
