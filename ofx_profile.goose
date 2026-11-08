// The profile response of an OFX file.
//
// parse_ofx_profile reads the PROFRS aggregate of a profile response:
// the institution, its sign-on rules and its message sets. The sign-on
// rules and the message sets are arrays that the caller owns. A leaf of
// a message set that has no typed field comes back as a note, so no
// value is lost. The package sends no request and opens no connection.
namespace bank_statement;

import std;
import fault;
import text;
import limits;
import amount;
import date;
import mt940;
import sgml;
import ofx;

// OfxProfile holds the institution part of a profile response.
struct OfxProfile {
    found: bool,
    updated: Date,
    name: const u8[:],
    addr1: const u8[:],
    addr2: const u8[:],
    addr3: const u8[:],
    city: const u8[:],
    state: const u8[:],
    postal_code: const u8[:],
    country: const u8[:],
    cs_phone: const u8[:],
    ts_phone: const u8[:],
    fax_phone: const u8[:],
    url: const u8[:],
    email: const u8[:],
}

// OfxSignonInfo holds one SIGNONINFO aggregate: the rules of a sign-on
// realm. The flags hold Y as true and N as false.
struct OfxSignonInfo {
    realm: const u8[:],
    min: i64,
    max: i64,
    char_type: const u8[:],
    case_sen: bool,
    special: bool,
    spaces: bool,
    pin_change: bool,
    chg_pin_first: bool,
    usercred1_label: const u8[:],
    usercred2_label: const u8[:],
    client_uid_req: bool,
    auth_token_first: bool,
    auth_token_label: const u8[:],
    auth_token_info_url: const u8[:],
    mfa_challenge_supt: bool,
    mfa_challenge_first: bool,
}

// OfxMsgSet holds one version of one message set. The kind is the name
// of the set, such as BANKMSGSET. The other leaves are a range of the
// array of notes.
struct OfxMsgSet {
    kind: const u8[:],
    ver: const u8[:],
    url: const u8[:],
    sec: const u8[:],
    trans_psec: const u8[:],
    realm: const u8[:],
    sp_name: const u8[:],
    note_start: i32,
    note_count: i32,
}

const CHAR_TYPES: const u8[:][] = ["ALPHAONLY", "NUMERICONLY", "ALPHAORNUMERIC", "ALPHAANDNUMERIC"];

// ofx_flag reads a Y or N leaf. A missing leaf is false.
fn ofx_flag(nodes: SgmlNode[>..]&, id: i32, name: const u8[:], buf: u8[>..]&) -> bool, Fault {
    let v = child_text(nodes, id, name, buf);
    if v.len == 0 || v == "N" { return false, no_fault(); }
    if v == "Y" { return true, no_fault(); }
    return false, fault(F_SYNTAX, 0, 0, name, "the flag is not Y or N");
}

// ofx_count reads a leaf of 1 to 9 digits. A missing leaf is 0.
fn ofx_count(nodes: SgmlNode[>..]&, id: i32, name: const u8[:], buf: u8[>..]&) -> i64, Fault {
    let v = child_text(nodes, id, name, buf);
    if v.len == 0 { return 0, no_fault(); }
    let n, ok = digits(v);
    if !ok { return 0, fault(F_SYNTAX, 0, 0, name, "the number has 1 to 9 digits"); }
    return n, no_fault();
}

fn ofx_signon_info(nodes: SgmlNode[>..]&, id: i32, buf: u8[>..]&) -> OfxSignonInfo, Fault {
    var s = OfxSignonInfo {
        realm: child_text(nodes, id, "SIGNONREALM", buf), min: 0, max: 0, char_type: child_text(nodes, id, "CHARTYPE", buf),
        case_sen: false, special: false, spaces: false, pin_change: false, chg_pin_first: false,
        usercred1_label: child_text(nodes, id, "USERCRED1LABEL", buf),
        usercred2_label: child_text(nodes, id, "USERCRED2LABEL", buf),
        client_uid_req: false, auth_token_first: false,
        auth_token_label: child_text(nodes, id, "AUTHTOKENLABEL", buf),
        auth_token_info_url: child_text(nodes, id, "AUTHTOKENINFOURL", buf),
        mfa_challenge_supt: false, mfa_challenge_first: false,
    };
    if s.char_type.len > 0 && !in_list(CHAR_TYPES, s.char_type) {
        return s, fault(F_SYNTAX, 0, 0, "CHARTYPE", "the character type is not known");
    }
    var f = no_fault();
    s.min, f = ofx_count(nodes, id, "MIN", buf); if f.kind != F_NONE { return s, f; }
    s.max, f = ofx_count(nodes, id, "MAX", buf); if f.kind != F_NONE { return s, f; }
    s.case_sen, f = ofx_flag(nodes, id, "CASESEN", buf); if f.kind != F_NONE { return s, f; }
    s.special, f = ofx_flag(nodes, id, "SPECIAL", buf); if f.kind != F_NONE { return s, f; }
    s.spaces, f = ofx_flag(nodes, id, "SPACES", buf); if f.kind != F_NONE { return s, f; }
    s.pin_change, f = ofx_flag(nodes, id, "PINCH", buf); if f.kind != F_NONE { return s, f; }
    s.chg_pin_first, f = ofx_flag(nodes, id, "CHGPINFIRST", buf); if f.kind != F_NONE { return s, f; }
    s.client_uid_req, f = ofx_flag(nodes, id, "CLIENTUIDREQ", buf); if f.kind != F_NONE { return s, f; }
    s.auth_token_first, f = ofx_flag(nodes, id, "AUTHTOKENFIRST", buf); if f.kind != F_NONE { return s, f; }
    s.mfa_challenge_supt, f = ofx_flag(nodes, id, "MFACHALLENGESUPT", buf); if f.kind != F_NONE { return s, f; }
    s.mfa_challenge_first, f = ofx_flag(nodes, id, "MFACHALLENGEFIRST", buf); if f.kind != F_NONE { return s, f; }
    return s, no_fault();
}

// ofx_msgset reads one version aggregate of a message set, such as
// BANKMSGSETV1. The set is the parent aggregate.
fn ofx_msgset(nodes: SgmlNode[>..]&, set: i32, v: i32, lim: Limits&, notes: Note[>..]&, buf: u8[>..]&) -> OfxMsgSet, Fault {
    var m = OfxMsgSet { kind: "", ver: "", url: "", sec: "", trans_psec: "", realm: "", sp_name: "",
                        note_start: notes.len as i32, note_count: 0 };
    let ks = buf.len;
    for u in nodes[set].name {
        if u >= 'a' && u <= 'z' { buf.push(u - 32); } else { buf.push(u); }
    }
    m.kind = buf[ks..];
    let d = nodes[v].depth;
    var j = v + 1;
    while j < nodes.len && nodes[j].depth > d {
        let n = nodes[j];
        if !n.leaf { j += 1; continue; }
        var done = false;
        if ieq(n.name, "VER") && m.ver.len == 0 { m.ver = sgml_text_of(nodes, j, buf); done = true; }
        else if ieq(n.name, "URL") && m.url.len == 0 { m.url = sgml_text_of(nodes, j, buf); done = true; }
        else if ieq(n.name, "OFXSEC") && m.sec.len == 0 { m.sec = sgml_text_of(nodes, j, buf); done = true; }
        else if ieq(n.name, "TRANSPSEC") && m.trans_psec.len == 0 { m.trans_psec = sgml_text_of(nodes, j, buf); done = true; }
        else if ieq(n.name, "SIGNONREALM") && m.realm.len == 0 { m.realm = sgml_text_of(nodes, j, buf); done = true; }
        else if ieq(n.name, "SPNAME") && m.sp_name.len == 0 { m.sp_name = sgml_text_of(nodes, j, buf); done = true; }
        if !done {
            if notes.len >= lim.max_fields { return m, fault(F_LIMIT, 0, 0, "", "more fields than max_fields"); }
            let start = buf.len;
            for u in n.name { buf.push(u); }
            let tag = buf[start..];
            let val = sgml_text_of(nodes, j, buf);
            notes.push(Note { tag: tag, value: val });
            m.note_count += 1;
        }
        j += 1;
    }
    return m, no_fault();
}

// parse_ofx_profile reads the profile response of an OFX file. The
// field found of the profile tells whether the file holds one.
fn parse_ofx_profile(input: const u8[:], lim: Limits&, profile: OfxProfile&, signons: OfxSignonInfo[>..]&,
                     sets: OfxMsgSet[>..]&, notes: Note[>..]&, buf: u8[>..]&) -> Fault {
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
    let ms = sgml_child(nodes, 0, "PROFMSGSRSV1");
    if ms < 0 { return no_fault(); }
    let tr = sgml_child(nodes, ms, "PROFTRNRS");
    if tr < 0 { return no_fault(); }
    let p = sgml_child(nodes, tr, "PROFRS");
    if p < 0 { return no_fault(); }
    profile.found = true;
    profile.name = child_text(nodes, p, "FINAME", buf);
    profile.addr1 = child_text(nodes, p, "ADDR1", buf);
    profile.addr2 = child_text(nodes, p, "ADDR2", buf);
    profile.addr3 = child_text(nodes, p, "ADDR3", buf);
    profile.city = child_text(nodes, p, "CITY", buf);
    profile.state = child_text(nodes, p, "STATE", buf);
    profile.postal_code = child_text(nodes, p, "POSTALCODE", buf);
    profile.country = child_text(nodes, p, "COUNTRY", buf);
    profile.cs_phone = child_text(nodes, p, "CSPHONE", buf);
    profile.ts_phone = child_text(nodes, p, "TSPHONE", buf);
    profile.fax_phone = child_text(nodes, p, "FAXPHONE", buf);
    profile.url = child_text(nodes, p, "URL", buf);
    profile.email = child_text(nodes, p, "EMAIL", buf);
    let dt = sgml_child(nodes, p, "DTPROFUP");
    if dt >= 0 {
        let d, ok = ofx_date(sgml_text_of(nodes, dt, buf));
        if !ok { return fault(F_DATE, 0, 0, "DTPROFUP", "the date is not OFX form"); }
        profile.updated = d;
    }
    let sl = sgml_child(nodes, p, "SIGNONINFOLIST");
    if sl >= 0 {
        var c = first_child(nodes, sl);
        while c >= 0 {
            if ieq(nodes[c].name, "SIGNONINFO") {
                if signons.len >= lim.max_records { return fault(F_LIMIT, 0, 0, "", "more records than max_records"); }
                let s, f = ofx_signon_info(nodes, c, buf);
                if f.kind != F_NONE { return f; }
                signons.push(s);
            }
            c = sgml_next(nodes, c);
        }
    }
    let ml = sgml_child(nodes, p, "MSGSETLIST");
    if ml >= 0 {
        var s = first_child(nodes, ml);
        while s >= 0 {
            var v = first_child(nodes, s);
            while v >= 0 {
                if sets.len >= lim.max_records { return fault(F_LIMIT, 0, 0, "", "more records than max_records"); }
                let m, f = ofx_msgset(nodes, s, v, lim, notes, buf);
                if f.kind != F_NONE { return f; }
                sets.push(m);
                v = sgml_next(nodes, v);
            }
            s = sgml_next(nodes, s);
        }
    }
    return no_fault();
}
