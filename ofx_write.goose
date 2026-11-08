// The OFX writer of the bank_statement package.
//
// write_ofx appends an OFX 1.x (SGML) or 2.x (XML) file to the buffer
// of the caller. It takes the statements, entries, balances and notes
// that parse_ofx gives. Every text is checked and escaped. The
// characters & < > become entities in both forms, and a byte above 127
// becomes a numeric reference, so the file is plain ASCII. A control
// byte, an unknown enum value, a missing required field and a text
// above its length limit are faults. No text is cut.
namespace bank_statement;

import std;
import fault;
import limits;
import amount;
import currency;
import date;
import mt940;
import write_text;

// OfxWriteOptions holds the options of the writer. The version is a
// number such as 102 or 203. It is 102 when 0. A version below 200
// writes SGML, a version from 200 writes XML. The flag credit_card
// writes credit card statements. The flag close_leaves closes the leaf
// tags in SGML, and XML always closes them. The flag indent writes one
// tag per line. The server date is required, because the writer reads
// no clock. The bank id and the account type are defaults for a
// statement that holds none of its own. The currency is the default for
// a statement whose balances and entries name none.
struct OfxWriteOptions {
    version: i32,
    credit_card: bool,
    close_leaves: bool,
    indent: bool,
    server_date: Date,
    org: const u8[:],
    fid: const u8[:],
    bank_id: const u8[:],
    account_type: const u8[:],
    currency: const u8[:],
}

// OfxForm holds the layout of the body.
struct OfxForm {
    closed: bool,
    indent: bool,
}

const TRNTYPES: const u8[:][] = [
    "CREDIT", "DEBIT", "INT", "DIV", "FEE", "SRVCHG", "DEP", "ATM", "POS", "XFER",
    "CHECK", "PAYMENT", "CASH", "DIRECTDEP", "DIRECTDEBIT", "REPEATPMT", "OTHER",
];
const ACCTTYPES: const u8[:][] = ["CHECKING", "SAVINGS", "MONEYMRKT", "CREDITLINE", "CD"];

// in_list tells whether the text is one of the words.
fn in_list(words: const u8[:][]&, s: const u8[:]) -> bool {
    for w in words {
        if w == s { return true; }
    }
    return false;
}

fn version_ok(v: i32) -> bool {
    return v == 100 || v == 102 || v == 103 || v == 151 || v == 160
        || v == 200 || v == 201 || v == 202 || v == 203 || v == 210 || v == 211 || v == 220;
}

fn put_ref(out: u8[>..]&, cp: i64) {
    put(out, "&#");
    put_num(out, cp, 1);
    out.push(';');
}

// put_escaped appends the text with & < > and the bytes above 127
// replaced. A byte sequence that is not UTF-8 is a fault.
fn put_escaped(out: u8[>..]&, s: const u8[:], tag: const u8[:]) -> Fault {
    var i: i64 = 0;
    while i < s.len {
        let c = s[i];
        if c == '&' { put(out, "&amp;"); i += 1; }
        else if c == '<' { put(out, "&lt;"); i += 1; }
        else if c == '>' { put(out, "&gt;"); i += 1; }
        else if c < 128 { out.push(c); i += 1; }
        else {
            var n: i64 = 0;
            var cp: i64 = 0;
            var min: i64 = 0;
            if c >= 0xC2 && c <= 0xDF { n = 1; cp = (c as i64) & 0x1F; min = 0x80; }
            else if c >= 0xE0 && c <= 0xEF { n = 2; cp = (c as i64) & 0x0F; min = 0x800; }
            else if c >= 0xF0 && c <= 0xF4 { n = 3; cp = (c as i64) & 0x07; min = 0x10000; }
            else { return fault(F_SYNTAX, 0, 0, tag, "text is not UTF-8"); }
            if i + n >= s.len { return fault(F_SYNTAX, 0, 0, tag, "text is not UTF-8"); }
            var k: i64 = 1;
            while k <= n {
                let d = s[i + k];
                if d < 0x80 || d > 0xBF { return fault(F_SYNTAX, 0, 0, tag, "text is not UTF-8"); }
                cp = cp * 64 + ((d as i64) & 0x3F);
                k += 1;
            }
            if cp < min || cp > 0x10FFFF || (cp >= 0xD800 && cp <= 0xDFFF) {
                return fault(F_SYNTAX, 0, 0, tag, "text is not UTF-8");
            }
            put_ref(out, cp);
            i += n + 1;
        }
    }
    return no_fault();
}

fn put_indent(out: u8[>..]&, w: OfxForm, depth: i64) {
    if !w.indent { return; }
    var i: i64 = 0;
    while i < depth * 2 { out.push(' '); i += 1; }
}

fn put_break(out: u8[>..]&, w: OfxForm) {
    if w.indent { out.push('\n'); }
}

// open_tag writes the start tag of an aggregate.
fn open_tag(out: u8[>..]&, w: OfxForm, tag: const u8[:], depth: i64) {
    put_indent(out, w, depth);
    out.push('<'); put(out, tag); out.push('>');
    put_break(out, w);
}

// close_tag writes the end tag of an aggregate.
fn close_tag(out: u8[>..]&, w: OfxForm, tag: const u8[:], depth: i64) {
    put_indent(out, w, depth);
    put(out, "</"); put(out, tag); out.push('>');
    put_break(out, w);
}

// leaf writes a leaf element with a checked and escaped text. The text
// must not be empty and must not be longer than max bytes.
fn leaf(out: u8[>..]&, w: OfxForm, tag: const u8[:], value: const u8[:], max: i64,
        depth: i64, lim: Limits&) -> Fault {
    if value.len == 0 { return fault(F_SYNTAX, 0, 0, tag, "a required value is empty"); }
    if value.len > max { return fault(F_LIMIT, 0, 0, tag, "text is longer than the OFX limit"); }
    let f = check_text(value, tag, lim);
    if f.kind != F_NONE { return f; }
    put_indent(out, w, depth);
    out.push('<'); put(out, tag); out.push('>');
    let e = put_escaped(out, value, tag);
    if e.kind != F_NONE { return e; }
    if w.closed { put(out, "</"); put(out, tag); out.push('>'); }
    put_break(out, w);
    return no_fault();
}

// leaf_date writes a date as YYYYMMDD000000.000[0:GMT].
fn leaf_date(out: u8[>..]&, w: OfxForm, tag: const u8[:], d: Date, depth: i64, lim: Limits&) -> Fault {
    let f = check_date(d, tag);
    if f.kind != F_NONE { return f; }
    var s: u8[>..] = [];
    put_num(s, d.year as i64, 4);
    put_num(s, d.month as i64, 2);
    put_num(s, d.day as i64, 2);
    put(s, "000000.000[0:GMT]");
    return leaf(out, w, tag, s, 32, depth, lim);
}

fn leaf_money(out: u8[>..]&, w: OfxForm, tag: const u8[:], minor: i64, exp: i32,
              depth: i64, lim: Limits&) -> Fault {
    var s: u8[>..] = [];
    put_amount(s, minor, exp, '.');
    return leaf(out, w, tag, s, 32, depth, lim);
}

fn mag_of(m: i64) -> i64 {
    if m == -9223372036854775808 { return m; }
    if m < 0 { return -m; }
    return m;
}

// signed_balance gives the signed amount of a balance.
fn signed_balance(b: Balance) -> i64, bool {
    if b.credit { 
        if b.amount.minor == -9223372036854775808 { return 0, false; }
        return mag_of(b.amount.minor), true;
    }
    if b.amount.minor == -9223372036854775808 { return b.amount.minor, true; }
    return -mag_of(b.amount.minor), true;
}

// signed_entry gives the signed amount of an entry. A debit is negative.
fn signed_entry(e: Entry) -> i64, bool {
    let m = e.amount.minor;
    var debit = m < 0;
    if e.mark == "D" || e.mark == "RC" { debit = true; }
    if e.mark == "C" || e.mark == "RD" { debit = false; }
    if m == -9223372036854775808 { return m, debit; }
    if debit { return -mag_of(m), true; }
    return mag_of(m), true;
}

fn find_note(notes: Note[>..]&, st: Statement, tag: const u8[:], fallback: const u8[:]) -> const u8[:] {
    var i: i64 = st.note_start as i64;
    let end = i + (st.note_count as i64);
    while i < end {
        if notes[i].tag == tag { return notes[i].value; }
        i += 1;
    }
    return fallback;
}

fn date_key(d: Date) -> i64 {
    return (d.year as i64) * 10000 + (d.month as i64) * 100 + (d.day as i64);
}

fn write_entry(out: u8[>..]&, w: OfxForm, e: Entry, depth: i64, lim: Limits&) -> Fault {
    let t: const u8[:] = "STMTTRN";
    let m, ok = signed_entry(e);
    if !ok { return fault(F_AMOUNT, 0, 0, t, "amount has no sign"); }
    if !in_list(TRNTYPES, e.type_id) { return fault(F_SYNTAX, 0, 0, "TRNTYPE", "unknown transaction type"); }
    open_tag(out, w, t, depth);
    var f = leaf(out, w, "TRNTYPE", e.type_id, 16, depth + 1, lim);
    if f.kind != F_NONE { return f; }
    f = leaf_date(out, w, "DTPOSTED", e.value_date, depth + 1, lim);
    if f.kind != F_NONE { return f; }
    if e.entry_date.year != 0 {
        f = leaf_date(out, w, "DTAVAIL", e.entry_date, depth + 1, lim);
        if f.kind != F_NONE { return f; }
    }
    f = leaf_money(out, w, "TRNAMT", m, e.amount.exp, depth + 1, lim);
    if f.kind != F_NONE { return f; }
    f = leaf(out, w, "FITID", e.entry_ref, 255, depth + 1, lim);
    if f.kind != F_NONE { return f; }
    if e.bank_ref.len > 0 {
        f = leaf(out, w, "SRVRTID", e.bank_ref, 10, depth + 1, lim);
        if f.kind != F_NONE { return f; }
    }
    if e.customer_ref.len > 0 {
        f = leaf(out, w, "CHECKNUM", e.customer_ref, 12, depth + 1, lim);
        if f.kind != F_NONE { return f; }
    }
    if e.supplementary.len > 0 {
        f = leaf(out, w, "REFNUM", e.supplementary, 32, depth + 1, lim);
        if f.kind != F_NONE { return f; }
    }
    if e.counter_name.len > 0 {
        f = leaf(out, w, "NAME", e.counter_name, 32, depth + 1, lim);
        if f.kind != F_NONE { return f; }
    }
    if e.narrative.len > 0 {
        f = leaf(out, w, "MEMO", e.narrative, 255, depth + 1, lim);
        if f.kind != F_NONE { return f; }
    }
    close_tag(out, w, t, depth);
    return no_fault();
}

fn write_balance(out: u8[>..]&, w: OfxForm, tag: const u8[:], b: Balance, fallback: Date,
                 depth: i64, lim: Limits&) -> Fault {
    let m, ok = signed_balance(b);
    if !ok { return fault(F_AMOUNT, 0, 0, tag, "balance has no sign"); }
    var d = b.date;
    if d.year == 0 { d = fallback; }
    open_tag(out, w, tag, depth);
    var f = leaf_money(out, w, "BALAMT", m, b.amount.exp, depth + 1, lim);
    if f.kind != F_NONE { return f; }
    f = leaf_date(out, w, "DTASOF", d, depth + 1, lim);
    if f.kind != F_NONE { return f; }
    close_tag(out, w, tag, depth);
    return no_fault();
}

// statement_currency picks the currency of a statement.
fn statement_currency(st: Statement, entries: Entry[>..]&, opts: OfxWriteOptions&) -> const u8[:] {
    if st.closing.kind != 0 && st.closing.amount.currency.len == 3 { return st.closing.amount.currency; }
    if st.entry_count > 0 && entries[st.entry_start].amount.currency.len == 3 {
        return entries[st.entry_start].amount.currency;
    }
    return opts.currency;
}

fn write_statement(out: u8[>..]&, w: OfxForm, st: Statement, entries: Entry[>..]&,
                   notes: Note[>..]&, opts: OfxWriteOptions&, lim: Limits&) -> Fault {
    let cc = opts.credit_card;
    var wrap: const u8[:] = "STMTTRNRS";
    var body: const u8[:] = "STMTRS";
    if cc { wrap = "CCSTMTTRNRS"; body = "CCSTMTRS"; }
    let ccy = statement_currency(st, entries, opts);
    if ccy.len != 3 || currency_index(ccy) < 0 {
        return fault(F_AMOUNT, 0, 0, "CURDEF", "the currency is not a known code");
    }
    if st.closing.kind == 0 { return fault(F_SYNTAX, 0, 0, "LEDGERBAL", "a statement needs a closing balance"); }
    open_tag(out, w, wrap, 2);
    var f = no_fault();
    if st.reference.len > 0 {
        f = leaf(out, w, "TRNUID", st.reference, 36, 3, lim);
    } else {
        f = leaf(out, w, "TRNUID", "0", 36, 3, lim);
    }
    if f.kind != F_NONE { return f; }
    open_tag(out, w, "STATUS", 3);
    f = leaf(out, w, "CODE", "0", 6, 4, lim);
    if f.kind != F_NONE { return f; }
    f = leaf(out, w, "SEVERITY", "INFO", 8, 4, lim);
    if f.kind != F_NONE { return f; }
    close_tag(out, w, "STATUS", 3);
    open_tag(out, w, body, 3);
    f = leaf(out, w, "CURDEF", ccy, 3, 4, lim);
    if f.kind != F_NONE { return f; }
    if cc {
        open_tag(out, w, "CCACCTFROM", 4);
        f = leaf(out, w, "ACCTID", st.account, 22, 5, lim);
        if f.kind != F_NONE { return f; }
        close_tag(out, w, "CCACCTFROM", 4);
    } else {
        let bank = find_note(notes, st, "BANKID", opts.bank_id);
        let kind = find_note(notes, st, "ACCTTYPE", opts.account_type);
        if kind.len > 0 && !in_list(ACCTTYPES, kind) {
            return fault(F_SYNTAX, 0, 0, "ACCTTYPE", "unknown account type");
        }
        open_tag(out, w, "BANKACCTFROM", 4);
        f = leaf(out, w, "BANKID", bank, 9, 5, lim);
        if f.kind != F_NONE { return f; }
        f = leaf(out, w, "ACCTID", st.account, 22, 5, lim);
        if f.kind != F_NONE { return f; }
        if kind.len > 0 {
            f = leaf(out, w, "ACCTTYPE", kind, 10, 5, lim);
        } else {
            f = leaf(out, w, "ACCTTYPE", "CHECKING", 10, 5, lim);
        }
        if f.kind != F_NONE { return f; }
        close_tag(out, w, "BANKACCTFROM", 4);
    }
    if st.entry_count > 0 {
        var lo = entries[st.entry_start].value_date;
        var hi = lo;
        var i: i64 = st.entry_start as i64;
        let end = i + (st.entry_count as i64);
        while i < end {
            let d = entries[i].value_date;
            if date_key(d) < date_key(lo) { lo = d; }
            if date_key(d) > date_key(hi) { hi = d; }
            i += 1;
        }
        open_tag(out, w, "BANKTRANLIST", 4);
        f = leaf_date(out, w, "DTSTART", lo, 5, lim);
        if f.kind != F_NONE { return f; }
        f = leaf_date(out, w, "DTEND", hi, 5, lim);
        if f.kind != F_NONE { return f; }
        i = st.entry_start as i64;
        while i < end {
            f = write_entry(out, w, entries[i], 5, lim);
            if f.kind != F_NONE { return with_pos(f, i - (st.entry_start as i64) + 1, f.tag); }
            i += 1;
        }
        close_tag(out, w, "BANKTRANLIST", 4);
    }
    f = write_balance(out, w, "LEDGERBAL", st.closing, opts.server_date, 4, lim);
    if f.kind != F_NONE { return f; }
    if st.available.kind != 0 {
        f = write_balance(out, w, "AVAILBAL", st.available, opts.server_date, 4, lim);
        if f.kind != F_NONE { return f; }
    }
    close_tag(out, w, body, 3);
    close_tag(out, w, wrap, 2);
    return no_fault();
}

// write_ofx appends the statements as an OFX file. All statements are
// bank statements, or all are credit card statements.
fn write_ofx(statements: Statement[>..]&, entries: Entry[>..]&,
             notes: Note[>..]&, opts: OfxWriteOptions, lim: Limits&, out: u8[>..]&) -> Fault {
    var v = opts.version;
    if v == 0 { v = 102; }
    if !version_ok(v) { return fault(F_SYNTAX, 0, 0, "VERSION", "the OFX version is not known"); }
    let xml = v >= 200;
    let w = OfxForm { closed: xml || opts.close_leaves, indent: opts.indent };
    if xml {
        put(out, "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"no\"?>\r\n");
        put(out, "<?OFX OFXHEADER=\"200\" VERSION=\"");
        put_num(out, v as i64, 3);
        put(out, "\" SECURITY=\"NONE\" OLDFILEUID=\"NONE\" NEWFILEUID=\"NONE\"?>\r\n");
    } else {
        put(out, "OFXHEADER:100\r\nDATA:OFXSGML\r\nVERSION:");
        put_num(out, v as i64, 3);
        put(out, "\r\nSECURITY:NONE\r\nENCODING:USASCII\r\nCHARSET:NONE\r\nCOMPRESSION:NONE\r\n");
        put(out, "OLDFILEUID:NONE\r\nNEWFILEUID:NONE\r\n\r\n");
    }
    open_tag(out, w, "OFX", 0);
    open_tag(out, w, "SIGNONMSGSRSV1", 1);
    open_tag(out, w, "SONRS", 2);
    open_tag(out, w, "STATUS", 3);
    var f = leaf(out, w, "CODE", "0", 6, 4, lim);
    if f.kind != F_NONE { return f; }
    f = leaf(out, w, "SEVERITY", "INFO", 8, 4, lim);
    if f.kind != F_NONE { return f; }
    close_tag(out, w, "STATUS", 3);
    f = leaf_date(out, w, "DTSERVER", opts.server_date, 3, lim);
    if f.kind != F_NONE { return f; }
    f = leaf(out, w, "LANGUAGE", "ENG", 3, 3, lim);
    if f.kind != F_NONE { return f; }
    if opts.org.len > 0 {
        open_tag(out, w, "FI", 3);
        f = leaf(out, w, "ORG", opts.org, 32, 4, lim);
        if f.kind != F_NONE { return f; }
        if opts.fid.len > 0 {
            f = leaf(out, w, "FID", opts.fid, 32, 4, lim);
            if f.kind != F_NONE { return f; }
        }
        close_tag(out, w, "FI", 3);
    }
    close_tag(out, w, "SONRS", 2);
    close_tag(out, w, "SIGNONMSGSRSV1", 1);
    var set: const u8[:] = "BANKMSGSRSV1";
    if opts.credit_card { set = "CREDITCARDMSGSRSV1"; }
    if statements.len > 0 {
        open_tag(out, w, set, 1);
        var i: i64 = 0;
        while i < statements.len {
            let e = write_statement(out, w, statements[i], entries, notes, opts, lim);
            if e.kind != F_NONE { return e; }
            let s = check_size(out, lim);
            if s.kind != F_NONE { return s; }
            i += 1;
        }
        close_tag(out, w, set, 1);
    }
    close_tag(out, w, "OFX", 0);
    return check_size(out, lim);
}
