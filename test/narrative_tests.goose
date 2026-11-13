// The tests of the group narrative.
namespace narrative_tests;

import std;
import os;
import xml from "rekanalar/goose-xml@v2.0.0";
import process from "rekanalar/goose-process@v1.0.0";
import bank_statement from "..";
import finance from "rekanalar/goose-finance@v0.1.0";

fn test_narrative() {
    let lim = bank_statement::default_limits();
    var out: bank_statement::NarrativeField[>..] = [];
    let k, f = bank_statement::split_narrative("020?00BANK TRANSFER?20PURPOSE?21LINE 2?32NAME", lim, out);
    assert(f.kind == 0 && k == bank_statement::NARR_SUBFIELD);
    assert(out.len == 5);
    assert(out[0].key == "code" && out[0].value == "020");
    assert(out[1].key == "00" && out[1].value == "BANK TRANSFER");
    assert(out[2].key == "20" && out[2].value == "PURPOSE");
    assert(out[4].key == "32" && out[4].value == "NAME");
}

fn test_narrative_pairs() {
    let lim = bank_statement::default_limits();
    var out: bank_statement::NarrativeField[>..] = [];
    let k, f = bank_statement::split_narrative("/EREF/ABC123/IBAN/DE89370400440532013000/REMI/Invoice 1/2/", lim, out);
    assert(f.kind == 0 && k == bank_statement::NARR_PAIRS);
    assert(out.len == 3);
    assert(out[0].key == "EREF" && out[0].value == "ABC123");
    assert(out[1].key == "IBAN" && out[1].value == "DE89370400440532013000");
    assert(out[2].key == "REMI" && out[2].value == "Invoice 1/2");
}

fn test_narrative_plain() {
    let lim = bank_statement::default_limits();
    var out: bank_statement::NarrativeField[>..] = [];
    let k, f = bank_statement::split_narrative("just some words", lim, out);
    assert(f.kind == 0 && k == bank_statement::NARR_PLAIN && out.len == 0);
}
