// The tests of the group field86.
namespace field86_tests;

import std;
import os;
import xml from "rekanalar/goose-xml@v2.0.0";
import process from "rekanalar/goose-process@v1.0.0";
import bank_statement from "..";
import finance from "rekanalar/goose-finance@v0.1.0";

fn test_field86() {
    let lim = bank_statement::default_limits();
    var extra: bank_statement::DialectValue[>..] = [];
    var buf: u8[>..] = [];
    // The GVC codes.
    let f, fe = bank_statement::parse_field_86("?00GVC123?10EREF-1?30DEUTDEFF?31DE89370400440532013000?32Acme?33Corp?20line one?21line two?99odd", lim, extra, buf);
    if fe.kind != 0 { print("FAIL field86 ", bank_statement::kind_name(fe.kind), " ", fe.detail, "\n"); }
    assert(fe.kind == 0);
    assert(f.transaction_code == "GVC123" && f.end_to_end_id == "EREF-1");
    assert(f.counterparty_bic == "DEUTDEFF" && f.counterparty_iban == "DE89370400440532013000");
    assert(f.creditor_name == "Acme Corp");
    assert(f.remittance_info == "line one line two");
    assert(f.tag_count == 1 && extra[0].key == "?99" && extra[0].value == "odd");
    // The slash tags, the amounts and the extra tag.
    var e2: bank_statement::DialectValue[>..] = [];
    var b2: u8[>..] = [];
    let g, ge = bank_statement::parse_field_86("/EREF/E2E/OCMT/EUR12,34/CHGS/1,50/PURP/GPCS/BOGUS/xyz", lim, e2, b2);
    assert(ge.kind == 0);
    assert(g.end_to_end_id == "E2E" && g.purpose_code == "GPCS");
    assert(g.has_original_amount && g.original_amount.minor == 1234);
    assert(g.has_charges_amount && g.charges_amount.minor == 150);
    assert(g.tag_count == 1 && e2[0].key == "BOGUS" && e2[0].value == "xyz");
    // A REMI tag joins its parts. A placeholder BIC stays out.
    var e3: bank_statement::DialectValue[>..] = [];
    var b3: u8[>..] = [];
    let h, he = bank_statement::parse_field_86("/REMI/part one//REMI/part two//BIC/NOTPROVIDED", lim, e3, b3);
    assert(he.kind == 0);
    assert(h.remittance_info == "part one part two" && h.counterparty_bic == "");
    // The IBAN fallback finds the naked IBAN.
    var e4: bank_statement::DialectValue[>..] = [];
    var b4: u8[>..] = [];
    let k, ke = bank_statement::parse_field_86("pay to DE89370400440532013000 today", lim, e4, b4);
    assert(ke.kind == 0);
    assert(k.counterparty_iban == "DE89370400440532013000" && k.counterparty_bic == "");
    // The BIC fallback skips the placeholder.
    var e5: bank_statement::DialectValue[>..] = [];
    var b5: u8[>..] = [];
    let m, me = bank_statement::parse_field_86("via NOTPROVIDED or DEUTDEFFXXX", lim, e5, b5);
    assert(me.kind == 0);
    assert(m.counterparty_bic == "DEUTDEFFXXX");
    // An amount with a space parses. A bad amount stays out.
    var e6: bank_statement::DialectValue[>..] = [];
    var b6: u8[>..] = [];
    let n, ne = bank_statement::parse_field_86("/ORAMT/EUR 9,99//FEE/nope", lim, e6, b6);
    assert(ne.kind == 0);
    assert(n.has_original_amount && n.original_amount.minor == 999);
    assert(!n.has_charges_amount);
}
