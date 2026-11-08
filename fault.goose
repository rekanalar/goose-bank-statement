// The fault type of the bank_statement package.
//
// Every parse call returns a Fault. A Fault with kind F_NONE means the
// parse succeeded. Any other kind names the first problem. The line and
// the column count from 1. A balance or total fault holds the two sums in
// have and want, as minor units. The tag holds the MT940 tag or the QIF code
// of the problem, and the detail holds a short reason. Both are spans
// over the input or over a string literal, so they stay valid only as
// long as the input.
namespace bank_statement;

const F_NONE: i32 = 0;
const F_LIMIT: i32 = 1;
const F_SYNTAX: i32 = 2;
const F_UNKNOWN_TAG: i32 = 3;
const F_AMOUNT: i32 = 4;
const F_OVERFLOW: i32 = 5;
const F_DATE: i32 = 6;
const F_BALANCE: i32 = 7;
const F_TOTAL: i32 = 8;
const F_AMBIGUOUS_DATE: i32 = 9;

struct Fault {
    kind: i32,
    line: i32,
    col: i32,
    tag: const u8[:],
    detail: const u8[:],
    have: i64,
    want: i64,
}

// no_fault gives the success value.
fn no_fault() -> Fault {
    return Fault { kind: F_NONE, line: 0, col: 0, tag: "", detail: "", have: 0, want: 0 };
}

// fault builds a fault value.
fn fault(kind: i32, line: i64, col: i64, tag: const u8[:], detail: const u8[:]) -> Fault {
    return Fault { kind: kind, line: line as i32, col: col as i32, tag: tag, detail: detail, have: 0, want: 0 };
}

// fault_sums builds a fault that names two sums: the sum that the input
// gives and the sum that the input claims.
fn fault_sums(kind: i32, line: i64, tag: const u8[:], detail: const u8[:], have: i64, want: i64) -> Fault {
    return Fault { kind: kind, line: line as i32, col: 1, tag: tag, detail: detail, have: have, want: want };
}

// kind_name gives the name of a fault kind.
fn kind_name(kind: i32) -> const u8[:] {
    if kind == F_NONE { return "none"; }
    if kind == F_LIMIT { return "limit"; }
    if kind == F_SYNTAX { return "syntax"; }
    if kind == F_UNKNOWN_TAG { return "unknown tag"; }
    if kind == F_AMOUNT { return "amount"; }
    if kind == F_OVERFLOW { return "overflow"; }
    if kind == F_DATE { return "date"; }
    if kind == F_BALANCE { return "balance"; }
    if kind == F_TOTAL { return "total"; }
    if kind == F_AMBIGUOUS_DATE { return "ambiguous date"; }
    return "unknown";
}

// with_pos puts the position into a fault that the amount parser made.
fn with_pos(f: Fault, line_no: i64, tag: const u8[:]) -> Fault {
    return Fault { kind: f.kind, line: line_no as i32, col: 1, tag: tag, detail: f.detail, have: 0, want: 0 };
}
