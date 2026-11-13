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

// parse_mt940_decoded reads a file of MT940 or MT942 statements. The
// arrays of the caller receive the statements, the entries, the
// balances and the notes.
fn parse_mt940_decoded(input: const u8[:], lim: Limits&, opts: Mt940Options&,
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

// parse_mt940 reads a file of MT940 or MT942 statements. When the
// option names a charset, the input is decoded into UTF-8 first, and
// the decoded text lives in buf. The text must outlive the statements.
fn parse_mt940(input: const u8[:], lim: Limits&, opts: Mt940Options&,
               statements: Statement[>..]&, entries: Entry[>..]&, balances: Balance[>..]&, notes: Note[>..]&,
               buf: u8[>..]&) -> Fault {
    if opts.charset != 0 {
        let mark = buf.len;
        let f = decode_charset(opts.charset, input, lim, buf);
        if f.kind != F_NONE { return f; }
        return parse_mt940_decoded(buf[mark..], lim, opts, statements, entries, balances, notes);
    }
    return parse_mt940_decoded(input, lim, opts, statements, entries, balances, notes);
}
