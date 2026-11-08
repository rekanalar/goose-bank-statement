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

// opt_leaf writes a leaf when the text is not empty.
fn opt_leaf(out: u8[>..]&, w: OfxForm, tag: const u8[:], value: const u8[:], max: i64,
            depth: i64, lim: Limits&) -> Fault {
    if value.len == 0 { return no_fault(); }
    return leaf(out, w, tag, value, max, depth, lim);
}

// write_payee writes a PAYEE aggregate. The name, the first address
// line, the city, the state, the postal code and the phone are required.
fn write_payee(out: u8[>..]&, w: OfxForm, p: OfxPayee, depth: i64, lim: Limits&) -> Fault {
    if p.country.len > 0 && !country_known(p.country) {
        return fault(F_SYNTAX, 0, 0, "COUNTRY", "the country is not an ISO 3166 alpha-3 code");
    }
    open_tag(out, w, "PAYEE", depth);
    var f = leaf(out, w, "NAME", p.name, 32, depth + 1, lim);
    if f.kind != F_NONE { return f; }
    f = leaf(out, w, "ADDR1", p.addr1, 32, depth + 1, lim);
    if f.kind != F_NONE { return f; }
    f = opt_leaf(out, w, "ADDR2", p.addr2, 32, depth + 1, lim);
    if f.kind != F_NONE { return f; }
    f = opt_leaf(out, w, "ADDR3", p.addr3, 32, depth + 1, lim);
    if f.kind != F_NONE { return f; }
    f = leaf(out, w, "CITY", p.city, 32, depth + 1, lim);
    if f.kind != F_NONE { return f; }
    f = leaf(out, w, "STATE", p.state, 5, depth + 1, lim);
    if f.kind != F_NONE { return f; }
    f = leaf(out, w, "POSTALCODE", p.postal_code, 11, depth + 1, lim);
    if f.kind != F_NONE { return f; }
    f = opt_leaf(out, w, "COUNTRY", p.country, 3, depth + 1, lim);
    if f.kind != F_NONE { return f; }
    f = leaf(out, w, "PHONE", p.phone, 32, depth + 1, lim);
    if f.kind != F_NONE { return f; }
    close_tag(out, w, "PAYEE", depth);
    return no_fault();
}

// write_rate writes a CURRENCY or ORIGCURRENCY aggregate. The rate text
// must read back as the exact rational of the entry.
fn write_rate(out: u8[>..]&, w: OfxForm, e: Entry, depth: i64, lim: Limits&) -> Fault {
    let x = e.ofx;
    var tag: const u8[:] = "CURRENCY";
    if x.rate_kind == 'O' { tag = "ORIGCURRENCY"; }
    if x.rate_kind != 'C' && x.rate_kind != 'O' { return fault(F_SYNTAX, 0, 0, "CURRATE", "the rate kind is not C or O"); }
    let r, rf = ofx_ratio(x.rate_text);
    if rf.kind != F_NONE { return with_pos(rf, 0, "CURRATE"); }
    if r.num == 0 || r.num != x.rate.num || r.den != x.rate.den {
        return fault(F_AMOUNT, 0, 0, "CURRATE", "the rate text differs from the rate or is zero");
    }
    if x.rate_symbol.len != 3 || currency_index(x.rate_symbol) < 0 {
        return fault(F_AMOUNT, 0, 0, "CURSYM", "the currency is not a known code");
    }
    if x.rate_kind == 'C' && e.amount.currency != x.rate_symbol {
        return fault(F_AMOUNT, 0, 0, "CURSYM", "the symbol differs from the currency of the amount");
    }
    open_tag(out, w, tag, depth);
    var f = leaf(out, w, "CURRATE", x.rate_text, 32, depth + 1, lim);
    if f.kind != F_NONE { return f; }
    f = leaf(out, w, "CURSYM", x.rate_symbol, 3, depth + 1, lim);
    if f.kind != F_NONE { return f; }
    close_tag(out, w, tag, depth);
    return no_fault();
}

// write_acct_to writes a BANKACCTTO or a CCACCTTO aggregate.
fn write_acct_to(out: u8[>..]&, w: OfxForm, x: OfxEntry, depth: i64, lim: Limits&) -> Fault {
    let a = x.acct_to;
    if x.acct_to_kind == 'B' {
        if !in_list(ACCTTYPES, a.acct_type) { return fault(F_SYNTAX, 0, 0, "ACCTTYPE", "unknown account type"); }
        open_tag(out, w, "BANKACCTTO", depth);
        var f = leaf(out, w, "BANKID", a.bank_id, 9, depth + 1, lim);
        if f.kind != F_NONE { return f; }
        f = opt_leaf(out, w, "BRANCHID", a.branch_id, 22, depth + 1, lim);
        if f.kind != F_NONE { return f; }
        f = leaf(out, w, "ACCTID", a.acct_id, 22, depth + 1, lim);
        if f.kind != F_NONE { return f; }
        f = leaf(out, w, "ACCTTYPE", a.acct_type, 10, depth + 1, lim);
        if f.kind != F_NONE { return f; }
        f = opt_leaf(out, w, "ACCTKEY", a.acct_key, 22, depth + 1, lim);
        if f.kind != F_NONE { return f; }
        close_tag(out, w, "BANKACCTTO", depth);
        return no_fault();
    }
    if x.acct_to_kind != 'C' { return fault(F_SYNTAX, 0, 0, "ACCTTO", "the account kind is not B or C"); }
    open_tag(out, w, "CCACCTTO", depth);
    var f = leaf(out, w, "ACCTID", a.acct_id, 22, depth + 1, lim);
    if f.kind != F_NONE { return f; }
    f = opt_leaf(out, w, "ACCTKEY", a.acct_key, 22, depth + 1, lim);
    if f.kind != F_NONE { return f; }
    close_tag(out, w, "CCACCTTO", depth);
    return no_fault();
}

fn leaf_count(out: u8[>..]&, w: OfxForm, tag: const u8[:], n: i64, depth: i64, lim: Limits&) -> Fault {
    var s: u8[>..] = [];
    put_num(s, n, 1);
    return leaf(out, w, tag, s, 9, depth, lim);
}

// write_image writes the IMAGEDATA aggregate of a transaction. The
// package only writes a reference. It never fetches one.
fn write_image(out: u8[>..]&, w: OfxForm, im: OfxImage, depth: i64, lim: Limits&) -> Fault {
    if !in_list(IMAGE_KINDS, im.kind) { return fault(F_SYNTAX, 0, 0, "IMAGETYPE", "unknown image type"); }
    if !in_list(IMAGE_REF_KINDS, im.ref_kind) { return fault(F_SYNTAX, 0, 0, "IMAGEREFTYPE", "unknown reference type"); }
    if im.check_sup.len > 0 && !in_list(CHECK_SUPS, im.check_sup) {
        return fault(F_SYNTAX, 0, 0, "CHECKSUP", "unknown check side");
    }
    if im.has_delay && im.avail.year != 0 {
        return fault(F_SYNTAX, 0, 0, "IMAGEDATA", "the image holds IMAGEDELAY and DTIMAGEAVAIL together");
    }
    if im.delay < 0 || im.ttl < 0 || im.delay > 999999999 || im.ttl > 999999999 {
        return fault(F_SYNTAX, 0, 0, "IMAGEDELAY", "a day count is out of range");
    }
    open_tag(out, w, "IMAGEDATA", depth);
    var f = leaf(out, w, "IMAGETYPE", im.kind, 11, depth + 1, lim);
    if f.kind != F_NONE { return f; }
    f = leaf(out, w, "IMAGEREF", im.ref, 255, depth + 1, lim);
    if f.kind != F_NONE { return f; }
    f = leaf(out, w, "IMAGEREFTYPE", im.ref_kind, 7, depth + 1, lim);
    if f.kind != F_NONE { return f; }
    if im.has_delay {
        f = leaf_count(out, w, "IMAGEDELAY", im.delay, depth + 1, lim);
        if f.kind != F_NONE { return f; }
    }
    if im.avail.year != 0 {
        f = leaf_date(out, w, "DTIMAGEAVAIL", im.avail, depth + 1, lim);
        if f.kind != F_NONE { return f; }
    }
    if im.has_ttl {
        f = leaf_count(out, w, "IMAGETTL", im.ttl, depth + 1, lim);
        if f.kind != F_NONE { return f; }
    }
    f = opt_leaf(out, w, "CHECKSUP", im.check_sup, 12, depth + 1, lim);
    if f.kind != F_NONE { return f; }
    close_tag(out, w, "IMAGEDATA", depth);
    return no_fault();
}

fn write_entry(out: u8[>..]&, w: OfxForm, e: Entry, depth: i64, lim: Limits&) -> Fault {
    let t: const u8[:] = "STMTTRN";
    let x = e.ofx;
    let m, ok = signed_entry(e);
    if !ok { return fault(F_AMOUNT, 0, 0, t, "amount has no sign"); }
    if !in_list(TRNTYPES, e.type_id) { return fault(F_SYNTAX, 0, 0, "TRNTYPE", "unknown transaction type"); }
    if x.correct_action.len > 0 && x.correct_action != "REPLACE" && x.correct_action != "DELETE" {
        return fault(F_SYNTAX, 0, 0, "CORRECTACTION", "the action is not REPLACE or DELETE");
    }
    if x.correct_ref.len > 0 && x.correct_action.len == 0 {
        return fault(F_SYNTAX, 0, 0, "CORRECTACTION", "a correction needs its action");
    }
    if x.correct_action.len > 0 && x.correct_ref.len == 0 {
        return fault(F_SYNTAX, 0, 0, "CORRECTFITID", "an action needs the corrected id");
    }
    if x.has_payee && e.counter_name.len > 0 && e.counter_name != x.payee.name {
        return fault(F_SYNTAX, 0, 0, "PAYEE", "the entry holds a name and a payee");
    }
    open_tag(out, w, t, depth);
    var f = leaf(out, w, "TRNTYPE", e.type_id, 16, depth + 1, lim);
    if f.kind != F_NONE { return f; }
    f = leaf_date(out, w, "DTPOSTED", e.value_date, depth + 1, lim);
    if f.kind != F_NONE { return f; }
    if x.user_date.year != 0 {
        f = leaf_date(out, w, "DTUSER", x.user_date, depth + 1, lim);
        if f.kind != F_NONE { return f; }
    }
    if e.entry_date.year != 0 {
        f = leaf_date(out, w, "DTAVAIL", e.entry_date, depth + 1, lim);
        if f.kind != F_NONE { return f; }
    }
    f = leaf_money(out, w, "TRNAMT", m, e.amount.exp, depth + 1, lim);
    if f.kind != F_NONE { return f; }
    f = leaf(out, w, "FITID", e.entry_ref, 255, depth + 1, lim);
    if f.kind != F_NONE { return f; }
    f = opt_leaf(out, w, "CORRECTFITID", x.correct_ref, 255, depth + 1, lim);
    if f.kind != F_NONE { return f; }
    f = opt_leaf(out, w, "CORRECTACTION", x.correct_action, 7, depth + 1, lim);
    if f.kind != F_NONE { return f; }
    f = opt_leaf(out, w, "SRVRTID", e.bank_ref, 10, depth + 1, lim);
    if f.kind != F_NONE { return f; }
    f = opt_leaf(out, w, "CHECKNUM", e.customer_ref, 12, depth + 1, lim);
    if f.kind != F_NONE { return f; }
    f = opt_leaf(out, w, "REFNUM", e.supplementary, 32, depth + 1, lim);
    if f.kind != F_NONE { return f; }
    if x.has_sic {
        if x.sic < 0 { return fault(F_SYNTAX, 0, 0, "SIC", "the code is negative"); }
        f = leaf_count(out, w, "SIC", x.sic, depth + 1, lim);
        if f.kind != F_NONE { return f; }
    }
    f = opt_leaf(out, w, "PAYEEID", x.payee_id, 12, depth + 1, lim);
    if f.kind != F_NONE { return f; }
    if x.has_payee {
        f = write_payee(out, w, x.payee, depth + 1, lim);
    } else {
        f = opt_leaf(out, w, "NAME", e.counter_name, 32, depth + 1, lim);
    }
    if f.kind != F_NONE { return f; }
    f = opt_leaf(out, w, "EXTDNAME", x.ext_name, 100, depth + 1, lim);
    if f.kind != F_NONE { return f; }
    if x.acct_to_kind != 0 {
        f = write_acct_to(out, w, x, depth + 1, lim);
        if f.kind != F_NONE { return f; }
    }
    f = opt_leaf(out, w, "MEMO", e.narrative, 255, depth + 1, lim);
    if f.kind != F_NONE { return f; }
    if x.image_count > 0 {
        f = write_image(out, w, x.image, depth + 1, lim);
        if f.kind != F_NONE { return f; }
    }
    if x.rate_kind != 0 {
        f = write_rate(out, w, e, depth + 1, lim);
        if f.kind != F_NONE { return f; }
    }
    if x.inv401k_source.len > 0 {
        if !in_list(INV401K, x.inv401k_source) { return fault(F_SYNTAX, 0, 0, "INV401KSOURCE", "unknown source"); }
        f = leaf(out, w, "INV401KSOURCE", x.inv401k_source, 14, depth + 1, lim);
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
