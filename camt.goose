// The camt reader of the bank_statement package.
//
// parse_camt reads a camt.052, camt.053 or camt.054 document of ISO 20022.
// The reader matches the element names after the namespace, so every
// schema version from .001.01 to .001.14 and every prefix parse.
//
// The text of the document goes into the buffer of the caller, and the
// fields of the results are spans over that buffer. The buffer must
// outlive the arrays.
//
// The reader builds on the goose-xml package. That package skips a
// doctype and never expands an entity, so no document can grow out of
// its own entities.
namespace bank_statement;

import std;
import fault;
import text;
import limits;
import amount;
import date;
import mt940;
import qif;
import xml;

// CamtOptions holds the options of the reader. The zero value is the safe
// one: the balance check runs.
struct CamtOptions {
    skip_balance_check: bool,
}

// c_child gives the first child element of the element with the local
// name. It gives -1 when the element has no such child.
fn c_child(doc: xml::Doc&, id: i32, local: const u8[:]) -> i32 {
    var c = doc.nodes[id].first_child;
    while c >= 0 {
        let n = doc.nodes[c];
        if n.kind == xml::KIND_ELEMENT && n.local == local { return c; }
        c = n.next_sibling;
    }
    return -1;
}

// c_trim gives the text without its blanks at both ends.
fn c_trim(s: const u8[:]) -> const u8[:] {
    var a: i64 = 0;
    var b = s.len;
    while a < b && (s[a] == ' ' || s[a] == '\t' || s[a] == '\n' || s[a] == '\r') { a += 1; }
    while b > a && (s[b - 1] == ' ' || s[b - 1] == '\t' || s[b - 1] == '\n' || s[b - 1] == '\r') { b -= 1; }
    return s[a..b];
}

// c_text writes the text of the child element with the local name into
// buf and gives the span of it. It gives false when the child is not
// there.
fn c_text(doc: xml::Doc&, id: i32, local: const u8[:], buf: u8[>..]&) -> const u8[:], bool {
    let c = c_child(doc, id, local);
    if c < 0 { return "", false; }
    let start = buf.len;
    xml::elem_text(buf, doc, c);
    return c_trim(buf[start..]), true;
}

// c_text_of writes the text of the element into buf and gives the span.
fn c_text_of(doc: xml::Doc&, id: i32, buf: u8[>..]&) -> const u8[:] {
    let start = buf.len;
    xml::elem_text(buf, doc, id);
    return c_trim(buf[start..]);
}

// camt_date reads a date of ISO form: YYYY-MM-DD.
fn camt_date(s: const u8[:]) -> Date, bool {
    if s.len < 10 { return no_date(), false; }
    if s[4] != '-' || s[7] != '-' { return no_date(), false; }
    let y, a = digits(s[0..4]);
    let m, b = digits(s[5..7]);
    let d, c = digits(s[8..10]);
    if !a || !b || !c { return no_date(), false; }
    return make_date(y, m, d);
}

// camt_datetime reads a date and time of ISO form:
// YYYY-MM-DDThh:mm:ss with an optional fraction and an optional zone.
// It gives the date, the minutes of the day and the offset in minutes.
fn camt_datetime(s: const u8[:]) -> Date, i32, i32, bool {
    if s.len < 19 { return no_date(), 0, 0, false; }
    if s[10] != 'T' && s[10] != ' ' { return no_date(), 0, 0, false; }
    let d, ok = camt_date(s[0..10]);
    if !ok { return no_date(), 0, 0, false; }
    let hh, a = digits(s[11..13]);
    let mm, b = digits(s[14..16]);
    let ss, c = digits(s[17..19]);
    if !a || !b || !c { return no_date(), 0, 0, false; }
    if s[13] != ':' || s[16] != ':' { return no_date(), 0, 0, false; }
    if hh > 23 || mm > 59 || ss > 60 { return no_date(), 0, 0, false; }
    var mins = (hh * 60 + mm) as i32;
    let _ = ss;
    // The zone: Z, +hh:mm, +hhmm or +hh.
    var p: i64 = 19;
    while p < s.len && (s[p] == '.' || is_digit(s[p])) { p += 1; }
    var off: i32 = 0;
    if p < s.len {
        let z = s[p];
        if z == 'Z' || z == 'z' {
            p += 1;
        } else if z == '+' || z == '-' {
            var sign: i32 = 1;
            if z == '-' { sign = -1; }
            let rest = s[p + 1..];
            var oh: i64 = 0;
            var om: i64 = 0;
            var ok2 = false;
            if rest.len >= 5 && rest[2] == ':' {
                let a2, x = digits(rest[0..2]);
                let b2, y = digits(rest[3..5]);
                oh = a2; om = b2; ok2 = x && y;
            } else if rest.len >= 4 {
                let a2, x = digits(rest[0..2]);
                let b2, y = digits(rest[2..4]);
                oh = a2; om = b2; ok2 = x && y;
            } else if rest.len >= 2 {
                let a2, x = digits(rest[0..2]);
                oh = a2; ok2 = x;
            }
            if !ok2 || oh > 23 || om > 59 { return no_date(), 0, 0, false; }
            off = sign * ((oh * 60 + om) as i32);
        } else {
            return no_date(), 0, 0, false;
        }
    }
    return d, mins, off, true;
}

// camt_amount reads the amount of an element: the child Amt with its Ccy
// attribute. The amount has no sign; the direction comes from the code of
// the element. A missing amount, a missing currency or a sign in the text
// is a fault.
fn camt_amount(doc: xml::Doc&, id: i32, tag: const u8[:], buf: u8[>..]&) -> Amount, Fault {
    let z = Amount { minor: 0, exp: 2, currency: "" };
    let a = c_child(doc, id, "Amt");
    if a < 0 { return z, fault(F_AMOUNT, 0, 0, tag, "the element has no amount"); }
    return camt_amount_of(doc, a, tag, buf);
}

// camt_amount_of reads an amount element: the text with the Ccy
// attribute.
fn camt_amount_of(doc: xml::Doc&, a: i32, tag: const u8[:], buf: u8[>..]&) -> Amount, Fault {
    let ccy, has = xml::attr_lookup(doc, doc.nodes[a], "Ccy");
    if !has || ccy.len != 3 { return Amount { minor: 0, exp: 2, currency: "" }, fault(F_AMOUNT, 0, 0, tag, "the amount has no currency"); }
    return camt_amount_ccy(doc, a, tag, ccy, buf);
}

// camt_amount_ccy reads an amount element with a known currency. The
// currency goes into the buffer of the caller, so the amount holds no
// span of the document.
fn camt_amount_ccy(doc: xml::Doc&, a: i32, tag: const u8[:], ccy: const u8[:], buf: u8[>..]&) -> Amount, Fault {
    let z = Amount { minor: 0, exp: 2, currency: "" };
    if ccy.len != 3 { return z, fault(F_AMOUNT, 0, 0, tag, "the amount has no currency"); }
    var tmp: u8[>..] = [];
    let text = c_text_of(doc, a, tmp);
    if text.len == 0 { return z, fault(F_AMOUNT, 0, 0, tag, "the amount is empty"); }
    if text[0] == '-' || text[0] == '+' { return z, fault(F_AMOUNT, 0, 0, tag, "the amount has a sign"); }
    let amount, f = parse_amount(text, currency_exponent(ccy), '.', 0);
    if f.kind != F_NONE { return z, with_pos(f, 0, tag); }
    // The currency code goes into the buffer of the caller, so the
    // amount holds no span of the document.
    let start = buf.len;
    for i in 0..ccy.len { buf.push(ccy[i]); }
    return Amount { minor: amount.minor, exp: amount.exp, currency: buf[start..] }, no_fault();
}

// camt_credit reads the credit or debit code of an element. It gives true
// for a credit. A missing or unknown code is a fault.
fn camt_credit(doc: xml::Doc&, id: i32, tag: const u8[:]) -> bool, Fault {
    let c = c_child(doc, id, "CdtDbtInd");
    if c < 0 { return false, fault(F_AMOUNT, 0, 0, tag, "the element has no credit or debit code"); }
    var tmp: u8[>..] = [];
    let v = c_text_of(doc, c, tmp);
    if v == "CRDT" { return true, no_fault(); }
    if v == "DBIT" { return false, no_fault(); }
    return false, fault(F_AMOUNT, 0, 0, tag, "the credit or debit code is not CRDT or DBIT");
}

// camt_code reads the code of a balance type: the Cd or the Prtry of the
// CdOrPrtry element.
fn camt_code(doc: xml::Doc&, id: i32, buf: u8[>..]&) -> const u8[:] {
    let tp = c_child(doc, id, "Tp");
    if tp < 0 { return ""; }
    let cp = c_child(doc, tp, "CdOrPrtry");
    if cp < 0 { return ""; }
    let cd = c_child(doc, cp, "Cd");
    if cd >= 0 { return c_text_of(doc, cd, buf); }
    let pr = c_child(doc, cp, "Prtry");
    if pr >= 0 { return c_text_of(doc, pr, buf); }
    return "";
}

// camt_kind gives the balance kind of a balance code.
fn camt_kind(code: const u8[:]) -> i32 {
    if code == "OPBD" { return BAL_OPENING; }
    if code == "CLBD" { return BAL_CLOSING; }
    if code == "OPAV" || code == "ITAV" || code == "CLAV" { return BAL_AVAILABLE; }
    if code == "FWAV" { return BAL_FORWARD; }
    return 0;
}

// camt_date_or_time reads a date of ISO form or a date and time of ISO
// form and gives the date.
fn camt_date_or_time(v: const u8[:]) -> Date, bool {
    let d, ok = camt_date(v);
    if ok { return d, true; }
    let d2, mins, off, ok2 = camt_datetime(v);
    if ok2 {
        let _ = mins;
        let _ = off;
        return d2, true;
    }
    return no_date(), false;
}

// camt_date_field reads the date of an element: the Dt or the DtTm of a
// date choice. The choice holds its own Dt or DtTm element.
fn camt_date_field(doc: xml::Doc&, id: i32) -> Date, bool {
    var tmp: u8[>..] = [];
    let c = c_child(doc, id, "Dt");
    if c >= 0 {
        let inner = c_child(doc, c, "Dt");
        if inner >= 0 { return camt_date_or_time(c_text_of(doc, inner, tmp)); }
        let inner2 = c_child(doc, c, "DtTm");
        if inner2 >= 0 { return camt_date_or_time(c_text_of(doc, inner2, tmp)); }
        return camt_date_or_time(c_text_of(doc, c, tmp));
    }
    let c2 = c_child(doc, id, "DtTm");
    if c2 >= 0 { return camt_date_or_time(c_text_of(doc, c2, tmp)); }
    return no_date(), false;
}

// camt_balance reads one Bal element.
fn camt_balance(doc: xml::Doc&, id: i32, lim: Limits&, balances: Balance[>..]&, buf: u8[>..]&) -> Fault {
    let tag: const u8[:] = "Bal";
    if balances.len >= lim.max_fields { return fault(F_LIMIT, 0, 0, tag, "more balances than max_fields"); }
    let code = camt_code(doc, id, buf);
    let a, af = camt_amount(doc, id, tag, buf);
    if af.kind != F_NONE { return af; }
    let credit, cf = camt_credit(doc, id, tag);
    if cf.kind != F_NONE { return cf; }
    let d, has_date = camt_date_field(doc, id);
    var b = Balance { kind: camt_kind(code), credit: credit, intermediate: code == "ITAV", date: d, amount: a, code: code };
    if !has_date { b.date = no_date(); }
    balances.push(b);
    return no_fault();
}

// camt_status reads the status of an entry: the text of the Sts element
// or the text of its Cd or Prtry child.
fn camt_status(doc: xml::Doc&, id: i32, buf: u8[>..]&) -> const u8[:] {
    let c = c_child(doc, id, "Sts");
    if c < 0 { return ""; }
    let v = c_text_of(doc, c, buf);
    if v.len > 0 { return v; }
    let cd = c_child(doc, c, "Cd");
    if cd >= 0 { return c_text_of(doc, cd, buf); }
    let pr = c_child(doc, c, "Prtry");
    if pr >= 0 { return c_text_of(doc, pr, buf); }
    return "";
}

// camt_tx_code reads the bank transaction code of an entry. The domain
// form gives the domain, the family and the sub family joined with
// slashes. The proprietary form gives the code.
fn camt_tx_code(doc: xml::Doc&, id: i32, buf: u8[>..]&) -> const u8[:] {
    let c = c_child(doc, id, "BkTxCd");
    if c < 0 { return ""; }
    let dom = c_child(doc, c, "Domn");
    if dom >= 0 {
        // The domain, the family and the sub family, joined with
        // slashes.
        var tmp: u8[>..] = [];
        let cd = c_child(doc, dom, "Cd");
        if cd >= 0 { c_text_of(doc, cd, tmp); }
        tmp.push('/');
        let fam = c_child(doc, dom, "Fmly");
        if fam >= 0 {
            let fc = c_child(doc, fam, "Cd");
            if fc >= 0 { c_text_of(doc, fc, tmp); }
            tmp.push('/');
            let sf = c_child(doc, fam, "SubFmlyCd");
            if sf >= 0 { c_text_of(doc, sf, tmp); }
        }
        let start = buf.len;
        for i in 0..tmp.len { buf.push(tmp[i]); }
        return buf[start..];
    }
    let pr = c_child(doc, c, "Prtry");
    if pr >= 0 {
        let cd = c_child(doc, pr, "Cd");
        if cd < 0 { return ""; }
        // A proprietary code gives the code and the issuer.
        let iss = c_child(doc, pr, "Issr");
        if iss < 0 { return c_text_of(doc, cd, buf); }
        var tmp: u8[>..] = [];
        c_text_of(doc, cd, tmp);
        tmp.push('/');
        c_text_of(doc, iss, tmp);
        let start = buf.len;
        for i in 0..tmp.len { buf.push(tmp[i]); }
        return buf[start..];
    }
    return "";
}

// camt_party reads the name and the IBAN of the debtor or the creditor of
// an entry. The name sits in Nm, in a Pty wrapper or in the element
// itself. The account element sits beside the party element.
fn camt_party(doc: xml::Doc&, id: i32, which: const u8[:], buf: u8[>..]&) -> const u8[:], const u8[:] {
    var acct_name: const u8[:] = "CdtrAcct";
    if which == "Dbtr" { acct_name = "DbtrAcct"; }
    let p = c_child(doc, id, which);
    if p < 0 { return "", camt_account_iban(doc, id, acct_name, buf); }
    let iban = camt_account_iban(doc, p, acct_name, buf);
    if iban.len > 0 { return camt_party_name(doc, p, buf), iban; }
    return camt_party_name(doc, p, buf), camt_account_iban(doc, id, acct_name, buf);
}

// camt_party_name reads the name of a party. The name sits in Nm, in a
// party wrapper or in the element itself.
fn camt_party_name(doc: xml::Doc&, id: i32, buf: u8[>..]&) -> const u8[:] {
    let nm = c_child(doc, id, "Nm");
    if nm >= 0 { return c_text_of(doc, nm, buf); }
    let pty = c_child(doc, id, "Pty");
    if pty >= 0 {
        let nm2 = c_child(doc, pty, "Nm");
        if nm2 >= 0 { return c_text_of(doc, nm2, buf); }
    }
    return "";
}

// camt_account_iban reads the IBAN of the account of a party.
fn camt_account_iban(doc: xml::Doc&, id: i32, acct_name: const u8[:], buf: u8[>..]&) -> const u8[:] {
    let acct = c_child(doc, id, acct_name);
    if acct < 0 { return ""; }
    let aid = c_child(doc, acct, "Id");
    if aid < 0 { return ""; }
    let ib = c_child(doc, aid, "IBAN");
    if ib < 0 { return ""; }
    return c_text_of(doc, ib, buf);
}

// camt_remittance reads the remittance text of an entry: the Ustrd lines
// of the entry and of its transaction details.
fn camt_remittance(doc: xml::Doc&, id: i32, buf: u8[>..]&) -> const u8[:] {
    let start = buf.len;
    var wrote = false;
    wrote = camt_ustrd(doc, id, buf, wrote);
    var det = doc.nodes[id].first_child;
    while det >= 0 {
        let n = doc.nodes[det];
        if n.kind == xml::KIND_ELEMENT && n.local == "NtryDtls" {
            var tx = n.first_child;
            while tx >= 0 {
                let t = doc.nodes[tx];
                if t.kind == xml::KIND_ELEMENT && t.local == "TxDtls" { wrote = camt_ustrd(doc, tx, buf, wrote); }
                tx = t.next_sibling;
            }
        }
        det = n.next_sibling;
    }
    return buf[start..];
}

// camt_ustrd writes the unstructured remittance lines of an element. It
// says whether it wrote a line.
fn camt_ustrd(doc: xml::Doc&, id: i32, buf: u8[>..]&, wrote: bool) -> bool {
    var has = wrote;
    var c = doc.nodes[id].first_child;
    while c >= 0 {
        let n = doc.nodes[c];
        if n.kind == xml::KIND_ELEMENT && n.local == "RmtInf" {
            var u = n.first_child;
            while u >= 0 {
                let un = doc.nodes[u];
                if un.kind == xml::KIND_ELEMENT && un.local == "Ustrd" {
                    if has { buf.push('\n'); }
                    c_text_of(doc, u, buf);
                    has = true;
                }
                u = un.next_sibling;
            }
        }
        c = n.next_sibling;
    }
    return has;
}

// camt_batch reads the batch block of an entry: the count of the
// transactions and the total of the amounts. The block sits in the
// entry, in the details or in the transaction details.
fn camt_batch(doc: xml::Doc&, id: i32, buf: u8[>..]&, e: Entry&) -> Fault {
    let b = c_child(doc, id, "Btch");
    if b < 0 { return no_fault(); }
    let mid, has_mid = c_text(doc, b, "MsgId", buf);
    if has_mid { e.batch_msg_id = mid; }
    let pid, has_pid = c_text(doc, b, "PmtInfId", buf);
    if has_pid { e.batch_pmt_id = pid; }
    let cnt, has = c_text(doc, b, "NbOfTxs", buf);
    if has { e.batch_count = cnt; }
    var tot = c_child(doc, b, "TtlNttryAmt");
    if tot < 0 { tot = c_child(doc, b, "TtlAmt"); }
    if tot >= 0 {
        let ta, tf = camt_amount_of(doc, tot, "Btch", buf);
        if tf.kind != F_NONE { return tf; }
        e.batch_total = ta;
        e.has_batch_total = true;
    }
    return no_fault();
}

// camt_entry reads one Ntry element.
fn camt_entry(doc: xml::Doc&, id: i32, lim: Limits&, entries: Entry[>..]&, buf: u8[>..]&) -> Fault {
    let tag: const u8[:] = "Ntry";
    if entries.len >= lim.max_entries { return fault(F_LIMIT, 0, 0, tag, "more entries than max_entries"); }
    let a, af = camt_amount(doc, id, tag, buf);
    if af.kind != F_NONE { return af; }
    let credit, cf = camt_credit(doc, id, tag);
    if cf.kind != F_NONE { return cf; }
    var e = Entry {
        value_date: no_date(), entry_date: no_date(), mark: "", funds_code: 0,
        amount: a, type_id: "", customer_ref: "", bank_ref: "", supplementary: "", narrative: "",
        status: "", entry_ref: "", counter_name: "", counter_iban: "", remittance: "",
        batch_count: "", batch_msg_id: "", batch_pmt_id: "",
        batch_total: Amount { minor: 0, exp: 2, currency: "" }, has_batch_total: false,
        units: Rational { num: 0, den: 1 }, has_units: false, units_text: "",
        unit_price: Rational { num: 0, den: 1 }, has_unit_price: false, unit_price_text: "",
        commission: Rational { num: 0, den: 1 }, has_commission: false, commission_text: "",
        total: Rational { num: 0, den: 1 }, has_total: false, total_text: "",
    };
    // A reversal of a credit is RC, a reversal of a debit is RD.
    if credit { e.mark = "C"; } else { e.mark = "D"; }
    let rvl = c_child(doc, id, "RvslInd");
    if rvl >= 0 {
        var b2: u8[>..] = [];
        let v = c_text_of(doc, rvl, b2);
        if v == "true" {
            if credit { e.mark = "RC"; } else { e.mark = "RD"; }
        }
    }
    // The dates.
    let vd = c_child(doc, id, "ValDt");
    if vd >= 0 {
        let d, ok = camt_date_field(doc, vd);
        if ok { e.value_date = d; }
    }
    let bd = c_child(doc, id, "BookgDt");
    if bd >= 0 {
        let d, ok = camt_date_field(doc, bd);
        if ok { e.entry_date = d; }
    }
    e.status = camt_status(doc, id, buf);
    // The references.
    let nref, has = c_text(doc, id, "NtryRef", buf);
    if has { e.entry_ref = nref; }
    let svcr, has2 = c_text(doc, id, "AcctSvcrRef", buf);
    if has2 { e.bank_ref = svcr; }
    let add, has3 = c_text(doc, id, "AddtlNtryInf", buf);
    if has3 { e.narrative = add; }
    e.type_id = camt_tx_code(doc, id, buf);
    // The counterparty and the remittance.
    var det = doc.nodes[id].first_child;
    while det >= 0 {
        let n = doc.nodes[det];
        if n.kind == xml::KIND_ELEMENT && n.local == "NtryDtls" {
            let bd = camt_batch(doc, det, buf, e);
            if bd.kind != F_NONE { return bd; }
            var tx = n.first_child;
            while tx >= 0 {
                let t = doc.nodes[tx];
                if t.kind == xml::KIND_ELEMENT && t.local == "TxDtls" {
                    let bf = camt_batch(doc, tx, buf, e);
                    if bf.kind != F_NONE { return bf; }
                    let refs = c_child(doc, tx, "Refs");
                    if refs >= 0 {
                        let e2e, has4 = c_text(doc, refs, "EndToEndId", buf);
                        if has4 && e.customer_ref.len == 0 { e.customer_ref = e2e; }
                    }
                    let parties = c_child(doc, tx, "RltdPties");
                    if parties >= 0 {
                        var which: const u8[:] = "Dbtr";
                        if !credit { which = "Cdtr"; }
                        let name, iban = camt_party(doc, parties, which, buf);
                        if e.counter_name.len == 0 { e.counter_name = name; }
                        if e.counter_iban.len == 0 { e.counter_iban = iban; }
                    }
                    let bf2 = camt_batch(doc, tx, buf, e);
                    if bf2.kind != F_NONE { return bf2; }
                }
                tx = t.next_sibling;
            }
        }
        det = n.next_sibling;
    }
    let bf3 = camt_batch(doc, id, buf, e);
    if bf3.kind != F_NONE { return bf3; }
    e.remittance = camt_remittance(doc, id, buf);
    entries.push(e);
    return no_fault();
}

// camt_account_ccy reads the currency of the account of a statement.
fn camt_account_ccy(doc: xml::Doc&, id: i32, buf: u8[>..]&) -> const u8[:] {
    let acct = c_child(doc, id, "Acct");
    if acct < 0 { return ""; }
    let cv, has = c_text(doc, acct, "Ccy", buf);
    if !has { return ""; }
    return cv;
}

// camt_summary reads the transaction summary of a statement: the counts
// and the sums of the debit and the credit entries. The summary of some
// banks holds one block for all the entries. The sum has no currency of
// its own, so the currency of the account gives it.
fn camt_summary(doc: xml::Doc&, id: i32, ccy: const u8[:], buf: u8[>..]&, statements: Statement[>..]&, cur: i64) -> Fault {
    let s = c_child(doc, id, "TxsSummry");
    if s < 0 { return no_fault(); }
    let tag: const u8[:] = "TxsSummry";
    // A summary that holds one block for all the entries gives the sum
    // of every entry without a sign. It has no place in the credit and
    // the debit totals, so the reader ignores it.
    let cdt = c_child(doc, s, "TtlCdtNtries");
    let dbt = c_child(doc, s, "TtlDbtNtries");
    if dbt >= 0 {
        let f = camt_sum_block(doc, dbt, "NbOfNtries", tag, ccy, buf, statements, cur, false);
        if f.kind != F_NONE { return f; }
    }
    if cdt >= 0 {
        let f = camt_sum_block(doc, cdt, "NbOfNtries", tag, ccy, buf, statements, cur, true);
        if f.kind != F_NONE { return f; }
    }
    return no_fault();
}

// camt_sum_block reads the count and the sum of one block of the
// transaction summary. The block gives the credit or the debit total.
fn camt_sum_block(doc: xml::Doc&, id: i32, cnt_name: const u8[:], tag: const u8[:], ccy: const u8[:],
                   buf: u8[>..]&, statements: Statement[>..]&, cur: i64, credit: bool) -> Fault {
    let cnt, has = c_text(doc, id, cnt_name, buf);
    if has {
        let n, ok = digits(cnt);
        if !ok { return fault(F_TOTAL, 0, 0, tag, "the number of entries in the summary is not a number"); }
        if credit { statements[cur].credit_count = n; } else { statements[cur].debit_count = n; }
    }
    var sum = c_child(doc, id, "Sum");
    if sum < 0 { sum = c_child(doc, id, "TtlNttryAmt"); }
    if sum < 0 { sum = c_child(doc, id, "TtlNetNtryAmt"); }
    if sum >= 0 {
        // The sum has a currency of its own, or it takes the currency
        // of the account.
        let attr, has_attr = xml::attr_lookup(doc, doc.nodes[sum], "Ccy");
        var a: Amount;
        var f: Fault;
        if has_attr && attr.len == 3 {
            a, f = camt_amount_of(doc, sum, tag, buf);
        } else {
            a, f = camt_amount_ccy(doc, sum, tag, ccy, buf);
        }
        if f.kind != F_NONE { return f; }
        if credit {
            statements[cur].credit_total = a;
            statements[cur].has_credit_total = true;
        } else {
            statements[cur].debit_total = a;
            statements[cur].has_debit_total = true;
        }
    }
    return no_fault();
}

// camt_statement reads one statement container.
fn camt_statement(doc: xml::Doc&, id: i32, kind: i32, grp: i32, lim: Limits&,
                  opts: CamtOptions&, statements: Statement[>..]&, entries: Entry[>..]&,
                  balances: Balance[>..]&, buf: u8[>..]&) -> Fault {
    if statements.len >= lim.max_statements { return fault(F_LIMIT, 0, 0, "", "more statements than max_statements"); }
    statements.push(new_statement());
    let cur = statements.len - 1;
    let v, has = c_text(doc, id, "Id", buf);
    if has { statements[cur].reference = v; }
    if grp >= 0 {
        let mid, has = c_text(doc, grp, "MsgId", buf);
        if has { statements[cur].related_ref = mid; }
    }
    // The account: the IBAN or the other id.
    let acct = c_child(doc, id, "Acct");
    if acct >= 0 {
        let aid = c_child(doc, acct, "Id");
        if aid >= 0 {
            let iban, has2 = c_text(doc, aid, "IBAN", buf);
            if has2 {
                statements[cur].account = iban;
            } else {
                let othr = c_child(doc, aid, "Othr");
                if othr >= 0 {
                    let oid, has3 = c_text(doc, othr, "Id", buf);
                    if has3 { statements[cur].account = oid; }
                }
            }
        }
    }
    // The currency of the account gives the currency of the summary.
    let ccy = camt_account_ccy(doc, id, buf);
    let num, has4 = c_text(doc, id, "ElctrncSeqNb", buf);
    if has4 { statements[cur].number = num; }
    let seq, has5 = c_text(doc, id, "LglSeqNb", buf);
    if has5 { statements[cur].sequence = seq; }
    // The creation date and time of the statement.
    let cdt, has6 = c_text(doc, id, "CreDtTm", buf);
    if has6 {
        let d, mins, off, ok = camt_datetime(cdt);
        if !ok { return fault(F_DATE, 0, 0, "CreDtTm", "the creation date and time is not ISO form"); }
        statements[cur].report_date = d;
        statements[cur].report_minutes = mins;
        statements[cur].report_offset = off;
        statements[cur].has_report_time = true;
    }
    // A report and a notification are interim statements.
    if kind != 2 { statements[cur].is_interim = true; }
    // The balances.
    let bal_start = balances.len;
    var b = doc.nodes[id].first_child;
    while b >= 0 {
        let n = doc.nodes[b];
        if n.kind == xml::KIND_ELEMENT && n.local == "Bal" {
            let f = camt_balance(doc, b, lim, balances, buf);
            if f.kind != F_NONE { return f; }
            let last = balances.len - 1;
            // The typed fields take the OPBD, the CLBD, the CLAV and
            // the FWAV balance. A second balance of the same kind
            // replaces the first.
            if balances[last].kind == BAL_OPENING { statements[cur].opening = balances[last]; }
            else if balances[last].kind == BAL_CLOSING { statements[cur].closing = balances[last]; }
            else if balances[last].kind == BAL_AVAILABLE && balances[last].code == "CLAV" { statements[cur].available = balances[last]; }
            else if balances[last].kind == BAL_FORWARD { statements[cur].forward = balances[last]; }
        }
        b = n.next_sibling;
    }
    statements[cur].balance_start = bal_start as i32;
    statements[cur].balance_count = (balances.len - bal_start) as i32;
    // The entries.
    let ent_start = entries.len;
    var e = doc.nodes[id].first_child;
    while e >= 0 {
        let n = doc.nodes[e];
        if n.kind == xml::KIND_ELEMENT && n.local == "Ntry" {
            let f = camt_entry(doc, e, lim, entries, buf);
            if f.kind != F_NONE { return f; }
        }
        e = n.next_sibling;
    }
    statements[cur].entry_start = ent_start as i32;
    statements[cur].entry_count = (entries.len - ent_start) as i32;
    // The transaction summary.
    let f = camt_summary(doc, id, ccy, buf, statements, cur);
    if f.kind != F_NONE { return f; }
    // The checks.
    return camt_checks(statements[cur], entries, opts, statements, cur);
}

// camt_checks runs the balance check and the total check of a camt
// statement. The balance check counts the booked entries only.
fn camt_checks(st: Statement&, entries: Entry[>..]&, opts: CamtOptions&, statements: Statement[>..]&, cur: i64) -> Fault {
    if !st.is_interim {
        // A statement without both booked balances has no check.
        if !opts.skip_balance_check && st.opening.kind != 0 && st.closing.kind != 0 {
            var sum = st.opening.amount.minor * bal_sign(st.opening);
            var k = 0;
            while k < st.entry_count {
                let e = entries[st.entry_start + k];
                if e.status == "BOOK" {
                    let step, ok = add_checked(sum, e.amount.minor * signed_effect(e.mark));
                    if !ok { return fault(F_OVERFLOW, 0, 1, "Ntry", "sum of entries does not fit in 64 bits"); }
                    sum = step;
                }
                k += 1;
            }
            let want = st.closing.amount.minor * bal_sign(st.closing);
            if sum != want {
                return fault_sums(F_BALANCE, 0, "Bal", "opening balance plus entries differs from the closing balance", sum, want);
            }
            statements[cur].balance_checked = true;
        }
    }
    return check_totals(st, entries, 0, "TxsSummry", "TxsSummry");
}

// parse_camt reads a camt document into the arrays of the caller.
fn parse_camt(input: const u8[:], lim: Limits&, opts: CamtOptions&,
              statements: Statement[>..]&, entries: Entry[>..]&, balances: Balance[>..]&,
              buf: u8[>..]&) -> Fault {
    let fi = check_input(input, lim);
    if fi.kind != F_NONE { return fi; }
    var nodes: xml::Node[>..] = [];
    var attrs: xml::Attr[>..] = [];
    let doc, ok = xml::parse(input, nodes, attrs);
    if !ok { return fault(F_SYNTAX, 0, 0, "", "the document is not well formed XML"); }
    if doc.root < 0 { return fault(F_SYNTAX, 0, 0, "", "the document has no root element"); }
    let root = doc.nodes[doc.root];
    if root.local != "Document" { return fault(F_SYNTAX, 0, 0, root.local, "the root element is not a camt document"); }
    // The message: a report, a statement or a notification.
    var msg = c_child(doc, doc.root, "BkToCstmrAcctRpt");
    var kind: i32 = 1;
    if msg < 0 { msg = c_child(doc, doc.root, "BkToCstmrStmt"); kind = 2; }
    if msg < 0 { msg = c_child(doc, doc.root, "BkToCstmrDbtCdtNtfctn"); kind = 3; }
    if msg < 0 { return fault(F_SYNTAX, 0, 0, "Document", "the document has no camt message"); }
    // The group header holds the message id.
    let grp = c_child(doc, msg, "GrpHdr");
    // The name of the statement container of the message.
    var container: const u8[:] = "Rpt";
    if kind == 2 { container = "Stmt"; }
    if kind == 3 { container = "Ntfctn"; }
    var found: i64 = 0;
    var c = doc.nodes[msg].first_child;
    while c >= 0 {
        let n = doc.nodes[c];
        if n.kind == xml::KIND_ELEMENT && n.local == container {
            let f = camt_statement(doc, c, kind, grp, lim, opts, statements, entries, balances, buf);
            if f.kind != F_NONE { return f; }
            found += 1;
        }
        c = n.next_sibling;
    }
    if found == 0 { return fault(F_SYNTAX, 0, 0, "Document", "the document has no camt statement"); }
    return no_fault();
}
