// Tests for the bank_statement package. Run with: goose run test/run.goose

import std;
import os;
import xml from "rekanalar/goose-xml@v2.0.0";
import process from "rekanalar/goose-process@v1.0.0";
import bank_statement from "..";

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

fn test_amount() {
    expect_amount("1234,56", 2, ',', 0, 123456);
    expect_amount("0,01", 2, ',', 0, 1);
    expect_amount("100,", 2, ',', 0, 10000);
    expect_amount("100", 2, ',', 0, 10000);
    expect_amount("1234,5", 2, ',', 0, 123450);
    expect_amount("1234", 0, ',', 0, 1234);
    expect_amount("1,234", 3, ',', 0, 1234);
    expect_amount("-1,234.56", 2, '.', ',', -123456);
    expect_amount("(1,234.56)", 2, '.', ',', -123456);
    expect_amount("1.234,56", 2, ',', '.', 123456);
    expect_amount("8.11", 2, '.', ',', 811);
    expect_amount("+5.00", 2, '.', ',', 500);
    expect_amount("92233720368547758,07", 2, ',', 0, 9223372036854775807);
    expect_amount("-92233720368547758,07", 2, ',', 0, -9223372036854775807);
    // The most negative i64 is a valid amount, whole and scaled.
    expect_amount("-9223372036854775808", 0, ',', 0, -9223372036854775808);
    expect_amount("-92233720368547758,08", 2, ',', 0, -9223372036854775808);
    expect_amount("-92233720368547758.08", 2, '.', 0, -9223372036854775808);
    // Trailing zeros of the decimal part change no value.
    expect_amount("-92233720368547758,0800", 2, ',', 0, -9223372036854775808);
}

fn test_amount_faults() {
    expect_amount_fault("", 2, ',', 0, 4);
    expect_amount_fault("1,2,3", 2, ',', 0, 4);
    expect_amount_fault("12a", 2, ',', 0, 4);
    expect_amount_fault("1,234", 2, ',', 0, 4);
    expect_amount_fault("1,23,456.00", 2, '.', ',', 4);
    expect_amount_fault("1,2345.00", 2, '.', ',', 4);
    expect_amount_fault("(1.00", 2, '.', ',', 4);
    expect_amount_fault("92233720368547758,08", 2, ',', 0, 5);
    // One unit beyond the range faults, positive and negative.
    expect_amount_fault("9223372036854775808", 0, ',', 0, 5);
    expect_amount_fault("-9223372036854775809", 0, ',', 0, 5);
    expect_amount_fault("-92233720368547758,09", 2, ',', 0, 5);
    // A decimal form that scales the value up out of the range faults.
    expect_amount_fault("-9223372036854775808.00", 2, '.', 0, 5);
    expect_amount_fault("99999999999999999999999999999999999999999999999999999999", 2, ',', 0, 5);
    expect_amount_fault("-", 2, ',', 0, 4);
}

fn test_exponent() {
    assert(bank_statement::currency_exponent("EUR") == 2);
    assert(bank_statement::currency_exponent("JPY") == 0);
    assert(bank_statement::currency_exponent("KWD") == 3);
    assert(bank_statement::currency_exponent("") == 2);
    assert(bank_statement::currency_exponent("ZZZ") == 2);
}

// test_currency_table checks the whole ISO 4217 table: the count, the
// sort order, the share of every exponent group and one code of each
// group. The values come from the list one file of the SIX group of
// 2026-09-17.
fn test_currency_table() {
    assert(bank_statement::CURRENCY_CODES.len == 178);
    var zero = 0;
    var two = 0;
    var three = 0;
    var four = 0;
    var i: i64 = 0;
    while i < bank_statement::CURRENCY_CODES.len {
        let e = bank_statement::CURRENCY_EXPONENTS[i];
        assert(e >= 0 && e <= 4);
        if e == 0 { zero += 1; }
        else if e == 2 { two += 1; }
        else if e == 3 { three += 1; }
        else { four += 1; }
        if i > 0 {
            assert(bank_statement::compare_bytes(bank_statement::CURRENCY_CODES[i - 1], bank_statement::CURRENCY_CODES[i]) < 0);
        }
        i += 1;
    }
    assert(zero == 30);  // 17 without minor digits, 13 not applicable
    assert(two == 139);
    assert(three == 7);
    assert(four == 2);
    // Spot values from the ISO file, one code or more of each group.
    assert(bank_statement::currency_exponent("BIF") == 0);
    assert(bank_statement::currency_exponent("JPY") == 0);
    assert(bank_statement::currency_exponent("XAU") == 0);
    assert(bank_statement::currency_exponent("XXX") == 0);
    assert(bank_statement::currency_exponent("BHD") == 3);
    assert(bank_statement::currency_exponent("TND") == 3);
    assert(bank_statement::currency_exponent("CLF") == 4);
    assert(bank_statement::currency_exponent("UYW") == 4);
    assert(bank_statement::currency_exponent("USD") == 2);
    assert(bank_statement::currency_exponent("CHF") == 2);
    assert(bank_statement::currency_exponent("ZZZ") == 2);
    assert(bank_statement::currency_known("EUR"));
    assert(!bank_statement::currency_known("ZZZ"));
    // The lookup finds every code of the table.
    i = 0;
    while i < bank_statement::CURRENCY_CODES.len {
        let e = bank_statement::currency_exponent(bank_statement::CURRENCY_CODES[i]);
        assert(e == bank_statement::CURRENCY_EXPONENTS[i]);
        i += 1;
    }
}

const STMT1: const u8[:] = "{1:F01BANKBEBBAXXX0000000000}{2:O9401234250101BANKDEFFAXXX00000000002501011234N}{4:\n:20:STMT001\n:25:DE89370400440532013000\n:28C:00001/001\n:60F:C250101EUR1000,00\n:61:2501020102C500,00NTRFNONREF//BANKREF1\nSUPPLEMENT\n:86:020?00BANK TRANSFER?20PURPOSE\n?21LINE 2?32JOHN DOE\n:61:250103D200,50NCHKCHK123\n:62F:C250103EUR1299,50\n:64:C250103EUR1299,50\n-}";

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

fn test_mt940_basic() {
    let lim = bank_statement::default_limits();
    let opts = bank_statement::Mt940Options { .. };
    var sts: bank_statement::Statement[>..] = [];
    var ens: bank_statement::Entry[>..] = [];
    var bals: bank_statement::Balance[>..] = [];
    var notes: bank_statement::Note[>..] = [];
    var xbuf2: u8[>..] = [];
    let f = bank_statement::parse_mt940(STMT1, lim, opts, sts, ens, bals, notes, xbuf2);
    if f.kind != 0 { print("FAIL ", bank_statement::kind_name(f.kind), " line ", f.line, " ", f.tag, " ", f.detail, "\n"); }
    assert(f.kind == 0);
    assert(sts.len == 1);
    let st = sts[0];
    assert(st.reference == "STMT001");
    assert(st.account == "DE89370400440532013000");
    assert(st.number == "00001");
    assert(st.sequence == "001");
    assert(st.opening.credit);
    assert(st.opening.amount.minor == 100000);
    assert(st.opening.amount.currency == "EUR");
    assert(st.opening.date.year == 2025 && st.opening.date.month == 1 && st.opening.date.day == 1);
    assert(st.closing.amount.minor == 129950);
    assert(st.entry_count == 2);
    assert(st.balance_count == 3);
    assert(ens.len == 2);
    let e = ens[0];
    assert(e.value_date.month == 1 && e.value_date.day == 2);
    assert(e.entry_date.year == 2025 && e.entry_date.month == 1 && e.entry_date.day == 2);
    assert(e.mark == "C");
    assert(e.amount.minor == 50000);
    assert(e.type_id == "NTRF");
    assert(e.customer_ref == "NONREF");
    assert(e.bank_ref == "BANKREF1");
    assert(e.supplementary == "SUPPLEMENT");
    assert(starts_with(e.narrative, "020?00BANK"));
    let e2 = ens[1];
    assert(e2.mark == "D");
    assert(e2.amount.minor == 20050);
    assert(e2.entry_date.year == 0);
    assert(e2.customer_ref == "CHK123");
    assert(e2.narrative.len == 0);
    assert(bals[2].kind == bank_statement::BAL_AVAILABLE);
}

fn test_mt940_balance_error() {
    // One cent off: the closing balance does not match.
    run_mt940("{4:\n:20:A\n:25:X\n:60F:C250101EUR1000,00\n:61:250102C500,00NTRFREF\n:62F:C250102EUR1500,01\n-}", false, 7, "62F");
    // The same file passes with the check off.
    run_mt940("{4:\n:20:A\n:25:X\n:60F:C250101EUR1000,00\n:61:250102C500,00NTRFREF\n:62F:C250102EUR1500,01\n-}", true, 0, "");
    // A good statement with a debit opening balance.
    run_mt940(":20:A\n:60F:D250101EUR100,00\n:61:250102C150,00NTRFREF\n:62F:C250102EUR50,00\n", false, 0, "");
    // Reversals: RC takes money out, RD puts money in.
    run_mt940(":20:A\n:60F:C250101EUR100,00\n:61:250102RC30,00NTRFREF\n:61:250102RD10,00NTRFREF\n:62F:C250102EUR80,00\n", false, 0, "");
    // No closing balance with the check on is a fault.
    run_mt940(":20:A\n:60F:C250101EUR100,00\n", false, 7, "62F");
}

fn test_mt940_faults() {
    run_mt940(":20:A\n:99:X\n", false, 3, "99");
    run_mt940(":25:X\n", false, 2, "25");
    run_mt940("stray\n", false, 2, "");
    run_mt940(":20:A\n:60F:X250101EUR1,00\n", false, 2, "60F");
    run_mt940(":20:A\n:60F:C251301EUR1,00\n", false, 6, "60F");
    run_mt940(":20:A\n:60F:C250101EUR1,2,3\n", false, 4, "60F");
}

fn test_mt940_multi() {
    let lim = bank_statement::default_limits();
    let opts = bank_statement::Mt940Options { .. };
    var sts: bank_statement::Statement[>..] = [];
    var ens: bank_statement::Entry[>..] = [];
    var bals: bank_statement::Balance[>..] = [];
    var notes: bank_statement::Note[>..] = [];
    // Three statements, mixed line ends, intermediate balances, no :28C:.
    let text = ":20:ONE\r\n:60M:C250101EUR10,00\r\n:62M:C250101EUR10,00\r\n-\r\n:20:TWO\n:60M:C250101EUR10,00\n:61:250101C1,00NTRFX\n:62F:C250101EUR11,00\n-\n:20:THREE\n:60F:C250101JPY5\n:61:250101D5NTRFX\n:62F:C250101JPY0\n";
    var xbuf3: u8[>..] = [];
    let f = bank_statement::parse_mt940(text, lim, opts, sts, ens, bals, notes, xbuf3);
    if f.kind != 0 { print("FAIL ", bank_statement::kind_name(f.kind), " line ", f.line, " ", f.tag, " ", f.detail, "\n"); }
    assert(f.kind == 0);
    assert(sts.len == 3);
    assert(sts[0].reference == "ONE");
    assert(sts[0].opening.intermediate);
    assert(sts[0].number.len == 0);
    assert(sts[1].entry_count == 1);
    assert(sts[2].opening.amount.exp == 0);
    assert(ens.len == 2);
    assert(sts[2].entry_start == 1);
}

fn test_currency_rules() {
    // An entry before any balance or floor limit has no currency.
    run_mt940(":20:A\n:61:250101C1NTRFX\n:60F:C250101JPY0\n:62F:C250101JPY1\n", false, 2, "61");
    // An interim report takes the currency of its floor limit.
    let lim = bank_statement::default_limits();
    let opts = bank_statement::Mt940Options { .. };
    var sts: bank_statement::Statement[>..] = [];
    var ens: bank_statement::Entry[>..] = [];
    var bals: bank_statement::Balance[>..] = [];
    var notes: bank_statement::Note[>..] = [];
    var xbuf4: u8[>..] = [];
    let f = bank_statement::parse_mt940(":20:I\n:34F:JPY0\n:61:250101C150NTRFX\n", lim, opts, sts, ens, bals, notes, xbuf4);
    assert(f.kind == 0);
    assert(ens[0].amount.minor == 150 && ens[0].amount.exp == 0 && ens[0].amount.currency == "JPY");
    assert(!sts[0].balance_checked);
}

fn test_interim_flag_keeps_check() {
    // A :13D: or :34F: line must not turn the balance check off.
    run_mt940(":20:A\n:13D:2501021530+0100\n:60F:C250101EUR100,00\n:61:250101C1,00NTRFX\n:62F:C250101EUR999,00\n", false, 7, "62F");
    run_mt940(":20:A\n:34F:EUR0,\n:60F:C250101EUR100,00\n:61:250101C1,00NTRFX\n:62F:C250101EUR999,00\n", false, 7, "62F");
    // An interim report with only one balance is not a statement: no fault from the missing one.
    run_mt940(":20:A\n:34F:EUR0,\n:61:250101C1,00NTRFX\n", false, 0, "");
    // A good statement with an interim line still passes.
    run_mt940(":20:A\n:34F:EUR0,\n:60F:C250101EUR100,00\n:61:250101C1,00NTRFX\n:62F:C250101EUR101,00\n", false, 0, "");
}

fn test_balance_checked() {
    let lim = bank_statement::default_limits();
    var sts: bank_statement::Statement[>..] = [];
    var ens: bank_statement::Entry[>..] = [];
    var bals: bank_statement::Balance[>..] = [];
    var notes: bank_statement::Note[>..] = [];
    let text = ":20:A\n:60F:C250101EUR0,00\n:62F:C250101EUR0,00\n";
    let on = bank_statement::Mt940Options { .. };
    let off = bank_statement::Mt940Options { skip_balance_check: true, check_fields: false, style: 0 };
    var xbuf5: u8[>..] = [];
    let f = bank_statement::parse_mt940(text, lim, on, sts, ens, bals, notes, xbuf5);
    assert(f.kind == 0 && sts[0].balance_checked);
    var sts2: bank_statement::Statement[>..] = [];
    var ens2: bank_statement::Entry[>..] = [];
    var bals2: bank_statement::Balance[>..] = [];
    var notes2: bank_statement::Note[>..] = [];
    var xbuf6: u8[>..] = [];
    let g = bank_statement::parse_mt940(text, lim, off, sts2, ens2, bals2, notes2, xbuf6);
    assert(g.kind == 0 && !sts2[0].balance_checked);
}

fn test_lone_cr() {
    run_mt940(":20:A\r:60F:C250101EUR0,00\r", false, 2, "");
    run_mt940(":20:A\r\n:60F:C250101EUR0,00\r\n:62F:C250101EUR0,00\r\n", false, 0, "");
    run_qif("!Type:Bank\rT1\r", 1, 2);
}

fn test_mt942() {
    let lim = bank_statement::default_limits();
    let opts = bank_statement::Mt940Options { .. };
    var sts: bank_statement::Statement[>..] = [];
    var ens: bank_statement::Entry[>..] = [];
    var bals: bank_statement::Balance[>..] = [];
    var notes: bank_statement::Note[>..] = [];
    let text = ":20:INTERIM\n:25:ACC\n:28C:5/1\n:34F:EUR0,\n:34F:EURD100,\n:13D:2501021530+0100\n:61:250102C500,00NTRFREF\n:61:250102D20,00NTRFREF2\n:90D:1EUR20,00\n:90C:1EUR500,00\n";
    var xbuf7: u8[>..] = [];
    let f = bank_statement::parse_mt940(text, lim, opts, sts, ens, bals, notes, xbuf7);
    if f.kind != 0 { print("FAIL ", bank_statement::kind_name(f.kind), " line ", f.line, " ", f.tag, " ", f.detail, "\n"); }
    assert(f.kind == 0);
    let st = sts[0];
    assert(st.is_interim);
    assert(st.floor.minor == 0 && st.floor_mark == '-');
    assert(st.floor2.minor == 10000 && st.floor2_mark == 'D');
    assert(st.has_report_time && st.report_minutes == 15 * 60 + 30 && st.report_offset == 60);
    assert(st.debit_count == 1 && st.debit_total.minor == 2000);
    assert(st.credit_count == 1 && st.credit_total.minor == 50000);
    // A wrong total is an error.
    run_mt940(":20:I\n:34F:EUR0,\n:61:250102C500,00NTRFREF\n:90C:1EUR499,99\n", false, 8, "90C");
    run_mt940(":20:I\n:34F:EUR0,\n:61:250102C500,00NTRFREF\n:90C:2EUR500,00\n", false, 8, "90C");
}

fn test_narrative() {
    let lim = bank_statement::default_limits();
    var out: bank_statement::NarrativeField[>..] = [];
    let k, f = bank_statement::split_narrative("020?00BANK TRANSFER?20PURPOSE?21LINE 2?32NAME", lim, out);
    assert(f.kind == 0 && k == bank_statement::NARR_SUBFIELD);
    assert(out.len == 5);
    assert(out[0].key == "code" && out[0].value == "020");
    assert(out[1].key == "00" && out[1].value == "BANK TRANSFER");
    assert(out[2].key == "20" && out[2].value == "PURPOSE");
    assert(out[4].key == "32" && out[4].value == "NAME");
}

fn test_narrative_pairs() {
    let lim = bank_statement::default_limits();
    var out: bank_statement::NarrativeField[>..] = [];
    let k, f = bank_statement::split_narrative("/EREF/ABC123/IBAN/DE89370400440532013000/REMI/Invoice 1/2/", lim, out);
    assert(f.kind == 0 && k == bank_statement::NARR_PAIRS);
    assert(out.len == 3);
    assert(out[0].key == "EREF" && out[0].value == "ABC123");
    assert(out[1].key == "IBAN" && out[1].value == "DE89370400440532013000");
    assert(out[2].key == "REMI" && out[2].value == "Invoice 1/2");
}

fn test_narrative_plain() {
    let lim = bank_statement::default_limits();
    var out: bank_statement::NarrativeField[>..] = [];
    let k, f = bank_statement::split_narrative("just some words", lim, out);
    assert(f.kind == 0 && k == bank_statement::NARR_PLAIN && out.len == 0);
}

const QIF1: const u8[:] = "!Type:Bank\nD12/31'25\nT-1,234.56\nCX\nN1001\nPAcme Corp\nMInvoice\nLGroceries:Food/Home\nAStreet 1\nAtown\nZodd\n^\nD1/ 2'25\nT(50.00)\nSRent\nEhalf\n$-30.00\nSUtil\n$-20.00\n%40\n^\nD3/4/25\nT8.11";

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

fn test_qif_basic() {
    let lim = bank_statement::default_limits();
    let opts = bank_statement::QifOptions { date_order: bank_statement::DATE_MDY, .. };
    var recs: bank_statement::QifRecord[>..] = [];
    var spl: bank_statement::QifSplit[>..] = [];
    var ext: bank_statement::QifField[>..] = [];
    var xbuf9: u8[>..] = [];
    let f = bank_statement::parse_qif(QIF1, lim, opts, recs, spl, ext, xbuf9);
    if f.kind != 0 { print("FAIL ", bank_statement::kind_name(f.kind), " line ", f.line, " ", f.detail, "\n"); }
    assert(f.kind == 0);
    assert(recs.len == 3);
    let r = recs[0];
    assert(r.section == bank_statement::Q_BANK);
    assert(r.date.year == 2025 && r.date.month == 12 && r.date.day == 31);
    assert(r.has_amount && r.amount.minor == -123456);
    assert(r.cleared == 'X');
    assert(r.number == "1001" && r.payee == "Acme Corp" && r.memo == "Invoice");
    assert(r.category == "Groceries:Food/Home");
    // Both A lines and the unknown Z line are kept as fields.
    assert(r.field_count == 3);
    assert(ext[0].code == 'A' && ext[0].value == "Street 1");
    assert(ext[2].code == 'Z' && ext[2].value == "odd");
    let r2 = recs[1];
    assert(r2.date.year == 2025 && r2.date.month == 1 && r2.date.day == 2);
    assert(r2.amount.minor == -5000);
    assert(r2.split_count == 2);
    assert(spl[0].category == "Rent" && spl[0].memo == "half" && spl[0].amount.minor == -3000);
    assert(spl[1].category == "Util" && spl[1].amount.minor == -2000);
    assert(spl[1].has_percent && spl[1].percent.num == 40 && spl[1].percent.den == 1);
    assert(spl[1].percent_text == "40");
    // The last record has no ^.
    let r3 = recs[2];
    assert(r3.date.year == 2025 && r3.date.month == 3 && r3.date.day == 4);
    assert(r3.amount.minor == 811);
}

fn test_qif_category() {
    let c = bank_statement::split_category("Groceries:Food/Home");
    assert(c.name == "Groceries" && c.sub == "Food" && c.class == "Home");
    let t = bank_statement::split_category("[Savings]/Trip");
    assert(t.transfer == "Savings" && t.class == "Trip");
    let p = bank_statement::split_category("Salary");
    assert(p.name == "Salary" && p.sub.len == 0);
}

fn test_qif_sections() {
    let lim = bank_statement::default_limits();
    let opts = bank_statement::QifOptions { date_order: bank_statement::DATE_DMY, decimal: ',', .. };
    var recs: bank_statement::QifRecord[>..] = [];
    var spl: bank_statement::QifSplit[>..] = [];
    var ext: bank_statement::QifField[>..] = [];
    let text = "!Account\nNChecking\nTBank\n^\n!Type:Cat\nNSalary\nI\n^\n!Type:Invst\nD31.12.2025\nNBuy\nYAcme\nI10,5\nQ100\nO9,99\nT1.050,00\n$1.050,00\n^\n!Type:Prices\n\"ACME\",10.5,\"31.12.2025\"\n^\n";
    var xbuf10: u8[>..] = [];
    let f = bank_statement::parse_qif(text, lim, opts, recs, spl, ext, xbuf10);
    if f.kind != 0 { print("FAIL ", bank_statement::kind_name(f.kind), " line ", f.line, " ", f.detail, "\n"); }
    assert(f.kind == 0);
    assert(recs.len == 4);
    assert(recs[0].section == bank_statement::Q_ACCOUNT && recs[0].field_count == 2);
    assert(recs[1].section == bank_statement::Q_CAT && recs[1].field_count == 2);
    let iv = recs[2];
    assert(iv.section == bank_statement::Q_INVST);
    assert(iv.action == "Buy" && iv.security == "Acme");
    // 10.5, 100 and 9,99 come back as exact rationals and keep their text.
    assert(iv.has_price && iv.price.num == 21 && iv.price.den == 2 && iv.price_text == "10,5");
    assert(iv.has_quantity && iv.quantity.num == 100 && iv.quantity.den == 1 && iv.quantity_text == "100");
    assert(iv.has_commission && iv.commission.num == 999 && iv.commission.den == 100 && iv.commission_text == "9,99");
    assert(iv.amount.minor == 105000);
    assert(iv.date.year == 2025 && iv.date.day == 31);
    assert(iv.field_count == 1 && ext[recs[2].field_start].code == '$');
    assert(recs[3].section == bank_statement::Q_PRICES && recs[3].field_count == 1);
    assert(spl.len == 0);
}

fn test_qif_dates() {
    // No order and a date that fits two orders: the caller must say.
    run_qif("!Type:Bank\nD01/02/2025\n^\n", bank_statement::DATE_AUTO, 9);
    // A part above 12 gives the order.
    run_qif("!Type:Bank\nD13/02/2025\n^\nD2025-03-04\n^\n", bank_statement::DATE_AUTO, 0);
    run_qif("!Type:Bank\nD02/13/2025\n^\n", bank_statement::DATE_AUTO, 0);
    // Equal day and month are no ambiguity.
    run_qif("!Type:Bank\nD05/05/2025\n^\n", bank_statement::DATE_AUTO, 0);
    // Detection reads the whole file.
    run_qif("!Type:Bank\nD01/02/2025\n^\nD13/02/2025\n^\n", bank_statement::DATE_DETECT, 0);
    run_qif("!Type:Bank\nD01/02/2025\n^\nD03/04/2025\n^\n", bank_statement::DATE_DETECT, 9);
    run_qif("!Type:Bank\nD13/02/2025\n^\nD02/13/2025\n^\n", bank_statement::DATE_DETECT, 6);
    // A day that does not exist.
    run_qif("!Type:Bank\nD02/30/2025\n^\n", bank_statement::DATE_MDY, 6);
    run_qif("!Type:Bank\nDabc\n^\n", bank_statement::DATE_MDY, 6);
    // The year pivot: 99 is 1999 and 24 is 2024.
    let lim = bank_statement::default_limits();
    let opts = bank_statement::QifOptions { date_order: bank_statement::DATE_MDY, .. };
    var recs: bank_statement::QifRecord[>..] = [];
    var spl: bank_statement::QifSplit[>..] = [];
    var ext: bank_statement::QifField[>..] = [];
    var xbuf11: u8[>..] = [];
    let f = bank_statement::parse_qif("!Type:Bank\nD1/2/99\n^\nD1/2/24\n^\nD20250102\n^\n", lim, opts, recs, spl, ext, xbuf11);
    assert(f.kind == 0);
    assert(recs[0].date.year == 1999 && recs[1].date.year == 2024);
}

fn test_qif_faults() {
    run_qif("!Type:Nope\n", 1, 3);
    run_qif("D1/1/25\n", 1, 2);
    run_qif("!Type:Bank\nTabc\n^\n", 1, 4);
    run_qif("!Type:Bank\nT1,2,3\n^\n", 1, 4);
    run_qif("!Type:Bank\nCQ\n^\n", 1, 2);
    run_qif("", 1, 0);
    // An unknown header names the header text, not just the !.
    let lim = bank_statement::default_limits();
    let opts = bank_statement::QifOptions { .. };
    var recs: bank_statement::QifRecord[>..] = [];
    var spl: bank_statement::QifSplit[>..] = [];
    var ext: bank_statement::QifField[>..] = [];
    var xbuf12: u8[>..] = [];
    let f = bank_statement::parse_qif("!Type:Purple\n", lim, opts, recs, spl, ext, xbuf12);
    assert(f.kind == 3 && f.tag == "!Type:Purple");
}

// test_qif_headers reads the headers the first release did not know and
// the case and space forms of the old ones.
fn test_qif_headers() {
    let lim = bank_statement::default_limits();
    let opts = bank_statement::QifOptions { date_order: bank_statement::DATE_MDY, .. };
    // Oth S, Invoice, Tax and Bill hold typed transaction records.
    var text = "!Type:Oth S\nD01/02/2025\nT100\n^\n!Type:Invoice\nD01/03/2025\nT200\n^\n!Type:Tax\nT300\n^\n!Type:Bill\nT400\n^\n";
    var recs: bank_statement::QifRecord[>..] = [];
    var spl: bank_statement::QifSplit[>..] = [];
    var ext: bank_statement::QifField[>..] = [];
    var xbuf13: u8[>..] = [];
    var f = bank_statement::parse_qif(text, lim, opts, recs, spl, ext, xbuf13);
    if f.kind != 0 { print("FAIL headers ", bank_statement::kind_name(f.kind), " line ", f.line, " ", f.detail, "\n"); }
    assert(f.kind == 0);
    assert(recs.len == 4);
    assert(recs[0].section == bank_statement::Q_OTH_S && recs[0].has_amount && recs[0].amount.minor == 10000);
    assert(recs[1].section == bank_statement::Q_INVOICE && recs[1].amount.minor == 20000);
    assert(recs[2].section == bank_statement::Q_TAX && recs[2].amount.minor == 30000);
    assert(recs[3].section == bank_statement::Q_BILL && recs[3].amount.minor == 40000);
    // Budget and Tag keep every line as a field, like Cat and Class.
    text = "!Type:Budget\nNGroceries\nB100\n^\n!Type:Tag\nNTravel\nDwork trips\n^\n";
    var recs2: bank_statement::QifRecord[>..] = [];
    var spl2: bank_statement::QifSplit[>..] = [];
    var ext2: bank_statement::QifField[>..] = [];
    var xbuf14: u8[>..] = [];
    f = bank_statement::parse_qif(text, lim, opts, recs2, spl2, ext2, xbuf14);
    assert(f.kind == 0);
    assert(recs2[0].section == bank_statement::Q_BUDGET && recs2[0].field_count == 2);
    assert(recs2[1].section == bank_statement::Q_TAG && recs2[1].field_count == 2);
    assert(ext2[0].code == 'N' && ext2[0].value == "Groceries");
    assert(ext2[3].code == 'D' && ext2[3].value == "work trips");
    // Case, space and no-blank forms open the same sections.
    var recs3: bank_statement::QifRecord[>..] = [];
    var spl3: bank_statement::QifSplit[>..] = [];
    var ext3: bank_statement::QifField[>..] = [];
    var xbuf15: u8[>..] = [];
    f = bank_statement::parse_qif("!type bank\nT1\n^\n!TYPE:BANK\nT2\n^\n!Type:OthA\nT3\n^\n!type oth a\nT4\n^\n", lim, opts, recs3, spl3, ext3, xbuf15);
    assert(f.kind == 0);
    assert(recs3.len == 4);
    assert(recs3[0].section == bank_statement::Q_BANK && recs3[1].section == bank_statement::Q_BANK);
    assert(recs3[2].section == bank_statement::Q_OTH_A && recs3[3].section == bank_statement::Q_OTH_A);
}

// test_qif_u_amount checks the U rule and the ... marker.
fn test_qif_u_amount() {
    let lim = bank_statement::default_limits();
    let opts = bank_statement::QifOptions { date_order: bank_statement::DATE_MDY, .. };
    var recs: bank_statement::QifRecord[>..] = [];
    var spl: bank_statement::QifSplit[>..] = [];
    var ext: bank_statement::QifField[>..] = [];
    // U wins over T in both orders. The losing value stays reachable.
    let text = "!Type:Bank\nT100.00\nU200.00\n^\nU300.00\nT400.00\n^\n";
    var xbuf16: u8[>..] = [];
    let f = bank_statement::parse_qif(text, lim, opts, recs, spl, ext, xbuf16);
    assert(f.kind == 0);
    assert(recs.len == 2);
    assert(recs[0].has_amount && recs[0].amount.minor == 20000 && recs[0].amount_code == 'U');
    assert(recs[0].has_alt_amount && recs[0].alt_amount.minor == 10000);
    assert(recs[1].has_amount && recs[1].amount.minor == 30000 && recs[1].amount_code == 'U');
    assert(recs[1].has_alt_amount && recs[1].alt_amount.minor == 40000);
    // A T alone names its code and holds no alt value.
    var recs2: bank_statement::QifRecord[>..] = [];
    var spl2: bank_statement::QifSplit[>..] = [];
    var ext2: bank_statement::QifField[>..] = [];
    var xbuf17: u8[>..] = [];
    let f2 = bank_statement::parse_qif("!Type:Bank\nT100.00\n^\n", lim, opts, recs2, spl2, ext2, xbuf17);
    assert(f2.kind == 0);
    assert(recs2[0].amount_code == 'T' && !recs2[0].has_alt_amount);
    // A value that starts with ... sets no amount and stays a field.
    var recs3: bank_statement::QifRecord[>..] = [];
    var spl3: bank_statement::QifSplit[>..] = [];
    var ext3: bank_statement::QifField[>..] = [];
    let text3 = "!Type:Bank\nT...\n^\nU...\n^\nSOne\n$...\nSTwo\n$5\n^\n";
    var xbuf18: u8[>..] = [];
    let f3 = bank_statement::parse_qif(text3, lim, opts, recs3, spl3, ext3, xbuf18);
    assert(f3.kind == 0);
    assert(recs3.len == 3);
    assert(!recs3[0].has_amount && recs3[0].field_count == 1 && ext3[0].code == 'T');
    assert(!recs3[1].has_amount && recs3[1].field_count == 1);
    assert(!spl3[0].has_amount && recs3[2].field_count == 1 && ext3[2].code == '$');
    assert(spl3[1].has_amount && spl3[1].amount.minor == 500);
}

// test_qif_ratio checks the exact number codes and the F flag.
fn test_qif_ratio() {
    let lim = bank_statement::default_limits();
    let opts = bank_statement::QifOptions { date_order: bank_statement::DATE_MDY, .. };
    var recs: bank_statement::QifRecord[>..] = [];
    var spl: bank_statement::QifSplit[>..] = [];
    var ext: bank_statement::QifField[>..] = [];
    // 10 1/2, 1/2, a negative commission and a percent with a tail.
    let text = "!Type:Invst\nI10 1/2\nQ1/4\nO-9.99\n^\n!Type:Bank\nSA\n%12.5 %\nSB\n%1/3\n^\nFphone\n^\n";
    var xbuf19: u8[>..] = [];
    let f = bank_statement::parse_qif(text, lim, opts, recs, spl, ext, xbuf19);
    if f.kind != 0 { print("FAIL ratio ", bank_statement::kind_name(f.kind), " line ", f.line, " ", f.detail, "\n"); }
    assert(f.kind == 0);
    assert(recs[0].has_price && recs[0].price.num == 21 && recs[0].price.den == 2 && recs[0].price_text == "10 1/2");
    assert(recs[0].has_quantity && recs[0].quantity.num == 1 && recs[0].quantity.den == 4);
    assert(recs[0].has_commission && recs[0].commission.num == -999 && recs[0].commission.den == 100);
    assert(spl[0].has_percent && spl[0].percent.num == 25 && spl[0].percent.den == 2 && spl[0].percent_text == "12.5 %");
    assert(spl[1].has_percent && spl[1].percent.num == 1 && spl[1].percent.den == 3);
    assert(recs[2].reimbursable && recs[2].reimbursable_text == "phone");
    // A value that fits no form is an amount fault with the code as tag.
    run_qif("!Type:Invst\nI1 2 3/4\n^\n", bank_statement::DATE_MDY, 4);
    var recs2: bank_statement::QifRecord[>..] = [];
    var spl2: bank_statement::QifSplit[>..] = [];
    var ext2: bank_statement::QifField[>..] = [];
    var xbuf20: u8[>..] = [];
    let f2 = bank_statement::parse_qif("!Type:Invst\nIabc\n^\n", lim, opts, recs2, spl2, ext2, xbuf20);
    assert(f2.kind == 4 && f2.tag == "I");
    // A fraction of zero is a fault.
    var xbuf21: u8[>..] = [];
    let f3 = bank_statement::parse_qif("!Type:Invst\nI1/0\n^\n", lim, opts, recs2, spl2, ext2, xbuf21);
    assert(f3.kind == 4);
}

// test_mt940_64_65 checks the typed available and forward balances.
fn test_mt940_64_65() {
    let lim = bank_statement::default_limits();
    let opts = bank_statement::Mt940Options { .. };
    var sts: bank_statement::Statement[>..] = [];
    var ens: bank_statement::Entry[>..] = [];
    var bals: bank_statement::Balance[>..] = [];
    var notes: bank_statement::Note[>..] = [];
    let text = ":20:A\n:60F:C250101EUR100,00\n:61:250102C50,00NTRFREF\n:62F:C250102EUR150,00\n:64:C250102EUR150,00\n:65:C250331EUR200,00\n:65:C250401EUR250,00\n";
    var xbuf22: u8[>..] = [];
    let f = bank_statement::parse_mt940(text, lim, opts, sts, ens, bals, notes, xbuf22);
    if f.kind != 0 { print("FAIL 64/65 ", bank_statement::kind_name(f.kind), " line ", f.line, " ", f.tag, " ", f.detail, "\n"); }
    assert(f.kind == 0);
    // Both balances sit in the balance range and as typed fields.
    assert(sts[0].balance_count == 5);
    assert(sts[0].available.kind == bank_statement::BAL_AVAILABLE);
    assert(sts[0].available.amount.minor == 15000 && sts[0].available.amount.currency == "EUR");
    assert(sts[0].available.date.year == 2025 && sts[0].available.date.month == 1 && sts[0].available.date.day == 2);
    assert(sts[0].forward.kind == bank_statement::BAL_FORWARD);
    assert(sts[0].forward.amount.minor == 25000);
    assert(sts[0].forward.date.day == 1 && sts[0].forward.date.month == 4);
    // The balance check reads the opening and closing balance only.
    assert(sts[0].balance_checked);
    // A statement without the lines holds kind 0.
    var sts2: bank_statement::Statement[>..] = [];
    var ens2: bank_statement::Entry[>..] = [];
    var bals2: bank_statement::Balance[>..] = [];
    var notes2: bank_statement::Note[>..] = [];
    var xbuf23: u8[>..] = [];
    let g = bank_statement::parse_mt940(":20:A\n:60F:C250101EUR0,00\n:62F:C250101EUR0,00\n", lim, opts, sts2, ens2, bals2, notes2, xbuf23);
    assert(g.kind == 0 && sts2[0].available.kind == 0 && sts2[0].forward.kind == 0);
    // A second :64: is a fault. A second :65: replaces the value.
    run_mt940(":20:A\n:64:C250101EUR1,00\n:64:C250102EUR2,00\n", false, 2, "64");
    var sts3: bank_statement::Statement[>..] = [];
    var ens3: bank_statement::Entry[>..] = [];
    var bals3: bank_statement::Balance[>..] = [];
    var notes3: bank_statement::Note[>..] = [];
    let off = bank_statement::Mt940Options { skip_balance_check: true, check_fields: false, style: 0 };
    var xbuf24: u8[>..] = [];
    let h = bank_statement::parse_mt940(":20:A\n:65:C250101EUR1,00\n:65:C250102EUR2,00\n", lim, off, sts3, ens3, bals3, notes3, xbuf24);
    assert(h.kind == 0 && sts3[0].forward.amount.minor == 200);
}

fn run_limited(text: const u8[:], lim: bank_statement::Limits&, kind: i32) {
    var rbuf: u8[>..] = [];
    let f = parse_kind(text, lim, true, rbuf);
    if f.kind != kind { print("FAIL limit want ", bank_statement::kind_name(kind), " got ", bank_statement::kind_name(f.kind), " ", f.detail); }
    assert(f.kind == kind);
}

fn test_hostile() {
    var lim = bank_statement::default_limits();
    // Input above max_input.
    lim.max_input = 10;
    run_limited(":20:ABCDEFGHIJKLMNOP\n", lim, 1);
    lim = bank_statement::default_limits();
    // A line above max_line.
    var big: u8[>..] = [];
    format(big, ":20:");
    for i in 5000 { big.push('A'); }
    format(big, "\n");
    run_limited(big[..], lim, 1);
    // A field above max_field.
    lim.max_field = 8;
    run_limited(":20:ABCDEFGHIJ\n", lim, 1);
    lim = bank_statement::default_limits();
    // Counts: statements, entries.
    lim.max_statements = 1;
    run_limited(":20:A\n:20:B\n", lim, 1);
    lim = bank_statement::default_limits();
    lim.max_entries = 1;
    run_limited(":20:A\n:60F:C250101EUR0,00\n:61:250101C1,00NTRFX\n:61:250101C1,00NTRFX\n", lim, 1);
    lim = bank_statement::default_limits();
    // Nesting of blocks.
    run_limited("{1:{{{{{{{{{{{{{{{{x}}}}}}}}}}}}}}}}\n", lim, 1);
    run_limited("{1:{abc}\n", lim, 2);
    run_limited("{9}\n", lim, 2);
    // A NUL byte, a bare tag and an empty file.
    run_limited(":20:A\n\0\n", lim, 2);
    run_limited(":20\n", lim, 2);
    run_limited("", lim, 0);
    run_limited("\n\n\r\n", lim, 0);
    // A number of 400 digits is an overflow, not a wrap.
    var num: u8[>..] = [];
    format(num, ":20:A\n:60F:C250101EUR");
    for i in 400 { num.push('9'); }
    format(num, ",00\n");
    run_limited(num[..], lim, 5);
    // The sum of the entries overflows.
    run_mt940(":20:A\n:60F:C250101EUR0,00\n:61:250101C92233720368547758,07NTRFX\n:61:250101C92233720368547758,07NTRFX\n:62F:C250101EUR0,00\n", false, 5, "61");
    // Bytes above 127 pass through into text fields.
    run_limited(":20:A\xff\xfe\n:25:caf\xc3\xa9\n", lim, 0);
}

fn test_hostile_qif() {
    var lim = bank_statement::default_limits();
    let opts = bank_statement::QifOptions { date_order: 1, .. };
    var recs: bank_statement::QifRecord[>..] = [];
    var spl: bank_statement::QifSplit[>..] = [];
    var ext: bank_statement::QifField[>..] = [];
    lim.max_records = 2;
    var xbuf25: u8[>..] = [];
    let f = bank_statement::parse_qif("!Type:Bank\nT1\n^\nT2\n^\nT3\n^\n", lim, opts, recs, spl, ext, xbuf25);
    assert(f.kind == 1);
    lim = bank_statement::default_limits();
    lim.max_splits = 1;
    var recs2: bank_statement::QifRecord[>..] = [];
    var spl2: bank_statement::QifSplit[>..] = [];
    var ext2: bank_statement::QifField[>..] = [];
    var xbuf26: u8[>..] = [];
    let g = bank_statement::parse_qif("!Type:Bank\nSa\n$1\nSb\n$2\n^\n", lim, opts, recs2, spl2, ext2, xbuf26);
    assert(g.kind == 1);
    run_qif("!Type:Bank\nT\0\n", 1, 2);
    run_qif("!Type:Bank\nT99999999999999999999999999999\n^\n", 1, 5);
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

// A doubled input must not take more than about twice as long.
fn test_linear_time() {
    // The best of three runs ignores a pause of a busy machine.
    var a = time_parse(20000);
    var b = time_parse(40000);
    for r in 2 {
        let a2 = time_parse(20000);
        let b2 = time_parse(40000);
        if a2 < a { a = a2; }
        if b2 < b { b = b2; }
    }
    if b > 3 * a + 30000000 { print("FAIL time ", a, " ns for 20000, ", b, " ns for 40000\n"); }
    assert(b <= 3 * a + 30000000);
}


// The camt documents of the tests. They are written in the shapes of the
// ISO 20022 schema versions .001.02, .001.04 and .001.08.
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

// The three documents below are real files of a bank.
// They come from the test data of the Go library moov-io/iso20022.
// That library holds the Apache License 2.0.

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

fn test_camt_statement() {
    let lim = bank_statement::default_limits();
    let opts = bank_statement::CamtOptions { .. };
    var sts: bank_statement::Statement[>..] = [];
    var ens: bank_statement::Entry[>..] = [];
    var bals: bank_statement::Balance[>..] = [];
    var buf: u8[>..] = [];
    var hd2 = bank_statement::CamtHeader { .. };
    let f = bank_statement::parse_camt(CAMT53, lim, opts, hd2, sts, ens, bals, buf);
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
}

fn test_camt_interim() {
    let lim = bank_statement::default_limits();
    let opts = bank_statement::CamtOptions { .. };
    var sts: bank_statement::Statement[>..] = [];
    var ens: bank_statement::Entry[>..] = [];
    var bals: bank_statement::Balance[>..] = [];
    var buf: u8[>..] = [];
    var hd3 = bank_statement::CamtHeader { .. };
    let f = bank_statement::parse_camt(CAMT52, lim, opts, hd3, sts, ens, bals, buf);
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
    let g = bank_statement::parse_camt(CAMT54, lim, opts, hd4, sts2, ens2, bals2, buf2);
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
    let f = bank_statement::parse_camt(CAMT02, lim, opts, hd5, sts, ens, bals, buf);
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
    let g = bank_statement::parse_camt(CAMTPREFIX, lim, opts, hd6, sts2, ens2, bals2, buf2);
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
    run_camt(bad, false, 7);
    run_camt(bad, true, 0);
    // A wrong total in the transaction summary.
    let bad_total = """
<Document xmlns="urn:iso:std:iso:20022:tech:xsd:camt.052.001.08"><BkToCstmrAcctRpt><Rpt><Id>R</Id>
<TxsSummry><TtlCdtNtries><NbOfNtries>2</NbOfNtries><Sum Ccy="EUR">500.00</Sum></TtlCdtNtries></TxsSummry>
<Ntry><Amt Ccy="EUR">500.00</Amt><CdtDbtInd>CRDT</CdtDbtInd><Sts>BOOK</Sts></Ntry>
</Rpt></BkToCstmrAcctRpt></Document>
""";
    run_camt(bad_total, false, 8);
    // A summary with one block for all the entries gives no credit or
    // debit total, so it has no check.
    let gross = """
<Document xmlns="urn:iso:std:iso:20022:tech:xsd:camt.054.001.08"><BkToCstmrDbtCdtNtfctn><Ntfctn><Id>N</Id>
<TxsSummry><TtlNtries><NbOfNtries>2</NbOfNtries><Sum>300.00</Sum><CdtDbtInd>CRDT</CdtDbtInd></TtlNtries></TxsSummry>
<Ntry><Amt Ccy="EUR">200.00</Amt><CdtDbtInd>CRDT</CdtDbtInd><Sts>BOOK</Sts></Ntry>
<Ntry><Amt Ccy="EUR">100.00</Amt><CdtDbtInd>DBIT</CdtDbtInd><Sts>BOOK</Sts></Ntry>
</Ntfctn></BkToCstmrDbtCdtNtfctn></Document>
""";
    run_camt(gross, false, 0);
}

fn test_camt_faults() {
    // A missing amount, a missing currency and a sign in the amount.
    run_camt("<Document xmlns=\"x\"><BkToCstmrStmt><Stmt><Ntry><CdtDbtInd>CRDT</CdtDbtInd></Ntry></Stmt></BkToCstmrStmt></Document>", false, 4);
    run_camt("<Document xmlns=\"x\"><BkToCstmrStmt><Stmt><Ntry><Amt Ccy=\"EUR\">1.00</Amt></Ntry></Stmt></BkToCstmrStmt></Document>", false, 4);
    run_camt("<Document xmlns=\"x\"><BkToCstmrStmt><Stmt><Ntry><Amt>1.00</Amt><CdtDbtInd>CRDT</CdtDbtInd></Ntry></Stmt></BkToCstmrStmt></Document>", false, 4);
    run_camt("<Document xmlns=\"x\"><BkToCstmrStmt><Stmt><Ntry><Amt Ccy=\"EUR\">-1.00</Amt><CdtDbtInd>CRDT</CdtDbtInd></Ntry></Stmt></BkToCstmrStmt></Document>", false, 4);
    run_camt("<Document xmlns=\"x\"><BkToCstmrStmt><Stmt><Ntry><Amt Ccy=\"EUR\">1.00</Amt><CdtDbtInd>XXXX</CdtDbtInd></Ntry></Stmt></BkToCstmrStmt></Document>", false, 4);
    // A root that is not a camt document and a document without a message.
    run_camt("<Foo/>", false, 2);
    run_camt("<Document xmlns=\"x\"><Other/></Document>", false, 2);
    // A document that is not well formed.
    run_camt("<Document>", false, 2);
    // A bad date.
    run_camt("<Document xmlns=\"x\"><BkToCstmrStmt><Stmt><CreDtTm>2025-13-45T99:99:99</CreDtTm></Stmt></BkToCstmrStmt></Document>", false, 6);
    // An unknown element is ignored. A statement without both booked
    // balances has no balance check.
    run_camt("<Document xmlns=\"x\"><BkToCstmrStmt><Stmt><FutureThing><Deeper>x</Deeper></FutureThing></Stmt></BkToCstmrStmt></Document>", false, 0);
    // A document with an entity is refused by the XML layer, so no
    // entity of it can expand.
    run_camt("<Document xmlns=\"x\"><BkToCstmrStmt><Stmt><Id>&xxe;</Id></Stmt></BkToCstmrStmt></Document>", false, 2);
    // A document above the input limit.
    var lim = bank_statement::default_limits();
    lim.max_input = 20;
    var sts: bank_statement::Statement[>..] = [];
    var ens: bank_statement::Entry[>..] = [];
    var bals: bank_statement::Balance[>..] = [];
    var buf: u8[>..] = [];
    let opts = bank_statement::CamtOptions { .. };
    var hd7 = bank_statement::CamtHeader { .. };
    let f = bank_statement::parse_camt(CAMT53, lim, opts, hd7, sts, ens, bals, buf);
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
    let f = bank_statement::parse_camt(REAL52, lim, opts, hd9, sts, ens, bals, buf);
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
    let g = bank_statement::parse_camt(REAL54, lim, opts, hd10, sts2, ens2, bals2, buf2);
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
    let h = bank_statement::parse_camt(REAL53, lim, opts, hd11, sts3, ens3, bals3, buf3);
    assert(h.kind == 7 && h.tag == "Bal");
    var sts4: bank_statement::Statement[>..] = [];
    var ens4: bank_statement::Entry[>..] = [];
    var bals4: bank_statement::Balance[>..] = [];
    var buf4: u8[>..] = [];
    let opts2 = bank_statement::CamtOptions { skip_balance_check: true };
    var hd12 = bank_statement::CamtHeader { .. };
    let k = bank_statement::parse_camt(REAL53, lim, opts2, hd12, sts4, ens4, bals4, buf4);
    assert(k.kind == 0);
    assert(sts4.len == 1 && ens4.len == 5 && bals4.len == 4);
    assert(sts4[0].opening.amount.minor == 21199319 && sts4[0].closing.amount.minor == 21511221);
}


// The OFX test files below. The first two are synthetic files that
// hold the forms a bank sends. The third is an investment statement.

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

fn test_ofx_v1() {
    let lim = bank_statement::default_limits();
    let opts = bank_statement::OfxOptions { .. };
    var sts: bank_statement::Statement[>..] = [];
    var ens: bank_statement::Entry[>..] = [];
    var bals: bank_statement::Balance[>..] = [];
    var notes: bank_statement::Note[>..] = [];
    var buf: u8[>..] = [];
    let f = bank_statement::parse_ofx(OFX_V1, lim, opts, sts, ens, bals, notes, buf);
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
    let f = bank_statement::parse_ofx(OFX_V2, lim, opts, sts, ens, bals, notes, buf);
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
    let f = bank_statement::parse_ofx(OFX_INV, lim, opts, sts, ens, bals, notes, buf);
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

fn test_ofx_dates() {
    // The date forms of the spec.
    assert(ofx_date_fault("20200101120000") == 0);
    assert(ofx_date_fault("2020010112") == 0);
    assert(ofx_date_fault("20200101") == 0);
    assert(ofx_date_fault("20200101120000.000") == 0);
    assert(ofx_date_fault("20200101120000[-5:EST]") == 0);
    assert(ofx_date_fault("20200101120000[-5.30:IST]") == 0);
    assert(ofx_date_fault("20200101120000[0:GMT]") == 0);
    // The bad dates.
    assert(ofx_date_fault("2020010112000") == 6);
    assert(ofx_date_fault("20201301120000") == 6);
    assert(ofx_date_fault("20200230120000") == 6);
    assert(ofx_date_fault("20200101120000[99:EST]") == 6);
    // The date of the entry holds the day.
    let lim = bank_statement::default_limits();
    let opts = bank_statement::OfxOptions { .. };
    var text: u8[>..] = [];
    build_ofx_date("20200101120000[-5:EST]", text);
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
    run_ofx("hello", 2);
    // A header with a bad field.
    run_ofx("OFXHEADER:999\nDATA:OFXSGML\nVERSION:102\n\n<OFX></OFX>", 2);
    run_ofx("OFXHEADER:100\nDATA:OFXSGML\nVERSION:999\n\n<OFX></OFX>", 2);
    run_ofx("OFXHEADER:100\nDATA:OFXSGML\nVERSION:102\nWHAT:1\n\n<OFX></OFX>", 2);
    // A root that is not OFX.
    run_ofx("OFXHEADER:100\nDATA:OFXSGML\nVERSION:102\n\n<OTHER></OTHER>", 2);
    // A close tag that does not match.
    run_ofx("OFXHEADER:100\nDATA:OFXSGML\nVERSION:102\n\n<OFX><A></B></OFX>", 2);
    // An aggregate that is not closed.
    run_ofx("OFXHEADER:100\nDATA:OFXSGML\nVERSION:102\n\n<OFX><A>", 2);
    // A doctype and an entity.
    run_ofx("OFXHEADER:100\nDATA:OFXSGML\nVERSION:102\n\n<!DOCTYPE OFX><OFX></OFX>", 2);
    run_ofx("OFXHEADER:100\nDATA:OFXSGML\nVERSION:102\n\n<!ENTITY x \"y\"><OFX></OFX>", 2);
    // A currency that is not known.
    run_ofx("OFXHEADER:100\nDATA:OFXSGML\nVERSION:102\n\n<OFX><BANKMSGSRSV1><STMTTRNRS><TRNUID>1<STMTRS><CURDEF>XXX</STMTRS></STMTTRNRS></BANKMSGSRSV1></OFX>", 4);
    // A bad amount.
    run_ofx("OFXHEADER:100\nDATA:OFXSGML\nVERSION:102\n\n<OFX><BANKMSGSRSV1><STMTTRNRS><TRNUID>1<STMTRS><CURDEF>USD<BANKTRANLIST><STMTTRN><TRNTYPE>CHECK<TRNAMT>1e5</STMTTRN></BANKTRANLIST></STMTRS></STMTTRNRS></BANKMSGSRSV1></OFX>", 4);
    // A file above the input limit.
    var lim = bank_statement::default_limits();
    lim.max_input = 20;
    var sts: bank_statement::Statement[>..] = [];
    var ens: bank_statement::Entry[>..] = [];
    var bals: bank_statement::Balance[>..] = [];
    var notes: bank_statement::Note[>..] = [];
    var buf: u8[>..] = [];
    let opts = bank_statement::OfxOptions { .. };
    let f = bank_statement::parse_ofx(OFX_V1, lim, opts, sts, ens, bals, notes, buf);
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

fn test_swift_fields() {
    // A file that keeps the manual parses with the rules on and gives
    // the same values as with the rules off.
    assert(fk(STMT1) == 0);
    // The widths: 16 passes, 17 fails.
    var a: u8[>..] = [];
    fill('A', 16, a);
    var b: u8[>..] = [];
    stmt_with(a, "ACC", b);
    assert(fk(b) == 0);
    var c: u8[>..] = [];
    fill('A', 17, c);
    var d: u8[>..] = [];
    stmt_with(c, "ACC", d);
    var rbuf2: u8[>..] = [];
    let f = fields_kind(d, rbuf2);
    assert(f.kind == 2 && f.tag == "20");
    // The same file parses with the rules off.
    run_mt940(d, false, 0, "");
    // The account: 35 passes, 36 fails.
    var e: u8[>..] = [];
    fill('9', 35, e);
    var g: u8[>..] = [];
    stmt_with("R", e, g);
    assert(fk(g) == 0);
    var h: u8[>..] = [];
    fill('9', 36, h);
    var k: u8[>..] = [];
    stmt_with("R", h, k);
    expect_fields(k, 2, "25");
}

fn test_swift_charset() {
    // Letters of both cases and the marks of the manual pass.
    expect_fields(":20:Ab-1/2 (x)\n:25:A\n:28C:1/1\n:60F:C250101EUR1,00\n:62F:C250101EUR1,00\n", 0, "");
    // An ampersand and a byte above 127 are outside the set.
    expect_fields(":20:A&B\n:25:A\n:28C:1/1\n:60F:C250101EUR1,00\n:62F:C250101EUR1,00\n", 2, "20");
    expect_fields(":20:R\n:25:A\n:28C:1/1\n:60F:C250101EUR1,00\n:61:250102C1,00NTRFREF\n:86:caf\xc3\xa9\n:62F:C250101EUR2,00\n", 2, "86");
    // The rules off accept both.
    run_mt940(":20:A&B\n:25:A\n:28C:1/1\n:60F:C250101EUR1,00\n:62F:C250101EUR1,00\n", false, 0, "");
}

fn test_swift_numbers() {
    // A currency of two letters and a count of six digits are faults.
    expect_fields(":20:R\n:25:A\n:28C:1/1\n:60F:C250101EU1,00\n:62F:C250101EUR1,00\n", 2, "60F");
    expect_fields(":20:R\n:25:A\n:28C:123456/1\n:60F:C250101EUR1,00\n:62F:C250101EUR1,00\n", 2, "28C");
    expect_fields(":20:R\n:25:A\n:28C:1/1\n:34F:EUR0,\n:61:250102C1,00NTRFREF\n:90D:123456EUR1,00\n", 2, "90D");
    // An amount with 16 digits is too wide.
    expect_fields(":20:R\n:25:A\n:28C:1/1\n:60F:C250101EUR1234567890123456,\n:62F:C250101EUR1,00\n", 2, "60F");
}

fn test_swift_61() {
    let head = ":20:R\n:25:A\n:28C:1/1\n:60F:C250101EUR10,00\n";
    let tail = ":62F:C250101EUR11,00\n";
    var ok: u8[>..] = [];
    format(ok, head); format(ok, ":61:250102C1,00NTRF1234567890123456//1234567890123456\n");
    fill('S', 34, ok); format(ok, "\n"); format(ok, tail);
    assert(fk(ok) == 0);
    var long_cust: u8[>..] = [];
    format(long_cust, head); format(long_cust, ":61:250102C1,00NTRF12345678901234567\n"); format(long_cust, tail);
    expect_fields(long_cust, 2, "61");
    var long_bank: u8[>..] = [];
    format(long_bank, head); format(long_bank, ":61:250102C1,00NTRFA//12345678901234567\n"); format(long_bank, tail);
    expect_fields(long_bank, 2, "61");
    var long_sup: u8[>..] = [];
    format(long_sup, head); format(long_sup, ":61:250102C1,00NTRFA\n");
    fill('S', 35, long_sup); format(long_sup, "\n"); format(long_sup, tail);
    expect_fields(long_sup, 2, "61");
}

fn test_swift_86() {
    let head = ":20:R\n:25:A\n:28C:1/1\n:60F:C250101EUR10,00\n:61:250102C1,00NTRFREF\n:86:";
    let tail = ":62F:C250101EUR11,00\n";
    // Six lines of 65 pass. A seventh fails. A line of 66 fails.
    var six: u8[>..] = [];
    format(six, head);
    var i = 0;
    while i < 6 { fill('T', 65, six); format(six, "\n"); i += 1; }
    format(six, tail);
    assert(fk(six) == 0);
    var seven: u8[>..] = [];
    format(seven, head);
    i = 0;
    while i < 7 { fill('T', 65, seven); format(seven, "\n"); i += 1; }
    format(seven, tail);
    expect_fields(seven, 2, "86");
    var wide: u8[>..] = [];
    format(wide, head); fill('T', 66, wide); format(wide, "\n"); format(wide, tail);
    expect_fields(wide, 2, "86");
    // The same file parses with the rules off.
    run_mt940(seven, false, 0, "");
}

fn test_swift_order() {
    // :25: before :21: is out of order.
    expect_fields(":20:R\n:25:A\n:21:B\n:28C:1/1\n:60F:C250101EUR1,00\n:62F:C250101EUR1,00\n", 2, "21");
    // A statement without :25: or :28C: is a fault.
    expect_fields(":20:R\n:28C:1/1\n:60F:C250101EUR1,00\n:62F:C250101EUR1,00\n", 2, "28C");
    expect_fields(":20:R\n:25:A\n:60F:C250101EUR1,00\n:62F:C250101EUR1,00\n", 2, "60F");
    // An interim report with :34F: and :13D: before the opening balance passes.
    assert(fk(":20:I\n:25:A\n:28C:5/1\n:34F:EUR0,\n:13D:2501021530+0100\n:61:250102C500,00NTRFREF\n:90C:1EUR500,00\n") == 0);
    // :NS: may follow any tag.
    assert(fk(":20:R\n:25:A\n:NS:note\n:28C:1/1\n:60F:C250101EUR1,00\n:62F:C250101EUR1,00\n") == 0);
    // The options with the rules off accept the out-of-order file.
    run_mt940(":20:R\n:25:A\n:21:B\n:28C:1/1\n:60F:C250101EUR1,00\n:62F:C250101EUR1,00\n", false, 0, "");
}

fn test_swift_hostile() {
    // A huge :20: faults at once with the rules on.
    var big: u8[>..] = [];
    fill('A', 4000, big);
    var d: u8[>..] = [];
    stmt_with(big, "A", d);
    expect_fields(d, 2, "20");
    // 100000 lines in one :86: fault on the field size.
    var many: u8[>..] = [];
    format(many, ":20:R\n:25:A\n:28C:1/1\n:60F:C250101EUR1,00\n:61:250102C1,00NTRFREF\n:86:");
    var i = 0;
    while i < 100000 { format(many, "x\n"); i += 1; }
    format(many, ":62F:C250101EUR2,00\n");
    var rbuf3: u8[>..] = [];
    let f = fields_kind(many, rbuf3);
    assert(f.kind == 1 || f.kind == 2);
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

fn test_dialect_rabo() {
    let text = "/MARF/12345/EREF/67890/NAME/JOE DOE/REMI/PAYMENT";
    var vals: bank_statement::DialectValue[>..] = [];
    var buf: u8[>..] = [];
    let f = dialect_run(bank_statement::D_RABOBANK, text, vals, buf);
    if f.kind != 0 { print("FAIL rabo ", bank_statement::kind_name(f.kind), " ", f.detail, "\n"); }
    assert(f.kind == 0);
    assert(dialect_value(vals, "marf") == "12345");
    assert(dialect_value(vals, "eref") == "67890");
    assert(dialect_value(vals, "name") == "JOE DOE");
    assert(dialect_value(vals, "remi") == "PAYMENT");
    assert(dialect_value(vals, "iban") == "");
    // A text of another bank gives no value and no fault.
    var other: bank_statement::DialectValue[>..] = [];
    var buf2: u8[>..] = [];
    let g = dialect_run(bank_statement::D_RABOBANK, "/FOO/BAR/NAME/", other, buf2);
    assert(g.kind == 0);
    assert(other.len == 0);
    // The tags of the bank may stand over the line ends.
    var over: bank_statement::DialectValue[>..] = [];
    var buf3: u8[>..] = [];
    let h = dialect_run(bank_statement::D_RABOBANK, "/MARF/12345/\nEREF/67890", over, buf3);
    assert(h.kind == 0);
    assert(dialect_value(over, "marf") == "12345");
    assert(dialect_value(over, "eref") == "67890");
}

fn test_dialect_abn() {
    let text = "/TRTP/SEPA OVERBOEKING/IBAN/DE89370400440532013000/BIC/GEFRADAM/NAME/ENERGIE BEDRIJF/EREF/NOTPROVIDED";
    var vals: bank_statement::DialectValue[>..] = [];
    var buf: u8[>..] = [];
    let f = dialect_run(bank_statement::D_ABN_AMRO, text, vals, buf);
    if f.kind != 0 { print("FAIL abn ", bank_statement::kind_name(f.kind), " ", f.detail, "\n"); }
    assert(f.kind == 0);
    assert(dialect_value(vals, "trtp") == "SEPA OVERBOEKING");
    assert(dialect_value(vals, "iban") == "DE89370400440532013000");
    assert(dialect_value(vals, "bic") == "GEFRADAM");
    assert(dialect_value(vals, "name") == "ENERGIE BEDRIJF");
    assert(dialect_value(vals, "eref") == "NOTPROVIDED");
    // The account number stands at the start of the text. The dots come out.
    var acc: bank_statement::DialectValue[>..] = [];
    var buf2: u8[>..] = [];
    let g = dialect_run(bank_statement::D_ABN_AMRO, "123.45.67.89/TRTP/SEPA OVERBOEKING", acc, buf2);
    assert(g.kind == 0);
    assert(dialect_value(acc, "account") == "123456789");
    assert(dialect_value(acc, "trtp") == "SEPA OVERBOEKING");
    // A giro account stands at the start of the text.
    var giro: bank_statement::DialectValue[>..] = [];
    var buf3: u8[>..] = [];
    let h = dialect_run(bank_statement::D_ABN_AMRO, "GIRO 4090309", giro, buf3);
    assert(h.kind == 0);
    assert(dialect_value(giro, "account") == "4090309");
    // A text of another bank gives no value and no fault.
    var other: bank_statement::DialectValue[>..] = [];
    var buf4: u8[>..] = [];
    let i = dialect_run(bank_statement::D_ABN_AMRO, "foo", other, buf4);
    assert(i.kind == 0);
    assert(other.len == 0);
}

fn test_dialect_mbank() {
    var vals: bank_statement::DialectValue[>..] = [];
    var buf: u8[>..] = [];
    let f = dialect_run(bank_statement::D_MBANK, "020 PRZELEW;ID IPH: X1234;x ID IPH: XX00123456789012;TNR: 1234.5678;", vals, buf);
    assert(f.kind == 0);
    assert(dialect_value(vals, "transaction_code") == "020");
    assert(dialect_value(vals, "iph_id") == "00123456789012");
    assert(dialect_value(vals, "tnr") == "1234.5678");
    var v2: bank_statement::DialectValue[>..] = [];
    assert(dialect_run(bank_statement::D_MBANK, "5 X\nTNR:\n12.3", v2, buf).kind == 0);
    assert(dialect_value(v2, "transaction_code") == "5" && dialect_value(v2, "tnr") == "12.3");
    // A text with none of the three gives no value and no fault.
    var v3: bank_statement::DialectValue[>..] = [];
    assert(dialect_run(bank_statement::D_MBANK, "hello; TNR:12.3", v3, buf).kind == 0);
    assert(v3.len == 0);
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

fn test_styles() {
    let c20 = "01234567890123456789";
    let c40 = "0123456789012345678901234567890123456789";
    let b20 = "01234567890123456789";
    assert(style_kind(bank_statement::STYLE_SWIFT, c20, "") == bank_statement::F_SYNTAX);
    assert(style_kind(bank_statement::STYLE_ASNB, c20, "") == 0);
    assert(style_kind(bank_statement::STYLE_ASNB, c40, "") == bank_statement::F_SYNTAX);
    assert(style_kind(bank_statement::STYLE_GLS, c40, "") == 0);
    assert(style_kind(bank_statement::STYLE_GLS, c40, b20) == 0);
    assert(style_kind(bank_statement::STYLE_GLS, c40, "0123456789012345678901234") == bank_statement::F_SYNTAX);
    assert(style_kind(bank_statement::STYLE_ASNB, c20, b20) == bank_statement::F_SYNTAX);
    assert(style_kind(7, c20, "") == bank_statement::F_SYNTAX);
}

fn test_transcode() {
    let lim = bank_statement::default_limits();
    var out: u8[>..] = [];
    // euro, caf\xe9, quotes and dash
    assert(bank_statement::decode_charset(bank_statement::CS_CP1252, "\x80 caf\xE9 \x93x\x94 \x96", lim, out).kind == 0);
    assert(out == "\xE2\x82\xAC caf\xC3\xA9 \xE2\x80\x9Cx\xE2\x80\x9D \xE2\x80\x93");
    var back: u8[>..] = [];
    assert(bank_statement::encode_charset(bank_statement::CS_CP1252, out, lim, back).kind == 0);
    assert(back == "\x80 caf\xE9 \x93x\x94 \x96");
    // Latin-1 keeps 0x80 to 0x9F as control characters; Windows-1252 does not.
    var l1: u8[>..] = [];
    assert(bank_statement::decode_charset(bank_statement::CS_LATIN1, "\x80\xE9", lim, l1).kind == 0);
    assert(l1 == "\xC2\x80\xC3\xA9");
    // The five undefined bytes are faults.
    var u: u8[>..] = [];
    assert(bank_statement::decode_charset(bank_statement::CS_CP1252, "a\x81", lim, u).kind == bank_statement::F_SYNTAX);
    assert(bank_statement::decode_charset(bank_statement::CS_CP1252, "\x8D", lim, u).kind == bank_statement::F_SYNTAX);
    assert(bank_statement::decode_charset(bank_statement::CS_CP1252, "\x8F", lim, u).kind == bank_statement::F_SYNTAX);
    assert(bank_statement::decode_charset(bank_statement::CS_CP1252, "\x90", lim, u).kind == bank_statement::F_SYNTAX);
    assert(bank_statement::decode_charset(bank_statement::CS_CP1252, "\x9D", lim, u).kind == bank_statement::F_SYNTAX);
    // Every other byte round trips.
    var all: u8[>..] = [];
    var b = 0;
    while b < 256 {
        if b != 0x81 && b != 0x8D && b != 0x8F && b != 0x90 && b != 0x9D { all.push(b as u8); }
        b += 1;
    }
    var dec: u8[>..] = [];
    assert(bank_statement::decode_charset(bank_statement::CS_CP1252, all, lim, dec).kind == 0);
    var enc: u8[>..] = [];
    assert(bank_statement::encode_charset(bank_statement::CS_CP1252, dec, lim, enc).kind == 0);
    assert(enc == all);
    // A character that the charset lacks, and bad UTF-8, are faults.
    var e1: u8[>..] = [];
    assert(bank_statement::encode_charset(bank_statement::CS_CP1252, "\xD0\x96", lim, e1).kind == bank_statement::F_SYNTAX);
    assert(bank_statement::encode_charset(bank_statement::CS_LATIN1, "\xE2\x82\xAC", lim, e1).kind == bank_statement::F_SYNTAX);
    assert(bank_statement::encode_charset(bank_statement::CS_CP1252, "\xC3", lim, e1).kind == bank_statement::F_SYNTAX);
    assert(bank_statement::encode_charset(bank_statement::CS_CP1252, "\xC0\x80", lim, e1).kind == bank_statement::F_SYNTAX);
    assert(bank_statement::encode_charset(bank_statement::CS_CP1252, "\xC2\x81", lim, e1).kind == bank_statement::F_SYNTAX);
    assert(bank_statement::decode_charset(9, "a", lim, e1).kind == bank_statement::F_SYNTAX);
    // The size limit holds.
    var small = bank_statement::default_limits();
    small.max_input = 3;
    var e2: u8[>..] = [];
    assert(bank_statement::decode_charset(bank_statement::CS_CP1252, "\x80\x80", small, e2).kind == bank_statement::F_LIMIT);
    // The header names the charset.
    assert(bank_statement::header_charset("OFXHEADER:100\nCHARSET:1252\nCOMPRESSION:NONE\n") == bank_statement::CS_CP1252);
    assert(bank_statement::header_charset("CHARSET: ISO-8859-1\r\n") == bank_statement::CS_LATIN1);
    assert(bank_statement::header_charset("CHARSET:NONE\n") == 0);
    assert(bank_statement::header_charset("<OFX>") == 0);
}

fn test_dialect_ing() {
    let text = "/EREF/170330P40411570.4342.2964442//CNTP/\nNL94RABO0123456789/RABONL2U/ENERGIE BEDRIJF///REMI/USTD//\n170330/REM INFO/";
    var vals: bank_statement::DialectValue[>..] = [];
    var buf: u8[>..] = [];
    let f = dialect_run(bank_statement::D_ING, text, vals, buf);
    if f.kind != 0 { print("FAIL ing ", bank_statement::kind_name(f.kind), " ", f.detail, "\n"); }
    assert(f.kind == 0);
    assert(dialect_value(vals, "eref") == "170330P40411570.4342.2964442");
    assert(dialect_value(vals, "cntp.account_number") == "NL94RABO0123456789");
    assert(dialect_value(vals, "cntp.bic") == "RABONL2U");
    assert(dialect_value(vals, "cntp.name") == "ENERGIE BEDRIJF");
    assert(dialect_value(vals, "remi.code") == "USTD");
    assert(dialect_value(vals, "remi.remittance_info") == "170330/REM INFO");
    // A text of another bank gives no value and no fault.
    var other: bank_statement::DialectValue[>..] = [];
    var buf2: u8[>..] = [];
    let g = dialect_run(bank_statement::D_ING, "/FOO/BAR/NAME/", other, buf2);
    assert(g.kind == 0);
    assert(other.len == 0);
}

fn test_dialect_regiobank() {
    let text = "12345678 Jan Jansen\nDorpsstraat 1\niban,remi,desc";
    var vals: bank_statement::DialectValue[>..] = [];
    var buf: u8[>..] = [];
    let f = dialect_run(bank_statement::D_REGIOBANK, text, vals, buf);
    if f.kind != 0 { print("FAIL regio ", bank_statement::kind_name(f.kind), " ", f.detail, "\n"); }
    assert(f.kind == 0);
    assert(dialect_value(vals, "account_number") == "12345678");
    assert(dialect_value(vals, "name") == "Jan Jansen");
    assert(dialect_value(vals, "address") == "Dorpsstraat 1");
    assert(dialect_value(vals, "reference") == "iban,remi,desc");
    // The bank writes "aan" and the name before the parts.
    var other: bank_statement::DialectValue[>..] = [];
    var buf2: u8[>..] = [];
    let g = dialect_run(bank_statement::D_REGIOBANK, "12345678 Jan Jansen\nDorpsstraat 1\naan Jan Jansen,NL01,remi,desc", other, buf2);
    assert(g.kind == 0);
    assert(dialect_value(other, "iban") == "NL01");
    assert(dialect_value(other, "remittance_info") == "remi");
    assert(dialect_value(other, "description") == "desc");
}

fn test_dialect_hostile() {
    let lim = bank_statement::default_limits();
    var vals: bank_statement::DialectValue[>..] = [];
    var buf: u8[>..] = [];
    // A kind that the package does not know is a fault.
    let f = bank_statement::parse_dialect(99, "/MARF/1", lim, vals, buf);
    assert(f.kind == 2);
    // A text above the limit is a fault.
    let mut: u8[>..] = [];
    for i in 5000 { mut.push('A'); }
    let g = bank_statement::parse_dialect(bank_statement::D_RABOBANK, mut, lim, vals, buf);
    assert(g.kind == 1);
    // A text with more values than the limit is a fault.
    var lim2 = bank_statement::default_limits();
    lim2.max_fields = 2;
    var small: bank_statement::DialectValue[>..] = [];
    var buf2: u8[>..] = [];
    let h = bank_statement::parse_dialect(bank_statement::D_RABOBANK, "/MARF/1/EREF/2/PREF/3/TRCD/4", lim2, small, buf2);
    assert(h.kind == 1);
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

fn test_write_qif() {
    qif_round_trip(0);
    qif_round_trip(bank_statement::DATE_DMY);
    qif_round_trip(bank_statement::DATE_YMD);
    let lim = bank_statement::default_limits();
    let ropts = bank_statement::QifOptions { date_order: bank_statement::DATE_MDY, .. };
    var recs: bank_statement::QifRecord[>..] = [];
    var spl: bank_statement::QifSplit[>..] = [];
    var ext: bank_statement::QifField[>..] = [];
    var xbuf32: u8[>..] = [];
    var xbuf32_pre: u8[>..] = [];
    assert(bank_statement::parse_qif(QIF1, lim, ropts, recs, spl, ext, xbuf32_pre).kind == 0);
    let wopts = bank_statement::QifWriteOptions { date_order: 0 };
    // A line end in a text is a fault: the value cannot add a field.
    recs[0].payee = "Eve\nT999.00";
    var out: u8[>..] = [];
    assert(bank_statement::write_qif(recs, spl, ext, wopts, lim, out).kind == bank_statement::F_SYNTAX);
    recs[0].payee = "Eve";
    recs[0].memo = "a\r^\r";
    var o2: u8[>..] = [];
    assert(bank_statement::write_qif(recs, spl, ext, wopts, lim, o2).kind == bank_statement::F_SYNTAX);
    recs[0].memo = "ok";
    // A text that is too long is a fault. It is never cut.
    var big: u8[>..] = [];
    bank_statement::put_num(big, 0, 5000);
    recs[0].memo = big;
    var o3: u8[>..] = [];
    assert(bank_statement::write_qif(recs, spl, ext, wopts, lim, o3).kind == bank_statement::F_LIMIT);
    recs[0].memo = "ok";
    // The splits must add up to the amount.
    spl[0].amount.minor = spl[0].amount.minor + 1;
    var o4: u8[>..] = [];
    assert(bank_statement::write_qif(recs, spl, ext, wopts, lim, o4).kind == bank_statement::F_TOTAL);
    spl[0].amount.minor = spl[0].amount.minor - 1;
    // A field code cannot start a header or end the record.
    ext[0].code = '^';
    var o5: u8[>..] = [];
    assert(bank_statement::write_qif(recs, spl, ext, wopts, lim, o5).kind == bank_statement::F_SYNTAX);
    ext[0].code = '!';
    var o6: u8[>..] = [];
    assert(bank_statement::write_qif(recs, spl, ext, wopts, lim, o6).kind == bank_statement::F_SYNTAX);
    ext[0].code = 'A';
    // A date that does not exist is a fault.
    recs[0].date.day = 31;
    recs[0].date.month = 2;
    var o7: u8[>..] = [];
    assert(bank_statement::write_qif(recs, spl, ext, wopts, lim, o7).kind == bank_statement::F_DATE);
    // The most negative amount and the other exponents.
    var a: u8[>..] = [];
    bank_statement::put_amount(a, -9223372036854775808, 2, '.');
    assert(a == "-92233720368547758.08");
    var b: u8[>..] = [];
    bank_statement::put_amount(b, 5, 3, ',');
    assert(b == "0,005");
    var c: u8[>..] = [];
    bank_statement::put_amount(c, -7, 0, '.');
    assert(c == "-7");
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
    assert(bank_statement::parse_ofx(OFX_V1, lim, ropts, sts, ens, bals, notes, buf).kind == 0);
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

fn test_write_ofx() {
    ofx_round_trip(ofx_wopts(0));
    ofx_round_trip(ofx_wopts(203));
    var o = ofx_wopts(151);
    o.close_leaves = true;
    ofx_round_trip(o);
    var p = ofx_wopts(220);
    p.indent = true;
    ofx_round_trip(p);
    var q = ofx_wopts(102);
    q.indent = true;
    ofx_round_trip(q);
    let lim = bank_statement::default_limits();
    let ropts = bank_statement::OfxOptions { .. };
    var sts: bank_statement::Statement[>..] = [];
    var ens: bank_statement::Entry[>..] = [];
    var bals: bank_statement::Balance[>..] = [];
    var notes: bank_statement::Note[>..] = [];
    var buf: u8[>..] = [];
    assert(bank_statement::parse_ofx(OFX_V1, lim, ropts, sts, ens, bals, notes, buf).kind == 0);
    // The header of version 1 ends with a blank line.
    var h: u8[>..] = [];
    assert(bank_statement::write_ofx(sts, ens, notes, ofx_wopts(0), lim, h).kind == 0);
    assert(h[..13] == "OFXHEADER:100");
    assert(find(h, "\r\n\r\n<OFX>") > 0);
    // The leaves stay open in version 1 and close in version 2.
    assert(find(h, "<CODE>0<SEVERITY>") > 0);
    var h2: u8[>..] = [];
    assert(bank_statement::write_ofx(sts, ens, notes, ofx_wopts(203), lim, h2).kind == 0);
    assert(find(h2, "<CODE>0</CODE>") > 0 && find(h2, "<?xml") == 0);
    // A hostile memo cannot add a transaction, in either form.
    ens[1].narrative = "</STMTTRN><STMTTRN><TRNAMT>999<MEMO>a&b";
    var evil: u8[>..] = [];
    assert(bank_statement::write_ofx(sts, ens, notes, ofx_wopts(102), lim, evil).kind == 0);
    assert(find(evil, "</STMTTRN><STMTTRN><TRNAMT>999") < 0);
    var s2: bank_statement::Statement[>..] = [];
    var e2: bank_statement::Entry[>..] = [];
    var b2: bank_statement::Balance[>..] = [];
    var n2: bank_statement::Note[>..] = [];
    var u2: u8[>..] = [];
    assert(bank_statement::parse_ofx(evil, lim, ropts, s2, e2, b2, n2, u2).kind == 0);
    assert(e2.len == 2);
    assert(e2[1].narrative == "</STMTTRN><STMTTRN><TRNAMT>999<MEMO>a&b");
    // A byte above 127 becomes a numeric reference and reads back.
    ens[1].narrative = "caf\xC3\xA9";
    var uni: u8[>..] = [];
    assert(bank_statement::write_ofx(sts, ens, notes, ofx_wopts(102), lim, uni).kind == 0);
    assert(find(uni, "caf&#233;") > 0);
    // Refusals.
    ens[1].narrative = "bad\x00byte";
    var r1: u8[>..] = [];
    assert(bank_statement::write_ofx(sts, ens, notes, ofx_wopts(102), lim, r1).kind == bank_statement::F_SYNTAX);
    ens[1].narrative = "\xFF";
    var r2: u8[>..] = [];
    assert(bank_statement::write_ofx(sts, ens, notes, ofx_wopts(102), lim, r2).kind == bank_statement::F_SYNTAX);
    var long: u8[>..] = [];
    bank_statement::put_num(long, 0, 256);
    ens[1].narrative = long;
    var r3: u8[>..] = [];
    assert(bank_statement::write_ofx(sts, ens, notes, ofx_wopts(102), lim, r3).kind == bank_statement::F_LIMIT);
    ens[1].narrative = "ok";
    ens[1].type_id = "BOGUS";
    var r4: u8[>..] = [];
    assert(bank_statement::write_ofx(sts, ens, notes, ofx_wopts(102), lim, r4).kind == bank_statement::F_SYNTAX);
    ens[1].type_id = "CREDIT";
    ens[1].entry_ref = "";
    var r5: u8[>..] = [];
    assert(bank_statement::write_ofx(sts, ens, notes, ofx_wopts(102), lim, r5).kind == bank_statement::F_SYNTAX);
    ens[1].entry_ref = "TX2";
    var bad = ofx_wopts(102);
    bad.server_date = bank_statement::Date { year: 2020, month: 13, day: 1 };
    var r6: u8[>..] = [];
    assert(bank_statement::write_ofx(sts, ens, notes, bad, lim, r6).kind == bank_statement::F_DATE);
    var r7: u8[>..] = [];
    assert(bank_statement::write_ofx(sts, ens, notes, ofx_wopts(999), lim, r7).kind == bank_statement::F_SYNTAX);
    // A statement without a closing balance is refused.
    sts[0].closing.kind = 0;
    var r8: u8[>..] = [];
    assert(bank_statement::write_ofx(sts, ens, notes, ofx_wopts(102), lim, r8).kind == bank_statement::F_SYNTAX);
}

fn test_write_mt940() {
    let lim = bank_statement::default_limits();
    let ropts = bank_statement::Mt940Options { skip_balance_check: false, check_fields: true, style: 0 };
    var sts: bank_statement::Statement[>..] = [];
    var ens: bank_statement::Entry[>..] = [];
    var bals: bank_statement::Balance[>..] = [];
    var notes: bank_statement::Note[>..] = [];
    let popts = bank_statement::Mt940Options { .. };
    var xbuf33: u8[>..] = [];
    var xbuf33_pre: u8[>..] = [];
    assert(bank_statement::parse_mt940(STMT1, lim, popts, sts, ens, bals, notes, xbuf33_pre).kind == 0);
    var out: u8[>..] = [];
    let w = bank_statement::write_mt940(sts, ens, lim, out);
    if w.kind != 0 { print("FAIL mt940 write ", bank_statement::kind_name(w.kind), " ", w.tag, " ", w.detail, "\n"); }
    assert(w.kind == 0);
    assert(find(out, ":60F:C250101EUR1000,00") >= 0);
    // The writer output reads back with the field rules on.
    var s2: bank_statement::Statement[>..] = [];
    var e2: bank_statement::Entry[>..] = [];
    var b2: bank_statement::Balance[>..] = [];
    var n2: bank_statement::Note[>..] = [];
    var xbuf34: u8[>..] = [];
    let g = bank_statement::parse_mt940(out, lim, ropts, s2, e2, b2, n2, xbuf34);
    if g.kind != 0 { print("FAIL mt940 reread ", bank_statement::kind_name(g.kind), " line ", g.line, " ", g.tag, " ", g.detail, "\n"); }
    assert(g.kind == 0);
    assert(s2.len == 1 && e2.len == 2 && b2.len == 3);
    assert(s2[0].reference == "STMT001" && s2[0].account == "DE89370400440532013000");
    assert(s2[0].number == "00001" && s2[0].sequence == "001");
    assert(e2[0].amount.minor == 50000 && e2[0].mark == "C" && e2[0].bank_ref == "BANKREF1");
    assert(e2[0].supplementary == "SUPPLEMENT" && e2[0].narrative == ens[0].narrative);
    assert(e2[1].customer_ref == "CHK123" && e2[1].entry_date.year == 0);
    assert(s2[0].available.amount.minor == 129950);
    // A narrative line that starts with a colon would start a tag.
    ens[0].narrative = "line one\n:20:EVIL";
    var r1: u8[>..] = [];
    assert(bank_statement::write_mt940(sts, ens, lim, r1).kind == bank_statement::F_SYNTAX);
    ens[0].narrative = "a{b\x00";
    var r2: u8[>..] = [];
    assert(bank_statement::write_mt940(sts, ens, lim, r2).kind == bank_statement::F_SYNTAX);
    // A byte outside the SWIFT set is a fault.
    ens[0].narrative = "caf\xC3\xA9";
    var r3: u8[>..] = [];
    assert(bank_statement::write_mt940(sts, ens, lim, r3).kind == bank_statement::F_SYNTAX);
    // A line over 65 characters, and more than six lines, are faults.
    var long: u8[>..] = [];
    bank_statement::put_num(long, 0, 66);
    ens[0].narrative = long;
    var r4: u8[>..] = [];
    assert(bank_statement::write_mt940(sts, ens, lim, r4).kind == bank_statement::F_SYNTAX);
    ens[0].narrative = "1\n2\n3\n4\n5\n6\n7";
    var r5: u8[>..] = [];
    assert(bank_statement::write_mt940(sts, ens, lim, r5).kind != 0);
    ens[0].narrative = "ok";
    // A reference that holds // is a fault.
    ens[0].customer_ref = "A//B";
    var r6: u8[>..] = [];
    assert(bank_statement::write_mt940(sts, ens, lim, r6).kind == bank_statement::F_SYNTAX);
    ens[0].customer_ref = "NONREF";
    // Balances that do not add up are a fault.
    ens[0].amount.minor = ens[0].amount.minor + 1;
    var r7: u8[>..] = [];
    assert(bank_statement::write_mt940(sts, ens, lim, r7).kind == bank_statement::F_BALANCE);
    ens[0].amount.minor = ens[0].amount.minor - 1;
    // A reference over 16 characters is a fault and is never cut.
    sts[0].reference = "12345678901234567";
    var r8: u8[>..] = [];
    assert(bank_statement::write_mt940(sts, ens, lim, r8).kind != 0);
}

const LISTS_TEXT: const u8[:] = "!Account\nNChecking\nTBank\nDMain account\nL1,000.00\n/12/31/2025\n$250.50\n^\n!Type:Cat\nNFood:Dining\nDEating out\nT\nI\nE\nRSched A\nB10.00\nB20.50\nXodd\n^\n!Type:Budget\nNHome\nB5.00\n^\n!Type:Class\nNGarden\nDplants\n^\n!Type:Security\nNAcme Corp\nSACME\nTStock\nGGrowth\n^\n!Type:Tag\nNtrip\nDvacation\n^\n!Type:Payee\nPBob's Cafe\nA1 Main St\nAFloor 2\nCParis\nSIDF\nZ75001\nYFRA\nN0102030405\n#ACC-9\n^\n!Type:Prices\n\"ACME\",50 1/2,\"6/30/98\"\n^\n\"A,B\",10.25,\"1/2'25\"\n^\n";

fn test_qif_item_lists() {
    let lim = bank_statement::default_limits();
    let ropts = bank_statement::QifOptions { date_order: bank_statement::DATE_MDY, .. };
    var items: bank_statement::QifItem[>..] = [];
    var buds: bank_statement::Amount[>..] = [];
    var lns: bank_statement::QifField[>..] = [];
    var ext: bank_statement::QifField[>..] = [];
    var prs: bank_statement::QifPrice[>..] = [];
    let f = bank_statement::parse_qif_lists(LISTS_TEXT, lim, ropts, items, buds, lns, ext, prs);
    if f.kind != 0 { print("FAIL lists ", bank_statement::kind_name(f.kind), " ", f.line, " ", f.detail, "\n"); }
    assert(f.kind == 0);
    assert(items.len == 7 && prs.len == 2);
    let a = items[0];
    assert(a.section == bank_statement::Q_ACCOUNT && a.name == "Checking" && a.kind == "Bank" && a.description == "Main account");
    assert(a.has_limit && a.limit.minor == 100000 && a.has_balance && a.balance.minor == 25050);
    assert(a.has_balance_date && a.balance_date.year == 2025 && a.balance_date.month == 12 && a.balance_date.day == 31);
    let c = items[1];
    assert(c.name == "Food:Dining" && c.tax && c.income && c.expense && c.schedule == "Sched A");
    assert(c.budget_count == 2 && buds[c.budget_start].minor == 1000 && buds[c.budget_start + 1].minor == 2050);
    // A code the section does not know stays a field.
    assert(c.field_count == 1 && ext[c.field_start].code == 'X' && ext[c.field_start].value == "odd");
    assert(items[2].section == bank_statement::Q_BUDGET && buds[items[2].budget_start].minor == 500);
    assert(items[3].section == bank_statement::Q_CLASS && items[3].name == "Garden");
    let s = items[4];
    assert(s.name == "Acme Corp" && s.symbol == "ACME" && s.kind == "Stock" && s.goal == "Growth");
    assert(items[5].section == bank_statement::Q_TAG && items[5].description == "vacation");
    let p = items[6];
    assert(p.section == bank_statement::Q_PAYEE && p.name == "Bob's Cafe" && p.address_count == 2);
    assert(lns[p.address_start].value == "1 Main St" && lns[p.address_start + 1].value == "Floor 2");
    assert(p.city == "Paris" && p.state == "IDF" && p.zip == "75001" && p.country == "FRA");
    assert(p.phone == "0102030405" && p.account == "ACC-9");
    assert(prs[0].symbol == "ACME" && prs[0].price.num == 101 && prs[0].price.den == 2);
    assert(prs[0].date.year == 1998 && prs[0].date.month == 6 && prs[0].date.day == 30);
    assert(prs[1].symbol == "A,B" && prs[1].price.num == 41 && prs[1].price.den == 4 && prs[1].date.year == 2025);
    // The record list reader keeps the payee section as fields.
    var recs: bank_statement::QifRecord[>..] = [];
    var spl: bank_statement::QifSplit[>..] = [];
    var ex2: bank_statement::QifField[>..] = [];
    var xbuf35: u8[>..] = [];
    var xbuf35_pre: u8[>..] = [];
    assert(bank_statement::parse_qif(LISTS_TEXT, lim, ropts, recs, spl, ex2, xbuf35_pre).kind == 0);
    // Write and read back to the same values.
    var out: u8[>..] = [];
    let wopts = bank_statement::QifWriteOptions { date_order: 0 };
    let w = bank_statement::write_qif_lists(items, buds, lns, ext, prs, wopts, lim, out);
    if w.kind != 0 { print("FAIL write lists ", bank_statement::kind_name(w.kind), " ", w.detail, "\n"); }
    assert(w.kind == 0);
    var i2: bank_statement::QifItem[>..] = [];
    var b2: bank_statement::Amount[>..] = [];
    var l2: bank_statement::QifField[>..] = [];
    var e2: bank_statement::QifField[>..] = [];
    var p2: bank_statement::QifPrice[>..] = [];
    assert(bank_statement::parse_qif_lists(out, lim, ropts, i2, b2, l2, e2, p2).kind == 0);
    assert(i2.len == 7 && p2.len == 2);
    assert(i2[0].limit.minor == 100000 && i2[0].balance_date.day == 31 && i2[1].tax && i2[1].income && i2[1].expense);
    assert(i2[1].budget_count == 2 && b2[i2[1].budget_start + 1].minor == 2050 && e2[i2[1].field_start].value == "odd");
    assert(i2[6].address_count == 2 && l2[i2[6].address_start].value == "1 Main St" && i2[6].account == "ACC-9");
    assert(p2[0].price.num == 101 && p2[0].price.den == 2 && p2[1].symbol == "A,B" && p2[1].price.num == 41);
    var o3: u8[>..] = [];
    assert(bank_statement::write_qif_lists(i2, b2, l2, e2, p2, wopts, lim, o3).kind == 0);
    assert(o3 == out);
}

fn test_qif_item_faults() {
    let lim = bank_statement::default_limits();
    let ropts = bank_statement::QifOptions { date_order: bank_statement::DATE_MDY, .. };
    var items: bank_statement::QifItem[>..] = [];
    var buds: bank_statement::Amount[>..] = [];
    var lns: bank_statement::QifField[>..] = [];
    var ext: bank_statement::QifField[>..] = [];
    var prs: bank_statement::QifPrice[>..] = [];
    // A price line with four parts, an unbalanced quote and a bad price are faults.
    assert(bank_statement::parse_qif_lists("!Type:Prices\n\"A\",1,\"1/1/2020\",9\n^\n", lim, ropts, items, buds, lns, ext, prs).kind == bank_statement::F_SYNTAX);
    var i2: bank_statement::QifItem[>..] = [];
    var p2: bank_statement::QifPrice[>..] = [];
    assert(bank_statement::parse_qif_lists("!Type:Prices\n\"A,1,\"1/1/2020\"\n", lim, ropts, i2, buds, lns, ext, p2).kind == bank_statement::F_SYNTAX);
    var p3: bank_statement::QifPrice[>..] = [];
    assert(bank_statement::parse_qif_lists("!Type:Prices\n\"A\",x,\"1/1/2020\"\n", lim, ropts, i2, buds, lns, ext, p3).kind != 0);
    // A record without a closing ^ is kept.
    var i3: bank_statement::QifItem[>..] = [];
    assert(bank_statement::parse_qif_lists("!Type:Class\nNKept\n", lim, ropts, i3, buds, lns, ext, p3).kind == 0 && i3.len == 1);
    // A repeated scalar line is kept as a field, not dropped.
    var i4: bank_statement::QifItem[>..] = [];
    var e4: bank_statement::QifField[>..] = [];
    assert(bank_statement::parse_qif_lists("!Type:Class\nNA\nNB\n^\n", lim, ropts, i4, buds, lns, e4, p3).kind == 0);
    assert(i4[0].name == "A" && i4[0].field_count == 1 && e4[0].value == "B");
    // The writer refuses a line end, a control byte, a quote in a symbol and a missing name.
    let wopts = bank_statement::QifWriteOptions { date_order: 0 };
    var out: u8[>..] = [];
    var it = i3[0];
    it.description = "a\nb";
    var one: bank_statement::QifItem[>..] = [it];
    assert(bank_statement::write_qif_lists(one, buds, lns, ext, p3, wopts, lim, out).kind == bank_statement::F_SYNTAX);
    it.description = "";
    it.name = "";
    var two: bank_statement::QifItem[>..] = [it];
    assert(bank_statement::write_qif_lists(two, buds, lns, ext, p3, wopts, lim, out).kind == bank_statement::F_SYNTAX);
    var bad: bank_statement::QifPrice[>..] = [bank_statement::QifPrice { symbol: "A\"B", price: bank_statement::Rational { num: 1, den: 1 }, price_text: "", date: bank_statement::Date { year: 2020, month: 1, day: 1 } }];
    var none: bank_statement::QifItem[>..] = [];
    assert(bank_statement::write_qif_lists(none, buds, lns, ext, bad, wopts, lim, out).kind == bank_statement::F_SYNTAX);
    // A field code of ! or ^ cannot start a new record or section.
    var xf: bank_statement::QifField[>..] = [bank_statement::QifField { code: '^', value: "x" }];
    var it2 = i3[0];
    it2.field_start = 0;
    it2.field_count = 1;
    var three: bank_statement::QifItem[>..] = [it2];
    assert(bank_statement::write_qif_lists(three, buds, lns, xf, p3, wopts, lim, out).kind == bank_statement::F_SYNTAX);
}

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

fn test_ofx_seclist() {
    let lim = bank_statement::default_limits();
    var secs: bank_statement::OfxSecurity[>..] = [];
    var notes: bank_statement::Note[>..] = [];
    var buf: u8[>..] = [];
    let f = bank_statement::parse_ofx_securities(SECLIST_SGML, lim, secs, notes, buf);
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
    assert(bank_statement::parse_ofx_securities(OFX_EXTRA, lim, s2, n2, b2).kind == 0 && s2.len == 0);
    // A bad price is a fault; a small record limit is a fault.
    var s3: bank_statement::OfxSecurity[>..] = [];
    var n3: bank_statement::Note[>..] = [];
    var b3: u8[>..] = [];
    var small = bank_statement::default_limits();
    small.max_records = 2;
    assert(bank_statement::parse_ofx_securities(SECLIST_SGML, small, s3, n3, b3).kind == bank_statement::F_LIMIT);
    // The writer writes the list back and the reader reads the same
    // securities.
    var out: u8[>..] = [];
    let wf = bank_statement::write_ofx_securities(secs, notes, ofx_wopts(102), lim, out);
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
    assert(bank_statement::write_ofx_securities(secs, notes, ofx_wopts(211), lim, out2).kind == 0);
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
    assert(bank_statement::write_ofx_securities(one, no, ofx_wopts(102), lim, o3).kind == bank_statement::F_UNKNOWN_TAG);
    bad.kind = "STOCKINFO";
    bad.id = "";
    var one2: bank_statement::OfxSecurity[>..] = [bad];
    assert(bank_statement::write_ofx_securities(one2, no, ofx_wopts(102), lim, o3).kind == bank_statement::F_SYNTAX);
    bad.id = "1";
    bad.currency = "EURO";
    var one3: bank_statement::OfxSecurity[>..] = [bad];
    assert(bank_statement::write_ofx_securities(one3, no, ofx_wopts(102), lim, o3).kind == bank_statement::F_SYNTAX);
    bad.currency = "";
    bad.has_price = true;
    bad.price = bank_statement::Rational { num: 1, den: 3 };
    var one4: bank_statement::OfxSecurity[>..] = [bad];
    assert(bank_statement::write_ofx_securities(one4, no, ofx_wopts(102), lim, o3).kind == bank_statement::F_AMOUNT);
}

fn test_country() {
    assert(bank_statement::country_known("USA") && bank_statement::country_known("FRA") && bank_statement::country_known("ZWE"));
    assert(bank_statement::country_known("ABW") && bank_statement::country_known("SSD"));
    assert(!bank_statement::country_known("XKX") && !bank_statement::country_known("usa") && !bank_statement::country_known("US") && !bank_statement::country_known(""));
    // Every code of the table is found, so the table is sorted.
    for c in bank_statement::COUNTRY_CODES { assert(bank_statement::country_known(c)); }
    assert(bank_statement::COUNTRY_CODES.len == 250);
    let lim = bank_statement::default_limits();
    let at = find(OFX_EXTRA, "<COUNTRY>FRA");
    assert(at > 0);
    var tb: u8[>..] = [];
    bank_statement::put(tb, OFX_EXTRA[..at]);
    bank_statement::put(tb, "<COUNTRY>ZZZ");
    bank_statement::put(tb, OFX_EXTRA[at + 12..]);
    let text: const u8[:] = tb;
    var sts: bank_statement::Statement[>..] = [];
    var ens: bank_statement::Entry[>..] = [];
    var bals: bank_statement::Balance[>..] = [];
    var notes: bank_statement::Note[>..] = [];
    var buf: u8[>..] = [];
    // The reader accepts an unknown country by default and refuses it on request.
    let lax = bank_statement::OfxOptions { .. };
    assert(bank_statement::parse_ofx(text, lim, lax, sts, ens, bals, notes, buf).kind == 0);
    var s2: bank_statement::Statement[>..] = [];
    var e2: bank_statement::Entry[>..] = [];
    var b2: bank_statement::Balance[>..] = [];
    var n2: bank_statement::Note[>..] = [];
    var u2: u8[>..] = [];
    let strict = bank_statement::OfxOptions { check_country: true, .. };
    assert(bank_statement::parse_ofx(text, lim, strict, s2, e2, b2, n2, u2).kind == bank_statement::F_SYNTAX);
    // The writer always refuses it.
    var out: u8[>..] = [];
    assert(bank_statement::write_ofx(sts, ens, notes, ofx_wopts(102), lim, out).kind == bank_statement::F_SYNTAX);
}

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

fn test_ofx_profile() {
    let lim = bank_statement::default_limits();
    var pr = bank_statement::OfxProfile { found: false, updated: bank_statement::no_date(), name: "", addr1: "", addr2: "", addr3: "", city: "", state: "", postal_code: "", country: "", cs_phone: "", ts_phone: "", fax_phone: "", url: "", email: "" };
    var sn: bank_statement::OfxSignonInfo[>..] = [];
    var ms: bank_statement::OfxMsgSet[>..] = [];
    var notes: bank_statement::Note[>..] = [];
    var buf: u8[>..] = [];
    let f = bank_statement::parse_ofx_profile(PROFILE_SGML, lim, pr, sn, ms, notes, buf);
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
    assert(bank_statement::parse_ofx_profile(OFX_EXTRA, lim, p2, s2, m2, n2, b2).kind == 0 && !p2.found);
    // A flag that is not Y or N is a fault.
    let at = find(PROFILE_SGML, "<CASESEN>Y");
    assert(at > 0);
    var tb: u8[>..] = [];
    bank_statement::put(tb, PROFILE_SGML[..at]);
    bank_statement::put(tb, "<CASESEN>maybe");
    bank_statement::put(tb, PROFILE_SGML[at + 10..]);
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
    assert(bank_statement::parse_ofx_profile(PROFILE_SGML, small, p4, s4, m4, n4, b4).kind == bank_statement::F_LIMIT);
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

fn test_legacy_charset() {
    let lim = bank_statement::default_limits();
    // MT940: the payee holds a Windows-1252 smart quote.
    var text: const u8[:] = ":20:S\n:25:A\n:28C:1/1\n:60F:C250101EUR1,00\n:61:250102C10,00NTRFREF\n:86:Caf\x92 Ltd\n:62F:C250102EUR11,00\n";
    var opts = bank_statement::Mt940Options { skip_balance_check: false, check_fields: false, style: 0 };
    opts.charset = bank_statement::CS_CP1252;
    var sts: bank_statement::Statement[>..] = [];
    var ens: bank_statement::Entry[>..] = [];
    var bals: bank_statement::Balance[>..] = [];
    var notes: bank_statement::Note[>..] = [];
    var buf: u8[>..] = [];
    assert(bank_statement::parse_mt940(text, lim, opts, sts, ens, bals, notes, buf).kind == 0);
    assert(ens.len == 1 && ens[0].narrative == "Caf\xe2\x80\x99 Ltd");
    // The field rules hold the SWIFT character set, so the decoded
    // text faults while the rules are on.
    var optsf = bank_statement::Mt940Options { skip_balance_check: false, check_fields: true, style: 0 };
    optsf.charset = bank_statement::CS_CP1252;
    var stsf: bank_statement::Statement[>..] = [];
    var ensf: bank_statement::Entry[>..] = [];
    var balsf: bank_statement::Balance[>..] = [];
    var notesf: bank_statement::Note[>..] = [];
    var buff: u8[>..] = [];
    assert(bank_statement::parse_mt940(text, lim, optsf, stsf, ensf, balsf, notesf, buff).kind == bank_statement::F_SYNTAX);
    // Without the charset the raw byte stays. The field rules are off,
    // because the raw byte leaves the SWIFT set.
    var opts0 = bank_statement::Mt940Options { skip_balance_check: false, check_fields: false, style: 0 };
    var sts2: bank_statement::Statement[>..] = [];
    var ens2: bank_statement::Entry[>..] = [];
    var bals2: bank_statement::Balance[>..] = [];
    var notes2: bank_statement::Note[>..] = [];
    var buf2: u8[>..] = [];
    assert(bank_statement::parse_mt940(text, lim, opts0, sts2, ens2, bals2, notes2, buf2).kind == 0);
    assert(ens2.len == 1 && ens2[0].narrative == "Caf\x92 Ltd");
    // QIF: the payee holds the same byte.
    var qtext: const u8[:] = "!Type:Bank\nD01/02/2020\nT-10.00\nPCaf\x92 Ltd\n^\n";
    var qopts = bank_statement::QifOptions { .. };
    qopts.charset = bank_statement::CS_CP1252;
    qopts.date_order = bank_statement::DATE_MDY;
    var recs: bank_statement::QifRecord[>..] = [];
    var spl: bank_statement::QifSplit[>..] = [];
    var ext: bank_statement::QifField[>..] = [];
    var qbuf: u8[>..] = [];
    assert(bank_statement::parse_qif(qtext, lim, qopts, recs, spl, ext, qbuf).kind == 0);
    assert(recs.len == 1 && recs[0].payee == "Caf\xe2\x80\x99 Ltd");
    var qopts0 = bank_statement::QifOptions { .. };
    qopts0.date_order = bank_statement::DATE_MDY;
    var recs2: bank_statement::QifRecord[>..] = [];
    var spl2: bank_statement::QifSplit[>..] = [];
    var ext2: bank_statement::QifField[>..] = [];
    var qbuf2: u8[>..] = [];
    assert(bank_statement::parse_qif(qtext, lim, qopts0, recs2, spl2, ext2, qbuf2).kind == 0);
    assert(recs2.len == 1 && recs2[0].payee == "Caf\x92 Ltd");
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
    assert(bank_statement::parse_camt(CAMT53, lim, opts, hd, sts, ens, bals, buf2).kind == 0);
    assert(ens.len > 0);
    let rv, ok = bank_statement::reversal_of(ens[0]);
    assert(ok);
    assert(rv.mark == "D" && ens[0].mark == "C");
    assert(rv.amount.minor == -ens[0].amount.minor);
    let nr, ok2 = bank_statement::reversal_of(ens[0]);
    assert(ok2 && nr.amount.minor == -ens[0].amount.minor);
}

fn test_field86() {
    let lim = bank_statement::default_limits();
    var extra: bank_statement::DialectValue[>..] = [];
    var buf: u8[>..] = [];
    // The GVC codes.
    let f, fe = bank_statement::parse_field_86("?00GVC123?10EREF-1?30DEUTDEFF?31DE89370400440532013000?32Acme?33Corp?20line one?21line two?99odd", lim, extra, buf);
    if fe.kind != 0 { print("FAIL field86 ", bank_statement::kind_name(fe.kind), " ", fe.detail, "\n"); }
    assert(fe.kind == 0);
    assert(f.transaction_code == "GVC123" && f.end_to_end_id == "EREF-1");
    assert(f.counterparty_bic == "DEUTDEFF" && f.counterparty_iban == "DE89370400440532013000");
    assert(f.creditor_name == "Acme Corp");
    assert(f.remittance_info == "line one line two");
    assert(f.tag_count == 1 && extra[0].key == "?99" && extra[0].value == "odd");
    // The slash tags, the amounts and the extra tag.
    var e2: bank_statement::DialectValue[>..] = [];
    var b2: u8[>..] = [];
    let g, ge = bank_statement::parse_field_86("/EREF/E2E/OCMT/EUR12,34/CHGS/1,50/PURP/GPCS/BOGUS/xyz", lim, e2, b2);
    assert(ge.kind == 0);
    assert(g.end_to_end_id == "E2E" && g.purpose_code == "GPCS");
    assert(g.has_original_amount && g.original_amount.minor == 1234);
    assert(g.has_charges_amount && g.charges_amount.minor == 150);
    assert(g.tag_count == 1 && e2[0].key == "BOGUS" && e2[0].value == "xyz");
    // A REMI tag joins its parts. A placeholder BIC stays out.
    var e3: bank_statement::DialectValue[>..] = [];
    var b3: u8[>..] = [];
    let h, he = bank_statement::parse_field_86("/REMI/part one//REMI/part two//BIC/NOTPROVIDED", lim, e3, b3);
    assert(he.kind == 0);
    assert(h.remittance_info == "part one part two" && h.counterparty_bic == "");
    // The IBAN fallback finds the naked IBAN.
    var e4: bank_statement::DialectValue[>..] = [];
    var b4: u8[>..] = [];
    let k, ke = bank_statement::parse_field_86("pay to DE89370400440532013000 today", lim, e4, b4);
    assert(ke.kind == 0);
    assert(k.counterparty_iban == "DE89370400440532013000" && k.counterparty_bic == "");
    // The BIC fallback skips the placeholder.
    var e5: bank_statement::DialectValue[>..] = [];
    var b5: u8[>..] = [];
    let m, me = bank_statement::parse_field_86("via NOTPROVIDED or DEUTDEFFXXX", lim, e5, b5);
    assert(me.kind == 0);
    assert(m.counterparty_bic == "DEUTDEFFXXX");
    // An amount with a space parses. A bad amount stays out.
    var e6: bank_statement::DialectValue[>..] = [];
    var b6: u8[>..] = [];
    let n, ne = bank_statement::parse_field_86("/ORAMT/EUR 9,99//FEE/nope", lim, e6, b6);
    assert(ne.kind == 0);
    assert(n.has_original_amount && n.original_amount.minor == 999);
    assert(!n.has_charges_amount);
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

fn test_ofx_tree() {
    let lim = bank_statement::default_limits();
    var tree: bank_statement::OfxNode[>..] = [];
    var buf: u8[>..] = [];
    let f = bank_statement::parse_ofx_tree(OFX_INV, lim, tree, buf);
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
    assert(bank_statement::parse_ofx(OFX_INV, lim, ropts, base_s, base_e, base_b, base_n, base_u).kind == 0);
    var v = 0;
    while v < 3 {
        var o = ofx_wopts(102);
        if v == 1 { o = ofx_wopts(211); o.indent = true; }
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
        tree_node(0, "SIGNONMSGSRQV1", ""), tree_node(1, "SONRQ", ""), tree_node(2, "DTCLIENT", "20200101"),
        tree_node(2, "USERID", "a<b>&c"), tree_node(2, "LANGUAGE", "ENG"),
        tree_node(2, "APPID", "GOOSE"), tree_node(2, "APPVER", "2600"),
    ];
    var ro: u8[>..] = [];
    assert(bank_statement::write_ofx_tree(req, ofx_wopts(211), lim, ro).kind == 0);
    assert(find(ro, "a&lt;b&gt;&amp;c") > 0 && find(ro, "a<b>") < 0);
    var back: bank_statement::OfxNode[>..] = [];
    var rb: u8[>..] = [];
    assert(bank_statement::parse_ofx_tree(ro, lim, back, rb).kind == 0);
    assert(back.len == 7 && back[3].text == "a<b>&c");
    // Refusals of the loose writer: a bad name, a depth jump, a text in
    // an aggregate, a control byte, an empty leaf.
    var bad1: bank_statement::OfxNode[>..] = [tree_node(0, "a b", "x")];
    assert(run_tree_write(bad1, ofx_wopts_loose()) == bank_statement::F_SYNTAX);
    var bad2: bank_statement::OfxNode[>..] = [tree_node(0, "A", ""), tree_node(2, "B", "x")];
    assert(run_tree_write(bad2, ofx_wopts_loose()) == bank_statement::F_SYNTAX);
    var bad3: bank_statement::OfxNode[>..] = [tree_node(0, "A", "text"), tree_node(1, "B", "x")];
    assert(run_tree_write(bad3, ofx_wopts_loose()) == bank_statement::F_SYNTAX);
    var bad4: bank_statement::OfxNode[>..] = [tree_node(0, "A", "x\x01y")];
    assert(run_tree_write(bad4, ofx_wopts_loose()) == bank_statement::F_SYNTAX);
    var bad5: bank_statement::OfxNode[>..] = [tree_node(0, "MEMO", "")];
    assert(run_tree_write(bad5, ofx_wopts_loose()) == bank_statement::F_SYNTAX);
    var bad6: bank_statement::OfxNode[>..] = [tree_node(1, "A", "x")];
    assert(run_tree_write(bad6, ofx_wopts_loose()) == bank_statement::F_SYNTAX);
    // Refusals of the rule check: an unknown element, a missing
    // required element, a wrong order, a bad flag value, an unknown tag
    // inside an aggregate.
    var r1: bank_statement::OfxNode[>..] = [tree_node(0, "NOTREAL", "x")];
    assert(run_tree_write(r1, ofx_wopts(102)) == bank_statement::F_UNKNOWN_TAG);
    var r2: bank_statement::OfxNode[>..] = [
        tree_node(0, "SIGNONMSGSRQV1", ""), tree_node(1, "SONRQ", ""), tree_node(2, "DTCLIENT", "20200101"),
    ];
    assert(run_tree_write(r2, ofx_wopts(102)) == bank_statement::F_SYNTAX);
    var r3: bank_statement::OfxNode[>..] = [
        tree_node(0, "SIGNONMSGSRQV1", ""), tree_node(1, "SONRQ", ""), tree_node(2, "USERID", "alice"),
        tree_node(2, "DTCLIENT", "20200101"), tree_node(2, "LANGUAGE", "ENG"),
        tree_node(2, "APPID", "GOOSE"), tree_node(2, "APPVER", "2600"),
    ];
    assert(run_tree_write(r3, ofx_wopts(102)) == bank_statement::F_SYNTAX);
    var r4: bank_statement::OfxNode[>..] = [
        tree_node(0, "SIGNONMSGSRQV1", ""), tree_node(1, "SONRQ", ""), tree_node(2, "DTCLIENT", "20200101"),
        tree_node(2, "USERID", "alice"), tree_node(2, "GENUSERKEY", "MAYBE"),
        tree_node(2, "LANGUAGE", "ENG"),
        tree_node(2, "APPID", "GOOSE"), tree_node(2, "APPVER", "2600"),
    ];
    assert(run_tree_write(r4, ofx_wopts(102)) == bank_statement::F_SYNTAX);
    var r5: bank_statement::OfxNode[>..] = [
        tree_node(0, "SIGNONMSGSRQV1", ""), tree_node(1, "SONRQ", ""), tree_node(2, "DTCLIENT", "20200101"),
        tree_node(2, "USERID", "alice"), tree_node(2, "LANGUAGE", "ENG"),
        tree_node(2, "APPID", "GOOSE"), tree_node(2, "APPVER", "2600"),
        tree_node(2, "NOTINSONRQ", "x"),
    ];
    assert(run_tree_write(r5, ofx_wopts(102)) == bank_statement::F_UNKNOWN_TAG);
    // A private extension at the start of X passes the rule check.
    var px: bank_statement::OfxNode[>..] = [
        tree_node(0, "XTENSION", ""), tree_node(1, "XFIELD", "free"),
    ];
    assert(run_tree_write(px, ofx_wopts(102)) == 0);
}

fn test_write_qif_lists() {
    let text: const u8[:] = "!Account\nNChecking\nTBank\n^\n!Type:Cat\nNFood:Dining\nE\n^\n!Type:Class\nNHome\n^\n!Type:Bank\nD01/02/2025\nT-5.00\nPShop\n^\n";
    let lim = bank_statement::default_limits();
    let ropts = bank_statement::QifOptions { date_order: bank_statement::DATE_MDY, .. };
    var recs: bank_statement::QifRecord[>..] = [];
    var spl: bank_statement::QifSplit[>..] = [];
    var ext: bank_statement::QifField[>..] = [];
    var xbuf36: u8[>..] = [];
    var xbuf36_pre: u8[>..] = [];
    assert(bank_statement::parse_qif(text, lim, ropts, recs, spl, ext, xbuf36_pre).kind == 0);
    var out: u8[>..] = [];
    let wopts = bank_statement::QifWriteOptions { date_order: 0 };
    assert(bank_statement::write_qif(recs, spl, ext, wopts, lim, out).kind == 0);
    assert(out == text);
    // A section the writer does not write is a fault.
    recs[0].section = bank_statement::Q_INVST;
    var o2: u8[>..] = [];
    assert(bank_statement::write_qif(recs, spl, ext, wopts, lim, o2).kind == bank_statement::F_SYNTAX);
}

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

fn test_ofx_extra() {
    let lim = bank_statement::default_limits();
    let ropts = bank_statement::OfxOptions { .. };
    var sts: bank_statement::Statement[>..] = [];
    var ens: bank_statement::Entry[>..] = [];
    var bals: bank_statement::Balance[>..] = [];
    var notes: bank_statement::Note[>..] = [];
    var buf: u8[>..] = [];
    let f = bank_statement::parse_ofx(OFX_EXTRA, lim, ropts, sts, ens, bals, notes, buf);
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
        var o = ofx_wopts(102);
        if v == 1 { o = ofx_wopts(203); o.indent = true; }
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
        extra_equal(ens[0], e2[0]);
        extra_equal(ens[1], e2[1]);
        assert(e2[0].amount.currency == "JPY" && e2[0].amount.minor == -5000);
        v += 1;
    }
    // Refusals.
    let wo = ofx_wopts(102);
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

fn test_ofx_extra_faults() {
    assert(ofx_kind("") == 0);
    assert(ofx_kind("<CORRECTACTION>MAYBE") == bank_statement::F_SYNTAX);
    assert(ofx_kind("<DTUSER>2020xx01") == bank_statement::F_DATE);
    assert(ofx_kind("<NAME>A<PAYEE><NAME>B</PAYEE>") == bank_statement::F_SYNTAX);
    assert(ofx_kind("<CURRENCY><CURRATE>1<CURSYM>EUR</CURRENCY><ORIGCURRENCY><CURRATE>1<CURSYM>EUR</ORIGCURRENCY>") == bank_statement::F_SYNTAX);
    assert(ofx_kind("<CURRENCY><CURRATE>0<CURSYM>EUR</CURRENCY>") == bank_statement::F_AMOUNT);
    assert(ofx_kind("<CURRENCY><CURRATE>1<CURSYM>ZZZ</CURRENCY>") == bank_statement::F_AMOUNT);
    assert(ofx_kind("<CURRENCY><CURSYM>EUR</CURRENCY>") == bank_statement::F_AMOUNT);
}

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

fn test_ofx_more() {
    let lim = bank_statement::default_limits();
    let ropts = bank_statement::OfxOptions { .. };
    var sts: bank_statement::Statement[>..] = [];
    var ens: bank_statement::Entry[>..] = [];
    var bals: bank_statement::Balance[>..] = [];
    var notes: bank_statement::Note[>..] = [];
    var buf: u8[>..] = [];
    let f = bank_statement::parse_ofx(OFX_EXTRA2, lim, ropts, sts, ens, bals, notes, buf);
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
        var o = ofx_wopts(102);
        if v == 1 { o = ofx_wopts(211); o.indent = true; }
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
        more_equal(ens[0], e2[0]);
        more_equal(ens[1], e2[1]);
        assert(e2[0].ofx.image_count == 2);
        v += 1;
    }
    // Refusals.
    let wo = ofx_wopts(102);
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
    assert(ofx_kind("<SIC>12ab") == bank_statement::F_SYNTAX);
    assert(ofx_kind("<INV401KSOURCE>NOPE") == bank_statement::F_SYNTAX);
    assert(ofx_kind("<BANKACCTTO><BANKID>1<ACCTID>2<ACCTTYPE>CD</BANKACCTTO><CCACCTTO><ACCTID>3</CCACCTTO>") == bank_statement::F_SYNTAX);
    assert(ofx_kind("<IMAGEDATA><IMAGETYPE>TAX<IMAGEREF>r<IMAGEREFTYPE>URL<IMAGEDELAY>1<DTIMAGEAVAIL>20200101</IMAGEDATA>") == bank_statement::F_SYNTAX);
    assert(ofx_kind("<IMAGEDATA><IMAGETYPE>TAX<IMAGEREF>r<IMAGEREFTYPE>NET</IMAGEDATA>") == bank_statement::F_SYNTAX);
    // A third image is a fault.
    assert(ofx_kind("<IMAGEDATA><IMAGETYPE>TAX<IMAGEREF>a<IMAGEREFTYPE>URL</IMAGEDATA><IMAGEDATA><IMAGETYPE>TAX<IMAGEREF>b<IMAGEREFTYPE>URL</IMAGEDATA><IMAGEDATA><IMAGETYPE>TAX<IMAGEREF>c<IMAGEREFTYPE>URL</IMAGEDATA>") == bank_statement::F_SYNTAX);
    assert(ofx_kind("<IMAGEDATA><IMAGETYPE>TAX<IMAGEREF>r<IMAGEREFTYPE>URL<IMAGEDELAY>-1</IMAGEDATA>") == bank_statement::F_SYNTAX);
    assert(ofx_kind("<IMAGEDATA><IMAGETYPE>TAX<IMAGEREF>r<IMAGEREFTYPE>URL<CHECKSUP>BOTH</IMAGEDATA>") == bank_statement::F_SYNTAX);
    assert(ofx_kind("<SIC>5411<INV401KSOURCE>MATCH") == 0);
}

fn test_write_mt942_hybrid() {
    let lim = bank_statement::default_limits();
    let opts = bank_statement::Mt940Options { .. };
    var sts: bank_statement::Statement[>..] = [];
    var ens: bank_statement::Entry[>..] = [];
    var bals: bank_statement::Balance[>..] = [];
    var notes: bank_statement::Note[>..] = [];
    let text = ":20:HYB\n:25:ACC\n:28C:5/1\n:34F:EUR0,\n:60F:C250101EUR100,00\n:61:250102C500,00NTRFREF\n:62F:C250102EUR600,00\n";
    var xbuf37: u8[>..] = [];
    let f = bank_statement::parse_mt940(text, lim, opts, sts, ens, bals, notes, xbuf37);
    if f.kind != 0 { print("FAIL hybrid read ", bank_statement::kind_name(f.kind), " ", f.tag, " ", f.detail, "\n"); }
    assert(f.kind == 0);
    var out: u8[>..] = [];
    let w = bank_statement::write_mt940(sts, ens, lim, out);
    if w.kind != 0 { print("FAIL hybrid write ", bank_statement::kind_name(w.kind), " ", w.tag, " ", w.detail, "\n"); }
    assert(w.kind == 0);
    assert(find(out, ":34F:EUR0,00") >= 0);
    assert(find(out, ":60F:C250101EUR100,00") >= 0);
    assert(find(out, ":62F:C250102EUR600,00") >= 0);
    assert(fk(out) == 0);
}

fn test_write_mt942_bare() {
    let lim = bank_statement::default_limits();
    let opts = bank_statement::Mt940Options { .. };
    var sts: bank_statement::Statement[>..] = [];
    var ens: bank_statement::Entry[>..] = [];
    var bals: bank_statement::Balance[>..] = [];
    var notes: bank_statement::Note[>..] = [];
    let text = ":20:B\n:25:ACC\n:28C:1\n:34F:EUR0,00\n:61:250102C500,00NTRFREF\n";
    var xbuf38: u8[>..] = [];
    var xbuf38_pre: u8[>..] = [];
    assert(bank_statement::parse_mt940(text, lim, opts, sts, ens, bals, notes, xbuf38_pre).kind == 0);
    var out: u8[>..] = [];
    assert(bank_statement::write_mt940(sts, ens, lim, out).kind == 0);
    assert(out == text);
    assert(find(out, ":13D:") < 0 && find(out, ":90") < 0);
}

fn test_write_mt942() {
    let lim = bank_statement::default_limits();
    let opts = bank_statement::Mt940Options { .. };
    var sts: bank_statement::Statement[>..] = [];
    var ens: bank_statement::Entry[>..] = [];
    var bals: bank_statement::Balance[>..] = [];
    var notes: bank_statement::Note[>..] = [];
    let text = ":20:INTERIM\n:21:RELATED\n:25:ACC\n:28C:5/1\n:34F:EUR0,\n:34F:EURD100,\n:13D:2501021530+0100\n:61:250102C500,00NTRFREF\n:61:250102D20,00NTRFREF2\n:90D:1EUR20,00\n:90C:1EUR500,00\n";
    var xbuf39: u8[>..] = [];
    let f = bank_statement::parse_mt940(text, lim, opts, sts, ens, bals, notes, xbuf39);
    if f.kind != 0 { print("FAIL mt942 read ", bank_statement::kind_name(f.kind), " ", f.tag, " ", f.detail, "\n"); }
    assert(f.kind == 0);
    // The writer gives the same text back.
    var out: u8[>..] = [];
    let w = bank_statement::write_mt940(sts, ens, lim, out);
    if w.kind != 0 { print("FAIL mt942 write ", bank_statement::kind_name(w.kind), " ", w.tag, " ", w.detail, "\n"); }
    assert(w.kind == 0);
    let want = ":20:INTERIM\n:21:RELATED\n:25:ACC\n:28C:5/1\n:34F:EUR0,00\n:34F:EURD100,00\n:13D:2501021530+0100\n:61:250102C500,00NTRFREF\n:61:250102D20,00NTRFREF2\n:90D:1EUR20,00\n:90C:1EUR500,00\n";
    assert(out == want);
    // The rules of the manual accept the text that the writer gives.
    assert(fk(text) == 0);
    assert(fk(out) == 0);
    // The reader gives the same values back.
    var s2: bank_statement::Statement[>..] = [];
    var e2: bank_statement::Entry[>..] = [];
    var b2: bank_statement::Balance[>..] = [];
    var n2: bank_statement::Note[>..] = [];
    var xbuf40: u8[>..] = [];
    let g = bank_statement::parse_mt940(out, lim, opts, s2, e2, b2, n2, xbuf40);
    if g.kind != 0 { print("FAIL mt942 reread ", bank_statement::kind_name(g.kind), " ", g.tag, " ", g.detail, "\n"); }
    assert(g.kind == 0);
    let a = sts[0];
    let b = s2[0];
    assert(a.is_interim && b.is_interim);
    assert(a.reference == b.reference && a.related_ref == b.related_ref);
    assert(a.account == b.account && a.number == b.number && a.sequence == b.sequence);
    assert(a.floor.minor == b.floor.minor && a.floor_mark == b.floor_mark);
    assert(a.floor2.minor == b.floor2.minor && a.floor2_mark == b.floor2_mark);
    assert(a.report_date.year == b.report_date.year && a.report_date.month == b.report_date.month);
    assert(a.report_minutes == b.report_minutes && a.report_offset == b.report_offset);
    assert(a.debit_count == b.debit_count && a.credit_count == b.credit_count);
    assert(a.debit_total.minor == b.debit_total.minor && a.credit_total.minor == b.credit_total.minor);
    assert(ens.len == 2 && e2.len == 2);
    assert(ens[0].mark == e2[0].mark && ens[0].amount.minor == e2[0].amount.minor);
    assert(ens[0].customer_ref == e2[0].customer_ref && ens[1].customer_ref == e2[1].customer_ref);
    // A total that does not match the entries is a fault.
    sts[0].debit_total.minor = 1;
    var bad: u8[>..] = [];
    assert(bank_statement::write_mt940(sts, ens, lim, bad).kind == bank_statement::F_TOTAL);
    sts[0].debit_total.minor = 2000;
    // An entry with a currency of its own is a fault.
    ens[0].amount.currency = "USD";
    var bad2: u8[>..] = [];
    assert(bank_statement::write_mt940(sts, ens, lim, bad2).kind == bank_statement::F_SYNTAX);
    ens[0].amount.currency = "EUR";
    // A floor limit without a currency is a fault.
    sts[0].floor.currency = "";
    var bad3: u8[>..] = [];
    assert(bank_statement::write_mt940(sts, ens, lim, bad3).kind == bank_statement::F_SYNTAX);
    sts[0].floor.currency = "EUR";
    // A control byte in the reference is a fault.
    sts[0].reference = "A\x01B";
    var bad4: u8[>..] = [];
    assert(bank_statement::write_mt940(sts, ens, lim, bad4).kind == bank_statement::F_SYNTAX);
    // A statement with an opening balance but no closing balance is a fault.
    sts[0].reference = "INTERIM";
    sts[0].opening.kind = 1;
    var bad5: u8[>..] = [];
    assert(bank_statement::write_mt940(sts, ens, lim, bad5).kind == bank_statement::F_SYNTAX);
    sts[0].opening.kind = 0;
    // A report without a floor limit is a fault.
    sts[0].floor.currency = "";
    var bad6: u8[>..] = [];
    assert(bank_statement::write_mt940(sts, ens, lim, bad6).kind == bank_statement::F_SYNTAX);
    sts[0].floor.currency = "EUR";
    // A total in another currency is a fault.
    sts[0].debit_total.currency = "USD";
    var bad7: u8[>..] = [];
    assert(bank_statement::write_mt940(sts, ens, lim, bad7).kind == bank_statement::F_TOTAL);
    sts[0].debit_total.currency = "EUR";
}

fn main() {
    test_hostile();
    test_hostile_qif();
    test_linear_time();
    test_qif_basic();
    test_qif_category();
    test_qif_sections();
    test_qif_dates();
    test_qif_faults();
    test_qif_headers();
    test_qif_u_amount();
    test_qif_ratio();
    test_mt940_basic();
    test_mt940_64_65();
    test_mt940_balance_error();
    test_mt940_faults();
    test_mt940_multi();
    test_mt942();
    test_currency_rules();
    test_balance_checked();
    test_interim_flag_keeps_check();
    test_lone_cr();
    test_narrative();
    test_narrative_pairs();
    test_narrative_plain();
    test_camt_statement();
    test_camt_interim();
    test_camt_versions();
    test_camt_checks();
    test_camt_faults();
    test_camt_real_documents();
    test_camt_two_statements();
    test_ofx_v1();
    test_ofx_v2();
    test_ofx_invest();
    test_ofx_dates();
    test_ofx_faults();
    test_ofx_forms();
    test_dialect_rabo();
    test_dialect_abn();
    test_dialect_ing();
    test_dialect_regiobank();
    test_dialect_hostile();
    test_swift_fields();
    test_swift_charset();
    test_swift_numbers();
    test_swift_61();
    test_swift_86();
    test_swift_order();
    test_swift_hostile();
    test_write_qif();
    test_write_qif_lists();
    test_qif_item_lists();
    test_ofx_seclist();
    test_country();
    test_ofx_profile();
    test_legacy_charset();
    test_camt_reason();
    test_field86();
    test_ofx_charset();
    test_ofx_net();
    test_ofx_tree();
    test_qif_item_faults();
    test_write_ofx();
    test_write_mt940();
    test_ofx_extra();
    test_ofx_extra_faults();
    test_ofx_more();
    test_ofx_more_faults();
    test_write_mt942();
    test_write_mt942_bare();
    test_dialect_mbank();
    test_styles();
    test_transcode();
    test_write_mt942_hybrid();
    test_amount();
    test_amount_faults();
    test_exponent();
    test_currency_table();
    print("ok\n");
    return 0;
}
