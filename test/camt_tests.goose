// The tests of the group camt.
namespace camt_tests;

import std;
import os;
import xml from "rekanalar/goose-xml@v2.0.0";
import process from "rekanalar/goose-process@v1.0.0";
import bank_statement from "..";
import finance from "rekanalar/goose-finance@v0.1.0";
import statement_checks;
import sample_texts;

fn test_camt_statement() {
    let lim = bank_statement::default_limits();
    let opts = bank_statement::CamtOptions { .. };
    var sts: bank_statement::Statement[>..] = [];
    var ens: bank_statement::Entry[>..] = [];
    var bals: bank_statement::Balance[>..] = [];
    var buf: u8[>..] = [];
    var hd2 = bank_statement::CamtHeader { .. };
    let f = bank_statement::parse_camt(sample_texts::CAMT53, lim, opts, hd2, sts, ens, bals, buf);
    if f.kind != 0 { print("FAIL camt53 ", bank_statement::kind_name(f.kind), " ", f.tag, " ", f.detail, "\n"); }
    assert(f.kind == 0);
    assert(sts.len == 1);
    let st = sts[0];
    assert(st.reference == "STMT-1");
    assert(st.related_ref == "MSG-1");
    assert(st.account == "DE89370400440532013000");
    assert(st.number == "42" && st.sequence == "7");
    assert(st.report_date.year == 2025 && st.report_date.month == 1 && st.report_date.day == 2);
    assert(st.report_minutes == 15 * 60 + 30 && st.report_offset == 60 && st.has_report_time);
    assert(!st.is_interim);
    assert(st.has_period);
    assert(st.period_from.year == 2025 && st.period_from.month == 1 && st.period_from.day == 1);
    assert(st.period_to.year == 2025 && st.period_to.month == 1 && st.period_to.day == 31);
    assert(st.copy_duplicate == "CCPY");
    assert(st.reporting_from == "11" && st.reporting_to == "78");
    assert(st.has_all_total && st.all_count == 3 && st.all_total.minor == 70000 && st.all_total.currency == "EUR");
    assert(st.has_net && st.net_amount.minor == 10000 && st.net_credit);
    assert(st.reporting_source == "MLST");
    assert(st.page_number == "2" && st.last_page);
    // The balances.
    assert(st.balance_count == 9);
    assert(st.opening.kind == bank_statement::BAL_OPENING);
    assert(st.opening.amount.minor == 100000 && st.opening.amount.currency == "EUR");
    assert(st.opening.date.year == 2025 && st.opening.date.day == 1);
    assert(st.opening.code == "OPBD");
    assert(st.closing.amount.minor == 170000 && st.closing.code == "CLBD");
    assert(st.available.amount.minor == 170000 && st.available.code == "CLAV");
    assert(st.forward.amount.minor == 180000 && st.forward.code == "FWAV");
    assert(st.balance_checked);
    // The other balance codes. The available and the forward fields
    // keep the first balance of their kind.
    assert(bals[5].kind == bank_statement::BAL_AVAILABLE && bals[5].code == "OPAV");
    assert(bals[6].kind == bank_statement::BAL_AVAILABLE && bals[6].code == "ITAV" && bals[6].intermediate);
    assert(bals[7].kind == 0 && bals[7].code == "PRCD");
    assert(bals[8].kind == 0 && bals[8].code == "XPCD");
    assert(bals[4].kind == 0 && bals[4].code == "OWN1");
    // The entries.
    assert(st.entry_count == 3 && ens.len == 3);
    let e = ens[0];
    assert(e.mark == "C" && e.amount.minor == 50000 && e.amount.exp == 2 && e.amount.currency == "EUR");
    assert(e.status == "BOOK");
    assert(e.value_date.year == 2025 && e.value_date.month == 1 && e.value_date.day == 3);
    assert(e.entry_date.year == 2025 && e.entry_date.month == 1 && e.entry_date.day == 2);
    assert(e.bank_ref == "BREF-1" && e.entry_ref == "EREF-1");
    assert(e.type_id == "PMNT/RCDT/ESCT");
    assert(e.narrative == "Payment for services");
    assert(e.customer_ref == "E2E-1");
    assert(e.counter_name == "Acme Corp" && e.counter_iban == "DE02120300000000202051");
    assert(e.remittance == "Invoice 42\nThanks");
    assert(e.batch_count == "2" && e.has_batch_total && e.batch_total.minor == 70000);
    assert(e.batch_msg_id == "BATCH-1" && e.batch_pmt_id == "PINF-1");
    // A reversal of a debit is RD and adds to the sum.
    assert(ens[1].mark == "RD" && ens[1].amount.minor == 20000 && ens[1].type_id == "DEB01/BANK");
    // A pending entry stays out of the sum.
    assert(ens[2].status == "PDNG");
    // The group header facts land in the message header.
    assert(hd2.kind == 2 && hd2.message_id == "MSG-1");
    assert(hd2.has_creation && hd2.creation.year == 2025);
    assert(hd2.initiator == "Main St Ltd" && hd2.recipient == "Acme Corp");
    assert(hd2.entry_count == "3" && hd2.additional_info == "settlement daily");
}

fn test_camt_apphdr() {
    let lim = bank_statement::default_limits();
    let opts = bank_statement::CamtOptions { .. };
    var sts: bank_statement::Statement[>..] = [];
    var ens: bank_statement::Entry[>..] = [];
    var bals: bank_statement::Balance[>..] = [];
    var buf: u8[>..] = [];
    var hd = bank_statement::CamtHeader { .. };
    let f = bank_statement::parse_camt(sample_texts::CAMTAPP, lim, opts, hd, sts, ens, bals, buf);
    if f.kind != 0 { print("FAIL camtapp ", bank_statement::kind_name(f.kind), " ", f.tag, " ", f.detail, "\n"); }
    assert(f.kind == 0 && sts.len == 1);
    assert(hd.definition == "camt.053.001.08" && hd.service == "AccountReporting");
    // The application header fills what the group header held not.
    assert(hd.message_id == "APP-MSG-1");
    assert(hd.has_creation && hd.creation.year == 2025 && hd.creation_minutes == 15 * 60 + 30 && hd.creation_offset == 60);
    assert(hd.initiator == "BANKDEFF" && hd.recipient == "CLEARINGX");
    assert(sts[0].report_date.year == 2025);
}

fn test_camt_interim() {
    let lim = bank_statement::default_limits();
    let opts = bank_statement::CamtOptions { .. };
    var sts: bank_statement::Statement[>..] = [];
    var ens: bank_statement::Entry[>..] = [];
    var bals: bank_statement::Balance[>..] = [];
    var buf: u8[>..] = [];
    var hd3 = bank_statement::CamtHeader { .. };
    let f = bank_statement::parse_camt(sample_texts::CAMT52, lim, opts, hd3, sts, ens, bals, buf);
    assert(f.kind == 0);
    assert(sts.len == 1 && sts[0].is_interim);
    assert(sts[0].reference == "RPT-1" && sts[0].related_ref == "RPT-MSG");
    assert(sts[0].account == "ACC-9");
    assert(sts[0].report_minutes == 10 * 60 && sts[0].report_offset == 0);
    // A report has no closing balance, so it has no balance check.
    assert(sts[0].closing.kind == 0 && !sts[0].balance_checked);
    // The transaction summary gives the totals.
    assert(sts[0].has_credit_total && sts[0].credit_count == 1 && sts[0].credit_total.minor == 50000);
    assert(sts[0].has_debit_total && sts[0].debit_count == 1 && sts[0].debit_total.minor == 20000);
    // A notification holds no balances.
    var sts2: bank_statement::Statement[>..] = [];
    var ens2: bank_statement::Entry[>..] = [];
    var bals2: bank_statement::Balance[>..] = [];
    var buf2: u8[>..] = [];
    var hd4 = bank_statement::CamtHeader { .. };
    let g = bank_statement::parse_camt(sample_texts::CAMT54, lim, opts, hd4, sts2, ens2, bals2, buf2);
    assert(g.kind == 0);
    assert(sts2.len == 1 && sts2[0].is_interim);
    assert(sts2[0].reference == "NTF-1" && sts2[0].related_ref == "NTF-MSG");
    assert(sts2[0].balance_count == 0 && sts2[0].entry_count == 1);
    assert(ens2[0].amount.minor == 150000 && ens2[0].amount.currency == "CHF");
    assert(ens2[0].status == "BOOK" && ens2[0].mark == "C");
    assert(ens2[0].type_id == "PMNT/RCDT/VCOM");
    assert(ens2[0].narrative == "SAMMELGUTSCHRIFT");
    assert(ens2[0].value_date.day == 25 && ens2[0].entry_date.day == 24);
}

fn test_camt_versions() {
    // The old shape: a plain status and a party without a wrapper.
    let lim = bank_statement::default_limits();
    let opts = bank_statement::CamtOptions { .. };
    var sts: bank_statement::Statement[>..] = [];
    var ens: bank_statement::Entry[>..] = [];
    var bals: bank_statement::Balance[>..] = [];
    var buf: u8[>..] = [];
    var hd5 = bank_statement::CamtHeader { .. };
    let f = bank_statement::parse_camt(sample_texts::CAMT02, lim, opts, hd5, sts, ens, bals, buf);
    assert(f.kind == 0);
    assert(sts[0].reference == "OLD-STMT" && sts[0].account == "OLD-ACC");
    assert(sts[0].report_date.year == 2013 && sts[0].report_minutes == 8 * 60);
    assert(ens[0].status == "BOOK" && ens[0].counter_name == "Old Corp");
    assert(sts[0].balance_checked);
    // A document with a prefix on every element.
    var sts2: bank_statement::Statement[>..] = [];
    var ens2: bank_statement::Entry[>..] = [];
    var bals2: bank_statement::Balance[>..] = [];
    var buf2: u8[>..] = [];
    var hd6 = bank_statement::CamtHeader { .. };
    let g = bank_statement::parse_camt(sample_texts::CAMTPREFIX, lim, opts, hd6, sts2, ens2, bals2, buf2);
    assert(g.kind == 0);
    assert(sts2[0].reference == "P-STMT" && sts2[0].related_ref == "P-1");
    assert(sts2[0].opening.amount.minor == 0 && sts2[0].closing.amount.minor == 0);
}

fn test_camt_checks() {
    // One cent off in the closing balance.
    let bad = """
<Document xmlns="urn:iso:std:iso:20022:tech:xsd:camt.053.001.08"><BkToCstmrStmt><Stmt><Id>S</Id>
<Bal><Tp><CdOrPrtry><Cd>OPBD</Cd></CdOrPrtry></Tp><Amt Ccy="EUR">100.00</Amt><CdtDbtInd>CRDT</CdtDbtInd></Bal>
<Bal><Tp><CdOrPrtry><Cd>CLBD</Cd></CdOrPrtry></Tp><Amt Ccy="EUR">200.01</Amt><CdtDbtInd>CRDT</CdtDbtInd></Bal>
<Ntry><Amt Ccy="EUR">100.00</Amt><CdtDbtInd>CRDT</CdtDbtInd><Sts>BOOK</Sts></Ntry>
</Stmt></BkToCstmrStmt></Document>
""";
    statement_checks::run_camt(bad, false, 7);
    statement_checks::run_camt(bad, true, 0);
    // A wrong total in the transaction summary.
    let bad_total = """
<Document xmlns="urn:iso:std:iso:20022:tech:xsd:camt.052.001.08"><BkToCstmrAcctRpt><Rpt><Id>R</Id>
<TxsSummry><TtlCdtNtries><NbOfNtries>2</NbOfNtries><Sum Ccy="EUR">500.00</Sum></TtlCdtNtries></TxsSummry>
<Ntry><Amt Ccy="EUR">500.00</Amt><CdtDbtInd>CRDT</CdtDbtInd><Sts>BOOK</Sts></Ntry>
</Rpt></BkToCstmrAcctRpt></Document>
""";
    statement_checks::run_camt(bad_total, false, 8);
    // A summary with one block for all the entries gives no credit or
    // debit total, so it has no check.
    let gross = """
<Document xmlns="urn:iso:std:iso:20022:tech:xsd:camt.054.001.08"><BkToCstmrDbtCdtNtfctn><Ntfctn><Id>N</Id>
<TxsSummry><TtlNtries><NbOfNtries>2</NbOfNtries><Sum>300.00</Sum><CdtDbtInd>CRDT</CdtDbtInd></TtlNtries></TxsSummry>
<Ntry><Amt Ccy="EUR">200.00</Amt><CdtDbtInd>CRDT</CdtDbtInd><Sts>BOOK</Sts></Ntry>
<Ntry><Amt Ccy="EUR">100.00</Amt><CdtDbtInd>DBIT</CdtDbtInd><Sts>BOOK</Sts></Ntry>
</Ntfctn></BkToCstmrDbtCdtNtfctn></Document>
""";
    statement_checks::run_camt(gross, false, 0);
}

fn test_camt_faults() {
    // A missing amount, a missing currency and a sign in the amount.
    statement_checks::run_camt("<Document xmlns=\"x\"><BkToCstmrStmt><Stmt><Ntry><CdtDbtInd>CRDT</CdtDbtInd></Ntry></Stmt></BkToCstmrStmt></Document>", false, 4);
    statement_checks::run_camt("<Document xmlns=\"x\"><BkToCstmrStmt><Stmt><Ntry><Amt Ccy=\"EUR\">1.00</Amt></Ntry></Stmt></BkToCstmrStmt></Document>", false, 4);
    statement_checks::run_camt("<Document xmlns=\"x\"><BkToCstmrStmt><Stmt><Ntry><Amt>1.00</Amt><CdtDbtInd>CRDT</CdtDbtInd></Ntry></Stmt></BkToCstmrStmt></Document>", false, 4);
    statement_checks::run_camt("<Document xmlns=\"x\"><BkToCstmrStmt><Stmt><Ntry><Amt Ccy=\"EUR\">-1.00</Amt><CdtDbtInd>CRDT</CdtDbtInd></Ntry></Stmt></BkToCstmrStmt></Document>", false, 4);
    statement_checks::run_camt("<Document xmlns=\"x\"><BkToCstmrStmt><Stmt><Ntry><Amt Ccy=\"EUR\">1.00</Amt><CdtDbtInd>XXXX</CdtDbtInd></Ntry></Stmt></BkToCstmrStmt></Document>", false, 4);
    // A root that is not a camt document and a document without a message.
    statement_checks::run_camt("<Foo/>", false, 2);
    statement_checks::run_camt("<Document xmlns=\"x\"><Other/></Document>", false, 2);
    // A document that is not well formed.
    statement_checks::run_camt("<Document>", false, 2);
    // A bad date.
    statement_checks::run_camt("<Document xmlns=\"x\"><BkToCstmrStmt><Stmt><CreDtTm>2025-13-45T99:99:99</CreDtTm></Stmt></BkToCstmrStmt></Document>", false, 6);
    // An unknown element is ignored. A statement without both booked
    // balances has no balance check.
    statement_checks::run_camt("<Document xmlns=\"x\"><BkToCstmrStmt><Stmt><FutureThing><Deeper>x</Deeper></FutureThing></Stmt></BkToCstmrStmt></Document>", false, 0);
    // A document with an entity is refused by the XML layer, so no
    // entity of it can expand.
    statement_checks::run_camt("<Document xmlns=\"x\"><BkToCstmrStmt><Stmt><Id>&xxe;</Id></Stmt></BkToCstmrStmt></Document>", false, 2);
    // A document above the input limit.
    var lim = bank_statement::default_limits();
    lim.max_input = 20;
    var sts: bank_statement::Statement[>..] = [];
    var ens: bank_statement::Entry[>..] = [];
    var bals: bank_statement::Balance[>..] = [];
    var buf: u8[>..] = [];
    let opts = bank_statement::CamtOptions { .. };
    var hd7 = bank_statement::CamtHeader { .. };
    let f = bank_statement::parse_camt(sample_texts::CAMT53, lim, opts, hd7, sts, ens, bals, buf);
    assert(f.kind == 1);
}

fn test_camt_two_statements() {
    let lim = bank_statement::default_limits();
    let opts = bank_statement::CamtOptions { .. };
    var sts: bank_statement::Statement[>..] = [];
    var ens: bank_statement::Entry[>..] = [];
    var bals: bank_statement::Balance[>..] = [];
    var buf: u8[>..] = [];
    let doc = "<Document xmlns=\"x\"><BkToCstmrStmt><Stmt><Id>S1</Id></Stmt><Stmt><Id>S2</Id></Stmt></BkToCstmrStmt></Document>";
    var hd8 = bank_statement::CamtHeader { .. };
    let f = bank_statement::parse_camt(doc, lim, opts, hd8, sts, ens, bals, buf);
    assert(f.kind == 0);
    assert(sts.len == 2);
    assert(sts[0].reference == "S1" && sts[1].reference == "S2");
}

fn test_camt_real_documents() {
    // A real camt.052 report of a bank.
    let lim = bank_statement::default_limits();
    let opts = bank_statement::CamtOptions { .. };
    var sts: bank_statement::Statement[>..] = [];
    var ens: bank_statement::Entry[>..] = [];
    var bals: bank_statement::Balance[>..] = [];
    var buf: u8[>..] = [];
    var hd9 = bank_statement::CamtHeader { .. };
    let f = bank_statement::parse_camt(sample_texts::REAL52, lim, opts, hd9, sts, ens, bals, buf);
    assert(f.kind == 0);
    assert(sts.len == 1 && sts[0].is_interim);
    assert(ens.len == 2 && bals.len == 2);
    // The first entry is a debit of 103.00 Swiss francs.
    assert(ens[0].mark == "D" && ens[0].amount.minor == 10300 && ens[0].amount.currency == "CHF");
    assert(ens[0].type_id == "PMNT/ICDT/AUTT");
    assert(ens[1].mark == "D" && ens[1].amount.minor == 91300);
    // The opening balance holds 208509.19. The intermediate code keeps
    // no kind, but its text stays on the balance.
    assert(sts[0].opening.kind == 1 && sts[0].opening.amount.minor == 20850919);
    assert(sts[0].opening.code == "OPBD");
    assert(bals[1].kind == 0 && bals[1].code == "ITBD");
    // A real camt.054 notification of a bank.
    var sts2: bank_statement::Statement[>..] = [];
    var ens2: bank_statement::Entry[>..] = [];
    var bals2: bank_statement::Balance[>..] = [];
    var buf2: u8[>..] = [];
    var hd10 = bank_statement::CamtHeader { .. };
    let g = bank_statement::parse_camt(sample_texts::REAL54, lim, opts, hd10, sts2, ens2, bals2, buf2);
    assert(g.kind == 0);
    assert(sts2.len == 1 && sts2[0].is_interim && ens2.len == 1 && bals2.len == 0);
    assert(ens2[0].mark == "C" && ens2[0].amount.minor == 150000 && ens2[0].amount.currency == "CHF");
    // A real camt.053 of a bank does not add up. The closing balance
    // of the file differs from the sum of the entries. The balance
    // check finds it, and the flag turns the check off.
    var sts3: bank_statement::Statement[>..] = [];
    var ens3: bank_statement::Entry[>..] = [];
    var bals3: bank_statement::Balance[>..] = [];
    var buf3: u8[>..] = [];
    var hd11 = bank_statement::CamtHeader { .. };
    let h = bank_statement::parse_camt(sample_texts::REAL53, lim, opts, hd11, sts3, ens3, bals3, buf3);
    assert(h.kind == 7 && h.tag == "Bal");
    var sts4: bank_statement::Statement[>..] = [];
    var ens4: bank_statement::Entry[>..] = [];
    var bals4: bank_statement::Balance[>..] = [];
    var buf4: u8[>..] = [];
    let opts2 = bank_statement::CamtOptions { skip_balance_check: true };
    var hd12 = bank_statement::CamtHeader { .. };
    let k = bank_statement::parse_camt(sample_texts::REAL53, lim, opts2, hd12, sts4, ens4, bals4, buf4);
    assert(k.kind == 0);
    assert(sts4.len == 1 && ens4.len == 5 && bals4.len == 4);
    assert(sts4[0].opening.amount.minor == 21199319 && sts4[0].closing.amount.minor == 21511221);
}

fn test_camt_reason() {
    var buf: u8[>..] = [];
    assert(bank_statement::reason_known("AC04", buf));
    assert(bank_statement::reason_known("ac04", buf));
    assert(!bank_statement::reason_known("ZZZZ", buf));
    assert(!bank_statement::reason_known("AC041", buf));
    assert(bank_statement::reason_name("AC04", buf) == "Closed Account Number");
    assert(bank_statement::reason_name("am04", buf) == "Insufficient Funds");
    assert(bank_statement::reason_name("ZZZZ", buf) == "Unknown reason code");
    // The policy names the action for the transient codes only.
    assert(bank_statement::reason_action("AC04", buf) == "return");
    assert(bank_statement::reason_action("AM04", buf) == "retry");
    assert(bank_statement::reason_action("narr", buf) == "ignore");
    assert(bank_statement::reason_action("ZZZZ", buf) == "return");
    // The marks turn around in both forms.
    let m1, ok1 = bank_statement::reverse_mark("CRDT");
    assert(ok1 && m1 == "DBIT");
    let m2, ok2 = bank_statement::reverse_mark("D");
    assert(ok2 && m2 == "C");
    let m3, ok3 = bank_statement::reverse_mark("x");
    assert(!ok3);
    // The reversing entry turns the mark and the signs around.
    let lim = bank_statement::default_limits();
    let opts = bank_statement::CamtOptions { .. };
    var sts: bank_statement::Statement[>..] = [];
    var ens: bank_statement::Entry[>..] = [];
    var bals: bank_statement::Balance[>..] = [];
    var buf2: u8[>..] = [];
    var hd = bank_statement::CamtHeader { .. };
    assert(bank_statement::parse_camt(sample_texts::CAMT53, lim, opts, hd, sts, ens, bals, buf2).kind == 0);
    assert(ens.len > 0);
    let rv, ok = bank_statement::reversal_of(ens[0]);
    assert(ok);
    assert(rv.mark == "D" && ens[0].mark == "C");
    assert(rv.amount.minor == -ens[0].amount.minor);
    let nr, ok2 = bank_statement::reversal_of(ens[0]);
    assert(ok2 && nr.amount.minor == -ens[0].amount.minor);
}
