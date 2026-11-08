// Writes a sign-on request with the element tree writer.
// Run with: goose run examples/ofx_tree.goose

import std;
import xml from "rekanalar/goose-xml@v2.0.0";
import process from "rekanalar/goose-process@v1.0.0";
import bank_statement from "..";

fn main() {
    var tree: bank_statement::OfxNode[>..] = [
        bank_statement::OfxNode { depth: 0, name: "SIGNONMSGSRQV1", text: "" },
        bank_statement::OfxNode { depth: 1, name: "SONRQ", text: "" },
        bank_statement::OfxNode { depth: 2, name: "DTCLIENT", text: "20200101" },
        bank_statement::OfxNode { depth: 2, name: "USERID", text: "alice" },
        bank_statement::OfxNode { depth: 2, name: "LANGUAGE", text: "ENG" },
    ];
    let lim = bank_statement::default_limits();
    let opts = bank_statement::OfxWriteOptions {
        version: 211, credit_card: false, close_leaves: false, indent: true,
        server_date: bank_statement::Date { year: 2020, month: 1, day: 1 },
        org: "", fid: "", bank_id: "", account_type: "", currency: "", loose_elements: false,
    };
    var out: u8[>..] = [];
    let f = bank_statement::write_ofx_tree(tree, opts, lim, out);
    if f.kind != 0 {
        print("error: ", bank_statement::kind_name(f.kind), " ", f.detail, "\n");
        return 1;
    }
    print(out);
    return 0;
}
