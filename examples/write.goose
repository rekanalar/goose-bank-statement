// Reads a QIF file and writes it again with ISO dates.
// Run with: goose run examples/write.goose

import std;
import xml from "rekanalar/goose-xml@v2.0.0";
import process from "rekanalar/goose-process@v1.0.0";
import bank_statement from "..";

fn main() {
    let text = "!Type:Bank\nD12/31/2025\nT-1234.56\nCX\nPAcme Corp\nLGroceries\n^\n";
    let lim = bank_statement::default_limits();
    let ropts = bank_statement::QifOptions { date_order: bank_statement::DATE_MDY, .. };
    var recs: bank_statement::QifRecord[>..] = [];
    var spl: bank_statement::QifSplit[>..] = [];
    var ext: bank_statement::QifField[>..] = [];
    let f = bank_statement::parse_qif(text, lim, ropts, recs, spl, ext);
    if f.kind != 0 { print("error: ", f.detail, "\n"); return 1; }
    // Write the same records with ISO dates.
    var out: u8[>..] = [];
    let wopts = bank_statement::QifWriteOptions { date_order: bank_statement::DATE_YMD };
    let w = bank_statement::write_qif(recs, spl, ext, wopts, lim, out);
    if w.kind != 0 { print("error: ", w.detail, "\n"); return 1; }
    print(out);
    // A payee with a line end is refused: it could add a field.
    recs[0].payee = "Eve\nT999.00";
    var bad: u8[>..] = [];
    let r = bank_statement::write_qif(recs, spl, ext, wopts, lim, bad);
    print("refused: ", bank_statement::kind_name(r.kind), " ", r.detail, "\n");
    return 0;
}
