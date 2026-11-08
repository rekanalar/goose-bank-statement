// The OFX reader of the bank_statement package.
//
// parse_ofx reads an OFX 1.x or OFX 2.x file: the header, the tag tree
// and the statement message sets. The bank and credit card statements
// and the investment statements come back as the shared Statement and
// Entry values. The signon status comes back as a note.
//
// The amounts are exact integer counts of minor units. A comma is a
// decimal separator only when the text holds no dot. A date of the
// form YYYYMMDD[HHMMSS[.XXX]][[+H.MM[:TZ]]] parses with the minutes
// reading of the dotted offset: [-5.30] is 5 hours 30 minutes, as
// ofxtools and the real bank files read it. No zone means GMT.
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

// OfxOptions holds the options of the reader. The zero value is the
// safe one: the pending list is read.
struct OfxOptions {
    skip_pending: bool,
    check_country: bool,
}

// parse_ofx reads one OFX file into the arrays of the caller. The
// buffer of the caller holds the text that the arrays point at.
fn parse_ofx(input: const u8[:], lim: Limits&, opts: OfxOptions&,
             statements: Statement[>..]&, entries: Entry[>..]&,
             balances: Balance[>..]&, notes: Note[>..]&, buf: u8[>..]&) -> Fault {
    let fi = check_input(input, lim);
    if fi.kind != F_NONE { return fi; }
    let h, body, hf = parse_sgml_header(input);
    if hf.kind != F_NONE { return hf; }
    var nodes: SgmlNode[>..] = [];
    let bf = parse_sgml_body(input, body, lim, nodes, buf);
    if bf.kind != F_NONE { return bf; }
    if nodes.len == 0 || nodes[0].depth != 0 || !ieq(nodes[0].name, "OFX") {
        // The name goes into the buffer, so the fault holds no span
        // of the node array.
        let start = buf.len;
        if nodes.len > 0 { for u in nodes[0].name { buf.push(u); } }
        return fault(F_SYNTAX, 0, 0, buf[start..], "the root element is not OFX");
    }
    let _ = h;
    // The message sets, in document order.
    var c = first_child(nodes, 0);
    while c >= 0 {
        let n = nodes[c];
        if ieq(n.name, "SIGNONMSGSRSV1") {
            let f = ofx_signon(nodes, c, notes, buf);
            if f.kind != F_NONE { return f; }
        } else if ieq(n.name, "BANKMSGSRSV1") {
            let f = ofx_set(nodes, c, "STMTTRNRS", "STMTRS", lim, opts, statements, entries, balances, notes, buf, false);
            if f.kind != F_NONE { return f; }
        } else if ieq(n.name, "CREDITCARDMSGSRSV1") {
            let f = ofx_set(nodes, c, "CCSTMTTRNRS", "CCSTMTRS", lim, opts, statements, entries, balances, notes, buf, false);
            if f.kind != F_NONE { return f; }
        } else if ieq(n.name, "INVSTMTMSGSRSV1") {
            let f = ofx_set(nodes, c, "INVSTMTTRNRS", "INVSTMTRS", lim, opts, statements, entries, balances, notes, buf, true);
            if f.kind != F_NONE { return f; }
        }
        // An unknown message set is skipped.
        c = sgml_next(nodes, c);
    }
    if opts.check_country {
        for e in entries {
            if e.ofx.has_payee && e.ofx.payee.country.len > 0 && !country_known(e.ofx.payee.country) {
                return fault(F_SYNTAX, 0, 0, "COUNTRY", "the country is not an ISO 3166 alpha-3 code");
            }
        }
    }
    return no_fault();
}

// first_child gives the first child element of a node.
fn first_child(nodes: SgmlNode[>..]&, id: i32) -> i32 {
    let d = nodes[id].depth;
    if id + 1 >= nodes.len { return -1; }
    if nodes[id + 1].depth > d { return id + 1; }
    return -1;
}

// ofx_signon reads the signon response. The status comes back as a
// note. The read never stops on a status of severity ERROR.
fn ofx_signon(nodes: SgmlNode[>..]&, id: i32, notes: Note[>..]&, buf: u8[>..]&) -> Fault {
    let sonrs = sgml_child(nodes, id, "SONRS");
    if sonrs < 0 { return no_fault(); }
    let st = sgml_child(nodes, sonrs, "STATUS");
    if st < 0 { return no_fault(); }
    let start = buf.len;
    let code = sgml_child(nodes, st, "CODE");
    if code >= 0 { sgml_text_of(nodes, code, buf); }
    buf.push('/');
    let sev = sgml_child(nodes, st, "SEVERITY");
    if sev >= 0 { sgml_text_of(nodes, sev, buf); }
    let msg = sgml_child(nodes, st, "MESSAGE");
    if msg >= 0 {
        buf.push(' ');
        sgml_text_of(nodes, msg, buf);
    }
    notes.push(Note { tag: "SONRS", value: buf[start..] });
    return no_fault();
}
// ofx_set reads one message set: the transaction wrappers, then one
// statement each. An unknown wrapper is skipped.
fn ofx_set(nodes: SgmlNode[>..]&, id: i32, wrap: const u8[:], stmt: const u8[:],
           lim: Limits&, opts: OfxOptions&, statements: Statement[>..]&,
           entries: Entry[>..]&, balances: Balance[>..]&, notes: Note[>..]&,
           buf: u8[>..]&, invest: bool) -> Fault {
    var c = first_child(nodes, id);
    while c >= 0 {
        if ieq(nodes[c].name, wrap) {
            if statements.len >= lim.max_statements {
                return fault(F_LIMIT, 0, 0, wrap, "more statements than max_statements");
            }
            let s = sgml_child(nodes, c, stmt);
            if s >= 0 {
                let f = ofx_statement(nodes, s, wrap, lim, opts, statements, entries, balances, notes, buf, invest);
                if f.kind != F_NONE { return f; }
            }
        }
        c = sgml_next(nodes, c);
    }
    return no_fault();
}

// ofx_statement reads one STMTRS, CCSTMTRS or INVSTMTRS.
fn ofx_statement(nodes: SgmlNode[>..]&, id: i32, wrap: const u8[:], lim: Limits&,
                 opts: OfxOptions&, statements: Statement[>..]&, entries: Entry[>..]&,
                 balances: Balance[>..]&, notes: Note[>..]&, buf: u8[>..]&, invest: bool) -> Fault {
    statements.push(new_statement());
    let cur = statements.len - 1;
    let ent_start = entries.len;
    let bal_start = balances.len;
    let note_start = notes.len;
    // The currency of the statement.
    let curdef = sgml_child(nodes, id, "CURDEF");
    // The currency goes into the buffer, so no span of the tree
    // stays on the statement.
    let ccy = ofx_currency(nodes, id, buf);
    if ccy.len != 3 {
        return fault(F_AMOUNT, 0, 0, "CURDEF", "the currency is not a known code");
    }
    // The account.
    if invest {
        let acct = sgml_child(nodes, id, "INVACCTFROM");
        if acct >= 0 {
            let start = buf.len;
            let br = sgml_child(nodes, acct, "BROKERID");
            if br >= 0 { sgml_text_of(nodes, br, buf); }
            buf.push(':');
            let ai = sgml_child(nodes, acct, "ACCTID");
            if ai >= 0 { sgml_text_of(nodes, ai, buf); }
            statements[cur].account = buf[start..];
        }
        let dt = sgml_child(nodes, id, "DTASOF");
        if dt >= 0 {
            let v = sgml_text_of(nodes, dt, buf);
            let d, mins, off, ok = ofx_datetime(v);
            if !ok { return fault(F_DATE, 0, 0, "DTASOF", "the date is not OFX form"); }
            let _ = mins;
            let _ = off;
            statements[cur].report_date = d;
        }
    } else {
        let acct = sgml_child(nodes, id, "BANKACCTFROM");
        if acct >= 0 {
            let ai = sgml_child(nodes, acct, "ACCTID");
            if ai >= 0 { statements[cur].account = sgml_text_of(nodes, ai, buf); }
            let bi = sgml_child(nodes, acct, "BANKID");
            if bi >= 0 {
                let v = sgml_text_of(nodes, bi, buf);
                notes.push(Note { tag: "BANKID", value: v });
            }
            let ty = sgml_child(nodes, acct, "ACCTTYPE");
            if ty >= 0 {
                let v = sgml_text_of(nodes, ty, buf);
                notes.push(Note { tag: "ACCTTYPE", value: v });
            }
        } else {
            let acct = sgml_child(nodes, id, "CCACCTFROM");
            if acct >= 0 {
                let ai = sgml_child(nodes, acct, "ACCTID");
                if ai >= 0 { statements[cur].account = sgml_text_of(nodes, ai, buf); }
            }
        }
    }
    // The reference of the transaction wrapper.
    let trn = sgml_child(nodes, parent_of(nodes, id), "TRNUID");
    if trn >= 0 { statements[cur].reference = sgml_text_of(nodes, trn, buf); }
    // The entries and the balances.
    if invest {
        let f = ofx_invest(nodes, id, ccy, lim, entries, balances, buf, cur);
        if f.kind != F_NONE { return f; }
    } else {
        let f = ofx_bank(nodes, id, ccy, lim, opts, statements, entries, balances, buf, cur);
        if f.kind != F_NONE { return f; }
    }
    statements[cur].entry_start = ent_start as i32;
    statements[cur].entry_count = (entries.len - ent_start) as i32;
    statements[cur].balance_start = bal_start as i32;
    statements[cur].balance_count = (balances.len - bal_start) as i32;
    statements[cur].note_start = note_start as i32;
    statements[cur].note_count = (notes.len - note_start) as i32;
    let _ = wrap;
    return no_fault();
}

// ofx_currency reads the CURDEF of a statement into the buffer. An
// empty text means the statement has none.
fn ofx_currency(nodes: SgmlNode[>..]&, id: i32, buf: u8[>..]&) -> const u8[:] {
    let curdef = sgml_child(nodes, id, "CURDEF");
    if curdef < 0 { return ""; }
    let v = sgml_text_of(nodes, curdef, buf);
    if v.len != 3 || currency_index(v) < 0 || ieq(v, "XXX") {
        return "";
    }
    return v;
}

// parent_of gives the parent index of a node.
fn parent_of(nodes: SgmlNode[>..]&, id: i32) -> i32 {
    return nodes[id].parent;
}
// ofx_bank reads the entries and the balances of a bank or credit card
// statement.
fn ofx_bank(nodes: SgmlNode[>..]&, id: i32, ccy: const u8[:], lim: Limits&,
            opts: OfxOptions&, statements: Statement[>..]&, entries: Entry[>..]&,
            balances: Balance[>..]&, buf: u8[>..]&, cur: i64) -> Fault {
    // The transaction lists: the booked list and the pending list.
    var list = sgml_child(nodes, id, "BANKTRANLIST");
    if list >= 0 {
        let f = ofx_tranlist(nodes, list, ccy, lim, entries, buf, cur);
        if f.kind != F_NONE { return f; }
        let ds = sgml_child(nodes, list, "DTSTART");
        if ds >= 0 {
            let v = sgml_text_of(nodes, ds, buf);
            let d, mins, off, ok = ofx_datetime(v);
            if ok {
                let _ = mins;
                let _ = off;
                statements[cur].report_date = d;
            }
        }
    }
    if !opts.skip_pending {
        list = sgml_child(nodes, id, "BANKTRANLISTP");
        if list >= 0 {
            let f = ofx_tranlist(nodes, list, ccy, lim, entries, buf, cur);
            if f.kind != F_NONE { return f; }
        }
    }
    // The ledger balance and the available balance.
    let led = sgml_child(nodes, id, "LEDGERBAL");
    if led >= 0 {
        let f = ofx_bal(nodes, led, BAL_CLOSING, "LEDGERBAL", ccy, lim, statements, balances, buf, cur);
        if f.kind != F_NONE { return f; }
    }
    let av = sgml_child(nodes, id, "AVAILBAL");
    if av >= 0 {
        let f = ofx_bal(nodes, av, BAL_AVAILABLE, "AVAILBAL", ccy, lim, statements, balances, buf, cur);
        if f.kind != F_NONE { return f; }
    }
    // The balance list: every balance keeps kind 0 and its type text.
    let ballist = sgml_child(nodes, id, "BALLIST");
    if ballist >= 0 {
        var b = first_child(nodes, ballist);
        while b >= 0 {
            if ieq(nodes[b].name, "BAL") {
                // The type text goes into the buffer. The code
                // binding happens once, so the root does not change.
                let ty = sgml_child(nodes, b, "BALTYPE");
                if ty >= 0 {
                    let cstart = buf.len;
                    let v = sgml_text_of(nodes, ty, buf);
                    if v.len > 0 {
                        let f = ofx_bal(nodes, b, 0, buf[cstart..], ccy, lim, statements, balances, buf, cur);
                        if f.kind != F_NONE { return f; }
                        b = sgml_next(nodes, b);
                        continue;
                    }
                }
                let f = ofx_bal(nodes, b, 0, "BAL", ccy, lim, statements, balances, buf, cur);
                if f.kind != F_NONE { return f; }
            }
            b = sgml_next(nodes, b);
        }
    }
    return no_fault();
}

// ofx_tranlist reads the STMTTRN entries of one transaction list.
fn ofx_tranlist(nodes: SgmlNode[>..]&, id: i32, ccy: const u8[:], lim: Limits&,
                entries: Entry[>..]&, buf: u8[>..]&, cur: i64) -> Fault {
    var c = first_child(nodes, id);
    while c >= 0 {
        if ieq(nodes[c].name, "STMTTRN") {
            let f = ofx_stmttrn(nodes, c, ccy, lim, entries, buf, cur);
            if f.kind != F_NONE { return f; }
        }
        c = sgml_next(nodes, c);
    }
    return no_fault();
}

// The enums of the transaction fields.
const INV401K: const u8[:][] = ["PRETAX", "AFTERTAX", "MATCH", "PROFITSHARING", "ROLLOVER", "OTHERVEST", "OTHERNONVEST"];
const IMAGE_KINDS: const u8[:][] = ["STATEMENT", "TRANSACTION", "TAX"];
const IMAGE_REF_KINDS: const u8[:][] = ["OPAQUE", "URL", "FORMURL"];
const CHECK_SUPS: const u8[:][] = ["FRONTONLY", "BACKONLY", "FRONTANDBACK"];

// child_text gives the text of the named child, or an empty text.
fn child_text(nodes: SgmlNode[>..]&, id: i32, name: const u8[:], buf: u8[>..]&) -> const u8[:] {
    let c = sgml_child(nodes, id, name);
    if c < 0 { return ""; }
    return sgml_text_of(nodes, c, buf);
}

// ofx_rate reads a CURRENCY or ORIGCURRENCY aggregate into x.
fn ofx_rate(nodes: SgmlNode[>..]&, agg: i32, kind: u8, buf: u8[>..]&, x: OfxEntry) -> OfxEntry, Fault {
    var out = x;
    let tag: const u8[:] = "CURRATE";
    let text = child_text(nodes, agg, "CURRATE", buf);
    let sym = child_text(nodes, agg, "CURSYM", buf);
    if text.len == 0 { return out, fault(F_AMOUNT, 0, 0, tag, "the rate is missing"); }
    let r, rf = ofx_ratio(text);
    if rf.kind != F_NONE { return out, with_pos(rf, 0, tag); }
    if r.num == 0 { return out, fault(F_AMOUNT, 0, 0, tag, "the rate is zero"); }
    if sym.len != 3 || currency_index(sym) < 0 {
        return out, fault(F_AMOUNT, 0, 0, "CURSYM", "the currency is not a known code");
    }
    out.rate_kind = kind;
    out.rate = r;
    out.rate_text = text;
    out.rate_symbol = sym;
    return out, no_fault();
}

// ofx_extras reads the OFX fields of a STMTTRN that no other format has.
fn ofx_extras(nodes: SgmlNode[>..]&, id: i32, buf: u8[>..]&) -> OfxEntry, Fault {
    var x = no_ofx();
    let du = sgml_child(nodes, id, "DTUSER");
    if du >= 0 {
        let d, ok = ofx_date(sgml_text_of(nodes, du, buf));
        if !ok { return x, fault(F_DATE, 0, 0, "DTUSER", "the date is not OFX form"); }
        x.user_date = d;
    }
    x.correct_ref = child_text(nodes, id, "CORRECTFITID", buf);
    x.correct_action = child_text(nodes, id, "CORRECTACTION", buf);
    if x.correct_action.len > 0 && x.correct_action != "REPLACE" && x.correct_action != "DELETE" {
        return x, fault(F_SYNTAX, 0, 0, "CORRECTACTION", "the action is not REPLACE or DELETE");
    }
    x.payee_id = child_text(nodes, id, "PAYEEID", buf);
    x.ext_name = child_text(nodes, id, "EXTDNAME", buf);
    let py = sgml_child(nodes, id, "PAYEE");
    if py >= 0 {
        x.has_payee = true;
        x.payee.name = child_text(nodes, py, "NAME", buf);
        x.payee.addr1 = child_text(nodes, py, "ADDR1", buf);
        x.payee.addr2 = child_text(nodes, py, "ADDR2", buf);
        x.payee.addr3 = child_text(nodes, py, "ADDR3", buf);
        x.payee.city = child_text(nodes, py, "CITY", buf);
        x.payee.state = child_text(nodes, py, "STATE", buf);
        x.payee.postal_code = child_text(nodes, py, "POSTALCODE", buf);
        x.payee.country = child_text(nodes, py, "COUNTRY", buf);
        x.payee.phone = child_text(nodes, py, "PHONE", buf);
    }
    let sic = sgml_child(nodes, id, "SIC");
    if sic >= 0 {
        let n, ok = digits(sgml_text_of(nodes, sic, buf));
        if !ok { return x, fault(F_SYNTAX, 0, 0, "SIC", "the code is not a number of 1 to 9 digits"); }
        x.sic = n;
        x.has_sic = true;
    }
    let bt = sgml_child(nodes, id, "BANKACCTTO");
    let ct = sgml_child(nodes, id, "CCACCTTO");
    if bt >= 0 && ct >= 0 {
        return x, fault(F_SYNTAX, 0, 0, "STMTTRN", "the entry holds BANKACCTTO and CCACCTTO together");
    }
    if bt >= 0 {
        x.acct_to_kind = 'B';
        x.acct_to.bank_id = child_text(nodes, bt, "BANKID", buf);
        x.acct_to.branch_id = child_text(nodes, bt, "BRANCHID", buf);
        x.acct_to.acct_id = child_text(nodes, bt, "ACCTID", buf);
        x.acct_to.acct_type = child_text(nodes, bt, "ACCTTYPE", buf);
        x.acct_to.acct_key = child_text(nodes, bt, "ACCTKEY", buf);
    }
    if ct >= 0 {
        x.acct_to_kind = 'C';
        x.acct_to.acct_id = child_text(nodes, ct, "ACCTID", buf);
        x.acct_to.acct_key = child_text(nodes, ct, "ACCTKEY", buf);
    }
    x.inv401k_source = child_text(nodes, id, "INV401KSOURCE", buf);
    if x.inv401k_source.len > 0 && !in_list(INV401K, x.inv401k_source) {
        return x, fault(F_SYNTAX, 0, 0, "INV401KSOURCE", "the source is not one of the seven values");
    }
    var c = first_child(nodes, id);
    while c >= 0 {
        if ieq(nodes[c].name, "IMAGEDATA") {
            // The front and the back of a check are the most that Go
            // ofxgo allows. A third image is a fault.
            if x.image_count >= 2 { return x, fault(F_SYNTAX, 0, 0, "IMAGEDATA", "a transaction holds more than two images"); }
            let im, imf = ofx_image(nodes, c, buf);
            if imf.kind != F_NONE { return x, imf; }
            if x.image_count == 0 { x.image = im; } else { x.image2 = im; }
            x.image_count += 1;
        }
        c = sgml_next(nodes, c);
    }
    let cu = sgml_child(nodes, id, "CURRENCY");
    let oc = sgml_child(nodes, id, "ORIGCURRENCY");
    if cu >= 0 && oc >= 0 {
        return x, fault(F_SYNTAX, 0, 0, "STMTTRN", "the entry holds CURRENCY and ORIGCURRENCY together");
    }
    if cu >= 0 {
        let y, f = ofx_rate(nodes, cu, 'C', buf, x);
        return y, f;
    }
    if oc >= 0 {
        let y, f = ofx_rate(nodes, oc, 'O', buf, x);
        return y, f;
    }
    return x, no_fault();
}

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

// is_invtran tells whether a name is one of the investment transaction
// aggregates.
fn is_invtran(name: const u8[:]) -> bool {
    if ieq(name, "INVBANKTRAN") { return true; }
    if ieq(name, "BUYSTOCK") || ieq(name, "SELLSTOCK") { return true; }
    if ieq(name, "BUYMF") || ieq(name, "SELLMF") { return true; }
    if ieq(name, "BUYOPT") || ieq(name, "SELLOPT") { return true; }
    if ieq(name, "BUYDEBT") || ieq(name, "SELLDEBT") { return true; }
    if ieq(name, "BUYOTHER") || ieq(name, "SELLOTHER") { return true; }
    if ieq(name, "INCOME") || ieq(name, "REINVEST") || ieq(name, "RETOFCAP") { return true; }
    if ieq(name, "SPLIT") || ieq(name, "TRANSFER") { return true; }
    if ieq(name, "JRNLFUND") || ieq(name, "JRNLSEC") { return true; }
    if ieq(name, "MARGININTEREST") || ieq(name, "INVEXPENSE") || ieq(name, "CLOSUREOPT") { return true; }
    return false;
}

// is_pos tells whether a name is one of the position aggregates.
fn is_pos(name: const u8[:]) -> bool {
    return ieq(name, "POSSTOCK") || ieq(name, "POSMF") || ieq(name, "POSOPT")
        || ieq(name, "POSDEBT") || ieq(name, "POSOTHER");
}

// ofx_invtran reads one investment transaction aggregate into an entry.
// The type text names the kind. The money fields go into the rationals
// of the entry; TOTAL is the amount.
fn ofx_invtran(nodes: SgmlNode[>..]&, id: i32, kind: const u8[:], ccy: const u8[:],
               lim: Limits&, entries: Entry[>..]&, buf: u8[>..]&, cur: i64) -> Fault {
    if entries.len >= lim.max_entries { return fault(F_LIMIT, 0, 0, kind, "more entries than max_entries"); }
    var e = new_entry(ccy);
    // The type text: the kind, plus the income kind or the action.
    {
        let start = buf.len;
        for u in kind { buf.push(u); }
        let inc = sgml_child(nodes, id, "INCOMETYPE");
        if inc >= 0 {
            buf.push('/');
            sgml_text_of(nodes, inc, buf);
        }
        e.type_id = buf[start..];
    }
    // INVTRAN holds the references and the dates. It sits in the
    // aggregate, or in its INVBUY or INVSELL child as the specification
    // orders it.
    var it = sgml_child(nodes, id, "INVTRAN");
    if it < 0 { it = ofx_money_child(nodes, id, "INVBUY", "INVTRAN"); }
    if it < 0 { it = ofx_money_child(nodes, id, "INVSELL", "INVTRAN"); }
    if it >= 0 {
        let fit = sgml_child(nodes, it, "FITID");
        if fit >= 0 { e.entry_ref = sgml_text_of(nodes, fit, buf); }
        let srv = sgml_child(nodes, it, "SRVRTID");
        if srv >= 0 { e.bank_ref = sgml_text_of(nodes, srv, buf); }
        let memo = sgml_child(nodes, it, "MEMO");
        if memo >= 0 { e.narrative = sgml_text_of(nodes, memo, buf); }
        let dt = sgml_child(nodes, it, "DTTRADE");
        if dt >= 0 {
            let v = sgml_text_of(nodes, dt, buf);
            let d, ok = ofx_date(v);
            if !ok { return fault(F_DATE, 0, 0, "DTTRADE", "the date is not OFX form"); }
            e.value_date = d;
        }
        let ds = sgml_child(nodes, it, "DTSETTLE");
        if ds >= 0 {
            let v = sgml_text_of(nodes, ds, buf);
            let d, ok = ofx_date(v);
            if ok { e.entry_date = d; }
        }
    }
    // TOTAL is the amount of the entry. INVBANKTRAN holds a STMTTRN
    // instead.
    if ieq(kind, "INVBANKTRAN") {
        let st = sgml_child(nodes, id, "STMTTRN");
        if st >= 0 {
            let f = ofx_stmttrn(nodes, st, ccy, lim, entries, buf, cur);
            if f.kind != F_NONE { return f; }
            entries[entries.len - 1].type_id = "INVBANKTRAN";
            return no_fault();
        }
    } else {
        // The total sits in the aggregate or in its INVBUY or INVSELL
        // child.
        var tot = sgml_child(nodes, id, "TOTAL");
        if tot < 0 { tot = ofx_money_child(nodes, id, "INVBUY", "TOTAL"); }
        if tot < 0 { tot = ofx_money_child(nodes, id, "INVSELL", "TOTAL"); }
        if tot >= 0 {
            let v = sgml_text_of(nodes, tot, buf);
            let r, f = ofx_ratio(v);
            if f.kind != F_NONE { return with_tag(f, "TOTAL"); }
            e.total = r;
            e.has_total = true;
            e.total_text = v;
            // The sign of the text is the mark.
            if v.len > 0 && v[0] == '-' { e.mark = "D"; } else { e.mark = "C"; }
            // The amount takes the total when it fits the currency.
            let a, af = parse_amount(v, currency_exponent(ccy), '.', 0);
            if af.kind == F_NONE { e.amount = a; }
        }
    }
    // The money fields of the trade.
    let m, mf = ofx_money(nodes, id, buf);
    if mf.kind != F_NONE { return mf; }
    e.units = m.units;
    e.has_units = m.has_units;
    e.units_text = m.units_text;
    e.unit_price = m.unit_price;
    e.has_unit_price = m.has_unit_price;
    e.unit_price_text = m.unit_price_text;
    e.commission = m.commission;
    e.has_commission = m.has_commission;
    e.commission_text = m.commission_text;
    entries.push(e);
    return no_fault();
}

// OfxMoney holds the money fields of an investment transaction. The
// rationals are exact; the texts stay as given.
struct OfxMoney {
    units: Rational,
    has_units: bool,
    units_text: const u8[:],
    unit_price: Rational,
    has_unit_price: bool,
    unit_price_text: const u8[:],
    commission: Rational,
    has_commission: bool,
    commission_text: const u8[:],
}

// ofx_money reads UNITS, UNITPRICE and COMMISSION of a transaction.
// The fields sit in the aggregate or in its INVBUY or INVSELL child.
fn ofx_money(nodes: SgmlNode[>..]&, id: i32, buf: u8[>..]&) -> OfxMoney, Fault {
    var m = OfxMoney {
        units: Rational { num: 0, den: 1 }, has_units: false, units_text: "",
        unit_price: Rational { num: 0, den: 1 }, has_unit_price: false, unit_price_text: "",
        commission: Rational { num: 0, den: 1 }, has_commission: false, commission_text: "",
    };
    var un = sgml_child(nodes, id, "UNITS");
    if un < 0 { un = ofx_money_child(nodes, id, "INVBUY", "UNITS"); }
    if un < 0 { un = ofx_money_child(nodes, id, "INVSELL", "UNITS"); }
    if un >= 0 {
        let v = sgml_text_of(nodes, un, buf);
        let r, f = ofx_ratio(v);
        if f.kind != F_NONE { return m, with_tag(f, "UNITS"); }
        m.units = r;
        m.has_units = true;
        m.units_text = v;
    }
    var up = sgml_child(nodes, id, "UNITPRICE");
    if up < 0 { up = ofx_money_child(nodes, id, "INVBUY", "UNITPRICE"); }
    if up < 0 { up = ofx_money_child(nodes, id, "INVSELL", "UNITPRICE"); }
    if up >= 0 {
        let v = sgml_text_of(nodes, up, buf);
        let r, f = ofx_ratio(v);
        if f.kind != F_NONE { return m, with_tag(f, "UNITPRICE"); }
        m.unit_price = r;
        m.has_unit_price = true;
        m.unit_price_text = v;
    }
    var co = sgml_child(nodes, id, "COMMISSION");
    if co < 0 { co = ofx_money_child(nodes, id, "INVBUY", "COMMISSION"); }
    if co < 0 { co = ofx_money_child(nodes, id, "INVSELL", "COMMISSION"); }
    if co >= 0 {
        let v = sgml_text_of(nodes, co, buf);
        let r, f = ofx_ratio(v);
        if f.kind != F_NONE { return m, with_tag(f, "COMMISSION"); }
        m.commission = r;
        m.has_commission = true;
        m.commission_text = v;
    }
    return m, no_fault();
}

// ofx_money_child gives the child element with the name in the child
// aggregate of the node, or -1.
fn ofx_money_child(nodes: SgmlNode[>..]&, id: i32, agg: const u8[:], name: const u8[:]) -> i32 {
    let a = sgml_child(nodes, id, agg);
    if a < 0 { return -1; }
    return sgml_child(nodes, a, name);
}

// ofx_pos reads one position aggregate into an entry whose type text
// names the position kind. The market value is the amount.
fn ofx_pos(nodes: SgmlNode[>..]&, id: i32, kind: const u8[:], ccy: const u8[:],
           lim: Limits&, entries: Entry[>..]&, balances: Balance[>..]&, buf: u8[>..]&, cur: i64) -> Fault {
    if entries.len >= lim.max_entries { return fault(F_LIMIT, 0, 0, kind, "more entries than max_entries"); }
    var e = new_entry(ccy);
    e.type_id = kind;
    e.mark = "C";
    let inv = sgml_child(nodes, id, "INVPOS");
    if inv < 0 { return fault(F_SYNTAX, 0, 0, kind, "the position has no INVPOS"); }
    let sec = sgml_child(nodes, inv, "SECID");
    if sec >= 0 {
        let uid = sgml_child(nodes, sec, "UNIQUEID");
        if uid >= 0 { e.customer_ref = sgml_text_of(nodes, uid, buf); }
    }
    let dt = sgml_child(nodes, inv, "DTPRICEASOF");
    if dt >= 0 {
        let v = sgml_text_of(nodes, dt, buf);
        let d, mins, off, ok = ofx_datetime(v);
        if ok {
            let _ = mins;
            let _ = off;
            e.value_date = d;
        }
    }
    let mv = sgml_child(nodes, inv, "MKTVAL");
    if mv >= 0 {
        let v = sgml_text_of(nodes, mv, buf);
        let r, f = ofx_ratio(v);
        if f.kind != F_NONE { return with_tag(f, "MKTVAL"); }
        e.total = r;
        e.has_total = true;
        e.total_text = v;
        if v.len > 0 && v[0] == '-' { e.mark = "D"; } else { e.mark = "C"; }
        // The amount takes the value when it fits the currency.
        let a, af = parse_amount(v, currency_exponent(ccy), '.', 0);
        if af.kind == F_NONE { e.amount = a; }
    }
    let m, mf = ofx_money(nodes, inv, buf);
    if mf.kind != F_NONE { return mf; }
    e.units = m.units;
    e.has_units = m.has_units;
    e.units_text = m.units_text;
    e.unit_price = m.unit_price;
    e.has_unit_price = m.has_unit_price;
    e.unit_price_text = m.unit_price_text;
    e.commission = m.commission;
    e.has_commission = m.has_commission;
    e.commission_text = m.commission_text;
    entries.push(e);
    let _ = balances;
    return no_fault();
}

// with_tag puts a new tag into a fault.
fn with_tag(f: Fault, tag: const u8[:]) -> Fault {
    return Fault { kind: f.kind, line: f.line, col: f.col, tag: tag, detail: f.detail, have: f.have, want: f.want };
}

// ofx_amount_of reads one amount element. The exponent comes from the
// currency. A comma is a decimal separator only when no dot is there.
fn ofx_amount_of(nodes: SgmlNode[>..]&, id: i32, tag: const u8[:], ccy: const u8[:], buf: u8[>..]&) -> Amount, Fault {
    let v = sgml_text_of(nodes, id, buf);
    if v.len == 0 { return Amount { minor: 0, exp: 2, currency: "" }, fault(F_AMOUNT, 0, 0, tag, "the amount is empty"); }
    var dec: u8 = '.';
    if find_byte(v, ',') >= 0 && find_byte(v, '.') < 0 { dec = ','; }
    let a, f = parse_amount(v, currency_exponent(ccy), dec, 0);
    if f.kind != F_NONE { return a, f; }
    // The parser gives no currency; the statement gives it.
    var out = a;
    out.currency = ccy;
    return out, no_fault();
}

// ofx_ratio reads an exact rational. It reuses the parser of the QIF
// side and names the tag of the caller.
fn ofx_ratio(v: const u8[:]) -> Rational, Fault {
    var dec: u8 = '.';
    if find_byte(v, ',') >= 0 && find_byte(v, '.') < 0 { dec = ','; }
    return parse_ratio(v, dec, 0, 0, 'I');
}

// find_byte gives the first place of a byte, or -1.
fn find_byte(s: const u8[:], c: u8) -> i64 {
    var i: i64 = 0;
    while i < s.len {
        if s[i] == c { return i; }
        i += 1;
    }
    return -1;
}
// ofx_date reads a date of OFX form and gives the date.
fn ofx_date(s: const u8[:]) -> Date, bool {
    let d, mins, off, ok = ofx_datetime(s);
    if !ok { return no_date(), false; }
    let _ = mins;
    let _ = off;
    return d, true;
}

// ofx_datetime reads a date and time of OFX form:
// YYYYMMDD[HHMM[SS[.XXX]]][[+H[.MM|HHMM][:TZ]]]. The dotted offset
// reads as hours and minutes: [-5.30] is 5 hours 30 minutes. No zone
// means GMT. It gives the date, the minutes of the day and the offset
// in minutes.
fn ofx_datetime(s: const u8[:]) -> Date, i32, i32, bool {
    if s.len < 8 { return no_date(), 0, 0, false; }
    let y, a = digits(s[0..4]);
    let m, b = digits(s[4..6]);
    let d, c = digits(s[6..8]);
    if !a || !b || !c { return no_date(), 0, 0, false; }
    let dt, ok = make_date(y, m, d);
    if !ok { return no_date(), 0, 0, false; }
    var mins: i32 = 0;
    var i: i64 = 8;
    // The time: HHMM, HHMMSS or HHMMSS.XXX.
    if i + 2 <= s.len && is_digit(s[i]) {
        let hh, ok2 = digits(s[i..i + 2]);
        if !ok2 || hh > 23 { return no_date(), 0, 0, false; }
        mins = (hh * 60) as i32;
        i += 2;
        if i + 2 <= s.len && is_digit(s[i]) {
            let mm, ok3 = digits(s[i..i + 2]);
            if !ok3 || mm > 59 { return no_date(), 0, 0, false; }
            mins += mm as i32;
            i += 2;
            if i + 2 <= s.len && is_digit(s[i]) {
                let ss, ok4 = digits(s[i..i + 2]);
                if !ok4 || ss > 60 { return no_date(), 0, 0, false; }
                let _ = ss;
                i += 2;
                if i < s.len && s[i] == '.' {
                    i += 1;
                    while i < s.len && is_digit(s[i]) { i += 1; }
                }
            }
        }
    }
    // The zone: [offset] or [offset:TZ] or [:TZ]. The offset is a
    // signed hour count with optional minutes after a dot, or two
    // more digits.
    var off: i32 = 0;
    if i < s.len {
        if s[i] != '[' { return no_date(), 0, 0, false; }
        let close = find_byte(s[i..], ']');
        if close < 0 { return no_date(), 0, 0, false; }
        let zone = s[i + 1..i + close];
        i = i + close + 1;
        var zi: i64 = 0;
        var sign: i32 = 1;
        if zi < zone.len && (zone[zi] == '+' || zone[zi] == '-') {
            if zone[zi] == '-' { sign = -1; }
            zi += 1;
        }
        var oh: i64 = -1;
        var om: i64 = 0;
        if zi < zone.len && is_digit(zone[zi]) {
            var zs = zi;
            while zs < zone.len && is_digit(zone[zs]) { zs += 1; }
            let n, okz = digits(zone[zi..zs]);
            if !okz { return no_date(), 0, 0, false; }
            oh = n;
            zi = zs;
            if zi < zone.len && zone[zi] == '.' {
                zi += 1;
                let ms = zi;
                while zi < zone.len && is_digit(zone[zi]) { zi += 1; }
                // One or two digits are minutes; more are hundredths
                // of an hour of the form .XXX. The minutes reading
                // wins for the two digit form.
                let fl = zi - ms;
                if fl == 1 || fl == 2 {
                    let mm, okm = digits(zone[ms..zi]);
                    if !okm || mm > 59 { return no_date(), 0, 0, false; }
                    om = mm;
                } else if fl == 3 {
                    let mm, okm = digits(zone[ms..ms + 2]);
                    if !okm || mm > 59 { return no_date(), 0, 0, false; }
                    om = mm;
                } else {
                    return no_date(), 0, 0, false;
                }
            } else if zi + 2 <= zone.len && is_digit(zone[zi]) && is_digit(zone[zi + 1]) {
                let mm, okm = digits(zone[zi..zi + 2]);
                if !okm || mm > 59 { return no_date(), 0, 0, false; }
                om = mm;
                zi += 2;
            }
            if oh > 14 { return no_date(), 0, 0, false; }
            off = sign * ((oh * 60 + om) as i32);
        } else {
            // No hours: the zone name must say the offset.
            let nm, okn = zone_name(zone);
            if !okn { return no_date(), 0, 0, false; }
            off = nm;
        }
        // A zone name after the offset is read and dropped. The
        // offset says the time already.
    }
    if i != s.len { return no_date(), 0, 0, false; }
    return dt, mins, off, true;
}

// zone_name gives the offset of a zone name of the table that the
// references hold, in minutes. An unknown name is refused.
fn zone_name(name: const u8[:]) -> i32, bool {
    if ieq(name, "EST") { return -5 * 60, true; }
    if ieq(name, "EDT") { return -4 * 60, true; }
    if ieq(name, "CST") { return -6 * 60, true; }
    if ieq(name, "CDT") { return -5 * 60, true; }
    if ieq(name, "MST") { return -7 * 60, true; }
    if ieq(name, "MDT") { return -6 * 60, true; }
    if ieq(name, "PST") { return -8 * 60, true; }
    if ieq(name, "PDT") { return -7 * 60, true; }
    if ieq(name, "GMT") || ieq(name, "UTC") { return 0, true; }
    return 0, false;
}
