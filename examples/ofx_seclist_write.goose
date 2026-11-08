// Writes a security list as an OFX file.
// Run with: goose run examples/ofx_seclist_write.goose

import std;
import xml from "rekanalar/goose-xml@v2.0.0";
import process from "rekanalar/goose-process@v1.0.0";
import finance from "rekanalar/goose-finance@v0.1.0";
import bank_statement from "..";

fn main() {
    let z = bank_statement::Rational { num: 0, den: 1 };
    let no_date = bank_statement::Date { year: 2020, month: 1, day: 31 };
    var secs: bank_statement::OfxSecurity[>..] = [
        bank_statement::OfxSecurity {
            kind: "STOCKINFO", id: "123456789", id_type: "CUSIP", name: "Acme", ticker: "ACME",
            fiid: "", rating: "", memo: "", currency: "USD", has_price: true,
            price: bank_statement::Rational { num: 25, den: 2 }, price_text: "",
            price_date: no_date, note_start: 0, note_count: 0,
        },
        bank_statement::OfxSecurity {
            kind: "MFINFO", id: "MF1", id_type: "ISIN", name: "Fund", ticker: "FUND",
            fiid: "", rating: "", memo: "", currency: "", has_price: false,
            price: z, price_text: "", price_date: bank_statement::no_date(),
            note_start: 0, note_count: 0,
        },
    ];
    var notes: bank_statement::Note[>..] = [];
    let lim = bank_statement::default_limits();
    var out: u8[>..] = [];
    let f = bank_statement::write_ofx_securities(secs, notes, bank_statement::OfxWriteOptions {
        version: 102, credit_card: false, close_leaves: false, indent: true,
        server_date: bank_statement::Date { year: 2020, month: 1, day: 1 },
        org: "", fid: "", bank_id: "", account_type: "", currency: "", loose_elements: false,
    }, lim, out);
    if f.kind != 0 {
        print("error: ", bank_statement::kind_name(f.kind), " ", f.detail, "\n");
        return 1;
    }
    print(out);
    return 0;
}
