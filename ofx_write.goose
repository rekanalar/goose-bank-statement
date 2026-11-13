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
    let cc = opts.credit_card || st.credit_card;
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

// put_ofx_header writes the header of an OFX file: the XML declaration
// and the OFX instruction in 2.x, the header lines in 1.x.
fn put_ofx_header(out: u8[>..]&, v: i32) {
    if v >= 200 {
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
}

// write_ofx appends the statements as an OFX file. All statements are
// bank statements, or all are credit card statements.
// write_set writes the statements of one account kind into one message
// set. A bank statement lands in the bank set. A credit card statement
// lands in the credit card set. The flag opts.credit_card puts every
// statement into the credit card set.
fn write_set(out: u8[>..]&, w: OfxForm, set: const u8[:], statements: Statement[>..]&, entries: Entry[>..]&,
             notes: Note[>..]&, opts: OfxWriteOptions, lim: Limits&) -> Fault {
    var wrote: i64 = 0;
    var i: i64 = 0;
    while i < statements.len {
        let is_cc = opts.credit_card || statements[i].credit_card;
        if set == "CREDITCARDMSGSRSV1" && !is_cc { i += 1; continue; }
        if set == "BANKMSGSRSV1" && is_cc { i += 1; continue; }
        if wrote == 0 { open_tag(out, w, set, 1); }
        let e = write_statement(out, w, statements[i], entries, notes, opts, lim);
        if e.kind != F_NONE { return e; }
        let s = check_size(out, lim);
        if s.kind != F_NONE { return s; }
        wrote += 1;
        i += 1;
    }
    if wrote > 0 { close_tag(out, w, set, 1); }
    return no_fault();
}

fn write_ofx(statements: Statement[>..]&, entries: Entry[>..]&,
             notes: Note[>..]&, opts: OfxWriteOptions, lim: Limits&, out: u8[>..]&) -> Fault {
    var v = opts.version;
    if v == 0 { v = 102; }
    if !version_ok(v) { return fault(F_SYNTAX, 0, 0, "VERSION", "the OFX version is not known"); }
    let xml = v >= 200;
    let w = OfxForm { closed: xml || opts.close_leaves, indent: opts.indent };
    put_ofx_header(out, v);
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
    // The flag names every statement a credit card statement. Without
    // it, each statement goes by its own account kind. The bank set
    // comes before the credit card set, as the reference writer puts it.
    if statements.len > 0 {
        if opts.credit_card {
            let e = write_set(out, w, "CREDITCARDMSGSRSV1", statements, entries, notes, opts, lim);
            if e.kind != F_NONE { return e; }
        } else {
            let e = write_set(out, w, "BANKMSGSRSV1", statements, entries, notes, opts, lim);
            if e.kind != F_NONE { return e; }
            let e2 = write_set(out, w, "CREDITCARDMSGSRSV1", statements, entries, notes, opts, lim);
            if e2.kind != F_NONE { return e2; }
        }
    }
    close_tag(out, w, "OFX", 0);
    return check_size(out, lim);
}
