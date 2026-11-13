// The tests of the group amount.
namespace amount_tests;

import std;
import os;
import xml from "rekanalar/goose-xml@v2.0.0";
import process from "rekanalar/goose-process@v1.0.0";
import bank_statement from "..";
import finance from "rekanalar/goose-finance@v0.1.0";
import statement_checks;

fn test_amount() {
    statement_checks::expect_amount("1234,56", 2, ',', 0, 123456);
    statement_checks::expect_amount("0,01", 2, ',', 0, 1);
    statement_checks::expect_amount("100,", 2, ',', 0, 10000);
    statement_checks::expect_amount("100", 2, ',', 0, 10000);
    statement_checks::expect_amount("1234,5", 2, ',', 0, 123450);
    statement_checks::expect_amount("1234", 0, ',', 0, 1234);
    statement_checks::expect_amount("1,234", 3, ',', 0, 1234);
    statement_checks::expect_amount("-1,234.56", 2, '.', ',', -123456);
    statement_checks::expect_amount("(1,234.56)", 2, '.', ',', -123456);
    statement_checks::expect_amount("1.234,56", 2, ',', '.', 123456);
    statement_checks::expect_amount("8.11", 2, '.', ',', 811);
    statement_checks::expect_amount("+5.00", 2, '.', ',', 500);
    statement_checks::expect_amount("92233720368547758,07", 2, ',', 0, 9223372036854775807);
    statement_checks::expect_amount("-92233720368547758,07", 2, ',', 0, -9223372036854775807);
    // The most negative i64 is a valid amount, whole and scaled.
    statement_checks::expect_amount("-9223372036854775808", 0, ',', 0, -9223372036854775808);
    statement_checks::expect_amount("-92233720368547758,08", 2, ',', 0, -9223372036854775808);
    statement_checks::expect_amount("-92233720368547758.08", 2, '.', 0, -9223372036854775808);
    // Trailing zeros of the decimal part change no value.
    statement_checks::expect_amount("-92233720368547758,0800", 2, ',', 0, -9223372036854775808);
}

fn test_amount_faults() {
    statement_checks::expect_amount_fault("", 2, ',', 0, 4);
    statement_checks::expect_amount_fault("1,2,3", 2, ',', 0, 4);
    statement_checks::expect_amount_fault("12a", 2, ',', 0, 4);
    statement_checks::expect_amount_fault("1,234", 2, ',', 0, 4);
    statement_checks::expect_amount_fault("1,23,456.00", 2, '.', ',', 4);
    statement_checks::expect_amount_fault("1,2345.00", 2, '.', ',', 4);
    statement_checks::expect_amount_fault("(1.00", 2, '.', ',', 4);
    statement_checks::expect_amount_fault("92233720368547758,08", 2, ',', 0, 5);
    // One unit beyond the range faults, positive and negative.
    statement_checks::expect_amount_fault("9223372036854775808", 0, ',', 0, 5);
    statement_checks::expect_amount_fault("-9223372036854775809", 0, ',', 0, 5);
    statement_checks::expect_amount_fault("-92233720368547758,09", 2, ',', 0, 5);
    // A decimal form that scales the value up out of the range faults.
    statement_checks::expect_amount_fault("-9223372036854775808.00", 2, '.', 0, 5);
    statement_checks::expect_amount_fault("99999999999999999999999999999999999999999999999999999999", 2, ',', 0, 5);
    statement_checks::expect_amount_fault("-", 2, ',', 0, 4);
}

fn test_exponent() {
    assert(bank_statement::currency_exponent("EUR") == 2);
    assert(bank_statement::currency_exponent("JPY") == 0);
    assert(bank_statement::currency_exponent("KWD") == 3);
    assert(bank_statement::currency_exponent("") == 2);
    assert(bank_statement::currency_exponent("ZZZ") == 2);
}
