# goose-bank-statement

[![ci](https://github.com/rekanalar/goose-bank-statement/actions/workflows/ci.yml/badge.svg)](https://github.com/rekanalar/goose-bank-statement/actions/workflows/ci.yml)

Bank statement files for the [Goose](https://github.com/aardappel/goose) programming language.
The package reads SWIFT MT940 statements, SWIFT MT942 interim reports and QIF files.
It also reads the ISO 20022 XML documents camt.052, camt.053 and camt.054.
Pure Goose, no C. The package uses the standard library and the package `goose-xml`.

Money is an integer count of minor units with the exponent of its currency. The package uses no float.
Every parse is one linear pass with no recursion. Every size has a limit.

## Install

Add these two lines to the root file of the program that uses it:

```goose
import bank_statement from "rekanalar/goose-bank-statement@v0.3.0";
import xml from "rekanalar/goose-xml@v2.0.0";
```

The camt reader uses the package `goose-xml`. A package that needs another package
must have that package declared in the root file of the program.
If the second line is missing, the compiler names the line to add.

## API

Every parse call returns a `Fault`. A fault of kind `F_NONE` (0) means success. The arrays belong to the caller.
Text fields are spans over the input, so the input must outlive the arrays.

| Function | What it does |
|---|---|
| `parse_mt940(input, lim, opts, statements, entries, balances, notes)` | reads a file of MT940 or MT942 statements; gives a `Fault` |
| `split_narrative(raw, lim, out)` | splits a `:86:` text into `?NN` subfields or `/KEY/value/` pairs; gives `kind, Fault` |
| `parse_qif(input, lim, opts, records, splits, extra)` | reads a QIF file; gives a `Fault` |
| `parse_camt(input, lim, opts, statements, entries, balances, buf)` | reads a camt.052, camt.053 or camt.054 document; gives a `Fault` |
| `split_category(l)` | splits an `L` value into name, sub-category, class and transfer account |
| `parse_amount(text, exp, decimal, group)` | reads an amount into minor units; gives `Amount, Fault` |
| `parse_number(text, decimal, group)` | reads a decimal into a mantissa and a scale; the scale drops the zeros at the end of the decimal part; gives `i64, i32, Fault` |
| `currency_exponent(code)` | gives the count of minor digits of an ISO 4217 code; 2 for a code the table does not hold |
| `currency_known(code)` | tells whether a code sits in the ISO 4217 table |
| `default_limits()` | gives the safe limits |
| `kind_name(kind)` | gives the name of a fault kind |

### MT940 and MT942

A statement starts at `:20:`. The reader accepts the blocks `{1:}` to `{5:}` and a bare list of tags.
It reads these tags.
The tags are `:20:`, `:21:`, `:25:`, `:28:`, `:28C:`, `:34F:`, `:13D:` and `:60F:`.
They go on with `:60M:`, `:61:`, `:62F:`, `:62M:`, `:64:`, `:65:`, `:86:`, `:90D:`, `:90C:` and `:NS:`.

| Type | Holds |
|---|---|
| `Statement` | reference, related reference, account, number, sequence, opening, closing, closing available and forward available balance, ranges of entries, balances and notes, and the MT942 fields |
| `Entry` | value date, entry date, mark (`D`, `C`, `RD`, `RC`), funds code, amount, type id, customer reference, bank reference, supplementary detail and the raw `:86:` text |
| `Balance` | kind (opening, closing, available, forward), credit flag, intermediate flag, date and amount |
| `Note` | a `:NS:` field, or a `:86:` that belongs to no entry |
| `Amount` | `minor`, `exp` and `currency` |

The four balances of the statement are copies of the matching lines of the balance range.
A statement that holds none of them holds kind 0 in the field.
A second `:64:` is a fault. A second `:65:` replaces the value of the first.

`Mt940Options` holds one flag. `skip_balance_check` is false by default.

The check adds the opening balance and the entries. It compares the sum with the closing balance.
A credit adds. A debit subtracts.
The available and forward balances stay out of the check.

A reversal of a credit (`RC`) subtracts. A reversal of a debit (`RD`) adds.
A mismatch gives a fault of kind `F_BALANCE`. The fault holds both sums in `have` and `want`.

The check runs whenever a statement holds both balances. An interim report has no balances, so it has no check.
Its `:90D:` and `:90C:` totals must match the entries.

### camt.052, camt.053 and camt.054

The reader takes the XML documents of ISO 20022.
The package `goose-xml` reads the document into a tree, and this package walks that tree.
The message gives the kind of the statement.

The text of the document goes into the buffer of the caller.
The fields of the results point at that buffer, so the buffer must outlive the arrays.
The document itself may go away after the call.

| Message | Container | Statement |
|---|---|---|
| camt.052 | `Rpt` of `BkToCstmrAcctRpt` | interim |
| camt.053 | `Stmt` of `BkToCstmrStmt` | not interim |
| camt.054 | `Ntfctn` of `BkToCstmrDbtCdtNtfctn` | interim |

An element name matches after the namespace.
So any schema version from `.001.01` to `.001.14` parses, and any prefix works.
An element the reader does not know is ignored.

The fields of the statement come from these elements.

| Field | Element |
|---|---|
| `reference` | `Id` |
| `related_ref` | `MsgId` of the group header |
| `account` | `Acct/Id/IBAN`, or `Acct/Id/Othr/Id` |
| `number` | `ElctrncSeqNb` |
| `sequence` | `LglSeqNb` |
| `report_date`, `report_minutes`, `report_offset` | `CreDtTm` |

The type code of a balance gives its kind. The code text stays on every balance in `code`.

| Code | Kind |
|---|---|
| `OPBD` | opening |
| `CLBD` | closing |
| `OPAV`, `ITAV`, `CLAV` | available |
| `FWAV` | forward |
| any other code, and a `Prtry` code | no kind |

The typed fields of the statement take the `OPBD`, the `CLBD`, the `CLAV` and the `FWAV` balance.
A second balance of the same kind replaces the first.

The fields of an entry come from these elements.

| Field | Element |
|---|---|
| `amount` | `Amt` with its `Ccy` attribute |
| `mark` | `CdtDbtInd` |
| `value_date` | `ValDt` |
| `entry_date` | `BookgDt` |
| `status` | `Sts`, its text or the text of `Cd` or `Prtry` |
| `bank_ref` | `AcctSvcrRef` |
| `entry_ref` | `NtryRef` |
| `narrative` | `AddtlNtryInf` |
| `type_id` | `BkTxCd`, `Cd/Fmly/SubFmlyCd` or `Cd/Issr` |
| `customer_ref` | `Refs/EndToEndId` |
| `counter_name` | `Dbtr/Nm` for a credit entry, `Cdtr/Nm` for a debit entry |
| `counter_iban` | `DbtrAcct/Id/IBAN`, or `CdtrAcct/Id/IBAN` |
| `remittance` | the `Ustrd` lines of `RmtInf` |
| `batch_msg_id`, `batch_pmt_id`, `batch_count`, `batch_total` | `Btch` |

The text of an amount has no sign. The sign comes from the credit or debit code.
A reversal of a credit is `RC`. A reversal of a debit is `RD`.

`CamtOptions` holds one flag. `skip_balance_check` is false by default.

The balance check adds the opening balance and the booked entries.
It compares the sum with the closing balance.
The pending and the informational entries stay out of the check.
The check runs for a camt.053 that holds both booked balances.
A mismatch gives a fault of kind `F_BALANCE`.

The transaction summary of a report gives the credit and the debit totals.
The blocks `TtlCdtNtries` and `TtlDbtNtries` fill the totals of the statement.
The totals are checked against the entries, as the `:90C:` and `:90D:` totals of an MT942.

```goose
var sts: bank_statement::Statement[>..] = [];
var ens: bank_statement::Entry[>..] = [];
var bals: bank_statement::Balance[>..] = [];
var buf: u8[>..] = [];
let lim = bank_statement::default_limits();
let opts = bank_statement::CamtOptions { .. };
let f = bank_statement::parse_camt(text, lim, opts, sts, ens, bals, buf);
if f.kind != 0 { print(bank_statement::kind_name(f.kind), " in ", f.tag); }
```

### QIF

A line that starts with `!` opens a section. The reader knows these headers:
`!Account`, `!Type:Bank`, `!Type:Cash`, `!Type:CCard`, `!Type:Oth A`, `!Type:Oth L` and `!Type:Oth S`.
They go on with `!Type:Invst`, `!Type:Port`, `!Type:Invoice`, `!Type:Tax`, `!Type:Bill` and `!Type:Cat`.
They end with `!Type:Budget`, `!Type:Class`, `!Type:Tag`, `!Type:Security`, `!Type:Prices` and `!Type:Memorized`.

The lines `!Option:AutoSwitch` and `!Clear:AutoSwitch` are read and ignored.
The match takes any letter case. It takes a space instead of the colon after the word `type`,
as in the `!type bank` form. It takes a header without the blank too, such as `!Type:OthA`.
A header outside the list is a fault whose tag names the header of the file.

The transaction sections give a `QifRecord`. They are Bank, Cash, CCard, Oth A, Oth L and Oth S.
They are also Invst, Port, Invoice, Tax, Bill and Memorized.
A record holds date, amount, cleared mark, number, payee, memo, category,
splits and the investment fields.

The codes are `D`, `T`, `U`, `C`, `N`, `P`, `M`, `L` and `F`.
They go on with `S`, `E`, `$`, `%`, `Y`, `I`, `Q` and `O`.
The other sections keep every line as a `QifField`. A code with no typed field also becomes a `QifField`.
The reader drops no line.

The amount of a record comes from the `U` code when the record holds one.
Without a `U`, it comes from `T`. The order in the file does not matter. This is the rule of GnuCash.
`amount_code` names the code that won, and `alt_amount` holds the value that lost.
A money value that starts with `...` sets no amount; the line stays a field.

The investment codes give exact numbers, never a float.
`I` holds the price. `Q` holds the quantity. `O` holds the commission. The split `%` holds a percent.
Each one comes back as a `Rational` with a numerator and a positive denominator,
reduced to its smallest terms.

The reader accepts a plain decimal with the marks of the file.
It also accepts a whole fraction `1/2` and a mixed fraction `10 1/2`.
The text of each value stays in `price_text`, `quantity_text`,
`commission_text` and `percent_text`. The `F` code sets the `reimbursable` flag of the record
and keeps its text.

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

- **The camt reader reads the statements, not the whole message.** Java `prowide-iso20022` reads 14 versions of them. Python `camt053` reads four profiles. This package reads the statement, the balances, the entries and the transaction summary of the message.
- **A summary with one block for all the entries gives no total.** The block holds the sum of every entry. That sum has no sign. The reader ignores the block.
- **The XML tree of the document has no count limit.** The input limit of the package bounds it.
- **OFX 1.x and 2.x are not read.** Python `ofxtools`, Go `ofxgo` and Node `ofx-js` read them.
- **There is no writer.** `ofxtools` writes OFX and GnuCash writes QIF.
- **Fields are not checked against the SWIFT manual.** Node `@centrapay/swift-parser` fixes the width of each tag. An example is 16 characters for `:20:`. This package accepts a longer value. Real banks send one.
- **Bank dialects are not interpreted.** Python `mt940` ships processors for four Dutch banks. This package splits a `:86:` text and leaves the meaning to the caller.
- **There is no transcoding.** A byte above 127 passes through into the text. Node `@fin.cx/mt940` fixes the encoding of each field.
- **The QIF sections beyond the transactions keep no typed record.** They hold lines as `QifField` values. GnuCash gives each one a record of its own type.
- **A long tail of zeros is a fault.** A decimal part with 19 or more zeros at the end faults.
- **After a fault the arrays hold partial results.** Do not use them.

The release before read the `U` code of a QIF record as a plain field.
It kept only the text of the investment codes. A caller of `v0.1.0` who reads those fields
must read the new typed fields.

## Security

The package reads files from people you do not know. Every input is hostile.

Protections beyond the reference libraries:

- **A tag outside the set is a fault.** Python `mt940` drops `:60M:`, `:62M:`, `:64:` and `:65:` without a word. Go `mmalcek/mt940` checks nothing.
- **A statement that does not add up is a fault.** Python `mt940` has no balance check. The check is on by default.
- **Amounts are exact.** Go `evmar/fin` reads a QIF amount through a float and gets cents wrong, as in `8.11`. Python `quiffen` strips every comma. This package checks the groups of a thousands mark and the count of decimals.
- **The investment values are exact rationals.** Rust `qif_parser` reads the price, the quantity and the commission through a float. It loses digits. This package gives a numerator and a denominator and uses no float.
- **Overflow is a fault.** An amount, a sum of entries or a count never wraps. The value range ends at the largest and the most negative 64-bit integer, and both are valid amounts.
- **An ambiguous QIF date is a fault.** Rust `qif_parser` guesses the order. This package asks the caller, or reads the whole file.
- **Every size has a limit.** The limits cover the input, the line, the field and the nesting of blocks. They also cover the counts of statements, entries, splits, records and fields. Python `mt940` and `quiffen` cap none of them. Python `bankstatementparser` caps the file size only. `default_limits()` holds safe values.
- **A control byte is a fault.** A NUL byte never reaches a text field. A CR without an LF is a fault too.
- **An interim line cannot switch off the balance check.** A forged `:13D:` or `:34F:` line does not skip it.
- **No recursion, linear time.** A hostile file cannot overflow the stack or make the parser slow down.
- **No entity of a document expands.** The package `goose-xml` skips a doctype. It never expands an entity. An unknown entity is a fault. It also refuses a picture deeper than 256 levels. Java `prowide-iso20022` and Python `camt053` use a parser that reads a doctype with an internal subset.

Risks that stay:

- **The text of a remittance or a party name is untrusted.** The package does not escape it. Escape it yourself for HTML, SQL, a path or a command.

- **The text of a narrative, a payee or a memo is untrusted.** The package does not escape it. Escape it yourself for HTML, SQL, a path or a command.
- **The default input limit is 16 MiB.** Lower it when you read from a form upload.
- **`skip_balance_check` turns the balance protection off.** Use it only for a file you already trust.
- **The fault names the tag and the line, not the content.** The package does not mask account numbers. Do not log a statement.
- **The input must outlive the arrays.** The spans point into it.

## License

MIT
