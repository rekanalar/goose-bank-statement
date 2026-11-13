// The tests of the group dialect.
namespace dialect_tests;

import std;
import os;
import xml from "rekanalar/goose-xml@v2.0.0";
import process from "rekanalar/goose-process@v1.0.0";
import bank_statement from "..";
import finance from "rekanalar/goose-finance@v0.1.0";
import statement_checks;

fn test_dialect_rabo() {
    let text = "/MARF/12345/EREF/67890/NAME/JOE DOE/REMI/PAYMENT";
    var vals: bank_statement::DialectValue[>..] = [];
    var buf: u8[>..] = [];
    let f = statement_checks::dialect_run(bank_statement::D_RABOBANK, text, vals, buf);
    if f.kind != 0 { print("FAIL rabo ", bank_statement::kind_name(f.kind), " ", f.detail, "\n"); }
    assert(f.kind == 0);
    assert(statement_checks::dialect_value(vals, "marf") == "12345");
    assert(statement_checks::dialect_value(vals, "eref") == "67890");
    assert(statement_checks::dialect_value(vals, "name") == "JOE DOE");
    assert(statement_checks::dialect_value(vals, "remi") == "PAYMENT");
    assert(statement_checks::dialect_value(vals, "iban") == "");
    // A text of another bank gives no value and no fault.
    var other: bank_statement::DialectValue[>..] = [];
    var buf2: u8[>..] = [];
    let g = statement_checks::dialect_run(bank_statement::D_RABOBANK, "/FOO/BAR/NAME/", other, buf2);
    assert(g.kind == 0);
    assert(other.len == 0);
    // The tags of the bank may stand over the line ends.
    var over: bank_statement::DialectValue[>..] = [];
    var buf3: u8[>..] = [];
    let h = statement_checks::dialect_run(bank_statement::D_RABOBANK, "/MARF/12345/\nEREF/67890", over, buf3);
    assert(h.kind == 0);
    assert(statement_checks::dialect_value(over, "marf") == "12345");
    assert(statement_checks::dialect_value(over, "eref") == "67890");
}

fn test_dialect_abn() {
    let text = "/TRTP/SEPA OVERBOEKING/IBAN/DE89370400440532013000/BIC/GEFRADAM/NAME/ENERGIE BEDRIJF/EREF/NOTPROVIDED";
    var vals: bank_statement::DialectValue[>..] = [];
    var buf: u8[>..] = [];
    let f = statement_checks::dialect_run(bank_statement::D_ABN_AMRO, text, vals, buf);
    if f.kind != 0 { print("FAIL abn ", bank_statement::kind_name(f.kind), " ", f.detail, "\n"); }
    assert(f.kind == 0);
    assert(statement_checks::dialect_value(vals, "trtp") == "SEPA OVERBOEKING");
    assert(statement_checks::dialect_value(vals, "iban") == "DE89370400440532013000");
    assert(statement_checks::dialect_value(vals, "bic") == "GEFRADAM");
    assert(statement_checks::dialect_value(vals, "name") == "ENERGIE BEDRIJF");
    assert(statement_checks::dialect_value(vals, "eref") == "NOTPROVIDED");
    // The account number stands at the start of the text. The dots come out.
    var acc: bank_statement::DialectValue[>..] = [];
    var buf2: u8[>..] = [];
    let g = statement_checks::dialect_run(bank_statement::D_ABN_AMRO, "123.45.67.89/TRTP/SEPA OVERBOEKING", acc, buf2);
    assert(g.kind == 0);
    assert(statement_checks::dialect_value(acc, "account") == "123456789");
    assert(statement_checks::dialect_value(acc, "trtp") == "SEPA OVERBOEKING");
    // A giro account stands at the start of the text.
    var giro: bank_statement::DialectValue[>..] = [];
    var buf3: u8[>..] = [];
    let h = statement_checks::dialect_run(bank_statement::D_ABN_AMRO, "GIRO 4090309", giro, buf3);
    assert(h.kind == 0);
    assert(statement_checks::dialect_value(giro, "account") == "4090309");
    // A text of another bank gives no value and no fault.
    var other: bank_statement::DialectValue[>..] = [];
    var buf4: u8[>..] = [];
    let i = statement_checks::dialect_run(bank_statement::D_ABN_AMRO, "foo", other, buf4);
    assert(i.kind == 0);
    assert(other.len == 0);
}

fn test_dialect_mbank() {
    var vals: bank_statement::DialectValue[>..] = [];
    var buf: u8[>..] = [];
    let f = statement_checks::dialect_run(bank_statement::D_MBANK, "020 PRZELEW;ID IPH: X1234;x ID IPH: XX00123456789012;TNR: 1234.5678;", vals, buf);
    assert(f.kind == 0);
    assert(statement_checks::dialect_value(vals, "transaction_code") == "020");
    assert(statement_checks::dialect_value(vals, "iph_id") == "00123456789012");
    assert(statement_checks::dialect_value(vals, "tnr") == "1234.5678");
    var v2: bank_statement::DialectValue[>..] = [];
    assert(statement_checks::dialect_run(bank_statement::D_MBANK, "5 X\nTNR:\n12.3", v2, buf).kind == 0);
    assert(statement_checks::dialect_value(v2, "transaction_code") == "5" && statement_checks::dialect_value(v2, "tnr") == "12.3");
    // A text with none of the three gives no value and no fault.
    var v3: bank_statement::DialectValue[>..] = [];
    assert(statement_checks::dialect_run(bank_statement::D_MBANK, "hello; TNR:12.3", v3, buf).kind == 0);
    assert(v3.len == 0);
}

fn test_dialect_ing() {
    let text = "/EREF/170330P40411570.4342.2964442//CNTP/\nNL94RABO0123456789/RABONL2U/ENERGIE BEDRIJF///REMI/USTD//\n170330/REM INFO/";
    var vals: bank_statement::DialectValue[>..] = [];
    var buf: u8[>..] = [];
    let f = statement_checks::dialect_run(bank_statement::D_ING, text, vals, buf);
    if f.kind != 0 { print("FAIL ing ", bank_statement::kind_name(f.kind), " ", f.detail, "\n"); }
    assert(f.kind == 0);
    assert(statement_checks::dialect_value(vals, "eref") == "170330P40411570.4342.2964442");
    assert(statement_checks::dialect_value(vals, "cntp.account_number") == "NL94RABO0123456789");
    assert(statement_checks::dialect_value(vals, "cntp.bic") == "RABONL2U");
    assert(statement_checks::dialect_value(vals, "cntp.name") == "ENERGIE BEDRIJF");
    assert(statement_checks::dialect_value(vals, "remi.code") == "USTD");
    assert(statement_checks::dialect_value(vals, "remi.remittance_info") == "170330/REM INFO");
    // A text of another bank gives no value and no fault.
    var other: bank_statement::DialectValue[>..] = [];
    var buf2: u8[>..] = [];
    let g = statement_checks::dialect_run(bank_statement::D_ING, "/FOO/BAR/NAME/", other, buf2);
    assert(g.kind == 0);
    assert(other.len == 0);
}

fn test_dialect_regiobank() {
    let text = "12345678 Jan Jansen\nDorpsstraat 1\niban,remi,desc";
    var vals: bank_statement::DialectValue[>..] = [];
    var buf: u8[>..] = [];
    let f = statement_checks::dialect_run(bank_statement::D_REGIOBANK, text, vals, buf);
    if f.kind != 0 { print("FAIL regio ", bank_statement::kind_name(f.kind), " ", f.detail, "\n"); }
    assert(f.kind == 0);
    assert(statement_checks::dialect_value(vals, "account_number") == "12345678");
    assert(statement_checks::dialect_value(vals, "name") == "Jan Jansen");
    assert(statement_checks::dialect_value(vals, "address") == "Dorpsstraat 1");
    assert(statement_checks::dialect_value(vals, "reference") == "iban,remi,desc");
    // The bank writes "aan" and the name before the parts.
    var other: bank_statement::DialectValue[>..] = [];
    var buf2: u8[>..] = [];
    let g = statement_checks::dialect_run(bank_statement::D_REGIOBANK, "12345678 Jan Jansen\nDorpsstraat 1\naan Jan Jansen,NL01,remi,desc", other, buf2);
    assert(g.kind == 0);
    assert(statement_checks::dialect_value(other, "iban") == "NL01");
    assert(statement_checks::dialect_value(other, "remittance_info") == "remi");
    assert(statement_checks::dialect_value(other, "description") == "desc");
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
