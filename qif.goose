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

// parse_qif_decoded reads a QIF file.
fn parse_qif_decoded(input: const u8[:], lim: Limits&, opts: QifOptions&,
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

// parse_qif reads a QIF file. When the option names a charset, the
// input is decoded into UTF-8 first, and the decoded text lives in buf.
// The text must outlive the records.
fn parse_qif(input: const u8[:], lim: Limits&, opts: QifOptions&,
             records: QifRecord[>..]&, splits: QifSplit[>..]&, extra: QifField[>..]&,
             buf: u8[>..]&) -> Fault {
    if opts.charset != 0 {
        let mark = buf.len;
        let f = decode_charset(opts.charset, input, lim, buf);
        if f.kind != F_NONE { return f; }
        return parse_qif_decoded(buf[mark..], lim, opts, records, splits, extra);
    }
    return parse_qif_decoded(input, lim, opts, records, splits, extra);
}
