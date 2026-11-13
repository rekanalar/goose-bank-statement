// The OFX reader of the bank_statement package.
//
// parse_ofx reads an OFX 1.x or OFX 2.x file: the header, the tag tree
// and the statement message sets. The bank and credit card statements
// and the investment statements come back as the shared Statement and
// Entry values. The signon status comes back as a note.
//
// The amounts are exact integer counts of minor units. A comma is a
// decimal separator only when the text holds no dot. A date of the
// form YYYYMMDD[HHMMSS[.XXX]][[+H.MM[:TZ]]] parses with the minutes
// reading of the dotted offset: [-5.30] is 5 hours 30 minutes, as
// ofxtools and the real bank files read it. No zone means GMT.
namespace bank_statement;

import std;
import fault;
import text;
import limits;
import amount;
import currency;
import date;
import qif;
import mt940;
import sgml;

// OfxOptions holds the options of the reader. The zero value is the
// safe one: the pending list is read.
// is_invtran tells whether a name is one of the investment transaction
// aggregates.
fn is_invtran(name: const u8[:]) -> bool {
    if ieq(name, "INVBANKTRAN") { return true; }
    if ieq(name, "BUYSTOCK") || ieq(name, "SELLSTOCK") { return true; }
    if ieq(name, "BUYMF") || ieq(name, "SELLMF") { return true; }
    if ieq(name, "BUYOPT") || ieq(name, "SELLOPT") { return true; }
    if ieq(name, "BUYDEBT") || ieq(name, "SELLDEBT") { return true; }
    if ieq(name, "BUYOTHER") || ieq(name, "SELLOTHER") { return true; }
    if ieq(name, "INCOME") || ieq(name, "REINVEST") || ieq(name, "RETOFCAP") { return true; }
    if ieq(name, "SPLIT") || ieq(name, "TRANSFER") { return true; }
    if ieq(name, "JRNLFUND") || ieq(name, "JRNLSEC") { return true; }
    if ieq(name, "MARGININTEREST") || ieq(name, "INVEXPENSE") || ieq(name, "CLOSUREOPT") { return true; }
    return false;
}

// is_pos tells whether a name is one of the position aggregates.
fn is_pos(name: const u8[:]) -> bool {
    return ieq(name, "POSSTOCK") || ieq(name, "POSMF") || ieq(name, "POSOPT")
        || ieq(name, "POSDEBT") || ieq(name, "POSOTHER");
}

// ofx_invtran reads one investment transaction aggregate into an entry.
// The type text names the kind. The money fields go into the rationals
// of the entry; TOTAL is the amount.
fn ofx_invtran(nodes: SgmlNode[>..]&, id: i32, kind: const u8[:], ccy: const u8[:],
               lim: Limits&, entries: Entry[>..]&, buf: u8[>..]&, cur: i64) -> Fault {
    if entries.len >= lim.max_entries { return fault(F_LIMIT, 0, 0, kind, "more entries than max_entries"); }
    var e = new_entry(ccy);
    // The type text: the kind, plus the income kind or the action.
    {
        let start = buf.len;
        for u in kind { buf.push(u); }
        let inc = sgml_child(nodes, id, "INCOMETYPE");
        if inc >= 0 {
            buf.push('/');
            sgml_text_of(nodes, inc, buf);
        }
        e.type_id = buf[start..];
    }
    // INVTRAN holds the references and the dates. It sits in the
    // aggregate, or in its INVBUY or INVSELL child as the specification
    // orders it.
    var it = sgml_child(nodes, id, "INVTRAN");
    if it < 0 { it = ofx_money_child(nodes, id, "INVBUY", "INVTRAN"); }
    if it < 0 { it = ofx_money_child(nodes, id, "INVSELL", "INVTRAN"); }
    if it >= 0 {
        let fit = sgml_child(nodes, it, "FITID");
        if fit >= 0 { e.entry_ref = sgml_text_of(nodes, fit, buf); }
        let srv = sgml_child(nodes, it, "SRVRTID");
        if srv >= 0 { e.bank_ref = sgml_text_of(nodes, srv, buf); }
        let memo = sgml_child(nodes, it, "MEMO");
        if memo >= 0 { e.narrative = sgml_text_of(nodes, memo, buf); }
        let dt = sgml_child(nodes, it, "DTTRADE");
        if dt >= 0 {
            let v = sgml_text_of(nodes, dt, buf);
            let d, ok = ofx_date(v);
            if !ok { return fault(F_DATE, 0, 0, "DTTRADE", "the date is not OFX form"); }
            e.value_date = d;
        }
        let ds = sgml_child(nodes, it, "DTSETTLE");
        if ds >= 0 {
            let v = sgml_text_of(nodes, ds, buf);
            let d, ok = ofx_date(v);
            if ok { e.entry_date = d; }
        }
    }
    // TOTAL is the amount of the entry. INVBANKTRAN holds a STMTTRN
    // instead.
    if ieq(kind, "INVBANKTRAN") {
        let st = sgml_child(nodes, id, "STMTTRN");
        if st >= 0 {
            let f = ofx_stmttrn(nodes, st, ccy, lim, entries, buf, cur);
            if f.kind != F_NONE { return f; }
            entries[entries.len - 1].type_id = "INVBANKTRAN";
            return no_fault();
        }
    } else {
        // The total sits in the aggregate or in its INVBUY or INVSELL
        // child.
        var tot = sgml_child(nodes, id, "TOTAL");
        if tot < 0 { tot = ofx_money_child(nodes, id, "INVBUY", "TOTAL"); }
        if tot < 0 { tot = ofx_money_child(nodes, id, "INVSELL", "TOTAL"); }
        if tot >= 0 {
            let v = sgml_text_of(nodes, tot, buf);
            let r, f = ofx_ratio(v);
            if f.kind != F_NONE { return with_tag(f, "TOTAL"); }
            e.total = r;
            e.has_total = true;
            e.total_text = v;
            // The sign of the text is the mark.
            if v.len > 0 && v[0] == '-' { e.mark = "D"; } else { e.mark = "C"; }
            // The amount takes the total when it fits the currency.
            let a, af = parse_amount(v, currency_exponent(ccy), '.', 0);
            if af.kind == F_NONE { e.amount = a; }
        }
    }
    // The money fields of the trade.
    let m, mf = ofx_money(nodes, id, buf);
    if mf.kind != F_NONE { return mf; }
    e.units = m.units;
    e.has_units = m.has_units;
    e.units_text = m.units_text;
    e.unit_price = m.unit_price;
    e.has_unit_price = m.has_unit_price;
    e.unit_price_text = m.unit_price_text;
    e.commission = m.commission;
    e.has_commission = m.has_commission;
    e.commission_text = m.commission_text;
    entries.push(e);
    return no_fault();
}

// OfxMoney holds the money fields of an investment transaction. The
// rationals are exact; the texts stay as given.
struct OfxMoney {
    units: Rational,
    has_units: bool,
    units_text: const u8[:],
    unit_price: Rational,
    has_unit_price: bool,
    unit_price_text: const u8[:],
    commission: Rational,
    has_commission: bool,
    commission_text: const u8[:],
}

// ofx_money reads UNITS, UNITPRICE and COMMISSION of a transaction.
// The fields sit in the aggregate or in its INVBUY or INVSELL child.
fn ofx_money(nodes: SgmlNode[>..]&, id: i32, buf: u8[>..]&) -> OfxMoney, Fault {
    var m = OfxMoney {
        units: Rational { num: 0, den: 1 }, has_units: false, units_text: "",
        unit_price: Rational { num: 0, den: 1 }, has_unit_price: false, unit_price_text: "",
        commission: Rational { num: 0, den: 1 }, has_commission: false, commission_text: "",
    };
    var un = sgml_child(nodes, id, "UNITS");
    if un < 0 { un = ofx_money_child(nodes, id, "INVBUY", "UNITS"); }
    if un < 0 { un = ofx_money_child(nodes, id, "INVSELL", "UNITS"); }
    if un >= 0 {
        let v = sgml_text_of(nodes, un, buf);
        let r, f = ofx_ratio(v);
        if f.kind != F_NONE { return m, with_tag(f, "UNITS"); }
        m.units = r;
        m.has_units = true;
        m.units_text = v;
    }
    var up = sgml_child(nodes, id, "UNITPRICE");
    if up < 0 { up = ofx_money_child(nodes, id, "INVBUY", "UNITPRICE"); }
    if up < 0 { up = ofx_money_child(nodes, id, "INVSELL", "UNITPRICE"); }
    if up >= 0 {
        let v = sgml_text_of(nodes, up, buf);
        let r, f = ofx_ratio(v);
        if f.kind != F_NONE { return m, with_tag(f, "UNITPRICE"); }
        m.unit_price = r;
        m.has_unit_price = true;
        m.unit_price_text = v;
    }
    var co = sgml_child(nodes, id, "COMMISSION");
    if co < 0 { co = ofx_money_child(nodes, id, "INVBUY", "COMMISSION"); }
    if co < 0 { co = ofx_money_child(nodes, id, "INVSELL", "COMMISSION"); }
    if co >= 0 {
        let v = sgml_text_of(nodes, co, buf);
        let r, f = ofx_ratio(v);
        if f.kind != F_NONE { return m, with_tag(f, "COMMISSION"); }
        m.commission = r;
        m.has_commission = true;
        m.commission_text = v;
    }
    return m, no_fault();
}

// ofx_money_child gives the child element with the name in the child
// aggregate of the node, or -1.
fn ofx_money_child(nodes: SgmlNode[>..]&, id: i32, agg: const u8[:], name: const u8[:]) -> i32 {
    let a = sgml_child(nodes, id, agg);
    if a < 0 { return -1; }
    return sgml_child(nodes, a, name);
}

// ofx_pos reads one position aggregate into an entry whose type text
// names the position kind. The market value is the amount.
fn ofx_pos(nodes: SgmlNode[>..]&, id: i32, kind: const u8[:], ccy: const u8[:],
           lim: Limits&, entries: Entry[>..]&, balances: Balance[>..]&, buf: u8[>..]&, cur: i64) -> Fault {
    if entries.len >= lim.max_entries { return fault(F_LIMIT, 0, 0, kind, "more entries than max_entries"); }
    var e = new_entry(ccy);
    e.type_id = kind;
    e.mark = "C";
    let inv = sgml_child(nodes, id, "INVPOS");
    if inv < 0 { return fault(F_SYNTAX, 0, 0, kind, "the position has no INVPOS"); }
    let sec = sgml_child(nodes, inv, "SECID");
    if sec >= 0 {
        let uid = sgml_child(nodes, sec, "UNIQUEID");
        if uid >= 0 { e.customer_ref = sgml_text_of(nodes, uid, buf); }
    }
    let dt = sgml_child(nodes, inv, "DTPRICEASOF");
    if dt >= 0 {
        let v = sgml_text_of(nodes, dt, buf);
        let d, mins, off, ok = ofx_datetime(v);
        if ok {
            let _ = mins;
            let _ = off;
            e.value_date = d;
        }
    }
    let mv = sgml_child(nodes, inv, "MKTVAL");
    if mv >= 0 {
        let v = sgml_text_of(nodes, mv, buf);
        let r, f = ofx_ratio(v);
        if f.kind != F_NONE { return with_tag(f, "MKTVAL"); }
        e.total = r;
        e.has_total = true;
        e.total_text = v;
        if v.len > 0 && v[0] == '-' { e.mark = "D"; } else { e.mark = "C"; }
        // The amount takes the value when it fits the currency.
        let a, af = parse_amount(v, currency_exponent(ccy), '.', 0);
        if af.kind == F_NONE { e.amount = a; }
    }
    let m, mf = ofx_money(nodes, inv, buf);
    if mf.kind != F_NONE { return mf; }
    e.units = m.units;
    e.has_units = m.has_units;
    e.units_text = m.units_text;
    e.unit_price = m.unit_price;
    e.has_unit_price = m.has_unit_price;
    e.unit_price_text = m.unit_price_text;
    e.commission = m.commission;
    e.has_commission = m.has_commission;
    e.commission_text = m.commission_text;
    entries.push(e);
    let _ = balances;
    return no_fault();
}

// with_tag puts a new tag into a fault.
fn with_tag(f: Fault, tag: const u8[:]) -> Fault {
    return Fault { kind: f.kind, line: f.line, col: f.col, tag: tag, detail: f.detail, have: f.have, want: f.want };
}

// ofx_amount_of reads one amount element. The exponent comes from the
// currency. A comma is a decimal separator only when no dot is there.
fn ofx_amount_of(nodes: SgmlNode[>..]&, id: i32, tag: const u8[:], ccy: const u8[:], buf: u8[>..]&) -> Amount, Fault {
    let v = sgml_text_of(nodes, id, buf);
    if v.len == 0 { return Amount { minor: 0, exp: 2, currency: "" }, fault(F_AMOUNT, 0, 0, tag, "the amount is empty"); }
    var dec: u8 = '.';
    if find_byte(v, ',') >= 0 && find_byte(v, '.') < 0 { dec = ','; }
    let a, f = parse_amount(v, currency_exponent(ccy), dec, 0);
    if f.kind != F_NONE { return a, f; }
    // The parser gives no currency; the statement gives it.
    var out = a;
    out.currency = ccy;
    return out, no_fault();
}

// ofx_ratio reads an exact rational. It reuses the parser of the QIF
// side and names the tag of the caller.
fn ofx_ratio(v: const u8[:]) -> Rational, Fault {
    var dec: u8 = '.';
    if find_byte(v, ',') >= 0 && find_byte(v, '.') < 0 { dec = ','; }
    return parse_ratio(v, dec, 0, 0, 'I');
}

// find_byte gives the first place of a byte, or -1.
fn find_byte(s: const u8[:], c: u8) -> i64 {
    var i: i64 = 0;
    while i < s.len {
        if s[i] == c { return i; }
        i += 1;
    }
    return -1;
}
// ofx_date reads a date of OFX form and gives the date.
fn ofx_date(s: const u8[:]) -> Date, bool {
    let d, mins, off, ok = ofx_datetime(s);
    if !ok { return no_date(), false; }
    let _ = mins;
    let _ = off;
    return d, true;
}

// ofx_datetime reads a date and time of OFX form:
// YYYYMMDD[HHMM[SS[.XXX]]][[+H[.MM|HHMM][:TZ]]]. The dotted offset
// reads as hours and minutes: [-5.30] is 5 hours 30 minutes. No zone
// means GMT. It gives the date, the minutes of the day and the offset
// in minutes.
fn ofx_datetime(s: const u8[:]) -> Date, i32, i32, bool {
    if s.len < 8 { return no_date(), 0, 0, false; }
    let y, a = digits(s[0..4]);
    let m, b = digits(s[4..6]);
    let d, c = digits(s[6..8]);
    if !a || !b || !c { return no_date(), 0, 0, false; }
    let dt, ok = make_date(y, m, d);
    if !ok { return no_date(), 0, 0, false; }
    var mins: i32 = 0;
    var i: i64 = 8;
    // The time: HHMM, HHMMSS or HHMMSS.XXX.
    if i + 2 <= s.len && is_digit(s[i]) {
        let hh, ok2 = digits(s[i..i + 2]);
        if !ok2 || hh > 23 { return no_date(), 0, 0, false; }
        mins = (hh * 60) as i32;
        i += 2;
        if i + 2 <= s.len && is_digit(s[i]) {
            let mm, ok3 = digits(s[i..i + 2]);
            if !ok3 || mm > 59 { return no_date(), 0, 0, false; }
            mins += mm as i32;
            i += 2;
            if i + 2 <= s.len && is_digit(s[i]) {
                let ss, ok4 = digits(s[i..i + 2]);
                if !ok4 || ss > 60 { return no_date(), 0, 0, false; }
                let _ = ss;
                i += 2;
                if i < s.len && s[i] == '.' {
                    i += 1;
                    while i < s.len && is_digit(s[i]) { i += 1; }
                }
            }
        }
    }
    // The zone: [offset] or [offset:TZ] or [:TZ]. The offset is a
    // signed hour count with optional minutes after a dot, or two
    // more digits.
    var off: i32 = 0;
    if i < s.len {
        if s[i] != '[' { return no_date(), 0, 0, false; }
        let close = find_byte(s[i..], ']');
        if close < 0 { return no_date(), 0, 0, false; }
        let zone = s[i + 1..i + close];
        i = i + close + 1;
        var zi: i64 = 0;
        var sign: i32 = 1;
        if zi < zone.len && (zone[zi] == '+' || zone[zi] == '-') {
            if zone[zi] == '-' { sign = -1; }
            zi += 1;
        }
        var oh: i64 = -1;
        var om: i64 = 0;
        if zi < zone.len && is_digit(zone[zi]) {
            var zs = zi;
            while zs < zone.len && is_digit(zone[zs]) { zs += 1; }
            let n, okz = digits(zone[zi..zs]);
            if !okz { return no_date(), 0, 0, false; }
            oh = n;
            zi = zs;
            if zi < zone.len && zone[zi] == '.' {
                zi += 1;
                let ms = zi;
                while zi < zone.len && is_digit(zone[zi]) { zi += 1; }
                // One or two digits are minutes; more are hundredths
                // of an hour of the form .XXX. The minutes reading
                // wins for the two digit form.
                let fl = zi - ms;
                if fl == 1 || fl == 2 {
                    let mm, okm = digits(zone[ms..zi]);
                    if !okm || mm > 59 { return no_date(), 0, 0, false; }
                    om = mm;
                } else if fl == 3 {
                    let mm, okm = digits(zone[ms..ms + 2]);
                    if !okm || mm > 59 { return no_date(), 0, 0, false; }
                    om = mm;
                } else {
                    return no_date(), 0, 0, false;
                }
            } else if zi + 2 <= zone.len && is_digit(zone[zi]) && is_digit(zone[zi + 1]) {
                let mm, okm = digits(zone[zi..zi + 2]);
                if !okm || mm > 59 { return no_date(), 0, 0, false; }
                om = mm;
                zi += 2;
            }
            if oh > 14 { return no_date(), 0, 0, false; }
            off = sign * ((oh * 60 + om) as i32);
        } else {
            // No hours: the zone name must say the offset.
            let nm, okn = zone_name(zone);
            if !okn { return no_date(), 0, 0, false; }
            off = nm;
        }
        // A zone name after the offset is read and dropped. The
        // offset says the time already.
    }
    if i != s.len { return no_date(), 0, 0, false; }
    return dt, mins, off, true;
}

// zone_name gives the offset of a zone name of the table that the
// references hold, in minutes. An unknown name is refused.
fn zone_name(name: const u8[:]) -> i32, bool {
    if ieq(name, "EST") { return -5 * 60, true; }
    if ieq(name, "EDT") { return -4 * 60, true; }
    if ieq(name, "CST") { return -6 * 60, true; }
    if ieq(name, "CDT") { return -5 * 60, true; }
    if ieq(name, "MST") { return -7 * 60, true; }
    if ieq(name, "MDT") { return -6 * 60, true; }
    if ieq(name, "PST") { return -8 * 60, true; }
    if ieq(name, "PDT") { return -7 * 60, true; }
    if ieq(name, "GMT") || ieq(name, "UTC") { return 0, true; }
    return 0, false;
}

// parse_ofx reads an OFX 1.x or 2.x file. When the header names a
// legacy charset, the body is decoded first, unless the option turns
// the decode off.
fn parse_ofx(input: const u8[:], lim: Limits&, opts: OfxOptions&,
             statements: Statement[>..]&, entries: Entry[>..]&, balances: Balance[>..]&,
             notes: Note[>..]&, buf: u8[>..]&) -> Fault {
    if opts.auto_charset {
        let cs = header_charset(input);
        if cs != 0 {
            let mark = buf.len;
            let f = decode_charset(cs, input, lim, buf);
            if f.kind != F_NONE { return f; }
            return parse_ofx_decoded(buf[mark..], lim, opts, statements, entries, balances, notes, buf);
        }
    }
    return parse_ofx_decoded(input, lim, opts, statements, entries, balances, notes, buf);

}
