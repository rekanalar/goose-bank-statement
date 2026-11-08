// Sends an OFX sign-on request over HTTPS and prints the answer.
// Run with: goose run examples/ofx_fetch.goose

import std;
import xml from "rekanalar/goose-xml@v2.0.0";
import process from "rekanalar/goose-process@v1.0.0";
import finance from "rekanalar/goose-finance@v0.1.0";
import bank_statement from "..";

fn main() {
    var tree: bank_statement::OfxNode[>..] = [
        bank_statement::OfxNode { depth: 0, name: "SIGNONMSGSRQV1", text: "" },
        bank_statement::OfxNode { depth: 1, name: "SONRQ", text: "" },
        bank_statement::OfxNode { depth: 2, name: "DTCLIENT", text: "20200101" },
        bank_statement::OfxNode { depth: 2, name: "USERID", text: "alice" },
        bank_statement::OfxNode { depth: 2, name: "LANGUAGE", text: "ENG" },
        bank_statement::OfxNode { depth: 2, name: "APPID", text: "GOOSE" },
        bank_statement::OfxNode { depth: 2, name: "APPVER", text: "2600" },
    ];
    let lim = bank_statement::default_limits();
    let opts = bank_statement::OfxWriteOptions {
        version: 211, credit_card: false, close_leaves: false, indent: false,
        server_date: bank_statement::Date { year: 2020, month: 1, day: 1 },
        org: "", fid: "", bank_id: "", account_type: "", currency: "", loose_elements: false,
    };
    var req: u8[>..] = [];
    let f = bank_statement::write_ofx_tree(tree, opts, lim, req);
    if f.kind != 0 {
        print("error: ", bank_statement::kind_name(f.kind), " ", f.detail, "\n");
        return 1;
    }
    let fo = bank_statement::OfxFetch {
        url: "https://example.com/", timeout_ms: 15000, content_type: "", user_agent: "goose-bank-statement",
    };
    var body: u8[>..] = [];
    var buf: u8[>..] = [];
    let code, g = bank_statement::ofx_fetch(req, fo, lim, body, buf);
    if g.kind != 0 {
        print("error: ", bank_statement::kind_name(g.kind), " ", g.tag, " ", g.detail, "\n");
        return 1;
    }
    print("status ", code, " bytes ", body.len, "\n");
    return 0;
}
