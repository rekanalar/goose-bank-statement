// The MT940 and MT942 reader of the bank_statement package.
//
// parse_mt940 reads a file with one or many statements. The statements,
// the entries, the balances and the notes go into arrays that the caller
// owns. Every text field is a span over the input, so the input must
// outlive the arrays. One pass over the lines, no recursion.
//
// A statement starts at :20:. The tags are a closed set. A tag outside
// the set is a fault. A statement that is not an interim report must add
// up: the opening balance plus the entries must equal the closing
// balance. The option skip_balance_check turns that check off.
namespace bank_statement;

import std;
import fault;
import limits;
import amount;
import date;
import text;
import swift;
import qif;

// The styles of the :61: line. The manual limits the customer reference
// to 16 characters. ASN Bank sends up to 34. GLS and Atruvia send any
// length, and the bank reference holds up to 23.
const STYLE_SWIFT: i32 = 0;
const STYLE_ASNB: i32 = 1;
const STYLE_GLS: i32 = 2;

// The kinds of a balance.
const BAL_OPENING: i32 = 1;
const BAL_CLOSING: i32 = 2;
const BAL_AVAILABLE: i32 = 3;
const BAL_FORWARD: i32 = 4;

// Balance holds one balance line. The kind is zero for an absent balance.
// The intermediate flag is true for the tags :60M: and :62M:.
struct Balance {
    kind: i32,
    credit: bool,
    intermediate: bool,
    date: Date,
    amount: Amount,
    code: const u8[:],
}

// Entry holds one :61: line with the :86: that follows it. The mark is
// one of D, C, RD and RC. The funds code is zero when absent. The
// entry date has year 0 when absent. The narrative is the raw text of the
// :86: field, with its line ends. split_narrative reads it.
// OfxPayee holds the PAYEE aggregate of an OFX transaction.
struct OfxPayee {
    name: const u8[:],
    addr1: const u8[:],
    addr2: const u8[:],
    addr3: const u8[:],
    city: const u8[:],
    state: const u8[:],
    postal_code: const u8[:],
    country: const u8[:],
    phone: const u8[:],
}

// OfxAccount holds a BANKACCTTO or a CCACCTTO aggregate.
struct OfxAccount {
    bank_id: const u8[:],
    branch_id: const u8[:],
    acct_id: const u8[:],
    acct_type: const u8[:],
    acct_key: const u8[:],
}

// OfxImage holds the first IMAGEDATA aggregate of a transaction. The
// delay and the time to live count days. The fields has_delay and
// has_ttl tell whether the file holds them; the date has year 0 when
// absent.
struct OfxImage {
    kind: const u8[:],
    ref: const u8[:],
    ref_kind: const u8[:],
    delay: i64,
    has_delay: bool,
    avail: Date,
    ttl: i64,
    has_ttl: bool,
    check_sup: const u8[:],
}

// OfxEntry holds the OFX fields of a transaction that no other format
// has. The rate_kind is C for a CURRENCY aggregate, O for an ORIGCURRENCY
// aggregate and zero for none. The rate is exact; its text stays in
// rate_text.
struct OfxEntry {
    user_date: Date,
    correct_ref: const u8[:],
    correct_action: const u8[:],
    payee_id: const u8[:],
    ext_name: const u8[:],
    has_payee: bool,
    payee: OfxPayee,
    rate_kind: u8,
    rate: Rational,
    rate_text: const u8[:],
    rate_symbol: const u8[:],
    sic: i64,
    has_sic: bool,
    acct_to_kind: u8,
    acct_to: OfxAccount,
    inv401k_source: const u8[:],
    image: OfxImage,
    image_count: i64,
}

// no_ofx gives the OFX fields of an entry that has none.
fn no_ofx() -> OfxEntry {
    return OfxEntry {
        user_date: no_date(), correct_ref: "", correct_action: "", payee_id: "", ext_name: "",
        has_payee: false,
        payee: OfxPayee { name: "", addr1: "", addr2: "", addr3: "", city: "", state: "", postal_code: "", country: "", phone: "" },
        rate_kind: 0, rate: Rational { num: 0, den: 1 }, rate_text: "", rate_symbol: "",
        sic: 0, has_sic: false, acct_to_kind: 0,
        acct_to: OfxAccount { bank_id: "", branch_id: "", acct_id: "", acct_type: "", acct_key: "" },
        inv401k_source: "",
        image: OfxImage { kind: "", ref: "", ref_kind: "", delay: 0, has_delay: false, avail: no_date(), ttl: 0, has_ttl: false, check_sup: "" },
        image_count: 0,
    };
}

struct Entry {
    value_date: Date,
    entry_date: Date,
    mark: const u8[:],
    funds_code: u8,
    amount: Amount,
    type_id: const u8[:],
    customer_ref: const u8[:],
    bank_ref: const u8[:],
    supplementary: const u8[:],
    narrative: const u8[:],
    status: const u8[:],
    entry_ref: const u8[:],
    counter_name: const u8[:],
    counter_iban: const u8[:],
    remittance: const u8[:],
    batch_count: const u8[:],
    batch_msg_id: const u8[:],
    batch_pmt_id: const u8[:],
    batch_total: Amount,
    has_batch_total: bool,
    // The investment fields of an OFX entry. The rationals are exact;
    // their texts stay as given.
    units: Rational,
    has_units: bool,
    units_text: const u8[:],
    unit_price: Rational,
    has_unit_price: bool,
    unit_price_text: const u8[:],
    commission: Rational,
    has_commission: bool,
    commission_text: const u8[:],
    total: Rational,
    has_total: bool,
    total_text: const u8[:],
    ofx: OfxEntry,
}

// Note holds a statement level text: a :NS: field or a :86: that does
// not belong to an entry.
struct Note {
    tag: const u8[:],
    value: const u8[:],
}

// Statement holds one statement or one interim report. The entries,
// the balances and the notes are ranges of the arrays of the caller.
// The opening, the closing, the available and the forward balance are
// copies of the matching lines of the balance range. A balance the
// statement has none of holds kind 0. The floor limits, the report
// time and the totals belong to the interim report.
struct Statement {
    reference: const u8[:],
    related_ref: const u8[:],
    account: const u8[:],
    number: const u8[:],
    sequence: const u8[:],
    opening: Balance,
    closing: Balance,
    available: Balance,
    forward: Balance,
    entry_start: i32,
    entry_count: i32,
    balance_start: i32,
    balance_count: i32,
    note_start: i32,
    note_count: i32,
    is_interim: bool,
    balance_checked: bool,
    floor: Amount,
    floor_mark: u8,
    floor2: Amount,
    floor2_mark: u8,
    report_date: Date,
    report_minutes: i32,
    report_offset: i32,
    has_report_time: bool,
    debit_count: i64,
    debit_total: Amount,
    has_debit_total: bool,
    credit_count: i64,
    credit_total: Amount,
    has_credit_total: bool,
}

// Mt940Options holds the options of the reader. The zero value is the
// safe one: the balance check runs. The flag check_fields turns on the
// field rules of the SWIFT manual. It is off by default, because banks
// send fields that are longer than the manual allows. The value style
// picks the widths of the :61: line: STYLE_SWIFT (0, the manual),
// STYLE_ASNB (1) or STYLE_GLS (2).
struct Mt940Options {
    skip_balance_check: bool,
    check_fields: bool,
    style: i32,
}

// State is the working state of one parse. The open statement is the
// element cur of the statement array. The last field holds the code of
// the tag that came before, for the order machine. State holds no span,
// because the compiler refuses a span in a local that the caller's array
// outlives.
struct State {
    cur: i64,
    open: bool,
    last: i32,
}

// is_tag_char tells the characters that a tag holds.
fn is_tag_char(c: u8) -> bool { return is_digit(c) || is_upper(c); }

// tag_of tests whether the line opens a field. It gives the tag, the
// offset of the value, and true when the line starts with :TAG: and the
// tag is two to four upper case letters or digits.
fn tag_of(line: const u8[:]) -> const u8[:], i64, bool {
    if line.len < 4 || line[0] != ':' { return "", 0, false; }
    var i = 1;
    while i < line.len && i < 6 {
        if line[i] == ':' {
            if i < 3 { return "", 0, false; }
            return line[1..i], i + 1, true;
        }
        if !is_tag_char(line[i]) { return "", 0, false; }
        i += 1;
    }
    return "", 0, false;
}

fn known_tag(t: const u8[:]) -> bool {
    let tags = ["20", "21", "25", "28", "28C", "34F", "13D", "60F", "60M", "61", "62F", "62M", "64", "65", "86", "90D", "90C", "NS"];
    for k in tags { if t == k { return true; } }
    return false;
}

// first_line gives the part of the text before the first line end.
fn first_line(s: const u8[:]) -> const u8[:], const u8[:] {
    var i = 0;
    while i < s.len && s[i] != '\n' { i += 1; }
    let head = trim_cr(s[..i]);
    if i < s.len { return head, s[i + 1..]; }
    return head, s[s.len..];
}

fn no_balance() -> Balance {
    return Balance { kind: 0, credit: false, intermediate: false, date: no_date(), amount: Amount { minor: 0, exp: 2, currency: "" }, code: "" };
}

fn new_statement() -> Statement {
    let z = Amount { minor: 0, exp: 2, currency: "" };
    return Statement {
        reference: "", related_ref: "", account: "", number: "", sequence: "",
        opening: no_balance(), closing: no_balance(),
        available: no_balance(), forward: no_balance(),
        entry_start: 0, entry_count: 0, balance_start: 0, balance_count: 0, note_start: 0, note_count: 0,
        is_interim: false, balance_checked: false,
        floor: z, floor_mark: 0, floor2: z, floor2_mark: 0,
        report_date: no_date(), report_minutes: 0, report_offset: 0, has_report_time: false,
        debit_count: 0, debit_total: z, has_debit_total: false,
        credit_count: 0, credit_total: z, has_credit_total: false,
    };
}

// parse_balance reads the value of :60F:, :60M:, :62F:, :62M:, :64: and
// :65:. The shape is C or D, six digits, three letters and an amount.
// The check flag turns on the width of the amount.
fn parse_balance(value: const u8[:], kind: i32, intermediate: bool, line_no: i64, tag: const u8[:], check: bool) -> Balance, Fault {
    var b = no_balance();
    let v = trim(value);
    if v.len < 11 { return b, fault(F_SYNTAX, line_no, 1, tag, "balance is too short"); }
    if v[0] != 'C' && v[0] != 'D' { return b, fault(F_SYNTAX, line_no, 1, tag, "balance mark is not C or D"); }
    let d, ok = date_yymmdd(v[1..7]);
    if !ok { return b, fault(F_DATE, line_no, 2, tag, "balance date is not a date"); }
    let cur = v[7..10];
    if !is_letters(cur) { return b, fault(F_SYNTAX, line_no, 8, tag, "currency is not three letters"); }
    if check {
        let f = check_amount(tag, v[10..], line_no);
        if f.kind != F_NONE { return b, f; }
    }
    let a, f = parse_amount(v[10..], currency_exponent(cur), ',', 0);
    if f.kind != F_NONE { return b, with_pos(f, line_no, tag); }
    b.kind = kind;
    b.credit = v[0] == 'C';
    b.intermediate = intermediate;
    b.date = d;
    b.amount = Amount { minor: a.minor, exp: a.exp, currency: cur };
    return b, no_fault();
}

// lim_unbounded is the width of a field that has no width in the manual.
fn lim_unbounded() -> i64 { return 9223372036854775807; }

// near_year gives the year of the entry date. An entry date belongs to the
// year of the value date, unless it lies more than six months away.
fn near_year(vy: i64, vm: i64, em: i64) -> i64 {
    if em + 6 < vm { return vy + 1; }
    if em > vm + 6 { return vy - 1; }
    return vy;
}

// parse_entry reads the value of a :61: field. The check flag turns on
// the widths of the parts of the line.
fn parse_entry(value: const u8[:], cur: const u8[:], line_no: i64, check: bool, style: i32) -> Entry, Fault {
    var e = Entry {
        value_date: no_date(), entry_date: no_date(), mark: "", funds_code: 0,
        amount: Amount { minor: 0, exp: 2, currency: cur },
        type_id: "", customer_ref: "", bank_ref: "", supplementary: "", narrative: "",
        status: "", entry_ref: "", counter_name: "", counter_iban: "", remittance: "",
        batch_count: "", batch_msg_id: "", batch_pmt_id: "",
        batch_total: Amount { minor: 0, exp: 2, currency: "" }, has_batch_total: false,
        units: Rational { num: 0, den: 1 }, has_units: false, units_text: "",
        unit_price: Rational { num: 0, den: 1 }, has_unit_price: false, unit_price_text: "",
        commission: Rational { num: 0, den: 1 }, has_commission: false, commission_text: "",
        total: Rational { num: 0, den: 1 }, has_total: false, total_text: "", ofx: no_ofx(),
    };
    let head, rest = first_line(value);
    let tag: const u8[:] = "61";
    if head.len < 12 { return e, fault(F_SYNTAX, line_no, 1, tag, "entry line is too short"); }
    let vd, ok = date_yymmdd(head[0..6]);
    if !ok { return e, fault(F_DATE, line_no, 1, tag, "value date is not a date"); }
    e.value_date = vd;
    var i = 6;
    // The entry date is four digits: month and day.
    if i + 4 <= head.len && is_digit(head[i]) {
        let em, a = digits(head[i..i + 2]);
        let ed, b = digits(head[i + 2..i + 4]);
        if !a || !b { return e, fault(F_DATE, line_no, i + 1, tag, "entry date is not a date"); }
        let d, good = make_date(near_year(vd.year, vd.month, em), em, ed);
        if !good { return e, fault(F_DATE, line_no, i + 1, tag, "entry date is not a date"); }
        e.entry_date = d;
        i += 4;
    }
    // The mark: D, C, RD or RC.
    if i < head.len && head[i] == 'R' {
        if i + 1 >= head.len || (head[i + 1] != 'C' && head[i + 1] != 'D') { return e, fault(F_SYNTAX, line_no, i + 1, tag, "mark is not D, C, RD or RC"); }
        e.mark = head[i..i + 2];
        i += 2;
    } else if i < head.len && (head[i] == 'C' || head[i] == 'D') {
        e.mark = head[i..i + 1];
        i += 1;
    } else {
        return e, fault(F_SYNTAX, line_no, i + 1, tag, "mark is not D, C, RD or RC");
    }
    // The funds code is one letter before the amount.
    if i + 1 < head.len && is_upper(head[i]) && is_digit(head[i + 1]) {
        e.funds_code = head[i];
        i += 1;
    }
    // The amount: digits and one comma.
    let astart = i;
    while i < head.len && (is_digit(head[i]) || head[i] == ',') { i += 1; }
    if i == astart { return e, fault(F_AMOUNT, line_no, astart + 1, tag, "entry has no amount"); }
    if check {
        let f = check_amount(tag, head[astart..i], line_no);
        if f.kind != F_NONE { return e, f; }
    }
    let a, f = parse_amount(head[astart..i], currency_exponent(cur), ',', 0);
    if f.kind != F_NONE { return e, with_pos(f, line_no, tag); }
    e.amount = Amount { minor: a.minor, exp: a.exp, currency: cur };
    // The transaction type: S, N or F and three characters.
    if i + 4 > head.len || (head[i] != 'S' && head[i] != 'N' && head[i] != 'F') {
        return e, fault(F_SYNTAX, line_no, i + 1, tag, "transaction type is missing");
    }
    e.type_id = head[i..i + 4];
    i += 4;
    // The customer reference runs to the // or to the end of the line.
    let tail = head[i..];
    let sep = find(tail, "//");
    if sep >= 0 {
        e.customer_ref = tail[..sep];
        e.bank_ref = tail[sep + 2..];
    } else {
        e.customer_ref = tail;
    }
    e.supplementary = trim(rest);
    if check {
        var cmax = SW_CUSTOMER_REF;
        var bmax = SW_BANK_REF;
        if style == STYLE_ASNB { cmax = 34; }
        if style == STYLE_GLS { cmax = lim_unbounded(); bmax = 23; }
        let f = check_width(tag, e.customer_ref, line_no, cmax);
        if f.kind != F_NONE { return e, f; }
        let g = check_width(tag, e.bank_ref, line_no, bmax);
        if g.kind != F_NONE { return e, g; }
        if style != STYLE_GLS {
            let h = check_width(tag, e.supplementary, line_no, SW_SUPPLEMENTARY);
            if h.kind != F_NONE { return e, h; }
        }
    }
    return e, no_fault();
}

// signed_effect gives +1 or -1: the way an entry moves the balance.
fn signed_effect(mark: const u8[:]) -> i64 {
    if mark == "C" || mark == "RD" { return 1; }
    return -1;
}

fn bal_sign(b: Balance&) -> i64 {
    if b.credit { return 1; }
    return -1;
}

// add_checked adds two numbers and gives false on overflow.
fn add_checked(a: i64, b: i64) -> i64, bool {
    if b > 0 && a > 9223372036854775807 - b { return 0, false; }
    if b < 0 && a < -9223372036854775807 - b { return 0, false; }
    return a + b, true;
}

// finalize checks the statement and pushes it.
// check_totals checks the totals of a statement against its entries. The
// debit total counts the debit entries and the credit total counts the
// credit entries. The tags name the two totals in a fault.
fn check_totals(st: Statement&, entries: Entry[>..]&, line_no: i64, tag_d: const u8[:], tag_c: const u8[:]) -> Fault {
    if !st.has_debit_total && !st.has_credit_total { return no_fault(); }
    var dn: i64 = 0;
    var cn: i64 = 0;
    var dsum: i64 = 0;
    var csum: i64 = 0;
    var k = 0;
    while k < st.entry_count {
        let e = entries[st.entry_start + k];
        // Debit entries are D and RC. Credit entries are C and RD.
        if signed_effect(e.mark) < 0 {
            dn += 1;
            let s, ok = add_checked(dsum, e.amount.minor);
            if !ok { return fault(F_OVERFLOW, line_no, 1, tag_d, "sum of entries does not fit in 64 bits"); }
            dsum = s;
        } else {
            cn += 1;
            let s, ok = add_checked(csum, e.amount.minor);
            if !ok { return fault(F_OVERFLOW, line_no, 1, tag_c, "sum of entries does not fit in 64 bits"); }
            csum = s;
        }
        k += 1;
    }
    if st.has_debit_total && (st.debit_count != dn || st.debit_total.minor != dsum) {
        return fault(F_TOTAL, line_no, 1, tag_d, "debit total differs from the entries");
    }
    if st.has_credit_total && (st.credit_count != cn || st.credit_total.minor != csum) {
        return fault(F_TOTAL, line_no, 1, tag_c, "credit total differs from the entries");
    }
    // A total holds the currency of the statement.
    var cur = st.opening.amount.currency;
    if cur.len == 0 { cur = st.floor.currency; }
    if cur.len > 0 {
        if st.has_debit_total && st.debit_total.currency != cur {
            return fault(F_TOTAL, line_no, 1, tag_d, "debit total holds another currency");
        }
        if st.has_credit_total && st.credit_total.currency != cur {
            return fault(F_TOTAL, line_no, 1, tag_c, "credit total holds another currency");
        }
    }
    return no_fault();
}

fn finalize(S: State&, lim: Limits&, opts: Mt940Options&, line_no: i64, statements: Statement[>..]&, entries: Entry[>..]&) -> Fault {
    let st = statements[S.cur];
    // The manual requires :25: and :28C: in every statement.
    if opts.check_fields {
        if st.account.len == 0 { return fault(F_SYNTAX, line_no, 1, "25", "statement has no account"); }
        if st.number.len == 0 { return fault(F_SYNTAX, line_no, 1, "28C", "statement has no statement number"); }
    }
    // The check runs whenever both balances are present. An interim flag
    // (:34F: or :13D:) must not switch it off, or a forged line would.
    // Only a report with no balances at all goes without the check.
    let both = st.opening.kind != 0 && st.closing.kind != 0;
    if !opts.skip_balance_check && (both || !st.is_interim) {
        if st.opening.kind == 0 { return fault(F_BALANCE, line_no, 1, "60F", "statement has no opening balance"); }
        if st.closing.kind == 0 { return fault(F_BALANCE, line_no, 1, "62F", "statement has no closing balance"); }
        if st.opening.amount.currency != st.closing.amount.currency {
            return fault(F_BALANCE, line_no, 1, "62F", "opening and closing balance differ in currency");
        }
        var sum = st.opening.amount.minor * bal_sign(st.opening);
        var k = 0;
        while k < st.entry_count {
            let e = entries[st.entry_start + k];
            let step, ok = add_checked(sum, e.amount.minor * signed_effect(e.mark));
            if !ok { return fault(F_OVERFLOW, line_no, 1, "61", "sum of entries does not fit in 64 bits"); }
            sum = step;
            k += 1;
        }
        statements[S.cur].balance_checked = true;
        let want = st.closing.amount.minor * bal_sign(st.closing);
        if sum != want {
            return fault_sums(F_BALANCE, line_no, "62F", "opening balance plus entries differs from the closing balance", sum, want);
        }
    }
    // The totals of an interim report must match the entries.
    let tf = check_totals(st, entries, line_no, "90D", "90C");
    if tf.kind != F_NONE { return tf; }
    S.open = false;
    return no_fault();
}

// parse_floor reads a :34F: value: a currency, an optional D or C, and
// an amount. The check flag turns on the width of the amount.
fn parse_floor(value: const u8[:], line_no: i64, check: bool) -> Amount, u8, Fault {
    let v = trim(value);
    let z = Amount { minor: 0, exp: 2, currency: "" };
    if v.len < 4 || !is_letters(v[0..3]) { return z, 0, fault(F_SYNTAX, line_no, 1, "34F", "floor limit needs a currency"); }
    var mark: u8 = 0;
    var i = 3;
    if v[3] == 'D' || v[3] == 'C' { mark = v[3]; i = 4; }
    if check {
        let f = check_amount("34F", v[i..], line_no);
        if f.kind != F_NONE { return z, 0, f; }
    }
    let a, f = parse_amount(v[i..], currency_exponent(v[0..3]), ',', 0);
    if f.kind != F_NONE { return z, 0, with_pos(f, line_no, "34F"); }
    return Amount { minor: a.minor, exp: a.exp, currency: v[0..3] }, mark, no_fault();
}

// parse_report_time reads a :13D: value: YYMMDDHHMM, a sign and HHMM.
fn parse_report_time(value: const u8[:], S: State&, line_no: i64, statements: Statement[>..]&) -> Fault {
    let v = trim(value);
    let tag: const u8[:] = "13D";
    if v.len != 15 || (v[10] != '+' && v[10] != '-') { return fault(F_SYNTAX, line_no, 1, tag, "date and time is not YYMMDDHHMM+HHMM"); }
    let d, ok = date_yymmdd(v[0..6]);
    let hh, a = digits(v[6..8]);
    let mm, b = digits(v[8..10]);
    let oh, c = digits(v[11..13]);
    let om, e = digits(v[13..15]);
    if !ok { return fault(F_DATE, line_no, 1, tag, "report date is not a date"); }
    if !a || !b || !c || !e || hh > 23 || mm > 59 || oh > 23 || om > 59 {
        return fault(F_DATE, line_no, 7, tag, "report time is not a time");
    }
    statements[S.cur].report_date = d;
    statements[S.cur].report_minutes = (hh * 60 + mm) as i32;
    var off = oh * 60 + om;
    if v[10] == '-' { off = -off; }
    statements[S.cur].report_offset = off as i32;
    statements[S.cur].has_report_time = true;
    statements[S.cur].is_interim = true;
    return no_fault();
}

// parse_total reads a :90D: or :90C: value: a count, a currency and an
// amount. The check flag turns on the widths of the count and of the
// amount.
fn parse_total(value: const u8[:], tag: const u8[:], line_no: i64, check: bool) -> i64, Amount, Fault {
    let v = trim(value);
    let z = Amount { minor: 0, exp: 2, currency: "" };
    var i = 0;
    while i < v.len && is_digit(v[i]) { i += 1; }
    let n, ok = digits(v[..i]);
    if !ok || i + 4 > v.len || !is_letters(v[i..i + 3]) { return 0, z, fault(F_SYNTAX, line_no, 1, tag, "total is not count, currency and amount"); }
    let cur = v[i..i + 3];
    if check {
        let f = check_digits(tag, v[..i], line_no, SW_COUNT);
        if f.kind != F_NONE { return 0, z, f; }
        let g = check_amount(tag, v[i + 3..], line_no);
        if g.kind != F_NONE { return 0, z, g; }
    }
    let a, f = parse_amount(v[i + 3..], currency_exponent(cur), ',', 0);
    if f.kind != F_NONE { return 0, z, with_pos(f, line_no, tag); }
    return n, Amount { minor: a.minor, exp: a.exp, currency: cur }, no_fault();
}

fn push_balance(S: State&, b: Balance, lim: Limits&, line_no: i64, tag: const u8[:], statements: Statement[>..]&, balances: Balance[>..]&) -> Fault {
    if balances.len >= lim.max_fields { return fault(F_LIMIT, line_no, 1, tag, "more balances than max_fields"); }
    balances.push(b);
    statements[S.cur].balance_count += 1;
    return no_fault();
}

fn push_note(S: State&, tag: const u8[:], value: const u8[:], lim: Limits&, line_no: i64, statements: Statement[>..]&, notes: Note[>..]&) -> Fault {
    if notes.len >= lim.max_fields { return fault(F_LIMIT, line_no, 1, tag, "more notes than max_fields"); }
    notes.push(Note { tag: tag, value: value });
    statements[S.cur].note_count += 1;
    return no_fault();
}

// check_field_rules applies the field rules of the SWIFT manual to one
// field. It checks the order of the tags and the width of the text
// fields. The amounts and the parts of a statement line are checked
// where the reader reads them.
fn check_field_rules(tag: const u8[:], value: const u8[:], line_no: i64, S: State&) -> Fault {
    // A statement starts at :20:. The tag before it belongs to the
    // statement before, so the order does not matter there.
    if tag != "20" {
        if !tag_allowed(S.last, tag_code(tag)) {
            return fault(F_SYNTAX, line_no, 1, tag, "the tag may not follow the tag of the field before it");
        }
    }
    if tag == "20" || tag == "21" || tag == "25" || tag == "86" {
        let cf = check_charset(tag, value, line_no);
        if cf.kind != F_NONE { return cf; }
    }
    if tag == "20" || tag == "21" { return check_width(tag, trim(value), line_no, SW_REF); }
    if tag == "25" { return check_width(tag, trim(value), line_no, SW_ACCOUNT); }
    if tag == "28" || tag == "28C" { return check_statement_number(tag, trim(value), line_no); }
    if tag == "86" { return check_86(tag, value, line_no); }
    return no_fault();
}

// handle_field applies one complete field to the working state.
fn handle_field(tag: const u8[:], value: const u8[:], line_no: i64, S: State&, lim: Limits&, opts: Mt940Options&,
                statements: Statement[>..]&, entries: Entry[>..]&, balances: Balance[>..]&, notes: Note[>..]&) -> Fault {
    if !known_tag(tag) { return fault(F_UNKNOWN_TAG, line_no, 1, tag, "tag is not part of MT940 or MT942"); }
    if value.len > lim.max_field { return fault(F_LIMIT, line_no, 1, tag, "field is longer than max_field"); }
    if opts.check_fields {
        let f = check_field_rules(tag, value, line_no, S);
        if f.kind != F_NONE { return f; }
    }
    // A :NS: field leaves the order state as it was.
    if tag != "NS" { S.last = tag_code(tag); }
    if tag == "20" {
        if S.open {
            let f = finalize(S, lim, opts, line_no, statements, entries);
            if f.kind != F_NONE { return f; }
        }
        if statements.len >= lim.max_statements { return fault(F_LIMIT, line_no, 1, tag, "more statements than max_statements"); }
        statements.push(new_statement());
        S.cur = statements.len - 1;
        statements[S.cur].reference = trim(value);
        statements[S.cur].entry_start = entries.len as i32;
        statements[S.cur].balance_start = balances.len as i32;
        statements[S.cur].note_start = notes.len as i32;
        S.open = true;
        return no_fault();
    }
    if !S.open { return fault(F_SYNTAX, line_no, 1, tag, "field before :20:"); }
    if tag == "21" { statements[S.cur].related_ref = trim(value); return no_fault(); }
    if tag == "25" { statements[S.cur].account = trim(value); return no_fault(); }
    if tag == "28" || tag == "28C" {
        let v = trim(value);
        let slash = find(v, "/");
        if slash >= 0 { statements[S.cur].number = v[..slash]; statements[S.cur].sequence = v[slash + 1..]; } else { statements[S.cur].number = v; }
        return no_fault();
    }
    if tag == "NS" { return push_note(S, tag, trim(value), lim, line_no, statements, notes); }
    if tag == "60F" || tag == "60M" {
        if statements[S.cur].opening.kind != 0 { return fault(F_SYNTAX, line_no, 1, tag, "second opening balance"); }
        let b, f = parse_balance(value, BAL_OPENING, tag == "60M", line_no, tag, opts.check_fields);
        if f.kind != F_NONE { return f; }
        statements[S.cur].opening = b;
        return push_balance(S, b, lim, line_no, tag, statements, balances);
    }
    if tag == "62F" || tag == "62M" {
        if statements[S.cur].closing.kind != 0 { return fault(F_SYNTAX, line_no, 1, tag, "second closing balance"); }
        let b, f = parse_balance(value, BAL_CLOSING, tag == "62M", line_no, tag, opts.check_fields);
        if f.kind != F_NONE { return f; }
        statements[S.cur].closing = b;
        return push_balance(S, b, lim, line_no, tag, statements, balances);
    }
    if tag == "64" || tag == "65" {
        var kind = BAL_AVAILABLE;
        if tag == "65" { kind = BAL_FORWARD; }
        let b, f = parse_balance(value, kind, false, line_no, tag, opts.check_fields);
        if f.kind != F_NONE { return f; }
        if tag == "64" {
            if statements[S.cur].available.kind != 0 { return fault(F_SYNTAX, line_no, 1, tag, "second closing available balance"); }
            statements[S.cur].available = b;
        } else {
            // A second forward balance replaces the first.
            statements[S.cur].forward = b;
        }
        return push_balance(S, b, lim, line_no, tag, statements, balances);
    }
    if tag == "61" {
        if statements[S.cur].closing.kind != 0 { return fault(F_SYNTAX, line_no, 1, tag, "entry after the closing balance"); }
        if entries.len >= lim.max_entries { return fault(F_LIMIT, line_no, 1, tag, "more entries than max_entries"); }
        // The entry has no currency of its own. It takes the one of the
        // opening balance, or of the floor limit of an interim report.
        var cur = statements[S.cur].opening.amount.currency;
        if cur.len == 0 { cur = statements[S.cur].floor.currency; }
        if cur.len == 0 { return fault(F_SYNTAX, line_no, 1, tag, "entry has no currency: put :60F: or :34F: before it"); }
        let e, f = parse_entry(value, cur, line_no, opts.check_fields, opts.style);
        if f.kind != F_NONE { return f; }
        entries.push(e);
        statements[S.cur].entry_count += 1;
        return no_fault();
    }
    if tag == "86" {
        if statements[S.cur].entry_count > 0 && statements[S.cur].closing.kind == 0 {
            let last = entries.len - 1;
            if entries[last].narrative.len > 0 { return fault(F_SYNTAX, line_no, 1, tag, "second :86: for one entry"); }
            entries[last].narrative = value;
            return no_fault();
        }
        return push_note(S, tag, trim(value), lim, line_no, statements, notes);
    }
    if tag == "34F" {
        if statements[S.cur].floor_mark != 0 && statements[S.cur].floor2_mark != 0 { return fault(F_SYNTAX, line_no, 1, tag, "third floor limit"); }
        let a, m, f = parse_floor(value, line_no, opts.check_fields);
        if f.kind != F_NONE { return f; }
        statements[S.cur].is_interim = true;
        if statements[S.cur].floor.currency.len == 0 { statements[S.cur].floor = a; statements[S.cur].floor_mark = m; if m == 0 { statements[S.cur].floor_mark = '-'; } }
        else { statements[S.cur].floor2 = a; statements[S.cur].floor2_mark = m; if m == 0 { statements[S.cur].floor2_mark = '-'; } }
        return no_fault();
    }
    if tag == "13D" { return parse_report_time(value, S, line_no, statements); }
    if tag == "90D" || tag == "90C" {
        let n, a, f = parse_total(value, tag, line_no, opts.check_fields);
        if f.kind != F_NONE { return f; }
        if tag == "90D" {
            if statements[S.cur].has_debit_total { return fault(F_SYNTAX, line_no, 1, tag, "second debit total"); }
            statements[S.cur].debit_count = n; statements[S.cur].debit_total = a; statements[S.cur].has_debit_total = true;
        } else {
            if statements[S.cur].has_credit_total { return fault(F_SYNTAX, line_no, 1, tag, "second credit total"); }
            statements[S.cur].credit_count = n; statements[S.cur].credit_total = a; statements[S.cur].has_credit_total = true;
        }
        return no_fault();
    }
    return fault(F_UNKNOWN_TAG, line_no, 1, tag, "tag is not part of MT940 or MT942");
}

// skip_group gives the position after the brace group that starts at
// start. It gives -1 for an unbalanced group and -2 for a group nested
// deeper than max_depth.
fn skip_group(line: const u8[:], start: i64, max_depth: i64) -> i64 {
    var depth: i64 = 0;
    var i = start;
    while i < line.len {
        let c = line[i];
        if c == '{' {
            depth += 1;
            if depth > max_depth { return -2; }
        } else if c == '}' {
            depth -= 1;
            if depth == 0 { return i + 1; }
        }
        i += 1;
    }
    return -1;
}

// read_blocks reads the blocks {1:} to {3:} and {5:} of a header line.
// It gives the offset after "{4:", or -1 when the line has no block 4.
fn read_blocks(line: const u8[:], max_depth: i64) -> i64, Fault {
    var i = 0;
    while i < line.len && line[i] == '{' {
        if i + 3 > line.len || !is_digit(line[i + 1]) || line[i + 2] != ':' {
            return -1, fault(F_SYNTAX, 0, i + 1, "", "block header is not {N:");
        }
        if line[i + 1] == '4' { return i + 3, no_fault(); }
        let j = skip_group(line, i, max_depth);
        if j == -2 { return -1, fault(F_LIMIT, 0, i + 1, "", "blocks are nested deeper than max_depth"); }
        if j < 0 { return -1, fault(F_SYNTAX, 0, i + 1, "", "block is not closed on its line"); }
        i = j;
    }
    if i < line.len { return -1, fault(F_SYNTAX, 0, i + 1, "", "text after the block header"); }
    return -1, no_fault();
}

// parse_mt940 reads a file of MT940 or MT942 statements. The arrays of the
// caller receive the statements, the entries, the balances and the notes.
fn parse_mt940(input: const u8[:], lim: Limits&, opts: Mt940Options&,
               statements: Statement[>..]&, entries: Entry[>..]&, balances: Balance[>..]&, notes: Note[>..]&) -> Fault {
    let fi = check_input(input, lim);
    if fi.kind != F_NONE { return fi; }
    if opts.style < STYLE_SWIFT || opts.style > STYLE_GLS { return fault(F_SYNTAX, 0, 0, "61", "the style is not a style of the package"); }
    var S = State { cur: 0, open: false, last: T_NONE };
    var pos = skip_bom(input);
    var line_no: i64 = 0;
    var have = false;
    var tstart: i64 = 0;
    var tend: i64 = 0;
    var fstart: i64 = 0;
    var fend: i64 = 0;
    var fline: i64 = 0;
    while pos < input.len {
        let e, bad = line_end(input, pos, lim.max_line);
        line_no += 1;
        if bad != 0 { return line_fault(bad, line_no, 1); }
        let line = trim_cr(input[pos..e]);
        let tg, voff, is_tag = tag_of(line);
        // kind: 0 blank, 1 continuation, 2 tag, 3 terminator, 4 block header
        var kind = 1;
        if line.len == 0 { kind = 0; }
        else if is_tag { kind = 2; }
        else if line[0] == '{' { kind = 4; }
        else if line[0] == '-' && (line.len == 1 || line[1] == '}') { kind = 3; }
        else if line[0] == '}' && line.len == 1 { kind = 3; }
        if kind >= 2 && have {
            let f = handle_field(input[tstart..tend], input[fstart..fend], fline, S, lim, opts, statements, entries, balances, notes);
            if f.kind != F_NONE { return f; }
            have = false;
        }
        if kind == 1 {
            if !have { return fault(F_SYNTAX, line_no, 1, "", "text outside a field"); }
            fend = pos + line.len;
        } else if kind == 2 {
            have = true;
            tstart = pos + 1;
            tend = pos + voff - 1;
            fstart = pos + voff;
            fend = pos + line.len;
            fline = line_no;
        } else if kind == 3 {
            if line.len > 2 {
                let rest = line[2..];
                if !starts_with(rest, "{5:") || skip_group(rest, 0, lim.max_depth) != rest.len {
                    return fault(F_SYNTAX, line_no, 3, "", "text after the end of block 4");
                }
            }
            if S.open {
                let f = finalize(S, lim, opts, line_no, statements, entries);
                if f.kind != F_NONE { return f; }
            }
        } else if kind == 4 {
            if S.open {
                let f = finalize(S, lim, opts, line_no, statements, entries);
                if f.kind != F_NONE { return f; }
            }
            let rest, fb = read_blocks(line, lim.max_depth);
            if fb.kind != F_NONE { return with_pos(fb, line_no, ""); }
            if rest >= 0 && rest < line.len {
                let tg2, voff2, ok2 = tag_of(line[rest..]);
                if !ok2 { return fault(F_SYNTAX, line_no, rest + 1, "", "text after the block 4 header"); }
                have = true;
                tstart = pos + rest + 1;
                tend = pos + rest + voff2 - 1;
                fstart = pos + rest + voff2;
                fend = pos + line.len;
                fline = line_no;
            }
        }
        pos = e + 1;
    }
    if have {
        let f = handle_field(input[tstart..tend], input[fstart..fend], fline, S, lim, opts, statements, entries, balances, notes);
        if f.kind != F_NONE { return f; }
    }
    if S.open {
        let f = finalize(S, lim, opts, line_no, statements, entries);
        if f.kind != F_NONE { return f; }
    }
    return no_fault();
}

// NarrativeField holds one part of a structured :86: narrative.
struct NarrativeField {
    key: const u8[:],
    value: const u8[:],
}

const NARR_PLAIN: i32 = 0;
const NARR_SUBFIELD: i32 = 1;
const NARR_PAIRS: i32 = 2;

// pair_key_len gives the length of the key of a /KEY/ at i, or 0. A key
// is two to four upper case letters.
fn pair_key_len(s: const u8[:], i: i64) -> i64 {
    if i >= s.len || s[i] != '/' { return 0; }
    var n = 0;
    while i + 1 + n < s.len && is_upper(s[i + 1 + n]) && n < 5 { n += 1; }
    if n < 2 || n > 4 || i + 1 + n >= s.len || s[i + 1 + n] != '/' { return 0; }
    return n;
}

// subfield_at tests for ?NN at i.
fn subfield_at(s: const u8[:], i: i64) -> bool {
    return i + 2 < s.len && s[i] == '?' && is_digit(s[i + 1]) && is_digit(s[i + 2]);
}

// split_narrative splits the text of a :86: into parts. German banks write
// a business code and ?NN subfields. Other banks write /KEY/value/ pairs.
// Text of neither form comes back whole as NARR_PLAIN, with no part.
// A line end inside a value stays in the value.
fn split_narrative(raw: const u8[:], lim: Limits&, out: NarrativeField[>..]&) -> i32, Fault {
    let s = trim(raw);
    if pair_key_len(s, 0) > 0 {
        var i: i64 = 0;
        while i < s.len {
            let kl = pair_key_len(s, i);
            if kl == 0 { return NARR_PAIRS, fault(F_SYNTAX, 0, i + 1, "86", "text outside a /KEY/ pair"); }
            let vstart = i + 2 + kl;
            var p = vstart;
            while p < s.len && pair_key_len(s, p) == 0 { p += 1; }
            var value = s[vstart..p];
            if p == s.len && value.len > 0 && value[value.len - 1] == '/' { value = value[..value.len - 1]; }
            if out.len >= lim.max_fields { return NARR_PAIRS, fault(F_LIMIT, 0, i + 1, "86", "more parts than max_fields"); }
            out.push(NarrativeField { key: s[i + 1..i + 1 + kl], value: value });
            i = p;
        }
        return NARR_PAIRS, no_fault();
    }
    var q: i64 = 0;
    while q < s.len && !subfield_at(s, q) { q += 1; }
    if q < s.len && q <= 4 {
        if q > 0 { out.push(NarrativeField { key: "code", value: s[..q] }); }
        var i = q;
        while i < s.len {
            var j = i + 3;
            while j < s.len && !subfield_at(s, j) { j += 1; }
            if out.len >= lim.max_fields { return NARR_SUBFIELD, fault(F_LIMIT, 0, i + 1, "86", "more parts than max_fields"); }
            out.push(NarrativeField { key: s[i + 1..i + 3], value: s[i + 3..j] });
            i = j;
        }
        return NARR_SUBFIELD, no_fault();
    }
    return NARR_PLAIN, no_fault();
}
