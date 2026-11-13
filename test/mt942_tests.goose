// The tests of the group mt942.
namespace mt942_tests;

import std;
import os;
import xml from "rekanalar/goose-xml@v2.0.0";
import process from "rekanalar/goose-process@v1.0.0";
import bank_statement from "..";
import finance from "rekanalar/goose-finance@v0.1.0";
import statement_checks;

fn test_mt942() {
    let lim = bank_statement::default_limits();
    let opts = bank_statement::Mt940Options { .. };
    var sts: bank_statement::Statement[>..] = [];
    var ens: bank_statement::Entry[>..] = [];
    var bals: bank_statement::Balance[>..] = [];
    var notes: bank_statement::Note[>..] = [];
    let text = ":20:INTERIM\n:25:ACC\n:28C:5/1\n:34F:EUR0,\n:34F:EURD100,\n:13D:2501021530+0100\n:61:250102C500,00NTRFREF\n:61:250102D20,00NTRFREF2\n:90D:1EUR20,00\n:90C:1EUR500,00\n";
    var xbuf7: u8[>..] = [];
    let f = bank_statement::parse_mt940(text, lim, opts, sts, ens, bals, notes, xbuf7);
    if f.kind != 0 { print("FAIL ", bank_statement::kind_name(f.kind), " line ", f.line, " ", f.tag, " ", f.detail, "\n"); }
    assert(f.kind == 0);
    let st = sts[0];
    assert(st.is_interim);
    assert(st.floor.minor == 0 && st.floor_mark == '-');
    assert(st.floor2.minor == 10000 && st.floor2_mark == 'D');
    assert(st.has_report_time && st.report_minutes == 15 * 60 + 30 && st.report_offset == 60);
    assert(st.debit_count == 1 && st.debit_total.minor == 2000);
    assert(st.credit_count == 1 && st.credit_total.minor == 50000);
    // A wrong total is an error.
    statement_checks::run_mt940(":20:I\n:34F:EUR0,\n:61:250102C500,00NTRFREF\n:90C:1EUR499,99\n", false, 8, "90C");
    statement_checks::run_mt940(":20:I\n:34F:EUR0,\n:61:250102C500,00NTRFREF\n:90C:2EUR500,00\n", false, 8, "90C");
}

fn test_write_mt942_hybrid() {
    let lim = bank_statement::default_limits();
    let opts = bank_statement::Mt940Options { .. };
    var sts: bank_statement::Statement[>..] = [];
    var ens: bank_statement::Entry[>..] = [];
    var bals: bank_statement::Balance[>..] = [];
    var notes: bank_statement::Note[>..] = [];
    let text = ":20:HYB\n:25:ACC\n:28C:5/1\n:34F:EUR0,\n:60F:C250101EUR100,00\n:61:250102C500,00NTRFREF\n:62F:C250102EUR600,00\n";
    var xbuf37: u8[>..] = [];
    let f = bank_statement::parse_mt940(text, lim, opts, sts, ens, bals, notes, xbuf37);
    if f.kind != 0 { print("FAIL hybrid read ", bank_statement::kind_name(f.kind), " ", f.tag, " ", f.detail, "\n"); }
    assert(f.kind == 0);
    var out: u8[>..] = [];
    let w = bank_statement::write_mt940(sts, ens, lim, out);
    if w.kind != 0 { print("FAIL hybrid write ", bank_statement::kind_name(w.kind), " ", w.tag, " ", w.detail, "\n"); }
    assert(w.kind == 0);
    assert(find(out, ":34F:EUR0,00") >= 0);
    assert(find(out, ":60F:C250101EUR100,00") >= 0);
    assert(find(out, ":62F:C250102EUR600,00") >= 0);
    assert(statement_checks::fk(out) == 0);
}

fn test_write_mt942_bare() {
    let lim = bank_statement::default_limits();
    let opts = bank_statement::Mt940Options { .. };
    var sts: bank_statement::Statement[>..] = [];
    var ens: bank_statement::Entry[>..] = [];
    var bals: bank_statement::Balance[>..] = [];
    var notes: bank_statement::Note[>..] = [];
    let text = ":20:B\n:25:ACC\n:28C:1\n:34F:EUR0,00\n:61:250102C500,00NTRFREF\n";
    var xbuf38: u8[>..] = [];
    var xbuf38_pre: u8[>..] = [];
    assert(bank_statement::parse_mt940(text, lim, opts, sts, ens, bals, notes, xbuf38_pre).kind == 0);
    var out: u8[>..] = [];
    assert(bank_statement::write_mt940(sts, ens, lim, out).kind == 0);
    assert(out == text);
    assert(find(out, ":13D:") < 0 && find(out, ":90") < 0);
}

fn test_write_mt942() {
    let lim = bank_statement::default_limits();
    let opts = bank_statement::Mt940Options { .. };
    var sts: bank_statement::Statement[>..] = [];
    var ens: bank_statement::Entry[>..] = [];
    var bals: bank_statement::Balance[>..] = [];
    var notes: bank_statement::Note[>..] = [];
    let text = ":20:INTERIM\n:21:RELATED\n:25:ACC\n:28C:5/1\n:34F:EUR0,\n:34F:EURD100,\n:13D:2501021530+0100\n:61:250102C500,00NTRFREF\n:61:250102D20,00NTRFREF2\n:90D:1EUR20,00\n:90C:1EUR500,00\n";
    var xbuf39: u8[>..] = [];
    let f = bank_statement::parse_mt940(text, lim, opts, sts, ens, bals, notes, xbuf39);
    if f.kind != 0 { print("FAIL mt942 read ", bank_statement::kind_name(f.kind), " ", f.tag, " ", f.detail, "\n"); }
    assert(f.kind == 0);
    // The writer gives the same text back.
    var out: u8[>..] = [];
    let w = bank_statement::write_mt940(sts, ens, lim, out);
    if w.kind != 0 { print("FAIL mt942 write ", bank_statement::kind_name(w.kind), " ", w.tag, " ", w.detail, "\n"); }
    assert(w.kind == 0);
    let want = ":20:INTERIM\n:21:RELATED\n:25:ACC\n:28C:5/1\n:34F:EUR0,00\n:34F:EURD100,00\n:13D:2501021530+0100\n:61:250102C500,00NTRFREF\n:61:250102D20,00NTRFREF2\n:90D:1EUR20,00\n:90C:1EUR500,00\n";
    assert(out == want);
    // The rules of the manual accept the text that the writer gives.
    assert(statement_checks::fk(text) == 0);
    assert(statement_checks::fk(out) == 0);
    // The reader gives the same values back.
    var s2: bank_statement::Statement[>..] = [];
    var e2: bank_statement::Entry[>..] = [];
    var b2: bank_statement::Balance[>..] = [];
    var n2: bank_statement::Note[>..] = [];
    var xbuf40: u8[>..] = [];
    let g = bank_statement::parse_mt940(out, lim, opts, s2, e2, b2, n2, xbuf40);
    if g.kind != 0 { print("FAIL mt942 reread ", bank_statement::kind_name(g.kind), " ", g.tag, " ", g.detail, "\n"); }
    assert(g.kind == 0);
    let a = sts[0];
    let b = s2[0];
    assert(a.is_interim && b.is_interim);
    assert(a.reference == b.reference && a.related_ref == b.related_ref);
    assert(a.account == b.account && a.number == b.number && a.sequence == b.sequence);
    assert(a.floor.minor == b.floor.minor && a.floor_mark == b.floor_mark);
    assert(a.floor2.minor == b.floor2.minor && a.floor2_mark == b.floor2_mark);
    assert(a.report_date.year == b.report_date.year && a.report_date.month == b.report_date.month);
    assert(a.report_minutes == b.report_minutes && a.report_offset == b.report_offset);
    assert(a.debit_count == b.debit_count && a.credit_count == b.credit_count);
    assert(a.debit_total.minor == b.debit_total.minor && a.credit_total.minor == b.credit_total.minor);
    assert(ens.len == 2 && e2.len == 2);
    assert(ens[0].mark == e2[0].mark && ens[0].amount.minor == e2[0].amount.minor);
    assert(ens[0].customer_ref == e2[0].customer_ref && ens[1].customer_ref == e2[1].customer_ref);
    // A total that does not match the entries is a fault.
    sts[0].debit_total.minor = 1;
    var bad: u8[>..] = [];
    assert(bank_statement::write_mt940(sts, ens, lim, bad).kind == bank_statement::F_TOTAL);
    sts[0].debit_total.minor = 2000;
    // An entry with a currency of its own is a fault.
    ens[0].amount.currency = "USD";
    var bad2: u8[>..] = [];
    assert(bank_statement::write_mt940(sts, ens, lim, bad2).kind == bank_statement::F_SYNTAX);
    ens[0].amount.currency = "EUR";
    // A floor limit without a currency is a fault.
    sts[0].floor.currency = "";
    var bad3: u8[>..] = [];
    assert(bank_statement::write_mt940(sts, ens, lim, bad3).kind == bank_statement::F_SYNTAX);
    sts[0].floor.currency = "EUR";
    // A control byte in the reference is a fault.
    sts[0].reference = "A\x01B";
    var bad4: u8[>..] = [];
    assert(bank_statement::write_mt940(sts, ens, lim, bad4).kind == bank_statement::F_SYNTAX);
    // A statement with an opening balance but no closing balance is a fault.
    sts[0].reference = "INTERIM";
    sts[0].opening.kind = 1;
    var bad5: u8[>..] = [];
    assert(bank_statement::write_mt940(sts, ens, lim, bad5).kind == bank_statement::F_SYNTAX);
    sts[0].opening.kind = 0;
    // A report without a floor limit is a fault.
    sts[0].floor.currency = "";
    var bad6: u8[>..] = [];
    assert(bank_statement::write_mt940(sts, ens, lim, bad6).kind == bank_statement::F_SYNTAX);
    sts[0].floor.currency = "EUR";
    // A total in another currency is a fault.
    sts[0].debit_total.currency = "USD";
    var bad7: u8[>..] = [];
    assert(bank_statement::write_mt940(sts, ens, lim, bad7).kind == bank_statement::F_TOTAL);
    sts[0].debit_total.currency = "EUR";
}
