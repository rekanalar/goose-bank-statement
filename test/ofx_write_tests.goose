// The tests of the group ofx_write.
namespace ofx_write_tests;

import std;
import os;
import xml from "rekanalar/goose-xml@v2.0.0";
import process from "rekanalar/goose-process@v1.0.0";
import bank_statement from "..";
import finance from "rekanalar/goose-finance@v0.1.0";
import statement_checks;
import sample_texts;

fn test_write_ofx() {
    statement_checks::ofx_round_trip(statement_checks::ofx_wopts(0));
    statement_checks::ofx_round_trip(statement_checks::ofx_wopts(203));
    var o = statement_checks::ofx_wopts(151);
    o.close_leaves = true;
    statement_checks::ofx_round_trip(o);
    var p = statement_checks::ofx_wopts(220);
    p.indent = true;
    statement_checks::ofx_round_trip(p);
    var q = statement_checks::ofx_wopts(102);
    q.indent = true;
    statement_checks::ofx_round_trip(q);
    let lim = bank_statement::default_limits();
    let ropts = bank_statement::OfxOptions { .. };
    var sts: bank_statement::Statement[>..] = [];
    var ens: bank_statement::Entry[>..] = [];
    var bals: bank_statement::Balance[>..] = [];
    var notes: bank_statement::Note[>..] = [];
    var buf: u8[>..] = [];
    assert(bank_statement::parse_ofx(sample_texts::OFX_V1, lim, ropts, sts, ens, bals, notes, buf).kind == 0);
    // The header of version 1 ends with a blank line.
    var h: u8[>..] = [];
    assert(bank_statement::write_ofx(sts, ens, notes, statement_checks::ofx_wopts(0), lim, h).kind == 0);
    assert(h[..13] == "OFXHEADER:100");
    assert(find(h, "\r\n\r\n<OFX>") > 0);
    // The leaves stay open in version 1 and close in version 2.
    assert(find(h, "<CODE>0<SEVERITY>") > 0);
    var h2: u8[>..] = [];
    assert(bank_statement::write_ofx(sts, ens, notes, statement_checks::ofx_wopts(203), lim, h2).kind == 0);
    assert(find(h2, "<CODE>0</CODE>") > 0 && find(h2, "<?xml") == 0);
    // A hostile memo cannot add a transaction, in either form.
    ens[1].narrative = "</STMTTRN><STMTTRN><TRNAMT>999<MEMO>a&b";
    var evil: u8[>..] = [];
    assert(bank_statement::write_ofx(sts, ens, notes, statement_checks::ofx_wopts(102), lim, evil).kind == 0);
    assert(find(evil, "</STMTTRN><STMTTRN><TRNAMT>999") < 0);
    var s2: bank_statement::Statement[>..] = [];
    var e2: bank_statement::Entry[>..] = [];
    var b2: bank_statement::Balance[>..] = [];
    var n2: bank_statement::Note[>..] = [];
    var u2: u8[>..] = [];
    assert(bank_statement::parse_ofx(evil, lim, ropts, s2, e2, b2, n2, u2).kind == 0);
    assert(e2.len == 2);
    assert(e2[1].narrative == "</STMTTRN><STMTTRN><TRNAMT>999<MEMO>a&b");
    // A byte above 127 becomes a numeric reference and reads back.
    ens[1].narrative = "caf\xC3\xA9";
    var uni: u8[>..] = [];
    assert(bank_statement::write_ofx(sts, ens, notes, statement_checks::ofx_wopts(102), lim, uni).kind == 0);
    assert(find(uni, "caf&#233;") > 0);
    // Refusals.
    ens[1].narrative = "bad\x00byte";
    var r1: u8[>..] = [];
    assert(bank_statement::write_ofx(sts, ens, notes, statement_checks::ofx_wopts(102), lim, r1).kind == bank_statement::F_SYNTAX);
    ens[1].narrative = "\xFF";
    var r2: u8[>..] = [];
    assert(bank_statement::write_ofx(sts, ens, notes, statement_checks::ofx_wopts(102), lim, r2).kind == bank_statement::F_SYNTAX);
    var long: u8[>..] = [];
    bank_statement::put_num(long, 0, 256);
    ens[1].narrative = long;
    var r3: u8[>..] = [];
    assert(bank_statement::write_ofx(sts, ens, notes, statement_checks::ofx_wopts(102), lim, r3).kind == bank_statement::F_LIMIT);
    ens[1].narrative = "ok";
    ens[1].type_id = "BOGUS";
    var r4: u8[>..] = [];
    assert(bank_statement::write_ofx(sts, ens, notes, statement_checks::ofx_wopts(102), lim, r4).kind == bank_statement::F_SYNTAX);
    ens[1].type_id = "CREDIT";
    ens[1].entry_ref = "";
    var r5: u8[>..] = [];
    assert(bank_statement::write_ofx(sts, ens, notes, statement_checks::ofx_wopts(102), lim, r5).kind == bank_statement::F_SYNTAX);
    ens[1].entry_ref = "TX2";
    var bad = statement_checks::ofx_wopts(102);
    bad.server_date = bank_statement::Date { year: 2020, month: 13, day: 1 };
    var r6: u8[>..] = [];
    assert(bank_statement::write_ofx(sts, ens, notes, bad, lim, r6).kind == bank_statement::F_DATE);
    var r7: u8[>..] = [];
    assert(bank_statement::write_ofx(sts, ens, notes, statement_checks::ofx_wopts(999), lim, r7).kind == bank_statement::F_SYNTAX);
    // A statement without a closing balance is refused.
    sts[0].closing.kind = 0;
    var r8: u8[>..] = [];
    assert(bank_statement::write_ofx(sts, ens, notes, statement_checks::ofx_wopts(102), lim, r8).kind == bank_statement::F_SYNTAX);
}

fn test_write_ofx_mixed() {
    let lim = bank_statement::default_limits();
    let ropts = bank_statement::OfxOptions { .. };
    // One bank statement and one credit card statement.
    var sts: bank_statement::Statement[>..] = [];
    var ens: bank_statement::Entry[>..] = [];
    var bals: bank_statement::Balance[>..] = [];
    var notes: bank_statement::Note[>..] = [];
    var buf: u8[>..] = [];
    assert(bank_statement::parse_ofx(sample_texts::OFX_V1, lim, ropts, sts, ens, bals, notes, buf).kind == 0);
    assert(!sts[0].credit_card);
    var csts: bank_statement::Statement[>..] = [];
    var cens: bank_statement::Entry[>..] = [];
    var cbals: bank_statement::Balance[>..] = [];
    var cnotes: bank_statement::Note[>..] = [];
    var cbuf: u8[>..] = [];
    assert(bank_statement::parse_ofx(sample_texts::OFX_CC, lim, ropts, csts, cens, cbals, cnotes, cbuf).kind == 0);
    assert(csts[0].credit_card);
    // Merge the credit card statement into the same arrays.
    csts[0].entry_start = ens.len as i32;
    csts[0].balance_start = bals.len as i32;
    var i: i64 = 0;
    while i < cens.len { ens.push(cens[i]); i += 1; }
    i = 0;
    while i < cbals.len { bals.push(cbals[i]); i += 1; }
    csts[0].entry_count = cens.len as i32;
    csts[0].balance_count = cbals.len as i32;
    sts.push(csts[0]);
    // One call writes both message sets, bank first.
    var out: u8[>..] = [];
    assert(bank_statement::write_ofx(sts, ens, notes, statement_checks::ofx_wopts(102), lim, out).kind == 0);
    let b = find(out, "<BANKMSGSRSV1>");
    let c = find(out, "<CREDITCARDMSGSRSV1>");
    assert(b > 0 && c > b);
    // The output reads back to the same two statements.
    var s2: bank_statement::Statement[>..] = [];
    var e2: bank_statement::Entry[>..] = [];
    var b2: bank_statement::Balance[>..] = [];
    var n2: bank_statement::Note[>..] = [];
    var u2: u8[>..] = [];
    assert(bank_statement::parse_ofx(out, lim, ropts, s2, e2, b2, n2, u2).kind == 0);
    assert(s2.len == 2);
    assert(!s2[0].credit_card && s2[1].credit_card);
    assert(s2[0].account == sts[0].account && s2[1].account == csts[0].account);
    // The credit card flag alone still puts every statement into one set.
    var one: u8[>..] = [];
    var wopts = statement_checks::ofx_wopts(102);
    wopts.credit_card = true;
    assert(bank_statement::write_ofx(sts, ens, notes, wopts, lim, one).kind == 0);
    assert(find(one, "<BANKMSGSRSV1>") < 0 && find(one, "<CREDITCARDMSGSRSV1>") > 0);
}
