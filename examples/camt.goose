// Reads a camt.053 statement and prints its balances and entries.
// Run with: goose run examples/camt.goose

import std;
import xml from "rekanalar/goose-xml@v2.0.0";
import process from "rekanalar/goose-process@v1.0.0";
import finance from "rekanalar/goose-finance@v0.1.0";
import bank_statement from "..";

const DOC: const u8[:] = """
<?xml version="1.0" encoding="UTF-8"?>
<Document xmlns="urn:iso:std:iso:20022:tech:xsd:camt.053.001.08">
  <BkToCstmrStmt>
    <GrpHdr><MsgId>MSG-1</MsgId><CreDtTm>2025-01-02T15:30:00+01:00</CreDtTm></GrpHdr>
    <Stmt>
      <Id>STMT-1</Id>
      <ElctrncSeqNb>42</ElctrncSeqNb>
      <Acct><Id><IBAN>DE89370400440532013000</IBAN></Id><Ccy>EUR</Ccy></Acct>
      <Bal><Tp><CdOrPrtry><Cd>OPBD</Cd></CdOrPrtry></Tp><Amt Ccy="EUR">1000.00</Amt><CdtDbtInd>CRDT</CdtDbtInd><Dt><Dt>2025-01-01</Dt></Dt></Bal>
      <Bal><Tp><CdOrPrtry><Cd>CLBD</Cd></CdOrPrtry></Tp><Amt Ccy="EUR">1299.50</Amt><CdtDbtInd>CRDT</CdtDbtInd><Dt><Dt>2025-01-03</Dt></Dt></Bal>
      <Ntry>
        <Amt Ccy="EUR">500.00</Amt>
        <CdtDbtInd>CRDT</CdtDbtInd>
        <Sts>BOOK</Sts>
        <BookgDt><Dt>2025-01-02</Dt></BookgDt>
        <AcctSvcrRef>BREF-1</AcctSvcrRef>
        <BkTxCd><Domn><Cd>PMNT</Cd><Fmly><Cd>RCDT</Cd><SubFmlyCd>ESCT</SubFmlyCd></Fmly></Domn></BkTxCd>
        <AddtlNtryInf>Payment for services</AddtlNtryInf>
        <NtryDtls>
          <TxDtls>
            <Refs><EndToEndId>E2E-1</EndToEndId></Refs>
            <RltdPties><Dbtr><Nm>Acme Corp</Nm></Dbtr><DbtrAcct><Id><IBAN>DE02120300000000202051</IBAN></Id></DbtrAcct></RltdPties>
            <RmtInf><Ustrd>Invoice 42</Ustrd></RmtInf>
          </TxDtls>
        </NtryDtls>
      </Ntry>
      <Ntry>
        <Amt Ccy="EUR">200.50</Amt>
        <CdtDbtInd>DBIT</CdtDbtInd>
        <Sts>BOOK</Sts>
        <BookgDt><Dt>2025-01-03</Dt></BookgDt>
        <BkTxCd><Prtry><Cd>DEB01</Cd><Issr>BANK</Issr></Prtry></BkTxCd>
      </Ntry>
    </Stmt>
  </BkToCstmrStmt>
</Document>
""";

fn main() {
    let lim = bank_statement::default_limits();
    let opts = bank_statement::CamtOptions { .. };
    var sts: bank_statement::Statement[>..] = [];
    var ens: bank_statement::Entry[>..] = [];
    var bals: bank_statement::Balance[>..] = [];
    var buf: u8[>..] = [];
    var hd1 = bank_statement::CamtHeader { .. };
    let f = bank_statement::parse_camt(DOC, lim, opts, hd1, sts, ens, bals, buf);
    if f.kind != 0 {
        print("error: ", bank_statement::kind_name(f.kind), " ", f.tag, " ", f.detail);
        return 1;
    }
    print("message ", hd1.message_id, " kind ", hd1.kind, " entries ", hd1.entry_count);
    for st in sts {
        print("statement ", st.reference, " account ", st.account, " sequence ", st.sequence);
        print("  opening ", st.opening.amount.minor, " minor units ", st.opening.amount.currency, " code ", st.opening.code);
        print("  closing ", st.closing.amount.minor, " minor units code ", st.closing.code);
    }
    for e in ens {
        print("  ", e.mark, " ", e.amount.minor, " ", e.amount.currency, " ", e.type_id, " ", e.customer_ref);
        print("      counter ", e.counter_name, " ", e.counter_iban);
        print("      remittance ", e.remittance);
    }
    return 0;
}
