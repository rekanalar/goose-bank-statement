// The tests of the group country.
namespace country_tests;

import std;
import os;
import xml from "rekanalar/goose-xml@v2.0.0";
import process from "rekanalar/goose-process@v1.0.0";
import bank_statement from "..";
import finance from "rekanalar/goose-finance@v0.1.0";
import statement_checks;
import sample_texts;

fn test_country() {
    assert(bank_statement::country_known("USA") && bank_statement::country_known("FRA") && bank_statement::country_known("ZWE"));
    assert(bank_statement::country_known("ABW") && bank_statement::country_known("SSD"));
    assert(!bank_statement::country_known("XKX") && !bank_statement::country_known("usa") && !bank_statement::country_known("US") && !bank_statement::country_known(""));
    // Every code of the table is found, so the table is sorted.
    for c in bank_statement::COUNTRY_CODES { assert(bank_statement::country_known(c)); }
    assert(bank_statement::COUNTRY_CODES.len == 250);
    let lim = bank_statement::default_limits();
    let at = find(sample_texts::OFX_EXTRA, "<COUNTRY>FRA");
    assert(at > 0);
    var tb: u8[>..] = [];
    bank_statement::put(tb, sample_texts::OFX_EXTRA[..at]);
    bank_statement::put(tb, "<COUNTRY>ZZZ");
    bank_statement::put(tb, sample_texts::OFX_EXTRA[at + 12..]);
    let text: const u8[:] = tb;
    var sts: bank_statement::Statement[>..] = [];
    var ens: bank_statement::Entry[>..] = [];
    var bals: bank_statement::Balance[>..] = [];
    var notes: bank_statement::Note[>..] = [];
    var buf: u8[>..] = [];
    // The reader accepts an unknown country by default and refuses it on request.
    let lax = bank_statement::OfxOptions { .. };
    assert(bank_statement::parse_ofx(text, lim, lax, sts, ens, bals, notes, buf).kind == 0);
    var s2: bank_statement::Statement[>..] = [];
    var e2: bank_statement::Entry[>..] = [];
    var b2: bank_statement::Balance[>..] = [];
    var n2: bank_statement::Note[>..] = [];
    var u2: u8[>..] = [];
    let strict = bank_statement::OfxOptions { check_country: true, .. };
    assert(bank_statement::parse_ofx(text, lim, strict, s2, e2, b2, n2, u2).kind == bank_statement::F_SYNTAX);
    // The writer always refuses it.
    var out: u8[>..] = [];
    assert(bank_statement::write_ofx(sts, ens, notes, statement_checks::ofx_wopts(102), lim, out).kind == bank_statement::F_SYNTAX);
}
