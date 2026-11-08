// The QIF reader of the bank_statement package.
//
// parse_qif reads a QIF file. A line that starts with ! opens a section.
// Every other line holds a one character code and a value. A line that
// holds ^ ends a record. The records, the splits and the other fields go
// into arrays that the caller owns. Text fields are spans over the
// input, so the input must outlive the arrays.
//
// Bank, cash, card, asset, liability, investment, portfolio and
// memorized sections give typed records. The account, category, class,
// security and price sections keep every line as a field of the record.
// A code that has no typed field comes back as a field too. No line is
// dropped.
namespace bank_statement;

import std;
import fault;
import text;
import limits;
import amount;
import date;

// The kinds of a section.
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

fn new_split() -> QifSplit {
    return QifSplit {
        category: "", memo: "", has_amount: false,
        amount: Amount { minor: 0, exp: 2, currency: "" },
        percent_text: "", has_percent: false, percent: Rational { num: 0, den: 1 },
    };
}

// magnitude gives the absolute value of an i64 as a u64. The most
// negative value maps to its own magnitude.
fn magnitude(v: i64) -> u64 {
    if v >= 0 { return v as u64; }
    if v == -9223372036854775808 { return 9223372036854775808; }
    return (-(v)) as u64;
}

// gcd_ratio gives the greatest common divisor of two magnitudes.
fn gcd_ratio(a: u64, b: u64) -> u64 {
    var x = a;
    var y = b;
    while y != 0 {
        let r = x % y;
        x = y;
        y = r;
    }
    return x;
}

// reduce_ratio brings a fraction to its smallest terms.
fn reduce_ratio(r: Rational) -> Rational {
    let g = gcd_ratio(magnitude(r.num), r.den as u64);
    if g > 1 {
        return Rational { num: r.num / (g as i64), den: r.den / (g as i64) };
    }
    return r;
}

// pow10 gives 10 to the power of n, or false when it does not fit.
fn pow10(n: i32) -> i64, bool {
    var v: i64 = 1;
    var i: i32 = 0;
    while i < n {
        if v > 922337203685477580 { return 0, false; }
        v = v * 10;
        i += 1;
    }
    return v, true;
}

// is_dots tells whether a value starts with the QIF marker that says
// the amount has no numeric value.
fn is_dots(value: const u8[:]) -> bool {
    return value.len >= 3 && value[0] == '.' && value[1] == '.' && value[2] == '.';
}

// code_tag gives the tag text of a number code for a fault.
fn code_tag(c: u8) -> const u8[:] {
    if c == 'I' { return "I"; }
    if c == 'Q' { return "Q"; }
    if c == 'O' { return "O"; }
    return "%";
}

// parse_ratio reads an exact number: a plain decimal, a whole fraction
// a/b or a mixed fraction a b/c, with the decimal and thousands marks
// of the file. The fraction comes back reduced. No float is used.
fn parse_ratio(text: const u8[:], dec: u8, grp: u8, line_no: i64, code: u8) -> Rational, Fault {
    let tag = code_tag(code);
    let bad = fault(F_AMOUNT, line_no, 2, tag, "value is not a number");
    let s = trim(text);
    if s.len == 0 { return Rational { num: 0, den: 1 }, bad; }
    // A mixed fraction holds one blank between the whole part and b/c.
    let slash = rfind(s, "/");
    if slash < 0 {
        let m, scale, f = parse_number(s, dec, grp);
        if f.kind != F_NONE { return Rational { num: 0, den: 1 }, with_pos(f, line_no, tag); }
        let den, ok = pow10(scale);
        if !ok { return Rational { num: 0, den: 1 }, fault(F_OVERFLOW, line_no, 2, tag, "denominator does not fit in 64 bits"); }
        return reduce_ratio(Rational { num: m, den: den }), no_fault();
    }
    let left = trim(s[..slash]);
    let right = trim(s[slash + 1..]);
    let dm, dscale, df = parse_number(right, dec, grp);
    if df.kind != F_NONE || dscale != 0 || dm <= 0 { return Rational { num: 0, den: 1 }, bad; }
    let den0 = dm;
    let blank = rfind(left, " ");
    var whole: i64 = 0;
    var num_text = left;
    if blank > 0 {
        let wt = trim(left[..blank]);
        let wm, wscale, wf = parse_number(wt, dec, grp);
        if wf.kind != F_NONE || wscale != 0 { return Rational { num: 0, den: 1 }, bad; }
        whole = wm;
        num_text = trim(left[blank + 1..]);
        if find(num_text, " ") >= 0 { return Rational { num: 0, den: 1 }, bad; }
    }
    let bn, bscale, bf = parse_number(num_text, dec, grp);
    if bf.kind != F_NONE || bscale != 0 || bn < 0 { return Rational { num: 0, den: 1 }, bad; }
    // num = whole * den0 + bn, checked in magnitudes.
    let wmag = magnitude(whole);
    let d = den0 as u64;
    if wmag > 9223372036854775808 / d { return Rational { num: 0, den: 1 }, fault(F_OVERFLOW, line_no, 2, tag, "value does not fit in 64 bits"); }
    let mag: u64 = wmag * d + bn as u64;
    let num, ok = signed_magnitude(mag, whole < 0);
    if !ok { return Rational { num: 0, den: 1 }, fault(F_OVERFLOW, line_no, 2, tag, "value does not fit in 64 bits"); }
    return reduce_ratio(Rational { num: num, den: den0 }), no_fault();
}

// split_category splits an L value: Name:Sub/Class or [Account]/Class.
fn split_category(l: const u8[:]) -> Category {
    var c = Category { name: "", sub: "", class: "", transfer: "" };
    var main = trim(l);
    let slash = find(main, "/");
    if slash >= 0 {
        c.class = main[slash + 1..];
        main = main[..slash];
    }
    if main.len >= 2 && main[0] == '[' && main[main.len - 1] == ']' {
        c.transfer = main[1..main.len - 1];
        return c;
    }
    let colon = find(main, ":");
    if colon >= 0 {
        c.name = main[..colon];
        c.sub = main[colon + 1..];
    } else {
        c.name = main;
    }
    return c;
}

fn push_field(code: u8, value: const u8[:], lim: Limits&, line_no: i64, records: QifRecord[>..]&, cur: i64, extra: QifField[>..]&) -> Fault {
    if extra.len >= lim.max_fields { return fault(F_LIMIT, line_no, 1, "", "more fields than max_fields"); }
    extra.push(QifField { code: code, value: value });
    records[cur].field_count += 1;
    return no_fault();
}

// q_group gives the thousands mark that pairs with a decimal mark.
fn q_group(dec: u8) -> u8 {
    var grp: u8 = ',';
    if dec == ',' { grp = '.'; }
    return grp;
}

fn q_amount(value: const u8[:], opts: QifOptions&, dec: u8, line_no: i64, code: u8) -> Amount, Fault {
    let a, f = parse_amount(value, currency_exponent(opts.currency), dec, q_group(dec));
    if f.kind != F_NONE {
        var tag: const u8[:] = "T";
        if code == '$' { tag = "$"; }
        return a, with_pos(f, line_no, tag);
    }
    return Amount { minor: a.minor, exp: a.exp, currency: opts.currency }, no_fault();
}

// parse_qif reads a QIF file.
fn parse_qif(input: const u8[:], lim: Limits&, opts: QifOptions&,
             records: QifRecord[>..]&, splits: QifSplit[>..]&, extra: QifField[>..]&) -> Fault {
    let fi = check_input(input, lim);
    if fi.kind != F_NONE { return fi; }
    var dec: u8 = '.';
    if opts.decimal != 0 { dec = opts.decimal; }
    if dec != '.' && dec != ',' { return fault(F_SYNTAX, 0, 0, "", "decimal mark is not . or ,"); }
    var pivot: i64 = 70;
    if opts.pivot != 0 { pivot = opts.pivot; }
    var order = opts.date_order;
    if order == DATE_DETECT {
        let o, f = detect_order(input, lim, pivot);
        if f.kind != F_NONE { return f; }
        order = o;
    }
    var sect: i32 = 0;
    var open = false;
    var cur: i64 = 0;
    var pos = skip_bom(input);
    var line_no: i64 = 0;
    while pos < input.len {
        let e, bad = line_end(input, pos, lim.max_line);
        line_no += 1;
        if bad != 0 { return line_fault(bad, line_no, 1); }
        let line = trim_cr(input[pos..e]);
        pos = e + 1;
        if line.len == 0 { continue; }
        let code = line[0];
        if code == '!' {
            let k = section_of(line[1..]);
            if k < 0 { return fault(F_UNKNOWN_TAG, line_no, 1, line, "section header is not known"); }
            open = false;
            if k > 0 { sect = k; }
            continue;
        }
        if code == '^' { open = false; continue; }
        if sect == 0 { return fault(F_SYNTAX, line_no, 1, "", "record before a ! header"); }
        let value = trim(line[1..]);
        if value.len > lim.max_field { return fault(F_LIMIT, line_no, 1, "", "field is longer than max_field"); }
        if !open {
            if records.len >= lim.max_records { return fault(F_LIMIT, line_no, 1, "", "more records than max_records"); }
            records.push(new_record(sect, line_no, extra.len, splits.len));
            cur = records.len - 1;
            open = true;
        }
        if !typed_section(sect) {
            let f = push_field(code, line[1..], lim, line_no, records, cur, extra);
            if f.kind != F_NONE { return f; }
            continue;
        }
        let invst = sect == Q_INVST || sect == Q_PORT;
        var f = no_fault();
        if code == 'D' {
            let d, df = parse_qif_date(value, order, pivot, line_no);
            if df.kind != F_NONE { return df; }
            records[cur].date = d;
        } else if code == 'T' || code == 'U' {
            // A value that starts with ... has no numeric value: the
            // line stays a field.
            if is_dots(value) {
                f = push_field(code, line[1..], lim, line_no, records, cur, extra);
            } else if code == 'U' {
                // The U code always wins over T, in both orders. The
                // value that was there before moves to the alt fields.
                let a, af = q_amount(value, opts, dec, line_no, code);
                if af.kind != F_NONE { return af; }
                if records[cur].has_amount {
                    records[cur].alt_amount = records[cur].amount;
                    records[cur].has_alt_amount = true;
                }
                records[cur].amount = a;
                records[cur].has_amount = true;
                records[cur].amount_code = 'U';
            } else if !records[cur].has_amount || records[cur].amount_code == 'T' {
                let a, af = q_amount(value, opts, dec, line_no, code);
                if af.kind != F_NONE { return af; }
                records[cur].amount = a;
                records[cur].has_amount = true;
                records[cur].amount_code = 'T';
            } else {
                // A T after a U loses, but the value stays reachable.
                let a, af = q_amount(value, opts, dec, line_no, code);
                if af.kind != F_NONE { return af; }
                records[cur].alt_amount = a;
                records[cur].has_alt_amount = true;
            }
        } else if code == 'F' {
            records[cur].reimbursable = true;
            records[cur].reimbursable_text = value;
        } else if code == 'C' {
            if value.len > 0 {
                let m = value[0];
                if m != '*' && m != 'c' && m != 'X' && m != 'R' { return fault(F_SYNTAX, line_no, 2, "C", "cleared mark is not *, c, X or R"); }
                records[cur].cleared = m;
            }
        } else if code == 'N' {
            if invst { records[cur].action = value; } else { records[cur].number = value; }
        } else if code == 'P' {
            records[cur].payee = value;
        } else if code == 'M' {
            records[cur].memo = value;
        } else if code == 'L' {
            records[cur].category = value;
        } else if invst && code == 'Y' {
            records[cur].security = value;
        } else if invst && (code == 'I' || code == 'Q' || code == 'O') {
            let r, rf = parse_ratio(value, dec, q_group(dec), line_no, code);
            if rf.kind != F_NONE { return rf; }
            if code == 'I' {
                records[cur].price = r;
                records[cur].has_price = true;
                records[cur].price_text = value;
            } else if code == 'Q' {
                records[cur].quantity = r;
                records[cur].has_quantity = true;
                records[cur].quantity_text = value;
            } else {
                records[cur].commission = r;
                records[cur].has_commission = true;
                records[cur].commission_text = value;
            }
        } else if !invst && (code == 'S' || code == 'E' || code == '$' || code == '%') {
            if code == 'S' || records[cur].split_count == 0 {
                if splits.len >= lim.max_splits { return fault(F_LIMIT, line_no, 1, "S", "more splits than max_splits"); }
                splits.push(new_split());
                records[cur].split_count += 1;
            }
            let last = splits.len - 1;
            if code == 'S' { splits[last].category = value; }
            else if code == 'E' { splits[last].memo = value; }
            else if code == '%' {
                // A trailing word like % goes: the number stands in
                // front of the first blank.
                let sp = find(value, " ");
                var t = value;
                if sp > 0 { t = value[..sp]; }
                let r, rf = parse_ratio(t, dec, q_group(dec), line_no, code);
                if rf.kind != F_NONE { return rf; }
                splits[last].percent = r;
                splits[last].has_percent = true;
                splits[last].percent_text = value;
            }
            else if is_dots(value) {
                // A $ value that starts with ... stays a field.
                f = push_field(code, line[1..], lim, line_no, records, cur, extra);
            }
            else {
                let a, af = q_amount(value, opts, dec, line_no, code);
                if af.kind != F_NONE { return af; }
                splits[last].amount = a;
                splits[last].has_amount = true;
            }
        } else {
            f = push_field(code, line[1..], lim, line_no, records, cur, extra);
        }
        if f.kind != F_NONE { return f; }
    }
    return no_fault();
}
