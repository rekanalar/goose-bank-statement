// The tests of the group swift.
namespace swift_tests;

import std;
import os;
import xml from "rekanalar/goose-xml@v2.0.0";
import process from "rekanalar/goose-process@v1.0.0";
import bank_statement from "..";
import finance from "rekanalar/goose-finance@v0.1.0";
import statement_checks;
import sample_texts;

fn test_swift_fields() {
    // A file that keeps the manual parses with the rules on and gives
    // the same values as with the rules off.
    assert(statement_checks::fk(sample_texts::STMT1) == 0);
    // The widths: 16 passes, 17 fails.
    var a: u8[>..] = [];
    statement_checks::fill('A', 16, a);
    var b: u8[>..] = [];
    statement_checks::stmt_with(a, "ACC", b);
    assert(statement_checks::fk(b) == 0);
    var c: u8[>..] = [];
    statement_checks::fill('A', 17, c);
    var d: u8[>..] = [];
    statement_checks::stmt_with(c, "ACC", d);
    var rbuf2: u8[>..] = [];
    let f = statement_checks::fields_kind(d, rbuf2);
    assert(f.kind == 2 && f.tag == "20");
    // The same file parses with the rules off.
    statement_checks::run_mt940(d, false, 0, "");
    // The account: 35 passes, 36 fails.
    var e: u8[>..] = [];
    statement_checks::fill('9', 35, e);
    var g: u8[>..] = [];
    statement_checks::stmt_with("R", e, g);
    assert(statement_checks::fk(g) == 0);
    var h: u8[>..] = [];
    statement_checks::fill('9', 36, h);
    var k: u8[>..] = [];
    statement_checks::stmt_with("R", h, k);
    statement_checks::expect_fields(k, 2, "25");
}

fn test_swift_charset() {
    // Letters of both cases and the marks of the manual pass.
    statement_checks::expect_fields(":20:Ab-1/2 (x)\n:25:A\n:28C:1/1\n:60F:C250101EUR1,00\n:62F:C250101EUR1,00\n", 0, "");
    // An ampersand and a byte above 127 are outside the set.
    statement_checks::expect_fields(":20:A&B\n:25:A\n:28C:1/1\n:60F:C250101EUR1,00\n:62F:C250101EUR1,00\n", 2, "20");
    statement_checks::expect_fields(":20:R\n:25:A\n:28C:1/1\n:60F:C250101EUR1,00\n:61:250102C1,00NTRFREF\n:86:caf\xc3\xa9\n:62F:C250101EUR2,00\n", 2, "86");
    // The rules off accept both.
    statement_checks::run_mt940(":20:A&B\n:25:A\n:28C:1/1\n:60F:C250101EUR1,00\n:62F:C250101EUR1,00\n", false, 0, "");
}

fn test_swift_numbers() {
    // A currency of two letters and a count of six digits are faults.
    statement_checks::expect_fields(":20:R\n:25:A\n:28C:1/1\n:60F:C250101EU1,00\n:62F:C250101EUR1,00\n", 2, "60F");
    statement_checks::expect_fields(":20:R\n:25:A\n:28C:123456/1\n:60F:C250101EUR1,00\n:62F:C250101EUR1,00\n", 2, "28C");
    statement_checks::expect_fields(":20:R\n:25:A\n:28C:1/1\n:34F:EUR0,\n:61:250102C1,00NTRFREF\n:90D:123456EUR1,00\n", 2, "90D");
    // An amount with 16 digits is too wide.
    statement_checks::expect_fields(":20:R\n:25:A\n:28C:1/1\n:60F:C250101EUR1234567890123456,\n:62F:C250101EUR1,00\n", 2, "60F");
}

fn test_swift_61() {
    let head = ":20:R\n:25:A\n:28C:1/1\n:60F:C250101EUR10,00\n";
    let tail = ":62F:C250101EUR11,00\n";
    var ok: u8[>..] = [];
    format(ok, head); format(ok, ":61:250102C1,00NTRF1234567890123456//1234567890123456\n");
    statement_checks::fill('S', 34, ok); format(ok, "\n"); format(ok, tail);
    assert(statement_checks::fk(ok) == 0);
    var long_cust: u8[>..] = [];
    format(long_cust, head); format(long_cust, ":61:250102C1,00NTRF12345678901234567\n"); format(long_cust, tail);
    statement_checks::expect_fields(long_cust, 2, "61");
    var long_bank: u8[>..] = [];
    format(long_bank, head); format(long_bank, ":61:250102C1,00NTRFA//12345678901234567\n"); format(long_bank, tail);
    statement_checks::expect_fields(long_bank, 2, "61");
    var long_sup: u8[>..] = [];
    format(long_sup, head); format(long_sup, ":61:250102C1,00NTRFA\n");
    statement_checks::fill('S', 35, long_sup); format(long_sup, "\n"); format(long_sup, tail);
    statement_checks::expect_fields(long_sup, 2, "61");
}

fn test_swift_86() {
    let head = ":20:R\n:25:A\n:28C:1/1\n:60F:C250101EUR10,00\n:61:250102C1,00NTRFREF\n:86:";
    let tail = ":62F:C250101EUR11,00\n";
    // Six lines of 65 pass. A seventh fails. A line of 66 fails.
    var six: u8[>..] = [];
    format(six, head);
    var i = 0;
    while i < 6 { statement_checks::fill('T', 65, six); format(six, "\n"); i += 1; }
    format(six, tail);
    assert(statement_checks::fk(six) == 0);
    var seven: u8[>..] = [];
    format(seven, head);
    i = 0;
    while i < 7 { statement_checks::fill('T', 65, seven); format(seven, "\n"); i += 1; }
    format(seven, tail);
    statement_checks::expect_fields(seven, 2, "86");
    var wide: u8[>..] = [];
    format(wide, head); statement_checks::fill('T', 66, wide); format(wide, "\n"); format(wide, tail);
    statement_checks::expect_fields(wide, 2, "86");
    // The same file parses with the rules off.
    statement_checks::run_mt940(seven, false, 0, "");
}

fn test_swift_order() {
    // :25: before :21: is out of order.
    statement_checks::expect_fields(":20:R\n:25:A\n:21:B\n:28C:1/1\n:60F:C250101EUR1,00\n:62F:C250101EUR1,00\n", 2, "21");
    // A statement without :25: or :28C: is a fault.
    statement_checks::expect_fields(":20:R\n:28C:1/1\n:60F:C250101EUR1,00\n:62F:C250101EUR1,00\n", 2, "28C");
    statement_checks::expect_fields(":20:R\n:25:A\n:60F:C250101EUR1,00\n:62F:C250101EUR1,00\n", 2, "60F");
    // An interim report with :34F: and :13D: before the opening balance passes.
    assert(statement_checks::fk(":20:I\n:25:A\n:28C:5/1\n:34F:EUR0,\n:13D:2501021530+0100\n:61:250102C500,00NTRFREF\n:90C:1EUR500,00\n") == 0);
    // :NS: may follow any tag.
    assert(statement_checks::fk(":20:R\n:25:A\n:NS:note\n:28C:1/1\n:60F:C250101EUR1,00\n:62F:C250101EUR1,00\n") == 0);
    // The options with the rules off accept the out-of-order file.
    statement_checks::run_mt940(":20:R\n:25:A\n:21:B\n:28C:1/1\n:60F:C250101EUR1,00\n:62F:C250101EUR1,00\n", false, 0, "");
}

fn test_swift_hostile() {
    // A huge :20: faults at once with the rules on.
    var big: u8[>..] = [];
    statement_checks::fill('A', 4000, big);
    var d: u8[>..] = [];
    statement_checks::stmt_with(big, "A", d);
    statement_checks::expect_fields(d, 2, "20");
    // 100000 lines in one :86: fault on the field size.
    var many: u8[>..] = [];
    format(many, ":20:R\n:25:A\n:28C:1/1\n:60F:C250101EUR1,00\n:61:250102C1,00NTRFREF\n:86:");
    var i = 0;
    while i < 100000 { format(many, "x\n"); i += 1; }
    format(many, ":62F:C250101EUR2,00\n");
    var rbuf3: u8[>..] = [];
    let f = statement_checks::fields_kind(many, rbuf3);
    assert(f.kind == 1 || f.kind == 2);
}
