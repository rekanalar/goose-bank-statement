// The tests of the group money_bridge.
namespace money_bridge_tests;

import std;
import os;
import xml from "rekanalar/goose-xml@v2.0.0";
import process from "rekanalar/goose-process@v1.0.0";
import bank_statement from "..";
import finance from "rekanalar/goose-finance@v0.1.0";

fn test_money_bridge() {
    var buf: u8[>..] = [];
    // An amount with the ISO exponent converts, and reads back.
    let a = bank_statement::Amount { minor: 12345, exp: 2, currency: "EUR" };
    let m, f = bank_statement::amount_money(a);
    if f.kind != 0 { print("FAIL bridge ", bank_statement::kind_name(f.kind), " ", f.detail, "\n"); }
    assert(f.kind == 0);
    assert(m.minor == 12345 && m.code == "EUR");
    let b = bank_statement::money_amount(m, 2, buf);
    assert(b.minor == 12345 && b.exp == 2 && b.currency == "EUR");
    // A zero exponent currency and a fund currency with four digits.
    let y = bank_statement::Amount { minor: 500, exp: 0, currency: "JPY" };
    let my, fy = bank_statement::amount_money(y);
    assert(fy.kind == 0 && my.minor == 500 && my.code == "JPY");
    let u = bank_statement::Amount { minor: 7, exp: 4, currency: "CLF" };
    let mu, fu = bank_statement::amount_money(u);
    assert(fu.kind == 0 && mu.minor == 7);
    // A mismatch faults. The caller keeps the amount.
    let bad = bank_statement::Amount { minor: 100, exp: 5, currency: "EUR" };
    let mb, fb = bank_statement::amount_money(bad);
    assert(fb.kind == bank_statement::F_AMOUNT && mb.minor == 0);
    // A code that no table holds faults.
    let no = bank_statement::Amount { minor: 1, exp: 2, currency: "XXX" };
    let mn, fn2 = bank_statement::amount_money(no);
    assert(fn2.kind == bank_statement::F_AMOUNT);
    // A short currency faults.
    let sh = bank_statement::Amount { minor: 1, exp: 2, currency: "EU" };
    let ms, fs = bank_statement::amount_money(sh);
    assert(fs.kind == bank_statement::F_AMOUNT);
}
