// The tests of the group hostile.
namespace hostile_tests;

import std;
import os;
import xml from "rekanalar/goose-xml@v2.0.0";
import process from "rekanalar/goose-process@v1.0.0";
import bank_statement from "..";
import finance from "rekanalar/goose-finance@v0.1.0";
import common;

fn test_hostile() {
    var lim = bank_statement::default_limits();
    // Input above max_input.
    lim.max_input = 10;
    common::run_limited(":20:ABCDEFGHIJKLMNOP\n", lim, 1);
    lim = bank_statement::default_limits();
    // A line above max_line.
    var big: u8[>..] = [];
    format(big, ":20:");
    for i in 5000 { big.push('A'); }
    format(big, "\n");
    common::run_limited(big[..], lim, 1);
    // A field above max_field.
    lim.max_field = 8;
    common::run_limited(":20:ABCDEFGHIJ\n", lim, 1);
    lim = bank_statement::default_limits();
    // Counts: statements, entries.
    lim.max_statements = 1;
    common::run_limited(":20:A\n:20:B\n", lim, 1);
    lim = bank_statement::default_limits();
    lim.max_entries = 1;
    common::run_limited(":20:A\n:60F:C250101EUR0,00\n:61:250101C1,00NTRFX\n:61:250101C1,00NTRFX\n", lim, 1);
    lim = bank_statement::default_limits();
    // Nesting of blocks.
    common::run_limited("{1:{{{{{{{{{{{{{{{{x}}}}}}}}}}}}}}}}\n", lim, 1);
    common::run_limited("{1:{abc}\n", lim, 2);
    common::run_limited("{9}\n", lim, 2);
    // A NUL byte, a bare tag and an empty file.
    common::run_limited(":20:A\n\0\n", lim, 2);
    common::run_limited(":20\n", lim, 2);
    common::run_limited("", lim, 0);
    common::run_limited("\n\n\r\n", lim, 0);
    // A number of 400 digits is an overflow, not a wrap.
    var num: u8[>..] = [];
    format(num, ":20:A\n:60F:C250101EUR");
    for i in 400 { num.push('9'); }
    format(num, ",00\n");
    common::run_limited(num[..], lim, 5);
    // The sum of the entries overflows.
    common::run_mt940(":20:A\n:60F:C250101EUR0,00\n:61:250101C92233720368547758,07NTRFX\n:61:250101C92233720368547758,07NTRFX\n:62F:C250101EUR0,00\n", false, 5, "61");
    // Bytes above 127 pass through into text fields.
    common::run_limited(":20:A\xff\xfe\n:25:caf\xc3\xa9\n", lim, 0);
}

fn test_hostile_qif() {
    var lim = bank_statement::default_limits();
    let opts = bank_statement::QifOptions { date_order: 1, .. };
    var recs: bank_statement::QifRecord[>..] = [];
    var spl: bank_statement::QifSplit[>..] = [];
    var ext: bank_statement::QifField[>..] = [];
    lim.max_records = 2;
    var xbuf25: u8[>..] = [];
    let f = bank_statement::parse_qif("!Type:Bank\nT1\n^\nT2\n^\nT3\n^\n", lim, opts, recs, spl, ext, xbuf25);
    assert(f.kind == 1);
    lim = bank_statement::default_limits();
    lim.max_splits = 1;
    var recs2: bank_statement::QifRecord[>..] = [];
    var spl2: bank_statement::QifSplit[>..] = [];
    var ext2: bank_statement::QifField[>..] = [];
    var xbuf26: u8[>..] = [];
    let g = bank_statement::parse_qif("!Type:Bank\nSa\n$1\nSb\n$2\n^\n", lim, opts, recs2, spl2, ext2, xbuf26);
    assert(g.kind == 1);
    common::run_qif("!Type:Bank\nT\0\n", 1, 2);
    common::run_qif("!Type:Bank\nT99999999999999999999999999999\n^\n", 1, 5);
}
