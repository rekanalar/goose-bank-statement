// The security list of an OFX file.
//
// parse_ofx_securities reads the SECLIST of an investment file: the
// aggregates STOCKINFO, MFINFO, DEBTINFO, OPTINFO and OTHERINFO. Each
// gives an OfxSecurity with the fields of its SECINFO. Every other leaf
// of the aggregate comes back as a note, so no value is lost. The price
// is an exact rational. The reader uses no float.
namespace bank_statement;

import std;
import fault;
import text;
import limits;
import amount;
import date;
import qif;
import mt940;
import sgml;
import ofx;
import write_text;
import ofx_write;
import ofx_tree;

// OfxSecurity holds one security. The kind is the name of the
// aggregate, in capitals. The notes of the security are a range of the
// array of notes that the caller owns.
struct OfxSecurity {
    kind: const u8[:],
    id: const u8[:],
    id_type: const u8[:],
    name: const u8[:],
    ticker: const u8[:],
    fiid: const u8[:],
    rating: const u8[:],
    memo: const u8[:],
    currency: const u8[:],
    has_price: bool,
    price: Rational,
    price_text: const u8[:],
    price_date: Date,
    note_start: i32,
    note_count: i32,
}

fn is_secinfo_kind(n: const u8[:]) -> bool {
    return ieq(n, "STOCKINFO") || ieq(n, "MFINFO") || ieq(n, "DEBTINFO") || ieq(n, "OPTINFO") || ieq(n, "OTHERINFO");
}

// sec_note copies the name and the text of a leaf into the buffer and
// adds a note.
fn sec_note(nodes: SgmlNode[>..]&, j: i32, lim: Limits&, notes: Note[>..]&, buf: u8[>..]&, s: OfxSecurity&) -> Fault {
    if notes.len >= lim.max_fields { return fault(F_LIMIT, 0, 0, "", "more fields than max_fields"); }
    let start = buf.len;
    for u in nodes[j].name { buf.push(u); }
    let tag = buf[start..];
    let v = sgml_text_of(nodes, j, buf);
    notes.push(Note { tag: tag, value: v });
    s.note_count += 1;
    return no_fault();
}

// ofx_security reads one security aggregate.
fn ofx_security(nodes: SgmlNode[>..]&, id: i32, lim: Limits&, notes: Note[>..]&, buf: u8[>..]&) -> OfxSecurity, Fault {
    var s = OfxSecurity {
        kind: "", id: "", id_type: "", name: "", ticker: "", fiid: "", rating: "", memo: "", currency: "",
        has_price: false, price: Rational { num: 0, den: 1 }, price_text: "", price_date: no_date(),
        note_start: notes.len as i32, note_count: 0,
    };
    let ks = buf.len;
    for u in nodes[id].name {
        if u >= 'a' && u <= 'z' { buf.push(u - 32); } else { buf.push(u); }
    }
    s.kind = buf[ks..];
    let d = nodes[id].depth;
    var sec_depth: i32 = -1;
    var j = id + 1;
    while j < nodes.len && nodes[j].depth > d {
        let n = nodes[j];
        if sec_depth >= 0 && n.depth <= sec_depth { sec_depth = -1; }
        if !n.leaf {
            if ieq(n.name, "SECINFO") { sec_depth = n.depth; }
            j += 1;
            continue;
        }
        var done = false;
        if sec_depth >= 0 {
            // Each field is read once; a repeat goes to the notes.
            if ieq(n.name, "UNIQUEID") && s.id.len == 0 { s.id = sgml_text_of(nodes, j, buf); done = true; }
            else if ieq(n.name, "UNIQUEIDTYPE") && s.id_type.len == 0 { s.id_type = sgml_text_of(nodes, j, buf); done = true; }
            else if ieq(n.name, "SECNAME") && s.name.len == 0 { s.name = sgml_text_of(nodes, j, buf); done = true; }
            else if ieq(n.name, "TICKER") && s.ticker.len == 0 { s.ticker = sgml_text_of(nodes, j, buf); done = true; }
            else if ieq(n.name, "FIID") && s.fiid.len == 0 { s.fiid = sgml_text_of(nodes, j, buf); done = true; }
            else if ieq(n.name, "RATING") && s.rating.len == 0 { s.rating = sgml_text_of(nodes, j, buf); done = true; }
            else if ieq(n.name, "MEMO") && s.memo.len == 0 { s.memo = sgml_text_of(nodes, j, buf); done = true; }
            else if ieq(n.name, "CURSYM") && s.currency.len == 0 { s.currency = sgml_text_of(nodes, j, buf); done = true; }
            else if ieq(n.name, "UNITPRICE") && !s.has_price {
                let v = sgml_text_of(nodes, j, buf);
                let r, rf = ofx_ratio(v);
                if rf.kind != F_NONE { return s, with_tag(rf, "UNITPRICE"); }
                s.price = r;
                s.has_price = true;
                s.price_text = v;
                done = true;
            } else if ieq(n.name, "DTASOF") && s.price_date.year == 0 {
                let v = sgml_text_of(nodes, j, buf);
                let dt, ok = ofx_date(v);
                if !ok { return s, fault(F_DATE, 0, 0, "DTASOF", "the date is not OFX form"); }
                s.price_date = dt;
                done = true;
            }
        }
        if !done {
            let f = sec_note(nodes, j, lim, notes, buf, s);
            if f.kind != F_NONE { return s, f; }
        }
        j += 1;
    }
    return s, no_fault();
}

// parse_ofx_securities reads the security list of an OFX file. A file
// without a list gives no security and no fault.
fn parse_ofx_securities_decoded(input: const u8[:], lim: Limits&, securities: OfxSecurity[>..]&,
                        notes: Note[>..]&, buf: u8[>..]&) -> Fault {
    let fi = check_input(input, lim);
    if fi.kind != F_NONE { return fi; }
    let h, body, hf = parse_sgml_header(input);
    if hf.kind != F_NONE { return hf; }
    let _ = h;
    var nodes: SgmlNode[>..] = [];
    let bf = parse_sgml_body(input, body, lim, nodes, buf);
    if bf.kind != F_NONE { return bf; }
    if nodes.len == 0 || nodes[0].depth != 0 || !ieq(nodes[0].name, "OFX") {
        return fault(F_SYNTAX, 0, 0, "OFX", "the root element is not OFX");
    }
    let ms = sgml_child(nodes, 0, "SECLISTMSGSRSV1");
    if ms < 0 { return no_fault(); }
    var l = sgml_child(nodes, ms, "SECLIST");
    while l >= 0 {
        var c = first_child(nodes, l);
        while c >= 0 {
            if is_secinfo_kind(nodes[c].name) {
                if securities.len >= lim.max_records { return fault(F_LIMIT, 0, 0, "", "more records than max_records"); }
                let s, f = ofx_security(nodes, c, lim, notes, buf);
                if f.kind != F_NONE { return f; }
                securities.push(s);
            }
            c = sgml_next(nodes, c);
        }
        // A second SECLIST in the same set is read too.
        l = sgml_next(nodes, l);
        while l >= 0 && !ieq(nodes[l].name, "SECLIST") { l = sgml_next(nodes, l); }
    }
    return no_fault();
}

// ---- the writer ----

// pow10_small gives 10 to the power of k, with k of at most 10.
fn pow10_small(k: i64) -> i64 {
    var v: i64 = 1;
    var i: i64 = 0;
    while i < k { v = v * 10; i += 1; }
    return v;
}

// sec_price_text builds the exact decimal text of a price. A
// denominator with a factor other than 2 or 5, or a price with more
// than ten decimals, is a fault. The text lands in buf.
fn sec_price_text(r: Rational, buf: u8[>..]&, tag: const u8[:]) -> const u8[:], Fault {
    var d = r.den;
    var a: i64 = 0;
    var b: i64 = 0;
    while d % 2 == 0 { d = d / 2; a += 1; }
    while d % 5 == 0 { d = d / 5; b += 1; }
    if d != 1 { return "", fault(F_AMOUNT, 0, 0, tag, "the price has no finite decimal form"); }
    var k = a;
    if b > k { k = b; }
    if k > 10 { return "", fault(F_AMOUNT, 0, 0, tag, "the price needs more than ten decimals"); }
    var m: i64 = 1;
    var i: i64 = 0;
    while i < k - a { m = m * 2; i += 1; }
    i = 0;
    while i < k - b { m = m * 5; i += 1; }
    var n = r.num;
    var neg = false;
    if n < 0 { neg = true; n = -n; }
    if n != 0 && m > 9223372036854775807 / n {
        return "", fault(F_AMOUNT, 0, 0, tag, "the price is too large to write");
    }
    let scaled = n * m;
    let p = pow10_small(k);
    let whole = scaled / p;
    let frac = scaled % p;
    let start = buf.len;
    if neg { buf.push('-'); }
    put_num(buf, whole, 1);
    if k > 0 {
        buf.push('.');
        var f = frac;
        var digits: i64 = 0;
        var div = p / 10;
        while digits < k {
            buf.push((f / div) as u8 + '0');
            f = f % div;
            div = div / 10;
            digits += 1;
        }
    }
    return buf[start..], no_fault();
}

// sec_opt_leaf writes a leaf when the text is not empty. The length
// limit comes from the rule table of the specification.
fn sec_opt_leaf(out: u8[>..]&, w: OfxForm, tag: const u8[:], value: const u8[:], max: i64,
                depth: i64, lim: Limits&) -> Fault {
    if value.len == 0 { return no_fault(); }
    return leaf(out, w, tag, value, max, depth, lim);
}

// write_security appends one security aggregate. Every field is checked
// against the rules of the specification before the writer uses it.
fn write_security(out: u8[>..]&, w: OfxForm, s: OfxSecurity, notes: Note[>..]&,
                  depth: i64, lim: Limits&) -> Fault {
    if !is_secinfo_kind(s.kind) {
        return fault(F_UNKNOWN_TAG, 0, 0, s.kind, "the security kind is not known");
    }
    if s.id.len == 0 || s.id.len > 32 {
        return fault(F_SYNTAX, 0, 0, "UNIQUEID", "the id of the security is empty or too long");
    }
    if s.id_type.len == 0 || s.id_type.len > 10 {
        return fault(F_SYNTAX, 0, 0, "UNIQUEIDTYPE", "the id type of the security is empty or too long");
    }
    if s.name.len == 0 || s.name.len > 120 {
        return fault(F_SYNTAX, 0, 0, "SECNAME", "the name of the security is empty or too long");
    }
    if s.currency.len > 3 {
        return fault(F_SYNTAX, 0, 0, "CURSYM", "the currency of the security is not three letters");
    }
    open_tag(out, w, s.kind, depth);
    open_tag(out, w, "SECINFO", depth + 1);
    open_tag(out, w, "SECID", depth + 2);
    var f = leaf(out, w, "UNIQUEID", s.id, 32, depth + 3, lim);
    if f.kind != F_NONE { return f; }
    f = leaf(out, w, "UNIQUEIDTYPE", s.id_type, 10, depth + 3, lim);
    if f.kind != F_NONE { return f; }
    close_tag(out, w, "SECID", depth + 2);
    f = leaf(out, w, "SECNAME", s.name, 120, depth + 2, lim);
    if f.kind != F_NONE { return f; }
    f = sec_opt_leaf(out, w, "TICKER", s.ticker, 32, depth + 2, lim);
    if f.kind != F_NONE { return f; }
    f = sec_opt_leaf(out, w, "FIID", s.fiid, 32, depth + 2, lim);
    if f.kind != F_NONE { return f; }
    f = sec_opt_leaf(out, w, "RATING", s.rating, 10, depth + 2, lim);
    if f.kind != F_NONE { return f; }
    if s.has_price {
        var tbuf: u8[>..] = [];
        let pt, pf = sec_price_text(s.price, tbuf, "UNITPRICE");
        if pf.kind != F_NONE { return pf; }
        f = leaf(out, w, "UNITPRICE", pt, 32, depth + 2, lim);
        if f.kind != F_NONE { return f; }
        if s.price_date.year != 0 {
            f = leaf_date(out, w, "DTASOF", s.price_date, depth + 2, lim);
            if f.kind != F_NONE { return f; }
        }
    }
    if s.currency.len > 0 {
        f = leaf(out, w, "CURSYM", s.currency, 3, depth + 2, lim);
        if f.kind != F_NONE { return f; }
    }
    f = sec_opt_leaf(out, w, "MEMO", s.memo, 255, depth + 2, lim);
    if f.kind != F_NONE { return f; }
    close_tag(out, w, "SECINFO", depth + 1);
    var j: i64 = s.note_start as i64;
    let jend: i64 = j + (s.note_count as i64);
    while j < jend {
        let nt = notes[j].tag;
        let nv = notes[j].value;
        if !name_ok(nt) {
            return fault(F_SYNTAX, 0, 0, nt, "the name of a note is not an element name");
        }
        if nv.len == 0 {
            open_tag(out, w, nt, depth + 1);
            close_tag(out, w, nt, depth + 1);
        } else {
            f = leaf(out, w, nt, nv, lim.max_field, depth + 1, lim);
            if f.kind != F_NONE { return f; }
        }
        j += 1;
    }
    close_tag(out, w, s.kind, depth);
    return no_fault();
}

// write_ofx_securities appends a security list as an OFX file. The
// caller may parse the output with parse_ofx_securities.
fn write_ofx_securities(securities: OfxSecurity[>..]&, notes: Note[>..]&, opts: OfxWriteOptions,
                        lim: Limits&, out: u8[>..]&) -> Fault {
    var v = opts.version;
    if v == 0 { v = 102; }
    if !version_ok(v) { return fault(F_SYNTAX, 0, 0, "VERSION", "the OFX version is not known"); }
    let w = OfxForm { closed: v >= 200 || opts.close_leaves, indent: opts.indent };
    put_ofx_header(out, v);
    open_tag(out, w, "OFX", 0);
    open_tag(out, w, "SECLISTMSGSRSV1", 1);
    open_tag(out, w, "SECLIST", 2);
    var i: i64 = 0;
    while i < securities.len {
        let f = write_security(out, w, securities[i], notes, 3, lim);
        if f.kind != F_NONE { return with_pos(f, i + 1, f.tag); }
        i += 1;
        let fs = check_size(out, lim);
        if fs.kind != F_NONE { return fs; }
    }
    close_tag(out, w, "SECLIST", 2);
    close_tag(out, w, "SECLISTMSGSRSV1", 1);
    close_tag(out, w, "OFX", 0);
    return check_size(out, lim);
}

// parse_ofx_securities reads the security list of an OFX file. When the
// header names a legacy charset, the body is decoded first.
fn parse_ofx_securities(input: const u8[:], lim: Limits&, securities: OfxSecurity[>..]&,
                        notes: Note[>..]&, buf: u8[>..]&) -> Fault {
    if true {
        let cs = header_charset(input);
        if cs != 0 {
            let mark = buf.len;
            let f = decode_charset(cs, input, lim, buf);
            if f.kind != F_NONE { return f; }
            return parse_ofx_securities_decoded(buf[mark..], lim, securities, notes, buf);
        }
    }
    return parse_ofx_securities_decoded(input, lim, securities, notes, buf);

}
