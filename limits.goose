// The limits and the line reader of the bank_statement package.
//
// A parse checks the size of the input before it reads one field. It
// checks every other limit before the work that the limit guards. A
// caller who reads files from unknown people keeps the defaults or
// lowers them.
namespace bank_statement;

import fault;

struct Limits {
    max_input: i64,
    max_line: i64,
    max_field: i64,
    max_entries: i64,
    max_splits: i64,
    max_statements: i64,
    max_records: i64,
    max_fields: i64,
    max_depth: i64,
}

// default_limits gives the safe defaults: 16 MiB of input, 4096 bytes
// in a line or a field, and counts that no honest file reaches.
fn default_limits() -> Limits {
    return Limits {
        max_input: 16777216,
        max_line: 4096,
        max_field: 4096,
        max_entries: 1000000,
        max_splits: 1000000,
        max_statements: 100000,
        max_records: 1000000,
        max_fields: 4000000,
        max_depth: 8,
    };
}

// check_input refuses an input above the limit, before any other work.
fn check_input(s: const u8[:], lim: Limits&) -> Fault {
    if s.len > lim.max_input {
        return fault(F_LIMIT, 1, 1, "", "input is larger than max_input");
    }
    return no_fault();
}

// skip_bom gives the position after a UTF-8 byte order mark, or 0.
fn skip_bom(s: const u8[:]) -> i64 {
    if s.len >= 3 && s[0] == 239 && s[1] == 187 && s[2] == 191 { return 3; }
    return 0;
}

// bad_byte is true for a control byte that no statement text holds.
// Tab, CR and LF are fine. Bytes above 127 pass through.
fn bad_byte(c: u8) -> bool {
    if c == '\t' || c == '\n' || c == '\r' { return false; }
    return c < 32 || c == 127;
}

// line_end gives the position of the end of the line that starts at pos:
// the position of the LF, or the length of the input. A line holds no
// bad byte and is not longer than max_line. The bad flag says which
// fault it is: 1 for a bad byte or a lone CR, 2 for a long line, 0 for none.
fn line_end(s: const u8[:], pos: i64, max_line: i64) -> i64, i32 {
    var i = pos;
    while i < s.len {
        let c = s[i];
        if c == '\n' { break; }
        if bad_byte(c) { return i, 1; }
        // A CR counts only before an LF. A lone CR could hide a line end.
        if c == '\r' && (i + 1 >= s.len || s[i + 1] != '\n') { return i, 1; }
        i += 1;
        if i - pos > max_line + 1 { return i, 2; }
    }
    // A CR before the LF is part of the line end, not of the line.
    var e = i;
    if e > pos && s[e - 1] == '\r' { e -= 1; }
    if e - pos > max_line { return i, 2; }
    return i, 0;
}

// trim_cr gives the line without one trailing CR.
fn trim_cr(line: const u8[:]) -> const u8[:] {
    if line.len > 0 && line[line.len - 1] == '\r' { return line[..line.len - 1]; }
    return line;
}

// line_fault builds the fault of a bad line.
fn line_fault(bad: i32, line_no: i64, col: i64) -> Fault {
    if bad == 1 { return fault(F_SYNTAX, line_no, col, "", "control byte in the text"); }
    return fault(F_LIMIT, line_no, 1, "", "line is longer than max_line");
}
