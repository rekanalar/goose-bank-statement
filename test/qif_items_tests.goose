// The tests of the group qif_items.
namespace qif_items_tests;

import std;
import os;
import xml from "rekanalar/goose-xml@v2.0.0";
import process from "rekanalar/goose-process@v1.0.0";
import bank_statement from "..";
import finance from "rekanalar/goose-finance@v0.1.0";
import sample_texts;

fn test_qif_item_lists() {
    let lim = bank_statement::default_limits();
    let ropts = bank_statement::QifOptions { date_order: bank_statement::DATE_MDY, .. };
    var items: bank_statement::QifItem[>..] = [];
    var buds: bank_statement::Amount[>..] = [];
    var lns: bank_statement::QifField[>..] = [];
    var ext: bank_statement::QifField[>..] = [];
    var prs: bank_statement::QifPrice[>..] = [];
    let f = bank_statement::parse_qif_lists(sample_texts::LISTS_TEXT, lim, ropts, items, buds, lns, ext, prs);
    if f.kind != 0 { print("FAIL lists ", bank_statement::kind_name(f.kind), " ", f.line, " ", f.detail, "\n"); }
    assert(f.kind == 0);
    assert(items.len == 7 && prs.len == 2);
    let a = items[0];
    assert(a.section == bank_statement::Q_ACCOUNT && a.name == "Checking" && a.kind == "Bank" && a.description == "Main account");
    assert(a.has_limit && a.limit.minor == 100000 && a.has_balance && a.balance.minor == 25050);
    assert(a.has_balance_date && a.balance_date.year == 2025 && a.balance_date.month == 12 && a.balance_date.day == 31);
    let c = items[1];
    assert(c.name == "Food:Dining" && c.tax && c.income && c.expense && c.schedule == "Sched A");
    assert(c.budget_count == 2 && buds[c.budget_start].minor == 1000 && buds[c.budget_start + 1].minor == 2050);
    // A code the section does not know stays a field.
    assert(c.field_count == 1 && ext[c.field_start].code == 'X' && ext[c.field_start].value == "odd");
    assert(items[2].section == bank_statement::Q_BUDGET && buds[items[2].budget_start].minor == 500);
    assert(items[3].section == bank_statement::Q_CLASS && items[3].name == "Garden");
    let s = items[4];
    assert(s.name == "Acme Corp" && s.symbol == "ACME" && s.kind == "Stock" && s.goal == "Growth");
    assert(items[5].section == bank_statement::Q_TAG && items[5].description == "vacation");
    let p = items[6];
    assert(p.section == bank_statement::Q_PAYEE && p.name == "Bob's Cafe" && p.address_count == 2);
    assert(lns[p.address_start].value == "1 Main St" && lns[p.address_start + 1].value == "Floor 2");
    assert(p.city == "Paris" && p.state == "IDF" && p.zip == "75001" && p.country == "FRA");
    assert(p.phone == "0102030405" && p.account == "ACC-9");
    assert(prs[0].symbol == "ACME" && prs[0].price.num == 101 && prs[0].price.den == 2);
    assert(prs[0].date.year == 1998 && prs[0].date.month == 6 && prs[0].date.day == 30);
    assert(prs[1].symbol == "A,B" && prs[1].price.num == 41 && prs[1].price.den == 4 && prs[1].date.year == 2025);
    // The extra parts of Perl Finance::QIF: a high, a low and a volume.
    assert(prs[1].has_high && prs[1].high.num == 21 && prs[1].high.den == 2);
    assert(prs[1].has_low && prs[1].low.num == 39 && prs[1].low.den == 4);
    assert(prs[1].has_volume && prs[1].volume == 42000);
    assert(!prs[0].has_high && !prs[0].has_low && !prs[0].has_volume);
    // The record list reader keeps the payee section as fields.
    var recs: bank_statement::QifRecord[>..] = [];
    var spl: bank_statement::QifSplit[>..] = [];
    var ex2: bank_statement::QifField[>..] = [];
    var xbuf35: u8[>..] = [];
    var xbuf35_pre: u8[>..] = [];
    assert(bank_statement::parse_qif(sample_texts::LISTS_TEXT, lim, ropts, recs, spl, ex2, xbuf35_pre).kind == 0);
    // Write and read back to the same values.
    var out: u8[>..] = [];
    let wopts = bank_statement::QifWriteOptions { date_order: 0 };
    let w = bank_statement::write_qif_lists(items, buds, lns, ext, prs, wopts, lim, out);
    if w.kind != 0 { print("FAIL write lists ", bank_statement::kind_name(w.kind), " ", w.detail, "\n"); }
    assert(w.kind == 0);
    var i2: bank_statement::QifItem[>..] = [];
    var b2: bank_statement::Amount[>..] = [];
    var l2: bank_statement::QifField[>..] = [];
    var e2: bank_statement::QifField[>..] = [];
    var p2: bank_statement::QifPrice[>..] = [];
    assert(bank_statement::parse_qif_lists(out, lim, ropts, i2, b2, l2, e2, p2).kind == 0);
    assert(i2.len == 7 && p2.len == 2);
    assert(i2[0].limit.minor == 100000 && i2[0].balance_date.day == 31 && i2[1].tax && i2[1].income && i2[1].expense);
    assert(i2[1].budget_count == 2 && b2[i2[1].budget_start + 1].minor == 2050 && e2[i2[1].field_start].value == "odd");
    assert(i2[6].address_count == 2 && l2[i2[6].address_start].value == "1 Main St" && i2[6].account == "ACC-9");
    assert(p2[0].price.num == 101 && p2[0].price.den == 2 && p2[1].symbol == "A,B" && p2[1].price.num == 41);
    assert(p2[1].has_high && p2[1].high.num == 21 && p2[1].has_low && p2[1].low.num == 39 && p2[1].has_volume && p2[1].volume == 42000);
    var o3: u8[>..] = [];
    assert(bank_statement::write_qif_lists(i2, b2, l2, e2, p2, wopts, lim, o3).kind == 0);
    assert(o3 == out);
}

fn test_qif_item_faults() {
    let lim = bank_statement::default_limits();
    let ropts = bank_statement::QifOptions { date_order: bank_statement::DATE_MDY, .. };
    var items: bank_statement::QifItem[>..] = [];
    var buds: bank_statement::Amount[>..] = [];
    var lns: bank_statement::QifField[>..] = [];
    var ext: bank_statement::QifField[>..] = [];
    var prs: bank_statement::QifPrice[>..] = [];
    // A price line with seven parts, an unbalanced quote and a bad price are faults.
    assert(bank_statement::parse_qif_lists("!Type:Prices\n\"A\",1,\"1/1/2020\",9,8,7,6\n^\n", lim, ropts, items, buds, lns, ext, prs).kind == bank_statement::F_SYNTAX);
    var i2: bank_statement::QifItem[>..] = [];
    var p2: bank_statement::QifPrice[>..] = [];
    assert(bank_statement::parse_qif_lists("!Type:Prices\n\"A,1,\"1/1/2020\"\n", lim, ropts, i2, buds, lns, ext, p2).kind == bank_statement::F_SYNTAX);
    var p3: bank_statement::QifPrice[>..] = [];
    assert(bank_statement::parse_qif_lists("!Type:Prices\n\"A\",x,\"1/1/2020\"\n", lim, ropts, i2, buds, lns, ext, p3).kind != 0);
    // A record without a closing ^ is kept.
    var i3: bank_statement::QifItem[>..] = [];
    assert(bank_statement::parse_qif_lists("!Type:Class\nNKept\n", lim, ropts, i3, buds, lns, ext, p3).kind == 0 && i3.len == 1);
    // A repeated scalar line is kept as a field, not dropped.
    var i4: bank_statement::QifItem[>..] = [];
    var e4: bank_statement::QifField[>..] = [];
    assert(bank_statement::parse_qif_lists("!Type:Class\nNA\nNB\n^\n", lim, ropts, i4, buds, lns, e4, p3).kind == 0);
    assert(i4[0].name == "A" && i4[0].field_count == 1 && e4[0].value == "B");
    // The writer refuses a line end, a control byte, a quote in a symbol and a missing name.
    let wopts = bank_statement::QifWriteOptions { date_order: 0 };
    var out: u8[>..] = [];
    var it = i3[0];
    it.description = "a\nb";
    var one: bank_statement::QifItem[>..] = [it];
    assert(bank_statement::write_qif_lists(one, buds, lns, ext, p3, wopts, lim, out).kind == bank_statement::F_SYNTAX);
    it.description = "";
    it.name = "";
    var two: bank_statement::QifItem[>..] = [it];
    assert(bank_statement::write_qif_lists(two, buds, lns, ext, p3, wopts, lim, out).kind == bank_statement::F_SYNTAX);
    var bad: bank_statement::QifPrice[>..] = [bank_statement::QifPrice { symbol: "A\"B", price: bank_statement::Rational { num: 1, den: 1 }, price_text: "", date: bank_statement::Date { year: 2020, month: 1, day: 1 }, has_high: false, high: bank_statement::Rational { num: 0, den: 1 }, has_low: false, low: bank_statement::Rational { num: 0, den: 1 }, has_volume: false, volume: 0 }];
    var none: bank_statement::QifItem[>..] = [];
    assert(bank_statement::write_qif_lists(none, buds, lns, ext, bad, wopts, lim, out).kind == bank_statement::F_SYNTAX);
    // A field code of ! or ^ cannot start a new record or section.
    var xf: bank_statement::QifField[>..] = [bank_statement::QifField { code: '^', value: "x" }];
    var it2 = i3[0];
    it2.field_start = 0;
    it2.field_count = 1;
    var three: bank_statement::QifItem[>..] = [it2];
    assert(bank_statement::write_qif_lists(three, buds, lns, xf, p3, wopts, lim, out).kind == bank_statement::F_SYNTAX);
}
