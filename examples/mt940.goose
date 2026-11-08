// Reads an MT940 statement and prints its balances and entries.
// Run with: goose run examples/mt940.goose

import std;
import xml from "rekanalar/goose-xml@v2.0.0";
import process from "rekanalar/goose-process@v1.0.0";
import bank_statement from "..";

fn main() {
    let text = ":20:STMT001\n:25:DE89370400440532013000\n:28C:00001/001\n:60F:C250101EUR1000,00\n:61:2501020102C500,00NTRFNONREF//BANKREF1\n:86:020?00BANK TRANSFER?20INVOICE 42?32ACME GMBH\n:61:250103D200,50NCHKCHK123\n:62F:C250103EUR1299,50\n";
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
    for st in sts {
        print("statement ", st.reference, " account ", st.account);
        print("  opening ", st.opening.amount.minor, " minor units ", st.opening.amount.currency);
        print("  closing ", st.closing.amount.minor, " minor units");
    }
    for e in ens {
        print("  ", e.mark, " ", e.amount.minor, " ", e.type_id, " ", e.customer_ref);
        var parts: bank_statement::NarrativeField[>..] = [];
        let kind, nf = bank_statement::split_narrative(e.narrative, lim, parts);
        for p in parts { print("      ", p.key, " = ", p.value); }
    }
    return 0;
}
