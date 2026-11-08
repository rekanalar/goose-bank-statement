// Reads an OFX 1.x bank statement and prints its entries and balances.
// Run with: goose run examples/ofx.goose

import std;
import xml from "rekanalar/goose-xml@v2.0.0";
import process from "rekanalar/goose-process@v1.0.0";
import finance from "rekanalar/goose-finance@v0.1.0";
import bank_statement from "..";

const DOC: const u8[:] = """
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
</SONRS>
</SIGNONMSGSRSV1>
<BANKMSGSRSV1>
<STMTTRNRS>
<TRNUID>1
<STMTRS>
<CURDEF>USD
<BANKACCTFROM>
<BANKID>111111111
<ACCTID>999999
<ACCTTYPE>CHECKING
</BANKACCTFROM>
<BANKTRANLIST>
<STMTTRN>
<TRNTYPE>CHECK
<DTPOSTED>20200105120000
<TRNAMT>-100.00
<FITID>TX1
<CHECKNUM>101
<NAME>Acme corp
<MEMO>payment
</STMTTRN>
<STMTTRN>
<TRNTYPE>CREDIT
<DTPOSTED>20200110000000
<TRNAMT>1234.56
<FITID>TX2
</STMTTRN>
</BANKTRANLIST>
<LEDGERBAL>
<BALAMT>1134.56
<DTASOF>20200131000000
</LEDGERBAL>
</STMTRS>
</STMTTRNRS>
</BANKMSGSRSV1>
</OFX>
""";

fn main() {
    let lim = bank_statement::default_limits();
    let opts = bank_statement::OfxOptions { .. };
    var sts: bank_statement::Statement[>..] = [];
    var ens: bank_statement::Entry[>..] = [];
    var bals: bank_statement::Balance[>..] = [];
    var notes: bank_statement::Note[>..] = [];
    var buf: u8[>..] = [];
    let f = bank_statement::parse_ofx(DOC, lim, opts, sts, ens, bals, notes, buf);
    if f.kind != 0 {
        print("error: ", bank_statement::kind_name(f.kind), " ", f.tag, " ", f.detail);
        return 1;
    }
    for st in sts {
        print("statement ", st.reference, " account ", st.account);
        print("  closing ", st.closing.amount.minor, " minor units ", st.closing.amount.currency);
    }
    for e in ens {
        print("  ", e.mark, " ", e.amount.minor, " ", e.amount.currency, " ", e.type_id, " ", e.entry_ref);
        print("      counter ", e.counter_name, " memo ", e.narrative);
    }
    for n in notes { print("  note ", n.tag, " = ", n.value); }
    return 0;
}
