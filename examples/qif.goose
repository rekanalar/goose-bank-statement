// Reads a QIF file and prints its records.
// Run with: goose run examples/qif.goose

import std;
import xml from "rekanalar/goose-xml@v2.0.0";
import process from "rekanalar/goose-process@v1.0.0";
import bank_statement from "..";

fn main() {
    let text = "!Type:Bank\nD12/31'25\nT-1,234.56\nCX\nPAcme Corp\nLGroceries:Food/Home\n^\nD1/ 2'25\nT(50.00)\nSRent\n$-30.00\nSUtil\n$-20.00\n^\n";
    let lim = bank_statement::default_limits();
    // The order of the date parts is the caller's choice.
    let opts = bank_statement::QifOptions { date_order: bank_statement::DATE_MDY, .. };
    var recs: bank_statement::QifRecord[>..] = [];
    var spl: bank_statement::QifSplit[>..] = [];
    var ext: bank_statement::QifField[>..] = [];
    let f = bank_statement::parse_qif(text, lim, opts, recs, spl, ext);
    if f.kind != 0 {
        print("error: ", bank_statement::kind_name(f.kind), " line ", f.line, " ", f.detail);
        return 1;
    }
    for r in recs {
        print(r.date.year, "-", r.date.month, "-", r.date.day, " ", r.amount.minor, " ", r.payee, " splits ", r.split_count);
        let c = bank_statement::split_category(r.category);
        if c.name.len > 0 { print("  category ", c.name, " sub ", c.sub, " class ", c.class); }
    }
    return 0;
}
