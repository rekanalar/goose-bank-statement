// The helpers and the globals that the tests share.
namespace sample_texts;

import std;
import os;
import xml from "rekanalar/goose-xml@v2.0.0";
import process from "rekanalar/goose-process@v1.0.0";
import bank_statement from "..";
import finance from "rekanalar/goose-finance@v0.1.0";

const REAL54: const u8[:] = """
<?xml version="1.0" encoding="UTF-8"?>
<Document xmlns="urn:iso:std:iso:20022:tech:xsd:camt.054.001.04" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="urn:iso:std:iso:20022:tech:xsd:camt.054.001.04 file:///C:/Users/alihodzica/Desktop/camt.054/camt.054.001.04.xsd">
	<BkToCstmrDbtCdtNtfctn>
		<GrpHdr>
			<MsgId>201904245375204223076552</MsgId>
			<CreDtTm>2019-04-24T21:28:58</CreDtTm>
			<MsgPgntn>
				<PgNb>1</PgNb>
				<LastPgInd>true</LastPgInd>
			</MsgPgntn>
			<AddtlInf>SPS/1.6/PROD</AddtlInf>
		</GrpHdr>
		<Ntfctn>
			<Id>20190424375204223076553</Id>
			<CreDtTm>2019-04-24T21:28:58</CreDtTm>
			<FrToDt>
				<FrDtTm>2019-04-24T21:28:58</FrDtTm>
				<ToDtTm>2019-04-24T21:28:58</ToDtTm>
			</FrToDt>
			<RptgSrc>
				<Prtry>CDTN</Prtry>
			</RptgSrc>
			<Acct>
				<Id>
					<IBAN>CH2909000000250094239</IBAN>
				</Id>
				<Ownr>
					<Nm>Robert Schneider SA Grands magasins Biel/Bienne</Nm>
				</Ownr>
			</Acct>
			<Ntry>
				<Amt Ccy="CHF">1500.00</Amt>
				<CdtDbtInd>CRDT</CdtDbtInd>
				<RvslInd>false</RvslInd>
				<Sts>BOOK</Sts>
				<BookgDt>
					<Dt>2019-04-24</Dt>
				</BookgDt>
				<ValDt>
					<Dt>2019-04-25</Dt>
				</ValDt>
				<AcctSvcrRef>074820002ZZ9J42U</AcctSvcrRef>
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
							<AcctSvcrRef>074820002ZZ9J42U</AcctSvcrRef>
						</Refs>
						<Amt Ccy="CHF">1500.00</Amt>
						<CdtDbtInd>CRDT</CdtDbtInd>
					</TxDtls>
				</NtryDtls>
				<AddtlNtryInf>SAMMELGUTSCHRIFT ESR VERARBEITUNG VOM 24.04.2019 KUNDENNUMMER 01-429580-3 PAKET ID: 180315CH00000HPA</AddtlNtryInf>
			</Ntry>
		</Ntfctn>
	</BkToCstmrDbtCdtNtfctn>
</Document>
""";
const CAMTAPP: const u8[:] = """
<?xml version="1.0" encoding="UTF-8"?>
<Document xmlns="urn:iso:std:iso:20022:tech:xsd:camt.053.001.08">
  <AppHdr>
    <Fr><FIId><FinInstnId><BICFI>BANKDEFF</BICFI></FinInstnId></FIId></Fr>
    <To><FIId><FinInstnId><BICFI>CLEARINGX</BICFI></FinInstnId></FIId></To>
    <BizMsgIdr>APP-MSG-1</BizMsgIdr>
    <MsgDefIdr>camt.053.001.08</MsgDefIdr>
    <BizSvc>AccountReporting</BizSvc>
    <CreDt>2025-01-02T15:30:00+01:00</CreDt>
  </AppHdr>
  <BkToCstmrStmt>
    <Stmt>
      <Id>APP-STMT</Id>
      <CreDtTm>2025-01-02T15:30:00+01:00</CreDtTm>
      <Acct><Id><IBAN>DE89370400440532013000</IBAN></Id><Ccy>EUR</Ccy></Acct>
      <Bal><Tp><CdOrPrtry><Cd>OPBD</Cd></CdOrPrtry></Tp><Amt Ccy="EUR">10.00</Amt><CdtDbtInd>CRDT</CdtDbtInd><Dt><Dt>2025-01-01</Dt></Dt></Bal>
    </Stmt>
  </BkToCstmrStmt>
</Document>
""";
const OFX_V1: const u8[:] = """
OFXHEADER:100
DATA:OFXSGML
VERSION:102
SECURITY:NONE
ENCODING:USASCII
CHARSET:1252
COMPRESSION:NONE
OLDFILEUID:NONE
NEWFILEUID:NONE

<OFX>
<SIGNONMSGSRSV1>
<SONRS>
<STATUS>
<CODE>0
<SEVERITY>INFO
</STATUS>
<DTSERVER>20200101120000
<LANGUAGE>ENG
<FI>
<ORG>TESTBANK
<FID>12345
</FI>
</SONRS>
</SIGNONMSGSRSV1>
<BANKMSGSRSV1>
<STMTTRNRS>
<TRNUID>1
<STATUS>
<CODE>0
<SEVERITY>INFO
</STATUS>
<STMTRS>
<CURDEF>USD
<BANKACCTFROM>
<BANKID>111111111
<ACCTID>999999
<ACCTTYPE>CHECKING
</BANKACCTFROM>
<BANKTRANLIST>
<DTSTART>20200101000000
<DTEND>20200131000000
<STMTTRN>
<TRNTYPE>CHECK
<DTPOSTED>20200105120000
<TRNAMT>-100.00
<FITID>TX1
<CHECKNUM>101
<NAME>ACME corp
<MEMO>payment
</STMTTRN>
<STMTTRN>
<TRNTYPE>CREDIT
<DTPOSTED>20200110000000
<TRNAMT>1234,56
<FITID>TX2
</STMTTRN>
</BANKTRANLIST>
<LEDGERBAL>
<BALAMT>1134.56
<DTASOF>20200131000000
</LEDGERBAL>
<AVAILBAL>
<BALAMT>1134.56
<DTASOF>20200131000000
</AVAILBAL>
</STMTRS>
</STMTTRNRS>
</BANKMSGSRSV1>
</OFX>
""";
const OFX_V2: const u8[:] = """
<?xml version="1.0" encoding="UTF-8" standalone="no"?>
<?OFX OFXHEADER="200" VERSION="203" SECURITY="NONE" OLDFILEUID="NONE" NEWFILEUID="NONE"?>
<OFX>
<SIGNONMSGSRSV1>
<SONRS>
<STATUS>
<CODE>0
<SEVERITY>INFO
</STATUS>
<DTSERVER>20200101120000.000[-5:EST]
</SONRS>
</SIGNONMSGSRSV1>
<BANKMSGSRSV1>
<STMTTRNRS>
<TRNUID>R2
<STATUS>
<CODE>0
<SEVERITY>INFO
</STATUS>
<STMTRS>
<CURDEF>EUR
<BANKACCTFROM>
<BANKID>222
<ACCTID>888
<ACCTTYPE>SAVINGS
</BANKACCTFROM>
<BANKTRANLIST>
<STMTTRN>
<TRNTYPE>POS
<DTPOSTED>20200102
<TRNAMT>-12.34
<FITID>A&amp;B
<NAME>A &lt;big&gt; shop
</STMTTRN>
</BANKTRANLIST>
<LEDGERBAL>
<BALAMT>1000.00
<DTASOF>20200131
</LEDGERBAL>
</STMTRS>
</STMTTRNRS>
</BANKMSGSRSV1>
</OFX>
""";
const OFX_INV: const u8[:] = """
OFXHEADER:100
DATA:OFXSGML
VERSION:103
SECURITY:NONE
ENCODING:USASCII
CHARSET:NONE
COMPRESSION:NONE
OLDFILEUID:NONE
NEWFILEUID:NONE

<OFX>
<INVSTMTMSGSRSV1>
<INVSTMTTRNRS>
<TRNUID>I1
<STATUS>
<CODE>0
<SEVERITY>INFO
</STATUS>
<INVSTMTRS>
<DTASOF>20200401
<CURDEF>USD
<INVACCTFROM>
<BROKERID>broker.com
<ACCTID>7
</INVACCTFROM>
<INVTRANLIST>
<DTSTART>20200301000000
<DTEND>20200401000000
<BUYSTOCK>
<INVBUY>
<INVTRAN>
<FITID>B1
<DTTRADE>20200310
<MEMO>buy
</INVTRAN>
<SECID>
<UNIQUEID>037833100
<UNIQUEIDTYPE>CUSIP
</SECID>
<UNITS>10.5
<UNITPRICE>100.125
<COMMISSION>9.95
<TOTAL>-1051.25
<SUBACCTSEC>CASH
<SUBACCTFUND>CASH
</INVBUY>
<BUYTYPE>BUY
</BUYSTOCK>
<INCOME>
<INVTRAN>
<FITID>I2
<DTTRADE>20200315
</INVTRAN>
<SECID>
<UNIQUEID>037833100
<UNIQUEIDTYPE>CUSIP
</SECID>
<INCOMETYPE>DIV
<TOTAL>25.00
<SUBACCTSEC>CASH
<SUBACCTFUND>CASH
</INCOME>
</INVTRANLIST>
<INVPOSLIST>
<POSSTOCK>
<INVPOS>
<SECID>
<UNIQUEID>037833100
<UNIQUEIDTYPE>CUSIP
</UNIQUEID>
</SECID>
<HELDINACCT>CASH
<POSTYPE>LONG
<UNITS>10.5
<UNITPRICE>105.25
<MKTVAL>1105.25
<DTPRICEASOF>20200401
</INVPOS>
</POSSTOCK>
</INVPOSLIST>
</INVSTMTRS>
</INVSTMTTRNRS>
</INVSTMTMSGSRSV1>
</OFX>
""";
const OFX_CC: const u8[:] = """
OFXHEADER:100
DATA:OFXSGML
VERSION:102
SECURITY:NONE
ENCODING:USASCII
CHARSET:1252
COMPRESSION:NONE
OLDFILEUID:NONE
NEWFILEUID:NONE

<OFX>
<SIGNONMSGSRSV1><SONRS><STATUS><CODE>0<SEVERITY>INFO</STATUS><DTSERVER>20201101120000</DTSERVER><LANGUAGE>ENG</LANGUAGE></SONRS></SIGNONMSGSRSV1>
<CREDITCARDMSGSRSV1>
<CCSTMTTRNRS><TRNUID>CC-1</TRNUID>
<STATUS><CODE>0<SEVERITY>INFO</STATUS>
<CCSTMTRS><CURDEF>USD</CURDEF><CCACCTFROM><ACCTID>4111111111111111</ACCTID></CCACCTFROM>
<BANKTRANLIST><DTSTART>20201001000000<DTEND>20201031000000</DTEND>
<STMTTRN><TRNTYPE>PAYMENT<DTPOSTED>20201005120000<TRNAMT>-25.50<FITID>CC1<NAME>Store</NAME></STMTTRN>
</BANKTRANLIST>
<LEDGERBAL><BALAMT>-120.00<DTASOF>20201031120000</DTASOF></LEDGERBAL>
</CCSTMTRS></CCSTMTTRNRS>
</CREDITCARDMSGSRSV1>
</OFX>
""";
const LISTS_TEXT: const u8[:] = "!Account\nNChecking\nTBank\nDMain account\nL1,000.00\n/12/31/2025\n$250.50\n^\n!Type:Cat\nNFood:Dining\nDEating out\nT\nI\nE\nRSched A\nB10.00\nB20.50\nXodd\n^\n!Type:Budget\nNHome\nB5.00\n^\n!Type:Class\nNGarden\nDplants\n^\n!Type:Security\nNAcme Corp\nSACME\nTStock\nGGrowth\n^\n!Type:Tag\nNtrip\nDvacation\n^\n!Type:Payee\nPBob's Cafe\nA1 Main St\nAFloor 2\nCParis\nSIDF\nZ75001\nYFRA\nN0102030405\n#ACC-9\n^\n!Type:Prices\n\"ACME\",50 1/2,\"6/30/98\"\n^\n\"A,B\",10.25,\"1/2'25\",10.5,9.75,42000\n^\n";
const SECLIST_SGML: const u8[:] = """
OFXHEADER:100
DATA:OFXSGML
VERSION:102
SECURITY:NONE
ENCODING:USASCII
CHARSET:NONE
COMPRESSION:NONE
OLDFILEUID:NONE
NEWFILEUID:NONE

<OFX><SECLISTMSGSRSV1><SECLIST>
<STOCKINFO><SECINFO><SECID><UNIQUEID>123456789<UNIQUEIDTYPE>CUSIP</SECID><SECNAME>Acme &amp; Sons<TICKER>ACME<UNITPRICE>12.50<DTASOF>20200131<CURRENCY><CURRATE>1.1<CURSYM>EUR</CURRENCY><MEMO>core</SECINFO><STOCKTYPE>COMMON<YIELD>2.5</STOCKINFO>
<MFINFO><SECINFO><SECID><UNIQUEID>MF1<UNIQUEIDTYPE>ISIN</SECID><SECNAME>Fund<UNITPRICE>10 1/2</SECINFO><MFTYPE>OPENEND</MFINFO>
<OPTINFO><SECINFO><SECID><UNIQUEID>OPT1<UNIQUEIDTYPE>CUSIP</SECID><SECNAME>Call</SECINFO><OPTTYPE>CALL<STRIKEPRICE>50<SECID><UNIQUEID>UNDER<UNIQUEIDTYPE>CUSIP</SECID></OPTINFO>
</SECLIST></SECLISTMSGSRSV1></OFX>
""";
const PROFILE_SGML: const u8[:] = """
OFXHEADER:100
DATA:OFXSGML
VERSION:102
SECURITY:NONE
ENCODING:USASCII
CHARSET:NONE
COMPRESSION:NONE
OLDFILEUID:NONE
NEWFILEUID:NONE

<OFX><PROFMSGSRSV1><PROFTRNRS><TRNUID>1<STATUS><CODE>0<SEVERITY>INFO</STATUS><PROFRS>
<MSGSETLIST>
<SIGNONMSGSET><SIGNONMSGSETV1><MSGSETCORE><VER>1<URL>https://bank.example/ofx<OFXSEC>TYPE1<TRANSPSEC>Y<SIGNONREALM>BANK<LANGUAGE>ENG<SYNCMODE>FULL<RESPFILEER>N</MSGSETCORE></SIGNONMSGSETV1></SIGNONMSGSET>
<BANKMSGSET><BANKMSGSETV1><MSGSETCORE><VER>1<URL>https://bank.example/bank<OFXSEC>NONE<TRANSPSEC>N<SIGNONREALM>BANK<LANGUAGE>ENG<SYNCMODE>LITE<RESPFILEER>N<SPNAME>Fiserv</MSGSETCORE><INVALIDACCTTYPE>CREDITLINE<CLOSINGAVAIL>Y</BANKMSGSETV1></BANKMSGSET>
</MSGSETLIST>
<SIGNONINFOLIST><SIGNONINFO><SIGNONREALM>BANK<MIN>4<MAX>12<CHARTYPE>ALPHAANDNUMERIC<CASESEN>Y<SPECIAL>N<SPACES>N<PINCH>Y<CHGPINFIRST>N<USERCRED1LABEL>Branch</SIGNONINFO></SIGNONINFOLIST>
<DTPROFUP>20200115<FINAME>Test Bank &amp; Trust<ADDR1>1 Main St<CITY>Springfield<STATE>IL<POSTALCODE>62701<COUNTRY>USA<CSPHONE>800-555-0100<URL>https://bank.example<EMAIL>help@bank.example
</PROFRS></PROFTRNRS></PROFMSGSRSV1></OFX>
""";
const OFX_EXTRA: const u8[:] = """
OFXHEADER:100
DATA:OFXSGML
VERSION:102
SECURITY:NONE
ENCODING:USASCII
CHARSET:NONE
COMPRESSION:NONE
OLDFILEUID:NONE
NEWFILEUID:NONE

<OFX><SIGNONMSGSRSV1><SONRS><STATUS><CODE>0<SEVERITY>INFO</STATUS><DTSERVER>20200101120000<LANGUAGE>ENG</SONRS></SIGNONMSGSRSV1>
<BANKMSGSRSV1><STMTTRNRS><TRNUID>7<STATUS><CODE>0<SEVERITY>INFO</STATUS>
<STMTRS><CURDEF>USD<BANKACCTFROM><BANKID>111111111<ACCTID>999999<ACCTTYPE>SAVINGS</BANKACCTFROM>
<BANKTRANLIST><DTSTART>20200101<DTEND>20200131
<STMTTRN><TRNTYPE>DEBIT<DTPOSTED>20200105<DTUSER>20200104<TRNAMT>-5000<FITID>A1<CORRECTFITID>A0<CORRECTACTION>REPLACE<PAYEEID>P77
<PAYEE><NAME>Cafe &amp; Bar<ADDR1>1 Main St<ADDR2>Floor 2<CITY>Paris<STATE>IDF<POSTALCODE>75001<COUNTRY>FRA<PHONE>0102030405</PAYEE>
<EXTDNAME>Cafe and Bar, Paris<MEMO>lunch<CURRENCY><CURRATE>0.0091<CURSYM>JPY</CURRENCY></STMTTRN>
<STMTTRN><TRNTYPE>CREDIT<DTPOSTED>20200106<TRNAMT>10.50<FITID>A2<NAME>Bob<ORIGCURRENCY><CURRATE>1,25<CURSYM>EUR</ORIGCURRENCY></STMTTRN>
</BANKTRANLIST>
<LEDGERBAL><BALAMT>100.00<DTASOF>20200131</LEDGERBAL></STMTRS></STMTTRNRS></BANKMSGSRSV1></OFX>
""";
const OFX_EXTRA2: const u8[:] = """
OFXHEADER:100
DATA:OFXSGML
VERSION:102
SECURITY:NONE
ENCODING:USASCII
CHARSET:NONE
COMPRESSION:NONE
OLDFILEUID:NONE
NEWFILEUID:NONE

<OFX><SIGNONMSGSRSV1><SONRS><STATUS><CODE>0<SEVERITY>INFO</STATUS><DTSERVER>20200101120000<LANGUAGE>ENG</SONRS></SIGNONMSGSRSV1>
<BANKMSGSRSV1><STMTTRNRS><TRNUID>7<STATUS><CODE>0<SEVERITY>INFO</STATUS>
<STMTRS><CURDEF>USD<BANKACCTFROM><BANKID>111111111<ACCTID>999999<ACCTTYPE>SAVINGS</BANKACCTFROM>
<BANKTRANLIST><DTSTART>20200101<DTEND>20200131
<STMTTRN><TRNTYPE>XFER<DTPOSTED>20200105<TRNAMT>-50.00<FITID>B1<SIC>5411<NAME>Move
<BANKACCTTO><BANKID>222222222<BRANCHID>12<ACCTID>5550001<ACCTTYPE>CHECKING<ACCTKEY>K1</BANKACCTTO>
<MEMO>to checking
<IMAGEDATA><IMAGETYPE>TRANSACTION<IMAGEREF>https://bank.example/img?a=1&amp;b=2<IMAGEREFTYPE>URL<IMAGEDELAY>3<IMAGETTL>30<CHECKSUP>FRONTONLY</IMAGEDATA>
<IMAGEDATA><IMAGETYPE>STATEMENT<IMAGEREF>second<IMAGEREFTYPE>OPAQUE</IMAGEDATA>
<INV401KSOURCE>MATCH</STMTTRN>
<STMTTRN><TRNTYPE>PAYMENT<DTPOSTED>20200106<TRNAMT>-20.00<FITID>B2<CCACCTTO><ACCTID>4111000011112222</CCACCTTO>
<IMAGEDATA><IMAGETYPE>TAX<IMAGEREF>r<IMAGEREFTYPE>FORMURL<DTIMAGEAVAIL>20200201</IMAGEDATA></STMTTRN>
</BANKTRANLIST>
<LEDGERBAL><BALAMT>100.00<DTASOF>20200131</LEDGERBAL></STMTRS></STMTTRNRS></BANKMSGSRSV1></OFX>
""";



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
