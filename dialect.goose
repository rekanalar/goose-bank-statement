// The bank dialects of the :86: field for the bank_statement package.
//
// A dialect reads the text of a :86: field and gives the named values
// of one bank. The banks are the four Dutch ones and mBank, as the
// Python library mt940 reads them. The names of the values keep the names of that
// library.
//
// The values point at the text of the caller or at the buffer of the
// caller. The text and the buffer must outlive the values. One pass
// over the text, no recursion.
namespace bank_statement;

import std;
import fault;
import limits;
import text;

// The kinds of the bank.
const D_RABOBANK: i32 = 1;
const D_ABN_AMRO: i32 = 2;
const D_ING: i32 = 3;
const D_REGIOBANK: i32 = 4;
const D_MBANK: i32 = 5;

// DialectValue holds one named value of a dialect. The key names the
// value. The value is the text of the bank.
struct DialectValue {
    key: const u8[:],
    value: const u8[:],
}

// The tags of Rabobank and the names of their values.
const RABO_TAGS: const u8[:][] = [
    "/MARF/", "/EREF/", "/PREF/", "/TRCD/", "/BENM/", "/ORDP/", "/NAME/",
    "/ID/", "/ADDR/", "/REMI/", "/CDTRREFTP//CD/SCOR/ISSR/CUR/CDTRREF/",
    "/CSID/", "/ISDT/", "/RTRN/",
];
const RABO_NAMES: const u8[:][] = [
    "marf", "eref", "pref", "trcd", "benm", "ordp", "name",
    "id", "addr", "remi", "cdtrref", "csid", "isdt", "rtrn",
];

// The tags of ABN AMRO and the names of their values.
const ABN_TAGS: const u8[:][] = [
    "/TRTP/", "/IBAN/", "/BIC/", "/CSID", "/NAME/", "/REMI/", "/EREF/",
    "/ORDP//ID/", "/BENM//ID/",
];
const ABN_NAMES: const u8[:][] = [
    "trtp", "iban", "bic", "csid", "name", "remi", "eref", "ordp", "benm",
];

// The tags of ING and the names of their values.
const ING_TAGS: const u8[:][] = [
    "/RTRN/", "/EREF/", "/PREF/", "/MARF/", "/CSID/", "/CNTP/", "/REMI/",
    "/PURP/", "/ULTC/", "/ULTD/",
];
const ING_NAMES: const u8[:][] = [
    "rtrn", "eref", "pref", "marf", "csid", "cntp", "remi", "purp",
    "ultc", "ultd",
];

// The parts of the nested tags of ING. The name of a part holds the
// name of the tag and the name of the part.
const ING_CNTP_FIELDS: const u8[:][] = [
    "cntp.account_number", "cntp.bic", "cntp.name", "cntp.city",
];
const ING_REMI_FIELDS: const u8[:][] = [
    "remi.code", "remi.issuer", "remi.remittance_info",
];
const ING_ULTC_FIELDS: const u8[:][] = ["ultc.name", "ultc.id"];
const ING_ULTD_FIELDS: const u8[:][] = ["ultd.name", "ultd.id"];

// The index of the nested tags in the table of ING.
const ING_IDX_CNTP: i64 = 5;
const ING_IDX_REMI: i64 = 6;
const ING_IDX_ULTC: i64 = 8;
const ING_IDX_ULTD: i64 = 9;

// put_dialect gives one value to the caller. The value must point at
// the text or at the buffer of the caller.
fn put_dialect(out: DialectValue[>..]&, lim: Limits&, key: const u8[:], value: const u8[:]) -> Fault {
    if out.len >= lim.max_fields { return fault(F_LIMIT, 0, 1, "", "more dialect values than max_fields"); }
    out.push(DialectValue { key: key, value: value });
    return no_fault();
}

// copy_no_lines copies the text into the buffer without its line ends.
// The span points at the buffer of the caller.
fn copy_no_lines(text: const u8[:], buf: u8[>..]&) -> const u8[:] {
    let start = buf.len;
    var i = 0;
    while i < text.len {
        let c = text[i];
        if c != '\n' && c != '\r' { buf.push(c); }
        i += 1;
    }
    return buf[start..];
}

// copy_span copies the text into the buffer. The span points at the
// buffer of the caller.
fn copy_span(text: const u8[:], buf: u8[>..]&) -> const u8[:] {
    let start = buf.len;
    for c in text { buf.push(c); }
    return buf[start..];
}

// tag_at tells whether the text starts with the tag at the index.
fn tag_at(text: const u8[:], tags: const u8[:][]&, idx: i64) -> bool {
    let t = tags[idx];
    if text.len < t.len { return false; }
    return text[..t.len] == t;
}

// value_end gives the end of the value of a tag. The value ends at the
// next tag of the bank, or at the end of the text.
fn value_end(text: const u8[:], tags: const u8[:][]&, skip: i64) -> i64 {
    var end = text.len;
    var i = 0;
    while i < tags.len {
        if i != skip {
            let at = find(text, tags[i]);
            if at >= 0 && at < end { end = at; }
        }
        i += 1;
    }
    return end;
}

// walk_tags reads the values of the tags of a bank. A tag gives a value
// when the text starts with it. The value ends at the next tag of the
// bank.
fn walk_tags(text: const u8[:], tags: const u8[:][]&, names: const u8[:][]&,
             out: DialectValue[>..]&, lim: Limits&) -> Fault {
    var start = 0;
    var i = 0;
    while i < tags.len {
        let rest = text[start..];
        if tag_at(rest, tags, i) {
            let t = tags[i];
            let body = rest[t.len..];
            let end = value_end(body, tags, i);
            let f = put_dialect(out, lim, names[i], body[..end]);
            if f.kind != F_NONE { return f; }
            start = start + t.len + end;
        }
        if start >= text.len { break; }
        i += 1;
    }
    return no_fault();
}

// abn_account gives the end of the account number at the start of the
// text. The number has four groups of digits with dots between them.
// The end is -1 when the text does not hold one.
fn abn_account(text: const u8[:]) -> i64 {
    var i = 0;
    var group = 0;
    var max = 3;
    while group < 4 {
        var digits = 0;
        while i < text.len && is_digit(text[i]) && digits < max {
            digits += 1;
            i += 1;
        }
        if digits == 0 { return -1; }
        if group == 3 { return i; }
        if i >= text.len || text[i] != '.' { return -1; }
        i += 1;
        group += 1;
        max = 2;
        if group == 3 { max = 3; }
    }
    return -1;
}

// abn_giro gives the digits of a giro account at the start of the
// text. The end is -1 when the text does not hold one.
fn abn_giro(text: const u8[:]) -> i64, i64 {
    if text.len < 5 { return 0, -1; }
    if text[..4] != "GIRO" { return 0, -1; }
    var i = 4;
    while i < text.len && text[i] == ' ' { i += 1; }
    let start = i;
    while i < text.len && is_digit(text[i]) { i += 1; }
    if i == start { return 0, -1; }
    return start, i;
}

// abn_dialect reads the text of an ABN AMRO statement line. The
// account number stands at the start of the text. The dots come out of
// the value. The tags of the bank follow the account number.
fn abn_dialect(text: const u8[:], out: DialectValue[>..]&, lim: Limits&, buf: u8[>..]&) -> Fault {
    var start = 0;
    let acc_end = abn_account(text);
    if acc_end >= 0 {
        var digits: u8[>..] = [];
        var i = 0;
        while i < acc_end {
            if text[i] != '.' { digits.push(text[i]); }
            i += 1;
        }
        let f = put_dialect(out, lim, "account", copy_span(digits, buf));
        if f.kind != F_NONE { return f; }
        start = acc_end;
    } else {
        let gstart, gend = abn_giro(text);
        if gend > gstart {
            let f = put_dialect(out, lim, "account", copy_span(text[gstart..gend], buf));
            if f.kind != F_NONE { return f; }
            start = gend;
        }
    }
    return walk_tags(text[start..], ABN_TAGS, ABN_NAMES, out, lim);
}

// ing_lead gives the parts of the leading fields of a nested value and
// the rest of the value. The value is split on the slash, at most lead
// times. The parts go into the array of the caller.
fn ing_lead(value: const u8[:], lead: i64, parts: const u8[:][>..]&) -> i64 {
    var start = 0;
    var n = 0;
    var i = 0;
    while i < value.len && n < lead {
        if value[i] == '/' {
            parts.push(value[start..i]);
            start = i + 1;
            n += 1;
        }
        i += 1;
    }
    parts.push(value[start..]);
    return n;
}

// ing_tail gives the parts of the trailing fields of a nested value.
// The value is split from the right on the slash, at most maxsplit
// times. The parts come in the order of the text.
fn ing_tail(value: const u8[:], maxsplit: i64, parts: const u8[:][>..]&) {
    var cuts: i64[>..] = [];
    var i = value.len;
    while i > 0 && cuts.len < maxsplit {
        i -= 1;
        if value[i] == '/' { cuts.push(i); }
    }
    var start = 0;
    var k = cuts.len;
    while k > 0 {
        k -= 1;
        let at = cuts[k];
        parts.push(value[start..at]);
        start = at + 1;
    }
    parts.push(value[start..]);
}

// ing_nested reads the parts of a nested tag of ING. The name of a part
// holds the name of the tag and the name of the part. The leading parts
// come from a split on the slash from the left. The trailing parts come
// from a split from the right, so that a name may hold a slash.
fn ing_nested(fields: const u8[:][]&, lead: i64, value: const u8[:],
               out: DialectValue[>..]&, lim: Limits&) -> Fault {
    var parts: const u8[:][>..] = [];
    let n = ing_lead(value, lead, parts);
    // The leading fields take the parts before the last one.
    var i = 0;
    while i < n {
        let f = put_dialect(out, lim, fields[i], parts[i]);
        if f.kind != F_NONE { return f; }
        i += 1;
    }
    // The trailing fields take the rest. The rest is split from the
    // right, so that the name of the bank may hold a slash.
    var rest: const u8[:][>..] = [];
    ing_tail(parts[n], fields.len - lead - 1, rest);
    var j = 0;
    while j < rest.len {
        let idx = lead + j;
        if idx >= fields.len { break; }
        let f = put_dialect(out, lim, fields[idx], rest[j]);
        if f.kind != F_NONE { return f; }
        j += 1;
    }
    return no_fault();
}

// ing_value gives the value of one tag of ING. A nested tag gives its
// parts instead of one value.
fn ing_value(idx: i64, value: const u8[:], out: DialectValue[>..]&, lim: Limits&) -> Fault {
    if idx == ING_IDX_CNTP { return ing_nested(ING_CNTP_FIELDS, 2, value, out, lim); }
    if idx == ING_IDX_REMI { return ing_nested(ING_REMI_FIELDS, 2, value, out, lim); }
    if idx == ING_IDX_ULTC { return ing_nested(ING_ULTC_FIELDS, 0, value, out, lim); }
    if idx == ING_IDX_ULTD { return ing_nested(ING_ULTD_FIELDS, 0, value, out, lim); }
    return put_dialect(out, lim, ING_NAMES[idx], value);
}

// ing_dialect reads the text of an ING statement line. The tags of the
// bank may stand at any place in the text. The value of a tag ends at
// the next tag, without the slash that separates the two.
fn ing_dialect(text: const u8[:], out: DialectValue[>..]&, lim: Limits&) -> Fault {
    var pos = 0;
    var have = false;
    var cur = 0;
    var start = 0;
    while pos < text.len {
        // The tag of the bank that starts at pos, if any.
        var best = -1;
        var i = 0;
        while i < ING_TAGS.len {
            let t = ING_TAGS[i];
            if text.len - pos >= t.len && text[pos..pos + t.len] == t { best = i; break; }
            i += 1;
        }
        if best < 0 { pos += 1; continue; }
        if have {
            // The value of the tag before ends at this tag. A slash at
            // the end of the value separates it from the next tag.
            var end = pos;
            if end > start && text[end - 1] == '/' { end -= 1; }
            let f = ing_value(cur, text[start..end], out, lim);
            if f.kind != F_NONE { return f; }
        }
        cur = best;
        start = pos + ING_TAGS[best].len;
        have = true;
        pos = start;
    }
    if have {
        var end = text.len;
        if end > start && text[end - 1] == '/' { end -= 1; }
        let f = ing_value(cur, text[start..end], out, lim);
        if f.kind != F_NONE { return f; }
    }
    return no_fault();
}

// regiobank_dialect reads the text of a Regiobank statement line. The
// dialect reads the lines by position.
fn regiobank_dialect(text: const u8[:], out: DialectValue[>..]&, lim: Limits&, buf: u8[>..]&) -> Fault {
    // The first line holds the account number and the name.
    var e0 = 0;
    while e0 < text.len && text[e0] != '\n' { e0 += 1; }
    if e0 >= text.len { return no_fault(); }
    // The second line holds the address. A text with one line gives no
    // value.
    var e1 = e0 + 1;
    while e1 < text.len && text[e1] != '\n' { e1 += 1; }
    if e1 <= e0 { return no_fault(); }
    var first = text[..e0];
    if first.len > 0 && first[first.len - 1] == '\r' { first = first[..first.len - 1]; }
    let space = find(first, " ");
    if space < 0 { return no_fault(); }
    let name = first[space + 1..];
    var second = text[e0 + 1..e1];
    if second.len > 0 && second[second.len - 1] == '\r' { second = second[..second.len - 1]; }
    let f = put_dialect(out, lim, "account_number", first[..space]);
    if f.kind != F_NONE { return f; }
    let g = put_dialect(out, lim, "name", name);
    if g.kind != F_NONE { return g; }
    let h = put_dialect(out, lim, "address", second);
    if h.kind != F_NONE { return h; }
    // The rest holds the IBAN, the remittance text and the description,
    // or the reference.
    if e1 >= text.len { return no_fault(); }
    let rest = copy_no_lines(text[e1 + 1..], buf);
    // The bank writes "aan" and the name before the parts.
    var want: u8[>..] = [];
    for c in "aan " { want.push(c); }
    for c in name { want.push(c); }
    if rest.len >= want.len && rest[..want.len] == want {
        // The parts are separated by a comma.
        var parts: const u8[:][>..] = [];
        var start = 0;
        var i = 0;
        while i < rest.len {
            if rest[i] == ',' {
                parts.push(rest[start..i]);
                start = i + 1;
            }
            i += 1;
        }
        parts.push(rest[start..]);
        if parts.len == 4 {
            let j = put_dialect(out, lim, "iban", parts[1]);
            if j.kind != F_NONE { return j; }
            let k = put_dialect(out, lim, "remittance_info", parts[2]);
            if k.kind != F_NONE { return k; }
            let l = put_dialect(out, lim, "description", parts[3]);
            if l.kind != F_NONE { return l; }
            return no_fault();
        }
    }
    return put_dialect(out, lim, "reference", rest);
}

// mbank_dialect reads the text of an mBank statement line. The first
// field up to the semicolon starts with the transaction code. The text
// may hold an IPH id and a TNR number. Python mt940 reads the same three.
// A value that is not there gives no value. The values point at the text.
fn mbank_dialect(text: const u8[:], out: DialectValue[>..]&, lim: Limits&) -> Fault {
    // The transaction code: digits before the first space of the first
    // semicolon field.
    var i = 0;
    while i < text.len && is_digit(text[i]) { i += 1; }
    if i > 0 && i <= 9 && (i == text.len || text[i] == ' ' || text[i] == ';') {
        let f = put_dialect(out, lim, "transaction_code", text[..i]);
        if f.kind != F_NONE { return f; }
    }
    // The IPH id: " ID IPH: " then masking X marks, up to 14 digits, ";".
    let ip = find(text, " ID IPH: ");
    if ip >= 0 {
        var j = ip + 9;
        while j < text.len && (text[j] == 'X' || text[j] == 'x') { j += 1; }
        let ds = j;
        while j < text.len && is_digit(text[j]) && j - ds < 14 { j += 1; }
        if j < text.len && text[j] == ';' {
            let f = put_dialect(out, lim, "iph_id", text[ds..j]);
            if f.kind != F_NONE { return f; }
        }
    }
    // The TNR number: "TNR:", one space or line end, digits, ".", digits.
    let tp = find(text, "TNR:");
    if tp >= 0 {
        var j = tp + 4;
        if j < text.len && (text[j] == ' ' || text[j] == '\n') { j += 1; }
        else if j + 1 < text.len && text[j] == '\r' && text[j + 1] == '\n' { j += 2; }
        else { return no_fault(); }
        let ds = j;
        while j < text.len && is_digit(text[j]) { j += 1; }
        if j > ds && j < text.len && text[j] == '.' {
            j += 1;
            let es = j;
            while j < text.len && is_digit(text[j]) { j += 1; }
            if j > es { return put_dialect(out, lim, "tnr", text[ds..j]); }
        }
    }
    return no_fault();
}

// parse_dialect reads the text of a :86: field with the dialect of the
// named bank. It gives the values of the bank. A text of another bank
// gives no values and no fault.
fn parse_dialect(kind: i32, text: const u8[:], lim: Limits&, out: DialectValue[>..]&, buf: u8[>..]&) -> Fault {
    if kind != D_RABOBANK && kind != D_ABN_AMRO && kind != D_ING && kind != D_REGIOBANK && kind != D_MBANK {
        return fault(F_SYNTAX, 0, 1, "", "the kind is not a bank of the package");
    }
    if text.len > lim.max_field { return fault(F_LIMIT, 0, 1, "", "the text is longer than max_field"); }
    if kind == D_REGIOBANK { return regiobank_dialect(text, out, lim, buf); }
    if kind == D_MBANK { return mbank_dialect(text, out, lim); }
    // The other banks write their tags over the line ends.
    let joined = copy_no_lines(text, buf);
    if kind == D_RABOBANK { return walk_tags(joined, RABO_TAGS, RABO_NAMES, out, lim); }
    if kind == D_ABN_AMRO { return abn_dialect(joined, out, lim, buf); }
    return ing_dialect(joined, out, lim);
}
