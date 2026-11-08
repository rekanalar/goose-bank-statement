// Reads an MT942 interim report and prints its limits and totals.
// Run with: goose run examples/mt942.goose

import std;
import xml from "rekanalar/goose-xml@v2.0.0";
import bank_statement from "..";

fn main() {
    let text = ":20:INTERIM\n:25:ACC\n:28C:5/1\n:34F:EUR0,\n:13D:2501021530+0100\n:61:250102C500,00NTRFREF\n:61:250102D20,00NTRFREF2\n:90D:1EUR20,00\n:90C:1EUR500,00\n";
    let lim = bank_statement::default_limits();
    let opts = bank_statement::Mt940Options { .. };
    var sts: bank_statement::Statement[>..] = [];
    var ens: bank_statement::Entry[>..] = [];
    var bals: bank_statement::Balance[>..] = [];
    var notes: bank_statement::Note[>..] = [];
    let f = bank_statement::parse_mt940(text, lim, opts, sts, ens, bals, notes);
    if f.kind != 0 {
        print("error: ", bank_statement::kind_name(f.kind), " line ", f.line, " ", f.detail);
        return 1;
    }
    let st = sts[0];
    print("interim ", st.is_interim, " minutes ", st.report_minutes, " offset ", st.report_offset);
    print("debits ", st.debit_count, " total ", st.debit_total.minor);
    print("credits ", st.credit_count, " total ", st.credit_total.minor);

    // A total that does not match the entries is an error.
    let bad = ":20:I\n:34F:EUR0,\n:61:250102C500,00NTRFREF\n:90C:1EUR499,99\n";
    var sts2: bank_statement::Statement[>..] = [];
    var ens2: bank_statement::Entry[>..] = [];
    var bals2: bank_statement::Balance[>..] = [];
    var notes2: bank_statement::Note[>..] = [];
    let g = bank_statement::parse_mt940(bad, lim, opts, sts2, ens2, bals2, notes2);
    print("bad total: ", bank_statement::kind_name(g.kind), " tag ", g.tag);
    return 0;
}
