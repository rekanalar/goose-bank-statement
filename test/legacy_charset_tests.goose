// The tests of the group legacy_charset.
namespace legacy_charset_tests;

import std;
import os;
import xml from "rekanalar/goose-xml@v2.0.0";
import process from "rekanalar/goose-process@v1.0.0";
import bank_statement from "..";
import finance from "rekanalar/goose-finance@v0.1.0";

fn test_legacy_charset() {
    let lim = bank_statement::default_limits();
    // MT940: the payee holds a Windows-1252 smart quote.
    var text: const u8[:] = ":20:S\n:25:A\n:28C:1/1\n:60F:C250101EUR1,00\n:61:250102C10,00NTRFREF\n:86:Caf\x92 Ltd\n:62F:C250102EUR11,00\n";
    var opts = bank_statement::Mt940Options { skip_balance_check: false, check_fields: false, style: 0 };
    opts.charset = bank_statement::CS_CP1252;
    var sts: bank_statement::Statement[>..] = [];
    var ens: bank_statement::Entry[>..] = [];
    var bals: bank_statement::Balance[>..] = [];
    var notes: bank_statement::Note[>..] = [];
    var buf: u8[>..] = [];
    assert(bank_statement::parse_mt940(text, lim, opts, sts, ens, bals, notes, buf).kind == 0);
    assert(ens.len == 1 && ens[0].narrative == "Caf\xe2\x80\x99 Ltd");
    // The field rules hold the SWIFT character set, so the decoded
    // text faults while the rules are on.
    var optsf = bank_statement::Mt940Options { skip_balance_check: false, check_fields: true, style: 0 };
    optsf.charset = bank_statement::CS_CP1252;
    var stsf: bank_statement::Statement[>..] = [];
    var ensf: bank_statement::Entry[>..] = [];
    var balsf: bank_statement::Balance[>..] = [];
    var notesf: bank_statement::Note[>..] = [];
    var buff: u8[>..] = [];
    assert(bank_statement::parse_mt940(text, lim, optsf, stsf, ensf, balsf, notesf, buff).kind == bank_statement::F_SYNTAX);
    // Without the charset the raw byte stays. The field rules are off,
    // because the raw byte leaves the SWIFT set.
    var opts0 = bank_statement::Mt940Options { skip_balance_check: false, check_fields: false, style: 0 };
    var sts2: bank_statement::Statement[>..] = [];
    var ens2: bank_statement::Entry[>..] = [];
    var bals2: bank_statement::Balance[>..] = [];
    var notes2: bank_statement::Note[>..] = [];
    var buf2: u8[>..] = [];
    assert(bank_statement::parse_mt940(text, lim, opts0, sts2, ens2, bals2, notes2, buf2).kind == 0);
    assert(ens2.len == 1 && ens2[0].narrative == "Caf\x92 Ltd");
    // QIF: the payee holds the same byte.
    var qtext: const u8[:] = "!Type:Bank\nD01/02/2020\nT-10.00\nPCaf\x92 Ltd\n^\n";
    var qopts = bank_statement::QifOptions { .. };
    qopts.charset = bank_statement::CS_CP1252;
    qopts.date_order = bank_statement::DATE_MDY;
    var recs: bank_statement::QifRecord[>..] = [];
    var spl: bank_statement::QifSplit[>..] = [];
    var ext: bank_statement::QifField[>..] = [];
    var qbuf: u8[>..] = [];
    assert(bank_statement::parse_qif(qtext, lim, qopts, recs, spl, ext, qbuf).kind == 0);
    assert(recs.len == 1 && recs[0].payee == "Caf\xe2\x80\x99 Ltd");
    var qopts0 = bank_statement::QifOptions { .. };
    qopts0.date_order = bank_statement::DATE_MDY;
    var recs2: bank_statement::QifRecord[>..] = [];
    var spl2: bank_statement::QifSplit[>..] = [];
    var ext2: bank_statement::QifField[>..] = [];
    var qbuf2: u8[>..] = [];
    assert(bank_statement::parse_qif(qtext, lim, qopts0, recs2, spl2, ext2, qbuf2).kind == 0);
    assert(recs2.len == 1 && recs2[0].payee == "Caf\x92 Ltd");
}
