// The tests of the group qif.
namespace qif_tests;

import std;
import os;
import xml from "rekanalar/goose-xml@v2.0.0";
import process from "rekanalar/goose-process@v1.0.0";
import bank_statement from "..";
import finance from "rekanalar/goose-finance@v0.1.0";
import common;

fn test_qif_basic() {
    let lim = bank_statement::default_limits();
    let opts = bank_statement::QifOptions { date_order: bank_statement::DATE_MDY, .. };
    var recs: bank_statement::QifRecord[>..] = [];
    var spl: bank_statement::QifSplit[>..] = [];
    var ext: bank_statement::QifField[>..] = [];
    var xbuf9: u8[>..] = [];
    let f = bank_statement::parse_qif(common::QIF1, lim, opts, recs, spl, ext, xbuf9);
    if f.kind != 0 { print("FAIL ", bank_statement::kind_name(f.kind), " line ", f.line, " ", f.detail, "\n"); }
    assert(f.kind == 0);
    assert(recs.len == 3);
    let r = recs[0];
    assert(r.section == bank_statement::Q_BANK);
    assert(r.date.year == 2025 && r.date.month == 12 && r.date.day == 31);
    assert(r.has_amount && r.amount.minor == -123456);
    assert(r.cleared == 'X');
    assert(r.number == "1001" && r.payee == "Acme Corp" && r.memo == "Invoice");
    assert(r.category == "Groceries:Food/Home");
    // Both A lines and the unknown Z line are kept as fields.
    assert(r.field_count == 3);
    assert(ext[0].code == 'A' && ext[0].value == "Street 1");
    assert(ext[2].code == 'Z' && ext[2].value == "odd");
    let r2 = recs[1];
    assert(r2.date.year == 2025 && r2.date.month == 1 && r2.date.day == 2);
    assert(r2.amount.minor == -5000);
    assert(r2.split_count == 2);
    assert(spl[0].category == "Rent" && spl[0].memo == "half" && spl[0].amount.minor == -3000);
    assert(spl[1].category == "Util" && spl[1].amount.minor == -2000);
    assert(spl[1].has_percent && spl[1].percent.num == 40 && spl[1].percent.den == 1);
    assert(spl[1].percent_text == "40");
    // The last record has no ^.
    let r3 = recs[2];
    assert(r3.date.year == 2025 && r3.date.month == 3 && r3.date.day == 4);
    assert(r3.amount.minor == 811);
}

fn test_qif_category() {
    let c = bank_statement::split_category("Groceries:Food/Home");
    assert(c.name == "Groceries" && c.sub == "Food" && c.class == "Home");
    let t = bank_statement::split_category("[Savings]/Trip");
    assert(t.transfer == "Savings" && t.class == "Trip");
    let p = bank_statement::split_category("Salary");
    assert(p.name == "Salary" && p.sub.len == 0);
}

fn test_qif_sections() {
    let lim = bank_statement::default_limits();
    let opts = bank_statement::QifOptions { date_order: bank_statement::DATE_DMY, decimal: ',', .. };
    var recs: bank_statement::QifRecord[>..] = [];
    var spl: bank_statement::QifSplit[>..] = [];
    var ext: bank_statement::QifField[>..] = [];
    let text = "!Account\nNChecking\nTBank\n^\n!Type:Cat\nNSalary\nI\n^\n!Type:Invst\nD31.12.2025\nNBuy\nYAcme\nI10,5\nQ100\nO9,99\nT1.050,00\n$1.050,00\n^\n!Type:Prices\n\"ACME\",10.5,\"31.12.2025\"\n^\n";
    var xbuf10: u8[>..] = [];
    let f = bank_statement::parse_qif(text, lim, opts, recs, spl, ext, xbuf10);
    if f.kind != 0 { print("FAIL ", bank_statement::kind_name(f.kind), " line ", f.line, " ", f.detail, "\n"); }
    assert(f.kind == 0);
    assert(recs.len == 4);
    assert(recs[0].section == bank_statement::Q_ACCOUNT && recs[0].field_count == 2);
    assert(recs[1].section == bank_statement::Q_CAT && recs[1].field_count == 2);
    let iv = recs[2];
    assert(iv.section == bank_statement::Q_INVST);
    assert(iv.action == "Buy" && iv.security == "Acme");
    // 10.5, 100 and 9,99 come back as exact rationals and keep their text.
    assert(iv.has_price && iv.price.num == 21 && iv.price.den == 2 && iv.price_text == "10,5");
    assert(iv.has_quantity && iv.quantity.num == 100 && iv.quantity.den == 1 && iv.quantity_text == "100");
    assert(iv.has_commission && iv.commission.num == 999 && iv.commission.den == 100 && iv.commission_text == "9,99");
    assert(iv.amount.minor == 105000);
    assert(iv.date.year == 2025 && iv.date.day == 31);
    assert(iv.field_count == 1 && ext[recs[2].field_start].code == '$');
    assert(recs[3].section == bank_statement::Q_PRICES && recs[3].field_count == 1);
    assert(spl.len == 0);
}

fn test_qif_dates() {
    // No order and a date that fits two orders: the caller must say.
    common::run_qif("!Type:Bank\nD01/02/2025\n^\n", bank_statement::DATE_AUTO, 9);
    // A part above 12 gives the order.
    common::run_qif("!Type:Bank\nD13/02/2025\n^\nD2025-03-04\n^\n", bank_statement::DATE_AUTO, 0);
    common::run_qif("!Type:Bank\nD02/13/2025\n^\n", bank_statement::DATE_AUTO, 0);
    // Equal day and month are no ambiguity.
    common::run_qif("!Type:Bank\nD05/05/2025\n^\n", bank_statement::DATE_AUTO, 0);
    // Detection reads the whole file.
    common::run_qif("!Type:Bank\nD01/02/2025\n^\nD13/02/2025\n^\n", bank_statement::DATE_DETECT, 0);
    common::run_qif("!Type:Bank\nD01/02/2025\n^\nD03/04/2025\n^\n", bank_statement::DATE_DETECT, 9);
    common::run_qif("!Type:Bank\nD13/02/2025\n^\nD02/13/2025\n^\n", bank_statement::DATE_DETECT, 6);
    // A day that does not exist.
    common::run_qif("!Type:Bank\nD02/30/2025\n^\n", bank_statement::DATE_MDY, 6);
    common::run_qif("!Type:Bank\nDabc\n^\n", bank_statement::DATE_MDY, 6);
    // The year pivot: 99 is 1999 and 24 is 2024.
    let lim = bank_statement::default_limits();
    let opts = bank_statement::QifOptions { date_order: bank_statement::DATE_MDY, .. };
    var recs: bank_statement::QifRecord[>..] = [];
    var spl: bank_statement::QifSplit[>..] = [];
    var ext: bank_statement::QifField[>..] = [];
    var xbuf11: u8[>..] = [];
    let f = bank_statement::parse_qif("!Type:Bank\nD1/2/99\n^\nD1/2/24\n^\nD20250102\n^\n", lim, opts, recs, spl, ext, xbuf11);
    assert(f.kind == 0);
    assert(recs[0].date.year == 1999 && recs[1].date.year == 2024);
}

fn test_qif_faults() {
    common::run_qif("!Type:Nope\n", 1, 3);
    common::run_qif("D1/1/25\n", 1, 2);
    common::run_qif("!Type:Bank\nTabc\n^\n", 1, 4);
    common::run_qif("!Type:Bank\nT1,2,3\n^\n", 1, 4);
    common::run_qif("!Type:Bank\nCQ\n^\n", 1, 2);
    common::run_qif("", 1, 0);
    // An unknown header names the header text, not just the !.
    let lim = bank_statement::default_limits();
    let opts = bank_statement::QifOptions { .. };
    var recs: bank_statement::QifRecord[>..] = [];
    var spl: bank_statement::QifSplit[>..] = [];
    var ext: bank_statement::QifField[>..] = [];
    var xbuf12: u8[>..] = [];
    let f = bank_statement::parse_qif("!Type:Purple\n", lim, opts, recs, spl, ext, xbuf12);
    assert(f.kind == 3 && f.tag == "!Type:Purple");
}

// test_qif_headers reads the headers the first release did not know and
// the case and space forms of the old ones.
fn test_qif_headers() {
    let lim = bank_statement::default_limits();
    let opts = bank_statement::QifOptions { date_order: bank_statement::DATE_MDY, .. };
    // Oth S, Invoice, Tax and Bill hold typed transaction records.
    var text = "!Type:Oth S\nD01/02/2025\nT100\n^\n!Type:Invoice\nD01/03/2025\nT200\n^\n!Type:Tax\nT300\n^\n!Type:Bill\nT400\n^\n";
    var recs: bank_statement::QifRecord[>..] = [];
    var spl: bank_statement::QifSplit[>..] = [];
    var ext: bank_statement::QifField[>..] = [];
    var xbuf13: u8[>..] = [];
    var f = bank_statement::parse_qif(text, lim, opts, recs, spl, ext, xbuf13);
    if f.kind != 0 { print("FAIL headers ", bank_statement::kind_name(f.kind), " line ", f.line, " ", f.detail, "\n"); }
    assert(f.kind == 0);
    assert(recs.len == 4);
    assert(recs[0].section == bank_statement::Q_OTH_S && recs[0].has_amount && recs[0].amount.minor == 10000);
    assert(recs[1].section == bank_statement::Q_INVOICE && recs[1].amount.minor == 20000);
    assert(recs[2].section == bank_statement::Q_TAX && recs[2].amount.minor == 30000);
    assert(recs[3].section == bank_statement::Q_BILL && recs[3].amount.minor == 40000);
    // Budget and Tag keep every line as a field, like Cat and Class.
    text = "!Type:Budget\nNGroceries\nB100\n^\n!Type:Tag\nNTravel\nDwork trips\n^\n";
    var recs2: bank_statement::QifRecord[>..] = [];
    var spl2: bank_statement::QifSplit[>..] = [];
    var ext2: bank_statement::QifField[>..] = [];
    var xbuf14: u8[>..] = [];
    f = bank_statement::parse_qif(text, lim, opts, recs2, spl2, ext2, xbuf14);
    assert(f.kind == 0);
    assert(recs2[0].section == bank_statement::Q_BUDGET && recs2[0].field_count == 2);
    assert(recs2[1].section == bank_statement::Q_TAG && recs2[1].field_count == 2);
    assert(ext2[0].code == 'N' && ext2[0].value == "Groceries");
    assert(ext2[3].code == 'D' && ext2[3].value == "work trips");
    // Case, space and no-blank forms open the same sections.
    var recs3: bank_statement::QifRecord[>..] = [];
    var spl3: bank_statement::QifSplit[>..] = [];
    var ext3: bank_statement::QifField[>..] = [];
    var xbuf15: u8[>..] = [];
    f = bank_statement::parse_qif("!type bank\nT1\n^\n!TYPE:BANK\nT2\n^\n!Type:OthA\nT3\n^\n!type oth a\nT4\n^\n", lim, opts, recs3, spl3, ext3, xbuf15);
    assert(f.kind == 0);
    assert(recs3.len == 4);
    assert(recs3[0].section == bank_statement::Q_BANK && recs3[1].section == bank_statement::Q_BANK);
    assert(recs3[2].section == bank_statement::Q_OTH_A && recs3[3].section == bank_statement::Q_OTH_A);
}

// test_qif_u_amount checks the U rule and the ... marker.
fn test_qif_u_amount() {
    let lim = bank_statement::default_limits();
    let opts = bank_statement::QifOptions { date_order: bank_statement::DATE_MDY, .. };
    var recs: bank_statement::QifRecord[>..] = [];
    var spl: bank_statement::QifSplit[>..] = [];
    var ext: bank_statement::QifField[>..] = [];
    // U wins over T in both orders. The losing value stays reachable.
    let text = "!Type:Bank\nT100.00\nU200.00\n^\nU300.00\nT400.00\n^\n";
    var xbuf16: u8[>..] = [];
    let f = bank_statement::parse_qif(text, lim, opts, recs, spl, ext, xbuf16);
    assert(f.kind == 0);
    assert(recs.len == 2);
    assert(recs[0].has_amount && recs[0].amount.minor == 20000 && recs[0].amount_code == 'U');
    assert(recs[0].has_alt_amount && recs[0].alt_amount.minor == 10000);
    assert(recs[1].has_amount && recs[1].amount.minor == 30000 && recs[1].amount_code == 'U');
    assert(recs[1].has_alt_amount && recs[1].alt_amount.minor == 40000);
    // A T alone names its code and holds no alt value.
    var recs2: bank_statement::QifRecord[>..] = [];
    var spl2: bank_statement::QifSplit[>..] = [];
    var ext2: bank_statement::QifField[>..] = [];
    var xbuf17: u8[>..] = [];
    let f2 = bank_statement::parse_qif("!Type:Bank\nT100.00\n^\n", lim, opts, recs2, spl2, ext2, xbuf17);
    assert(f2.kind == 0);
    assert(recs2[0].amount_code == 'T' && !recs2[0].has_alt_amount);
    // A value that starts with ... sets no amount and stays a field.
    var recs3: bank_statement::QifRecord[>..] = [];
    var spl3: bank_statement::QifSplit[>..] = [];
    var ext3: bank_statement::QifField[>..] = [];
    let text3 = "!Type:Bank\nT...\n^\nU...\n^\nSOne\n$...\nSTwo\n$5\n^\n";
    var xbuf18: u8[>..] = [];
    let f3 = bank_statement::parse_qif(text3, lim, opts, recs3, spl3, ext3, xbuf18);
    assert(f3.kind == 0);
    assert(recs3.len == 3);
    assert(!recs3[0].has_amount && recs3[0].field_count == 1 && ext3[0].code == 'T');
    assert(!recs3[1].has_amount && recs3[1].field_count == 1);
    assert(!spl3[0].has_amount && recs3[2].field_count == 1 && ext3[2].code == '$');
    assert(spl3[1].has_amount && spl3[1].amount.minor == 500);
}

// test_qif_ratio checks the exact number codes and the F flag.
fn test_qif_ratio() {
    let lim = bank_statement::default_limits();
    let opts = bank_statement::QifOptions { date_order: bank_statement::DATE_MDY, .. };
    var recs: bank_statement::QifRecord[>..] = [];
    var spl: bank_statement::QifSplit[>..] = [];
    var ext: bank_statement::QifField[>..] = [];
    // 10 1/2, 1/2, a negative commission and a percent with a tail.
    let text = "!Type:Invst\nI10 1/2\nQ1/4\nO-9.99\n^\n!Type:Bank\nSA\n%12.5 %\nSB\n%1/3\n^\nFphone\n^\n";
    var xbuf19: u8[>..] = [];
    let f = bank_statement::parse_qif(text, lim, opts, recs, spl, ext, xbuf19);
    if f.kind != 0 { print("FAIL ratio ", bank_statement::kind_name(f.kind), " line ", f.line, " ", f.detail, "\n"); }
    assert(f.kind == 0);
    assert(recs[0].has_price && recs[0].price.num == 21 && recs[0].price.den == 2 && recs[0].price_text == "10 1/2");
    assert(recs[0].has_quantity && recs[0].quantity.num == 1 && recs[0].quantity.den == 4);
    assert(recs[0].has_commission && recs[0].commission.num == -999 && recs[0].commission.den == 100);
    assert(spl[0].has_percent && spl[0].percent.num == 25 && spl[0].percent.den == 2 && spl[0].percent_text == "12.5 %");
    assert(spl[1].has_percent && spl[1].percent.num == 1 && spl[1].percent.den == 3);
    assert(recs[2].reimbursable && recs[2].reimbursable_text == "phone");
    // A value that fits no form is an amount fault with the code as tag.
    common::run_qif("!Type:Invst\nI1 2 3/4\n^\n", bank_statement::DATE_MDY, 4);
    var recs2: bank_statement::QifRecord[>..] = [];
    var spl2: bank_statement::QifSplit[>..] = [];
    var ext2: bank_statement::QifField[>..] = [];
    var xbuf20: u8[>..] = [];
    let f2 = bank_statement::parse_qif("!Type:Invst\nIabc\n^\n", lim, opts, recs2, spl2, ext2, xbuf20);
    assert(f2.kind == 4 && f2.tag == "I");
    // A fraction of zero is a fault.
    var xbuf21: u8[>..] = [];
    let f3 = bank_statement::parse_qif("!Type:Invst\nI1/0\n^\n", lim, opts, recs2, spl2, ext2, xbuf21);
    assert(f3.kind == 4);
}
