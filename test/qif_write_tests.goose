// The tests of the group qif_write.
namespace qif_write_tests;

import std;
import os;
import xml from "rekanalar/goose-xml@v2.0.0";
import process from "rekanalar/goose-process@v1.0.0";
import bank_statement from "..";
import finance from "rekanalar/goose-finance@v0.1.0";
import common;

fn test_write_qif() {
    common::qif_round_trip(0);
    common::qif_round_trip(bank_statement::DATE_DMY);
    common::qif_round_trip(bank_statement::DATE_YMD);
    let lim = bank_statement::default_limits();
    let ropts = bank_statement::QifOptions { date_order: bank_statement::DATE_MDY, .. };
    var recs: bank_statement::QifRecord[>..] = [];
    var spl: bank_statement::QifSplit[>..] = [];
    var ext: bank_statement::QifField[>..] = [];
    var xbuf32: u8[>..] = [];
    var xbuf32_pre: u8[>..] = [];
    assert(bank_statement::parse_qif(common::QIF1, lim, ropts, recs, spl, ext, xbuf32_pre).kind == 0);
    let wopts = bank_statement::QifWriteOptions { date_order: 0 };
    // A line end in a text is a fault: the value cannot add a field.
    recs[0].payee = "Eve\nT999.00";
    var out: u8[>..] = [];
    assert(bank_statement::write_qif(recs, spl, ext, wopts, lim, out).kind == bank_statement::F_SYNTAX);
    recs[0].payee = "Eve";
    recs[0].memo = "a\r^\r";
    var o2: u8[>..] = [];
    assert(bank_statement::write_qif(recs, spl, ext, wopts, lim, o2).kind == bank_statement::F_SYNTAX);
    recs[0].memo = "ok";
    // A text that is too long is a fault. It is never cut.
    var big: u8[>..] = [];
    bank_statement::put_num(big, 0, 5000);
    recs[0].memo = big;
    var o3: u8[>..] = [];
    assert(bank_statement::write_qif(recs, spl, ext, wopts, lim, o3).kind == bank_statement::F_LIMIT);
    recs[0].memo = "ok";
    // The splits must add up to the amount.
    spl[0].amount.minor = spl[0].amount.minor + 1;
    var o4: u8[>..] = [];
    assert(bank_statement::write_qif(recs, spl, ext, wopts, lim, o4).kind == bank_statement::F_TOTAL);
    spl[0].amount.minor = spl[0].amount.minor - 1;
    // A field code cannot start a header or end the record.
    ext[0].code = '^';
    var o5: u8[>..] = [];
    assert(bank_statement::write_qif(recs, spl, ext, wopts, lim, o5).kind == bank_statement::F_SYNTAX);
    ext[0].code = '!';
    var o6: u8[>..] = [];
    assert(bank_statement::write_qif(recs, spl, ext, wopts, lim, o6).kind == bank_statement::F_SYNTAX);
    ext[0].code = 'A';
    // A date that does not exist is a fault.
    recs[0].date.day = 31;
    recs[0].date.month = 2;
    var o7: u8[>..] = [];
    assert(bank_statement::write_qif(recs, spl, ext, wopts, lim, o7).kind == bank_statement::F_DATE);
    // The most negative amount and the other exponents.
    var a: u8[>..] = [];
    bank_statement::put_amount(a, -9223372036854775808, 2, '.');
    assert(a == "-92233720368547758.08");
    var b: u8[>..] = [];
    bank_statement::put_amount(b, 5, 3, ',');
    assert(b == "0,005");
    var c: u8[>..] = [];
    bank_statement::put_amount(c, -7, 0, '.');
    assert(c == "-7");
}

fn test_write_qif_lists() {
    let text: const u8[:] = "!Account\nNChecking\nTBank\n^\n!Type:Cat\nNFood:Dining\nE\n^\n!Type:Class\nNHome\n^\n!Type:Bank\nD01/02/2025\nT-5.00\nPShop\n^\n";
    let lim = bank_statement::default_limits();
    let ropts = bank_statement::QifOptions { date_order: bank_statement::DATE_MDY, .. };
    var recs: bank_statement::QifRecord[>..] = [];
    var spl: bank_statement::QifSplit[>..] = [];
    var ext: bank_statement::QifField[>..] = [];
    var xbuf36: u8[>..] = [];
    var xbuf36_pre: u8[>..] = [];
    assert(bank_statement::parse_qif(text, lim, ropts, recs, spl, ext, xbuf36_pre).kind == 0);
    var out: u8[>..] = [];
    let wopts = bank_statement::QifWriteOptions { date_order: 0 };
    assert(bank_statement::write_qif(recs, spl, ext, wopts, lim, out).kind == 0);
    assert(out == text);
    // A section the writer does not write is a fault.
    recs[0].section = bank_statement::Q_INVST;
    var o2: u8[>..] = [];
    assert(bank_statement::write_qif(recs, spl, ext, wopts, lim, o2).kind == bank_statement::F_SYNTAX);
}
