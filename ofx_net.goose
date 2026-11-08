// The OFX network client.
//
// ofx_fetch sends an OFX request over HTTPS and appends the body of the
// answer. It runs the curl program of the system as a child process, so
// the TLS stack of the system does the crypto. The caller builds a
// request with write_ofx_tree and parses the body with parse_ofx or
// parse_ofx_tree. The call gives the HTTP status code of the answer, or
// a fault.
namespace bank_statement;

import fault;
import limits;
import write_text;
import process;

// OfxFetch holds the settings of one request. The URL must be an HTTPS
// URL. The time limit is in milliseconds; 0 means no limit. The type of
// the content defaults to the type of the OFX 1.x form.
struct OfxFetch {
    url: const u8[:],
    timeout_ms: i32,
    content_type: const u8[:],
    user_agent: const u8[:],
}

// url_ok tells whether a URL is safe to hand to curl. It must be an
// HTTPS URL and hold no space and no control byte. The child runs
// without a shell, so a URL cannot inject a command; the check keeps a
// broken URL out all the same.
fn url_ok(u: const u8[:]) -> bool {
    if u.len < 9 { return false; }
    if u[0] != 'h' || u[1] != 't' || u[2] != 't' || u[3] != 'p' || u[4] != 's' { return false; }
    if u[5] != ':' || u[6] != '/' || u[7] != '/' { return false; }
    for c in u {
        if c <= ' ' || c >= 127 { return false; }
    }
    return true;
}

// put_num_text appends the decimal text of a number.
fn put_num_text(buf: u8[>..]&, v: i64) {
    put_num(buf, v, 1);
}

// ofx_fetch sends one request. The request holds OFX text. The body of
// the answer lands in out, without the status line. The size of the
// answer never passes max_input. The status code of the HTTP answer
// comes back, with F_NONE on success.
fn ofx_fetch(request: const u8[:], opts: OfxFetch, lim: Limits&, out: u8[>..]&, buf: u8[>..]&) -> i32, Fault {
    if !url_ok(opts.url) {
        return 0, fault(F_SYNTAX, 0, 0, "url", "the URL is not an HTTPS URL without spaces");
    }
    let fi = check_input(request, lim);
    if fi.kind != F_NONE { return 0, fi; }
    var ct = opts.content_type;
    if ct.len == 0 { ct = "application/x-ofx"; }
    var args: const u8[:][>..] = ["-sS", "-X", "POST"];
    // The headers live in the buffer of the caller.
    let h1 = buf.len;
    put(buf, "Content-Type: ");
    put(buf, ct);
    args.push(buf[h1..]);
    if opts.user_agent.len > 0 {
        let h2 = buf.len;
        put(buf, "User-Agent: ");
        put(buf, opts.user_agent);
        args.push(buf[h2..]);
    }
    // The body comes from the standard input, capped in size.
    args.push("--data-binary");
    args.push("@-");
    let h3 = buf.len;
    put_num_text(buf, lim.max_input);
    args.push("--max-filesize");
    args.push(buf[h3..]);
    // The time limit in seconds, rounded up. The child gets a slack, so
    // curl can report its own limit first.
    if opts.timeout_ms > 0 {
        let secs = ((opts.timeout_ms as i64) + 999) / 1000;
        let h4 = buf.len;
        put_num_text(buf, secs);
        args.push("--max-time");
        args.push(buf[h4..]);
    }
    // The status code lands after the body, behind a line end.
    args.push("-w");
    args.push("\n%{http_code}");
    args.push(opts.url);
    var err: u8[>..] = [];
    var popts = process::options();
    if opts.timeout_ms > 0 { popts.timeout_ms = opts.timeout_ms + 10000; }
    let oc = process::run_split("curl", args, request, popts, out, err);
    if oc.status == process::NOT_STARTED {
        return 0, fault(F_SYNTAX, 0, 0, "curl", "the curl program did not start");
    }
    if oc.status != process::ENDED || oc.code != 0 {
        return 0, fault(F_SYNTAX, 0, 0, "curl", "the request failed");
    }
    // The status code sits at the end. The digits come off one by one.
    var code: i64 = 0;
    var mul: i64 = 1;
    var got = false;
    while out.len > 0 {
        let c = out[out.len - 1];
        if c < '0' || c > '9' { break; }
        code += (c - '0') as i64 * mul;
        mul = mul * 10;
        got = true;
        out.pop();
    }
    if got && out.len > 0 && out[out.len - 1] == '\n' { out.pop(); }
    if !got {
        return 0, fault(F_SYNTAX, 0, 0, "curl", "the answer holds no status code");
    }
    return code as i32, no_fault();
}
