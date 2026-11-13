// The records of the QIF parser.
//
namespace bank_statement;

import std;
import fault;
import text;
import limits;
import amount;
import date;

const Q_ACCOUNT: i32 = 1;
const Q_BANK: i32 = 2;
const Q_CASH: i32 = 3;
const Q_CCARD: i32 = 4;
const Q_OTH_A: i32 = 5;
const Q_OTH_L: i32 = 6;
const Q_INVST: i32 = 7;
const Q_PORT: i32 = 8;
const Q_CAT: i32 = 9;
const Q_CLASS: i32 = 10;
const Q_SECURITY: i32 = 11;
const Q_PRICES: i32 = 12;
const Q_MEMORIZED: i32 = 13;
const Q_OTH_S: i32 = 14;
const Q_INVOICE: i32 = 15;
const Q_TAX: i32 = 16;
const Q_BILL: i32 = 17;
const Q_BUDGET: i32 = 18;
const Q_TAG: i32 = 19;
const Q_PAYEE: i32 = 20;

// The order of the parts of a date. DATE_AUTO reads each date alone: a
// year of four digits first means year first, a part above 12 gives the
// order, and a date that fits two orders is an error. DATE_DETECT reads
// the whole file and picks the one order that fits every date.
const DATE_AUTO: i32 = 0;
const DATE_MDY: i32 = 1;
const DATE_DMY: i32 = 2;
const DATE_YMD: i32 = 3;
const DATE_DETECT: i32 = 4;

// QifOptions holds the options of the reader. The zero value reads dates
// with DATE_AUTO, the decimal mark ".", the pivot 70 and a currency with
// two minor digits.
struct QifOptions {
    date_order: i32,
    decimal: u8,
    pivot: i32,
    currency: const u8[:],
    // The charset to decode first: 0 keeps the bytes, CS_CP1252 and
    // CS_LATIN1 decode into UTF-8.
    charset: i32 = 0,
}

// QifField holds one line that has no typed field.
struct QifField {
    code: u8,
    value: const u8[:],
}

// QifSplit holds one split of a transaction.
struct QifSplit {
    category: const u8[:],
    memo: const u8[:],
    has_amount: bool,
    amount: Amount,
    percent_text: const u8[:],
    has_percent: bool,
    percent: Rational,
}

// Rational holds an exact number as a numerator and a positive
// denominator. The fraction is reduced to its smallest terms. No float
// reaches the value.
struct Rational {
    num: i64,
    den: i64,
}

// QifRecord holds one record. The splits and the fields are ranges of
// the arrays of the caller. The date has year 0 when absent. The amount
// holds the value of the U code when the record has one, else the value
// of T; amount_code names the code that won and alt_amount holds the
// value that lost. The investment values price, quantity and commission
// are exact rationals; their text stays in price_text, quantity_text and
// commission_text.
struct QifRecord {
    section: i32,
    line: i32,
    date: Date,
    has_amount: bool,
    amount: Amount,
    amount_code: u8,
    has_alt_amount: bool,
    alt_amount: Amount,
    cleared: u8,
    number: const u8[:],
    payee: const u8[:],
    memo: const u8[:],
    category: const u8[:],
    action: const u8[:],
    security: const u8[:],
    reimbursable: bool,
    reimbursable_text: const u8[:],
    price: Rational,
    has_price: bool,
    price_text: const u8[:],
    quantity: Rational,
    has_quantity: bool,
    quantity_text: const u8[:],
    commission: Rational,
    has_commission: bool,
    commission_text: const u8[:],
    split_start: i32,
    split_count: i32,
    field_start: i32,
    field_count: i32,
}

// Category holds the parts of an L line: Name:Sub/Class or [Account]/Class.
struct Category {
    name: const u8[:],
    sub: const u8[:],
    class: const u8[:],
    transfer: const u8[:],
}

// section_of reads the text after the ! of a header line. It gives the
// kind, 0 for a header that only switches a mode, and -1 for an unknown
// header. The match takes any letter case, takes a space or a colon
// after the word type, and takes a form like OthA without the blank.
fn section_of(h: const u8[:]) -> i32 {
    let t = trim(h);
    if ieq_nospace(t, "account") { return Q_ACCOUNT; }
    if ieq_nospace(t, "option:autoswitch") || ieq_nospace(t, "clear:autoswitch") { return 0; }
    if !(t.len >= 5 && ieq(t[..4], "type") && (t[4] == ':' || t[4] == ' ')) { return -1; }
    let name = trim(t[5..]);
    if ieq_nospace(name, "bank") { return Q_BANK; }
    if ieq_nospace(name, "cash") { return Q_CASH; }
    if ieq_nospace(name, "ccard") { return Q_CCARD; }
    if ieq_nospace(name, "oth a") { return Q_OTH_A; }
    if ieq_nospace(name, "oth l") { return Q_OTH_L; }
    if ieq_nospace(name, "oth s") { return Q_OTH_S; }
    if ieq_nospace(name, "invst") { return Q_INVST; }
    if ieq_nospace(name, "port") { return Q_PORT; }
    if ieq_nospace(name, "invoice") { return Q_INVOICE; }
    if ieq_nospace(name, "tax") { return Q_TAX; }
    if ieq_nospace(name, "bill") { return Q_BILL; }
    if ieq_nospace(name, "cat") { return Q_CAT; }
    if ieq_nospace(name, "budget") { return Q_BUDGET; }
    if ieq_nospace(name, "class") { return Q_CLASS; }
    if ieq_nospace(name, "tag") { return Q_TAG; }
    if ieq_nospace(name, "security") { return Q_SECURITY; }
    if ieq_nospace(name, "prices") { return Q_PRICES; }
    if ieq_nospace(name, "memorized") { return Q_MEMORIZED; }
    if ieq_nospace(name, "payee") { return Q_PAYEE; }
    return -1;
}

fn typed_section(k: i32) -> bool {
    return k == Q_BANK || k == Q_CASH || k == Q_CCARD || k == Q_OTH_A || k == Q_OTH_L || k == Q_OTH_S
        || k == Q_INVST || k == Q_PORT || k == Q_INVOICE || k == Q_TAX || k == Q_BILL || k == Q_MEMORIZED;
}

// DateParts holds the three numbers of a date text and the length of
// each, in the order of the text.
struct DateParts {
    n1: i64, n2: i64, n3: i64,
    l1: i64, l2: i64, l3: i64,
    apostrophe: bool,
    ok: bool,
}

// date_parts reads three numbers separated by one of / - . or an
// apostrophe. Blanks inside are ignored. A text of eight digits without
// separators reads as four, two and two.
fn date_parts(text: const u8[:]) -> DateParts {
    var g = DateParts { n1: 0, n2: 0, n3: 0, l1: 0, l2: 0, l3: 0, apostrophe: false, ok: false };
    let s = trim(text);
    if s.len == 0 || s.len > 16 { return g; }
    var vals = [0, 0, 0];
    var lens = [0, 0, 0];
    var k = 0;
    var cur: i64 = 0;
    var len: i64 = 0;
    var i = 0;
    while i < s.len {
        let c = s[i];
        if is_digit(c) {
            cur = cur * 10 + (c - '0');
            len += 1;
            if len > 9 { return g; }
        } else if c == ' ' {
            // blanks pad single digit parts: "1/ 2'25"
        } else if c == '/' || c == '-' || c == '.' || c == '\'' {
            if len == 0 || k >= 2 { return g; }
            vals[k] = cur;
            lens[k] = len;
            k += 1;
            cur = 0;
            len = 0;
            if c == '\'' { g.apostrophe = true; }
        } else {
            return g;
        }
        i += 1;
    }
    if len == 0 { return g; }
    if k == 0 && len == 8 {
        g.n1 = cur / 10000; g.n2 = (cur / 100) % 100; g.n3 = cur % 100;
        g.l1 = 4; g.l2 = 2; g.l3 = 2;
        g.ok = true;
        return g;
    }
    if k != 2 { return g; }
    g.n1 = vals[0]; g.n2 = vals[1]; g.n3 = cur;
    g.l1 = lens[0]; g.l2 = lens[1]; g.l3 = len;
    g.ok = true;
    return g;
}

// year_of turns a year part into a year. It gives 0 for a part that is
// not a year of two or four digits.
fn year_of(n: i64, l: i64, apostrophe: bool, pivot: i64) -> i64 {
    if l == 4 { return n; }
    if l == 2 {
        if apostrophe { return 2000 + n; }
        return year_of_two(n, pivot);
    }
    return 0;
}

// date_in reads the parts in a fixed order.
fn date_in(g: DateParts, order: i32, pivot: i64) -> Date, bool {
    if order == DATE_YMD {
        if g.l1 != 4 { return no_date(), false; }
        return make_date(g.n1, g.n2, g.n3);
    }
    let y = year_of(g.n3, g.l3, g.apostrophe, pivot);
    if y == 0 { return no_date(), false; }
    if order == DATE_MDY { return make_date(y, g.n1, g.n2); }
    return make_date(y, g.n2, g.n1);
}

// parse_qif_date reads one date. The order must be one of the three
// orders or DATE_AUTO. A date that fits two orders is an ambiguity.
fn parse_qif_date(text: const u8[:], order: i32, pivot: i64, line_no: i64) -> Date, Fault {
    let g = date_parts(text);
    if !g.ok { return no_date(), fault(F_DATE, line_no, 2, "D", "date is not three numbers"); }
    // A first part of four digits is a year, whatever order the caller set.
    var o = order;
    if g.l1 == 4 { o = DATE_YMD; }
    if o == DATE_AUTO {
        if g.n1 > 12 && g.n2 <= 12 {
            o = DATE_DMY;
        } else if g.n2 > 12 && g.n1 <= 12 {
            o = DATE_MDY;
        } else if g.n1 == g.n2 && g.n1 <= 12 {
            o = DATE_MDY;
        } else if g.n1 <= 12 && g.n2 <= 12 {
            return no_date(), fault(F_AMBIGUOUS_DATE, line_no, 2, "D", "day and month can swap: set the date order");
        } else {
            return no_date(), fault(F_DATE, line_no, 2, "D", "date is not a date");
        }
    }
    let d, ok = date_in(g, o, pivot);
    if !ok { return no_date(), fault(F_DATE, line_no, 2, "D", "date is not a date"); }
    return d, no_fault();
}

// detect_order reads every date of the file and gives the one order that
// fits all of them. It faults when none fits or when more than one fits.
fn detect_order(input: const u8[:], lim: Limits&, pivot: i64) -> i32, Fault {
    var mdy = true;
    var dmy = true;
    var ymd = true;
    var sect: i32 = 0;
    var seen = false;
    var pos = skip_bom(input);
    var line_no: i64 = 0;
    while pos < input.len {
        let e, bad = line_end(input, pos, lim.max_line);
        line_no += 1;
        if bad != 0 { return DATE_AUTO, line_fault(bad, line_no, 1); }
        let line = trim_cr(input[pos..e]);
        pos = e + 1;
        if line.len == 0 { continue; }
        if line[0] == '!' {
            let k = section_of(line[1..]);
            if k > 0 { sect = k; }
            continue;
        }
        if line[0] != 'D' || !typed_section(sect) { continue; }
        let g = date_parts(line[1..]);
        if !g.ok { return DATE_AUTO, fault(F_DATE, line_no, 2, "D", "date is not three numbers"); }
        seen = true;
        let a, ok1 = date_in(g, DATE_MDY, pivot);
        let b, ok2 = date_in(g, DATE_DMY, pivot);
        let c, ok3 = date_in(g, DATE_YMD, pivot);
        if !ok1 { mdy = false; }
        if !ok2 { dmy = false; }
        if !ok3 { ymd = false; }
    }
    if !seen { return DATE_MDY, no_fault(); }
    var n = 0;
    if mdy { n += 1; }
    if dmy { n += 1; }
    if ymd { n += 1; }
    if n == 0 { return DATE_AUTO, fault(F_DATE, 0, 0, "D", "no date order fits every date"); }
    if n > 1 { return DATE_AUTO, fault(F_AMBIGUOUS_DATE, 0, 0, "D", "more than one date order fits every date"); }
    if mdy { return DATE_MDY, no_fault(); }
    if dmy { return DATE_DMY, no_fault(); }
    return DATE_YMD, no_fault();
}

fn new_record(sect: i32, line_no: i64, fields: i64, splits: i64) -> QifRecord {
    let z = Amount { minor: 0, exp: 2, currency: "" };
    let r = Rational { num: 0, den: 1 };
    return QifRecord {
        section: sect, line: line_no as i32, date: no_date(), has_amount: false, amount: z,
        amount_code: 0, has_alt_amount: false, alt_amount: z, cleared: 0,
        number: "", payee: "", memo: "", category: "", action: "", security: "",
        reimbursable: false, reimbursable_text: "",
        price: r, has_price: false, price_text: "",
        quantity: r, has_quantity: false, quantity_text: "",
        commission: r, has_commission: false, commission_text: "",
        split_start: splits as i32, split_count: 0, field_start: fields as i32, field_count: 0,
    };
}
