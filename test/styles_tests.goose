// The tests of the group styles.
namespace styles_tests;

import std;
import os;
import xml from "rekanalar/goose-xml@v2.0.0";
import process from "rekanalar/goose-process@v1.0.0";
import bank_statement from "..";
import finance from "rekanalar/goose-finance@v0.1.0";
import common;

fn test_styles() {
    let c20 = "01234567890123456789";
    let c40 = "0123456789012345678901234567890123456789";
    let b20 = "01234567890123456789";
    assert(common::style_kind(bank_statement::STYLE_SWIFT, c20, "") == bank_statement::F_SYNTAX);
    assert(common::style_kind(bank_statement::STYLE_ASNB, c20, "") == 0);
    assert(common::style_kind(bank_statement::STYLE_ASNB, c40, "") == bank_statement::F_SYNTAX);
    assert(common::style_kind(bank_statement::STYLE_GLS, c40, "") == 0);
    assert(common::style_kind(bank_statement::STYLE_GLS, c40, b20) == 0);
    assert(common::style_kind(bank_statement::STYLE_GLS, c40, "0123456789012345678901234") == bank_statement::F_SYNTAX);
    assert(common::style_kind(bank_statement::STYLE_ASNB, c20, b20) == bank_statement::F_SYNTAX);
    assert(common::style_kind(7, c20, "") == bank_statement::F_SYNTAX);
}

fn test_transcode() {
    let lim = bank_statement::default_limits();
    var out: u8[>..] = [];
    // euro, caf\xe9, quotes and dash
    assert(bank_statement::decode_charset(bank_statement::CS_CP1252, "\x80 caf\xE9 \x93x\x94 \x96", lim, out).kind == 0);
    assert(out == "\xE2\x82\xAC caf\xC3\xA9 \xE2\x80\x9Cx\xE2\x80\x9D \xE2\x80\x93");
    var back: u8[>..] = [];
    assert(bank_statement::encode_charset(bank_statement::CS_CP1252, out, lim, back).kind == 0);
    assert(back == "\x80 caf\xE9 \x93x\x94 \x96");
    // Latin-1 keeps 0x80 to 0x9F as control characters; Windows-1252 does not.
    var l1: u8[>..] = [];
    assert(bank_statement::decode_charset(bank_statement::CS_LATIN1, "\x80\xE9", lim, l1).kind == 0);
    assert(l1 == "\xC2\x80\xC3\xA9");
    // The five undefined bytes are faults.
    var u: u8[>..] = [];
    assert(bank_statement::decode_charset(bank_statement::CS_CP1252, "a\x81", lim, u).kind == bank_statement::F_SYNTAX);
    assert(bank_statement::decode_charset(bank_statement::CS_CP1252, "\x8D", lim, u).kind == bank_statement::F_SYNTAX);
    assert(bank_statement::decode_charset(bank_statement::CS_CP1252, "\x8F", lim, u).kind == bank_statement::F_SYNTAX);
    assert(bank_statement::decode_charset(bank_statement::CS_CP1252, "\x90", lim, u).kind == bank_statement::F_SYNTAX);
    assert(bank_statement::decode_charset(bank_statement::CS_CP1252, "\x9D", lim, u).kind == bank_statement::F_SYNTAX);
    // Every other byte round trips.
    var all: u8[>..] = [];
    var b = 0;
    while b < 256 {
        if b != 0x81 && b != 0x8D && b != 0x8F && b != 0x90 && b != 0x9D { all.push(b as u8); }
        b += 1;
    }
    var dec: u8[>..] = [];
    assert(bank_statement::decode_charset(bank_statement::CS_CP1252, all, lim, dec).kind == 0);
    var enc: u8[>..] = [];
    assert(bank_statement::encode_charset(bank_statement::CS_CP1252, dec, lim, enc).kind == 0);
    assert(enc == all);
    // A character that the charset lacks, and bad UTF-8, are faults.
    var e1: u8[>..] = [];
    assert(bank_statement::encode_charset(bank_statement::CS_CP1252, "\xD0\x96", lim, e1).kind == bank_statement::F_SYNTAX);
    assert(bank_statement::encode_charset(bank_statement::CS_LATIN1, "\xE2\x82\xAC", lim, e1).kind == bank_statement::F_SYNTAX);
    assert(bank_statement::encode_charset(bank_statement::CS_CP1252, "\xC3", lim, e1).kind == bank_statement::F_SYNTAX);
    assert(bank_statement::encode_charset(bank_statement::CS_CP1252, "\xC0\x80", lim, e1).kind == bank_statement::F_SYNTAX);
    assert(bank_statement::encode_charset(bank_statement::CS_CP1252, "\xC2\x81", lim, e1).kind == bank_statement::F_SYNTAX);
    assert(bank_statement::decode_charset(9, "a", lim, e1).kind == bank_statement::F_SYNTAX);
    // The size limit holds.
    var small = bank_statement::default_limits();
    small.max_input = 3;
    var e2: u8[>..] = [];
    assert(bank_statement::decode_charset(bank_statement::CS_CP1252, "\x80\x80", small, e2).kind == bank_statement::F_LIMIT);
    // The header names the charset.
    assert(bank_statement::header_charset("OFXHEADER:100\nCHARSET:1252\nCOMPRESSION:NONE\n") == bank_statement::CS_CP1252);
    assert(bank_statement::header_charset("CHARSET: ISO-8859-1\r\n") == bank_statement::CS_LATIN1);
    assert(bank_statement::header_charset("CHARSET:NONE\n") == 0);
    assert(bank_statement::header_charset("<OFX>") == 0);
}
