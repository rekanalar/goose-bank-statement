// The bridge between the amounts of this package and the money values
// of goose-finance.
//
// An amount of a statement carries the exponent that the file names:
// camt allows five digits, a fund balance may hold another count than
// the ISO table says. A money value of goose-finance holds the
// exponent of the ISO table. The bridge converts when the two agree
// and faults when they differ, so no caller loses digits without a
// fault.
namespace bank_statement;

import std;
import finance from "rekanalar/goose-finance@v0.1.0";
import fault;
import amount;

// amount_money gives the money value of the amount. The exponent of
// the amount must equal the minor-unit exponent that the currency
// table of goose-finance names, and the currency must be in that
// table. Any other amount faults, and the caller keeps the amount.
fn amount_money(a: Amount) -> finance::Money, Fault {
    let z = finance::Money { minor: 0, code: "" };
    if a.currency.len != 3 {
        return z, fault(F_AMOUNT, 0, 0, "", "the currency of the amount is not a code of three letters");
    }
    if finance::currency_exponent(a.currency) != a.exp {
        return z, fault(F_AMOUNT, 0, 0, a.currency, "the exponent of the amount differs from the currency table");
    }
    let m, ok = finance::money(a.minor, a.currency);
    if !ok {
        return z, fault(F_AMOUNT, 0, 0, a.currency, "the currency table holds not the currency");
    }
    return m, no_fault();
}

// money_amount gives the amount of a money value. The caller names the
// exponent, because a money value holds none of its own. The currency
// of the money value goes into the buffer of the caller.
fn money_amount(m: finance::Money, exp: i32, buf: u8[>..]&) -> Amount {
    let start = buf.len;
    var i: i64 = 0;
    while i < m.code.len {
        buf.push(m.code[i]);
        i += 1;
    }
    return Amount { minor: m.minor, exp: exp, currency: buf[start..] };
}
