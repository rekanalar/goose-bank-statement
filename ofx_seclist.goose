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
fn parse_ofx_securities(input: const u8[:], lim: Limits&, securities: OfxSecurity[>..]&,
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
