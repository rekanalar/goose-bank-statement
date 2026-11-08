// Transcoding between UTF-8 and the legacy charsets of bank files.
//
// Banks send MT940, QIF and OFX files in Windows-1252 or ISO-8859-1.
// The readers keep the bytes of a text as they are, so a caller turns
// the file into UTF-8 first. decode_charset does that. encode_charset
// does the reverse, for a bank that wants a legacy file.
//
// The five bytes that Windows-1252 leaves undefined (0x81, 0x8D, 0x8F,
// 0x90 and 0x9D) are a fault. Python codecs refuses them too. The WHATWG
// standard maps them to the control characters U+0081 and so on. This
// package follows Python, because a control character in a statement
// is a defect of the file. A text that holds a character that the
// charset lacks is a fault. Nothing is replaced and nothing is lost.
namespace bank_statement;

import std;
import fault;
import limits;
import write_text;

const CS_CP1252: i32 = 1;
const CS_LATIN1: i32 = 2;

// The code points of the bytes 0x80 to 0x9F of Windows-1252. A zero
// marks an undefined byte.
const CP1252_HIGH: i32[] = [
    0x20AC, 0, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021,
    0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0, 0x017D, 0,
    0, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014,
    0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0, 0x017E, 0x0178,
];

// put_utf8 appends one code point as UTF-8.
fn put_utf8(out: u8[>..]&, cp: i64) {
    if cp < 0x80 {
        out.push(cp as u8);
    } else if cp < 0x800 {
        out.push((0xC0 + cp / 64) as u8);
        out.push((0x80 + cp % 64) as u8);
    } else if cp < 0x10000 {
        out.push((0xE0 + cp / 4096) as u8);
        out.push((0x80 + (cp / 64) % 64) as u8);
        out.push((0x80 + cp % 64) as u8);
    } else {
        out.push((0xF0 + cp / 262144) as u8);
        out.push((0x80 + (cp / 4096) % 64) as u8);
        out.push((0x80 + (cp / 64) % 64) as u8);
        out.push((0x80 + cp % 64) as u8);
    }
}

// decode_charset turns the bytes of a legacy charset into UTF-8. It
// appends to the buffer. The output has the limit max_input.
fn decode_charset(kind: i32, input: const u8[:], lim: Limits&, out: u8[>..]&) -> Fault {
    if kind != CS_CP1252 && kind != CS_LATIN1 { return fault(F_SYNTAX, 0, 0, "", "the charset is not a charset of the package"); }
    if input.len > lim.max_input { return fault(F_LIMIT, 0, 0, "", "input is longer than max_input"); }
    var i: i64 = 0;
    while i < input.len {
        let b = input[i] as i64;
        if b < 0x80 || b >= 0xA0 {
            put_utf8(out, b);
        } else if kind == CS_LATIN1 {
            put_utf8(out, b);
        } else {
            let cp = CP1252_HIGH[b - 0x80] as i64;
            if cp == 0 { return fault(F_SYNTAX, 0, (i + 1) as i32, "", "byte is not defined in Windows-1252"); }
            put_utf8(out, cp);
        }
        i += 1;
    }
    return check_size(out, lim);
}

// utf8_next reads one code point at the index. It gives the code point
// and the length, or a length of 0 for bytes that are not UTF-8.
fn utf8_next(s: const u8[:], i: i64) -> i64, i64 {
    let c = s[i] as i64;
    if c < 0x80 { return c, 1; }
    var n: i64 = 0;
    var cp: i64 = 0;
    var min: i64 = 0;
    if c >= 0xC2 && c <= 0xDF { n = 1; cp = c & 0x1F; min = 0x80; }
    else if c >= 0xE0 && c <= 0xEF { n = 2; cp = c & 0x0F; min = 0x800; }
    else if c >= 0xF0 && c <= 0xF4 { n = 3; cp = c & 0x07; min = 0x10000; }
    else { return 0, 0; }
    if i + n >= s.len { return 0, 0; }
    var k: i64 = 1;
    while k <= n {
        let d = s[i + k] as i64;
        if d < 0x80 || d > 0xBF { return 0, 0; }
        cp = cp * 64 + (d & 0x3F);
        k += 1;
    }
    if cp < min || cp > 0x10FFFF || (cp >= 0xD800 && cp <= 0xDFFF) { return 0, 0; }
    return cp, n + 1;
}

// encode_charset turns UTF-8 into the bytes of a legacy charset. A text
// that is not UTF-8, and a character that the charset lacks, are faults.
fn encode_charset(kind: i32, input: const u8[:], lim: Limits&, out: u8[>..]&) -> Fault {
    if kind != CS_CP1252 && kind != CS_LATIN1 { return fault(F_SYNTAX, 0, 0, "", "the charset is not a charset of the package"); }
    if input.len > lim.max_input { return fault(F_LIMIT, 0, 0, "", "input is longer than max_input"); }
    var i: i64 = 0;
    while i < input.len {
        let cp, n = utf8_next(input, i);
        if n == 0 { return fault(F_SYNTAX, 0, (i + 1) as i32, "", "text is not UTF-8"); }
        if cp < 0x80 || (cp >= 0xA0 && cp <= 0xFF) {
            out.push(cp as u8);
        } else if kind == CS_LATIN1 && cp < 0xA0 {
            out.push(cp as u8);
        } else {
            var found: i64 = -1;
            if kind == CS_CP1252 {
                var k: i64 = 0;
                while k < 32 {
                    if CP1252_HIGH[k] as i64 == cp { found = k; break; }
                    k += 1;
                }
            }
            if found < 0 { return fault(F_SYNTAX, 0, (i + 1) as i32, "", "the charset has no such character"); }
            out.push((0x80 + found) as u8);
        }
        i += n;
    }
    return check_size(out, lim);
}

// header_charset reads the CHARSET line of an OFX 1.x header. It gives
// CS_CP1252 for 1252, CS_LATIN1 for ISO-8859-1 and 0 for anything else.
// The OFX 2.x header has no such line, because XML names its encoding.
fn header_charset(input: const u8[:]) -> i32 {
    var end = input.len;
    if end > 512 { end = 512; }
    let head = input[..end];
    let at = find(head, "CHARSET:");
    if at < 0 { return 0; }
    var i = at + 8;
    while i < head.len && head[i] == ' ' { i += 1; }
    var j = i;
    while j < head.len && head[j] != '\n' && head[j] != '\r' && head[j] != '<' { j += 1; }
    let v = head[i..j];
    if v == "1252" { return CS_CP1252; }
    if v == "ISO-8859-1" { return CS_LATIN1; }
    return 0;
}
