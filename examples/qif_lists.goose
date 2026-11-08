// Reads the lists of a QIF file, then writes them back.
// Run with: goose run examples/qif_lists.goose

import std;
import xml from "rekanalar/goose-xml@v2.0.0";
import process from "rekanalar/goose-process@v1.0.0";
import finance from "rekanalar/goose-finance@v0.1.0";
import bank_statement from "..";

fn main() {
    let text = "!Account\nNChecking\nTBank\n^\n!Type:Cat\nNFood:Dining\nE\nB10.00\n^\n!Type:Payee\nPBob's Cafe\nA1 Main St\nCParis\n^\n!Type:Prices\n\"ACME\",50 1/2,\"6/30/98\"\n^\n";
    let lim = bank_statement::default_limits();
    let opts = bank_statement::QifOptions { date_order: bank_statement::DATE_MDY, .. };
    var items: bank_statement::QifItem[>..] = [];
    var budgets: bank_statement::Amount[>..] = [];
    var lines: bank_statement::QifField[>..] = [];
    var extra: bank_statement::QifField[>..] = [];
    var prices: bank_statement::QifPrice[>..] = [];
    let f = bank_statement::parse_qif_lists(text, lim, opts, items, budgets, lines, extra, prices);
    if f.kind != 0 {
        print("error: ", bank_statement::kind_name(f.kind), " line ", f.line, " ", f.detail, "\n");
        return 1;
    }
    for it in items { print("list ", it.section, " ", it.name, "\n"); }
    for p in prices { print("price ", p.symbol, " ", p.price.num, "/", p.price.den, "\n"); }
    var out: u8[>..] = [];
    let w = bank_statement::write_qif_lists(items, budgets, lines, extra, prices,
        bank_statement::QifWriteOptions { date_order: 0 }, lim, out);
    if w.kind != 0 {
        print("error: ", bank_statement::kind_name(w.kind), " ", w.detail, "\n");
        return 1;
    }
    print(out);
    return 0;
}
