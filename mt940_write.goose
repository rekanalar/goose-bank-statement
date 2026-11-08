// The MT940 writer of the bank_statement package.
//
// write_mt940 appends MT940 statements to the buffer of the caller. It
// takes the statements, entries and balances that parse_mt940 gives.
// The writer applies the field rules of the SWIFT manual: the widths,
// the character set and the order of the tags. A text that leaves the
// character set, a field that is too wide, a line that would start a
// new tag and a statement whose balances do not add up are faults. The
// amount uses a comma as the decimal mark. No text is cut.
namespace bank_statement;

import std;
import fault;
import limits;
import amount;
import date;
import mt940;
import swift;
import write_text;

// yymmdd appends a date as six digits. The reader reads the years 1970
// to 2069.
fn put_yymmdd(out: u8[>..]&, d: Date) {
    put_num(out, (d.year as i64) % 100, 2);
    put_num(out, d.month as i64, 2);
    put_num(out, d.day as i64, 2);
}

fn check_year(d: Date, tag: const u8[:]) -> Fault {
    let f = check_date(d, tag);
    if f.kind != F_NONE { return f; }
    if d.year < 1970 || d.year > 2069 { return fault(F_DATE, 0, 0, tag, "the year is outside 1970 to 2069"); }
    return no_fault();
}

// check_line checks one line of free text: the character set, the
// width and the first byte. A line must not start with a colon, and a
// line must not be a lone minus, because the reader takes those as the
// start of a tag and the end of a message.
fn check_line(tag: const u8[:], s: const u8[:], max: i64) -> Fault {
    for c in s {
        if c < 32 || !swift_char(c) { return fault(F_SYNTAX, 0, 0, tag, "byte outside the SWIFT character set"); }
    }
    let w = check_width(tag, s, 0, max);
    if w.kind != F_NONE { return w; }
    if s.len > 0 && s[0] == ':' { return fault(F_SYNTAX, 0, 0, tag, "a line must not start with a colon"); }
    if s == "-" { return fault(F_SYNTAX, 0, 0, tag, "a line must not be a lone minus"); }
    return no_fault();
}

// amount_text builds the amount of a field: digits, a comma and the
// minor digits. A currency without minor digits keeps the comma.
fn amount_text(minor: i64, exp: i32, buf: u8[>..]&) {
    put_amount(buf, minor, exp, ',');
    if exp == 0 { buf.push(','); }
}

fn magnitude_ok(m: i64) -> bool {
    return m != -9223372036854775808;
}

// signed_part gives the signed minor units of a balance.
fn balance_value(b: Balance) -> i64 {
    var m = b.amount.minor;
    if m < 0 { m = -m; }
    if b.credit { return m; }
    return -m;
}

fn write_balance_line(out: u8[>..]&, tag: const u8[:], b: Balance) -> Fault {
    if !magnitude_ok(b.amount.minor) { return fault(F_AMOUNT, 0, 0, tag, "amount is too large"); }
    let fd = check_year(b.date, tag);
    if fd.kind != F_NONE { return fd; }
    if b.amount.currency.len != 3 || !is_letters(b.amount.currency) {
        return fault(F_SYNTAX, 0, 0, tag, "currency is not three letters");
    }
    var m = b.amount.minor;
    if m < 0 { m = -m; }
    var a: u8[>..] = [];
    amount_text(m, b.amount.exp, a);
    let fa = check_amount(tag, a, 0);
    if fa.kind != F_NONE { return fa; }
    out.push(':'); put(out, tag); out.push(':');
    if b.credit { out.push('C'); } else { out.push('D'); }
    put_yymmdd(out, b.date);
    for c in b.amount.currency { out.push(c); }
    put(out, a);
    out.push('\n');
    return no_fault();
}

// put_text_field writes :tag:value after the checks.
fn put_text_field(out: u8[>..]&, tag: const u8[:], value: const u8[:], max: i64) -> Fault {
    let f = check_line(tag, value, max);
    if f.kind != F_NONE { return f; }
    out.push(':'); put(out, tag); out.push(':');
    put(out, value);
    out.push('\n');
    return no_fault();
}

fn mark_ok(m: const u8[:]) -> bool {
    return m == "D" || m == "C" || m == "RD" || m == "RC";
}

// entry_effect gives the way an entry moves the balance.
fn entry_effect(e: Entry) -> i64, bool {
    var mark = e.mark;
    if mark.len == 0 { return 0, false; }
    if !mark_ok(mark) { return 0, false; }
    if !magnitude_ok(e.amount.minor) { return 0, false; }
    var m = e.amount.minor;
    if m < 0 { m = -m; }
    if mark == "C" || mark == "RD" { return m, true; }
    return -m, true;
}

fn write_entry_lines(out: u8[>..]&, e: Entry, n: i64) -> Fault {
    let tag: const u8[:] = "61";
    if !mark_ok(e.mark) { return with_pos(fault(F_SYNTAX, 0, 0, tag, "mark is not D, C, RD or RC"), n, tag); }
    if !magnitude_ok(e.amount.minor) { return with_pos(fault(F_AMOUNT, 0, 0, tag, "amount is too large"), n, tag); }
    let fd = check_year(e.value_date, tag);
    if fd.kind != F_NONE { return with_pos(fd, n, tag); }
    if e.entry_date.year != 0 {
        let fe = check_date(e.entry_date, tag);
        if fe.kind != F_NONE { return with_pos(fe, n, tag); }
    }
    if e.type_id.len != 4 || (e.type_id[0] != 'S' && e.type_id[0] != 'N' && e.type_id[0] != 'F') {
        return with_pos(fault(F_SYNTAX, 0, 0, tag, "type is not S, N or F and three characters"), n, tag);
    }
    if e.funds_code != 0 && !is_upper(e.funds_code) {
        return with_pos(fault(F_SYNTAX, 0, 0, tag, "funds code is not a capital letter"), n, tag);
    }
    // A reference that holds // would move the bank reference.
    if find(e.customer_ref, "//") >= 0 || find(e.bank_ref, "//") >= 0 {
        return with_pos(fault(F_SYNTAX, 0, 0, tag, "a reference must not hold //"), n, tag);
    }
    var m = e.amount.minor;
    if m < 0 { m = -m; }
    var a: u8[>..] = [];
    amount_text(m, e.amount.exp, a);
    let fa = check_amount(tag, a, 0);
    if fa.kind != F_NONE { return with_pos(fa, n, tag); }
    var head: u8[>..] = [];
    put_yymmdd(head, e.value_date);
    if e.entry_date.year != 0 {
        put_num(head, e.entry_date.month as i64, 2);
        put_num(head, e.entry_date.day as i64, 2);
    }
    put(head, e.mark);
    if e.funds_code != 0 { head.push(e.funds_code); }
    put(head, a);
    put(head, e.type_id);
    if e.customer_ref.len > 0 { put(head, e.customer_ref); } else { put(head, "NONREF"); }
    if e.bank_ref.len > 0 { put(head, "//"); put(head, e.bank_ref); }
    let fc = check_width(tag, e.customer_ref, 0, SW_CUSTOMER_REF);
    if fc.kind != F_NONE { return with_pos(fc, n, tag); }
    let fb = check_width(tag, e.bank_ref, 0, SW_BANK_REF);
    if fb.kind != F_NONE { return with_pos(fb, n, tag); }
    for c in head {
        if !swift_char(c) || c < 32 { return with_pos(fault(F_SYNTAX, 0, 0, tag, "byte outside the SWIFT character set"), n, tag); }
    }
    out.push(':'); put(out, tag); out.push(':');
    put(out, head);
    out.push('\n');
    if e.supplementary.len > 0 {
        let fs = check_line(tag, e.supplementary, SW_SUPPLEMENTARY);
        if fs.kind != F_NONE { return with_pos(fs, n, tag); }
        put(out, e.supplementary);
        out.push('\n');
    }
    if e.narrative.len > 0 {
        var end = e.narrative.len;
        if end > 0 && e.narrative[end - 1] == '\n' { end -= 1; }
        if end > 0 && e.narrative[end - 1] == '\r' { end -= 1; }
        let text = e.narrative[..end];
        let f86 = check_86("86", text, 0);
        if f86.kind != F_NONE { return with_pos(f86, n, "86"); }
        // Every line is checked for a leading colon and the set.
        var start: i64 = 0;
        var i: i64 = 0;
        while i <= text.len {
            if i == text.len || text[i] == '\n' {
                var stop = i;
                if stop > start && text[stop - 1] == '\r' { stop -= 1; }
                let fl = check_line("86", text[start..stop], SW_LINE);
                if fl.kind != F_NONE { return with_pos(fl, n, "86"); }
                start = i + 1;
            }
            i += 1;
        }
        put(out, ":86:");
        var j: i64 = 0;
        while j < text.len {
            if text[j] != '\r' { out.push(text[j]); }
            j += 1;
        }
        out.push('\n');
    }
    return no_fault();
}

// write_floor_line writes a :34F: line: a currency, an optional D or C
// mark and an amount. A mark of 0 and a mark of - mean that the line
// has no mark.
fn write_floor_line(out: u8[>..]&, tag: const u8[:], a: Amount, mark: u8) -> Fault {
    if a.currency.len != 3 || !is_letters(a.currency) {
        return fault(F_SYNTAX, 0, 0, tag, "currency is not three letters");
    }
    if a.minor < 0 { return fault(F_AMOUNT, 0, 0, tag, "the floor limit is negative"); }
    if a.exp != currency_exponent(a.currency) {
        return fault(F_AMOUNT, 0, 0, tag, "the exponent of the amount differs from the currency");
    }
    var m: u8[>..] = [];
    amount_text(a.minor, a.exp, m);
    let f = check_amount(tag, m, 0);
    if f.kind != F_NONE { return f; }
    out.push(':'); put(out, tag); out.push(':');
    for c in a.currency { out.push(c); }
    if mark == 'D' || mark == 'C' { out.push(mark); }
    put(out, m);
    out.push('\n');
    return no_fault();
}

// write_report_time writes a :13D: line: a date, a time, a sign and an
// offset from the Greenwich time.
fn write_report_time(out: u8[>..]&, d: Date, minutes: i32, offset: i32) -> Fault {
    let tag: const u8[:] = "13D";
    let fd = check_date(d, tag);
    if fd.kind != F_NONE { return fd; }
    if d.year < 1970 || d.year > 2069 { return fault(F_DATE, 0, 0, tag, "the year is outside 1970 to 2069"); }
    if minutes < 0 || minutes > 1439 { return fault(F_DATE, 0, 0, tag, "the time of the report is not a time"); }
    if offset < -1439 || offset > 1439 { return fault(F_DATE, 0, 0, tag, "the offset of the report is not a time"); }
    out.push(':'); put(out, tag); out.push(':');
    put_yymmdd(out, d);
    put_num(out, (minutes / 60) as i64, 2);
    put_num(out, (minutes % 60) as i64, 2);
    if offset < 0 { out.push('-'); } else { out.push('+'); }
    var o = offset;
    if o < 0 { o = -o; }
    put_num(out, (o / 60) as i64, 2);
    put_num(out, (o % 60) as i64, 2);
    out.push('\n');
    return no_fault();
}

// write_total_line writes a :90D: or a :90C: line: a count, a currency
// and an amount.
fn write_total_line(out: u8[>..]&, tag: const u8[:], count: i64, a: Amount) -> Fault {
    if count < 0 || count > 99999 { return fault(F_SYNTAX, 0, 0, tag, "the count has more than five digits"); }
    if a.currency.len != 3 || !is_letters(a.currency) {
        return fault(F_SYNTAX, 0, 0, tag, "currency is not three letters");
    }
    if a.minor < 0 { return fault(F_AMOUNT, 0, 0, tag, "the total is negative"); }
    if a.exp != currency_exponent(a.currency) {
        return fault(F_AMOUNT, 0, 0, tag, "the exponent of the amount differs from the currency");
    }
    var m: u8[>..] = [];
    amount_text(a.minor, a.exp, m);
    let f = check_amount(tag, m, 0);
    if f.kind != F_NONE { return f; }
    out.push(':'); put(out, tag); out.push(':');
    put_num(out, count, 1);
    for c in a.currency { out.push(c); }
    put(out, m);
    out.push('\n');
    return no_fault();
}

// write_entry_block writes the entries of a statement. It gives the sum
// of their effect, the number and the sum of the debit entries and the
// number and the sum of the credit entries. The currency is the one the
// entries take.
fn write_entry_block(out: u8[>..]&, st: Statement, entries: Entry[>..]&, cur: const u8[:]) -> i64, i64, i64, i64, i64, Fault {
    var sum: i64 = 0;
    var dsum: i64 = 0;
    var csum: i64 = 0;
    var dn: i64 = 0;
    var cn: i64 = 0;
    let ex = currency_exponent(cur);
    var i: i64 = st.entry_start as i64;
    let end = i + (st.entry_count as i64);
    while i < end {
        let e = entries[i];
        let n = i - (st.entry_start as i64) + 1;
        if e.amount.currency.len > 0 && e.amount.currency != cur {
            return 0, 0, 0, 0, 0, with_pos(fault(F_SYNTAX, 0, 0, "61", "the currency of the entry differs from the currency of the statement"), n, "61");
        }
        if e.amount.exp != ex {
            return 0, 0, 0, 0, 0, with_pos(fault(F_AMOUNT, 0, 0, "61", "the exponent of the amount differs from the currency"), n, "61");
        }
        let eff, ok = entry_effect(e);
        if !ok { return 0, 0, 0, 0, 0, with_pos(fault(F_SYNTAX, 0, 0, "61", "mark is not D, C, RD or RC"), n, "61"); }
        if (eff > 0 && sum > 9223372036854775807 - eff) || (eff < 0 && sum < -9223372036854775807 - eff) {
            return 0, 0, 0, 0, 0, fault(F_OVERFLOW, 0, 0, "61", "the sum of the entries overflows");
        }
        sum += eff;
        var m = e.amount.minor;
        if m < 0 { m = -m; }
        if eff < 0 {
            dn += 1;
            let s, ok2 = add_checked(dsum, m);
            if !ok2 { return 0, 0, 0, 0, 0, fault(F_OVERFLOW, 0, 0, "90D", "sum of entries does not fit in 64 bits"); }
            dsum = s;
        } else {
            cn += 1;
            let s, ok2 = add_checked(csum, m);
            if !ok2 { return 0, 0, 0, 0, 0, fault(F_OVERFLOW, 0, 0, "90C", "sum of entries does not fit in 64 bits"); }
            csum = s;
        }
        let f = write_entry_lines(out, e, n);
        if f.kind != F_NONE { return 0, 0, 0, 0, 0, f; }
        i += 1;
    }
    return sum, dn, dsum, cn, csum, no_fault();
}

// write_one writes one statement. The fields come in the order of the
// manual: :20:, :21:, :25:, :28C:, the floor limits :34F:, the report
// time :13D:, the opening balance :60F:, the entries :61:, the closing
// balance :62F:, the balances :64: and :65: and the totals :90D: and
// :90C:. A statement holds the balances. An interim report holds no
// balance and needs a floor limit for the currency of its entries.
fn write_one(out: u8[>..]&, st: Statement, entries: Entry[>..]&, lim: Limits&) -> Fault {
    if st.reference.len == 0 { return fault(F_SYNTAX, 0, 0, "20", "a statement needs a reference"); }
    if st.account.len == 0 { return fault(F_SYNTAX, 0, 0, "25", "a statement needs an account"); }
    if st.number.len == 0 { return fault(F_SYNTAX, 0, 0, "28C", "a statement needs a number"); }
    // A statement holds both balances. An interim report holds none.
    let has_open = st.opening.kind != 0;
    let has_close = st.closing.kind != 0;
    if has_open != has_close {
        if has_open { return fault(F_SYNTAX, 0, 0, "62F", "a statement needs a closing balance"); }
        return fault(F_SYNTAX, 0, 0, "60F", "a statement needs an opening balance");
    }
    // The currency of the entries is the currency of the opening
    // balance. A report without one takes the currency of its floor
    // limit.
    var cur = st.floor.currency;
    if has_open { cur = st.opening.amount.currency; }
    if cur.len != 3 || !is_letters(cur) {
        return fault(F_SYNTAX, 0, 0, "60F", "the statement needs a currency");
    }
    var f = put_text_field(out, "20", st.reference, SW_REF);
    if f.kind != F_NONE { return f; }
    if st.related_ref.len > 0 {
        f = put_text_field(out, "21", st.related_ref, SW_REF);
        if f.kind != F_NONE { return f; }
    }
    f = put_text_field(out, "25", st.account, SW_ACCOUNT);
    if f.kind != F_NONE { return f; }
    var num: u8[>..] = [];
    put(num, st.number);
    if st.sequence.len > 0 { num.push('/'); put(num, st.sequence); }
    f = check_statement_number("28C", num, 0);
    if f.kind != F_NONE { return f; }
    f = put_text_field(out, "28C", num, 11);
    if f.kind != F_NONE { return f; }
    if st.floor.currency.len > 0 {
        f = write_floor_line(out, "34F", st.floor, st.floor_mark);
        if f.kind != F_NONE { return f; }
    }
    if st.floor2.currency.len > 0 {
        f = write_floor_line(out, "34F", st.floor2, st.floor2_mark);
        if f.kind != F_NONE { return f; }
    }
    if st.has_report_time {
        f = write_report_time(out, st.report_date, st.report_minutes, st.report_offset);
        if f.kind != F_NONE { return f; }
    }
    var sum = 0;
    if has_open {
        var open_tag: const u8[:] = "60F";
        if st.opening.intermediate { open_tag = "60M"; }
        f = write_balance_line(out, open_tag, st.opening);
        if f.kind != F_NONE { return f; }
        sum = balance_value(st.opening);
    }
    let add, dn, dsum, cn, csum, fe = write_entry_block(out, st, entries, cur);
    if fe.kind != F_NONE { return fe; }
    if (add > 0 && sum > 9223372036854775807 - add) || (add < 0 && sum < -9223372036854775807 - add) {
        return fault(F_OVERFLOW, 0, 0, "61", "the sum of the entries overflows");
    }
    sum += add;
    if has_close {
        var close_tag: const u8[:] = "62F";
        if st.closing.intermediate { close_tag = "62M"; }
        let want = balance_value(st.closing);
        if sum != want { return fault_sums(F_BALANCE, 0, close_tag, "the balances do not add up", sum, want); }
        f = write_balance_line(out, close_tag, st.closing);
        if f.kind != F_NONE { return f; }
    }
    if st.available.kind != 0 {
        f = write_balance_line(out, "64", st.available);
        if f.kind != F_NONE { return f; }
    }
    if st.forward.kind != 0 {
        f = write_balance_line(out, "65", st.forward);
        if f.kind != F_NONE { return f; }
    }
    if st.has_debit_total {
        if st.debit_count != dn || st.debit_total.minor != dsum || st.debit_total.currency != cur {
            return fault(F_TOTAL, 0, 0, "90D", "debit total differs from the entries");
        }
        f = write_total_line(out, "90D", st.debit_count, st.debit_total);
        if f.kind != F_NONE { return f; }
    }
    if st.has_credit_total {
        if st.credit_count != cn || st.credit_total.minor != csum || st.credit_total.currency != cur {
            return fault(F_TOTAL, 0, 0, "90C", "credit total differs from the entries");
        }
        f = write_total_line(out, "90C", st.credit_count, st.credit_total);
        if f.kind != F_NONE { return f; }
    }
    return check_size(out, lim);
}

// write_mt940 appends the statements as MT940 text. Each statement
// starts with its :20: line.
fn write_mt940(statements: Statement[>..]&, entries: Entry[>..]&, lim: Limits&, out: u8[>..]&) -> Fault {
    var i: i64 = 0;
    while i < statements.len {
        let f = write_one(out, statements[i], entries, lim);
        if f.kind != F_NONE { return f; }
        i += 1;
    }
    return no_fault();
}
