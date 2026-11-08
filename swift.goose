// The field rules of the SWIFT manual for the MT940 and MT942 reader.
//
// The rules hold the width of every field, the count of the digits of
// every number and the order of the tags of a statement. A caller turns
// them on with the flag check_fields of the options of the reader. The
// rules never change a value. They only add faults.
//
// The widths come from the Rust crate mt940-rs, from the Node table of
// @centrapay/swift-parser and from the field guide of Danske Bank. The
// order comes from the machine of the Rust crate and from the field
// list of the manual.
namespace bank_statement;

import std;
import fault;
import text;

// The widths of the SWIFT manual.
const SW_REF: i64 = 16;
const SW_ACCOUNT: i64 = 35;
const SW_AMOUNT: i64 = 15;
const SW_AMOUNT_TEXT: i64 = 16;
const SW_COUNT: i64 = 5;
const SW_CUSTOMER_REF: i64 = 16;
const SW_BANK_REF: i64 = 16;
const SW_SUPPLEMENTARY: i64 = 34;
const SW_LINE: i64 = 65;
const SW_LINES: i64 = 6;
const SW_STATEMENT_NO: i64 = 5;

// The codes of the tags of the order machine.
const T_NONE: i32 = 0;
const T_20: i32 = 1;
const T_21: i32 = 2;
const T_25: i32 = 3;
const T_28: i32 = 4;
const T_34F: i32 = 5;
const T_13D: i32 = 6;
const T_60: i32 = 7;
const T_61: i32 = 8;
const T_86: i32 = 9;
const T_62: i32 = 10;
const T_64: i32 = 11;
const T_65: i32 = 12;
const T_90: i32 = 13;
const T_NS: i32 = 14;

// swift_char tells whether the SWIFT character set of the manual holds
// the byte: letters of both cases, digits, the space and / - ? : ( ) . , ' + { }.
// A line end is allowed, because a field holds many lines.
fn swift_char(c: u8) -> bool {
    if is_digit(c) || (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') { return true; }
    return c == ' ' || c == '/' || c == '-' || c == '?' || c == ':' || c == '(' || c == ')'
        || c == '.' || c == ',' || c == '\'' || c == '+' || c == '{' || c == '}'
        || c == '\n' || c == '\r';
}

// check_charset refuses a value that holds a byte outside the character
// set of the manual. The fault names the column of the first such byte.
fn check_charset(tag: const u8[:], value: const u8[:], line_no: i64) -> Fault {
    var i = 0;
    while i < value.len {
        if !swift_char(value[i]) {
            return fault(F_SYNTAX, line_no, i + 1, tag, "the field holds a character outside the SWIFT character set");
        }
        i += 1;
    }
    return no_fault();
}

// check_width refuses a value that is longer than the width of the
// manual. The fault names the tag and the column of the first mark
// that is too much.
fn check_width(tag: const u8[:], value: const u8[:], line_no: i64, max: i64) -> Fault {
    if value.len > max {
        return fault(F_SYNTAX, line_no, max + 1, tag, "the field is longer than the width of the manual");
    }
    return no_fault();
}

// check_digits refuses a text that holds a mark that is not a digit and a
// text with more than max digits.
fn check_digits(tag: const u8[:], value: const u8[:], line_no: i64, max: i64) -> Fault {
    var n: i64 = 0;
    var i = 0;
    while i < value.len {
        if !is_digit(value[i]) {
            return fault(F_SYNTAX, line_no, i + 1, tag, "the number holds a mark that is not a digit");
        }
        n += 1;
        i += 1;
    }
    if n > max {
        return fault(F_SYNTAX, line_no, max + 1, tag, "the number has more digits than the manual allows");
    }
    return no_fault();
}

// check_amount refuses an amount with more than 15 digits. The manual
// counts the comma in the 15. The Node table and the Python library
// accept 16 characters, so the package accepts 16 characters with at
// most 15 digits.
fn check_amount(tag: const u8[:], value: const u8[:], line_no: i64) -> Fault {
    let f = check_width(tag, value, line_no, SW_AMOUNT_TEXT);
    if f.kind != F_NONE { return f; }
    var n: i64 = 0;
    var i = 0;
    while i < value.len {
        if is_digit(value[i]) { n += 1; }
        i += 1;
    }
    if n > SW_AMOUNT {
        return fault(F_SYNTAX, line_no, SW_AMOUNT + 1, tag, "the amount has more digits than the manual allows");
    }
    return no_fault();
}

// check_statement_number checks the parts of a :28: or a :28C: field.
// Every part holds at most five digits. The Node table knows a third
// part. The manual knows two.
fn check_statement_number(tag: const u8[:], value: const u8[:], line_no: i64) -> Fault {
    var start = 0;
    var i = 0;
    while i <= value.len {
        if i == value.len || value[i] == '/' {
            let part = value[start..i];
            let f = check_digits(tag, part, line_no, SW_STATEMENT_NO);
            if f.kind != F_NONE { return f; }
            start = i + 1;
        }
        i += 1;
    }
    return no_fault();
}

// check_86 checks the lines of a :86: field. The manual allows six
// lines of 65 characters. A line end of two marks does not count.
fn check_86(tag: const u8[:], value: const u8[:], line_no: i64) -> Fault {
    var end = value.len;
    if end > 0 && value[end - 1] == '\n' { end -= 1; }
    var lines: i64 = 1;
    var start = 0;
    var i = 0;
    while i < end {
        if value[i] == '\n' {
            var stop = i;
            if stop > start && value[stop - 1] == '\r' { stop -= 1; }
            let f = check_width(tag, value[start..stop], line_no, SW_LINE);
            if f.kind != F_NONE { return f; }
            lines += 1;
            if lines > SW_LINES {
                return fault(F_SYNTAX, line_no, 1, tag, "the field has more lines than the manual allows");
            }
            start = i + 1;
        }
        i += 1;
    }
    var stop = end;
    if stop > start && value[stop - 1] == '\r' { stop -= 1; }
    return check_width(tag, value[start..stop], line_no, SW_LINE);
}

// tag_code gives the code of a tag. A tag that the order machine does
// not know gives T_NONE.
fn tag_code(tag: const u8[:]) -> i32 {
    if tag == "20" { return T_20; }
    if tag == "21" { return T_21; }
    if tag == "25" { return T_25; }
    if tag == "28" || tag == "28C" { return T_28; }
    if tag == "34F" { return T_34F; }
    if tag == "13D" { return T_13D; }
    if tag == "60F" || tag == "60M" { return T_60; }
    if tag == "61" { return T_61; }
    if tag == "86" { return T_86; }
    if tag == "62F" || tag == "62M" { return T_62; }
    if tag == "64" { return T_64; }
    if tag == "65" { return T_65; }
    if tag == "90D" || tag == "90C" { return T_90; }
    if tag == "NS" { return T_NS; }
    return T_NONE;
}

// tag_allowed tells whether a tag may follow the last tag of a
// statement. The machine of the Rust crate gives the base. The floor
// limit and the time of an interim report join it. The :NS: field may
// follow any tag.
fn tag_allowed(last: i32, tag: i32) -> bool {
    if last == T_NONE { return tag == T_20; }
    if tag == T_NONE { return false; }
    // The non-Swift field of a bank may follow any tag.
    if tag == T_NS { return true; }
    if last == T_20 { return tag == T_21 || tag == T_25; }
    if last == T_21 { return tag == T_25; }
    if last == T_25 { return tag == T_28; }
    if last == T_28 { return tag == T_34F || tag == T_13D || tag == T_60 || tag == T_61; }
    if last == T_34F { return tag == T_13D || tag == T_60 || tag == T_61; }
    if last == T_13D { return tag == T_60 || tag == T_61; }
    if last == T_60 { return tag == T_61 || tag == T_62 || tag == T_86; }
    if last == T_61 { return tag == T_61 || tag == T_86 || tag == T_62 || tag == T_90; }
    if last == T_86 { return tag == T_61 || tag == T_86 || tag == T_62 || tag == T_90; }
    if last == T_62 { return tag == T_64 || tag == T_65 || tag == T_86 || tag == T_90; }
    if last == T_64 { return tag == T_65 || tag == T_86 || tag == T_90; }
    if last == T_65 { return tag == T_65 || tag == T_86 || tag == T_90; }
    if last == T_90 { return tag == T_90 || tag == T_86 || tag == T_61; }
    return false;
}
