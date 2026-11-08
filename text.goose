// Character and text helpers shared by the modules of the bank_statement
// package.
namespace bank_statement;

fn is_digit(c: u8) -> bool { return c >= '0' && c <= '9'; }

fn is_upper(c: u8) -> bool { return c >= 'A' && c <= 'Z'; }

// is_letters is true when every byte is an upper case ASCII letter.
fn is_letters(s: const u8[:]) -> bool {
    for c in s { if !is_upper(c) { return false; } }
    return true;
}

// trim gives the text without blanks and line ends at both ends.
fn trim(s: const u8[:]) -> const u8[:] {
    var a = 0;
    var b = s.len;
    while a < b && (s[a] == ' ' || s[a] == '\t' || s[a] == '\n' || s[a] == '\r') { a += 1; }
    while b > a && (s[b - 1] == ' ' || s[b - 1] == '\t' || s[b - 1] == '\n' || s[b - 1] == '\r') { b -= 1; }
    return s[a..b];
}

fn lower(c: u8) -> u8 {
    if c >= 'A' && c <= 'Z' { return c + 32; }
    return c;
}

// ieq compares two texts and ignores the case of ASCII letters.
fn ieq(a: const u8[:], b: const u8[:]) -> bool {
    if a.len != b.len { return false; }
    var i = 0;
    while i < a.len {
        if lower(a[i]) != lower(b[i]) { return false; }
        i += 1;
    }
    return true;
}

// ieq_nospace compares two texts without their letter case and without
// their blanks, so "Oth A" and "otha" match the same name.
fn ieq_nospace(a: const u8[:], b: const u8[:]) -> bool {
    var i: i64 = 0;
    var j: i64 = 0;
    while i < a.len && j < b.len {
        if a[i] == ' ' { i += 1; continue; }
        if b[j] == ' ' { j += 1; continue; }
        if lower(a[i]) != lower(b[j]) { return false; }
        i += 1;
        j += 1;
    }
    while i < a.len && a[i] == ' ' { i += 1; }
    while j < b.len && b[j] == ' ' { j += 1; }
    return i == a.len && j == b.len;
}
