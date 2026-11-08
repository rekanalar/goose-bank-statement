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
