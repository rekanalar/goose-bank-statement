// The QIF writer of the bank_statement package.
//
// write_qif appends a QIF file to the buffer of the caller. It takes
// the records, the splits and the extra fields that parse_qif gives.
// The writer writes the sections bank, cash, card, other asset, other
// liability and every list section. The lists keep their lines as
// fields; write_qif_lists writes the typed records of the lists.
// Every text is checked. A line end or a control byte is a fault, so a
// value cannot add a field or end a record.
namespace bank_statement;

import std;
import fault;
import limits;
import amount;
import date;
import qif;
import write_text;

// QifWriteOptions holds the options of the writer. The date order is
// DATE_MDY (the default when 0), DATE_DMY or DATE_YMD.
struct QifWriteOptions {
    date_order: i32,
}

// section_header gives the header line of a section, or "" when the
// writer does not write the section.
fn section_header(k: i32) -> const u8[:] {
    if k == Q_ACCOUNT { return "!Account"; }
    if k == Q_BANK { return "!Type:Bank"; }
    if k == Q_CASH { return "!Type:Cash"; }
    if k == Q_CCARD { return "!Type:CCard"; }
    if k == Q_OTH_A { return "!Type:Oth A"; }
    if k == Q_OTH_L { return "!Type:Oth L"; }
    if k == Q_CAT { return "!Type:Cat"; }
    if k == Q_CLASS { return "!Type:Class"; }
    if k == Q_BUDGET { return "!Type:Budget"; }
    if k == Q_TAG { return "!Type:Tag"; }
    if k == Q_SECURITY { return "!Type:Security"; }
    if k == Q_PRICES { return "!Type:Prices"; }
    if k == Q_PAYEE { return "!Type:Payee"; }
    return "";
}

// put_line writes one code and one checked value.
fn put_line(out: u8[>..]&, code: u8, value: const u8[:], tag: const u8[:], lim: Limits&) -> Fault {
    let f = check_text(value, tag, lim);
    if f.kind != F_NONE { return f; }
    out.push(code);
    put(out, value);
    out.push('\n');
    return no_fault();
}

// put_qif_date writes a date in the order of the option.
fn put_qif_date(out: u8[>..]&, d: Date, order: i32) {
    if order == DATE_YMD {
        put_num(out, d.year as i64, 4); out.push('-');
        put_num(out, d.month as i64, 2); out.push('-');
        put_num(out, d.day as i64, 2);
    } else if order == DATE_DMY {
        put_num(out, d.day as i64, 2); out.push('/');
        put_num(out, d.month as i64, 2); out.push('/');
        put_num(out, d.year as i64, 4);
    } else {
        put_num(out, d.month as i64, 2); out.push('/');
        put_num(out, d.day as i64, 2); out.push('/');
        put_num(out, d.year as i64, 4);
    }
}

// put_money writes a line with an amount.
fn put_money(out: u8[>..]&, code: u8, a: Amount) {
    out.push(code);
    put_amount(out, a.minor, a.exp, '.');
    out.push('\n');
}

// split_sum adds the amounts of the splits of a record. The flag is
// false when an amount overflows or a split has no amount.
fn split_sum(splits: QifSplit[>..]&, start: i64, count: i64, exp: i32) -> i64, bool {
    var sum: i64 = 0;
    var i = start;
    while i < start + count {
        if !splits[i].has_amount || splits[i].amount.exp != exp { return 0, false; }
        let m = splits[i].amount.minor;
        if (m > 0 && sum > 9223372036854775807 - m) || (m < 0 && sum < -9223372036854775808 - m) {
            return 0, false;
        }
        sum += m;
        i += 1;
    }
    return sum, true;
}

// write_split writes the lines of one split.
fn write_split(out: u8[>..]&, s: QifSplit, lim: Limits&) -> Fault {
    let f = put_line(out, 'S', s.category, "S", lim);
    if f.kind != F_NONE { return f; }
    if s.memo.len > 0 {
        let g = put_line(out, 'E', s.memo, "E", lim);
        if g.kind != F_NONE { return g; }
    }
    if s.has_amount { put_money(out, '$', s.amount); }
    if s.has_percent {
        if s.percent_text.len == 0 { return fault(F_SYNTAX, 0, 0, "%", "a percent needs its text"); }
        let h = put_line(out, '%', s.percent_text, "%", lim);
        if h.kind != F_NONE { return h; }
    }
    return no_fault();
}

// cleared_ok tells whether the byte is a cleared mark of the reader.
fn cleared_ok(c: u8) -> bool {
    return c == '*' || c == 'C' || c == 'c' || c == 'X' || c == 'x' || c == 'R' || c == 'r';
}

// write_record writes the lines of one record of a typed section.
fn write_record(out: u8[>..]&, r: QifRecord, splits: QifSplit[>..]&, extra: QifField[>..]&,
                order: i32, lim: Limits&) -> Fault {
    if r.date.year != 0 {
        let fd = check_date(r.date, "D");
        if fd.kind != F_NONE { return fd; }
        out.push('D');
        put_qif_date(out, r.date, order);
        out.push('\n');
    }
    if r.has_amount {
        if r.amount_code == 'U' && r.has_alt_amount {
            put_money(out, 'T', r.alt_amount);
            put_money(out, 'U', r.amount);
        } else {
            put_money(out, 'T', r.amount);
        }
    }
    if r.cleared != 0 {
        if !cleared_ok(r.cleared) { return fault(F_SYNTAX, 0, 0, "C", "unknown cleared mark"); }
        out.push('C'); out.push(r.cleared); out.push('\n');
    }
    if r.number.len > 0 { let f = put_line(out, 'N', r.number, "N", lim); if f.kind != F_NONE { return f; } }
    if r.payee.len > 0 { let f = put_line(out, 'P', r.payee, "P", lim); if f.kind != F_NONE { return f; } }
    if r.memo.len > 0 { let f = put_line(out, 'M', r.memo, "M", lim); if f.kind != F_NONE { return f; } }
    let fx = write_fields(out, r.field_start as i64, r.field_count as i64, extra, lim);
    if fx.kind != F_NONE { return fx; }
    if r.category.len > 0 { let f = put_line(out, 'L', r.category, "L", lim); if f.kind != F_NONE { return f; } }
    var i: i64 = r.split_start as i64;
    let end: i64 = i + (r.split_count as i64);
    if r.split_count > 0 && r.has_amount {
        let sum, ok = split_sum(splits, i, r.split_count as i64, r.amount.exp);
        if ok && sum != r.amount.minor {
            return fault_sums(F_TOTAL, 0, "$", "the splits do not add up to the amount", sum, r.amount.minor);
        }
    }
    while i < end {
        let f = write_split(out, splits[i], lim);
        if f.kind != F_NONE { return f; }
        i += 1;
    }
    if r.reimbursable {
        let f = put_line(out, 'F', r.reimbursable_text, "F", lim);
        if f.kind != F_NONE { return f; }
    }
    return no_fault();
}

// write_fields writes the extra fields of a record. The code of a
// field must be a printable byte that is not ! and not ^.
fn write_fields(out: u8[>..]&, start: i64, count: i64, extra: QifField[>..]&, lim: Limits&) -> Fault {
    var i: i64 = start;
    let end: i64 = i + count;
    while i < end {
        let c = extra[i].code;
        if c <= 32 || c == 127 || c == '!' || c == '^' {
            return fault(F_SYNTAX, 0, 0, "", "a field code must be printable and not ! or ^");
        }
        let f = put_line(out, c, extra[i].value, "", lim);
        if f.kind != F_NONE { return f; }
        i += 1;
    }
    return no_fault();
}

// write_qif appends the records as a QIF file. A section header comes
// before the first record and whenever the section changes.
fn write_qif(records: QifRecord[>..]&, splits: QifSplit[>..]&, extra: QifField[>..]&,
             opts: QifWriteOptions, lim: Limits&, out: u8[>..]&) -> Fault {
    var order = opts.date_order;
    if order == 0 { order = DATE_MDY; }
    if order != DATE_MDY && order != DATE_DMY && order != DATE_YMD {
        return fault(F_SYNTAX, 0, 0, "", "the date order is not US, EU or ISO");
    }
    var sect: i32 = -1;
    var n: i64 = 0;
    while n < records.len {
        let r = records[n];
        let h = section_header(r.section);
        if h.len == 0 { return fault(F_SYNTAX, 0, 0, "", "the writer does not write this section"); }
        if r.section != sect {
            put(out, h);
            out.push('\n');
            sect = r.section;
        }
        if typed_section(r.section) {
            let f = write_record(out, r, splits, extra, order, lim);
            if f.kind != F_NONE { return with_pos(f, n + 1, f.tag); }
        } else {
            let f = write_fields(out, r.field_start as i64, r.field_count as i64, extra, lim);
            if f.kind != F_NONE { return with_pos(f, n + 1, f.tag); }
        }
        put(out, "^\n");
        let fs = check_size(out, lim);
        if fs.kind != F_NONE { return fs; }
        n += 1;
    }
    return no_fault();
}
