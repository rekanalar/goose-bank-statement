// The investment parts of the OFX parser.
//
namespace bank_statement;

import std;
import fault;
import text;
import limits;
import amount;
import currency;
import date;
import qif;
import mt940;
import sgml;

// ofx_image reads one IMAGEDATA aggregate.
fn ofx_image(nodes: SgmlNode[>..]&, first: i32, buf: u8[>..]&) -> OfxImage, Fault {
    var im = no_image();
    im.kind = child_text(nodes, first, "IMAGETYPE", buf);
    im.ref = child_text(nodes, first, "IMAGEREF", buf);
    im.ref_kind = child_text(nodes, first, "IMAGEREFTYPE", buf);
    im.check_sup = child_text(nodes, first, "CHECKSUP", buf);
    let dl = child_text(nodes, first, "IMAGEDELAY", buf);
    if dl.len > 0 {
        let n, ok = digits(dl);
        if !ok { return im, fault(F_SYNTAX, 0, 0, "IMAGEDELAY", "the delay is not a number of 1 to 9 digits"); }
        im.delay = n;
        im.has_delay = true;
    }
    let tl = child_text(nodes, first, "IMAGETTL", buf);
    if tl.len > 0 {
        let n, ok = digits(tl);
        if !ok { return im, fault(F_SYNTAX, 0, 0, "IMAGETTL", "the time to live is not a number of 1 to 9 digits"); }
        im.ttl = n;
        im.has_ttl = true;
    }
    let da = sgml_child(nodes, first, "DTIMAGEAVAIL");
    if da >= 0 {
        let d, ok = ofx_date(sgml_text_of(nodes, da, buf));
        if !ok { return im, fault(F_DATE, 0, 0, "DTIMAGEAVAIL", "the date is not OFX form"); }
        im.avail = d;
    }
    if !in_list(IMAGE_KINDS, im.kind) || !in_list(IMAGE_REF_KINDS, im.ref_kind) {
        return im, fault(F_SYNTAX, 0, 0, "IMAGEDATA", "the image type or reference type is not known");
    }
    if im.check_sup.len > 0 && !in_list(CHECK_SUPS, im.check_sup) {
        return im, fault(F_SYNTAX, 0, 0, "CHECKSUP", "the check side is not known");
    }
    if im.has_delay && im.avail.year != 0 {
        return im, fault(F_SYNTAX, 0, 0, "IMAGEDATA", "the image holds IMAGEDELAY and DTIMAGEAVAIL together");
    }
    return im, no_fault();
}

// ofx_trnamt reads TRNAMT. A CURRENCY aggregate gives the currency of
// the amount; else the statement gives it.
fn ofx_trnamt(nodes: SgmlNode[>..]&, amt: i32, x: OfxEntry, ccy: const u8[:], buf: u8[>..]&) -> Amount, Fault {
    if x.rate_kind == 'C' { return ofx_amount_of(nodes, amt, "STMTTRN", x.rate_symbol, buf); }
    return ofx_amount_of(nodes, amt, "STMTTRN", ccy, buf);
}

// ofx_stmttrn reads one STMTTRN into an entry. The sign of TRNAMT is
// the mark: a debit is negative.
fn ofx_stmttrn(nodes: SgmlNode[>..]&, id: i32, ccy: const u8[:], lim: Limits&,
               entries: Entry[>..]&, buf: u8[>..]&, cur: i64) -> Fault {
    let tag: const u8[:] = "STMTTRN";
    if entries.len >= lim.max_entries { return fault(F_LIMIT, 0, 0, tag, "more entries than max_entries"); }
    var e = new_entry(ccy);
    // The amount and the mark.
    let amt = sgml_child(nodes, id, "TRNAMT");
    if amt < 0 { return fault(F_AMOUNT, 0, 0, tag, "the entry has no amount"); }
    let x, xf = ofx_extras(nodes, id, buf);
    if xf.kind != F_NONE { return xf; }
    let a, af = ofx_trnamt(nodes, amt, x, ccy, buf);
    if af.kind != F_NONE { return af; }
    e.amount = a;
    e.ofx = x;
    if a.minor < 0 { e.mark = "D"; } else { e.mark = "C"; }
    // The dates.
    let dp = sgml_child(nodes, id, "DTPOSTED");
    if dp >= 0 {
        let v = sgml_text_of(nodes, dp, buf);
        let d, ok = ofx_date(v);
        if !ok { return fault(F_DATE, 0, 0, "DTPOSTED", "the date is not OFX form"); }
        e.value_date = d;
    }
    let da = sgml_child(nodes, id, "DTAVAIL");
    if da >= 0 {
        let v = sgml_text_of(nodes, da, buf);
        let d, ok = ofx_date(v);
        if ok { e.entry_date = d; }
    }
    // The references.
    let fit = sgml_child(nodes, id, "FITID");
    if fit >= 0 { e.entry_ref = sgml_text_of(nodes, fit, buf); }
    let srv = sgml_child(nodes, id, "SRVRTID");
    if srv >= 0 { e.bank_ref = sgml_text_of(nodes, srv, buf); }
    let chk = sgml_child(nodes, id, "CHECKNUM");
    if chk >= 0 { e.customer_ref = sgml_text_of(nodes, chk, buf); }
    let refn = sgml_child(nodes, id, "REFNUM");
    if refn >= 0 { e.supplementary = sgml_text_of(nodes, refn, buf); }
    // The type.
    let ty = sgml_child(nodes, id, "TRNTYPE");
    if ty >= 0 { e.type_id = sgml_text_of(nodes, ty, buf); }
    // The counterparty: NAME or PAYEE, never both.
    let name = sgml_child(nodes, id, "NAME");
    let payee = sgml_child(nodes, id, "PAYEE");
    if name >= 0 && payee >= 0 {
        return fault(F_SYNTAX, 0, 0, tag, "the entry holds NAME and PAYEE together");
    }
    if name >= 0 {
        e.counter_name = sgml_text_of(nodes, name, buf);
    } else if payee >= 0 {
        let pn = sgml_child(nodes, payee, "NAME");
        if pn >= 0 { e.counter_name = sgml_text_of(nodes, pn, buf); }
    }
    // The memo.
    let memo = sgml_child(nodes, id, "MEMO");
    if memo >= 0 { e.narrative = sgml_text_of(nodes, memo, buf); }
    entries.push(e);
    return no_fault();
}

// ofx_bal reads one balance element into the balance array.
fn ofx_bal(nodes: SgmlNode[>..]&, id: i32, kind: i32, code: const u8[:], ccy: const u8[:],
           lim: Limits&, statements: Statement[>..]&, balances: Balance[>..]&,
           buf: u8[>..]&, cur: i64) -> Fault {
    if balances.len >= lim.max_fields { return fault(F_LIMIT, 0, 0, code, "more balances than max_fields"); }
    let amt = sgml_child(nodes, id, "BALAMT");
    if amt < 0 { return fault(F_AMOUNT, 0, 0, code, "the balance has no amount"); }
    let a, af = ofx_amount_of(nodes, amt, code, ccy, buf);
    if af.kind != F_NONE { return af; }
    var b = no_balance();
    b.kind = kind;
    b.credit = a.minor >= 0;
    b.amount = a;
    b.code = code;
    let dt = sgml_child(nodes, id, "DTASOF");
    if dt >= 0 {
        let v = sgml_text_of(nodes, dt, buf);
        let d, ok = ofx_date(v);
        if ok { b.date = d; }
    }
    balances.push(b);
    if kind == BAL_CLOSING { statements[cur].closing = b; }
    else if kind == BAL_AVAILABLE { statements[cur].available = b; }
    return no_fault();
}
// new_entry gives an entry with the defaults of the OFX reader.
fn new_entry(cur: const u8[:]) -> Entry {
    let r = Rational { num: 0, den: 1 };
    return Entry {
        value_date: no_date(), entry_date: no_date(), mark: "", funds_code: 0,
        amount: Amount { minor: 0, exp: 2, currency: cur },
        type_id: "", customer_ref: "", bank_ref: "", supplementary: "", narrative: "",
        status: "", entry_ref: "", counter_name: "", counter_iban: "", remittance: "",
        batch_count: "", batch_msg_id: "", batch_pmt_id: "",
        batch_total: Amount { minor: 0, exp: 2, currency: "" }, has_batch_total: false,
        units: r, has_units: false, units_text: "",
        unit_price: r, has_unit_price: false, unit_price_text: "",
        commission: r, has_commission: false, commission_text: "",
        total: r, has_total: false, total_text: "", ofx: no_ofx(),
    };
}

// ofx_invest reads the investment transactions and the positions.
fn ofx_invest(nodes: SgmlNode[>..]&, id: i32, ccy: const u8[:], lim: Limits&,
              entries: Entry[>..]&, balances: Balance[>..]&, buf: u8[>..]&, cur: i64) -> Fault {
    // The names go into the buffer, so the entries hold no span of
    // the node array.
    let tl = sgml_child(nodes, id, "INVTRANLIST");
    if tl >= 0 {
        var c = first_child(nodes, tl);
        while c >= 0 {
            let start = buf.len;
            for u in nodes[c].name { buf.push(u); }
            let name = buf[start..];
            // An unknown transaction aggregate is ignored.
            if is_invtran(name) {
                let f = ofx_invtran(nodes, c, name, ccy, lim, entries, buf, cur);
                if f.kind != F_NONE { return f; }
            }
            c = sgml_next(nodes, c);
        }
    }
    let pl = sgml_child(nodes, id, "INVPOSLIST");
    if pl >= 0 {
        var c = first_child(nodes, pl);
        while c >= 0 {
            let start = buf.len;
            for u in nodes[c].name { buf.push(u); }
            let name = buf[start..];
            if is_pos(name) {
                let f = ofx_pos(nodes, c, name, ccy, lim, entries, balances, buf, cur);
                if f.kind != F_NONE { return f; }
            }
            c = sgml_next(nodes, c);
        }
    }
    return no_fault();
}
