// The ISO 20022 external return reason codes.
//
// The table holds the codes and the names of the Python library
// camt053: 41 codes, sorted by code, and the action policy of that
// library, sorted too. A policy names the action for a code: "return",
// "retry" or "ignore". A code that no policy names means "return".
// Edit the library and generate the tables again, never by hand.
namespace bank_statement;

const REASON_CODES: const u8[:][] = [
    "AC01", "AC02", "AC03", "AC04", "AC06", "AC13", "AC14", "AG01", "AG02", "AM01",
    "AM02", "AM03", "AM04", "AM05", "AM06", "AM07", "AM08", "AM09", "BE01", "BE05",
    "CNOR", "DNOR", "DT01", "ED01", "ED05", "FF01", "MD01", "MD06", "MD07", "MS02",
    "MS03", "NARR", "NOAS", "NOOR", "RC01", "RR01", "RR02", "RR03", "RR04", "SL01",
    "TM01",
];

const REASON_NAMES: const u8[:][] = [
    "Incorrect Account Number",
    "Invalid Debtor Account Number",
    "Invalid Creditor Account Number",
    "Closed Account Number",
    "Blocked Account",
    "Invalid Debtor Account Type",
    "Invalid Creditor Account Type",
    "Transaction Forbidden",
    "Invalid Bank Operation Code",
    "Zero Amount",
    "Not Allowed Amount",
    "Not Allowed Currency",
    "Insufficient Funds",
    "Duplication",
    "Too Low Amount",
    "Blocked Amount",
    "Non Settled Amount",
    "Wrong Amount",
    "Inconsistent With End Customer",
    "Unrecognised Initiating Party",
    "Creditor Bank Is Not Registered",
    "Debtor Bank Is Not Registered",
    "Invalid Date",
    "Correspondent Bank Not Possible",
    "Settlement Failed",
    "Invalid File Format",
    "No Mandate",
    "Refund Request By End Customer",
    "End Customer Deceased",
    "Not Specified Reason Customer Generated",
    "Not Specified Reason Agent Generated",
    "Narrative",
    "No Answer From Customer",
    "No Original Transaction Received",
    "Bank Identifier Incorrect",
    "Missing Debtor Account Or Identification",
    "Missing Debtor Name Or Address",
    "Missing Creditor Name Or Address",
    "Regulatory Reason",
    "Specific Service Offered By Debtor Agent",
    "Cut Off Time",
];

const REASON_POLICY_CODES: const u8[:][] = [
    "AC01", "AC02", "AC03", "AC04", "AC06", "AC13", "AC14", "AG01", "AM04", "AM05",
    "AM07", "ED05", "MS02", "MS03", "NARR", "TM01",
];

const REASON_POLICY_ACTIONS: const u8[:][] = [
    "return",
    "return",
    "return",
    "return",
    "return",
    "return",
    "return",
    "return",
    "retry",
    "retry",
    "retry",
    "retry",
    "ignore",
    "ignore",
    "ignore",
    "retry",
];

// find_reason looks a code up in the table with a binary search. The
// codes are sorted. It gives -1 when no code matches.
fn find_reason(code: const u8[:]) -> i64 {
    var lo: i64 = 0;
    var hi: i64 = REASON_CODES.len as i64;
    while lo < hi {
        let mid = (lo + hi) / 2;
        let c = compare_bytes(code, REASON_CODES[mid]);
        if c == 0 { return mid; }
        if c < 0 { hi = mid; } else { lo = mid + 1; }
    }
    return -1;
}

// upper_code gives the capital form of a code in the buffer. A code
// longer than four letters is no code of the table.
fn upper_code(code: const u8[:], buf: u8[>..]&) -> const u8[:], bool {
    if code.len != 4 { return "", false; }
    let start = buf.len;
    for c in code {
        if c >= 'a' && c <= 'z' { buf.push(c - 32); } else { buf.push(c); }
    }
    return buf[start..], true;
}

// reason_known tells whether a code is a reason code of the table. The
// match takes any letter case.
fn reason_known(code: const u8[:], buf: u8[>..]&) -> bool {
    let up, ok = upper_code(code, buf);
    if !ok { return false; }
    return find_reason(up) >= 0;
}

// reason_name gives the name of a reason code. A code that the table
// holds not gives the text of the reference: "Unknown reason code".
fn reason_name(code: const u8[:], buf: u8[>..]&) -> const u8[:] {
    let up, ok = upper_code(code, buf);
    if !ok { return "Unknown reason code"; }
    let at = find_reason(up);
    if at < 0 { return "Unknown reason code"; }
    return REASON_NAMES[at];
}

// reason_action gives the action that the policy names for a code:
// "return", "retry" or "ignore". A code that the policy holds not means
// "return". The match takes any letter case.
fn reason_action(code: const u8[:], buf: u8[>..]&) -> const u8[:] {
    let up, ok = upper_code(code, buf);
    if !ok { return "return"; }
    var lo: i64 = 0;
    var hi: i64 = REASON_POLICY_CODES.len as i64;
    while lo < hi {
        let mid = (lo + hi) / 2;
        let c = compare_bytes(up, REASON_POLICY_CODES[mid]);
        if c == 0 { return REASON_POLICY_ACTIONS[mid]; }
        if c < 0 { hi = mid; } else { lo = mid + 1; }
    }
    return "return";
}

// reverse_mark gives the opposite credit or debit mark. It takes the
// long form CRDT and DBIT and the short form C and D. An unknown mark
// is false.
fn reverse_mark(mark: const u8[:]) -> const u8[:], bool {
    if mark.len == 1 {
        if mark[0] == 'C' { return "D", true; }
        if mark[0] == 'D' { return "C", true; }
        return "", false;
    }
    if compare_bytes(mark, "CRDT") == 0 { return "DBIT", true; }
    if compare_bytes(mark, "DBIT") == 0 { return "CRDT", true; }
    return "", false;
}

// reversal_of gives the reversing entry of one entry. The mark and the
// sign of the amount turn around, and so do the signs of the total and
// the batch total when the entry holds one. Everything else stays. An
// entry with an unknown mark gives no reversal.
fn reversal_of(e: Entry) -> Entry, bool {
    let mark, ok = reverse_mark(e.mark);
    if !ok { return e, false; }
    var r = e;
    r.mark = mark;
    if r.amount.minor != -9223372036854775808 {
        r.amount.minor = -r.amount.minor;
    } else {
        return e, false;
    }
    if r.has_batch_total && r.batch_total.minor != -9223372036854775808 {
        r.batch_total.minor = -r.batch_total.minor;
    }
    if r.has_total && r.total.num != -9223372036854775808 {
        r.total.num = -r.total.num;
    }
    return r, true;
}
