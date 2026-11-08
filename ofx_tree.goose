// The element tree of an OFX file.
//
// parse_ofx_tree reads every element under the OFX root into a flat list
// of nodes in document order. write_ofx_tree writes such a list as an
// OFX file. The pair covers the message sets that have no typed record:
// the investment statement, the sign-on request, the bill pay messages
// and any other set. The reader keeps every value. The writer checks
// every name, every nesting step and every text, and it escapes the text.
namespace bank_statement;

import std;
import fault;
import text;
import limits;
import amount;
import date;
import sgml;
import write_text;
import ofx_write;
import currency;
import country;
import ofx;

// OfxNode holds one element. The depth is 0 for a child of the OFX
// root. An aggregate has an empty text. A leaf holds its text.
struct OfxNode {
    depth: i32,
    name: const u8[:],
    text: const u8[:],
}

// parse_ofx_tree reads the elements under the OFX root. The names go
// to the capital letters. The names and the texts live in buf.
fn parse_ofx_tree(input: const u8[:], lim: Limits&, tree: OfxNode[>..]&, buf: u8[>..]&) -> Fault {
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
    var j: i64 = 1;
    while j < nodes.len {
        if tree.len >= lim.max_fields { return fault(F_LIMIT, 0, 0, "", "more fields than max_fields"); }
        let n = nodes[j];
        let ks = buf.len;
        for u in n.name {
            if u >= 'a' && u <= 'z' { buf.push(u - 32); } else { buf.push(u); }
        }
        let name = buf[ks..];
        if n.leaf {
            let text = sgml_text_of(nodes, j as i32, buf);
            tree.push(OfxNode { depth: n.depth - 1, name: name, text: text });
        } else {
            tree.push(OfxNode { depth: n.depth - 1, name: name, text: "" });
        }
        j += 1;
    }
    return no_fault();
}

// name_ok tells whether a name is 1 to 32 capital letters or digits.
fn name_ok(s: const u8[:]) -> bool {
    if s.len < 1 || s.len > 32 { return false; }
    for c in s {
        if !((c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')) { return false; }
    }
    return true;
}

// close_to closes the open aggregates down to a depth.
fn close_to(out: u8[>..]&, w: OfxForm, tree: OfxNode[>..]&, open: i64[>..]&, depth: i64) {
    while open.len > 0 && (tree[open[open.len - 1]].depth as i64) >= depth {
        let at = open[open.len - 1];
        close_tag(out, w, tree[at].name, (tree[at].depth as i64) + 1);
        open.pop();
    }
}

// write_ofx_tree appends an OFX file. The nodes must start at depth 0
// and may go down by one step only. A node with children holds no text.
// A leaf of the DTD, and any node with a text, is written as a leaf.
fn write_ofx_tree(tree: OfxNode[>..]&, opts: OfxWriteOptions, lim: Limits&, out: u8[>..]&) -> Fault {
    var v = opts.version;
    if v == 0 { v = 102; }
    if !version_ok(v) { return fault(F_SYNTAX, 0, 0, "VERSION", "the OFX version is not known"); }
    if !opts.loose_elements {
        let cf = check_ofx_tree(tree, lim);
        if cf.kind != F_NONE { return cf; }
    }
    let w = OfxForm { closed: v >= 200 || opts.close_leaves, indent: opts.indent };
    put_ofx_header(out, v);
    open_tag(out, w, "OFX", 0);
    var open: i64[>..] = [];
    var prev: i64 = -1;
    var i: i64 = 0;
    while i < tree.len {
        let n = tree[i];
        let d = n.depth as i64;
        if !name_ok(n.name) { return fault(F_SYNTAX, i + 1, 0, n.name, "an element name is 1 to 32 capital letters or digits"); }
        if d < 0 || d > prev + 1 || d > lim.max_depth - 2 {
            return fault(F_SYNTAX, i + 1, 0, n.name, "the depth is below 0, above the limit or two steps down");
        }
        close_to(out, w, tree, open, d);
        let has_children = i + 1 < tree.len && (tree[i + 1].depth as i64) > d;
        if has_children {
            if n.text.len > 0 { return fault(F_SYNTAX, i + 1, 0, n.name, "an aggregate holds no text"); }
            open_tag(out, w, n.name, d + 1);
            open.push(i);
        } else if n.text.len > 0 || is_leaf(n.name) {
            let f = leaf(out, w, n.name, n.text, lim.max_field, d + 1, lim);
            if f.kind != F_NONE { return with_pos(f, i + 1, n.name); }
        } else {
            open_tag(out, w, n.name, d + 1);
            close_tag(out, w, n.name, d + 1);
        }
        prev = d;
        i += 1;
        let fs = check_size(out, lim);
        if fs.kind != F_NONE { return fs; }
    }
    close_to(out, w, tree, open, 0);
    close_tag(out, w, "OFX", 0);
    return check_size(out, lim);
}


// ---- the element rules ----

// find_rule looks a row of the rule table up by name with a binary
// search. The names are sorted. It gives -1 when no row carries the
// name.
fn find_rule(name: const u8[:]) -> i64 {
    var lo: i64 = 0;
    var hi: i64 = OFX_RULE_NAMES.len as i64;
    while lo < hi {
        let mid = (lo + hi) / 2;
        let c = compare_bytes(name, OFX_RULE_NAMES[mid]);
        if c == 0 { return mid; }
        if c < 0 { hi = mid; } else { lo = mid + 1; }
    }
    return -1;
}

// rule_elem reads the element number n of a row. It gives the tag
// without the star, the kind letter, the required flag and the argument
// text. The last result tells whether the row holds an element number n.
fn rule_elem(row: const u8[:], n: i64) -> const u8[:], u8, bool, const u8[:], bool {
    var elem: i64 = 0;
    var start: i64 = 0;
    var i: i64 = 0;
    while i <= row.len {
        if i == row.len || row[i] == ',' {
            if elem == n {
                let part = row[start..i];
                var tag: const u8[:] = "";
                var kind: u8 = 'U';
                var req = false;
                var arg: const u8[:] = "";
                var f: i64 = 0;
                var p: i64 = 0;
                var q: i64 = 0;
                while q <= part.len {
                    if q == part.len || part[q] == ':' {
                        let fld = part[p..q];
                        if f == 0 {
                            tag = fld;
                            if tag.len > 0 && tag[tag.len - 1] == '*' { tag = tag[..tag.len - 1]; }
                        } else if f == 1 && fld.len > 0 {
                            kind = fld[0];
                        } else if f == 2 {
                            req = fld.len > 0 && fld[0] == '1';
                        } else if f == 3 {
                            arg = fld;
                        }
                        f += 1;
                        p = q + 1;
                    }
                    q += 1;
                }
                return tag, kind, req, arg, true;
            }
            elem += 1;
            start = i + 1;
        }
        i += 1;
    }
    return "", 'U', false, "", false;
}

// arg_num reads the number out of an argument text.
fn arg_num(arg: const u8[:]) -> i64 {
    var v: i64 = 0;
    for c in arg {
        if c >= '0' && c <= '9' { v = v * 10 + (c - '0') as i64; }
    }
    return v;
}

// enum_member tells whether a value is a member of an enum set. The
// sets hold the members in order, split by the slash.
fn enum_member(val: const u8[:], set: i64) -> bool {
    if set < 0 || set >= OFX_ENUM_SETS.len as i64 { return false; }
    let s = OFX_ENUM_SETS[set];
    var start: i64 = 0;
    var i: i64 = 0;
    while i <= s.len {
        if i == s.len || s[i] == '/' {
            if compare_bytes(val, s[start..i]) == 0 { return true; }
            start = i + 1;
        }
        i += 1;
    }
    return false;
}

// digits_ok tells whether a text is an integer with an optional sign.
fn digits_ok(t: const u8[:]) -> bool {
    var i: i64 = 0;
    if t.len > 0 && (t[0] == '-' || t[0] == '+') { i = 1; }
    if i >= t.len { return false; }
    while i < t.len {
        if !is_digit(t[i]) { return false; }
        i += 1;
    }
    return true;
}

// decimal_ok tells whether a text is a decimal number with an optional
// sign, one decimal point and at least one digit.
fn decimal_ok(t: const u8[:]) -> bool {
    var i: i64 = 0;
    if t.len > 0 && (t[0] == '-' || t[0] == '+') { i = 1; }
    var dots: i64 = 0;
    var digits: i64 = 0;
    while i < t.len {
        if t[i] == '.' { dots += 1; }
        else if is_digit(t[i]) { digits += 1; }
        else { return false; }
        i += 1;
    }
    return digits > 0 && dots <= 1;
}

// value_ok checks the text of one leaf against its kind. The kinds that
// the table does not pin stay unchecked.
fn value_ok(kind: u8, arg: const u8[:], text: const u8[:]) -> bool {
    if kind == 'S' { return arg.len == 0 || arg_num(arg) == 0 || text.len <= arg_num(arg); }
    if kind == 'I' { return digits_ok(text); }
    if kind == 'B' { return text.len == 1 && (text[0] == 'Y' || text[0] == 'N'); }
    if kind == 'E' { return enum_member(text, arg_num(arg)); }
    if kind == 'T' { let _, _, _, ok = ofx_datetime(text); return ok; }
    if kind == 'D' { return decimal_ok(text); }
    if kind == 'C' { return text.len == 3; }
    if kind == 'K' { return country_known(text); }
    if kind == 'G' { return text.len == 3; }
    return true;
}

// check_tree_value checks one leaf node against one rule element.
fn check_tree_value(n: OfxNode, kind: u8, arg: const u8[:], req: bool, at: i64) -> Fault {
    if req && n.text.len == 0 {
        return fault(F_SYNTAX, at, 0, n.name, "a required element holds no text");
    }
    if n.text.len > 0 && !value_ok(kind, arg, n.text) {
        return fault(F_SYNTAX, at, 0, n.name, "the text of the element breaks its rule");
    }
    return no_fault();
}

// elem_more tells whether a row holds an element number k.
fn elem_more(row: const u8[:], k: i64) -> bool {
    let _, _, _, _, more = rule_elem(row, k);
    return more;
}

// elem_required tells whether the element number k of a row is required.
fn elem_required(row: const u8[:], k: i64) -> bool {
    let _, _, req, _, _ = rule_elem(row, k);
    return req;
}

// check_open_end checks the elements that a closed aggregate leaves
// unconsumed. A required element that never came is a fault.
fn check_open_end(row: const u8[:], pos: i64, name: const u8[:]) -> Fault {
    var k = pos;
    while elem_more(row, k) {
        if elem_required(row, k) {
            return fault(F_SYNTAX, 0, 0, name, "a required element is missing before the close");
        }
        k += 1;
    }
    return no_fault();
}

// push_opaque puts a marker on the stack. The checker does not look
// inside a subtree with a marker.
fn push_opaque(rows: i64[>..]&, poss: i64[>..]&, depths: i64[>..]&, d: i64) {
    rows.push(-1);
    poss.push(0);
    depths.push(d);
}

// check_ofx_tree checks every node of a tree against the rule table of
// the OFX specification. It gives the first fault. The line of the fault
// is the number of the node. A name that no row knows is allowed when it
// starts with the capital letter X: the specification keeps that range
// for private extensions, and the checker does not look inside it.
fn check_ofx_tree(tree: OfxNode[>..]&, lim: Limits&) -> Fault {
    let _ = lim;
    let root = find_rule("OFX");
    if root < 0 { return fault(F_UNKNOWN_TAG, 0, 0, "OFX", "the rule table holds no OFX row"); }
    var rows: i64[>..] = [root];
    var poss: i64[>..] = [0];
    var depths: i64[>..] = [-1];
    var i: i64 = 0;
    while i < tree.len {
        let n = tree[i];
        let d = n.depth as i64;
        let has_children = i + 1 < tree.len && (tree[i + 1].depth as i64) > d;
        while depths.len > 0 && depths[depths.len - 1] >= d {
            let r = rows[rows.len - 1];
            if r >= 0 {
                let f = check_open_end(OFX_RULE_ROWS[r], poss[poss.len - 1], OFX_RULE_NAMES[r]);
                if f.kind != F_NONE { return f; }
            }
            rows.pop();
            poss.pop();
            depths.pop();
        }
        if rows.len == 0 {
            return fault(F_SYNTAX, i + 1, 0, n.name, "an element stands outside the OFX root");
        }
        let top = rows.len - 1;
        let r = rows[top];
        if r < 0 {
            if d <= depths[top] {
                return fault(F_SYNTAX, i + 1, 0, n.name, "the depth does not step by one");
            }
            i += 1;
            continue;
        }
        if depths[top] + 1 != d {
            return fault(F_SYNTAX, i + 1, 0, n.name, "the depth does not step by one");
        }
        let row = OFX_RULE_ROWS[r];
        if row.len == 0 {
            push_opaque(rows, poss, depths, d);
            i += 1;
            continue;
        }
        var k = poss[top];
        var found = false;
        var kind: u8 = 'U';
        var req = false;
        var arg: const u8[:] = "";
        var more0 = elem_more(row, k);
        while more0 && !found {
            let t, kd, rq, ag, _ = rule_elem(row, k);
            if compare_bytes(n.name, t) == 0 {
                found = true;
                kind = kd;
                req = rq;
                arg = ag;
            } else {
                if rq {
                    return fault(F_SYNTAX, i + 1, 0, n.name, "a required element comes before this one");
                }
                k += 1;
                more0 = elem_more(row, k);
            }
        }
        if !found {
            let private = n.name.len > 0 && n.name[0] == 'X' && find_rule(n.name) < 0;
            if private {
                push_opaque(rows, poss, depths, d);
                i += 1;
                continue;
            }
            return fault(F_UNKNOWN_TAG, i + 1, 0, n.name, "the element is not allowed in this aggregate");
        }
        poss[top] = k + 1;
        if kind == 'A' || kind == 'L' {
            if !has_children {
                return fault(F_SYNTAX, i + 1, 0, n.name, "an aggregate holds no children");
            }
            let child = find_rule(arg);
            rows.push(child);
            poss.push(0);
            depths.push(d);
        } else {
            if has_children {
                return fault(F_SYNTAX, i + 1, 0, n.name, "a leaf holds children");
            }
            let f = check_tree_value(n, kind, arg, req, i + 1);
            if f.kind != F_NONE { return f; }
        }
        i += 1;
    }
    while depths.len > 0 {
        let r = rows[rows.len - 1];
        if r >= 0 {
            let f = check_open_end(OFX_RULE_ROWS[r], poss[poss.len - 1], OFX_RULE_NAMES[r]);
            if f.kind != F_NONE { return f; }
        }
        rows.pop();
        poss.pop();
        depths.pop();
    }
    return no_fault();
}
