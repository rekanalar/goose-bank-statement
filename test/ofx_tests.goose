// The tests of the group ofx.
namespace ofx_tests;

import std;
import os;
import xml from "rekanalar/goose-xml@v2.0.0";
import process from "rekanalar/goose-process@v1.0.0";
import bank_statement from "..";
import finance from "rekanalar/goose-finance@v0.1.0";
import common;
import common_2;

fn test_ofx_v1() {
    let lim = bank_statement::default_limits();
    let opts = bank_statement::OfxOptions { .. };
    var sts: bank_statement::Statement[>..] = [];
    var ens: bank_statement::Entry[>..] = [];
    var bals: bank_statement::Balance[>..] = [];
    var notes: bank_statement::Note[>..] = [];
    var buf: u8[>..] = [];
    let f = bank_statement::parse_ofx(common_2::OFX_V1, lim, opts, sts, ens, bals, notes, buf);
    if f.kind != 0 { print("FAIL ofx v1 ", bank_statement::kind_name(f.kind), " ", f.tag, " ", f.detail, "\n"); }
    assert(f.kind == 0);
    // One statement with the account and the entries.
    assert(sts.len == 1);
    let st = sts[0];
    assert(st.reference == "1");
    assert(st.account == "999999");
    assert(st.entry_count == 2 && ens.len == 2);
    // The first entry is a debit of 100.00 dollars.
    assert(ens[0].mark == "D" && ens[0].amount.minor == -10000 && ens[0].amount.exp == 2);
    assert(ens[0].amount.currency == "USD");
    assert(ens[0].type_id == "CHECK" && ens[0].entry_ref == "TX1");
    assert(ens[0].customer_ref == "101");
    assert(ens[0].counter_name == "ACME corp");
    assert(ens[0].narrative == "payment");
    assert(ens[0].value_date.year == 2020 && ens[0].value_date.month == 1 && ens[0].value_date.day == 5);
    // The second entry has a comma as the decimal mark.
    assert(ens[1].mark == "C" && ens[1].amount.minor == 123456 && ens[1].entry_ref == "TX2");
    // The balances.
    assert(bals.len == 2);
    assert(st.closing.kind == bank_statement::BAL_CLOSING && st.closing.amount.minor == 113456);
    assert(st.closing.code == "LEDGERBAL");
    assert(st.available.kind == bank_statement::BAL_AVAILABLE && st.available.amount.minor == 113456);
    assert(st.closing.date.year == 2020 && st.closing.date.month == 1 && st.closing.date.day == 31);
    // The signon status and the account notes.
    assert(notes.len == 3);
    assert(notes[0].tag == "SONRS" && notes[0].value == "0/INFO");
    assert(notes[1].tag == "BANKID" && notes[1].value == "111111111");
    assert(notes[2].tag == "ACCTTYPE" && notes[2].value == "CHECKING");
}

fn test_ofx_v2() {
    let lim = bank_statement::default_limits();
    let opts = bank_statement::OfxOptions { .. };
    var sts: bank_statement::Statement[>..] = [];
    var ens: bank_statement::Entry[>..] = [];
    var bals: bank_statement::Balance[>..] = [];
    var notes: bank_statement::Note[>..] = [];
    var buf: u8[>..] = [];
    let f = bank_statement::parse_ofx(common_2::OFX_V2, lim, opts, sts, ens, bals, notes, buf);
    if f.kind != 0 { print("FAIL ofx v2 ", bank_statement::kind_name(f.kind), " ", f.tag, " ", f.detail, "\n"); }
    assert(f.kind == 0);
    assert(sts.len == 1 && sts[0].reference == "R2");
    assert(sts[0].account == "888");
    assert(ens.len == 1);
    // The entities decode once.
    assert(ens[0].entry_ref == "A&B");
    assert(ens[0].counter_name == "A <big> shop");
    assert(ens[0].mark == "D" && ens[0].amount.minor == -1234 && ens[0].amount.currency == "EUR");
    assert(ens[0].value_date.year == 2020 && ens[0].value_date.month == 1 && ens[0].value_date.day == 2);
    assert(bals.len == 1 && bals[0].amount.minor == 100000);
}

fn test_ofx_invest() {
    let lim = bank_statement::default_limits();
    let opts = bank_statement::OfxOptions { .. };
    var sts: bank_statement::Statement[>..] = [];
    var ens: bank_statement::Entry[>..] = [];
    var bals: bank_statement::Balance[>..] = [];
    var notes: bank_statement::Note[>..] = [];
    var buf: u8[>..] = [];
    let f = bank_statement::parse_ofx(common_2::OFX_INV, lim, opts, sts, ens, bals, notes, buf);
    if f.kind != 0 { print("FAIL ofx inv ", bank_statement::kind_name(f.kind), " ", f.tag, " ", f.detail, "\n"); }
    assert(f.kind == 0);
    assert(sts.len == 1);
    assert(sts[0].account == "broker.com:7");
    // The buy, the income and the position.
    assert(ens.len == 3);
    assert(ens[0].type_id == "BUYSTOCK" && ens[0].entry_ref == "B1");
    assert(ens[0].mark == "D" && ens[0].amount.minor == -105125);
    assert(ens[0].has_units && ens[0].units.num == 21 && ens[0].units.den == 2);
    assert(ens[0].units_text == "10.5");
    assert(ens[0].has_unit_price && ens[0].unit_price.num == 801 && ens[0].unit_price.den == 8);
    assert(ens[0].has_commission && ens[0].commission.num == 199 && ens[0].commission.den == 20);
    assert(ens[0].value_date.year == 2020 && ens[0].value_date.month == 3 && ens[0].value_date.day == 10);
    // The income names its kind and holds its total.
    assert(ens[1].type_id == "INCOME/DIV" && ens[1].mark == "C");
    assert(ens[1].has_total && ens[1].total.num == 25 && ens[1].total.den == 1);
    assert(ens[1].amount.minor == 2500);
    // The position holds its units, its price and its value.
    assert(ens[2].type_id == "POSSTOCK");
    assert(ens[2].has_units && ens[2].units.num == 21 && ens[2].units.den == 2);
    assert(ens[2].customer_ref == "037833100");
    assert(ens[2].amount.minor == 110525);
    assert(ens[2].value_date.year == 2020 && ens[2].value_date.month == 4 && ens[2].value_date.day == 1);
}

fn test_ofx_dates() {
    // The date forms of the spec.
    assert(common::ofx_date_fault("20200101120000") == 0);
    assert(common::ofx_date_fault("2020010112") == 0);
    assert(common::ofx_date_fault("20200101") == 0);
    assert(common::ofx_date_fault("20200101120000.000") == 0);
    assert(common::ofx_date_fault("20200101120000[-5:EST]") == 0);
    assert(common::ofx_date_fault("20200101120000[-5.30:IST]") == 0);
    assert(common::ofx_date_fault("20200101120000[0:GMT]") == 0);
    // The bad dates.
    assert(common::ofx_date_fault("2020010112000") == 6);
    assert(common::ofx_date_fault("20201301120000") == 6);
    assert(common::ofx_date_fault("20200230120000") == 6);
    assert(common::ofx_date_fault("20200101120000[99:EST]") == 6);
    // The date of the entry holds the day.
    let lim = bank_statement::default_limits();
    let opts = bank_statement::OfxOptions { .. };
    var text: u8[>..] = [];
    common::build_ofx_date("20200101120000[-5:EST]", text);
    var sts: bank_statement::Statement[>..] = [];
    var ens: bank_statement::Entry[>..] = [];
    var bals: bank_statement::Balance[>..] = [];
    var notes: bank_statement::Note[>..] = [];
    var buf: u8[>..] = [];
    let f = bank_statement::parse_ofx(text[..], lim, opts, sts, ens, bals, notes, buf);
    assert(f.kind == 0);
    assert(ens.len == 1);
    assert(ens[0].value_date.year == 2020 && ens[0].value_date.month == 1 && ens[0].value_date.day == 1);
}

fn test_ofx_faults() {
    // A file that is no OFX file.
    common::run_ofx("hello", 2);
    // A header with a bad field.
    common::run_ofx("OFXHEADER:999\nDATA:OFXSGML\nVERSION:102\n\n<OFX></OFX>", 2);
    common::run_ofx("OFXHEADER:100\nDATA:OFXSGML\nVERSION:999\n\n<OFX></OFX>", 2);
    common::run_ofx("OFXHEADER:100\nDATA:OFXSGML\nVERSION:102\nWHAT:1\n\n<OFX></OFX>", 2);
    // A root that is not OFX.
    common::run_ofx("OFXHEADER:100\nDATA:OFXSGML\nVERSION:102\n\n<OTHER></OTHER>", 2);
    // A close tag that does not match.
    common::run_ofx("OFXHEADER:100\nDATA:OFXSGML\nVERSION:102\n\n<OFX><A></B></OFX>", 2);
    // An aggregate that is not closed.
    common::run_ofx("OFXHEADER:100\nDATA:OFXSGML\nVERSION:102\n\n<OFX><A>", 2);
    // A doctype and an entity.
    common::run_ofx("OFXHEADER:100\nDATA:OFXSGML\nVERSION:102\n\n<!DOCTYPE OFX><OFX></OFX>", 2);
    common::run_ofx("OFXHEADER:100\nDATA:OFXSGML\nVERSION:102\n\n<!ENTITY x \"y\"><OFX></OFX>", 2);
    // A currency that is not known.
    common::run_ofx("OFXHEADER:100\nDATA:OFXSGML\nVERSION:102\n\n<OFX><BANKMSGSRSV1><STMTTRNRS><TRNUID>1<STMTRS><CURDEF>XXX</STMTRS></STMTTRNRS></BANKMSGSRSV1></OFX>", 4);
    // A bad amount.
    common::run_ofx("OFXHEADER:100\nDATA:OFXSGML\nVERSION:102\n\n<OFX><BANKMSGSRSV1><STMTTRNRS><TRNUID>1<STMTRS><CURDEF>USD<BANKTRANLIST><STMTTRN><TRNTYPE>CHECK<TRNAMT>1e5</STMTTRN></BANKTRANLIST></STMTRS></STMTTRNRS></BANKMSGSRSV1></OFX>", 4);
    // A file above the input limit.
    var lim = bank_statement::default_limits();
    lim.max_input = 20;
    var sts: bank_statement::Statement[>..] = [];
    var ens: bank_statement::Entry[>..] = [];
    var bals: bank_statement::Balance[>..] = [];
    var notes: bank_statement::Note[>..] = [];
    var buf: u8[>..] = [];
    let opts = bank_statement::OfxOptions { .. };
    let f = bank_statement::parse_ofx(common_2::OFX_V1, lim, opts, sts, ens, bals, notes, buf);
    assert(f.kind == 1);
}

fn test_ofx_forms() {
    // The header of one line, with a space after the colon and
    // without the blank line.
    let one = "OFXHEADER:100 DATA:OFXSGML VERSION:102 SECURITY:NONE ENCODING:USASCII CHARSET:1252 COMPRESSION:NONE OLDFILEUID:NONE NEWFILEUID:NONE<OFX><BANKMSGSRSV1><STMTTRNRS><TRNUID>1<STMTRS><CURDEF>USD</STMTRS></STMTTRNRS></BANKMSGSRSV1></OFX>";
    let lim = bank_statement::default_limits();
    let opts = bank_statement::OfxOptions { .. };
    var sts: bank_statement::Statement[>..] = [];
    var ens: bank_statement::Entry[>..] = [];
    var bals: bank_statement::Balance[>..] = [];
    var notes: bank_statement::Note[>..] = [];
    var buf: u8[>..] = [];
    let f = bank_statement::parse_ofx(one, lim, opts, sts, ens, bals, notes, buf);
    if f.kind != 0 { print("FAIL ofx one line ", bank_statement::kind_name(f.kind), " ", f.tag, " ", f.detail, "\n"); }
    assert(f.kind == 0);
    assert(sts.len == 1);
    // A comment, a CDATA section and a private tag do not disturb the
    // read.
    let forms = "OFXHEADER:100\nDATA:OFXSGML\nVERSION:102\n\n<OFX><!-- a comment --><INTU.BID>private</INTU.BID><BANKMSGSRSV1><STMTTRNRS><TRNUID>1<STMTRS><CURDEF>USD<BANKTRANLIST><STMTTRN><TRNTYPE>CHECK<TRNAMT>1.00<FITID>X</STMTTRN></BANKTRANLIST></STMTRS></STMTTRNRS></BANKMSGSRSV1></OFX>";
    var sts2: bank_statement::Statement[>..] = [];
    var ens2: bank_statement::Entry[>..] = [];
    var bals2: bank_statement::Balance[>..] = [];
    var notes2: bank_statement::Note[>..] = [];
    var buf2: u8[>..] = [];
    let g = bank_statement::parse_ofx(forms, lim, opts, sts2, ens2, bals2, notes2, buf2);
    if g.kind != 0 { print("FAIL ofx forms ", bank_statement::kind_name(g.kind), " ", g.tag, " ", g.detail, "\n"); }
    assert(g.kind == 0);
    assert(sts2.len == 1 && ens2.len == 1);
    // A tag that is not in the leaf list holds its text and closes
    // with its own close tag.
    let custom = "OFXHEADER:100\nDATA:OFXSGML\nVERSION:102\n\n<OFX><MYTAG>text</MYTAG><BANKMSGSRSV1><STMTTRNRS><TRNUID>1<STMTRS><CURDEF>USD</STMTRS></STMTTRNRS></BANKMSGSRSV1></OFX>";
    var sts3: bank_statement::Statement[>..] = [];
    var ens3: bank_statement::Entry[>..] = [];
    var bals3: bank_statement::Balance[>..] = [];
    var notes3: bank_statement::Note[>..] = [];
    var buf3: u8[>..] = [];
    let h = bank_statement::parse_ofx(custom, lim, opts, sts3, ens3, bals3, notes3, buf3);
    if h.kind != 0 { print("FAIL ofx custom ", bank_statement::kind_name(h.kind), " ", f.tag, " ", f.detail, "\n"); }
    assert(h.kind == 0);
    assert(sts3.len == 1);
    // An unknown entity stays as text. It never expands.
    let ent = "OFXHEADER:100\nDATA:OFXSGML\nVERSION:102\n\n<OFX><A>&xxe;</A></OFX>";
    var sts4: bank_statement::Statement[>..] = [];
    var ens4: bank_statement::Entry[>..] = [];
    var bals4: bank_statement::Balance[>..] = [];
    var notes4: bank_statement::Note[>..] = [];
    var buf4: u8[>..] = [];
    let k = bank_statement::parse_ofx(ent, lim, opts, sts4, ens4, bals4, notes4, buf4);
    assert(k.kind == 0);
}

fn test_ofx_seclist() {
    let lim = bank_statement::default_limits();
    var secs: bank_statement::OfxSecurity[>..] = [];
    var notes: bank_statement::Note[>..] = [];
    var buf: u8[>..] = [];
    let f = bank_statement::parse_ofx_securities(common_2::SECLIST_SGML, lim, secs, notes, buf);
    if f.kind != 0 { print("FAIL seclist ", bank_statement::kind_name(f.kind), " ", f.tag, " ", f.detail, "\n"); }
    assert(f.kind == 0);
    assert(secs.len == 3);
    let a = secs[0];
    assert(a.kind == "STOCKINFO" && a.id == "123456789" && a.id_type == "CUSIP" && a.name == "Acme & Sons");
    assert(a.ticker == "ACME" && a.memo == "core" && a.currency == "EUR");
    assert(a.has_price && a.price.num == 25 && a.price.den == 2 && a.price_text == "12.50");
    assert(a.price_date.year == 2020 && a.price_date.month == 1 && a.price_date.day == 31);
    // The leaves outside SECINFO and the CURRATE leaf stay as notes.
    assert(a.note_count == 3);
    assert(notes[a.note_start].tag == "CURRATE" && notes[a.note_start + 1].tag == "STOCKTYPE" && notes[a.note_start + 1].value == "COMMON");
    assert(secs[1].kind == "MFINFO" && secs[1].price.num == 21 && secs[1].price.den == 2);
    let o = secs[2];
    assert(o.kind == "OPTINFO" && o.id == "OPT1" && o.note_count == 4);
    assert(notes[o.note_start + 2].tag == "UNIQUEID" && notes[o.note_start + 2].value == "UNDER");
    // A file without a list gives nothing.
    var s2: bank_statement::OfxSecurity[>..] = [];
    var n2: bank_statement::Note[>..] = [];
    var b2: u8[>..] = [];
    assert(bank_statement::parse_ofx_securities(common_2::OFX_EXTRA, lim, s2, n2, b2).kind == 0 && s2.len == 0);
    // A bad price is a fault; a small record limit is a fault.
    var s3: bank_statement::OfxSecurity[>..] = [];
    var n3: bank_statement::Note[>..] = [];
    var b3: u8[>..] = [];
    var small = bank_statement::default_limits();
    small.max_records = 2;
    assert(bank_statement::parse_ofx_securities(common_2::SECLIST_SGML, small, s3, n3, b3).kind == bank_statement::F_LIMIT);
    // The writer writes the list back and the reader reads the same
    // securities.
    var out: u8[>..] = [];
    let wf = bank_statement::write_ofx_securities(secs, notes, common::ofx_wopts(102), lim, out);
    if wf.kind != 0 { print("FAIL seclist write ", bank_statement::kind_name(wf.kind), " ", wf.tag, " ", wf.detail, "\n"); }
    assert(wf.kind == 0);
    var secs4: bank_statement::OfxSecurity[>..] = [];
    var n4: bank_statement::Note[>..] = [];
    var b4: u8[>..] = [];
    assert(bank_statement::parse_ofx_securities(out, lim, secs4, n4, b4).kind == 0);
    assert(secs4.len == 3 && n4.len == notes.len);
    var k: i64 = 0;
    while k < secs4.len {
        let x = secs4[k];
        let y = secs[k];
        assert(x.kind == y.kind && x.id == y.id && x.id_type == y.id_type && x.name == y.name);
        assert(x.ticker == y.ticker && x.fiid == y.fiid && x.rating == y.rating && x.memo == y.memo);
        assert(x.currency == y.currency && x.has_price == y.has_price);
        assert(x.price.num == y.price.num && x.price.den == y.price.den);
        assert(x.price_date.year == y.price_date.year && x.price_date.day == y.price_date.day);
        assert(x.note_count == y.note_count);
        var m: i64 = 0;
        while m < x.note_count {
            assert(n4[(x.note_start + m) as i64].tag == notes[(y.note_start + m) as i64].tag);
            assert(n4[(x.note_start + m) as i64].value == notes[(y.note_start + m) as i64].value);
            m += 1;
        }
        k += 1;
    }
    // The writer accepts one form of the list too.
    var out2: u8[>..] = [];
    assert(bank_statement::write_ofx_securities(secs, notes, common::ofx_wopts(211), lim, out2).kind == 0);
    assert(find(out2, "</SECNAME>") > 0);
    // Refusals: an unknown kind, an empty id, a long currency, a price
    // with no decimal form.
    let z = bank_statement::Rational { num: 0, den: 1 };
    var bad = bank_statement::OfxSecurity {
        kind: "BONDINFO", id: "1", id_type: "CUSIP", name: "B", ticker: "", fiid: "", rating: "", memo: "",
        currency: "", has_price: false, price: z, price_text: "", price_date: bank_statement::no_date(),
        note_start: 0, note_count: 0,
    };
    var o3: u8[>..] = [];
    var one: bank_statement::OfxSecurity[>..] = [bad];
    var no: bank_statement::Note[>..] = [];
    assert(bank_statement::write_ofx_securities(one, no, common::ofx_wopts(102), lim, o3).kind == bank_statement::F_UNKNOWN_TAG);
    bad.kind = "STOCKINFO";
    bad.id = "";
    var one2: bank_statement::OfxSecurity[>..] = [bad];
    assert(bank_statement::write_ofx_securities(one2, no, common::ofx_wopts(102), lim, o3).kind == bank_statement::F_SYNTAX);
    bad.id = "1";
    bad.currency = "EURO";
    var one3: bank_statement::OfxSecurity[>..] = [bad];
    assert(bank_statement::write_ofx_securities(one3, no, common::ofx_wopts(102), lim, o3).kind == bank_statement::F_SYNTAX);
    bad.currency = "";
    bad.has_price = true;
    bad.price = bank_statement::Rational { num: 1, den: 3 };
    var one4: bank_statement::OfxSecurity[>..] = [bad];
    assert(bank_statement::write_ofx_securities(one4, no, common::ofx_wopts(102), lim, o3).kind == bank_statement::F_AMOUNT);
}

fn test_ofx_profile() {
    let lim = bank_statement::default_limits();
    var pr = bank_statement::OfxProfile { found: false, updated: bank_statement::no_date(), name: "", addr1: "", addr2: "", addr3: "", city: "", state: "", postal_code: "", country: "", cs_phone: "", ts_phone: "", fax_phone: "", url: "", email: "" };
    var sn: bank_statement::OfxSignonInfo[>..] = [];
    var ms: bank_statement::OfxMsgSet[>..] = [];
    var notes: bank_statement::Note[>..] = [];
    var buf: u8[>..] = [];
    let f = bank_statement::parse_ofx_profile(common_2::PROFILE_SGML, lim, pr, sn, ms, notes, buf);
    if f.kind != 0 { print("FAIL profile ", bank_statement::kind_name(f.kind), " ", f.tag, " ", f.detail, "\n"); }
    assert(f.kind == 0);
    assert(pr.found && pr.name == "Test Bank & Trust" && pr.addr1 == "1 Main St" && pr.city == "Springfield");
    assert(pr.state == "IL" && pr.postal_code == "62701" && pr.country == "USA" && pr.cs_phone == "800-555-0100");
    assert(pr.url == "https://bank.example" && pr.email == "help@bank.example");
    assert(pr.updated.year == 2020 && pr.updated.month == 1 && pr.updated.day == 15);
    assert(sn.len == 1 && sn[0].realm == "BANK" && sn[0].min == 4 && sn[0].max == 12);
    assert(sn[0].char_type == "ALPHAANDNUMERIC" && sn[0].case_sen && !sn[0].special && sn[0].pin_change && sn[0].usercred1_label == "Branch");
    assert(ms.len == 2 && ms[0].kind == "SIGNONMSGSET" && ms[0].ver == "1" && ms[0].url == "https://bank.example/ofx");
    assert(ms[0].sec == "TYPE1" && ms[0].trans_psec == "Y" && ms[0].realm == "BANK" && ms[0].note_count == 3);
    assert(ms[1].kind == "BANKMSGSET" && ms[1].sp_name == "Fiserv" && ms[1].note_count == 5);
    assert(notes[ms[1].note_start + 3].tag == "INVALIDACCTTYPE" && notes[ms[1].note_start + 3].value == "CREDITLINE");
    // A file without a profile gives found false.
    var p2 = pr;
    p2.found = false;
    var s2: bank_statement::OfxSignonInfo[>..] = [];
    var m2: bank_statement::OfxMsgSet[>..] = [];
    var n2: bank_statement::Note[>..] = [];
    var b2: u8[>..] = [];
    assert(bank_statement::parse_ofx_profile(common_2::OFX_EXTRA, lim, p2, s2, m2, n2, b2).kind == 0 && !p2.found);
    // A flag that is not Y or N is a fault.
    let at = find(common_2::PROFILE_SGML, "<CASESEN>Y");
    assert(at > 0);
    var tb: u8[>..] = [];
    bank_statement::put(tb, common_2::PROFILE_SGML[..at]);
    bank_statement::put(tb, "<CASESEN>maybe");
    bank_statement::put(tb, common_2::PROFILE_SGML[at + 10..]);
    let bad: const u8[:] = tb;
    var s3: bank_statement::OfxSignonInfo[>..] = [];
    var m3: bank_statement::OfxMsgSet[>..] = [];
    var n3: bank_statement::Note[>..] = [];
    var b3: u8[>..] = [];
    var p3 = pr;
    assert(bank_statement::parse_ofx_profile(bad, lim, p3, s3, m3, n3, b3).kind == bank_statement::F_SYNTAX);
    // A small record limit is a fault.
    var small = bank_statement::default_limits();
    small.max_records = 1;
    var s4: bank_statement::OfxSignonInfo[>..] = [];
    var m4: bank_statement::OfxMsgSet[>..] = [];
    var n4: bank_statement::Note[>..] = [];
    var b4: u8[>..] = [];
    var p4 = pr;
    assert(bank_statement::parse_ofx_profile(common_2::PROFILE_SGML, small, p4, s4, m4, n4, b4).kind == bank_statement::F_LIMIT);
}

fn test_ofx_charset() {
    let lim = bank_statement::default_limits();
    // The header names Windows-1252 and the payee holds a smart quote.
    var text: const u8[:] = "OFXHEADER:100\nDATA:OFXSGML\nVERSION:102\nSECURITY:NONE\nENCODING:USASCII\nCHARSET:1252\nCOMPRESSION:NONE\nOLDFILEUID:NONE\nNEWFILEUID:NONE\n\n<OFX><BANKMSGSRSV1><STMTTRNRS><TRNUID>1<STMTRS><CURDEF>USD<BANKACCTFROM><BANKID>1<ACCTID>2<ACCTTYPE>CHECKING</BANKACCTFROM><BANKTRANLIST><STMTTRN><TRNTYPE>CHECK<DTPOSTED>20200101<TRNAMT>-10.00<FITID>1<NAME>Caf\x92 Ltd</NAME></STMTTRN></BANKTRANLIST><LEDGERBAL><BALAMT>0.00<DTASOF>20200101</LEDGERBAL></STMTRS></STMTTRNRS></BANKMSGSRSV1></OFX>\n";
    let opts = bank_statement::OfxOptions { .. };
    var sts: bank_statement::Statement[>..] = [];
    var ens: bank_statement::Entry[>..] = [];
    var bals: bank_statement::Balance[>..] = [];
    var notes: bank_statement::Note[>..] = [];
    var buf: u8[>..] = [];
    assert(bank_statement::parse_ofx(text, lim, opts, sts, ens, bals, notes, buf).kind == 0);
    assert(ens.len == 1 && ens[0].counter_name == "Caf\xe2\x80\x99 Ltd");
    // The option off keeps the raw byte.
    var lax = bank_statement::OfxOptions { .. };
    lax.auto_charset = false;
    var sts2: bank_statement::Statement[>..] = [];
    var ens2: bank_statement::Entry[>..] = [];
    var bals2: bank_statement::Balance[>..] = [];
    var notes2: bank_statement::Note[>..] = [];
    var buf2: u8[>..] = [];
    assert(bank_statement::parse_ofx(text, lim, lax, sts2, ens2, bals2, notes2, buf2).kind == 0);
    assert(ens2.len == 1 && ens2[0].counter_name == "Caf\x92 Ltd");
    // The tree reader decodes too.
    var tree: bank_statement::OfxNode[>..] = [];
    var buf3: u8[>..] = [];
    assert(bank_statement::parse_ofx_tree(text, lim, tree, buf3).kind == 0);
    var found = false;
    for n in tree {
        if n.name == "NAME" { assert(n.text == "Caf\xe2\x80\x99 Ltd"); found = true; }
    }
    assert(found);
}

fn test_ofx_net() {
    let lim = bank_statement::default_limits();
    var body: u8[>..] = [];
    var buf: u8[>..] = [];
    // A URL that is not HTTPS is a fault.
    let o1 = bank_statement::OfxFetch { url: "http://example.com/", timeout_ms: 0, content_type: "", user_agent: "" };
    let c1, f1 = bank_statement::ofx_fetch("x", o1, lim, body, buf);
    assert(f1.kind == bank_statement::F_SYNTAX && c1 == 0);
    // A URL with a space is a fault.
    let o2 = bank_statement::OfxFetch { url: "https://ex ample.com/", timeout_ms: 0, content_type: "", user_agent: "" };
    let c2, f2 = bank_statement::ofx_fetch("x", o2, lim, body, buf);
    assert(f2.kind == bank_statement::F_SYNTAX && c2 == 0);
    // A request over max_input is a fault.
    var small = bank_statement::default_limits();
    small.max_input = 2;
    let o3 = bank_statement::OfxFetch { url: "https://example.com/", timeout_ms: 0, content_type: "", user_agent: "" };
    let c3, f3 = bank_statement::ofx_fetch("abc", o3, small, body, buf);
    assert(f3.kind == bank_statement::F_LIMIT && c3 == 0);
    // A URL with a control byte is a fault.
    let o4 = bank_statement::OfxFetch { url: "https://example.com/\x01", timeout_ms: 0, content_type: "", user_agent: "" };
    let c4, f4 = bank_statement::ofx_fetch("x", o4, lim, body, buf);
    assert(f4.kind == bank_statement::F_SYNTAX && c4 == 0);
}

fn test_ofx_tree_repeats() {
    let lim = bank_statement::default_limits();
    // Two transactions in one list. The list may hold many.
    var two: bank_statement::OfxNode[>..] = [
        common::tree_node(0, "SIGNONMSGSRSV1", ""), common::tree_node(1, "SONRS", ""), common::tree_node(2, "STATUS", ""),
        common::tree_node(3, "CODE", "0"), common::tree_node(3, "SEVERITY", "INFO"),
        common::tree_node(2, "DTSERVER", "20200101120000"), common::tree_node(2, "LANGUAGE", "ENG"),
        common::tree_node(0, "BANKMSGSRSV1", ""), common::tree_node(1, "STMTTRNRS", ""), common::tree_node(2, "TRNUID", "T1"),
        common::tree_node(2, "STATUS", ""), common::tree_node(3, "CODE", "0"), common::tree_node(3, "SEVERITY", "INFO"),
        common::tree_node(2, "STMTRS", ""), common::tree_node(3, "CURDEF", "USD"),
        common::tree_node(3, "BANKACCTFROM", ""), common::tree_node(4, "BANKID", "987654321"),
        common::tree_node(4, "ACCTID", "12345"), common::tree_node(4, "ACCTTYPE", "CHECKING"),
        common::tree_node(3, "BANKTRANLIST", ""), common::tree_node(4, "DTSTART", "20200101000000"),
        common::tree_node(4, "DTEND", "20200102000000"),
        common::tree_node(4, "STMTTRN", ""), common::tree_node(5, "TRNTYPE", "DEBIT"), common::tree_node(5, "DTPOSTED", "20200101000000"),
        common::tree_node(5, "TRNAMT", "-1.00"), common::tree_node(5, "FITID", "1"),
        common::tree_node(4, "STMTTRN", ""), common::tree_node(5, "TRNTYPE", "DEBIT"), common::tree_node(5, "DTPOSTED", "20200101000000"),
        common::tree_node(5, "TRNAMT", "-2.00"), common::tree_node(5, "FITID", "2"),
        common::tree_node(3, "LEDGERBAL", ""), common::tree_node(4, "BALAMT", "1.00"), common::tree_node(4, "DTASOF", "20200102000000"),
    ];
    var out: u8[>..] = [];
    let w = bank_statement::write_ofx_tree(two, common::ofx_wopts(102), lim, out);
    if w.kind != 0 { print("FAIL repeat ", bank_statement::kind_name(w.kind), " ", w.tag, " ", w.detail, "\n"); }
    assert(w.kind == 0);
    // The output holds both transactions.
    var tree: bank_statement::OfxNode[>..] = [];
    var buf: u8[>..] = [];
    assert(bank_statement::parse_ofx_tree(out, lim, tree, buf).kind == 0);
    assert(tree.len == two.len);
    // Two aggregates that exclude each other fault. The specification
    // names one of them in the aggregate of a transaction.
    var excl: bank_statement::OfxNode[>..] = [
        common::tree_node(0, "SIGNONMSGSRSV1", ""), common::tree_node(1, "SONRS", ""), common::tree_node(2, "STATUS", ""),
        common::tree_node(3, "CODE", "0"), common::tree_node(3, "SEVERITY", "INFO"),
        common::tree_node(2, "DTSERVER", "20200101120000"), common::tree_node(2, "LANGUAGE", "ENG"),
        common::tree_node(0, "BANKMSGSRSV1", ""), common::tree_node(1, "STMTTRNRS", ""), common::tree_node(2, "TRNUID", "T1"),
        common::tree_node(2, "STATUS", ""), common::tree_node(3, "CODE", "0"), common::tree_node(3, "SEVERITY", "INFO"),
        common::tree_node(2, "STMTRS", ""), common::tree_node(3, "CURDEF", "USD"),
        common::tree_node(3, "BANKACCTFROM", ""), common::tree_node(4, "BANKID", "987654321"),
        common::tree_node(4, "ACCTID", "12345"), common::tree_node(4, "ACCTTYPE", "CHECKING"),
        common::tree_node(3, "BANKTRANLIST", ""), common::tree_node(4, "DTSTART", "20200101000000"),
        common::tree_node(4, "DTEND", "20200102000000"),
        common::tree_node(4, "STMTTRN", ""), common::tree_node(5, "TRNTYPE", "DEBIT"), common::tree_node(5, "DTPOSTED", "20200101000000"),
        common::tree_node(5, "TRNAMT", "-1.00"), common::tree_node(5, "FITID", "1"),
        common::tree_node(5, "BANKACCTTO", ""), common::tree_node(6, "BANKID", "123456789"),
        common::tree_node(6, "ACCTID", "54321"), common::tree_node(6, "ACCTTYPE", "SAVINGS"),
        common::tree_node(5, "CCACCTTO", ""), common::tree_node(6, "ACCTID", "99999"),
        common::tree_node(3, "LEDGERBAL", ""), common::tree_node(4, "BALAMT", "1.00"), common::tree_node(4, "DTASOF", "20200102000000"),
    ];
    var o3: u8[>..] = [];
    let w3 = bank_statement::write_ofx_tree(excl, common::ofx_wopts(102), lim, o3);
    assert(w3.kind == bank_statement::F_SYNTAX);
    assert(w3.detail == "two aggregates that exclude each other stand in one aggregate");
    // An element that may come only once faults when it comes twice.
    var dup: bank_statement::OfxNode[>..] = [
        common::tree_node(0, "SIGNONMSGSRSV1", ""), common::tree_node(1, "SONRS", ""), common::tree_node(2, "STATUS", ""),
        common::tree_node(3, "CODE", "0"), common::tree_node(3, "SEVERITY", "INFO"),
        common::tree_node(2, "DTSERVER", "20200101120000"), common::tree_node(2, "LANGUAGE", "ENG"),
        common::tree_node(2, "LANGUAGE", "FRA"),
    ];
    var o2: u8[>..] = [];
    let w2 = bank_statement::write_ofx_tree(dup, common::ofx_wopts(102), lim, o2);
    assert(w2.kind == bank_statement::F_SYNTAX);
    assert(w2.detail == "the element may come only once in this aggregate");
}

fn test_ofx_tree() {
    let lim = bank_statement::default_limits();
    var tree: bank_statement::OfxNode[>..] = [];
    var buf: u8[>..] = [];
    let f = bank_statement::parse_ofx_tree(common_2::OFX_INV, lim, tree, buf);
    if f.kind != 0 { print("FAIL tree ", bank_statement::kind_name(f.kind), " ", f.tag, " ", f.detail, "\n"); }
    assert(f.kind == 0);
    assert(tree.len > 20 && tree[0].depth == 0 && tree[0].name == "INVSTMTMSGSRSV1" && tree[0].text == "");
    // The investment file gives the same entries after a write in both forms.
    var base_s: bank_statement::Statement[>..] = [];
    var base_e: bank_statement::Entry[>..] = [];
    var base_b: bank_statement::Balance[>..] = [];
    var base_n: bank_statement::Note[>..] = [];
    var base_u: u8[>..] = [];
    let ropts = bank_statement::OfxOptions { .. };
    assert(bank_statement::parse_ofx(common_2::OFX_INV, lim, ropts, base_s, base_e, base_b, base_n, base_u).kind == 0);
    var v = 0;
    while v < 3 {
        var o = common::ofx_wopts(102);
        if v == 1 { o = common::ofx_wopts(211); o.indent = true; }
        if v == 2 { o.close_leaves = true; }
        var out: u8[>..] = [];
        let w = bank_statement::write_ofx_tree(tree, o, lim, out);
        if w.kind != 0 { print("FAIL tree write ", bank_statement::kind_name(w.kind), " ", w.tag, " ", w.detail, "\n"); }
        assert(w.kind == 0);
        var s2: bank_statement::Statement[>..] = [];
        var e2: bank_statement::Entry[>..] = [];
        var b2: bank_statement::Balance[>..] = [];
        var n2: bank_statement::Note[>..] = [];
        var u2: u8[>..] = [];
        assert(bank_statement::parse_ofx(out, lim, ropts, s2, e2, b2, n2, u2).kind == 0);
        assert(s2.len == base_s.len && e2.len == base_e.len && b2.len == base_b.len);
        var k: i64 = 0;
        while k < e2.len {
            assert(e2[k].type_id == base_e[k].type_id && e2[k].amount.minor == base_e[k].amount.minor);
            assert(e2[k].units_text == base_e[k].units_text && e2[k].unit_price_text == base_e[k].unit_price_text);
            k += 1;
        }
        // The tree of the output equals the tree of the input.
        var t2: bank_statement::OfxNode[>..] = [];
        var u3: u8[>..] = [];
        assert(bank_statement::parse_ofx_tree(out, lim, t2, u3).kind == 0);
        assert(t2.len == tree.len);
        k = 0;
        while k < t2.len {
            assert(t2[k].depth == tree[k].depth && t2[k].name == tree[k].name && t2[k].text == tree[k].text);
            k += 1;
        }
        v += 1;
    }
    // A sign-on request with a text that holds markup: the text is escaped.
    var req: bank_statement::OfxNode[>..] = [
        common::tree_node(0, "SIGNONMSGSRQV1", ""), common::tree_node(1, "SONRQ", ""), common::tree_node(2, "DTCLIENT", "20200101"),
        common::tree_node(2, "USERID", "a<b>&c"), common::tree_node(2, "LANGUAGE", "ENG"),
        common::tree_node(2, "APPID", "GOOSE"), common::tree_node(2, "APPVER", "2600"),
    ];
    var ro: u8[>..] = [];
    assert(bank_statement::write_ofx_tree(req, common::ofx_wopts(211), lim, ro).kind == 0);
    assert(find(ro, "a&lt;b&gt;&amp;c") > 0 && find(ro, "a<b>") < 0);
    var back: bank_statement::OfxNode[>..] = [];
    var rb: u8[>..] = [];
    assert(bank_statement::parse_ofx_tree(ro, lim, back, rb).kind == 0);
    assert(back.len == 7 && back[3].text == "a<b>&c");
    // Refusals of the loose writer: a bad name, a depth jump, a text in
    // an aggregate, a control byte, an empty leaf.
    var bad1: bank_statement::OfxNode[>..] = [common::tree_node(0, "a b", "x")];
    assert(common::run_tree_write(bad1, common::ofx_wopts_loose()) == bank_statement::F_SYNTAX);
    var bad2: bank_statement::OfxNode[>..] = [common::tree_node(0, "A", ""), common::tree_node(2, "B", "x")];
    assert(common::run_tree_write(bad2, common::ofx_wopts_loose()) == bank_statement::F_SYNTAX);
    var bad3: bank_statement::OfxNode[>..] = [common::tree_node(0, "A", "text"), common::tree_node(1, "B", "x")];
    assert(common::run_tree_write(bad3, common::ofx_wopts_loose()) == bank_statement::F_SYNTAX);
    var bad4: bank_statement::OfxNode[>..] = [common::tree_node(0, "A", "x\x01y")];
    assert(common::run_tree_write(bad4, common::ofx_wopts_loose()) == bank_statement::F_SYNTAX);
    var bad5: bank_statement::OfxNode[>..] = [common::tree_node(0, "MEMO", "")];
    assert(common::run_tree_write(bad5, common::ofx_wopts_loose()) == bank_statement::F_SYNTAX);
    var bad6: bank_statement::OfxNode[>..] = [common::tree_node(1, "A", "x")];
    assert(common::run_tree_write(bad6, common::ofx_wopts_loose()) == bank_statement::F_SYNTAX);
    // Refusals of the rule check: an unknown element, a missing
    // required element, a wrong order, a bad flag value, an unknown tag
    // inside an aggregate.
    var r1: bank_statement::OfxNode[>..] = [common::tree_node(0, "NOTREAL", "x")];
    assert(common::run_tree_write(r1, common::ofx_wopts(102)) == bank_statement::F_UNKNOWN_TAG);
    var r2: bank_statement::OfxNode[>..] = [
        common::tree_node(0, "SIGNONMSGSRQV1", ""), common::tree_node(1, "SONRQ", ""), common::tree_node(2, "DTCLIENT", "20200101"),
    ];
    assert(common::run_tree_write(r2, common::ofx_wopts(102)) == bank_statement::F_SYNTAX);
    var r3: bank_statement::OfxNode[>..] = [
        common::tree_node(0, "SIGNONMSGSRQV1", ""), common::tree_node(1, "SONRQ", ""), common::tree_node(2, "USERID", "alice"),
        common::tree_node(2, "DTCLIENT", "20200101"), common::tree_node(2, "LANGUAGE", "ENG"),
        common::tree_node(2, "APPID", "GOOSE"), common::tree_node(2, "APPVER", "2600"),
    ];
    assert(common::run_tree_write(r3, common::ofx_wopts(102)) == bank_statement::F_SYNTAX);
    var r4: bank_statement::OfxNode[>..] = [
        common::tree_node(0, "SIGNONMSGSRQV1", ""), common::tree_node(1, "SONRQ", ""), common::tree_node(2, "DTCLIENT", "20200101"),
        common::tree_node(2, "USERID", "alice"), common::tree_node(2, "GENUSERKEY", "MAYBE"),
        common::tree_node(2, "LANGUAGE", "ENG"),
        common::tree_node(2, "APPID", "GOOSE"), common::tree_node(2, "APPVER", "2600"),
    ];
    assert(common::run_tree_write(r4, common::ofx_wopts(102)) == bank_statement::F_SYNTAX);
    var r5: bank_statement::OfxNode[>..] = [
        common::tree_node(0, "SIGNONMSGSRQV1", ""), common::tree_node(1, "SONRQ", ""), common::tree_node(2, "DTCLIENT", "20200101"),
        common::tree_node(2, "USERID", "alice"), common::tree_node(2, "LANGUAGE", "ENG"),
        common::tree_node(2, "APPID", "GOOSE"), common::tree_node(2, "APPVER", "2600"),
        common::tree_node(2, "NOTINSONRQ", "x"),
    ];
    assert(common::run_tree_write(r5, common::ofx_wopts(102)) == bank_statement::F_UNKNOWN_TAG);
    // A private extension at the start of X passes the rule check.
    var px: bank_statement::OfxNode[>..] = [
        common::tree_node(0, "XTENSION", ""), common::tree_node(1, "XFIELD", "free"),
    ];
    assert(common::run_tree_write(px, common::ofx_wopts(102)) == 0);
}

fn test_ofx_extra() {
    let lim = bank_statement::default_limits();
    let ropts = bank_statement::OfxOptions { .. };
    var sts: bank_statement::Statement[>..] = [];
    var ens: bank_statement::Entry[>..] = [];
    var bals: bank_statement::Balance[>..] = [];
    var notes: bank_statement::Note[>..] = [];
    var buf: u8[>..] = [];
    let f = bank_statement::parse_ofx(common_2::OFX_EXTRA, lim, ropts, sts, ens, bals, notes, buf);
    if f.kind != 0 { print("FAIL ofx extra ", bank_statement::kind_name(f.kind), " ", f.tag, " ", f.detail, "\n"); }
    assert(f.kind == 0);
    assert(ens.len == 2);
    let x = ens[0].ofx;
    assert(x.user_date.year == 2020 && x.user_date.month == 1 && x.user_date.day == 4);
    assert(x.correct_ref == "A0" && x.correct_action == "REPLACE" && x.payee_id == "P77");
    assert(x.ext_name == "Cafe and Bar, Paris");
    assert(x.has_payee && x.payee.name == "Cafe & Bar" && x.payee.city == "Paris" && x.payee.country == "FRA");
    assert(ens[0].counter_name == "Cafe & Bar");
    // CURRENCY gives the currency and the exponent of the amount.
    assert(x.rate_kind == 'C' && x.rate.num == 91 && x.rate.den == 10000 && x.rate_symbol == "JPY");
    assert(ens[0].amount.currency == "JPY" && ens[0].amount.exp == 0 && ens[0].amount.minor == -5000);
    // ORIGCURRENCY leaves the currency of the statement.
    let y = ens[1].ofx;
    assert(y.rate_kind == 'O' && y.rate.num == 5 && y.rate.den == 4 && y.rate_symbol == "EUR");
    assert(ens[1].amount.currency == "USD" && ens[1].amount.minor == 1050);
    assert(!y.has_payee && y.user_date.year == 0);
    // Round trip in both forms.
    var v = 0;
    while v < 2 {
        var o = common::ofx_wopts(102);
        if v == 1 { o = common::ofx_wopts(203); o.indent = true; }
        var out: u8[>..] = [];
        let w = bank_statement::write_ofx(sts, ens, notes, o, lim, out);
        if w.kind != 0 { print("FAIL write extra ", bank_statement::kind_name(w.kind), " ", w.tag, " ", w.detail, "\n"); }
        assert(w.kind == 0);
        assert(find(out, "Cafe &amp; Bar") > 0);
        var s2: bank_statement::Statement[>..] = [];
        var e2: bank_statement::Entry[>..] = [];
        var b2: bank_statement::Balance[>..] = [];
        var n2: bank_statement::Note[>..] = [];
        var u2: u8[>..] = [];
        let g = bank_statement::parse_ofx(out, lim, ropts, s2, e2, b2, n2, u2);
        if g.kind != 0 { print("FAIL reread extra ", bank_statement::kind_name(g.kind), " ", g.tag, " ", g.detail, "\n"); }
        assert(g.kind == 0);
        assert(e2.len == 2);
        common::extra_equal(ens[0], e2[0]);
        common::extra_equal(ens[1], e2[1]);
        assert(e2[0].amount.currency == "JPY" && e2[0].amount.minor == -5000);
        v += 1;
    }
    // Refusals.
    let wo = common::ofx_wopts(102);
    ens[0].ofx.correct_action = "";
    var r1: u8[>..] = [];
    assert(bank_statement::write_ofx(sts, ens, notes, wo, lim, r1).kind == bank_statement::F_SYNTAX);
    ens[0].ofx.correct_action = "REPLACE";
    ens[0].ofx.payee_id = "1234567890123";
    var r2: u8[>..] = [];
    assert(bank_statement::write_ofx(sts, ens, notes, wo, lim, r2).kind == bank_statement::F_LIMIT);
    ens[0].ofx.payee_id = "P77";
    ens[0].ofx.payee.country = "fr";
    var r3: u8[>..] = [];
    assert(bank_statement::write_ofx(sts, ens, notes, wo, lim, r3).kind == bank_statement::F_SYNTAX);
    ens[0].ofx.payee.country = "FRA";
    ens[0].ofx.payee.city = "";
    var r4: u8[>..] = [];
    assert(bank_statement::write_ofx(sts, ens, notes, wo, lim, r4).kind == bank_statement::F_SYNTAX);
    ens[0].ofx.payee.city = "Paris";
    ens[1].ofx.rate_text = "1.30";
    var r5: u8[>..] = [];
    assert(bank_statement::write_ofx(sts, ens, notes, wo, lim, r5).kind == bank_statement::F_AMOUNT);
    ens[1].ofx.rate_text = "1,25";
    ens[1].ofx.rate_symbol = "ZZZ";
    var r6: u8[>..] = [];
    assert(bank_statement::write_ofx(sts, ens, notes, wo, lim, r6).kind == bank_statement::F_AMOUNT);
    ens[1].ofx.rate_symbol = "EUR";
    ens[0].ofx.ext_name = "x\ny";
    var r7: u8[>..] = [];
    assert(bank_statement::write_ofx(sts, ens, notes, wo, lim, r7).kind == bank_statement::F_SYNTAX);
}

fn test_ofx_extra_faults() {
    assert(common::ofx_kind("") == 0);
    assert(common::ofx_kind("<CORRECTACTION>MAYBE") == bank_statement::F_SYNTAX);
    assert(common::ofx_kind("<DTUSER>2020xx01") == bank_statement::F_DATE);
    assert(common::ofx_kind("<NAME>A<PAYEE><NAME>B</PAYEE>") == bank_statement::F_SYNTAX);
    assert(common::ofx_kind("<CURRENCY><CURRATE>1<CURSYM>EUR</CURRENCY><ORIGCURRENCY><CURRATE>1<CURSYM>EUR</ORIGCURRENCY>") == bank_statement::F_SYNTAX);
    assert(common::ofx_kind("<CURRENCY><CURRATE>0<CURSYM>EUR</CURRENCY>") == bank_statement::F_AMOUNT);
    assert(common::ofx_kind("<CURRENCY><CURRATE>1<CURSYM>ZZZ</CURRENCY>") == bank_statement::F_AMOUNT);
    assert(common::ofx_kind("<CURRENCY><CURSYM>EUR</CURRENCY>") == bank_statement::F_AMOUNT);
}

fn test_ofx_more() {
    let lim = bank_statement::default_limits();
    let ropts = bank_statement::OfxOptions { .. };
    var sts: bank_statement::Statement[>..] = [];
    var ens: bank_statement::Entry[>..] = [];
    var bals: bank_statement::Balance[>..] = [];
    var notes: bank_statement::Note[>..] = [];
    var buf: u8[>..] = [];
    let f = bank_statement::parse_ofx(common_2::OFX_EXTRA2, lim, ropts, sts, ens, bals, notes, buf);
    if f.kind != 0 { print("FAIL ofx more ", bank_statement::kind_name(f.kind), " ", f.tag, " ", f.detail, "\n"); }
    assert(f.kind == 0);
    assert(ens.len == 2);
    let x = ens[0].ofx;
    assert(x.has_sic && x.sic == 5411 && x.inv401k_source == "MATCH");
    assert(x.acct_to_kind == 'B' && x.acct_to.bank_id == "222222222" && x.acct_to.branch_id == "12");
    assert(x.acct_to.acct_id == "5550001" && x.acct_to.acct_type == "CHECKING" && x.acct_to.acct_key == "K1");
    // Two images are kept; the second sits in image2.
    assert(x.image_count == 2 && x.image.kind == "TRANSACTION" && x.image.ref == "https://bank.example/img?a=1&b=2");
    assert(x.image.ref_kind == "URL" && x.image.delay == 3 && x.image.ttl == 30 && x.image.check_sup == "FRONTONLY");
    assert(x.image2.kind == "STATEMENT" && x.image2.ref == "second" && x.image2.ref_kind == "OPAQUE");
    let y = ens[1].ofx;
    assert(y.acct_to_kind == 'C' && y.acct_to.acct_id == "4111000011112222");
    assert(y.image_count == 1 && y.image.avail.year == 2020 && y.image.avail.month == 2 && !y.image.has_delay);
    var v = 0;
    while v < 2 {
        var o = common::ofx_wopts(102);
        if v == 1 { o = common::ofx_wopts(211); o.indent = true; }
        var out: u8[>..] = [];
        let w = bank_statement::write_ofx(sts, ens, notes, o, lim, out);
        if w.kind != 0 { print("FAIL write more ", bank_statement::kind_name(w.kind), " ", w.tag, " ", w.detail, "\n"); }
        assert(w.kind == 0);
        assert(find(out, "a=1&amp;b=2") > 0);
        var s2: bank_statement::Statement[>..] = [];
        var e2: bank_statement::Entry[>..] = [];
        var b2: bank_statement::Balance[>..] = [];
        var n2: bank_statement::Note[>..] = [];
        var u2: u8[>..] = [];
        let g = bank_statement::parse_ofx(out, lim, ropts, s2, e2, b2, n2, u2);
        if g.kind != 0 { print("FAIL reread more ", bank_statement::kind_name(g.kind), " ", g.tag, " ", g.detail, "\n"); }
        assert(g.kind == 0);
        common::more_equal(ens[0], e2[0]);
        common::more_equal(ens[1], e2[1]);
        assert(e2[0].ofx.image_count == 2);
        v += 1;
    }
    // Refusals.
    let wo = common::ofx_wopts(102);
    ens[0].ofx.inv401k_source = "OTHER";
    var r1: u8[>..] = [];
    assert(bank_statement::write_ofx(sts, ens, notes, wo, lim, r1).kind == bank_statement::F_SYNTAX);
    ens[0].ofx.inv401k_source = "MATCH";
    ens[0].ofx.acct_to.acct_type = "GOLD";
    var r2: u8[>..] = [];
    assert(bank_statement::write_ofx(sts, ens, notes, wo, lim, r2).kind == bank_statement::F_SYNTAX);
    ens[0].ofx.acct_to.acct_type = "CHECKING";
    ens[0].ofx.acct_to.acct_id = "1234567890123456789012x";
    var r3: u8[>..] = [];
    assert(bank_statement::write_ofx(sts, ens, notes, wo, lim, r3).kind == bank_statement::F_LIMIT);
    ens[0].ofx.acct_to.acct_id = "5550001";
    ens[0].ofx.image.ref = "a\nb";
    var r4: u8[>..] = [];
    assert(bank_statement::write_ofx(sts, ens, notes, wo, lim, r4).kind == bank_statement::F_SYNTAX);
    ens[0].ofx.image.ref = "ok";
    ens[0].ofx.image.avail = bank_statement::Date { year: 2020, month: 2, day: 1 };
    var r5: u8[>..] = [];
    assert(bank_statement::write_ofx(sts, ens, notes, wo, lim, r5).kind == bank_statement::F_SYNTAX);
    ens[0].ofx.image.avail = bank_statement::no_date();
    ens[0].ofx.image.check_sup = "BOTH";
    var r7: u8[>..] = [];
    assert(bank_statement::write_ofx(sts, ens, notes, wo, lim, r7).kind == bank_statement::F_SYNTAX);
    ens[0].ofx.image.check_sup = "FRONTONLY";
    ens[0].ofx.image.delay = -1;
    var r8: u8[>..] = [];
    assert(bank_statement::write_ofx(sts, ens, notes, wo, lim, r8).kind == bank_statement::F_SYNTAX);
    ens[0].ofx.image.delay = 3;
    ens[0].ofx.sic = -1;
    var r9: u8[>..] = [];
    assert(bank_statement::write_ofx(sts, ens, notes, wo, lim, r9).kind == bank_statement::F_SYNTAX);
    ens[0].ofx.sic = 5411;
    ens[0].ofx.image.kind = "PHOTO";
    var r6: u8[>..] = [];
    assert(bank_statement::write_ofx(sts, ens, notes, wo, lim, r6).kind == bank_statement::F_SYNTAX);
}

fn test_ofx_more_faults() {
    assert(common::ofx_kind("<SIC>12ab") == bank_statement::F_SYNTAX);
    assert(common::ofx_kind("<INV401KSOURCE>NOPE") == bank_statement::F_SYNTAX);
    assert(common::ofx_kind("<BANKACCTTO><BANKID>1<ACCTID>2<ACCTTYPE>CD</BANKACCTTO><CCACCTTO><ACCTID>3</CCACCTTO>") == bank_statement::F_SYNTAX);
    assert(common::ofx_kind("<IMAGEDATA><IMAGETYPE>TAX<IMAGEREF>r<IMAGEREFTYPE>URL<IMAGEDELAY>1<DTIMAGEAVAIL>20200101</IMAGEDATA>") == bank_statement::F_SYNTAX);
    assert(common::ofx_kind("<IMAGEDATA><IMAGETYPE>TAX<IMAGEREF>r<IMAGEREFTYPE>NET</IMAGEDATA>") == bank_statement::F_SYNTAX);
    // A third image is a fault.
    assert(common::ofx_kind("<IMAGEDATA><IMAGETYPE>TAX<IMAGEREF>a<IMAGEREFTYPE>URL</IMAGEDATA><IMAGEDATA><IMAGETYPE>TAX<IMAGEREF>b<IMAGEREFTYPE>URL</IMAGEDATA><IMAGEDATA><IMAGETYPE>TAX<IMAGEREF>c<IMAGEREFTYPE>URL</IMAGEDATA>") == bank_statement::F_SYNTAX);
    assert(common::ofx_kind("<IMAGEDATA><IMAGETYPE>TAX<IMAGEREF>r<IMAGEREFTYPE>URL<IMAGEDELAY>-1</IMAGEDATA>") == bank_statement::F_SYNTAX);
    assert(common::ofx_kind("<IMAGEDATA><IMAGETYPE>TAX<IMAGEREF>r<IMAGEREFTYPE>URL<CHECKSUP>BOTH</IMAGEDATA>") == bank_statement::F_SYNTAX);
    assert(common::ofx_kind("<SIC>5411<INV401KSOURCE>MATCH") == 0);
}
