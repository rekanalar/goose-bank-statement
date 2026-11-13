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
        total: Rational { num: 0, den: 1 }, has_total: false, total_text: "", ofx: no_ofx(),
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
    // of every entry without a sign. The currency of the account gives
    // the sum its currency.
    let all = c_child(doc, s, "TtlNtries");
    if all >= 0 {
        let cnt, has = c_text(doc, all, "NbOfNtries", buf);
        if has {
            let n, ok = digits(cnt);
            if !ok { return fault(F_TOTAL, 0, 0, tag, "the number of entries in the summary is not a number"); }
            statements[cur].all_count = n;
        }
        // The signed net entry of the block.
        let net = c_child(doc, all, "TtlNetNtry");
        if net >= 0 {
            let amt = c_child(doc, net, "Amt");
            if amt >= 0 {
                var a: Amount;
                var f: Fault;
                let at, hasat = xml::attr_lookup(doc, doc.nodes[amt], "Ccy");
                if hasat && at.len == 3 {
                    a, f = camt_amount_of(doc, amt, tag, buf);
                } else {
                    a, f = camt_amount_ccy(doc, amt, tag, ccy, buf);
                }
                if f.kind != F_NONE { return f; }
                statements[cur].net_amount = a;
                statements[cur].has_net = true;
            }
            let dir, hasd = c_text(doc, net, "CdtDbtInd", buf);
            if hasd && dir == "CRDT" { statements[cur].net_credit = true; }
        }
        let sum = c_child(doc, all, "Sum");
        if sum >= 0 && ccy.len == 3 {
            // The sum has no currency of its own. When the account
            // names none, the count alone stays.
            let a, f = camt_amount_ccy(doc, sum, tag, ccy, buf);
            if f.kind != F_NONE { return f; }
            statements[cur].all_total = a;
            statements[cur].has_all_total = true;
        }
    }
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
    // The period, the copy flag and the reporting sequence.
    let ft = c_child(doc, id, "FrToDt");
    if ft >= 0 {
        var fv, has1 = c_text(doc, ft, "FrDtTm", buf);
        if !has1 { var fv2, has2 = c_text(doc, ft, "FrDt", buf); if has2 { fv = fv2; has1 = has2; } }
        if has1 {
            var fd, fok = camt_date(fv);
            if !fok {
                let fd2, _, _, dok = camt_datetime(fv);
                if dok {
                    statements[cur].period_from = fd2;
                    statements[cur].has_period = true;
                }
            } else {
                statements[cur].period_from = fd;
                statements[cur].has_period = true;
            }
        }
        var tv, has3 = c_text(doc, ft, "ToDtTm", buf);
        if !has3 { var tv2, has4 = c_text(doc, ft, "ToDt", buf); if has4 { tv = tv2; has3 = has4; } }
        if has3 {
            var td, tok = camt_date(tv);
            if !tok {
                let td2, _, _, dok2 = camt_datetime(tv);
                if dok2 { statements[cur].period_to = td2; }
            } else {
                statements[cur].period_to = td;
            }
        }
    }
    let cpd, hasc = c_text(doc, id, "CpyDplctInd", buf);
    if hasc { statements[cur].copy_duplicate = cpd; }
    let src = c_child(doc, id, "RptgSrc");
    if src >= 0 {
        let cd, hasc2 = c_text(doc, src, "Cd", buf);
        if !hasc2 { let pr, hasp = c_text(doc, src, "Prtry", buf); if hasp { statements[cur].reporting_source = pr; } else { statements[cur].reporting_source = cd; } }
        else { statements[cur].reporting_source = cd; }
    }
    let pg = c_child(doc, id, "StmtPgntn");
    if pg >= 0 {
        let nb, hasnb = c_text(doc, pg, "PgNb", buf);
        if hasnb { statements[cur].page_number = nb; }
        let lp, haslp = c_text(doc, pg, "LastPgInd", buf);
        if haslp && lp == "true" { statements[cur].last_page = true; }
    }
    let seq = c_child(doc, id, "RptgSeq");
    if seq >= 0 {
        let rng = c_child(doc, seq, "FrToSeq");
        if rng >= 0 {
            let from, has1 = c_text(doc, rng, "From", buf);
            if has1 { statements[cur].reporting_from = from; }
            let to, has2 = c_text(doc, rng, "To", buf);
            if has2 { statements[cur].reporting_to = to; }
        } else {
            let from, has1 = c_text(doc, seq, "FrSeq", buf);
            if has1 { statements[cur].reporting_from = from; }
            let to, has2 = c_text(doc, seq, "ToSeq", buf);
            if has2 { statements[cur].reporting_to = to; }
        }
    }
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
fn parse_camt(input: const u8[:], lim: Limits&, opts: CamtOptions&, header: CamtHeader&,
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
    // The application header sits beside the message.
    let app = c_child(doc, doc.root, "AppHdr");
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
    header = camt_header(doc, kind, app, grp, buf);
    return no_fault();
}
