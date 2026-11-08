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
    percent: const u8[:],
}

// QifRecord holds one record. The splits and the fields are ranges of
// the arrays of the caller. The date has year 0 when absent. The
// investment values price, quantity and commission stay as text;
// parse_number reads them.
struct QifRecord {
    section: i32,
    line: i32,
    date: Date,
    has_amount: bool,
    amount: Amount,
    cleared: u8,
    number: const u8[:],
    payee: const u8[:],
    memo: const u8[:],
    category: const u8[:],
    action: const u8[:],
    security: const u8[:],
    price: const u8[:],
    quantity: const u8[:],
    commission: const u8[:],
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
// header.
fn section_of(h: const u8[:]) -> i32 {
    let t = trim(h);
    if ieq(t, "Account") { return Q_ACCOUNT; }
    if ieq(t, "Type:Bank") { return Q_BANK; }
    if ieq(t, "Type:Cash") { return Q_CASH; }
    if ieq(t, "Type:CCard") { return Q_CCARD; }
    if ieq(t, "Type:Oth A") { return Q_OTH_A; }
    if ieq(t, "Type:Oth L") { return Q_OTH_L; }
    if ieq(t, "Type:Invst") { return Q_INVST; }
    if ieq(t, "Type:Port") { return Q_PORT; }
    if ieq(t, "Type:Cat") { return Q_CAT; }
    if ieq(t, "Type:Class") { return Q_CLASS; }
    if ieq(t, "Type:Security") { return Q_SECURITY; }
    if ieq(t, "Type:Prices") { return Q_PRICES; }
    if ieq(t, "Type:Memorized") { return Q_MEMORIZED; }
    if ieq(t, "Option:AutoSwitch") || ieq(t, "Clear:AutoSwitch") { return 0; }
    return -1;
}

fn typed_section(k: i32) -> bool {
    return k == Q_BANK || k == Q_CASH || k == Q_CCARD || k == Q_OTH_A || k == Q_OTH_L
        || k == Q_INVST || k == Q_PORT || k == Q_MEMORIZED;
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
    return QifRecord {
        section: sect, line: line_no as i32, date: no_date(), has_amount: false, amount: z, cleared: 0,
        number: "", payee: "", memo: "", category: "", action: "", security: "", price: "", quantity: "", commission: "",
        split_start: splits as i32, split_count: 0, field_start: fields as i32, field_count: 0,
    };
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

fn q_amount(value: const u8[:], opts: QifOptions&, dec: u8, line_no: i64, code: u8) -> Amount, Fault {
    var grp: u8 = ',';
    if dec == ',' { grp = '.'; }
    let a, f = parse_amount(value, currency_exponent(opts.currency), dec, grp);
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
            if k < 0 { return fault(F_UNKNOWN_TAG, line_no, 1, "!", "section header is not known"); }
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
        } else if code == 'T' {
            let a, af = q_amount(value, opts, dec, line_no, code);
            if af.kind != F_NONE { return af; }
            records[cur].amount = a;
            records[cur].has_amount = true;
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
        } else if invst && code == 'I' {
            records[cur].price = value;
        } else if invst && code == 'Q' {
            records[cur].quantity = value;
        } else if invst && code == 'O' {
            records[cur].commission = value;
        } else if !invst && (code == 'S' || code == 'E' || code == '$' || code == '%') {
            if code == 'S' || records[cur].split_count == 0 {
                if splits.len >= lim.max_splits { return fault(F_LIMIT, line_no, 1, "S", "more splits than max_splits"); }
                splits.push(QifSplit { category: "", memo: "", has_amount: false, amount: Amount { minor: 0, exp: 2, currency: "" }, percent: "" });
                records[cur].split_count += 1;
            }
            let last = splits.len - 1;
            if code == 'S' { splits[last].category = value; }
            else if code == 'E' { splits[last].memo = value; }
            else if code == '%' { splits[last].percent = value; }
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
