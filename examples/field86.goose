// Reads the structured values of a :86: narrative.
// Run with: goose run examples/field86.goose

import std;
import xml from "rekanalar/goose-xml@v2.0.0";
import process from "rekanalar/goose-process@v1.0.0";
import bank_statement from "..";

fn main() {
    let lim = bank_statement::default_limits();
    var extra: bank_statement::DialectValue[>..] = [];
    var buf: u8[>..] = [];
    let f, fe = bank_statement::parse_field_86("?00GVC171?10EREF-7?30DEUTDEFF?31DE89370400440532013000?32Acme Corp?20invoice 41?99custom", lim, extra, buf);
    if fe.kind != 0 {
        print("error: ", bank_statement::kind_name(fe.kind), " ", fe.detail, "\n");
        return 1;
    }
    print("code ", f.transaction_code, " end-to-end ", f.end_to_end_id);
    print("  bic ", f.counterparty_bic, " iban ", f.counterparty_iban);
    print("  creditor ", f.creditor_name, " remittance ", f.remittance_info);
    var i: i64 = 0;
    while i < f.tag_count {
        print("  ", extra[i].key, " ", extra[i].value);
        i += 1;
    }
    return 0;
}
