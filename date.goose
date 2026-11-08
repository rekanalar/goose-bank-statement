// Calendar dates for the bank_statement package.
//
// A Date holds a civil date. A year of 0 means that the date is absent.
namespace bank_statement;

import std;
import fault;
import text;

struct Date {
    year: i32,
    month: i32,
    day: i32,
}

// no_date gives the absent date.
fn no_date() -> Date {
    return Date { year: 0, month: 0, day: 0 };
}

fn is_leap(y: i64) -> bool {
    return (y % 4 == 0 && y % 100 != 0) || y % 400 == 0;
}

// days_in_month gives the days of a month, or 0 for a month outside 1..12.
fn days_in_month(y: i64, m: i64) -> i64 {
    if m == 2 { if is_leap(y) { return 29; } return 28; }
    if m == 4 || m == 6 || m == 9 || m == 11 { return 30; }
    if m >= 1 && m <= 12 { return 31; }
    return 0;
}

// make_date builds a date. It gives false for a day that does not exist.
fn make_date(y: i64, m: i64, d: i64) -> Date, bool {
    if y < 1 || y > 9999 || d < 1 || d > days_in_month(y, m) { return no_date(), false; }
    return Date { year: y as i32, month: m as i32, day: d as i32 }, true;
}

// digits reads a run of decimal digits of at most 9 characters.
fn digits(s: const u8[:]) -> i64, bool {
    if s.len == 0 || s.len > 9 { return 0, false; }
    var v: i64 = 0;
    for c in s {
        if c < '0' || c > '9' { return 0, false; }
        v = v * 10 + (c - '0');
    }
    return v, true;
}

// year_of_two turns a two digit year into a year. The pivot is the first
// year that belongs to the 1900s: 70 gives 70..99 as 1970..1999 and
// 00..69 as 2000..2069.
fn year_of_two(yy: i64, pivot: i64) -> i64 {
    if yy >= pivot { return 1900 + yy; }
    return 2000 + yy;
}

// date_yymmdd reads six digits as a date with the pivot 70.
fn date_yymmdd(s: const u8[:]) -> Date, bool {
    if s.len != 6 { return no_date(), false; }
    let yy, a = digits(s[0..2]);
    let mm, b = digits(s[2..4]);
    let dd, c = digits(s[4..6]);
    if !a || !b || !c { return no_date(), false; }
    return make_date(year_of_two(yy, 70), mm, dd);
}
