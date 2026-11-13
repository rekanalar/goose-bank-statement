// The fields of the OFX statements.
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

struct OfxOptions {
    skip_pending: bool,
    check_country: bool,
    // Decode the body with the charset that the header names. The
    // default is on.
    auto_charset: bool = true,
}

// parse_ofx reads one OFX file into the arrays of the caller. The
// buffer of the caller holds the text that the arrays point at.
// parse_ofx reads an OFX 1.x or 2.x file. When the header names a
// legacy charset, the body is decoded first, unless the option turns
// the decode off.
fn parse_ofx_decoded(input: const u8[:], lim: Limits&, opts: OfxOptions&,
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
                statements[cur].credit_card = true;
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
