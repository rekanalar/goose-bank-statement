// The helpers and the globals that the tests share.
namespace common;

import std;
import os;
import xml from "rekanalar/goose-xml@v2.0.0";
import process from "rekanalar/goose-process@v1.0.0";
import bank_statement from "..";
import finance from "rekanalar/goose-finance@v0.1.0";
import common_2;

const STMT1: const u8[:] = "{1:F01BANKBEBBAXXX0000000000}{2:O9401234250101BANKDEFFAXXX00000000002501011234N}{4:\n:20:STMT001\n:25:DE89370400440532013000\n:28C:00001/001\n:60F:C250101EUR1000,00\n:61:2501020102C500,00NTRFNONREF//BANKREF1\nSUPPLEMENT\n:86:020?00BANK TRANSFER?20PURPOSE\n?21LINE 2?32JOHN DOE\n:61:250103D200,50NCHKCHK123\n:62F:C250103EUR1299,50\n:64:C250103EUR1299,50\n-}";
const QIF1: const u8[:] = "!Type:Bank\nD12/31'25\nT-1,234.56\nCX\nN1001\nPAcme Corp\nMInvoice\nLGroceries:Food/Home\nAStreet 1\nAtown\nZodd\n^\nD1/ 2'25\nT(50.00)\nSRent\nEhalf\n$-30.00\nSUtil\n$-20.00\n%40\n^\nD3/4/25\nT8.11";
const CAMT53: const u8[:] = """
<?xml version="1.0" encoding="UTF-8"?>
<Document xmlns="urn:iso:std:iso:20022:tech:xsd:camt.053.001.08">
  <BkToCstmrStmt>
    <GrpHdr><MsgId>MSG-1</MsgId><CreDtTm>2025-01-02T15:30:00+01:00</CreDtTm><NbOfTxs>3</NbOfTxs><AddtlInf>settlement daily</AddtlInf><InitgPty><Nm>Main St Ltd</Nm></InitgPty><MsgRcpt><Nm>Acme Corp</Nm></MsgRcpt></GrpHdr>
    <Stmt>
      <Id>STMT-1</Id>
      <ElctrncSeqNb>42</ElctrncSeqNb>
      <LglSeqNb>7</LglSeqNb>
      <CreDtTm>2025-01-02T15:30:00+01:00</CreDtTm>
      <FrToDt><FrDtTm>2025-01-01T00:00:00</FrDtTm><ToDtTm>2025-01-31T23:59:59</ToDtTm></FrToDt>
      <CpyDplctInd>CCPY</CpyDplctInd>
      <RptgSeq><FrToSeq><From>11</From><To>78</To></FrToSeq></RptgSeq>
      <RptgSrc><Cd>MLST</Cd></RptgSrc>
      <StmtPgntn><PgNb>2</PgNb><LastPgInd>true</LastPgInd></StmtPgntn>
      <Acct><Id><IBAN>DE89370400440532013000</IBAN></Id><Ccy>EUR</Ccy></Acct>
      <Bal><Tp><CdOrPrtry><Cd>OPBD</Cd></CdOrPrtry></Tp><Amt Ccy="EUR">1000.00</Amt><CdtDbtInd>CRDT</CdtDbtInd><Dt><Dt>2025-01-01</Dt></Dt></Bal>
      <Bal><Tp><CdOrPrtry><Cd>CLBD</Cd></CdOrPrtry></Tp><Amt Ccy="EUR">1700.00</Amt><CdtDbtInd>CRDT</CdtDbtInd><Dt><Dt>2025-01-02</Dt></Dt></Bal>
      <Bal><Tp><CdOrPrtry><Cd>CLAV</Cd></CdOrPrtry></Tp><Amt Ccy="EUR">1700.00</Amt><CdtDbtInd>CRDT</CdtDbtInd><Dt><Dt>2025-01-02</Dt></Dt></Bal>
      <Bal><Tp><CdOrPrtry><Cd>FWAV</Cd></CdOrPrtry></Tp><Amt Ccy="EUR">1800.00</Amt><CdtDbtInd>CRDT</CdtDbtInd><Dt><Dt>2025-02-01</Dt></Dt></Bal>
      <Bal><Tp><CdOrPrtry><Prtry>OWN1</Prtry></CdOrPrtry></Tp><Amt Ccy="EUR">900.00</Amt><CdtDbtInd>CRDT</CdtDbtInd></Bal>
      <Bal><Tp><CdOrPrtry><Cd>OPAV</Cd></CdOrPrtry></Tp><Amt Ccy="EUR">1000.00</Amt><CdtDbtInd>CRDT</CdtDbtInd></Bal>
      <Bal><Tp><CdOrPrtry><Cd>ITAV</Cd></CdOrPrtry></Tp><Amt Ccy="EUR">1200.00</Amt><CdtDbtInd>CRDT</CdtDbtInd></Bal>
      <Bal><Tp><CdOrPrtry><Cd>PRCD</Cd></CdOrPrtry></Tp><Amt Ccy="EUR">900.00</Amt><CdtDbtInd>CRDT</CdtDbtInd></Bal>
      <Bal><Tp><CdOrPrtry><Cd>XPCD</Cd></CdOrPrtry></Tp><Amt Ccy="EUR">800.00</Amt><CdtDbtInd>CRDT</CdtDbtInd></Bal>
      <Ntry>
        <Amt Ccy="EUR">500.00</Amt>
        <CdtDbtInd>CRDT</CdtDbtInd>
        <Sts><Cd>BOOK</Cd></Sts>
        <BookgDt><Dt>2025-01-02</Dt></BookgDt>
        <ValDt><Dt>2025-01-03</Dt></ValDt>
        <AcctSvcrRef>BREF-1</AcctSvcrRef>
        <NtryRef>EREF-1</NtryRef>
        <BkTxCd><Domn><Cd>PMNT</Cd><Fmly><Cd>RCDT</Cd><SubFmlyCd>ESCT</SubFmlyCd></Fmly></Domn></BkTxCd>
        <AddtlNtryInf>Payment for services</AddtlNtryInf>
        <NtryDtls>
          <Btch><MsgId>BATCH-1</MsgId><PmtInfId>PINF-1</PmtInfId><NbOfTxs>2</NbOfTxs><TtlAmt Ccy="EUR">700.00</TtlAmt></Btch>
          <TxDtls>
            <Refs><EndToEndId>E2E-1</EndToEndId><TxId>TX-1</TxId></Refs>
            <RltdPties><Dbtr><Pty><Nm>Acme Corp</Nm></Pty></Dbtr><DbtrAcct><Id><IBAN>DE02120300000000202051</IBAN></Id></DbtrAcct></RltdPties>
            <RmtInf><Ustrd>Invoice 42</Ustrd><Ustrd>Thanks</Ustrd></RmtInf>
          </TxDtls>
        </NtryDtls>
      </Ntry>
      <Ntry>
        <Amt Ccy="EUR">200.00</Amt>
        <CdtDbtInd>DBIT</CdtDbtInd>
        <RvslInd>true</RvslInd>
        <Sts><Cd>BOOK</Cd></Sts>
        <BookgDt><Dt>2025-01-02</Dt></BookgDt>
        <BkTxCd><Prtry><Cd>DEB01</Cd><Issr>BANK</Issr></Prtry></BkTxCd>
      </Ntry>
      <Ntry>
        <Amt Ccy="EUR">999.00</Amt>
        <CdtDbtInd>CRDT</CdtDbtInd>
        <Sts><Cd>PDNG</Cd></Sts>
        <BkTxCd><Domn><Cd>PMNT</Cd><Fmly><Cd>RCDT</Cd><SubFmlyCd>ESCT</SubFmlyCd></Fmly></Domn></BkTxCd>
      </Ntry>
      <TxsSummry><TtlNtries><NbOfNtries>3</NbOfNtries><Sum>700.00</Sum><TtlNetNtry><Amt Ccy="EUR">100.00</Amt><CdtDbtInd>CRDT</CdtDbtInd></TtlNetNtry></TtlNtries></TxsSummry>
    </Stmt>
  </BkToCstmrStmt>
</Document>
""";
const CAMT52: const u8[:] = """
<?xml version="1.0" encoding="UTF-8"?>
<Document xmlns="urn:iso:std:iso:20022:tech:xsd:camt.052.001.08">
  <BkToCstmrAcctRpt>
    <GrpHdr><MsgId>RPT-MSG</MsgId></GrpHdr>
    <Rpt>
      <Id>RPT-1</Id>
      <CreDtTm>2025-01-02T10:00:00Z</CreDtTm>
      <Acct><Id><Othr><Id>ACC-9</Id></Othr></Id></Acct>
      <Bal><Tp><CdOrPrtry><Cd>OPBD</Cd></CdOrPrtry></Tp><Amt Ccy="EUR">100.00</Amt><CdtDbtInd>CRDT</CdtDbtInd></Bal>
      <TxsSummry>
        <TtlNtries><NbOfNtries>2</NbOfNtries></TtlNtries>
        <TtlCdtNtries><NbOfNtries>1</NbOfNtries><Sum Ccy="EUR">500.00</Sum></TtlCdtNtries>
        <TtlDbtNtries><NbOfNtries>1</NbOfNtries><Sum Ccy="EUR">200.00</Sum></TtlDbtNtries>
      </TxsSummry>
      <Ntry><Amt Ccy="EUR">500.00</Amt><CdtDbtInd>CRDT</CdtDbtInd><Sts>BOOK</Sts><BkTxCd><Domn><Cd>PMNT</Cd><Fmly><Cd>RCDT</Cd><SubFmlyCd>ESCT</SubFmlyCd></Fmly></Domn></BkTxCd></Ntry>
      <Ntry><Amt Ccy="EUR">200.00</Amt><CdtDbtInd>DBIT</CdtDbtInd><Sts>BOOK</Sts><BkTxCd><Domn><Cd>PMNT</Cd><Fmly><Cd>ICDT</Cd><SubFmlyCd>ESCT</SubFmlyCd></Fmly></Domn></BkTxCd></Ntry>
    </Rpt>
  </BkToCstmrAcctRpt>
</Document>
""";
const CAMT54: const u8[:] = """
<?xml version="1.0" encoding="UTF-8"?>
<Document xmlns="urn:iso:std:iso:20022:tech:xsd:camt.054.001.04">
  <BkToCstmrDbtCdtNtfctn>
    <GrpHdr><MsgId>NTF-MSG</MsgId></GrpHdr>
    <Ntfctn>
      <Id>NTF-1</Id>
      <CreDtTm>2019-04-24T21:28:58</CreDtTm>
      <Acct><Id><IBAN>CH2909000000250094239</IBAN></Id></Acct>
      <Ntry>
        <Amt Ccy="CHF">1500.00</Amt>
        <CdtDbtInd>CRDT</CdtDbtInd>
        <RvslInd>false</RvslInd>
        <Sts>BOOK</Sts>
        <BookgDt><Dt>2019-04-24</Dt></BookgDt>
        <ValDt><Dt>2019-04-25</Dt></ValDt>
        <AcctSvcrRef>074820002ZZ9J42U</AcctSvcrRef>
        <BkTxCd><Domn><Cd>PMNT</Cd><Fmly><Cd>RCDT</Cd><SubFmlyCd>VCOM</SubFmlyCd></Fmly></Domn></BkTxCd>
        <NtryDtls><TxDtls><Refs><AcctSvcrRef>074820002ZZ9J42U</AcctSvcrRef></Refs><Amt Ccy="CHF">1500.00</Amt><CdtDbtInd>CRDT</CdtDbtInd></TxDtls></NtryDtls>
        <AddtlNtryInf>SAMMELGUTSCHRIFT</AddtlNtryInf>
      </Ntry>
    </Ntfctn>
  </BkToCstmrDbtCdtNtfctn>
</Document>
""";
const CAMT02: const u8[:] = """
<?xml version="1.0" encoding="UTF-8"?>
<Document xmlns="urn:iso:std:iso:20022:tech:xsd:camt.053.001.02">
  <BkToCstmrStmt>
    <GrpHdr><MsgId>OLD-1</MsgId></GrpHdr>
    <Stmt>
      <Id>OLD-STMT</Id>
      <CreDtTm>2013-05-06T08:00:00</CreDtTm>
      <Acct><Id><Othr><Id>OLD-ACC</Id></Othr></Id></Acct>
      <Bal><Tp><CdOrPrtry><Cd>OPBD</Cd></CdOrPrtry></Tp><Amt Ccy="EUR">0.00</Amt><CdtDbtInd>CRDT</CdtDbtInd></Bal>
      <Bal><Tp><CdOrPrtry><Cd>CLBD</Cd></CdOrPrtry></Tp><Amt Ccy="EUR">100.00</Amt><CdtDbtInd>CRDT</CdtDbtInd></Bal>
      <Ntry>
        <Amt Ccy="EUR">100.00</Amt>
        <CdtDbtInd>CRDT</CdtDbtInd>
        <Sts>BOOK</Sts>
        <BookgDt><Dt>2013-05-06</Dt></BookgDt>
        <BkTxCd><Domn><Cd>PMNT</Cd><Fmly><Cd>RCDT</Cd><SubFmlyCd>ESCT</SubFmlyCd></Fmly></Domn></BkTxCd>
        <NtryDtls><TxDtls><RltdPties><Dbtr><Nm>Old Corp</Nm></Dbtr></RltdPties></TxDtls></NtryDtls>
      </Ntry>
    </Stmt>
  </BkToCstmrStmt>
</Document>
""";
const CAMTPREFIX: const u8[:] = """
<?xml version="1.0" encoding="UTF-8"?>
<camt:Document xmlns:camt="urn:iso:std:iso:20022:tech:xsd:camt.053.001.08">
  <camt:BkToCstmrStmt>
    <camt:GrpHdr><camt:MsgId>P-1</camt:MsgId></camt:GrpHdr>
    <camt:Stmt>
      <camt:Id>P-STMT</camt:Id>
      <camt:Bal><camt:Tp><camt:CdOrPrtry><camt:Cd>OPBD</camt:Cd></camt:CdOrPrtry></camt:Tp><camt:Amt Ccy="EUR">0.00</camt:Amt><camt:CdtDbtInd>CRDT</camt:CdtDbtInd></camt:Bal>
      <camt:Bal><camt:Tp><camt:CdOrPrtry><camt:Cd>CLBD</camt:Cd></camt:CdOrPrtry></camt:Tp><camt:Amt Ccy="EUR">0.00</camt:Amt><camt:CdtDbtInd>CRDT</camt:CdtDbtInd></camt:Bal>
    </camt:Stmt>
  </camt:BkToCstmrStmt>
</camt:Document>
""";
const REAL52: const u8[:] = """
<?xml version="1.0" encoding="UTF-8"?>
<Document xmlns="urn:iso:std:iso:20022:tech:xsd:camt.052.001.04" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="urn:iso:std:iso:20022:tech:xsd:camt.052.001.04 file:///C:/Users/alihodzica/Desktop/camt.052/camt.052.001.04.xsd">
	<BkToCstmrAcctRpt>
		<GrpHdr>
			<MsgId>20190424375204223062173</MsgId>
			<CreDtTm>2019-04-24T16:07:09</CreDtTm>
			<MsgPgntn>
				<PgNb>1</PgNb>
				<LastPgInd>true</LastPgInd>
			</MsgPgntn>
			<AddtlInf>SPS/1.6/PROD</AddtlInf>
		</GrpHdr>
		<Rpt>
			<Id>20190424375204223062174</Id>
			<ElctrncSeqNb>78</ElctrncSeqNb>
			<CreDtTm>2019-04-24T16:07:09</CreDtTm>
			<FrToDt>
				<FrDtTm>2019-04-24T00:00:00</FrDtTm>
				<ToDtTm>2019-04-24T16:00:00</ToDtTm>
			</FrToDt>
			<Acct>
				<Id>
					<IBAN>CH2909000000250094239</IBAN>
				</Id>
				<Ownr>
					<Nm>Robert Schneider SA Grands magasins Biel/Bienne</Nm>
				</Ownr>
			</Acct>
			<Bal>
				<Tp>
					<CdOrPrtry>
						<Cd>OPBD</Cd>
					</CdOrPrtry>
				</Tp>
				<Amt Ccy="CHF">208509.19</Amt>
				<CdtDbtInd>CRDT</CdtDbtInd>
				<Dt>
					<Dt>2019-04-24</Dt>
				</Dt>
			</Bal>
			<Bal>
				<Tp>
					<CdOrPrtry>
						<Cd>ITBD</Cd>
					</CdOrPrtry>
				</Tp>
				<Amt Ccy="CHF">207596.19</Amt>
				<CdtDbtInd>CRDT</CdtDbtInd>
				<Dt>
					<Dt>2019-04-24</Dt>
				</Dt>
			</Bal>
			<Ntry>
				<Amt Ccy="CHF">103.00</Amt>
				<CdtDbtInd>DBIT</CdtDbtInd>
				<RvslInd>false</RvslInd>
				<Sts>BOOK</Sts>
				<BookgDt>
					<Dt>2019-04-24</Dt>
				</BookgDt>
				<ValDt>
					<Dt>2019-04-24</Dt>
				</ValDt>
				<AcctSvcrRef>074820002ZU1EPZK</AcctSvcrRef>
				<BkTxCd>
					<Domn>
						<Cd>PMNT</Cd>
						<Fmly>
							<Cd>ICDT</Cd>
							<SubFmlyCd>AUTT</SubFmlyCd>
						</Fmly>
					</Domn>
				</BkTxCd>
				<NtryDtls>
					<TxDtls>
						<Refs>
							<MsgId>20190423-000369773</MsgId>
							<AcctSvcrRef>25-1120172999-1</AcctSvcrRef>
							<PmtInfId>30003101</PmtInfId>
							<EndToEndId>20190423001255000100005</EndToEndId>
						</Refs>
						<Amt Ccy="CHF">103.00</Amt>
						<CdtDbtInd>DBIT</CdtDbtInd>
					</TxDtls>
				</NtryDtls>
				<AddtlNtryInf>GIRO POST CH5109000000250092291 Bernasconi Maria Place de la Gare 12 2502 Biel/Bienne SENDER REFERENZ: 30003101</AddtlNtryInf>
			</Ntry>
			<Ntry>
				<Amt Ccy="CHF">913.00</Amt>
				<CdtDbtInd>DBIT</CdtDbtInd>
				<RvslInd>false</RvslInd>
				<Sts>BOOK</Sts>
				<BookgDt>
					<Dt>2019-04-24</Dt>
				</BookgDt>
				<ValDt>
					<Dt>2019-04-24</Dt>
				</ValDt>
				<AcctSvcrRef>074820002ZU1EQ0K</AcctSvcrRef>
				<BkTxCd>
					<Domn>
						<Cd>PMNT</Cd>
						<Fmly>
							<Cd>ICDT</Cd>
							<SubFmlyCd>AUTT</SubFmlyCd>
						</Fmly>
					</Domn>
				</BkTxCd>
				<NtryDtls>
					<TxDtls>
						<Refs>
							<MsgId>20190423-000369773</MsgId>
							<AcctSvcrRef>25-1120172999-2</AcctSvcrRef>
							<PmtInfId>30003101</PmtInfId>
							<EndToEndId>20190423001255000100006</EndToEndId>
						</Refs>
						<Amt Ccy="CHF">913.00</Amt>
						<CdtDbtInd>DBIT</CdtDbtInd>
					</TxDtls>
				</NtryDtls>
				<AddtlNtryInf>GIRO POST CH5109000000250092291 Bernasconi Maria Place de la Gare 12 2502 Biel/Bienne SENDER REFERENZ: 30003101</AddtlNtryInf>
			</Ntry>
		</Rpt>
	</BkToCstmrAcctRpt>
</Document>
""";
const REAL53: const u8[:] = """
<?xml version="1.0" encoding="UTF-8"?>
<Document xmlns="urn:iso:std:iso:20022:tech:xsd:camt.053.001.04" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="urn:iso:std:iso:20022:tech:xsd:camt.053.001.04">
	<BkToCstmrStmt>
		<GrpHdr>
			<MsgId>20201124375204229003967</MsgId>
			<CreDtTm>2020-11-25T02:02:16</CreDtTm>
			<MsgPgntn>
				<PgNb>1</PgNb>
				<LastPgInd>true</LastPgInd>
			</MsgPgntn>
			<AddtlInf>SPS/1.7/PROD</AddtlInf>
		</GrpHdr>
		<Stmt>
			<Id>20201124375204229003973</Id>
			<ElctrncSeqNb>118</ElctrncSeqNb>
			<CreDtTm>2020-11-25T02:02:16</CreDtTm>
			<FrToDt>
				<FrDtTm>2020-06-24T00:00:00</FrDtTm>
				<ToDtTm>2020-06-24T23:59:59</ToDtTm>
			</FrToDt>
			<Acct>
				<Id>
					<IBAN>CH2909000000250094239</IBAN>
				</Id>
				<Ownr>
					<Nm>Robert Schneider SA Grands magasins Biel/Bienne</Nm>
				</Ownr>
			</Acct>
			<Bal>
				<Tp>
					<CdOrPrtry>
						<Cd>OPBD</Cd>
					</CdOrPrtry>
				</Tp>
				<Amt Ccy="CHF">211993.19</Amt>
				<CdtDbtInd>CRDT</CdtDbtInd>
				<Dt>
					<Dt>2020-11-24</Dt>
				</Dt>
			</Bal>
			<Bal>
				<Tp>
					<CdOrPrtry>
						<Cd>CLBD</Cd>
					</CdOrPrtry>
				</Tp>
				<Amt Ccy="CHF">215112.21</Amt>
				<CdtDbtInd>CRDT</CdtDbtInd>
				<Dt>
					<Dt>2020-11-24</Dt>
				</Dt>
			</Bal>
			<Bal>
				<Tp>
					<CdOrPrtry>
						<Cd>CLAV</Cd>
					</CdOrPrtry>
				</Tp>
				<Amt Ccy="CHF">215112.21</Amt>
				<CdtDbtInd>CRDT</CdtDbtInd>
				<Dt>
					<Dt>2020-11-24</Dt>
				</Dt>
			</Bal>
			<Bal>
				<Tp>
					<CdOrPrtry>
						<Cd>FWAV</Cd>
					</CdOrPrtry>
				</Tp>
				<Amt Ccy="CHF">216649.21</Amt>
				<CdtDbtInd>CRDT</CdtDbtInd>
				<Dt>
					<Dt>2020-11-25</Dt>
				</Dt>
			</Bal>
			<Ntry>
				<NtryRef>41100000000872849</NtryRef>
				<Amt Ccy="CHF">4.50</Amt>
				<CdtDbtInd>CRDT</CdtDbtInd>
				<RvslInd>false</RvslInd>
				<Sts>BOOK</Sts>
				<BookgDt>
					<Dt>2020-11-24</Dt>
				</BookgDt>
				<ValDt>
					<Dt>2020-11-24</Dt>
				</ValDt>
				<AcctSvcrRef>0758103031480900</AcctSvcrRef>
				<BkTxCd>
					<Domn>
						<Cd>PMNT</Cd>
						<Fmly>
							<Cd>IDDT</Cd>
							<SubFmlyCd>PMDD</SubFmlyCd>
						</Fmly>
					</Domn>
				</BkTxCd>
				<NtryDtls>
					<TxDtls>
						<Refs>
							<AcctSvcrRef>0758103031480900</AcctSvcrRef>
						</Refs>
						<Amt Ccy="CHF">4.50</Amt>
						<CdtDbtInd>CRDT</CdtDbtInd>
					</TxDtls>
				</NtryDtls>
				<AddtlNtryInf>GUTSCHRIFT CH-DD-BASISLASTSCHRIFT ID-NR. DES ZAHLUNGSEMPFÄNGERS: 41100000000872849 REFERENZ-NR: PmtInfId-CHDD-1</AddtlNtryInf>
			</Ntry>
			<Ntry>
				<Amt Ccy="CHF">77.70</Amt>
				<CdtDbtInd>DBIT</CdtDbtInd>
				<RvslInd>false</RvslInd>
				<Sts>BOOK</Sts>
				<BookgDt>
					<Dt>2020-11-24</Dt>
				</BookgDt>
				<ValDt>
					<Dt>2020-11-24</Dt>
				</ValDt>
				<AcctSvcrRef>0758103031480977</AcctSvcrRef>
				<BkTxCd>
					<Domn>
						<Cd>PMNT</Cd>
						<Fmly>
							<Cd>ICDT</Cd>
							<SubFmlyCd>AUTT</SubFmlyCd>
						</Fmly>
					</Domn>
				</BkTxCd>
				<NtryDtls>
					<TxDtls>
						<Refs>
							<AcctSvcrRef>0758103031480977</AcctSvcrRef>
						</Refs>
						<Amt Ccy="CHF">77.70</Amt>
						<CdtDbtInd>CRDT</CdtDbtInd>
					</TxDtls>
				</NtryDtls>
				<AddtlNtryInf>GUTSCHRIFT CH-DD-BASISLASTSCHRIFT ID-NR. DES ZAHLUNGSEMPFÄNGERS: 41100000000872849 REFERENZ-NR: PmtInfId-CHDD-1</AddtlNtryInf>
			</Ntry>
			<Ntry>
				<Amt Ccy="CHF">1500.00</Amt>
				<CdtDbtInd>CRDT</CdtDbtInd>
				<RvslInd>false</RvslInd>
				<Sts>BOOK</Sts>
				<BookgDt>
					<Dt>2020-11-24</Dt>
				</BookgDt>
				<ValDt>
					<Dt>2020-11-24</Dt>
				</ValDt>
				<AcctSvcrRef>07582000303F0C7U</AcctSvcrRef>
				<BkTxCd>
					<Domn>
						<Cd>PMNT</Cd>
						<Fmly>
							<Cd>RCDT</Cd>
							<SubFmlyCd>AUTT</SubFmlyCd>
						</Fmly>
					</Domn>
				</BkTxCd>
				<NtryDtls>
					<TxDtls>
						<Refs>
							<AcctSvcrRef>07582000303F0C7U</AcctSvcrRef>
						</Refs>
						<Amt Ccy="CHF">1500.00</Amt>
						<CdtDbtInd>CRDT</CdtDbtInd>
					</TxDtls>
				</NtryDtls>
				<AddtlNtryInf>SAMMELGUTSCHRIFT FÜR KONTO: CH2909000000250094239 VERARBEITUNG VOM 23.11.2020 PAKET ID: 9999999999999999</AddtlNtryInf>
			</Ntry>
			<Ntry>
				<NtryRef>014295803</NtryRef>
				<Amt Ccy="CHF">1537.00</Amt>
				<CdtDbtInd>CRDT</CdtDbtInd>
				<RvslInd>false</RvslInd>
				<Sts>BOOK</Sts>
				<BookgDt>
					<Dt>2020-11-24</Dt>
				</BookgDt>
				<ValDt>
					<Dt>2020-11-25</Dt>
				</ValDt>
				<AcctSvcrRef>07582000303KBMSU</AcctSvcrRef>
				<BkTxCd>
					<Domn>
						<Cd>PMNT</Cd>
						<Fmly>
							<Cd>RCDT</Cd>
							<SubFmlyCd>VCOM</SubFmlyCd>
						</Fmly>
					</Domn>
				</BkTxCd>
				<NtryDtls>
					<TxDtls>
						<Refs>
							<AcctSvcrRef>07582000303KBMSU</AcctSvcrRef>
						</Refs>
						<Amt Ccy="CHF">1537.00</Amt>
						<CdtDbtInd>CRDT</CdtDbtInd>
					</TxDtls>
				</NtryDtls>
				<AddtlNtryInf>SAMMELGUTSCHRIFT ESR VERARBEITUNG VOM 24.11.2020 KUNDENNUMMER 01-429580-3 PAKET ID: 201124CH00000UR0</AddtlNtryInf>
			</Ntry>
			<Ntry>
				<NtryRef>CH7730000001250094239</NtryRef>
				<Amt Ccy="CHF">1692.22</Amt>
				<CdtDbtInd>CRDT</CdtDbtInd>
				<RvslInd>false</RvslInd>
				<Sts>BOOK</Sts>
				<BookgDt>
					<Dt>2020-11-24</Dt>
				</BookgDt>
				<ValDt>
					<Dt>2020-11-24</Dt>
				</ValDt>
				<AcctSvcrRef>07582000303KBMSU</AcctSvcrRef>
				<BkTxCd>
					<Domn>
						<Cd>PMNT</Cd>
						<Fmly>
							<Cd>RCDT</Cd>
							<SubFmlyCd>VCOM</SubFmlyCd>
						</Fmly>
					</Domn>
				</BkTxCd>
				<NtryDtls>
					<TxDtls>
						<Refs>
							<AcctSvcrRef>07582000303KBMSU</AcctSvcrRef>
						</Refs>
						<Amt Ccy="CHF">1692.22</Amt>
						<CdtDbtInd>CRDT</CdtDbtInd>
					</TxDtls>
				</NtryDtls>
				<AddtlNtryInf>SAMMELGUTSCHRIFT FÜR KONTO: CH7730000001250094239 VERARBEITUNG VOM 24.11.2020 PAKET ID: 201124CH000009TB</AddtlNtryInf>
			</Ntry>
		</Stmt>
	</BkToCstmrStmt>
</Document>
""";

fn expect_amount(text: const u8[:], exp: i32, dec: u8, grp: u8, want: i64) {
    let a, f = bank_statement::parse_amount(text, exp, dec, grp);
    if f.kind != 0 || a.minor != want {
        print("FAIL amount ", text, " got ", a.minor, " fault ", bank_statement::kind_name(f.kind), "\n");
    }
    assert(f.kind == 0);
    assert(a.minor == want);
}

fn expect_amount_fault(text: const u8[:], exp: i32, dec: u8, grp: u8, kind: i32) {
    let a, f = bank_statement::parse_amount(text, exp, dec, grp);
    if f.kind != kind { print("FAIL amount fault ", text, " got ", bank_statement::kind_name(f.kind), "\n"); }
    assert(f.kind == kind);
}

// parse_kind parses text and gives the fault. The buffer holds the
// decoded text when the option names a charset.
fn parse_kind(text: const u8[:], lim: bank_statement::Limits&, skip: bool, buf: u8[>..]&) -> bank_statement::Fault {
    let opts = bank_statement::Mt940Options { skip_balance_check: skip, check_fields: false, style: 0 };
    var sts: bank_statement::Statement[>..] = [];
    var ens: bank_statement::Entry[>..] = [];
    var bals: bank_statement::Balance[>..] = [];
    var notes: bank_statement::Note[>..] = [];
    return bank_statement::parse_mt940(text, lim, opts, sts, ens, bals, notes, buf);
}

fn run_mt940(text: const u8[:], skip: bool, kind: i32, tag: const u8[:]) {
    let lim = bank_statement::default_limits();
    var rbuf: u8[>..] = [];
    let f = parse_kind(text, lim, skip, rbuf);
    if f.kind != kind || f.tag != tag {
        print("FAIL mt940 want ", bank_statement::kind_name(kind), " got ", bank_statement::kind_name(f.kind), " line ", f.line, " tag ", f.tag, " ", f.detail);
    }
    assert(f.kind == kind);
    assert(f.tag == tag);
}

fn run_qif(text: const u8[:], order: i32, kind: i32) {
    let lim = bank_statement::default_limits();
    let opts = bank_statement::QifOptions { date_order: order, .. };
    var recs: bank_statement::QifRecord[>..] = [];
    var spl: bank_statement::QifSplit[>..] = [];
    var ext: bank_statement::QifField[>..] = [];
    var xbuf8: u8[>..] = [];
    let f = bank_statement::parse_qif(text, lim, opts, recs, spl, ext, xbuf8);
    if f.kind != kind { print("FAIL qif want ", bank_statement::kind_name(kind), " got ", bank_statement::kind_name(f.kind), " line ", f.line, " ", f.detail, "\n"); }
    assert(f.kind == kind);
}

fn run_limited(text: const u8[:], lim: bank_statement::Limits&, kind: i32) {
    var rbuf: u8[>..] = [];
    let f = parse_kind(text, lim, true, rbuf);
    if f.kind != kind { print("FAIL limit want ", bank_statement::kind_name(kind), " got ", bank_statement::kind_name(f.kind), " ", f.detail); }
    assert(f.kind == kind);
}

// build_statement writes a statement with n entries of 1,00 each.
fn build_statement(out: u8[>..]&, n: i64) {
    format(out, ":20:BIG\n:60F:C250101EUR0,00\n");
    for i in n { format(out, ":61:250102C1,00NTRFREF", i, "\n:86:note\n"); }
    format(out, ":62F:C250102EUR", n, ",00\n");
}

fn time_parse(n: i64) -> i64 {
    var text: u8[>..] = [];
    build_statement(text, n);
    let lim = bank_statement::default_limits();
    let opts = bank_statement::Mt940Options { .. };
    var sts: bank_statement::Statement[>..] = [];
    var ens: bank_statement::Entry[>..] = [];
    var bals: bank_statement::Balance[>..] = [];
    var notes: bank_statement::Note[>..] = [];
    let t0 = clock_ns();
    var xbuf27: u8[>..] = [];
    let f = bank_statement::parse_mt940(text[..], lim, opts, sts, ens, bals, notes, xbuf27);
    let t1 = clock_ns();
    assert(f.kind == 0);
    assert(ens.len == n);
    return t1 - t0;
}

// run_camt parses a camt document and gives the fault.
fn run_camt(text: const u8[:], skip: bool, kind: i32) {
    let lim = bank_statement::default_limits();
    let opts = bank_statement::CamtOptions { skip_balance_check: skip };
    var sts: bank_statement::Statement[>..] = [];
    var ens: bank_statement::Entry[>..] = [];
    var bals: bank_statement::Balance[>..] = [];
    var buf: u8[>..] = [];
    var hd1 = bank_statement::CamtHeader { .. };
    let f = bank_statement::parse_camt(text, lim, opts, hd1, sts, ens, bals, buf);
    if f.kind != kind { print("FAIL camt want ", bank_statement::kind_name(kind), " got ", bank_statement::kind_name(f.kind), " ", f.tag, " ", f.detail, "\n"); }
    assert(f.kind == kind);
}

// run_ofx parses an OFX file and gives the fault.
fn run_ofx(text: const u8[:], kind: i32) {
    let lim = bank_statement::default_limits();
    let opts = bank_statement::OfxOptions { .. };
    var sts: bank_statement::Statement[>..] = [];
    var ens: bank_statement::Entry[>..] = [];
    var bals: bank_statement::Balance[>..] = [];
    var notes: bank_statement::Note[>..] = [];
    var buf: u8[>..] = [];
    let f = bank_statement::parse_ofx(text, lim, opts, sts, ens, bals, notes, buf);
    if f.kind != kind {
        print("FAIL ofx want ", bank_statement::kind_name(kind), " got ", bank_statement::kind_name(f.kind), " ", f.tag, " ", f.detail, "\n");
    }
    assert(f.kind == kind);
}

// build_ofx_date writes a file with one entry and the given date.
fn build_ofx_date(date_text: const u8[:], out: u8[>..]&) {
    format(out, "OFXHEADER:100\nDATA:OFXSGML\nVERSION:102\nSECURITY:NONE\nENCODING:USASCII\nCHARSET:1252\nCOMPRESSION:NONE\nOLDFILEUID:NONE\nNEWFILEUID:NONE\n\n<OFX><BANKMSGSRSV1><STMTTRNRS><TRNUID>1<STMTRS><CURDEF>USD<BANKACCTFROM><BANKID>1<ACCTID>2<ACCTTYPE>CHECKING</BANKACCTFROM><BANKTRANLIST><STMTTRN><TRNTYPE>CHECK<DTPOSTED>");
    out.append(date_text);
    format(out, "</DTPOSTED><TRNAMT>1.00<FITID>X</STMTTRN></BANKTRANLIST><LEDGERBAL><BALAMT>1.00<DTASOF>20200101</LEDGERBAL></STMTRS></STMTTRNRS></BANKMSGSRSV1></OFX>");
}

// ofx_date_fault gives the fault of a file with one entry and the
// given date.
fn ofx_date_fault(date_text: const u8[:]) -> i32 {
    let lim = bank_statement::default_limits();
    let opts = bank_statement::OfxOptions { .. };
    var text: u8[>..] = [];
    build_ofx_date(date_text, text);
    var sts: bank_statement::Statement[>..] = [];
    var ens: bank_statement::Entry[>..] = [];
    var bals: bank_statement::Balance[>..] = [];
    var notes: bank_statement::Note[>..] = [];
    var buf: u8[>..] = [];
    let f = bank_statement::parse_ofx(text[..], lim, opts, sts, ens, bals, notes, buf);
    return f.kind;
}

// fk parses text with the field rules on and gives the kind of the
// fault only.
fn fk(text: const u8[:]) -> i32 {
    var rbuf: u8[>..] = [];
    return fields_kind(text, rbuf).kind;
}

// fields_kind parses text with the field rules on and gives the fault.
// The buffer holds the decoded text when the option names a charset.
fn fields_kind(text: const u8[:], buf: u8[>..]&) -> bank_statement::Fault {
    let lim = bank_statement::default_limits();
    let opts = bank_statement::Mt940Options { skip_balance_check: false, check_fields: true, style: 0 };
    var sts: bank_statement::Statement[>..] = [];
    var ens: bank_statement::Entry[>..] = [];
    var bals: bank_statement::Balance[>..] = [];
    var notes: bank_statement::Note[>..] = [];
    return bank_statement::parse_mt940(text, lim, opts, sts, ens, bals, notes, buf);
}

fn expect_fields(text: const u8[:], kind: i32, tag: const u8[:]) {
    var rbuf: u8[>..] = [];
    let f = fields_kind(text, rbuf);
    if f.kind != kind || f.tag != tag {
        print("FAIL fields want ", bank_statement::kind_name(kind), " ", tag, " got ", bank_statement::kind_name(f.kind), " line ", f.line, " tag ", f.tag, " ", f.detail, "\n");
    }
    assert(f.kind == kind);
    assert(f.tag == tag);
}

// fill gives n copies of the letter c.
fn fill(c: u8, n: i64, out: u8[>..]&) {
    var i = 0;
    while i < n { out.push(c); i += 1; }
}

// stmt_with builds a small statement whose :20: and :25: take the given text.
fn stmt_with(ref20: const u8[:], acct: const u8[:], out: u8[>..]&) {
    format(out, ":20:"); format(out, ref20);
    format(out, "\n:25:"); format(out, acct);
    format(out, "\n:28C:1/1\n:60F:C250101EUR1,00\n:62F:C250101EUR1,00\n");
}

// dialect_value gives the value of a key of the dialect, or an empty
// text when the dialect has no such key.
fn dialect_value(vals: bank_statement::DialectValue[>..]&, key: const u8[:]) -> const u8[:] {
    for v in vals {
        if v.key == key { return v.value; }
    }
    return "";
}

// dialect_run reads the text with the dialect and gives the values.
// The buffer of the caller holds the text that the values point at, so
// the buffer must live as long as the values.
fn dialect_run(kind: i32, text: const u8[:], vals: bank_statement::DialectValue[>..]&, buf: u8[>..]&) -> bank_statement::Fault {
    let lim = bank_statement::default_limits();
    return bank_statement::parse_dialect(kind, text, lim, vals, buf);
}

fn style_kind(style: i32, cref: const u8[:], bref: const u8[:]) -> i32 {
    var text: u8[>..] = [];
    format(text, ":20:S\n:25:A\n:28C:1/1\n:60F:C250101EUR1,00\n:61:250102C1,00NTRF");
    format(text, cref);
    if bref.len > 0 { format(text, "//"); format(text, bref); }
    format(text, "\n:62F:C250102EUR2,00\n");
    let lim = bank_statement::default_limits();
    let opts = bank_statement::Mt940Options { skip_balance_check: false, check_fields: true, style: style };
    var sts: bank_statement::Statement[>..] = [];
    var ens: bank_statement::Entry[>..] = [];
    var bals: bank_statement::Balance[>..] = [];
    var notes: bank_statement::Note[>..] = [];
    var xbuf29: u8[>..] = [];
    return bank_statement::parse_mt940(text, lim, opts, sts, ens, bals, notes, xbuf29).kind;
}

fn same_record(a: bank_statement::QifRecord, b: bank_statement::QifRecord) {
    assert(a.section == b.section);
    assert(a.date.year == b.date.year && a.date.month == b.date.month && a.date.day == b.date.day);
    assert(a.has_amount == b.has_amount && a.amount.minor == b.amount.minor);
    assert(a.cleared == b.cleared && a.number == b.number && a.payee == b.payee);
    assert(a.memo == b.memo && a.category == b.category);
    assert(a.split_count == b.split_count && a.field_count == b.field_count);
}

fn qif_round_trip(order: i32) {
    let lim = bank_statement::default_limits();
    let ropts = bank_statement::QifOptions { date_order: bank_statement::DATE_MDY, .. };
    var recs: bank_statement::QifRecord[>..] = [];
    var spl: bank_statement::QifSplit[>..] = [];
    var ext: bank_statement::QifField[>..] = [];
    var xbuf30: u8[>..] = [];
    let f = bank_statement::parse_qif(QIF1, lim, ropts, recs, spl, ext, xbuf30);
    assert(f.kind == 0);
    var out: u8[>..] = [];
    let wopts = bank_statement::QifWriteOptions { date_order: order };
    let w = bank_statement::write_qif(recs, spl, ext, wopts, lim, out);
    if w.kind != 0 { print("FAIL qif write ", bank_statement::kind_name(w.kind), " ", w.detail, "\n"); }
    assert(w.kind == 0);
    var o2 = order;
    if o2 == 0 { o2 = bank_statement::DATE_MDY; }
    let popts = bank_statement::QifOptions { date_order: o2, .. };
    var recs2: bank_statement::QifRecord[>..] = [];
    var spl2: bank_statement::QifSplit[>..] = [];
    var ext2: bank_statement::QifField[>..] = [];
    var xbuf31: u8[>..] = [];
    let g = bank_statement::parse_qif(out, lim, popts, recs2, spl2, ext2, xbuf31);
    if g.kind != 0 { print("FAIL qif reread ", bank_statement::kind_name(g.kind), " ", g.detail, " line ", g.line, "\n"); }
    assert(g.kind == 0);
    assert(recs2.len == recs.len);
    var i = 0;
    while i < recs.len { same_record(recs[i], recs2[i]); i += 1; }
    assert(spl2.len == spl.len && ext2.len == ext.len);
    assert(spl2[0].category == spl[0].category && spl2[0].amount.minor == spl[0].amount.minor);
    assert(ext2[0].value == ext[0].value);
}

fn ofx_wopts(version: i32) -> bank_statement::OfxWriteOptions {
    return bank_statement::OfxWriteOptions {
        version: version, credit_card: false, close_leaves: false, indent: false,
        server_date: bank_statement::Date { year: 2020, month: 2, day: 1 },
        org: "TESTBANK", fid: "12345", bank_id: "", account_type: "", currency: "", loose_elements: false,
    };
}

fn same_entry(a: bank_statement::Entry, b: bank_statement::Entry) {
    assert(a.mark == b.mark && a.amount.minor == b.amount.minor && a.amount.currency == b.amount.currency);
    assert(a.type_id == b.type_id && a.entry_ref == b.entry_ref && a.customer_ref == b.customer_ref);
    assert(a.counter_name == b.counter_name && a.narrative == b.narrative);
    assert(a.value_date.year == b.value_date.year && a.value_date.month == b.value_date.month);
    assert(a.value_date.day == b.value_date.day);
}

// ofx_round_trip writes the sample, reads it back and compares.
fn ofx_round_trip(opts: bank_statement::OfxWriteOptions) {
    let lim = bank_statement::default_limits();
    let ropts = bank_statement::OfxOptions { .. };
    var sts: bank_statement::Statement[>..] = [];
    var ens: bank_statement::Entry[>..] = [];
    var bals: bank_statement::Balance[>..] = [];
    var notes: bank_statement::Note[>..] = [];
    var buf: u8[>..] = [];
    assert(bank_statement::parse_ofx(common_2::OFX_V1, lim, ropts, sts, ens, bals, notes, buf).kind == 0);
    var out: u8[>..] = [];
    let w = bank_statement::write_ofx(sts, ens, notes, opts, lim, out);
    if w.kind != 0 { print("FAIL ofx write ", bank_statement::kind_name(w.kind), " ", w.tag, " ", w.detail, "\n"); }
    assert(w.kind == 0);
    var sts2: bank_statement::Statement[>..] = [];
    var ens2: bank_statement::Entry[>..] = [];
    var bals2: bank_statement::Balance[>..] = [];
    var notes2: bank_statement::Note[>..] = [];
    var buf2: u8[>..] = [];
    let g = bank_statement::parse_ofx(out, lim, ropts, sts2, ens2, bals2, notes2, buf2);
    if g.kind != 0 { print("FAIL ofx reread ", bank_statement::kind_name(g.kind), " ", g.tag, " ", g.detail, "\n"); }
    assert(g.kind == 0);
    assert(sts2.len == 1 && ens2.len == 2);
    assert(sts2[0].account == "999999" && sts2[0].reference == "1");
    same_entry(ens[0], ens2[0]);
    same_entry(ens[1], ens2[1]);
    assert(sts2[0].closing.amount.minor == 113456 && sts2[0].available.amount.minor == 113456);
    assert(sts2[0].closing.date.day == 31);
}

fn tree_node(depth: i32, name: const u8[:], text: const u8[:]) -> bank_statement::OfxNode {
    return bank_statement::OfxNode { depth: depth, name: name, text: text };
}

// ofx_wopts_loose gives options that skip the element rules. The writer
// then checks only the names, the depths and the texts.
fn ofx_wopts_loose() -> bank_statement::OfxWriteOptions {
    var o = ofx_wopts(102);
    o.loose_elements = true;
    return o;
}

// run_tree_write writes a tree with the options and gives the fault.
fn run_tree_write(tree: bank_statement::OfxNode[>..]&, opts: bank_statement::OfxWriteOptions) -> i32 {
    let lim = bank_statement::default_limits();
    var out: u8[>..] = [];
    return bank_statement::write_ofx_tree(tree, opts, lim, out).kind;
}

fn extra_equal(a: bank_statement::Entry, b: bank_statement::Entry) {
    let x = a.ofx;
    let y = b.ofx;
    assert(x.user_date.day == y.user_date.day && x.user_date.year == y.user_date.year);
    assert(x.correct_ref == y.correct_ref && x.correct_action == y.correct_action);
    assert(x.payee_id == y.payee_id && x.ext_name == y.ext_name);
    assert(x.has_payee == y.has_payee);
    assert(x.payee.name == y.payee.name && x.payee.addr2 == y.payee.addr2 && x.payee.country == y.payee.country);
    assert(x.payee.phone == y.payee.phone && x.payee.postal_code == y.payee.postal_code);
    assert(x.rate_kind == y.rate_kind && x.rate.num == y.rate.num && x.rate.den == y.rate.den);
    assert(x.rate_symbol == y.rate_symbol);
}

fn ofx_kind(extra: const u8[:]) -> i32 {
    var text: u8[>..] = [];
    for c in "OFXHEADER:100\nDATA:OFXSGML\nVERSION:102\nSECURITY:NONE\nENCODING:USASCII\nCHARSET:NONE\nCOMPRESSION:NONE\nOLDFILEUID:NONE\nNEWFILEUID:NONE\n\n<OFX><BANKMSGSRSV1><STMTTRNRS><TRNUID>1<STMTRS><CURDEF>USD<BANKACCTFROM><BANKID>1<ACCTID>2<ACCTTYPE>CHECKING</BANKACCTFROM><BANKTRANLIST><STMTTRN><TRNTYPE>DEBIT<DTPOSTED>20200101<TRNAMT>-1<FITID>X" { text.push(c); }
    for c in extra { text.push(c); }
    for c in "</STMTTRN></BANKTRANLIST></STMTRS></STMTTRNRS></BANKMSGSRSV1></OFX>" { text.push(c); }
    let lim = bank_statement::default_limits();
    let ropts = bank_statement::OfxOptions { .. };
    var sts: bank_statement::Statement[>..] = [];
    var ens: bank_statement::Entry[>..] = [];
    var bals: bank_statement::Balance[>..] = [];
    var notes: bank_statement::Note[>..] = [];
    var buf: u8[>..] = [];
    return bank_statement::parse_ofx(text, lim, ropts, sts, ens, bals, notes, buf).kind;
}

fn more_equal(a: bank_statement::Entry, b: bank_statement::Entry) {
    let x = a.ofx;
    let y = b.ofx;
    assert(x.sic == y.sic && x.has_sic == y.has_sic);
    assert(x.acct_to_kind == y.acct_to_kind);
    assert(x.acct_to.bank_id == y.acct_to.bank_id && x.acct_to.acct_id == y.acct_to.acct_id);
    assert(x.acct_to.acct_type == y.acct_to.acct_type && x.acct_to.acct_key == y.acct_to.acct_key);
    assert(x.acct_to.branch_id == y.acct_to.branch_id);
    assert(x.image.has_delay == y.image.has_delay && x.image.has_ttl == y.image.has_ttl);
    assert(x.image.avail.day == y.image.avail.day);
    assert(x.inv401k_source == y.inv401k_source);
    assert(x.image.kind == y.image.kind && x.image.ref == y.image.ref && x.image.ref_kind == y.image.ref_kind);
    assert(x.image.delay == y.image.delay && x.image.ttl == y.image.ttl && x.image.check_sup == y.image.check_sup);
    assert(x.image.avail.year == y.image.avail.year && x.image.avail.month == y.image.avail.month);
    assert(x.image_count == y.image_count);
    assert(x.image2.kind == y.image2.kind && x.image2.ref == y.image2.ref && x.image2.ref_kind == y.image2.ref_kind);
}
