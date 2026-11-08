// The typed list records of the QIF files.
//
// parse_qif_lists reads the list sections of a QIF file: Account, Cat,
// Budget, Class, Tag, Security, Payee and Prices. Each record of a list
// gives a QifItem with named fields. Each line of the Prices section
// gives a QifPrice. The transaction sections are skipped; parse_qif reads
// them. A line with a code that the section does not know stays a field
// in the array extra, so the reader drops no line. A record that has no
// ^ before the next header or the end of the file is kept.
//
// write_qif_lists writes the records back. Every text is checked, so a
// value cannot add a field or end a record.
namespace bank_statement;

import std;
import fault;
import text;
import limits;
import amount;
import date;
import qif;
import write_text;
import qif_write;

// QifItem holds one record of a list. The fields that a section does not
// use stay empty. The name is the N line, or the P line of a payee.
// The kind is the T line of an account or a security. The budget amounts
// of a category are a range of the array budgets. The address lines of a
// payee are a range of the array lines. The unknown lines are a range of
// the array extra.
struct QifItem {
    section: i32,
    line: i32,
    name: const u8[:],
    description: const u8[:],
    kind: const u8[:],
    symbol: const u8[:],
    goal: const u8[:],
    schedule: const u8[:],
    has_limit: bool,
    limit: Amount,
    has_balance_date: bool,
    balance_date: Date,
    has_balance: bool,
    balance: Amount,
    tax: bool,
    income: bool,
    expense: bool,
    budget_start: i32,
    budget_count: i32,
    address_start: i32,
    address_count: i32,
    city: const u8[:],
    state: const u8[:],
    zip: const u8[:],
    country: const u8[:],
    phone: const u8[:],
    account: const u8[:],
    field_start: i32,
    field_count: i32,
}

// QifPrice holds one line of the Prices section: "symbol",price,"date".
struct QifPrice {
    symbol: const u8[:],
    price: Rational,
    price_text: const u8[:],
    date: Date,
}

fn list_section(k: i32) -> bool {
    return k == Q_ACCOUNT || k == Q_CAT || k == Q_BUDGET || k == Q_CLASS || k == Q_TAG
        || k == Q_SECURITY || k == Q_PAYEE;
}

fn new_item(sect: i32, line_no: i64, fields: i64, lines: i64, budgets: i64) -> QifItem {
    let z = Amount { minor: 0, exp: 2, currency: "" };
    return QifItem {
        section: sect, line: line_no as i32, name: "", description: "", kind: "", symbol: "",
        goal: "", schedule: "", has_limit: false, limit: z, has_balance_date: false,
        balance_date: no_date(), has_balance: false, balance: z, tax: false, income: false,
        expense: false, budget_start: budgets as i32, budget_count: 0, address_start: lines as i32,
        address_count: 0, city: "", state: "", zip: "", country: "", phone: "", account: "",
        field_start: fields as i32, field_count: 0,
    };
}

// unquote takes the quotes off a part of a price line. A quote inside
// the text, or a quote on one side only, is a fault.
fn unquote(s: const u8[:]) -> const u8[:], bool {
    let t = trim(s);
    if t.len >= 2 && t[0] == '"' && t[t.len - 1] == '"' {
        let inner = t[1..t.len - 1];
        if find(inner, "\"") >= 0 { return "", false; }
        return inner, true;
    }
    if find(t, "\"") >= 0 { return "", false; }
    return t, true;
}

// parse_price reads one price line. A comma inside quotes does not split
// the line. A line with more or fewer than three parts is a fault.
fn parse_price(line: const u8[:], dec: u8, order: i32, pivot: i64, line_no: i64) -> QifPrice, Fault {
    let z = QifPrice { symbol: "", price: Rational { num: 0, den: 1 }, price_text: "", date: no_date() };
    var cuts = [0, 0, 0, 0, 0, 0];
    var n: i64 = 0;
    var start: i64 = 0;
    var inq = false;
    var i: i64 = 0;
    while i <= line.len {
        var cut = i == line.len;
        if !cut {
            if line[i] == '"' { inq = !inq; }
            else if line[i] == ',' && !inq { cut = true; }
        }
        if cut {
            if n < 3 { cuts[n * 2] = start; cuts[n * 2 + 1] = i; }
            n += 1;
            start = i + 1;
            if n > 3 { return z, fault(F_SYNTAX, line_no, 1, "", "a price line holds more than three parts"); }
        }
        i += 1;
    }
    if inq || n != 3 { return z, fault(F_SYNTAX, line_no, 1, "", "a price line needs a symbol, a price and a date"); }
    let a = line[cuts[0]..cuts[1]];
    let b = line[cuts[2]..cuts[3]];
    let c = line[cuts[4]..cuts[5]];
    let sym, ok1 = unquote(a);
    if !ok1 || sym.len == 0 { return z, fault(F_SYNTAX, line_no, 1, "", "the symbol of a price is empty or has a quote"); }
    let txt, ok2 = unquote(b);
    if !ok2 { return z, fault(F_AMOUNT, line_no, 1, "I", "the price has a quote"); }
    let r, rf = parse_ratio(txt, dec, q_group(dec), line_no, 'I');
    if rf.kind != F_NONE { return z, rf; }
    let dt, ok3 = unquote(c);
    if !ok3 { return z, fault(F_DATE, line_no, 1, "D", "the date of a price has a quote"); }
    let d, df = parse_qif_date(dt, order, pivot, line_no);
    if df.kind != F_NONE { return z, df; }
    return QifPrice { symbol: sym, price: r, price_text: txt, date: d }, no_fault();
}

fn push_extra(code: u8, value: const u8[:], lim: Limits&, line_no: i64, items: QifItem[>..]&, cur: i64, extra: QifField[>..]&) -> Fault {
    if extra.len >= lim.max_fields { return fault(F_LIMIT, line_no, 1, "", "more fields than max_fields"); }
    extra.push(QifField { code: code, value: value });
    items[cur].field_count += 1;
    return no_fault();
}

// item_field stores one line in the open record. A scalar that is set
// already, and a code that the section does not know, go to extra.
fn item_field(code: u8, value: const u8[:], raw: const u8[:], sect: i32, cur: i64, opts: QifOptions&,
              dec: u8, order: i32, pivot: i64, lim: Limits&, line_no: i64,
              items: QifItem[>..]&, budgets: Amount[>..]&, lines: QifField[>..]&, extra: QifField[>..]&) -> Fault {
    if sect == Q_PAYEE {
        if code == 'P' && items[cur].name.len == 0 { items[cur].name = value; return no_fault(); }
        if code == 'A' {
            if lines.len >= lim.max_fields { return fault(F_LIMIT, line_no, 1, "", "more fields than max_fields"); }
            lines.push(QifField { code: 'A', value: value });
            items[cur].address_count += 1;
            return no_fault();
        }
        if code == 'C' && items[cur].city.len == 0 { items[cur].city = value; return no_fault(); }
        if code == 'S' && items[cur].state.len == 0 { items[cur].state = value; return no_fault(); }
        if code == 'Z' && items[cur].zip.len == 0 { items[cur].zip = value; return no_fault(); }
        if code == 'Y' && items[cur].country.len == 0 { items[cur].country = value; return no_fault(); }
        if code == 'N' && items[cur].phone.len == 0 { items[cur].phone = value; return no_fault(); }
        if code == '#' && items[cur].account.len == 0 { items[cur].account = value; return no_fault(); }
        return push_extra(code, raw, lim, line_no, items, cur, extra);
    }
    if code == 'N' && items[cur].name.len == 0 { items[cur].name = value; return no_fault(); }
    if code == 'D' && items[cur].description.len == 0 { items[cur].description = value; return no_fault(); }
    if sect == Q_ACCOUNT {
        if code == 'T' && items[cur].kind.len == 0 { items[cur].kind = value; return no_fault(); }
        if code == 'L' && !items[cur].has_limit {
            let a, af = q_amount(value, opts, dec, line_no, 'T');
            if af.kind != F_NONE { return af; }
            items[cur].limit = a;
            items[cur].has_limit = true;
            return no_fault();
        }
        if code == '$' && !items[cur].has_balance {
            let a, af = q_amount(value, opts, dec, line_no, '$');
            if af.kind != F_NONE { return af; }
            items[cur].balance = a;
            items[cur].has_balance = true;
            return no_fault();
        }
        if code == '/' && !items[cur].has_balance_date {
            let d, df = parse_qif_date(value, order, pivot, line_no);
            if df.kind != F_NONE { return df; }
            items[cur].balance_date = d;
            items[cur].has_balance_date = true;
            return no_fault();
        }
    } else if sect == Q_SECURITY {
        if code == 'T' && items[cur].kind.len == 0 { items[cur].kind = value; return no_fault(); }
        if code == 'S' && items[cur].symbol.len == 0 { items[cur].symbol = value; return no_fault(); }
        if code == 'G' && items[cur].goal.len == 0 { items[cur].goal = value; return no_fault(); }
    } else if sect == Q_CAT || sect == Q_BUDGET {
        if code == 'T' && !items[cur].tax { items[cur].tax = true; return no_fault(); }
        if code == 'I' && !items[cur].income { items[cur].income = true; return no_fault(); }
        if code == 'E' && !items[cur].expense { items[cur].expense = true; return no_fault(); }
        if code == 'R' && items[cur].schedule.len == 0 { items[cur].schedule = value; return no_fault(); }
        if code == 'B' {
            if budgets.len >= lim.max_fields { return fault(F_LIMIT, line_no, 1, "", "more fields than max_fields"); }
            let a, af = q_amount(value, opts, dec, line_no, 'T');
            if af.kind != F_NONE { return af; }
            budgets.push(a);
            items[cur].budget_count += 1;
            return no_fault();
        }
    } else if sect == Q_CLASS {
        if code == 'R' && items[cur].schedule.len == 0 { items[cur].schedule = value; return no_fault(); }
    }
    return push_extra(code, raw, lim, line_no, items, cur, extra);
}

// parse_qif_lists reads the list sections of a QIF file. DATE_DETECT
// reads like DATE_AUTO here: the dates of the lists are read one by one.
fn parse_qif_lists(input: const u8[:], lim: Limits&, opts: QifOptions&, items: QifItem[>..]&,
                   budgets: Amount[>..]&, lines: QifField[>..]&, extra: QifField[>..]&,
                   prices: QifPrice[>..]&) -> Fault {
    let fi = check_input(input, lim);
    if fi.kind != F_NONE { return fi; }
    var dec: u8 = '.';
    if opts.decimal != 0 { dec = opts.decimal; }
    if dec != '.' && dec != ',' { return fault(F_SYNTAX, 0, 0, "", "decimal mark is not . or ,"); }
    var pivot: i64 = 70;
    if opts.pivot != 0 { pivot = opts.pivot; }
    var order = opts.date_order;
    if order == DATE_DETECT { order = DATE_AUTO; }
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
        if sect == Q_PRICES {
            if prices.len >= lim.max_records { return fault(F_LIMIT, line_no, 1, "", "more records than max_records"); }
            if line.len > lim.max_field { return fault(F_LIMIT, line_no, 1, "", "field is longer than max_field"); }
            let p, pf = parse_price(line, dec, order, pivot, line_no);
            if pf.kind != F_NONE { return pf; }
            prices.push(p);
            continue;
        }
        if !list_section(sect) { continue; }
        let value = trim(line[1..]);
        if value.len > lim.max_field { return fault(F_LIMIT, line_no, 1, "", "field is longer than max_field"); }
        if !open {
            if items.len >= lim.max_records { return fault(F_LIMIT, line_no, 1, "", "more records than max_records"); }
            items.push(new_item(sect, line_no, extra.len, lines.len, budgets.len));
            cur = items.len - 1;
            open = true;
        }
        let f = item_field(code, value, line[1..], sect, cur, opts, dec, order, pivot, lim, line_no,
                           items, budgets, lines, extra);
        if f.kind != F_NONE { return f; }
    }
    return no_fault();
}

// ---- the writer ----

// put_text writes a line when the text is not empty.
fn put_text(out: u8[>..]&, code: u8, value: const u8[:], lim: Limits&) -> Fault {
    if value.len == 0 { return no_fault(); }
    return put_line(out, code, value, "", lim);
}

fn put_flag(out: u8[>..]&, code: u8) {
    out.push(code);
    out.push('\n');
}

// write_item writes the lines of one record.
fn write_item(out: u8[>..]&, it: QifItem, budgets: Amount[>..]&, lines: QifField[>..]&,
              extra: QifField[>..]&, order: i32, lim: Limits&) -> Fault {
    var f = no_fault();
    if it.name.len == 0 { return fault(F_SYNTAX, 0, 0, "N", "a list record needs a name"); }
    if it.section == Q_PAYEE {
        f = put_line(out, 'P', it.name, "P", lim); if f.kind != F_NONE { return f; }
        var i: i64 = it.address_start as i64;
        let end: i64 = i + (it.address_count as i64);
        while i < end {
            f = put_line(out, 'A', lines[i].value, "A", lim); if f.kind != F_NONE { return f; }
            i += 1;
        }
        f = put_text(out, 'C', it.city, lim); if f.kind != F_NONE { return f; }
        f = put_text(out, 'S', it.state, lim); if f.kind != F_NONE { return f; }
        f = put_text(out, 'Z', it.zip, lim); if f.kind != F_NONE { return f; }
        f = put_text(out, 'Y', it.country, lim); if f.kind != F_NONE { return f; }
        f = put_text(out, 'N', it.phone, lim); if f.kind != F_NONE { return f; }
        f = put_text(out, '#', it.account, lim); if f.kind != F_NONE { return f; }
    } else {
        f = put_line(out, 'N', it.name, "N", lim); if f.kind != F_NONE { return f; }
        f = put_text(out, 'D', it.description, lim); if f.kind != F_NONE { return f; }
        if it.section == Q_ACCOUNT || it.section == Q_SECURITY {
            f = put_text(out, 'T', it.kind, lim); if f.kind != F_NONE { return f; }
        }
        if it.section == Q_SECURITY {
            f = put_text(out, 'S', it.symbol, lim); if f.kind != F_NONE { return f; }
            f = put_text(out, 'G', it.goal, lim); if f.kind != F_NONE { return f; }
        }
        if it.section == Q_ACCOUNT {
            if it.has_limit { put_money(out, 'L', it.limit); }
            if it.has_balance_date {
                let fd = check_date(it.balance_date, "/");
                if fd.kind != F_NONE { return fd; }
                out.push('/');
                put_qif_date(out, it.balance_date, order);
                out.push('\n');
            }
            if it.has_balance { put_money(out, '$', it.balance); }
        }
        if it.section == Q_CAT || it.section == Q_BUDGET {
            if it.tax { put_flag(out, 'T'); }
            if it.income { put_flag(out, 'I'); }
            if it.expense { put_flag(out, 'E'); }
        }
        if it.section == Q_CAT || it.section == Q_BUDGET || it.section == Q_CLASS {
            f = put_text(out, 'R', it.schedule, lim); if f.kind != F_NONE { return f; }
        }
        if it.section == Q_CAT || it.section == Q_BUDGET {
            var j: i64 = it.budget_start as i64;
            let jend: i64 = j + (it.budget_count as i64);
            while j < jend { put_money(out, 'B', budgets[j]); j += 1; }
        }
    }
    return write_fields(out, it.field_start as i64, it.field_count as i64, extra, lim);
}

// put_price writes the value of a price: a decimal when the denominator
// is a power of ten, else a fraction n/d. A denominator below 1 is false.
fn put_price(out: u8[>..]&, r: Rational) -> bool {
    if r.den < 1 { return false; }
    var k: i32 = 0;
    var d: i64 = 1;
    while d < r.den && d <= 100000000000000000 { d = d * 10; k += 1; }
    if d == r.den {
        put_amount(out, r.num, k, '.');
        return true;
    }
    put_amount(out, r.num, 0, '.');
    out.push('/');
    put_amount(out, r.den, 0, '.');
    return true;
}

fn write_price(out: u8[>..]&, p: QifPrice, order: i32, lim: Limits&) -> Fault {
    let fs = check_text(p.symbol, "S", lim);
    if fs.kind != F_NONE { return fs; }
    if p.symbol.len == 0 || find(p.symbol, "\"") >= 0 {
        return fault(F_SYNTAX, 0, 0, "S", "the symbol of a price is empty or has a quote");
    }
    let fd = check_date(p.date, "D");
    if fd.kind != F_NONE { return fd; }
    var v: u8[>..] = [];
    if !put_price(v, p.price) { return fault(F_AMOUNT, 0, 0, "I", "the denominator of a price is not positive"); }
    out.push('"'); put(out, p.symbol); out.push('"'); out.push(',');
    put(out, v);
    out.push(','); out.push('"');
    put_qif_date(out, p.date, order);
    out.push('"'); out.push('\n');
    put(out, "^\n");
    return no_fault();
}

// write_qif_lists appends the list records and the prices as QIF text.
// A section header comes before the first record and whenever the
// section changes. The prices come last, under one !Type:Prices header.
fn write_qif_lists(items: QifItem[>..]&, budgets: Amount[>..]&, lines: QifField[>..]&, extra: QifField[>..]&,
                   prices: QifPrice[>..]&, opts: QifWriteOptions, lim: Limits&, out: u8[>..]&) -> Fault {
    var order = opts.date_order;
    if order == 0 { order = DATE_MDY; }
    if order != DATE_MDY && order != DATE_DMY && order != DATE_YMD {
        return fault(F_SYNTAX, 0, 0, "", "the date order is not US, EU or ISO");
    }
    var sect: i32 = -1;
    var n: i64 = 0;
    while n < items.len {
        let it = items[n];
        if !list_section(it.section) { return fault(F_SYNTAX, 0, 0, "", "this is not a list section"); }
        if it.section != sect {
            put(out, section_header(it.section));
            out.push('\n');
            sect = it.section;
        }
        let f = write_item(out, it, budgets, lines, extra, order, lim);
        if f.kind != F_NONE { return with_pos(f, n + 1, f.tag); }
        put(out, "^\n");
        let fs = check_size(out, lim);
        if fs.kind != F_NONE { return fs; }
        n += 1;
    }
    if prices.len > 0 {
        put(out, "!Type:Prices\n");
        var i: i64 = 0;
        while i < prices.len {
            let f = write_price(out, prices[i], order, lim);
            if f.kind != F_NONE { return with_pos(f, i + 1, f.tag); }
            i += 1;
        }
    }
    return check_size(out, lim);
}
