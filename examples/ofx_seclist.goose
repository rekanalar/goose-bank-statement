// Reads the security list of an OFX investment file.
// Run with: goose run examples/ofx_seclist.goose

import std;
import xml from "rekanalar/goose-xml@v2.0.0";
import process from "rekanalar/goose-process@v1.0.0";
import bank_statement from "..";

fn main() {
    let text = "OFXHEADER:100\nDATA:OFXSGML\nVERSION:102\nSECURITY:NONE\nENCODING:USASCII\nCHARSET:NONE\nCOMPRESSION:NONE\nOLDFILEUID:NONE\nNEWFILEUID:NONE\n\n<OFX><SECLISTMSGSRSV1><SECLIST><STOCKINFO><SECINFO><SECID><UNIQUEID>123456789<UNIQUEIDTYPE>CUSIP</SECID><SECNAME>Acme<TICKER>ACME<UNITPRICE>12.50</SECINFO><STOCKTYPE>COMMON</STOCKINFO></SECLIST></SECLISTMSGSRSV1></OFX>\n";
    let lim = bank_statement::default_limits();
    var secs: bank_statement::OfxSecurity[>..] = [];
    var notes: bank_statement::Note[>..] = [];
    var buf: u8[>..] = [];
    let f = bank_statement::parse_ofx_securities(text, lim, secs, notes, buf);
    if f.kind != 0 {
        print("error: ", bank_statement::kind_name(f.kind), " ", f.detail, "\n");
        return 1;
    }
    for s in secs { print(s.kind, " ", s.ticker, " ", s.name, " ", s.price.num, "/", s.price.den, "\n"); }
    return 0;
}
