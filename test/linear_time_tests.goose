// The tests of the group linear_time.
namespace linear_time_tests;

import std;
import os;
import xml from "rekanalar/goose-xml@v2.0.0";
import process from "rekanalar/goose-process@v1.0.0";
import bank_statement from "..";
import finance from "rekanalar/goose-finance@v0.1.0";
import statement_checks;

// A doubled input must not take more than about twice as long.
fn test_linear_time() {
    // The best of three runs ignores a pause of a busy machine.
    var a = statement_checks::time_parse(20000);
    var b = statement_checks::time_parse(40000);
    for r in 2 {
        let a2 = statement_checks::time_parse(20000);
        let b2 = statement_checks::time_parse(40000);
        if a2 < a { a = a2; }
        if b2 < b { b = b2; }
    }
    if b > 3 * a + 30000000 { print("FAIL time ", a, " ns for 20000, ", b, " ns for 40000\n"); }
    assert(b <= 3 * a + 30000000);
}
