// Names a return reason code and builds a reversing entry.
// Run with: goose run examples/camt_reason.goose

import std;
import xml from "rekanalar/goose-xml@v2.0.0";
import process from "rekanalar/goose-process@v1.0.0";
import bank_statement from "..";

fn main() {
    var buf: u8[>..] = [];
    print("AC04 ", bank_statement::reason_name("AC04", buf), " action ", bank_statement::reason_action("AC04", buf));
    print("AM04 ", bank_statement::reason_name("AM04", buf), " action ", bank_statement::reason_action("AM04", buf));
    let lim = bank_statement::default_limits();
    let opts = bank_statement::CamtOptions { .. };
    var sts: bank_statement::Statement[>..] = [];
    var ens: bank_statement::Entry[>..] = [];
    var bals: bank_statement::Balance[>..] = [];
    var notes: bank_statement::Note[>..] = [];
    var buf2: u8[>..] = [];
    var hd = bank_statement::CamtHeader { .. };
    let f = bank_statement::parse_camt("<Document xmlns=\"urn:iso:std:iso:20022:tech:xsd:camt.053.001.08\"><BkToCstmrStmt><GrpHdr><MsgId>M</MsgId><CreDtTm>2025-01-02T15:30:00+01:00</CreDtTm></GrpHdr><Stmt><Id>S</Id><CreDtTm>2025-01-02T15:30:00+01:00</CreDtTm><Acct><Id><IBAN>DE89370400440532013000</IBAN></Id><Ccy>EUR</Ccy></Acct><Bal><Tp><CdOrPrtry><Cd>OPBD</Cd></CdOrPrtry></Tp><Amt Ccy=\"EUR\">1000.00</Amt><CdtDbtInd>CRDT</CdtDbtInd><Dt><Dt>2025-01-01</Dt></Dt></Bal><Bal><Tp><CdOrPrtry><Cd>CLBD</Cd></CdOrPrtry></Tp><Amt Ccy=\"EUR\">900.00</Amt><CdtDbtInd>CRDT</CdtDbtInd><Dt><Dt>2025-01-02</Dt></Dt></Bal><Ntry><Amt Ccy=\"EUR\">100.00</Amt><CdtDbtInd>DBIT</CdtDbtInd><Sts>BOOK</Sts><BookgDt><Dt>2025-01-02</Dt></BookgDt></Ntry></Stmt></BkToCstmrStmt></Document>", lim, opts, hd, sts, ens, bals, buf2);
    if f.kind != 0 {
        print("error: ", bank_statement::kind_name(f.kind), " ", f.detail, "\n");
        return 1;
    }
    let rv, ok = bank_statement::reversal_of(ens[0]);
    if !ok {
        print("error: the entry has no mark to reverse\n");
        return 1;
    }
    print("entry ", ens[0].mark, " ", ens[0].amount.minor, " reversal ", rv.mark, " ", rv.amount.minor);
    return 0;
}
