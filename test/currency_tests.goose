// The tests of the group currency.
namespace currency_tests;

import std;
import os;
import xml from "rekanalar/goose-xml@v2.0.0";
import process from "rekanalar/goose-process@v1.0.0";
import bank_statement from "..";
import finance from "rekanalar/goose-finance@v0.1.0";
import statement_checks;

// test_currency_table checks the whole ISO 4217 table: the count, the
// sort order, the share of every exponent group and one code of each
// group. The values come from the list one file of the SIX group of
// 2026-09-17.
fn test_currency_table() {
    assert(bank_statement::CURRENCY_CODES.len == 178);
    var zero = 0;
    var two = 0;
    var three = 0;
    var four = 0;
    var i: i64 = 0;
    while i < bank_statement::CURRENCY_CODES.len {
        let e = bank_statement::CURRENCY_EXPONENTS[i];
        assert(e >= 0 && e <= 4);
        if e == 0 { zero += 1; }
        else if e == 2 { two += 1; }
        else if e == 3 { three += 1; }
        else { four += 1; }
        if i > 0 {
            assert(bank_statement::compare_bytes(bank_statement::CURRENCY_CODES[i - 1], bank_statement::CURRENCY_CODES[i]) < 0);
        }
        i += 1;
    }
    assert(zero == 30);  // 17 without minor digits, 13 not applicable
    assert(two == 139);
    assert(three == 7);
    assert(four == 2);
    // Spot values from the ISO file, one code or more of each group.
    assert(bank_statement::currency_exponent("BIF") == 0);
    assert(bank_statement::currency_exponent("JPY") == 0);
    assert(bank_statement::currency_exponent("XAU") == 0);
    assert(bank_statement::currency_exponent("XXX") == 0);
    assert(bank_statement::currency_exponent("BHD") == 3);
    assert(bank_statement::currency_exponent("TND") == 3);
    assert(bank_statement::currency_exponent("CLF") == 4);
    assert(bank_statement::currency_exponent("UYW") == 4);
    assert(bank_statement::currency_exponent("USD") == 2);
    assert(bank_statement::currency_exponent("CHF") == 2);
    assert(bank_statement::currency_exponent("ZZZ") == 2);
    assert(bank_statement::currency_known("EUR"));
    assert(!bank_statement::currency_known("ZZZ"));
    // The lookup finds every code of the table.
    i = 0;
    while i < bank_statement::CURRENCY_CODES.len {
        let e = bank_statement::currency_exponent(bank_statement::CURRENCY_CODES[i]);
        assert(e == bank_statement::CURRENCY_EXPONENTS[i]);
        i += 1;
    }
}

fn test_currency_rules() {
    // An entry before any balance or floor limit has no currency.
    statement_checks::run_mt940(":20:A\n:61:250101C1NTRFX\n:60F:C250101JPY0\n:62F:C250101JPY1\n", false, 2, "61");
    // An interim report takes the currency of its floor limit.
    let lim = bank_statement::default_limits();
    let opts = bank_statement::Mt940Options { .. };
    var sts: bank_statement::Statement[>..] = [];
    var ens: bank_statement::Entry[>..] = [];
    var bals: bank_statement::Balance[>..] = [];
    var notes: bank_statement::Note[>..] = [];
    var xbuf4: u8[>..] = [];
    let f = bank_statement::parse_mt940(":20:I\n:34F:JPY0\n:61:250101C150NTRFX\n", lim, opts, sts, ens, bals, notes, xbuf4);
    assert(f.kind == 0);
    assert(ens[0].amount.minor == 150 && ens[0].amount.exp == 0 && ens[0].amount.currency == "JPY");
    assert(!sts[0].balance_checked);
}
