// The field readers of the camt documents.
//
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

struct CamtOptions {
    skip_balance_check: bool,
}

// CamtHeader holds the group header of a camt message. The kind is 1
// for a report, 2 for a statement and 3 for a notification. The
// entry count and the names stay text; the creation time is a typed
// date with the offset in minutes.
struct CamtHeader {
    kind: i32,
    message_id: const u8[:],
    has_creation: bool,
    creation: Date,
    creation_minutes: i32,
    creation_offset: i32,
    entry_count: const u8[:],
    additional_info: const u8[:],
    initiator: const u8[:],
    recipient: const u8[:],
    definition: const u8[:],
    service: const u8[:],
}

// camt_header reads the group header of the message into a record. A
// field that the message holds not stays empty.
fn camt_header(doc: xml::Doc&, kind: i32, app: i32, grp: i32, buf: u8[>..]&) -> CamtHeader {
    var h = CamtHeader {
        kind: kind, message_id: "", has_creation: false, creation: no_date(),
        creation_minutes: 0, creation_offset: 0, entry_count: "", additional_info: "",
        initiator: "", recipient: "", definition: "", service: "",
    };
    // The application header. It carries the same facts as the group
    // header under other names. A fact the group header held not is
    // taken from here.
    if app >= 0 {
        let d, hasd = c_text(doc, app, "MsgDefIdr", buf);
        if hasd { h.definition = d; }
        let sv, hass = c_text(doc, app, "BizSvc", buf);
        if hass { h.service = sv; }
    }
    // The application header fills what the group header held not.
    if app >= 0 {
        if h.message_id.len == 0 {
            let bid, has8 = c_text(doc, app, "BizMsgIdr", buf);
            if has8 { h.message_id = bid; }
        }
        if !h.has_creation {
            let cdt2, has9 = c_text(doc, app, "CreDt", buf);
            if has9 {
                let d2, mins, off, ok2 = camt_datetime(cdt2);
                if !ok2 {
                    let d3, ok3 = camt_date(cdt2);
                    if ok3 {
                        h.creation = d3;
                        h.has_creation = true;
                    }
                } else {
                    h.creation = d2;
                    h.creation_minutes = mins;
                    h.creation_offset = off;
                    h.has_creation = true;
                }
            }
        }
        if h.initiator.len == 0 { h.initiator = party_name(doc, app, "Fr", buf); }
        if h.recipient.len == 0 { h.recipient = party_name(doc, app, "To", buf); }
    }
    if grp < 0 { return h; }
    let mid, has = c_text(doc, grp, "MsgId", buf);
    if has { h.message_id = mid; }
    let cnt, has2 = c_text(doc, grp, "NbOfTxs", buf);
    if has2 { h.entry_count = cnt; }
    let inf, has3 = c_text(doc, grp, "AddtlInf", buf);
    if has3 { h.additional_info = inf; }
    let cdt, has4 = c_text(doc, grp, "CreDtTm", buf);
    if !has4 {
        let cd, has5 = c_text(doc, grp, "CreDt", buf);
        if has5 {
            let d, ok = camt_date(cd);
            if ok {
                h.creation = d;
                h.has_creation = true;
            }
        }
    }
    if has4 {
        let d, mins, off, ok = camt_datetime(cdt);
        if ok {
            h.creation = d;
            h.creation_minutes = mins;
            h.creation_offset = off;
            h.has_creation = true;
        }
    }
    let init = c_child(doc, grp, "InitgPty");
    if init >= 0 {
        let nm, has6 = c_text(doc, init, "Nm", buf);
        if has6 { h.initiator = nm; }
    }
    let rcpt = c_child(doc, grp, "MsgRcpt");
    if rcpt >= 0 {
        let nm, has7 = c_text(doc, rcpt, "Nm", buf);
        if has7 { h.recipient = nm; }
    }
    return h;
}

// party_name reads the name of a party of the application header. The
// party is a choice: a name, a financial institution, or a clearing
// system member. The name comes from Nm, or from the BIC, or from the
// member id.
fn party_name(doc: xml::Doc&, id: i32, local: const u8[:], buf: u8[>..]&) -> const u8[:] {
    let p = c_child(doc, id, local);
    if p < 0 { return ""; }
    let nm, has = c_text(doc, p, "Nm", buf);
    if has { return nm; }
    let fi = c_child(doc, p, "FIId");
    if fi < 0 {
        let mmb = c_child(doc, p, "ClrSysMmbId");
        if mmb < 0 { return ""; }
        let mid, has3 = c_text(doc, mmb, "MmbId", buf);
        if has3 { return mid; }
        return "";
    }
    let fin = c_child(doc, fi, "FinInstnId");
    if fin < 0 { return ""; }
    let bic, has2 = c_text(doc, fin, "BICFI", buf);
    if has2 { return bic; }
    let nm2, has4 = c_text(doc, fin, "Nm", buf);
    if has4 { return nm2; }
    return "";
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
