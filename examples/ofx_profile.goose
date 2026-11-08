// Reads the profile response of an OFX file.
// Run with: goose run examples/ofx_profile.goose

import std;
import xml from "rekanalar/goose-xml@v2.0.0";
import process from "rekanalar/goose-process@v1.0.0";
import finance from "rekanalar/goose-finance@v0.1.0";
import bank_statement from "..";

fn main() {
    let text = "OFXHEADER:100\nDATA:OFXSGML\nVERSION:102\nSECURITY:NONE\nENCODING:USASCII\nCHARSET:NONE\nCOMPRESSION:NONE\nOLDFILEUID:NONE\nNEWFILEUID:NONE\n\n<OFX><PROFMSGSRSV1><PROFTRNRS><TRNUID>1<STATUS><CODE>0<SEVERITY>INFO</STATUS><PROFRS><MSGSETLIST><BANKMSGSET><BANKMSGSETV1><MSGSETCORE><VER>1<URL>https://bank.example/ofx<OFXSEC>NONE<TRANSPSEC>N<SIGNONREALM>BANK</MSGSETCORE></BANKMSGSETV1></BANKMSGSET></MSGSETLIST><SIGNONINFOLIST><SIGNONINFO><SIGNONREALM>BANK<MIN>4<MAX>12<CHARTYPE>ALPHAONLY<CASESEN>N<SPECIAL>N<SPACES>N<PINCH>N</SIGNONINFO></SIGNONINFOLIST><DTPROFUP>20200115<FINAME>Test Bank<ADDR1>1 Main St<CITY>Springfield<STATE>IL<POSTALCODE>62701<COUNTRY>USA</PROFRS></PROFTRNRS></PROFMSGSRSV1></OFX>\n";
    let lim = bank_statement::default_limits();
    var pr = bank_statement::OfxProfile { found: false, updated: bank_statement::no_date(), name: "", addr1: "", addr2: "", addr3: "", city: "", state: "", postal_code: "", country: "", cs_phone: "", ts_phone: "", fax_phone: "", url: "", email: "" };
    var signons: bank_statement::OfxSignonInfo[>..] = [];
    var sets: bank_statement::OfxMsgSet[>..] = [];
    var notes: bank_statement::Note[>..] = [];
    var buf: u8[>..] = [];
    let f = bank_statement::parse_ofx_profile(text, lim, pr, signons, sets, notes, buf);
    if f.kind != 0 {
        print("error: ", bank_statement::kind_name(f.kind), " ", f.detail, "\n");
        return 1;
    }
    print(pr.name, ", ", pr.city, "\n");
    for m in sets { print(m.kind, " ", m.url, "\n"); }
    return 0;
}
