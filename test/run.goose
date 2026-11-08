// Tests for the bank_statement package. Run with: goose run test/run.goose

import std;
import os;
import xml from "rekanalar/goose-xml@v2.0.0";
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

// parse_kind parses text and gives only the fault. The arrays are local.
fn parse_kind(text: const u8[:], lim: bank_statement::Limits&, skip: bool) -> bank_statement::Fault {
    let opts = bank_statement::Mt940Options { skip_balance_check: skip, check_fields: false };
    var sts: bank_statement::Statement[>..] = [];
    var ens: bank_statement::Entry[>..] = [];
    var bals: bank_statement::Balance[>..] = [];
    var notes: bank_statement::Note[>..] = [];
    return bank_statement::parse_mt940(text, lim, opts, sts, ens, bals, notes);
}

fn run_mt940(text: const u8[:], skip: bool, kind: i32, tag: const u8[:]) {
    let lim = bank_statement::default_limits();
    let f = parse_kind(text, lim, skip);
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
    let f = bank_statement::parse_mt940(STMT1, lim, opts, sts, ens, bals, notes);
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
    let f = bank_statement::parse_mt940(text, lim, opts, sts, ens, bals, notes);
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
    let f = bank_statement::parse_mt940(":20:I\n:34F:JPY0\n:61:250101C150NTRFX\n", lim, opts, sts, ens, bals, notes);
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
    let off = bank_statement::Mt940Options { skip_balance_check: true, check_fields: false };
    let f = bank_statement::parse_mt940(text, lim, on, sts, ens, bals, notes);
    assert(f.kind == 0 && sts[0].balance_checked);
    var sts2: bank_statement::Statement[>..] = [];
    var ens2: bank_statement::Entry[>..] = [];
    var bals2: bank_statement::Balance[>..] = [];
    var notes2: bank_statement::Note[>..] = [];
    let g = bank_statement::parse_mt940(text, lim, off, sts2, ens2, bals2, notes2);
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
    let f = bank_statement::parse_mt940(text, lim, opts, sts, ens, bals, notes);
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
    let f = bank_statement::parse_qif(text, lim, opts, recs, spl, ext);
    if f.kind != kind { print("FAIL qif want ", bank_statement::kind_name(kind), " got ", bank_statement::kind_name(f.kind), " line ", f.line, " ", f.detail, "\n"); }
    assert(f.kind == kind);
}

fn test_qif_basic() {
    let lim = bank_statement::default_limits();
    let opts = bank_statement::QifOptions { date_order: bank_statement::DATE_MDY, .. };
    var recs: bank_statement::QifRecord[>..] = [];
    var spl: bank_statement::QifSplit[>..] = [];
    var ext: bank_statement::QifField[>..] = [];
    let f = bank_statement::parse_qif(QIF1, lim, opts, recs, spl, ext);
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
    let f = bank_statement::parse_qif(text, lim, opts, recs, spl, ext);
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
    let f = bank_statement::parse_qif("!Type:Bank\nD1/2/99\n^\nD1/2/24\n^\nD20250102\n^\n", lim, opts, recs, spl, ext);
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
    let f = bank_statement::parse_qif("!Type:Purple\n", lim, opts, recs, spl, ext);
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
    var f = bank_statement::parse_qif(text, lim, opts, recs, spl, ext);
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
    f = bank_statement::parse_qif(text, lim, opts, recs2, spl2, ext2);
    assert(f.kind == 0);
    assert(recs2[0].section == bank_statement::Q_BUDGET && recs2[0].field_count == 2);
    assert(recs2[1].section == bank_statement::Q_TAG && recs2[1].field_count == 2);
    assert(ext2[0].code == 'N' && ext2[0].value == "Groceries");
    assert(ext2[3].code == 'D' && ext2[3].value == "work trips");
    // Case, space and no-blank forms open the same sections.
    var recs3: bank_statement::QifRecord[>..] = [];
    var spl3: bank_statement::QifSplit[>..] = [];
    var ext3: bank_statement::QifField[>..] = [];
    f = bank_statement::parse_qif("!type bank\nT1\n^\n!TYPE:BANK\nT2\n^\n!Type:OthA\nT3\n^\n!type oth a\nT4\n^\n", lim, opts, recs3, spl3, ext3);
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
    let f = bank_statement::parse_qif(text, lim, opts, recs, spl, ext);
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
    let f2 = bank_statement::parse_qif("!Type:Bank\nT100.00\n^\n", lim, opts, recs2, spl2, ext2);
    assert(f2.kind == 0);
    assert(recs2[0].amount_code == 'T' && !recs2[0].has_alt_amount);
    // A value that starts with ... sets no amount and stays a field.
    var recs3: bank_statement::QifRecord[>..] = [];
    var spl3: bank_statement::QifSplit[>..] = [];
    var ext3: bank_statement::QifField[>..] = [];
    let text3 = "!Type:Bank\nT...\n^\nU...\n^\nSOne\n$...\nSTwo\n$5\n^\n";
    let f3 = bank_statement::parse_qif(text3, lim, opts, recs3, spl3, ext3);
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
    let f = bank_statement::parse_qif(text, lim, opts, recs, spl, ext);
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
    let f2 = bank_statement::parse_qif("!Type:Invst\nIabc\n^\n", lim, opts, recs2, spl2, ext2);
    assert(f2.kind == 4 && f2.tag == "I");
    // A fraction of zero is a fault.
    let f3 = bank_statement::parse_qif("!Type:Invst\nI1/0\n^\n", lim, opts, recs2, spl2, ext2);
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
    let f = bank_statement::parse_mt940(text, lim, opts, sts, ens, bals, notes);
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
    let g = bank_statement::parse_mt940(":20:A\n:60F:C250101EUR0,00\n:62F:C250101EUR0,00\n", lim, opts, sts2, ens2, bals2, notes2);
    assert(g.kind == 0 && sts2[0].available.kind == 0 && sts2[0].forward.kind == 0);
    // A second :64: is a fault. A second :65: replaces the value.
    run_mt940(":20:A\n:64:C250101EUR1,00\n:64:C250102EUR2,00\n", false, 2, "64");
    var sts3: bank_statement::Statement[>..] = [];
    var ens3: bank_statement::Entry[>..] = [];
    var bals3: bank_statement::Balance[>..] = [];
    var notes3: bank_statement::Note[>..] = [];
    let off = bank_statement::Mt940Options { skip_balance_check: true, check_fields: false };
    let h = bank_statement::parse_mt940(":20:A\n:65:C250101EUR1,00\n:65:C250102EUR2,00\n", lim, off, sts3, ens3, bals3, notes3);
    assert(h.kind == 0 && sts3[0].forward.amount.minor == 200);
}

fn run_limited(text: const u8[:], lim: bank_statement::Limits&, kind: i32) {
    let f = parse_kind(text, lim, true);
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
    let f = bank_statement::parse_qif("!Type:Bank\nT1\n^\nT2\n^\nT3\n^\n", lim, opts, recs, spl, ext);
    assert(f.kind == 1);
    lim = bank_statement::default_limits();
    lim.max_splits = 1;
    var recs2: bank_statement::QifRecord[>..] = [];
    var spl2: bank_statement::QifSplit[>..] = [];
    var ext2: bank_statement::QifField[>..] = [];
    let g = bank_statement::parse_qif("!Type:Bank\nSa\n$1\nSb\n$2\n^\n", lim, opts, recs2, spl2, ext2);
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
    let f = bank_statement::parse_mt940(text[..], lim, opts, sts, ens, bals, notes);
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
    <GrpHdr><MsgId>MSG-1</MsgId><CreDtTm>2025-01-02T15:30:00+01:00</CreDtTm></GrpHdr>
    <Stmt>
      <Id>STMT-1</Id>
      <ElctrncSeqNb>42</ElctrncSeqNb>
      <LglSeqNb>7</LglSeqNb>
      <CreDtTm>2025-01-02T15:30:00+01:00</CreDtTm>
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
    let f = bank_statement::parse_camt(text, lim, opts, sts, ens, bals, buf);
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
    let f = bank_statement::parse_camt(CAMT53, lim, opts, sts, ens, bals, buf);
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
    let f = bank_statement::parse_camt(CAMT52, lim, opts, sts, ens, bals, buf);
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
    let g = bank_statement::parse_camt(CAMT54, lim, opts, sts2, ens2, bals2, buf2);
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
    let f = bank_statement::parse_camt(CAMT02, lim, opts, sts, ens, bals, buf);
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
    let g = bank_statement::parse_camt(CAMTPREFIX, lim, opts, sts2, ens2, bals2, buf2);
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
    let f = bank_statement::parse_camt(CAMT53, lim, opts, sts, ens, bals, buf);
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
    let f = bank_statement::parse_camt(doc, lim, opts, sts, ens, bals, buf);
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
    let f = bank_statement::parse_camt(REAL52, lim, opts, sts, ens, bals, buf);
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
    let g = bank_statement::parse_camt(REAL54, lim, opts, sts2, ens2, bals2, buf2);
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
    let h = bank_statement::parse_camt(REAL53, lim, opts, sts3, ens3, bals3, buf3);
    assert(h.kind == 7 && h.tag == "Bal");
    var sts4: bank_statement::Statement[>..] = [];
    var ens4: bank_statement::Entry[>..] = [];
    var bals4: bank_statement::Balance[>..] = [];
    var buf4: u8[>..] = [];
    let opts2 = bank_statement::CamtOptions { skip_balance_check: true };
    let k = bank_statement::parse_camt(REAL53, lim, opts2, sts4, ens4, bals4, buf4);
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
<INVTRAN>
<FITID>B1
<DTTRADE>20200310
<MEMO>buy
</INVTRAN>
<SECID>
<UNIQUEID>037833100
<UNIQUEIDTYPE>CUSIP
</SECID>
<INVBUY>
<UNITS>10.5
<UNITPRICE>100.125
<COMMISSION>9.95
<TOTAL>-1051.25
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
</UNIQUEID>
</SECID>
<INCOMETYPE>DIV
<TOTAL>25.00
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

// fields_kind parses text with the field rules on and gives the fault.
fn fields_kind(text: const u8[:]) -> bank_statement::Fault {
    let lim = bank_statement::default_limits();
    let opts = bank_statement::Mt940Options { skip_balance_check: false, check_fields: true };
    var sts: bank_statement::Statement[>..] = [];
    var ens: bank_statement::Entry[>..] = [];
    var bals: bank_statement::Balance[>..] = [];
    var notes: bank_statement::Note[>..] = [];
    return bank_statement::parse_mt940(text, lim, opts, sts, ens, bals, notes);
}

fn expect_fields(text: const u8[:], kind: i32, tag: const u8[:]) {
    let f = fields_kind(text);
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
    assert(fields_kind(STMT1).kind == 0);
    // The widths: 16 passes, 17 fails.
    var a: u8[>..] = [];
    fill('A', 16, a);
    var b: u8[>..] = [];
    stmt_with(a, "ACC", b);
    assert(fields_kind(b).kind == 0);
    var c: u8[>..] = [];
    fill('A', 17, c);
    var d: u8[>..] = [];
    stmt_with(c, "ACC", d);
    let f = fields_kind(d);
    assert(f.kind == 2 && f.tag == "20");
    // The same file parses with the rules off.
    run_mt940(d, false, 0, "");
    // The account: 35 passes, 36 fails.
    var e: u8[>..] = [];
    fill('9', 35, e);
    var g: u8[>..] = [];
    stmt_with("R", e, g);
    assert(fields_kind(g).kind == 0);
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
    assert(fields_kind(ok).kind == 0);
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
    assert(fields_kind(six).kind == 0);
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
    assert(fields_kind(":20:I\n:25:A\n:28C:5/1\n:34F:EUR0,\n:13D:2501021530+0100\n:61:250102C500,00NTRFREF\n:90C:1EUR500,00\n").kind == 0);
    // :NS: may follow any tag.
    assert(fields_kind(":20:R\n:25:A\n:NS:note\n:28C:1/1\n:60F:C250101EUR1,00\n:62F:C250101EUR1,00\n").kind == 0);
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
    let f = fields_kind(many);
    assert(f.kind == 1 || f.kind == 2);
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
    test_swift_fields();
    test_swift_charset();
    test_swift_numbers();
    test_swift_61();
    test_swift_86();
    test_swift_order();
    test_swift_hostile();
    test_amount();
    test_amount_faults();
    test_exponent();
    test_currency_table();
    print("ok\n");
    return 0;
}
