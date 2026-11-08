# goose-bank-statement

[![ci](https://github.com/rekanalar/goose-bank-statement/actions/workflows/ci.yml/badge.svg)](https://github.com/rekanalar/goose-bank-statement/actions/workflows/ci.yml)

Bank statement files for the [Goose](https://github.com/aardappel/goose) programming language.
The package reads SWIFT MT940 statements, SWIFT MT942 interim reports and QIF files.
Pure Goose, no C, no dependency beyond the standard library.

Money is an integer count of minor units with the exponent of its currency. The package uses no float.
Every parse is one linear pass with no recursion. Every size has a limit.

## Install

Add this to the root file of the program that uses it:

```goose
import bank_statement from "rekanalar/goose-bank-statement@v0.1.0";
```

## API

Every parse call returns a `Fault`. A fault of kind `F_NONE` (0) means success. The arrays belong to the caller.
Text fields are spans over the input, so the input must outlive the arrays.

| Function | What it does |
|---|---|
| `parse_mt940(input, lim, opts, statements, entries, balances, notes)` | reads a file of MT940 or MT942 statements; gives a `Fault` |
| `split_narrative(raw, lim, out)` | splits a `:86:` text into `?NN` subfields or `/KEY/value/` pairs; gives `kind, Fault` |
| `parse_qif(input, lim, opts, records, splits, extra)` | reads a QIF file; gives a `Fault` |
| `split_category(l)` | splits an `L` value into name, sub-category, class and transfer account |
| `parse_amount(text, exp, decimal, group)` | reads an amount into minor units; gives `Amount, Fault` |
| `parse_number(text, decimal, group)` | reads a decimal into a mantissa and a scale; gives `i64, i32, Fault` |
| `currency_exponent(code)` | gives the count of minor digits of an ISO 4217 code |
| `default_limits()` | gives the safe limits |
| `kind_name(kind)` | gives the name of a fault kind |

### MT940 and MT942

A statement starts at `:20:`. The reader accepts the blocks `{1:}` to `{5:}` and a bare list of tags.
It reads these tags.
They are `:20:`, `:21:`, `:25:`, `:28:`, `:28C:`, `:34F:`, `:13D:`, `:60F:`, `:60M:`, `:61:`,
`:62F:`, `:62M:`, `:64:`, `:65:`, `:86:`, `:90D:`, `:90C:` and `:NS:`.

| Type | Holds |
|---|---|
| `Statement` | reference, related reference, account, number, sequence, opening and closing balance, ranges of entries, balances and notes, and the MT942 fields |
| `Entry` | value date, entry date, mark (`D`, `C`, `RD`, `RC`), funds code, amount, type id, customer reference, bank reference, supplementary detail and the raw `:86:` text |
| `Balance` | kind (opening, closing, available, forward), credit flag, intermediate flag, date and amount |
| `Note` | a `:NS:` field, or a `:86:` that belongs to no entry |
| `Amount` | `minor`, `exp` and `currency` |

`Mt940Options` holds one flag. `skip_balance_check` is false by default.

The check adds the opening balance and the entries. It compares the sum with the closing balance.
A credit adds. A debit subtracts.

A reversal of a credit (`RC`) subtracts. A reversal of a debit (`RD`) adds.
A mismatch gives a fault of kind `F_BALANCE`. The fault holds both sums in `have` and `want`.

The check runs whenever a statement holds both balances. An interim report has no balances, so it has no check.
Its `:90D:` and `:90C:` totals must match the entries.

### QIF

A line that starts with `!` opens a section. The reader knows these headers:
`!Account`, `!Type:Bank`, `!Type:Cash`, `!Type:CCard`, `!Type:Oth A`, `!Type:Oth L`, `!Type:Invst`,
`!Type:Port`, `!Type:Cat`, `!Type:Class`, `!Type:Security`, `!Type:Prices` and `!Type:Memorized`.
The lines `!Option:AutoSwitch` and `!Clear:AutoSwitch` are read and ignored.

The typed sections give a `QifRecord` with date, amount, cleared mark, number, payee, memo, category,
splits and the investment fields. The codes are `D`, `T`, `C`, `N`, `P`, `M`, `L`, `S`, `E`, `$`, `%`, `Y`, `I`, `Q` and `O`.
The other sections keep every line as a `QifField`. A code with no typed field also becomes a `QifField`.
The reader drops no line.

`QifOptions` holds four values. The zero value is the safe one.

| Field | Meaning |
|---|---|
| `date_order` | `DATE_AUTO` (default), `DATE_MDY`, `DATE_DMY`, `DATE_YMD` or `DATE_DETECT` |
| `decimal` | the decimal mark, `.` (default) or `,` |
| `pivot` | the first two-digit year that belongs to the 1900s; 70 by default |
| `currency` | an ISO 4217 code; it sets the count of minor digits (2 by default) |

QIF has no standard date form. With `DATE_AUTO`, a year of four digits means year first,
and a part above 12 gives the order. A date that fits two orders is a fault of kind `F_AMBIGUOUS_DATE`.
`DATE_DETECT` reads every date of the file and picks the one order that fits them all.
An apostrophe year (`12/31'25`) means 2000 or later.

```goose
var sts: bank_statement::Statement[>..] = [];
var ens: bank_statement::Entry[>..] = [];
var bals: bank_statement::Balance[>..] = [];
var notes: bank_statement::Note[>..] = [];
let lim = bank_statement::default_limits();
let opts = bank_statement::Mt940Options { .. };
let f = bank_statement::parse_mt940(text, lim, opts, sts, ens, bals, notes);
if f.kind != 0 { print(bank_statement::kind_name(f.kind), " at line ", f.line); }
```

## Limits

This package is below `v1.0.0`. These gaps against the reference libraries stay open.

- **camt.052, camt.053 and camt.054 are not read.** Java `prowide-iso20022` reads 14 versions of them. Python `camt053` reads four profiles.
- **OFX 1.x and 2.x are not read.** Python `ofxtools`, Go `ofxgo` and Node `ofx-js` read them.
- **There is no writer.** `ofxtools` writes OFX and GnuCash writes QIF.
- **Fields are not checked against the SWIFT manual.** Node `@centrapay/swift-parser` fixes the width of each tag. An example is 16 characters for `:20:`. This package accepts a longer value. Real banks send one.
- **Bank dialects are not interpreted.** Python `mt940` ships processors for four Dutch banks. This package splits a `:86:` text and leaves the meaning to the caller.
- **There is no transcoding.** A byte above 127 passes through into the text. Node `@fin.cx/mt940` fixes the encoding of each field.
- **The currency table is small.** It holds the 17 currencies with no minor digits and the 7 with three. Every other code has two.
- **Only the listed QIF headers are known.** Another `!Type:` header gives a fault.
- **The `U` code is kept as a field.** The amount of a record comes from `T`.
- **Price, quantity, commission and percent stay as text.** `parse_number` reads them. A price in fractions, such as `10 1/2`, stays text.
- **The `:64:` and `:65:` balances sit in the balance range.** The statement copies the opening and closing balance only.
- **The most negative `i64` is not an amount.** The digits add up as a positive number. That value is an overflow fault.
- **After a fault the arrays hold partial results.** Do not use them.

## Security

The package reads files from people you do not know. Every input is hostile.

Protections beyond the reference libraries:

- **A tag outside the set is a fault.** Python `mt940` drops `:60M:`, `:62M:`, `:64:` and `:65:` without a word. Go `mmalcek/mt940` checks nothing.
- **A statement that does not add up is a fault.** Python `mt940` has no balance check. The check is on by default.
- **Amounts are exact.** Go `evmar/fin` reads a QIF amount through a float and gets cents wrong, as in `8.11`. Python `quiffen` strips every comma. This package checks the groups of a thousands mark and the count of decimals.
- **Overflow is a fault.** An amount, a sum of entries or a count never wraps.
- **An ambiguous QIF date is a fault.** Rust `qif_parser` guesses the order. This package asks the caller, or reads the whole file.
- **Every size has a limit.** The limits cover the input, the line, the field and the nesting of blocks. They also cover the counts of statements, entries, splits, records and fields. Python `mt940` and `quiffen` cap none of them. Python `bankstatementparser` caps the file size only. `default_limits()` holds safe values.
- **A control byte is a fault.** A NUL byte never reaches a text field. A CR without an LF is a fault too.
- **An interim line cannot switch off the balance check.** A forged `:13D:` or `:34F:` line does not skip it.
- **No recursion, linear time.** A hostile file cannot overflow the stack or make the parser slow down.
- **No XML.** This release reads no XML, so entity expansion has no place to happen.

Risks that stay:

- **The text of a narrative, a payee or a memo is untrusted.** The package does not escape it. Escape it yourself for HTML, SQL, a path or a command.
- **The default input limit is 16 MiB.** Lower it when you read from a form upload.
- **`skip_balance_check` turns the balance protection off.** Use it only for a file you already trust.
- **The fault names the tag and the line, not the content.** The package does not mask account numbers. Do not log a statement.
- **The input must outlive the arrays.** The spans point into it.

## License

MIT
