// The tests of the group mt940_write.
namespace mt940_write_tests;

import std;
import os;
import xml from "rekanalar/goose-xml@v2.0.0";
import process from "rekanalar/goose-process@v1.0.0";
import bank_statement from "..";
import finance from "rekanalar/goose-finance@v0.1.0";
import statement_checks;
import sample_texts;

fn test_write_mt940() {
    let lim = bank_statement::default_limits();
    let ropts = bank_statement::Mt940Options { skip_balance_check: false, check_fields: true, style: 0 };
    var sts: bank_statement::Statement[>..] = [];
    var ens: bank_statement::Entry[>..] = [];
    var bals: bank_statement::Balance[>..] = [];
    var notes: bank_statement::Note[>..] = [];
    let popts = bank_statement::Mt940Options { .. };
    var xbuf33: u8[>..] = [];
    var xbuf33_pre: u8[>..] = [];
    assert(bank_statement::parse_mt940(sample_texts::STMT1, lim, popts, sts, ens, bals, notes, xbuf33_pre).kind == 0);
    var out: u8[>..] = [];
    let w = bank_statement::write_mt940(sts, ens, lim, out);
    if w.kind != 0 { print("FAIL mt940 write ", bank_statement::kind_name(w.kind), " ", w.tag, " ", w.detail, "\n"); }
    assert(w.kind == 0);
    assert(find(out, ":60F:C250101EUR1000,00") >= 0);
    // The writer output reads back with the field rules on.
    var s2: bank_statement::Statement[>..] = [];
    var e2: bank_statement::Entry[>..] = [];
    var b2: bank_statement::Balance[>..] = [];
    var n2: bank_statement::Note[>..] = [];
    var xbuf34: u8[>..] = [];
    let g = bank_statement::parse_mt940(out, lim, ropts, s2, e2, b2, n2, xbuf34);
    if g.kind != 0 { print("FAIL mt940 reread ", bank_statement::kind_name(g.kind), " line ", g.line, " ", g.tag, " ", g.detail, "\n"); }
    assert(g.kind == 0);
    assert(s2.len == 1 && e2.len == 2 && b2.len == 3);
    assert(s2[0].reference == "STMT001" && s2[0].account == "DE89370400440532013000");
    assert(s2[0].number == "00001" && s2[0].sequence == "001");
    assert(e2[0].amount.minor == 50000 && e2[0].mark == "C" && e2[0].bank_ref == "BANKREF1");
    assert(e2[0].supplementary == "SUPPLEMENT" && e2[0].narrative == ens[0].narrative);
    assert(e2[1].customer_ref == "CHK123" && e2[1].entry_date.year == 0);
    assert(s2[0].available.amount.minor == 129950);
    // A narrative line that starts with a colon would start a tag.
    ens[0].narrative = "line one\n:20:EVIL";
    var r1: u8[>..] = [];
    assert(bank_statement::write_mt940(sts, ens, lim, r1).kind == bank_statement::F_SYNTAX);
    ens[0].narrative = "a{b\x00";
    var r2: u8[>..] = [];
    assert(bank_statement::write_mt940(sts, ens, lim, r2).kind == bank_statement::F_SYNTAX);
    // A byte outside the SWIFT set is a fault.
    ens[0].narrative = "caf\xC3\xA9";
    var r3: u8[>..] = [];
    assert(bank_statement::write_mt940(sts, ens, lim, r3).kind == bank_statement::F_SYNTAX);
    // A line over 65 characters, and more than six lines, are faults.
    var long: u8[>..] = [];
    bank_statement::put_num(long, 0, 66);
    ens[0].narrative = long;
    var r4: u8[>..] = [];
    assert(bank_statement::write_mt940(sts, ens, lim, r4).kind == bank_statement::F_SYNTAX);
    ens[0].narrative = "1\n2\n3\n4\n5\n6\n7";
    var r5: u8[>..] = [];
    assert(bank_statement::write_mt940(sts, ens, lim, r5).kind != 0);
    ens[0].narrative = "ok";
    // A reference that holds // is a fault.
    ens[0].customer_ref = "A//B";
    var r6: u8[>..] = [];
    assert(bank_statement::write_mt940(sts, ens, lim, r6).kind == bank_statement::F_SYNTAX);
    ens[0].customer_ref = "NONREF";
    // Balances that do not add up are a fault.
    ens[0].amount.minor = ens[0].amount.minor + 1;
    var r7: u8[>..] = [];
    assert(bank_statement::write_mt940(sts, ens, lim, r7).kind == bank_statement::F_BALANCE);
    ens[0].amount.minor = ens[0].amount.minor - 1;
    // A reference over 16 characters is a fault and is never cut.
    sts[0].reference = "12345678901234567";
    var r8: u8[>..] = [];
    assert(bank_statement::write_mt940(sts, ens, lim, r8).kind != 0);
}
