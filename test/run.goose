// Tests for the bank_statement package. Run with: goose run test/run.goose

import std;
import os;
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
    let opts = bank_statement::Mt940Options { skip_balance_check: skip };
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
    let off = bank_statement::Mt940Options { skip_balance_check: true };
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
    let off = bank_statement::Mt940Options { skip_balance_check: true };
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
    run_limited("{1:{{{{{{{{{{x}}}}}}}}}}}\n", lim, 1);
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
    let a = time_parse(20000);
    let b = time_parse(40000);
    if b > 3 * a + 30000000 { print("FAIL time ", a, " ns for 20000, ", b, " ns for 40000\n"); }
    assert(b <= 3 * a + 30000000);
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
    test_amount();
    test_amount_faults();
    test_exponent();
    test_currency_table();
    print("ok\n");
    return 0;
}
