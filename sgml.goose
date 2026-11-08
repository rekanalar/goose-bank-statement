// The SGML side of the bank_statement package: the OFX header and the
// tag tree reader.
//
// parse_sgml_header reads the header of an OFX 1.x or OFX 2.x file.
// parse_sgml_body reads the body into a flat array of nodes, one linear
// pass with no recursion. The names in the leaf list close at their
// text or at the next tag; every other tag without text opens an
// aggregate. The list is the leaf list of the OFX 1.0.3 DTD.
//
// The nodes are ranges of the input. The input must outlive the tree.
namespace bank_statement;

import std;
import fault;
import limits;
import text;

const SGML_V1: i32 = 1;
const SGML_V2: i32 = 2;

// SgmlHeader holds the fields of an OFX header that the mapping reads.
// The spans point at the input.
struct SgmlHeader {
    version: i32,               // SGML_V1 or SGML_V2
    ofx_header: const u8[:],    // the OFXHEADER field: 100 or 200
    data: const u8[:],          // the DATA field of version 1
    ofx_version: const u8[:],   // 102, 103, 151, 160, 203...
    security: const u8[:],
    encoding: const u8[:],
    charset: const u8[:],
    compression: const u8[:],
    uid_old: const u8[:],
    uid_new: const u8[:],
}

// SgmlNode holds one tag of the body.
struct SgmlNode {
    name: const u8[:],      // the name as the file holds it
    text: const u8[:],      // empty for an aggregate
    parent: i32,
    depth: i32,
    leaf: bool,             // true for a tag that closed at its text
}

// SGML_LEAF holds the leaf names of the OFX 1.0.3 DTD, sorted, one
// name per line. The names match in either letter case.
const SGML_LEAF: const u8[:] =
    "ACCESSKEY\nACCRDINT\nACCTID\nACCTKEY\nACCTREQUIRED\nACCTTYPE\nADDR1\nADDR2\nADDR3\nADJAMT\nADJDATE\nADJDESC\nADJNO\nAPPID\nAPPVER\nASSETCLASS\nAUCTION\nAUTHTOKEN\nAUTHTOKENFIRST\nAUTHTOKENINFOURL\nAUTHTOKENLABEL\nAVAILACCTS\nAVAILCASH\nAVGCOSTBASIS\nBALAMT\nBALCLOSE\nBALDNLD\nBALMIN\nBALOPEN\nBALTYPE\nBANKID\nBILLREFINFO\nBRANCHID\nBROKERID\nBUYPOWER\nBUYTYPE\nCALLPRICE\nCALLTYPE\nCANADDPAYEE\nCANBILLPAY\nCANCELWND\nCANEMAIL\nCANMODMDLS\nCANMODPMTS\nCANMODXFERS\nCANNOTIFY\nCANPENDING\nCANRECUR\nCANSCHED\nCANUSEDESC\nCANUSERANGE\nCASESEN\nCHARTYPE\nCHECKING\nCHECKNUM\nCHGPINFIRST\nCHGUSERINFO\nCHKANDDEB\nCHKERROR\nCHKNUMEND\nCHKNUMSTART\nCHKSTATUS\nCITY\nCLIENTACTREQ\nCLIENTROUTING\nCLIENTUID\nCLIENTUIDREQ\nCLOSINGAVAIL\nCLTCOOKIE\nCODE\nCOMMISSION\nCONFMSG\nCORRECTACTION\nCORRECTFITID\nCOUNTRY\nCOUPONFREQ\nCOUPONRT\nCREDITLIMIT\nCSPHONE\nCURDEF\nCURRATE\nCURSYM\nDATEBIRTH\nDAYPHONE\nDAYSTOPAY\nDAYSWITH\nDEBADJ\nDEBTCLASS\nDEBTTYPE\nDENOMINATOR\nDEPANDCREDIT\nDESC\nDFLTDAYSTOPAY\nDIFFFIRSTPMT\nDIFFLASTPMT\nDOMXFERFEE\nDSCAMT\nDSCDATE\nDSCDESC\nDSCRATE\nDTACCTUP\nDTASOF\nDTAUCTION\nDTAVAIL\nDTCALL\nDTCHANGED\nDTCLIENT\nDTCLOSE\nDTCOUPON\nDTCREATED\nDTDUE\nDTEND\nDTEXPIRE\nDTINFOCHG\nDTMAT\nDTNEXT\nDTOPEN\nDTPLACED\nDTPMTDUE\nDTPMTPRC\nDTPOSTED\nDTPOSTEND\nDTPOSTSTART\nDTPRICEASOF\nDTPROFUP\nDTPURCHASE\nDTSERVER\nDTSETTLE\nDTSTART\nDTTRADE\nDTUSER\nDTXFERPRC\nDTXFERPRJ\nDTYIELDASOF\nDURATION\nEMAIL\nEVEPHONE\nEXTDPMTCHK\nEXTDPMTFOR\nFAXPHONE\nFEE\nFEEMSG\nFEES\nFIASSETCLASS\nFICERTID\nFID\nFIID\nFINALAMT\nFINAME\nFINCHG\nFIRSTNAME\nFITID\nFRACCASH\nFREQ\nFROM\nGAIN\nGENUSERKEY\nGETMIMESUP\nHASEXTDPMT\nHELDINACCT\nIDSCOPE\nINCBAL\nINCIMAGES\nINCLUDE\nINCOMETYPE\nINCOO\nINITIALAMT\nINTLXFERFEE\nINVACCTTYPE\nINVALIDACCTTYPE\nINVDATE\nINVDESC\nINVNO\nINVPAIDAMT\nINVTOTALAMT\nLANGUAGE\nLASTNAME\nLIMITPRICE\nLITMAMT\nLITMDESC\nLOAD\nLOSTSYNC\nMAILSUP\nMARGINBALANCE\nMARKDOWN\nMARKUP\nMAX\nMEMO\nMESSAGE\nMFACHALLENGEFIRST\nMFACHALLENGESUPT\nMFAPHRASEA\nMFAPHRASEID\nMFAPHRASELABEL\nMFTYPE\nMIDDLENAME\nMIN\nMINPMTDUE\nMINUNITS\nMKTGINFO\nMKTVAL\nMODELWND\nMODPENDING\nNAME\nNEWUNITS\nNEWUSERPASS\nNINSTS\nNONCE\nNUMERATOR\nOFXSEC\nOLDUNITS\nOODNLD\nOPTACTION\nOPTBUYTYPE\nOPTIONLEVEL\nOPTSELLTYPE\nOPTTYPE\nORG\nPARVALUE\nPAYACCT\nPAYANDCREDIT\nPAYEEID\nPAYEELSTID\nPAYINSTRUCT\nPERCENT\nPHONE\nPINCH\nPMTBYADDR\nPMTBYPAYEEID\nPMTBYXFER\nPMTPRCCODE\nPOSDNLD\nPOSTALCODE\nPOSTPROCWND\nPOSTYPE\nPROCDAYSOFF\nPROCENDTM\nPURANDADV\nRATING\nRECSRVRTID\nREFNUM\nREFRESH\nREFRESHSUPT\nREINVCG\nREINVDIV\nREJECTIFMISSING\nRELFITID\nRELTYPE\nRESPFILEER\nRESTRICTION\nSECLISTRQDNLD\nSECNAME\nSECURED\nSECURITYNAME\nSELLALL\nSELLREASON\nSELLTYPE\nSESSCOOKIE\nSEVERITY\nSHORTBALANCE\nSHPERCTRCT\nSIC\nSIGNONREALM\nSPACES\nSPECIAL\nSPNAME\nSRVRTID\nSTATE\nSTOCKTYPE\nSTOPPRICE\nSTPCHKFEE\nSTRIKEPRICE\nSTSVIAMODS\nSUBACCT\nSUBACCTFROM\nSUBACCTSEC\nSUBACCTTO\nSUBJECT\nSUPTXDL\nSVC\nSVCSTATUS\nSWITCHALL\nSYNCMODE\nTAN\nTAXES\nTAXEXEMPT\nTAXID\nTEMPPASS\nTFERACTION\nTICKER\nTO\nTOKEN\nTOKENONLY\nTOTAL\nTOTALFEES\nTOTALINT\nTRANDNLD\nTRANSPSEC\nTRNAMT\nTRNTYPE\nTRNUID\nTSKEYEXPIRE\nTSPHONE\nTYPEDESC\nUNIQUEID\nUNIQUEIDTYPE\nUNITPRICE\nUNITS\nUNITSSTREET\nUNITSUSER\nUNITTYPE\nURL\nUSEHTML\nUSERCRED1\nUSERCRED1LABEL\nUSERCRED2\nUSERCRED2LABEL\nUSERID\nUSERKEY\nUSERPASS\nUSPRODUCTTYPE\nVALUE\nVER\nWITHHOLDING\nXFERDAYSWITH\nXFERDEST\nXFERDFLTDAYSTOPAY\nXFERPRCCODE\nXFERSRC\nYIELD\nYIELDTOCALL\nYIELDTOMAT";

// is_leaf tells whether a tag name sits in the leaf list. The match
// takes either letter case.
fn is_leaf(name: const u8[:]) -> bool {
    var start: i64 = 0;
    var i: i64 = 0;
    while i <= SGML_LEAF.len {
        if i == SGML_LEAF.len || SGML_LEAF[i] == '\n' {
            if ieq(SGML_LEAF[start..i], name) { return true; }
            start = i + 1;
        }
        i += 1;
    }
    return false;
}

// sgml_child gives the first child element of the node with the local
// name. The match takes either letter case. It gives -1 when there is
// no such child.
fn sgml_child(nodes: SgmlNode[>..]&, id: i32, name: const u8[:]) -> i32 {
    let d = nodes[id].depth;
    var j = id + 1;
    while j < nodes.len {
        if nodes[j].depth <= d { return -1; }
        if nodes[j].depth == d + 1 && ieq(nodes[j].name, name) { return j; }
        j += 1;
    }
    return -1;
}

// sgml_next gives the next sibling of a node, or -1. A sibling sits
// at the same depth with the same parent.
fn sgml_next(nodes: SgmlNode[>..]&, id: i32) -> i32 {
    let d = nodes[id].depth;
    let p = nodes[id].parent;
    var j = id + 1;
    while j < nodes.len {
        if nodes[j].depth < d { return -1; }
        if nodes[j].depth == d && nodes[j].parent == p { return j; }
        j += 1;
    }
    return -1;
}

// sgml_text_of writes the decoded text of a leaf into buf and gives the
// span. The five named entities and the numeric references decode once.
// An unknown entity stays as text.
fn sgml_text_of(nodes: SgmlNode[>..]&, id: i32, buf: u8[>..]&) -> const u8[:] {
    let start = buf.len;
    decode_entities(nodes[id].text, buf);
    return trim(buf[start..]);
}

// decode_entities copies text into buf and decodes the entities of the
// OFX spec: amp, lt, gt, apos, quot and the numeric references.
fn decode_entities(text: const u8[:], buf: u8[>..]&) {
    var i: i64 = 0;
    while i < text.len {
        if text[i] == '&' {
            let end = find_entity(text, i);
            if end > 0 {
                let name = text[i + 1..end];
                if ieq(name, "amp") { buf.push('&'); }
                else if ieq(name, "lt") { buf.push('<'); }
                else if ieq(name, "gt") { buf.push('>'); }
                else if ieq(name, "apos") { buf.push('\''); }
                else if ieq(name, "quot") { buf.push('"'); }
                else if name.len > 1 && name[0] == '#' {
                    var v: i64 = 0;
                    var ok = true;
                    var k: i64 = 1;
                    var hex = false;
                    if name[1] == 'x' || name[1] == 'X' { hex = true; k = 2; }
                    while k < name.len {
                        let c = name[k];
                        if hex {
                            if c >= '0' && c <= '9' { v = v * 16 + (c - '0'); }
                            else if c >= 'a' && c <= 'f' { v = v * 16 + (c - 'a' + 10); }
                            else if c >= 'A' && c <= 'F' { v = v * 16 + (c - 'A' + 10); }
                            else { ok = false; break; }
                        } else {
                            if !is_digit(c) { ok = false; break; }
                            v = v * 10 + (c - '0');
                        }
                        if v > 1114111 { ok = false; break; }
                        k += 1;
                    }
                    if ok && v >= 32 { push_utf8(buf, v); }
                    else if !ok { for u in text[i..end + 1] { buf.push(u); } }
                } else {
                    // An unknown entity stays as text.
                    for u in text[i..end + 1] { buf.push(u); }
                }
                i = end + 1;
                continue;
            }
        }
        buf.push(text[i]);
        i += 1;
    }
}

// find_entity gives the index of the semicolon that ends the entity at
// start, or -1. The name holds at most 10 bytes.
fn find_entity(text: const u8[:], start: i64) -> i64 {
    var i = start + 1;
    while i < text.len && i <= start + 11 {
        if text[i] == ';' { return i; }
        if text[i] == '&' || text[i] == '<' { return -1; }
        i += 1;
    }
    return -1;
}

// push_utf8 writes one code point into buf.
fn push_utf8(buf: u8[>..]&, v: i64) {
    if v < 128 { buf.push(v as u8); }
    else if v < 2048 {
        buf.push((192 + v / 64) as u8);
        buf.push((128 + v % 64) as u8);
    } else if v < 65536 {
        buf.push((224 + v / 4096) as u8);
        buf.push((128 + (v / 64) % 64) as u8);
        buf.push((128 + v % 64) as u8);
    } else {
        buf.push((240 + v / 262144) as u8);
        buf.push((128 + (v / 4096) % 64) as u8);
        buf.push((128 + (v / 64) % 64) as u8);
        buf.push((128 + v % 64) as u8);
    }
}
// parse_sgml_header reads the header of an OFX file. It gives the
// header, the place where the body starts, and a fault. The reader
// skips a byte order mark and at most 16 leading lines.
fn parse_sgml_header(input: const u8[:]) -> SgmlHeader, i64, Fault {
    let z = SgmlHeader { version: 0, ofx_header: "", data: "", ofx_version: "", security: "", encoding: "", charset: "", compression: "", uid_old: "", uid_new: "" };
    var i: i64 = 0;
    if input.len >= 3 && input[0] == 0xEF && input[1] == 0xBB && input[2] == 0xBF { i = 3; }
    // The first form check: a processing instruction means version 2.
    var j = i;
    while j < input.len && (input[j] == ' ' || input[j] == '\t' || input[j] == '\r' || input[j] == '\n') { j += 1; }
    if j + 5 <= input.len && ieq(input[j..j + 5], "<?xml") {
        return parse_header_v2(input, j);
    }
    // Version 1: the KEY:VALUE lines up to the first tag.
    var h = SgmlHeader { version: SGML_V1, ofx_header: "100", data: "OFXSGML", ofx_version: "102", security: "NONE", encoding: "USASCII", charset: "NONE", compression: "NONE", uid_old: "NONE", uid_new: "NONE" };
    var lines: i64 = 0;
    var k = i;
    var body: i64 = -1;
    while k < input.len && lines < 16 {
        // One line.
        var e = k;
        while e < input.len && input[e] != '\n' && input[e] != '\r' { e += 1; }
        let line = input[k..e];
        // A tag in the line starts the body. The text before it is
        // still a header field.
        let lt = find_char(line, '<');
        if lt >= 0 {
            let f = read_header_fields(line[0..lt], h);
            if f.kind != F_NONE { return z, -1, f; }
            body = k + lt;
            break;
        }
        if trim(line).len > 0 {
            let f = read_header_fields(line, h);
            if f.kind != F_NONE { return z, -1, f; }
        }
        lines += 1;
        if e >= input.len { k = e; break; }
        // The line ends: CR LF counts as one.
        if input[e] == '\r' && e + 1 < input.len && input[e + 1] == '\n' { k = e + 2; }
        else { k = e + 1; }
    }
    if body < 0 { return z, -1, fault(F_SYNTAX, 0, 0, "", "the file has no OFX body"); }
    let f2 = check_header(h);
    if f2.kind != F_NONE { return z, -1, f2; }
    return h, body, no_fault();
}

// find_char gives the first place of a byte in a slice, or -1.
fn find_char(s: const u8[:], c: u8) -> i64 {
    var i: i64 = 0;
    while i < s.len {
        if s[i] == c { return i; }
        i += 1;
    }
    return -1;
}

// read_header_fields reads the KEY:VALUE pairs of a text. The pairs
// may sit on one line. A value ends at a blank.
fn read_header_fields(text: const u8[:], h: SgmlHeader&) -> Fault {
    var i: i64 = 0;
    while i < text.len {
        while i < text.len && (text[i] == ' ' || text[i] == '\t' || text[i] == '\r' || text[i] == '\n') { i += 1; }
        if i >= text.len { break; }
        var e = i;
        while e < text.len && text[e] != ':' { e += 1; }
        if e >= text.len { return fault(F_SYNTAX, 0, 0, "", "the header line is not KEY:VALUE"); }
        let key = trim(text[i..e]);
        if key.len == 0 { return fault(F_SYNTAX, 0, 0, "", "the header line has no field name"); }
        i = e + 1;
        var v = i;
        while v < text.len && text[v] != ' ' && text[v] != '\t' && text[v] != '\r' && text[v] != '\n' { v += 1; }
        let value = text[i..v];
        let f = set_header_field(h, key, value, 0);
        if f.kind != F_NONE { return f; }
        i = v;
    }
    return no_fault();
}

// split_header_line splits a KEY:VALUE line. A space after the colon
// is part of the rule.
fn split_header_line(line: const u8[:]) -> const u8[:], const u8[:], bool {
    var c: i64 = 0;
    while c < line.len && line[c] != ':' { c += 1; }
    if c == 0 || c >= line.len { return "", "", false; }
    return trim(line[0..c]), trim(line[c + 1..]), true;
}

// set_header_field puts one field of a v1 header into the header. An
// unknown field is a fault that names it.
fn set_header_field(h: SgmlHeader&, key: const u8[:], value: const u8[:], line_no: i64) -> Fault {
    if ieq(key, "OFXHEADER") { h.ofx_header = value; return no_fault(); }
    if ieq(key, "DATA") { h.data = value; return no_fault(); }
    if ieq(key, "VERSION") { h.ofx_version = value; return no_fault(); }
    if ieq(key, "SECURITY") { h.security = value; return no_fault(); }
    if ieq(key, "ENCODING") { h.encoding = value; return no_fault(); }
    if ieq(key, "CHARSET") { h.charset = value; return no_fault(); }
    if ieq(key, "COMPRESSION") { h.compression = value; return no_fault(); }
    if ieq(key, "OLDFILEUID") { h.uid_old = value; return no_fault(); }
    if ieq(key, "NEWFILEUID") { h.uid_new = value; return no_fault(); }
    return fault(F_SYNTAX, line_no, 1, key, "the header field is not an OFX field");
}

// check_header checks the values of a v1 header. A bad value is a
// fault that names the field.
fn check_header(h: SgmlHeader&) -> Fault {
    if !(h.ofx_header.len == 3 && h.ofx_header == "100") {
        return fault(F_SYNTAX, 0, 0, "OFXHEADER", "the header version is not 100");
    }
    if !ieq(h.data, "OFXSGML") { return fault(F_SYNTAX, 0, 0, "DATA", "the data type is not OFXSGML"); }
    if !(ieq(h.ofx_version, "102") || ieq(h.ofx_version, "103") || ieq(h.ofx_version, "151") || ieq(h.ofx_version, "160")) {
        return fault(F_SYNTAX, 0, 0, "VERSION", "the OFX version is not 102, 103, 151 or 160");
    }
    if !(ieq(h.security, "NONE") || ieq(h.security, "TYPE1")) {
        return fault(F_SYNTAX, 0, 0, "SECURITY", "the security is not NONE or TYPE1");
    }
    if !(ieq(h.encoding, "USASCII") || ieq(h.encoding, "UNICODE") || ieq(h.encoding, "UTF-8")) {
        return fault(F_SYNTAX, 0, 0, "ENCODING", "the encoding is not USASCII, UNICODE or UTF-8");
    }
    if !(ieq(h.charset, "NONE") || ieq(h.charset, "1252") || ieq(h.charset, "ISO-8859-1")) {
        return fault(F_SYNTAX, 0, 0, "CHARSET", "the charset is not NONE, 1252 or ISO-8859-1");
    }
    if !ieq(h.compression, "NONE") { return fault(F_SYNTAX, 0, 0, "COMPRESSION", "the compression is not NONE"); }
    if h.uid_old.len > 36 || h.uid_new.len > 36 {
        return fault(F_SYNTAX, 0, 0, "UID", "a file uid is longer than 36 bytes");
    }
    return no_fault();
}

// parse_header_v2 reads the two processing instructions of an OFX 2.x
// file. The body starts after the OFX instruction.
fn parse_header_v2(input: const u8[:], at: i64) -> SgmlHeader, i64, Fault {
    let z = SgmlHeader { version: 0, ofx_header: "", data: "", ofx_version: "", security: "", encoding: "", charset: "", compression: "", uid_old: "", uid_new: "" };
    var h = SgmlHeader { version: SGML_V2, ofx_header: "200", data: "", ofx_version: "", security: "NONE", encoding: "", charset: "", compression: "NONE", uid_old: "NONE", uid_new: "NONE" };
    // The xml declaration runs to ?>.
    let x = find_pi_end(input, at);
    if x < 0 { return z, -1, fault(F_SYNTAX, 1, 1, "?xml", "the xml declaration is not closed"); }
    // The OFX instruction, after the ?> of the xml declaration.
    var k = x + 2;
    while k < input.len && (input[k] == ' ' || input[k] == '\t' || input[k] == '\r' || input[k] == '\n') { k += 1; }
    if k + 5 > input.len || !ieq(input[k..k + 5], "<?ofx") {
        return z, -1, fault(F_SYNTAX, 1, 1, "?OFX", "the file has no OFX instruction");
    }
    let o = find_pi_end(input, k);
    if o < 0 { return z, -1, fault(F_SYNTAX, 1, 1, "?OFX", "the OFX instruction is not closed"); }
    // The text of the instruction runs to the ? of the ?>.
    let f = read_pi_attrs(input[k + 5..o], h);
    if f.kind != F_NONE { return z, -1, f; }
    if !(h.ofx_header.len == 3 && h.ofx_header == "200") {
        return z, -1, fault(F_SYNTAX, 0, 0, "OFXHEADER", "the header version is not 200");
    }
    if !(ieq(h.ofx_version, "200") || ieq(h.ofx_version, "201") || ieq(h.ofx_version, "202") || ieq(h.ofx_version, "203")
         || ieq(h.ofx_version, "210") || ieq(h.ofx_version, "211") || ieq(h.ofx_version, "220")) {
        return z, -1, fault(F_SYNTAX, 0, 0, "VERSION", "the OFX version is not 200 to 220");
    }
    if !(ieq(h.security, "NONE") || ieq(h.security, "TYPE1")) {
        return z, -1, fault(F_SYNTAX, 0, 0, "SECURITY", "the security is not NONE or TYPE1");
    }
    return h, o + 2, no_fault();
}

// find_pi_end gives the index of the ? of ?>, or -1.
fn find_pi_end(input: const u8[:], at: i64) -> i64 {
    var i = at;
    while i + 1 < input.len {
        if input[i] == '?' && input[i + 1] == '>' { return i; }
        i += 1;
    }
    return -1;
}

// read_pi_attrs reads the NAME="value" pairs of a processing
// instruction. An unknown attribute is a fault that names it.
fn read_pi_attrs(text: const u8[:], h: SgmlHeader&) -> Fault {
    var i: i64 = 0;
    while i < text.len {
        while i < text.len && (text[i] == ' ' || text[i] == '\t' || text[i] == '\r' || text[i] == '\n') { i += 1; }
        if i >= text.len { break; }
        var e = i;
        while e < text.len && text[e] != '=' { e += 1; }
        if e >= text.len { return fault(F_SYNTAX, 0, 0, text[i..e], "the attribute has no value"); }
        let key = trim(text[i..e]);
        if e + 1 >= text.len || text[e + 1] != '"' { return fault(F_SYNTAX, 0, 0, key, "the attribute value is not in quotes"); }
        var q = e + 2;
        while q < text.len && text[q] != '"' { q += 1; }
        if q >= text.len { return fault(F_SYNTAX, 0, 0, key, "the attribute value is not closed"); }
        let value = text[e + 2..q];
        if ieq(key, "OFXHEADER") { h.ofx_header = value; }
        else if ieq(key, "VERSION") { h.ofx_version = value; }
        else if ieq(key, "SECURITY") { h.security = value; }
        else if ieq(key, "OLDFILEUID") { h.uid_old = value; }
        else if ieq(key, "NEWFILEUID") { h.uid_new = value; }
        else { return fault(F_SYNTAX, 0, 0, key, "the attribute is not an OFX attribute"); }
        i = q + 1;
    }
    return no_fault();
}
// parse_sgml_body reads the body of an OFX file into the node array of
// the caller. One linear pass, no recursion. A tag with text is a
// leaf. A tag whose name sits in the leaf list closes at the next tag.
// Any other tag without text opens an aggregate. A closing tag must
// name the open aggregate.
fn parse_sgml_body(input: const u8[:], start: i64, lim: Limits&, nodes: SgmlNode[>..]&, buf: u8[>..]&) -> Fault {
    var stack: i32[>..] = [];
    var i = start;
    while i < input.len {
        if input[i] != '<' {
            // Text outside a tag. It is a fault unless it is blank,
            // or it is the text of a leaf that waits for it.
            var e = i;
            while e < input.len && input[e] != '<' { e += 1; }
            if trim(input[i..e]).len > 0 {
                return fault(F_SYNTAX, 0, 0, "", "the body has text outside a tag");
            }
            i = e;
            continue;
        }
        // A comment, a CDATA section, a doctype or a tag.
        if i + 4 <= input.len && ieq(input[i..i + 4], "<!--") {
            let e = find_lit(input, i + 4, "-->");
            if e < 0 { return fault(F_SYNTAX, 0, 0, "!--", "the comment is not closed"); }
            i = e + 3;
            continue;
        }
        if i + 9 <= input.len && ieq(input[i..i + 9], "<![CDATA[") {
            return fault(F_SYNTAX, 0, 0, "CDATA", "a CDATA section sits outside a tag");
        }
        if i + 9 <= input.len && ieq(input[i..i + 9], "<!DOCTYPE") {
            return fault(F_SYNTAX, 0, 0, "DOCTYPE", "a doctype has no place in OFX");
        }
        if i + 8 <= input.len && ieq(input[i..i + 8], "<!ENTITY") {
            return fault(F_SYNTAX, 0, 0, "ENTITY", "an entity has no place in OFX");
        }
        if i + 2 <= input.len && input[i + 1] == '!' {
            return fault(F_SYNTAX, 0, 0, "!", "the body holds an unknown declaration");
        }
        if i + 1 < input.len && input[i + 1] == '?' {
            let e = find_pi_end(input, i);
            if e < 0 { return fault(F_SYNTAX, 0, 0, "?", "the processing instruction is not closed"); }
            i = e + 2;
            continue;
        }
        // A tag. The name runs to the > or to blank.
        var n = i + 1;
        var is_close = false;
        if n < input.len && input[n] == '/' { is_close = true; n += 1; }
        let name_start = n;
        while n < input.len && input[n] != '>' && input[n] != ' ' && input[n] != '\t' && input[n] != '\r' && input[n] != '\n' { n += 1; }
        if n >= input.len { return fault(F_SYNTAX, 0, 0, "", "the tag is not closed"); }
        let name = input[name_start..n];
        if name.len == 0 { return fault(F_SYNTAX, 0, 0, "", "the tag has no name"); }
        // The > of the tag.
        while n < input.len && input[n] != '>' {
            if input[n] == '<' { return fault(F_SYNTAX, 0, 0, name, "the tag holds a second tag"); }
            n += 1;
        }
        if n >= input.len { return fault(F_SYNTAX, 0, 0, name, "the tag is not closed"); }
        i = n + 1;
        if is_close {
            // A closing tag. It must name the open aggregate. A bank
            // may also write the close tag of a leaf that closed at
            // its text; such a tag is dropped.
            if stack.len == 0 { return fault(F_SYNTAX, 0, 0, name, "the tag closes nothing"); }
            let top = stack[stack.len - 1];
            if !ieq(nodes[top].name, name) {
                // A leaf never closes an aggregate, so the close tag
                // of a leaf name is dropped. The close tag of a leaf
                // that closed at its text is dropped too. Any other
                // mismatch is a fault.
                if is_leaf(name) { continue; }
                let last = nodes.len - 1;
                if last >= 0 && ieq(nodes[last].name, name) && nodes[last].leaf { continue; }
                return fault(F_SYNTAX, 0, 0, name, "the tag does not match the open tag");
            }
            stack.pop();
            continue;
        }
        // A private tag holds a dot in its name. The reader drops it.
        let private = find_char(name, '.') >= 0;
        // The text up to the next markup.
        let t = text_upto(input, i);
        var leaf = false;
        // The text starts with the root of the input, so the spans of
        // the body share one root.
        var text: const u8[:] = input[0..0];
        if t.kind == 2 {
            // A CDATA section right after the tag.
            let e = find_lit(input, t.end + 9, "]]>");
            if e < 0 { return fault(F_SYNTAX, 0, 0, name, "the CDATA section is not closed"); }
            leaf = true;
            text = input[t.end + 9..e];
            i = e + 3;
        } else {
            let txt = trim(t.text);
            if txt.len > 0 {
                leaf = true;
                text = txt;
                i = t.end;
            } else if is_leaf(name) {
                leaf = true;
                i = t.end;
            } else {
                i = t.end;
            }
        }
        if private {
            // The close tag of a private tag is dropped too.
            if i + 2 + name.len <= input.len && input[i + 1] == '/' && ieq(input[i + 2..i + 2 + name.len], name) {
                var q = i + 2 + name.len;
                while q < input.len && input[q] != '>' { q += 1; }
                if q < input.len { i = q + 1; }
            }
            continue;
        }
        if nodes.len >= lim.max_fields {
            return fault(F_LIMIT, 0, 0, name, "more elements than max_fields");
        }
        var parent: i32 = -1;
        var depth: i32 = 0;
        if stack.len > 0 {
            parent = stack[stack.len - 1];
            depth = nodes[parent].depth + 1;
            if depth > lim.max_depth {
                return fault(F_LIMIT, 0, 0, name, "the nesting is deeper than max_depth");
            }
        }
        nodes.push(SgmlNode { name: name, text: text, parent: parent, depth: depth, leaf: leaf });
        if !leaf { stack.push((nodes.len - 1) as i32); }
    }
    if stack.len > 0 {
        // The name goes into the buffer of the caller, so the fault
        // holds no span of the node array.
        let top = stack[stack.len - 1];
        let start = buf.len;
        for u in nodes[top].name { buf.push(u); }
        return fault(F_SYNTAX, 0, 0, buf[start..], "the tag is not closed at the end of the file");
    }
    return no_fault();
}

// struct text_upto holds what text_upto found.
struct text_upto {
    kind: i32,      // 0: blank or nothing, 1: text, 2: a CDATA section
    text: const u8[:],
    end: i64,       // the place after the text or the CDATA section
}

// text_upto reads the text from at to the next markup. A CDATA section
// counts as markup of its own kind.
fn text_upto(input: const u8[:], at: i64) -> text_upto {
    var i = at;
    while i < input.len {
        if input[i] == '<' {
            if i + 9 <= input.len && ieq(input[i..i + 9], "<![CDATA[") { return text_upto { kind: 2, text: "", end: i }; }
            return text_upto { kind: 1, text: input[at..i], end: i };
        }
        i += 1;
    }
    return text_upto { kind: 1, text: input[at..], end: i };
}

// find_lit gives the index of the first hit of lit at or after at, or
// -1.
fn find_lit(s: const u8[:], at: i64, lit: const u8[:]) -> i64 {
    var i = at;
    while i + lit.len <= s.len {
        var k: i64 = 0;
        while k < lit.len && s[i + k] == lit[k] { k += 1; }
        if k == lit.len { return i; }
        i += 1;
    }
    return -1;
}
