// The tests of the group mt940.
namespace mt940_tests;

import std;
import os;
import xml from "rekanalar/goose-xml@v2.0.0";
import process from "rekanalar/goose-process@v1.0.0";
import bank_statement from "..";
import finance from "rekanalar/goose-finance@v0.1.0";
import common;

fn test_mt940_basic() {
    let lim = bank_statement::default_limits();
    let opts = bank_statement::Mt940Options { .. };
    var sts: bank_statement::Statement[>..] = [];
    var ens: bank_statement::Entry[>..] = [];
    var bals: bank_statement::Balance[>..] = [];
    var notes: bank_statement::Note[>..] = [];
    var xbuf2: u8[>..] = [];
    let f = bank_statement::parse_mt940(common::STMT1, lim, opts, sts, ens, bals, notes, xbuf2);
    if f.kind != 0 { print("FAIL ", bank_statement::kind_name(f.kind), " line ", f.line, " ", f.tag, " ", f.detail, "\n"); }
    assert(f.kind == 0);
    assert(sts.len == 1);
    let st = sts[0];
    assert(st.reference == "STMT001");
    assert(st.account == "DE89370400440532013000");
    assert(st.number == "00001");
    assert(st.sequence == "001");
    assert(st.opening.credit);
    assert(st.opening.amount.minor == 100000);
    assert(st.opening.amount.currency == "EUR");
    assert(st.opening.date.year == 2025 && st.opening.date.month == 1 && st.opening.date.day == 1);
    assert(st.closing.amount.minor == 129950);
    assert(st.entry_count == 2);
    assert(st.balance_count == 3);
    assert(ens.len == 2);
    let e = ens[0];
    assert(e.value_date.month == 1 && e.value_date.day == 2);
    assert(e.entry_date.year == 2025 && e.entry_date.month == 1 && e.entry_date.day == 2);
    assert(e.mark == "C");
    assert(e.amount.minor == 50000);
    assert(e.type_id == "NTRF");
    assert(e.customer_ref == "NONREF");
    assert(e.bank_ref == "BANKREF1");
    assert(e.supplementary == "SUPPLEMENT");
    assert(starts_with(e.narrative, "020?00BANK"));
    let e2 = ens[1];
    assert(e2.mark == "D");
    assert(e2.amount.minor == 20050);
    assert(e2.entry_date.year == 0);
    assert(e2.customer_ref == "CHK123");
    assert(e2.narrative.len == 0);
    assert(bals[2].kind == bank_statement::BAL_AVAILABLE);
}

fn test_mt940_balance_error() {
    // One cent off: the closing balance does not match.
    common::run_mt940("{4:\n:20:A\n:25:X\n:60F:C250101EUR1000,00\n:61:250102C500,00NTRFREF\n:62F:C250102EUR1500,01\n-}", false, 7, "62F");
    // The same file passes with the check off.
    common::run_mt940("{4:\n:20:A\n:25:X\n:60F:C250101EUR1000,00\n:61:250102C500,00NTRFREF\n:62F:C250102EUR1500,01\n-}", true, 0, "");
    // A good statement with a debit opening balance.
    common::run_mt940(":20:A\n:60F:D250101EUR100,00\n:61:250102C150,00NTRFREF\n:62F:C250102EUR50,00\n", false, 0, "");
    // Reversals: RC takes money out, RD puts money in.
    common::run_mt940(":20:A\n:60F:C250101EUR100,00\n:61:250102RC30,00NTRFREF\n:61:250102RD10,00NTRFREF\n:62F:C250102EUR80,00\n", false, 0, "");
    // No closing balance with the check on is a fault.
    common::run_mt940(":20:A\n:60F:C250101EUR100,00\n", false, 7, "62F");
}

fn test_mt940_faults() {
    common::run_mt940(":20:A\n:99:X\n", false, 3, "99");
    common::run_mt940(":25:X\n", false, 2, "25");
    common::run_mt940("stray\n", false, 2, "");
    common::run_mt940(":20:A\n:60F:X250101EUR1,00\n", false, 2, "60F");
    common::run_mt940(":20:A\n:60F:C251301EUR1,00\n", false, 6, "60F");
    common::run_mt940(":20:A\n:60F:C250101EUR1,2,3\n", false, 4, "60F");
}

fn test_mt940_multi() {
    let lim = bank_statement::default_limits();
    let opts = bank_statement::Mt940Options { .. };
    var sts: bank_statement::Statement[>..] = [];
    var ens: bank_statement::Entry[>..] = [];
    var bals: bank_statement::Balance[>..] = [];
    var notes: bank_statement::Note[>..] = [];
    // Three statements, mixed line ends, intermediate balances, no :28C:.
    let text = ":20:ONE\r\n:60M:C250101EUR10,00\r\n:62M:C250101EUR10,00\r\n-\r\n:20:TWO\n:60M:C250101EUR10,00\n:61:250101C1,00NTRFX\n:62F:C250101EUR11,00\n-\n:20:THREE\n:60F:C250101JPY5\n:61:250101D5NTRFX\n:62F:C250101JPY0\n";
    var xbuf3: u8[>..] = [];
    let f = bank_statement::parse_mt940(text, lim, opts, sts, ens, bals, notes, xbuf3);
    if f.kind != 0 { print("FAIL ", bank_statement::kind_name(f.kind), " line ", f.line, " ", f.tag, " ", f.detail, "\n"); }
    assert(f.kind == 0);
    assert(sts.len == 3);
    assert(sts[0].reference == "ONE");
    assert(sts[0].opening.intermediate);
    assert(sts[0].number.len == 0);
    assert(sts[1].entry_count == 1);
    assert(sts[2].opening.amount.exp == 0);
    assert(ens.len == 2);
    assert(sts[2].entry_start == 1);
}

fn test_interim_flag_keeps_check() {
    // A :13D: or :34F: line must not turn the balance check off.
    common::run_mt940(":20:A\n:13D:2501021530+0100\n:60F:C250101EUR100,00\n:61:250101C1,00NTRFX\n:62F:C250101EUR999,00\n", false, 7, "62F");
    common::run_mt940(":20:A\n:34F:EUR0,\n:60F:C250101EUR100,00\n:61:250101C1,00NTRFX\n:62F:C250101EUR999,00\n", false, 7, "62F");
    // An interim report with only one balance is not a statement: no fault from the missing one.
    common::run_mt940(":20:A\n:34F:EUR0,\n:61:250101C1,00NTRFX\n", false, 0, "");
    // A good statement with an interim line still passes.
    common::run_mt940(":20:A\n:34F:EUR0,\n:60F:C250101EUR100,00\n:61:250101C1,00NTRFX\n:62F:C250101EUR101,00\n", false, 0, "");
}

fn test_balance_checked() {
    let lim = bank_statement::default_limits();
    var sts: bank_statement::Statement[>..] = [];
    var ens: bank_statement::Entry[>..] = [];
    var bals: bank_statement::Balance[>..] = [];
    var notes: bank_statement::Note[>..] = [];
    let text = ":20:A\n:60F:C250101EUR0,00\n:62F:C250101EUR0,00\n";
    let on = bank_statement::Mt940Options { .. };
    let off = bank_statement::Mt940Options { skip_balance_check: true, check_fields: false, style: 0 };
    var xbuf5: u8[>..] = [];
    let f = bank_statement::parse_mt940(text, lim, on, sts, ens, bals, notes, xbuf5);
    assert(f.kind == 0 && sts[0].balance_checked);
    var sts2: bank_statement::Statement[>..] = [];
    var ens2: bank_statement::Entry[>..] = [];
    var bals2: bank_statement::Balance[>..] = [];
    var notes2: bank_statement::Note[>..] = [];
    var xbuf6: u8[>..] = [];
    let g = bank_statement::parse_mt940(text, lim, off, sts2, ens2, bals2, notes2, xbuf6);
    assert(g.kind == 0 && !sts2[0].balance_checked);
}

fn test_lone_cr() {
    common::run_mt940(":20:A\r:60F:C250101EUR0,00\r", false, 2, "");
    common::run_mt940(":20:A\r\n:60F:C250101EUR0,00\r\n:62F:C250101EUR0,00\r\n", false, 0, "");
    common::run_qif("!Type:Bank\rT1\r", 1, 2);
}

// test_mt940_64_65 checks the typed available and forward balances.
fn test_mt940_64_65() {
    let lim = bank_statement::default_limits();
    let opts = bank_statement::Mt940Options { .. };
    var sts: bank_statement::Statement[>..] = [];
    var ens: bank_statement::Entry[>..] = [];
    var bals: bank_statement::Balance[>..] = [];
    var notes: bank_statement::Note[>..] = [];
    let text = ":20:A\n:60F:C250101EUR100,00\n:61:250102C50,00NTRFREF\n:62F:C250102EUR150,00\n:64:C250102EUR150,00\n:65:C250331EUR200,00\n:65:C250401EUR250,00\n";
    var xbuf22: u8[>..] = [];
    let f = bank_statement::parse_mt940(text, lim, opts, sts, ens, bals, notes, xbuf22);
    if f.kind != 0 { print("FAIL 64/65 ", bank_statement::kind_name(f.kind), " line ", f.line, " ", f.tag, " ", f.detail, "\n"); }
    assert(f.kind == 0);
    // Both balances sit in the balance range and as typed fields.
    assert(sts[0].balance_count == 5);
    assert(sts[0].available.kind == bank_statement::BAL_AVAILABLE);
    assert(sts[0].available.amount.minor == 15000 && sts[0].available.amount.currency == "EUR");
    assert(sts[0].available.date.year == 2025 && sts[0].available.date.month == 1 && sts[0].available.date.day == 2);
    assert(sts[0].forward.kind == bank_statement::BAL_FORWARD);
    assert(sts[0].forward.amount.minor == 25000);
    assert(sts[0].forward.date.day == 1 && sts[0].forward.date.month == 4);
    // The balance check reads the opening and closing balance only.
    assert(sts[0].balance_checked);
    // A statement without the lines holds kind 0.
    var sts2: bank_statement::Statement[>..] = [];
    var ens2: bank_statement::Entry[>..] = [];
    var bals2: bank_statement::Balance[>..] = [];
    var notes2: bank_statement::Note[>..] = [];
    var xbuf23: u8[>..] = [];
    let g = bank_statement::parse_mt940(":20:A\n:60F:C250101EUR0,00\n:62F:C250101EUR0,00\n", lim, opts, sts2, ens2, bals2, notes2, xbuf23);
    assert(g.kind == 0 && sts2[0].available.kind == 0 && sts2[0].forward.kind == 0);
    // A second :64: is a fault. A second :65: replaces the value.
    common::run_mt940(":20:A\n:64:C250101EUR1,00\n:64:C250102EUR2,00\n", false, 2, "64");
    var sts3: bank_statement::Statement[>..] = [];
    var ens3: bank_statement::Entry[>..] = [];
    var bals3: bank_statement::Balance[>..] = [];
    var notes3: bank_statement::Note[>..] = [];
    let off = bank_statement::Mt940Options { skip_balance_check: true, check_fields: false, style: 0 };
    var xbuf24: u8[>..] = [];
    let h = bank_statement::parse_mt940(":20:A\n:65:C250101EUR1,00\n:65:C250102EUR2,00\n", lim, off, sts3, ens3, bals3, notes3, xbuf24);
    assert(h.kind == 0 && sts3[0].forward.amount.minor == 200);
}
