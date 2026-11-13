// The state machine of the MT940 parser.
//
namespace bank_statement;

import std;
import fault;
import limits;
import amount;
import date;
import text;
import swift;
import qif;

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

// OfxImage holds one IMAGEDATA aggregate of a transaction. The
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
    image2: OfxImage,
    image_count: i64,
}

fn no_image() -> OfxImage {
    return OfxImage { kind: "", ref: "", ref_kind: "", delay: 0, has_delay: false, avail: no_date(), ttl: 0, has_ttl: false, check_sup: "" };
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
        image: no_image(), image2: no_image(),
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
    // The camt fields of the statement container. The period is the
    // FrToDt element, the flag is the CpyDplctInd element, and the two
    // texts are the RptgSeq element.
    period_from: Date,
    period_to: Date,
    has_period: bool,
    copy_duplicate: const u8[:],
    reporting_from: const u8[:],
    reporting_to: const u8[:],
    reporting_source: const u8[:],
    page_number: const u8[:],
    last_page: bool,
    all_count: i64,
    all_total: Amount,
    has_all_total: bool,
    net_amount: Amount,
    has_net: bool,
    net_credit: bool,
    credit_card: bool,
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
    // The charset to decode first: 0 keeps the bytes, CS_CP1252 and
    // CS_LATIN1 decode into UTF-8.
    charset: i32 = 0,
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
        period_from: no_date(), period_to: no_date(), has_period: false,
        copy_duplicate: "", reporting_from: "", reporting_to: "",
        reporting_source: "", page_number: "", last_page: false,
        all_count: 0, all_total: z, has_all_total: false,
        net_amount: z, has_net: false, net_credit: false,
        credit_card: false,
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
