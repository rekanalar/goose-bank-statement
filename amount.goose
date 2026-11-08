// Exact amounts for the bank_statement package.
//
// An amount is a count of minor units with the exponent of its currency.
// The parser reads digits into an i64 with a check on every step. It uses
// no float. A number that does not fit is an overflow fault.
namespace bank_statement;

import std;
import fault;
import text;

// Amount holds money as minor units. The sign sits in minor. The exp is
// the count of minor digits of the currency. The currency is a span over
// the input and may be empty.
struct Amount {
    minor: i64,
    exp: i32,
    currency: const u8[:],
}

// currency_exponent gives the count of minor digits of an ISO 4217 code:
// 0 for the zero digit currencies, 3 for the three digit ones, 2 for
// the rest.
fn currency_exponent(code: const u8[:]) -> i32 {
    if code.len != 3 { return 2; }
    let zero = ["BIF", "CLP", "DJF", "GNF", "ISK", "JPY", "KMF", "KRW", "PYG", "RWF", "UGX", "UYI", "VND", "VUV", "XAF", "XOF", "XPF"];
    for z in zero { if code == z { return 0; } }
    let three = ["BHD", "IQD", "JOD", "KWD", "LYD", "OMR", "TND"];
    for t in three { if code == t { return 3; } }
    return 2;
}

// parse_number reads a decimal number. It gives the digits as an i64
// mantissa and the count of digits after the decimal mark. The decimal
// argument is the decimal mark. The group argument is the thousands mark,
// or 0 for none. A thousands mark must sit between digits and every
// group after the first must hold exactly three digits. A sign, a plus
// sign or a pair of parentheses may stand in front. The result of a
// parenthesised number is negative.
fn parse_number(text: const u8[:], decimal: u8, group: u8) -> i64, i32, Fault {
    var s = text;
    var neg = false;
    // Trim blanks.
    while s.len > 0 && (s[0] == ' ' || s[0] == '\t') { s = s[1..]; }
    while s.len > 0 && (s[s.len - 1] == ' ' || s[s.len - 1] == '\t') { s = s[..s.len - 1]; }
    if s.len == 0 { return 0, 0, fault(F_AMOUNT, 0, 0, "", "empty amount"); }
    if s[0] == '(' {
        if s[s.len - 1] != ')' { return 0, 0, fault(F_AMOUNT, 0, 0, "", "unbalanced parentheses"); }
        neg = true;
        s = s[1..s.len - 1];
    }
    if s.len > 0 && (s[0] == '-' || s[0] == '+') {
        if s[0] == '-' { neg = !neg; }
        s = s[1..];
    }
    if s.len == 0 { return 0, 0, fault(F_AMOUNT, 0, 0, "", "no digits"); }
    let limit: i64 = 9223372036854775807;
    var acc: i64 = 0;
    var seen_dec = false;
    var scale: i32 = 0;
    var digits = 0;
    var run = 0;          // digits since the last thousands mark
    var in_group = false; // a thousands mark was read
    var i = 0;
    while i < s.len {
        let c = s[i];
        if is_digit(c) {
            let d = (c - '0');
            if acc > (limit - d) / 10 { return 0, 0, fault(F_OVERFLOW, 0, 0, "", "amount does not fit in 64 bits"); }
            acc = acc * 10 + d;
            digits += 1;
            run += 1;
            if seen_dec { scale += 1; }
            if run > 3 && in_group && !seen_dec { return 0, 0, fault(F_AMOUNT, 0, 0, "", "thousands group is not three digits"); }
        } else if c == decimal && !seen_dec {
            if in_group && run != 3 { return 0, 0, fault(F_AMOUNT, 0, 0, "", "thousands group is not three digits"); }
            seen_dec = true;
            run = 0;
        } else if group != 0 && c == group && !seen_dec {
            if run == 0 || i + 1 >= s.len { return 0, 0, fault(F_AMOUNT, 0, 0, "", "thousands mark outside digits"); }
            if in_group && run != 3 { return 0, 0, fault(F_AMOUNT, 0, 0, "", "thousands group is not three digits"); }
            if !in_group && run > 3 { return 0, 0, fault(F_AMOUNT, 0, 0, "", "thousands group is not three digits"); }
            in_group = true;
            run = 0;
        } else {
            return 0, 0, fault(F_AMOUNT, 0, 0, "", "unexpected character in amount");
        }
        i += 1;
    }
    if digits == 0 { return 0, 0, fault(F_AMOUNT, 0, 0, "", "no digits"); }
    if in_group && !seen_dec && run != 3 { return 0, 0, fault(F_AMOUNT, 0, 0, "", "thousands group is not three digits"); }
    if neg { acc = -acc; }
    return acc, scale, no_fault();
}

// parse_amount reads an amount in a currency with exp minor digits. It
// faults on more decimals than exp. Fewer decimals are padded with zeros.
fn parse_amount(text: const u8[:], exp: i32, decimal: u8, group: u8) -> Amount, Fault {
    var a = Amount { minor: 0, exp: exp, currency: "" };
    let m, scale, f = parse_number(text, decimal, group);
    if f.kind != F_NONE { return a, f; }
    if scale > exp { return a, fault(F_AMOUNT, 0, 0, "", "more decimals than the currency allows"); }
    var v = m;
    var k = scale;
    while k < exp {
        if v > 922337203685477580 || v < -922337203685477580 { return a, fault(F_OVERFLOW, 0, 0, "", "amount does not fit in 64 bits"); }
        v = v * 10;
        k += 1;
    }
    a.minor = v;
    return a, no_fault();
}
