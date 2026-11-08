// The structured values of a SWIFT :86: text.
//
// parse_field_86 reads the narrative of a :86: field into a typed
// record. It reads the German SEPA GVC codes (?00 to ?63) and the
// generic slash tags (/TAG/value) of Python `bankstatementparser`, and
// it finds an IBAN or a BIC that no tag names. Every tag that no named
// field takes comes back as a named value in the array of the caller.
// The names of the values keep the names of that library.
//
// The record and the values point at the text of the caller or at the
// buffer of the caller. One pass over the text, no recursion, no
// regular expression.
namespace bank_statement;

import std;
import fault;
import limits;
import text;
import amount;

// Field86 holds the structured values of one :86: text. A field that
// the text holds not stays empty. The tags that no named field takes
// are a range of the array of named values.
struct Field86 {
    transaction_code: const u8[:],
    end_to_end_id: const u8[:],
    mandate_id: const u8[:],
    creditor_id: const u8[:],
    creditor_name: const u8[:],
    debtor_name: const u8[:],
    counterparty_iban: const u8[:],
    counterparty_bic: const u8[:],
    remittance_info: const u8[:],
    purpose_code: const u8[:],
    service_reference: const u8[:],
    has_original_amount: bool,
    original_amount: Amount,
    has_charges_amount: bool,
    charges_amount: Amount,
    tag_start: i32,
    tag_count: i32,
    raw: const u8[:],
}

fn is_alnum(c: u8) -> bool {
    return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || is_digit(c);
}

fn is_alpha(c: u8) -> bool {
    return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z');
}

// add_part joins one part into the region that at names in the buffer.
// A negative at starts a new region. The parts come out with one space
// between two of them.
fn add_part(buf: u8[>..]&, at: i64&, part: const u8[:]) -> const u8[:] {
    if part.len == 0 && at >= 0 { return buf[at..]; }
    if at < 0 { at = buf.len; } else { buf.push(' '); }
    put(buf, part);
    return buf[at..];
}

// take_tag fills the field of the record that a slash tag names. It
// gives true when a named field took the value.
fn take_tag(f: Field86&, tag: const u8[:], v: const u8[:], buf: u8[>..]&, rem_at: i64&) -> bool {
    if tag == "EREF" { f.end_to_end_id = v; return true; }
    if tag == "MARF" || tag == "MREF" { f.mandate_id = v; return true; }
    if tag == "CDTR" || tag == "CNAM" || tag == "CRED" { f.creditor_name = v; return true; }
    if tag == "DBTR" || tag == "DNAM" || tag == "DEBT" { f.debtor_name = v; return true; }
    if tag == "CDTRID" || tag == "CI" { f.creditor_id = v; return true; }
    if tag == "IBAN" { f.counterparty_iban = v; return true; }
    if tag == "PURP" || tag == "CODP" { f.purpose_code = v; return true; }
    if tag == "SVCR" || tag == "SRV" { f.service_reference = v; return true; }
    if tag == "REMI" || tag == "RMTINF" {
        f.remittance_info = add_part(buf, rem_at, v);
        return true;
    }
    if tag == "BIC" || tag == "SWIFT" {
        if v == "NOTPROVIDED" || v == "UNDEFINED" { return true; }
        f.counterparty_bic = v;
        return true;
    }
    return false;
}

// take_amount reads the text of an amount tag. The text may name a
// currency and may hold a comma. A text that gives no amount is no
// fault; the field stays empty, as the reference library does.
fn take_amount(v: const u8[:]) -> Amount, bool {
    var z = Amount { minor: 0, exp: 2, currency: "" };
    // A comma as the decimal mark becomes a dot. Spaces come off.
    var clean: u8[>..] = [];
    for c in trim(v) {
        if c == ',' { clean.push('.'); }
        else if c != ' ' { clean.push(c); }
    }
    var t: const u8[:] = clean;
    // A currency of three letters before the number comes off.
    if t.len > 3 && is_alpha(t[0]) && is_alpha(t[1]) && is_alpha(t[2]) && (is_digit(t[3]) || t[3] == '.') {
        t = t[3..];
    }
    let a, af = parse_amount(t, 2, '.', 0);
    if af.kind != F_NONE { return z, false; }
    return a, true;
}

// iban_at tells whether an IBAN of the SWIFT form starts at the
// position. It gives the length, or 0.
fn iban_at(t: const u8[:], i: i64) -> i64 {
    if i + 15 > t.len { return 0; }
    if !is_alpha(t[i]) || !is_alpha(t[i + 1]) { return 0; }
    if !is_digit(t[i + 2]) || !is_digit(t[i + 3]) { return 0; }
    var j: i64 = i + 4;
    while j < t.len && is_alnum(t[j]) && j - i < 34 { j += 1; }
    let n = j - i;
    if n >= 15 { return n; }
    return 0;
}

// bic_at tells whether a BIC of the SWIFT form starts at the position.
// It gives the length, or 0. A placeholder is no BIC.
fn bic_at(t: const u8[:], i: i64) -> i64 {
    if i + 8 > t.len { return 0; }
    var j: i64 = 0;
    while j < 6 {
        if !is_alpha(t[i + j]) { return 0; }
        j += 1;
    }
    while j < 8 {
        if !is_alnum(t[i + j]) { return 0; }
        j += 1;
    }
    if i + 11 <= t.len && is_alnum(t[i + 8]) && is_alnum(t[i + 9]) && is_alnum(t[i + 10]) { j = 11; }
    return j;
}

// word_start tells whether the position starts a word: the byte before
// it holds no letter and no digit.
fn word_start(t: const u8[:], i: i64) -> bool {
    if i == 0 { return true; }
    return !is_alnum(t[i - 1]);
}

// parse_field_86 reads the narrative of a :86: field. The tags that no
// named field takes are appended to the array of named values of the
// caller.
fn parse_field_86(text: const u8[:], lim: Limits&, extra: DialectValue[>..]&, buf: u8[>..]&) -> Field86, Fault {
    var f = Field86 {
        transaction_code: "", end_to_end_id: "", mandate_id: "", creditor_id: "", creditor_name: "",
        debtor_name: "", counterparty_iban: "", counterparty_bic: "", remittance_info: "",
        purpose_code: "", service_reference: "", has_original_amount: false,
        original_amount: Amount { minor: 0, exp: 2, currency: "" }, has_charges_amount: false,
        charges_amount: Amount { minor: 0, exp: 2, currency: "" },
        tag_start: extra.len as i32, tag_count: 0, raw: text,
    };
    if text.len > lim.max_field {
        return f, fault(F_LIMIT, 0, 0, "86", "the text is longer than max_field");
    }
    // The GVC codes. A question mark, two digits, and the value up to
    // the next question mark.
    var cred_at: i64 = -1;
    var rem_at: i64 = -1;
    var i: i64 = 0;
    while i + 2 < text.len {
        if text[i] != '?' { i += 1; continue; }
        if !is_digit(text[i + 1]) || !is_digit(text[i + 2]) { i += 1; continue; }
        let code = text[i + 1..i + 3];
        var j = i + 3;
        while j < text.len && text[j] != '?' { j += 1; }
        let v = trim(text[i + 3..j]);
        if v.len > 0 {
            if code == "00" {
                f.transaction_code = v;
            } else if code == "10" {
                f.end_to_end_id = v;
            } else if code == "30" {
                f.counterparty_bic = v;
            } else if code == "31" {
                f.counterparty_iban = v;
            } else if code == "32" || code == "33" {
                f.creditor_name = add_part(buf, cred_at, v);
            } else if code[0] == '2' && code[1] >= '0' && code[1] <= '9' {
                f.remittance_info = add_part(buf, rem_at, v);
            } else {
                if extra.len >= lim.max_fields {
                    return f, fault(F_LIMIT, 0, 0, "86", "more fields than max_fields");
                }
                let ks = buf.len;
                buf.push('?');
                put(buf, code);
                extra.push(DialectValue { key: buf[ks..], value: v });
                f.tag_count += 1;
            }
        }
        i = j;
    }
    // The slash tags. A slash, two to twelve letters or digits, a
    // slash, and the value up to the next slash.
    i = 0;
    while i < text.len {
        if text[i] != '/' { i += 1; continue; }
        var j = i + 1;
        while j < text.len && j - i - 1 < 12 && is_alnum(text[j]) { j += 1; }
        let tlen = j - i - 1;
        if tlen < 2 || j >= text.len || text[j] != '/' {
            i += 1;
            continue;
        }
        let tag = text[i + 1..j];
        var k = j + 1;
        while k < text.len && text[k] != '/' { k += 1; }
        let v = trim(text[j + 1..k]);
        i = k;
        if v.len == 0 { continue; }
        if take_tag(f, tag, v, buf, rem_at) { continue; }
        if tag == "OCMT" || tag == "ORAMT" {
            let a, ok = take_amount(v);
            if ok {
                f.original_amount = a;
                f.has_original_amount = true;
            }
            continue;
        }
        if tag == "CHGS" || tag == "FEE" {
            let a, ok = take_amount(v);
            if ok {
                f.charges_amount = a;
                f.has_charges_amount = true;
            }
            continue;
        }
        if extra.len >= lim.max_fields {
            return f, fault(F_LIMIT, 0, 0, "86", "more fields than max_fields");
        }
        extra.push(DialectValue { key: tag, value: v });
        f.tag_count += 1;
    }
    // The fallback. An IBAN or a BIC in the naked text, when no tag
    // named one.
    if f.counterparty_iban.len == 0 {
        var p: i64 = 0;
        while p < text.len {
            if word_start(text, p) {
                let n = iban_at(text, p);
                if n > 0 {
                    f.counterparty_iban = text[p..p + n];
                    break;
                }
            }
            p += 1;
        }
    }
    if f.counterparty_bic.len == 0 {
        var p: i64 = 0;
        while p < text.len {
            if word_start(text, p) {
                let n = bic_at(text, p);
                if n >= 8 {
                    let cand = text[p..p + n];
                    if cand != "NOTPROVIDED" && cand != "UNDEFINED" {
                        f.counterparty_bic = cand;
                        break;
                    }
                }
            }
            p += 1;
        }
    }
    return f, no_fault();
}
