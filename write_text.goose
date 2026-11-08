// Helpers that the writers of the bank_statement package share.
//
// Every writer appends text to a buffer of the caller. A text is
// checked before it is written. A text that holds a control byte or
// that is longer than max_field is a fault. The writers never cut and
// never repair a text.
namespace bank_statement;

import std;
import fault;
import limits;
import amount;
import date;

// put appends the text to the buffer.
fn put(out: u8[>..]&, s: const u8[:]) {
    for c in s { out.push(c); }
}

// put_num appends a number with at least width digits.
fn put_num(out: u8[>..]&, n: i64, width: i64) {
    var digits: u8[>..] = [];
    var v = n;
    if v < 0 { v = 0; }
    while v > 0 {
        digits.push('0' + (v % 10) as u8);
        v = v / 10;
    }
    var zeros = width - digits.len;
    while zeros > 0 { out.push('0'); zeros -= 1; }
    var i = digits.len;
    while i > 0 {
        i -= 1;
        out.push(digits[i]);
    }
}

// put_amount appends minor units with exp digits after the radix mark.
// It uses integers only. The most negative i64 is valid.
fn put_amount(out: u8[>..]&, minor: i64, exp: i32, radix: u8) {
    var mag: u64 = 0;
    if minor < 0 {
        mag = ((-(minor + 1)) as u64) + 1;
        out.push('-');
    } else {
        mag = minor as u64;
    }
    var digits: u8[>..] = [];
    while mag > 0 {
        digits.push('0' + (mag % 10) as u8);
        mag = mag / 10;
    }
    while digits.len < (exp as i64) + 1 { digits.push('0'); }
    var i = digits.len;
    while i > 0 {
        i -= 1;
        out.push(digits[i]);
        if i == (exp as i64) && exp > 0 { out.push(radix); }
    }
}

// check_text refuses a text with a control byte, and a text that is
// longer than max_field. The tag names the field in the fault.
fn check_text(s: const u8[:], tag: const u8[:], lim: Limits&) -> Fault {
    if s.len > lim.max_field {
        return fault(F_LIMIT, 0, 0, tag, "text is longer than max_field");
    }
    for c in s {
        if c < 32 || c == 127 {
            return fault(F_SYNTAX, 0, 0, tag, "control byte in text");
        }
    }
    return no_fault();
}

// check_date refuses a date that does not exist.
fn check_date(d: Date, tag: const u8[:]) -> Fault {
    if d.year < 1 || d.year > 9999 || d.month < 1 || d.month > 12 || d.day < 1
       || d.day > days_in_month(d.year as i64, d.month as i64) {
        return fault(F_DATE, 0, 0, tag, "date does not exist");
    }
    return no_fault();
}

// check_size refuses output above max_input.
fn check_size(out: u8[>..]&, lim: Limits&) -> Fault {
    if out.len > lim.max_input { return fault(F_LIMIT, 0, 0, "", "output is longer than max_input"); }
    return no_fault();
}
