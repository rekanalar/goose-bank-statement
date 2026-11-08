# goose-bank-statement

[![ci](https://github.com/rekanalar/goose-bank-statement/actions/workflows/ci.yml/badge.svg)](https://github.com/rekanalar/goose-bank-statement/actions/workflows/ci.yml)

Bank statement files for the [Goose](https://github.com/aardappel/goose) programming language.
The package reads SWIFT MT940 statements, SWIFT MT942 interim reports and QIF files.
It also reads the ISO 20022 XML documents camt.052, camt.053 and camt.054.
It reads the OFX 1.x and OFX 2.x files of the banks of North America.
It writes QIF, OFX and MT940.

Pure Goose, no C. The package uses the standard library and the package `goose-xml`.

Money is an integer count of minor units with the exponent of its currency. The package uses no float.
Every parse is one linear pass with no recursion. Every size has a limit.

## Install

Add these two lines to the root file of the program that uses it:

```goose
import bank_statement from "rekanalar/goose-bank-statement@v0.22.0";
import xml from "rekanalar/goose-xml@v2.0.0";
```

The camt reader uses the package `goose-xml`. The network client uses the package `goose-process`.
A package that needs another package must have that package declared in the root file of the program.
If the second line is missing, the compiler names the line to add.

## API

Every parse call returns a `Fault`. A fault of kind `F_NONE` (0) means success. The arrays belong to the caller.
Text fields are spans over the input, so the input must outlive the arrays.

| Function | What it does |
|---|---|
| `parse_mt940(input, lim, opts, statements, entries, balances, notes)` | reads a file of MT940 or MT942 statements; gives a `Fault` |
| `split_narrative(raw, lim, out)` | splits a `:86:` text into `?NN` subfields or `/KEY/value/` pairs; gives `kind, Fault` |
| `parse_qif(input, lim, opts, records, splits, extra)` | reads a QIF file; gives a `Fault` |
| `parse_camt(input, lim, opts, header, statements, entries, balances, buf)` | reads a camt.052, camt.053 or camt.054 document with its group header; gives a `Fault` |
| `parse_ofx(input, lim, opts, statements, entries, balances, notes, buf)` | reads an OFX 1.x or OFX 2.x file; gives a `Fault` |
| `parse_ofx_securities(input, lim, securities, notes, buf)` | reads the security list of an OFX file; gives a `Fault` |
| `write_ofx_securities(securities, notes, opts, lim, out)` | appends a security list as an OFX file; gives a `Fault` |
| `parse_ofx_profile(input, lim, profile, signons, sets, notes, buf)` | reads the profile response of an OFX file; gives a `Fault` |
| `parse_ofx_tree(input, lim, tree, buf)` | reads every element under the OFX root into a flat list of `OfxNode`; gives a `Fault` |
| `write_ofx_tree(tree, opts, lim, out)` | appends an OFX file from a list of `OfxNode`; checks each element against the rules; gives a `Fault` |
| `check_ofx_tree(tree, lim)` | checks a list of `OfxNode` against the element rules of OFX; gives the first `Fault` |
| `ofx_fetch(request, opts, lim, out, buf)` | sends an OFX request over HTTPS with `curl` and appends the body; gives the status code and a `Fault` |
| `parse_dialect(kind, text, lim, values, buffer)` | reads the named values of a `:86:` text of a Dutch bank; gives a `Fault` |
| `parse_qif_lists(input, lim, opts, items, budgets, lines, extra, prices)` | reads the list sections of a QIF file into typed records; gives a `Fault` |
| `write_qif(records, splits, extra, opts, lim, out)` | appends a QIF file to `out`; gives a `Fault` |
| `write_qif_lists(items, budgets, lines, extra, prices, opts, lim, out)` | appends the typed list records of a QIF file to `out`; gives a `Fault` |
| `write_ofx(statements, entries, notes, opts, lim, out)` | appends an OFX 1.x or 2.x file to `out`; gives a `Fault` |
| `write_mt940(statements, entries, lim, out)` | appends MT940 statements to `out`; gives a `Fault` |
| `decode_charset(kind, input, lim, out)` | turns Windows-1252 or ISO-8859-1 bytes into UTF-8; gives a `Fault` |
| `encode_charset(kind, input, lim, out)` | turns UTF-8 into Windows-1252 or ISO-8859-1 bytes; gives a `Fault` |
| `header_charset(input)` | reads the `CHARSET` line of an OFX 1.x header; gives `CS_CP1252`, `CS_LATIN1` or 0 |
| `split_category(l)` | splits an `L` value into name, sub-category, class and transfer account |
| `parse_amount(text, exp, decimal, group)` | reads an amount into minor units; gives `Amount, Fault` |
| `parse_number(text, decimal, group)` | reads a decimal into a mantissa and a scale; the scale drops the zeros at the end of the decimal part; gives `i64, i32, Fault` |
| `currency_exponent(code)` | gives the count of minor digits of an ISO 4217 code; 2 for a code the table does not hold |
| `currency_known(code)` | tells whether a code sits in the ISO 4217 table |
| `country_known(code)` | tells whether a code sits in the ISO 3166 alpha-3 table |
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
| `Entry` | value date, entry date, mark (`D`, `C`, `RD`, `RC`), funds code, amount, type id, customer reference, bank reference, supplementary detail, the raw `:86:` text and the OFX member `ofx` |
| `Balance` | kind (opening, closing, available, forward), credit flag, intermediate flag, date and amount |
| `Note` | a `:NS:` field, or a `:86:` that belongs to no entry |
| `Amount` | `minor`, `exp` and `currency` |

The four balances of the statement are copies of the matching lines of the balance range.
A statement that holds none of them holds kind 0 in the field.
A second `:64:` is a fault. A second `:65:` replaces the value of the first.

`Mt940Options` holds two flags and a style. `skip_balance_check` and `check_fields` are false by default. `style` is `STYLE_SWIFT` by default.

#### The field rules of the SWIFT manual

The flag `check_fields` turns on the field rules of the manual. It adds faults. It never changes a value.
Banks send fields that are longer than the manual allows, so the flag is off by default.
Turn it on for the banks that keep the manual.

The `style` option picks the widths of the `:61:` line under `check_fields`.
`STYLE_ASNB` lets the customer reference hold 34 characters, as ASN Bank sends it.

`STYLE_GLS` is the style of GLS and Atruvia. The customer reference and the supplementary text have any length.
The bank reference holds 23 characters.

Python `mt940` 5.1.3 holds these two as opt-in patterns of the `:61:` tag.
An unknown style is a fault. The writer keeps the widths of the manual.

| Field | Rule |
|---|---|
| `:20:`, `:21:` | at most 16 characters |
| `:25:` | at most 35 characters |
| `:28:`, `:28C:` | up to three parts of digits, at most 5 digits each |
| `:34F:`, `:60F:`, `:60M:`, `:62F:`, `:62M:`, `:64:`, `:65:` | the amount has at most 16 characters and 15 digits |
| `:61:` | the amount follows that rule; the customer reference and the bank reference have at most 16 characters; the supplementary text has at most 34 |
| `:86:` | at most 6 lines of at most 65 characters |
| `:90D:`, `:90C:` | the count has at most 5 digits; the amount follows the rule above |
| `:20:`, `:21:`, `:25:`, `:86:` | only the characters of the SWIFT set: letters of both cases, digits, the space and `/ - ? : ( ) . , ' + { }` |

The tags must come in the order of the manual. First come `:20:`, `:21:`, `:25:` and `:28C:`.
Then come `:34F:`, `:13D:`, the opening balance, and the entries with their `:86:` fields.
Last come the closing balance, the two available balances and the totals.

A `:NS:` field may stand anywhere. A statement without `:25:` or without `:28C:` is a fault.
Every fault is of kind `F_SYNTAX` and names the tag and the line.

Node `@centrapay/swift-parser` cuts a value that is too long and says nothing.
The Rust crate `mt940` refuses the whole message. This package refuses the file and names the tag.

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

The header of the message is a `CamtHeader`. It holds the kind, the message id, and the creation date and time with the offset.
It holds the entry count, the additional information, and the names of the initiator and the recipient.
The entry count and the names stay text. A field that the message holds not stays empty.

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
var hd = bank_statement::CamtHeader { .. };
let f = bank_statement::parse_camt(text, lim, opts, hd, sts, ens, bals, buf);
if f.kind != 0 { print(bank_statement::kind_name(f.kind), " in ", f.tag); }
```

### OFX

The reader takes the OFX files of the banks of North America.
It reads the header, the tag tree and the statement message sets.
The OFX 1.x body is SGML: a leaf tag holds its text and often has no
closing tag. The reader holds the leaf list of the OFX 1.0.3 DTD for
this, as the Go reference does.

The header of version 1 is the nine `KEY:VALUE` lines.
The reader skips blank lines and accepts a space after the colon.
It accepts all fields on one line and a missing blank line after the
header. It accepts LF, CRLF and CR line ends.
The header of version 2 is the `<?xml?>` declaration and the `<?OFX?>`
instruction.

| Header field | Values |
|---|---|
| `OFXHEADER` | 100 for version 1, 200 for version 2 |
| `DATA` | `OFXSGML` |
| `VERSION` | 102, 103, 151, 160 for version 1; 200 to 220 for version 2 |
| `SECURITY` | `NONE` or `TYPE1` |
| `ENCODING` | `USASCII`, `UNICODE` or `UTF-8` |
| `CHARSET` | `NONE`, `1252` or `ISO-8859-1` |
| `COMPRESSION` | `NONE` |

A bank statement gives one statement. A credit card statement gives one
statement. An investment statement gives one statement.

| Field | Element |
|---|---|
| `reference` | `TRNUID` |
| `account` | `BANKACCTFROM/ACCTID` or `CCACCTFROM/ACCTID` |
| `account` | `INVACCTFROM/BROKERID:ACCTID` for an investment statement |
| `amount` | `TRNAMT` with the exponent of `CURDEF` |
| `mark` | the sign of `TRNAMT`: a negative amount is a debit |
| `value_date` | `DTPOSTED` |
| `entry_date` | `DTAVAIL` |
| `entry_ref` | `FITID` |
| `bank_ref` | `SRVRTID` |
| `customer_ref` | `CHECKNUM` |
| `supplementary` | `REFNUM` |
| `type_id` | `TRNTYPE` |
| `counter_name` | `NAME` or `PAYEE/NAME` |
| `narrative` | `MEMO` |
| `closing` | `LEDGERBAL` |
| `available` | `AVAILBAL` |

The signon status comes back as a note with the tag `SONRS`.
The value holds the code, the severity and the message.
The bank id and the account type come back as notes.
A status of severity `ERROR` does not stop the read of the statements.

An investment transaction gives an entry. The type text names the kind
of the transaction, such as `BUYSTOCK` or `INCOME/DIV`.
The money fields are exact rationals, and their texts stay as given.

| Field | Element |
|---|---|
| `units` | `UNITS` |
| `unit_price` | `UNITPRICE` |
| `commission` | `COMMISSION` |
| `total` | `TOTAL` |
| `amount` | `TOTAL` when it fits the currency of the statement |
| `entry_ref` | `INVTRAN/FITID` |
| `value_date` | `INVTRAN/DTTRADE` |
| `entry_date` | `INVTRAN/DTSETTLE` |

A position gives an entry. The type text names the kind, such as
`POSSTOCK`. The units and the unit price come from the position, and
the market value is the amount.

The date of the OFX spec is `YYYYMMDD[HHMM[SS[.XXX]]][[+H[.MM][:TZ]]]`.
The reader reads the minutes of a dotted offset: `[-5.30]` is 5 hours
30 minutes. The Go reference reads hundredths of an hour there.
The reader follows the Python reference and the real bank files.
A date with no zone means GMT.

The amount of a statement is exact. A comma is a decimal separator only
when the text holds no dot. An exponent, a NaN and two marks are faults.

`OfxOptions` holds two flags. Both are false by default.
`skip_pending` drops the pending list. Without it, the pending list gives entries like the booked list.
`check_country` refuses a `COUNTRY` that is not an ISO 3166 alpha-3 code.

```goose
var sts: bank_statement::Statement[>..] = [];
var ens: bank_statement::Entry[>..] = [];
var bals: bank_statement::Balance[>..] = [];
var notes: bank_statement::Note[>..] = [];
var buf: u8[>..] = [];
let lim = bank_statement::default_limits();
let opts = bank_statement::OfxOptions { .. };
let f = bank_statement::parse_ofx(text, lim, opts, sts, ens, bals, notes, buf);
if f.kind != 0 { print(bank_statement::kind_name(f.kind), " in ", f.tag); }
```

#### The extra fields of an OFX transaction

The member `ofx` of an `Entry` holds the OFX fields that no other format has.
Every other reader gives it the empty value from `no_ofx()`.

| Member | OFX element |
|---|---|
| `user_date` | `DTUSER` |
| `correct_ref`, `correct_action` | `CORRECTFITID`, `CORRECTACTION` (`REPLACE` or `DELETE`) |
| `payee_id`, `ext_name` | `PAYEEID`, `EXTDNAME` |
| `has_payee`, `payee` | the `PAYEE` aggregate: name, three address lines, city, state, postal code, country, phone |
| `rate_kind`, `rate`, `rate_text`, `rate_symbol` | `CURRENCY` (kind `C`) or `ORIGCURRENCY` (kind `O`) with `CURRATE` and `CURSYM` |
| `has_sic`, `sic` | `SIC` |
| `acct_to_kind`, `acct_to` | `BANKACCTTO` (kind `B`) or `CCACCTTO` (kind `C`) |
| `inv401k_source` | `INV401KSOURCE` |
| `image`, `image2`, `image_count` | the first and the second `IMAGEDATA` aggregate and the count of the aggregates |

The rate is an exact rational. Its text stays in `rate_text`. A rate of zero is a fault.
`CURRENCY` gives the currency of the amount. The reader then reads `TRNAMT` with the minor digits of that currency.
`ORIGCURRENCY` leaves the currency of the statement.

The reader refuses `NAME` together with `PAYEE`. It refuses `CURRENCY` together with `ORIGCURRENCY`.
It refuses `BANKACCTTO` together with `CCACCTTO`.
The writer writes the fields in the order of the OFX specification and checks the limits of Python `ofxtools`.

Those limits are `PAYEEID` 12, `EXTDNAME` 100, `CORRECTFITID` 255 and the `PAYEE` fields 32, 5 and 11.
A `PAYEE` needs its name, first address line, city, state, postal code and phone.
The country is a code of the table `COUNTRY_CODES`: 250 ISO 3166-1 alpha-3 codes from Python `ofxtools`. `country_known(code)` tells whether a code is in it.

The table holds `ANT`, a retired code, and no code for Kosovo. Go `ofxgo` checks the length only. The writer follows `ofxtools` and refuses an unknown code.
A correction needs both `CORRECTFITID` and `CORRECTACTION`.

The `SIC` code is a number of one to nine digits.
The `acct_to` member holds the bank id, the branch id, the account id, the account type and the account key.
The account type is one of `CHECKING`, `SAVINGS`, `MONEYMRKT`, `CREDITLINE` and `CD`.
The `CCACCTTO` aggregate holds the account id and the account key only.
The `INV401KSOURCE` is one of `PRETAX`, `AFTERTAX`, `MATCH`, `PROFITSHARING`, `ROLLOVER`, `OTHERVEST` and `OTHERNONVEST`.

The `image` member holds the type, the reference and the reference type.
It also holds the delay, the availability date, the time to live and the check side.

The image type is one of `STATEMENT`, `TRANSACTION` and `TAX`.
The reference type is one of `OPAQUE`, `URL` and `FORMURL`.
The check side is one of `FRONTONLY`, `BACKONLY` and `FRONTANDBACK`.
The `IMAGEDELAY` and the `DTIMAGEAVAIL` exclude each other.

The reader keeps up to two `IMAGEDATA` aggregates: the front and the back of a check.
The writer writes as many images as `image_count` says.
A third aggregate is a fault. Go `ofxgo` allows two at most.

Python `ofxtools` marks `IMAGEDATA` as unsupported. Go `ofxgo` reads it.
This package reads it and writes it.

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
`parse_qif` keeps the lines of the list sections as `QifField` values. A code with no typed field also becomes a `QifField`.
The reader drops no line.

`parse_qif_lists` reads the list sections into named fields. It skips the transaction sections.
Each record gives a `QifItem`. Each line of the Prices section gives a `QifPrice`.

| Section | Codes |
|---|---|
| `!Account` | `N` name, `T` type, `D` description, `L` credit limit, `/` statement balance date, `$` statement balance |
| `!Type:Cat` and `!Type:Budget` | `N` name, `D` description, `T` tax flag, `I` income flag, `E` expense flag, `R` tax schedule, `B` budget amounts |
| `!Type:Class` | `N` name, `D` description, `R` tax schedule |
| `!Type:Security` | `N` name, `S` symbol, `T` type, `G` goal |
| `!Type:Tag` | `N` name, `D` description |
| `!Type:Payee` | `P` name, `A` address lines, `C` city, `S` state, `Z` zip, `Y` country, `N` phone, `#` account |
| `!Type:Prices` | one line `"symbol",price,"date"` for each price, each one followed by `^` |

The budget amounts of a category are a range of the array `budgets`.
The address lines of a payee are a range of the array `lines`.

A price is an exact `Rational`; its text stays in `price_text`. A comma inside the quotes of a symbol does not split the line.
A code that the section does not know, and a scalar line that repeats, stay as fields in `extra`.
A record without a closing `^` before the next header or the end of the file is kept.
`DATE_DETECT` reads like `DATE_AUTO` for the lists: each date is read alone, and an ambiguous date is a fault.

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

#### The bank dialects of the :86: field

Four Dutch banks and mBank write named values into the `:86:` text. Python `mt940` is the only mature library that reads them.
`parse_dialect(kind, text, limits, values, buffer)` reads one `:86:` text. It fills an array of `DialectValue` with a `key` and a `value`.
The names keep the names of the Python library.

| Kind | Keys |
|---|---|
| `D_RABOBANK` | `marf`, `eref`, `pref`, `trcd`, `benm`, `ordp`, `name`, `id`, `addr`, `remi`, `cdtrref`, `csid`, `isdt`, `rtrn` |
| `D_ABN_AMRO` | `account`, `trtp`, `iban`, `bic`, `csid`, `name`, `remi`, `eref`, `ordp`, `benm` |
| `D_ING` | `rtrn`, `eref`, `pref`, `marf`, `csid`, `purp`, and the parts `cntp.account_number`, `cntp.bic`, `cntp.name`, `cntp.city`, `remi.code`, `remi.issuer`, `remi.remittance_info`, `ultc.name`, `ultc.id`, `ultd.name`, `ultd.id` |
| `D_REGIOBANK` | `account_number`, `name`, `address`, `iban`, `remittance_info`, `description`, `reference` |
| `D_MBANK` | `transaction_code`, `iph_id`, `tnr` |

A text of another bank gives no value and no fault. An unknown kind is a fault.

The count of values has the limit `max_fields`. The text has the limit `max_field`.

The values point into the text or into the buffer. Both must outlive the values.
The ABN AMRO account number loses its dots, so it goes into the buffer.
This package keeps scanning the tags after the account number. Python `mt940` stops there, so this package may give more values.

### Transcoding

The readers keep the bytes of a text as they are. Banks send files in Windows-1252 or ISO-8859-1.
Turn such a file into UTF-8 before you read it. Use `decode_charset` with `CS_CP1252` or `CS_LATIN1`.
For an OFX 1.x file, `header_charset` reads the `CHARSET` line and tells which one to use.
`encode_charset` does the reverse for a bank that wants a legacy file.

Windows-1252 leaves five bytes undefined: `0x81`, `0x8D`, `0x8F`, `0x90` and `0x9D`.
Python `codecs` refuses them. The WHATWG standard maps them to control characters.

This package refuses them. A control character in a statement is a defect of the file.
A character that the charset lacks is a fault. The package never replaces and never drops a character.

### Writers

Each writer takes the arrays that the matching reader gives. It appends text to a `u8[>..]` buffer of the caller.
What a writer writes, the reader reads back to the same values.
A fault leaves partial text in the buffer. Do not use it.

Every writer checks each text before it writes the text. It never cuts a text and never repairs one.
A control byte is a fault. A text that is too long is a fault. The output has the limit `max_input`.

**QIF.** `write_qif` writes the sections Bank, Cash, CCard, Oth A and Oth L. It writes the list sections from their fields.

`write_qif_lists` writes the typed list records and the prices. A name is required. A price needs a symbol without a quote.
The writer writes a price as a decimal or as a fraction `n/d`.
It takes the decimal when the denominator is a power of ten.
A record writes `D`, `T`, `U`, `C`, `N`, `P`, `M`, `L`, the splits and `F`.

It also writes the extra fields, such as the `A` lines. Each address line is one `A` line.
`QifWriteOptions.date_order` is `DATE_MDY` (the default), `DATE_DMY` or `DATE_YMD`.

The splits must add up to the amount, or the writer gives `F_TOTAL`.
A field code is a printable byte. It is not `!` and not `^`.

**OFX.** `write_ofx` writes bank statements. With `credit_card` it writes credit card statements.
Version 1.x writes the header with CRLF and a blank line, and leaves the leaf tags open. The default version is 1.0.2.
Version 2.x writes the XML declaration, the OFX instruction and closed leaves.

`close_leaves` closes the leaves in 1.x. `indent` writes one tag per line.
The server date is an option, because the writer reads no clock. Dates carry the time `000000.000[0:GMT]`.

A statement needs a closing balance. The writer writes `LEDGERBAL` from it and `AVAILBAL` from the available balance.

The OFX writer checks `TRNTYPE`, `ACCTTYPE`, the currency, the version and the required fields.
It also checks the limit of each text, in bytes.
The limits are `NAME` 32, `MEMO` 255 and `FITID` 255.
They are `CHECKNUM` 12, `REFNUM` 32 and `SRVRTID` 10.
They are `ACCTID` 22, `BANKID` 9 and `TRNUID` 36.

**MT940.** `write_mt940` writes `:20:`, `:21:`, `:25:`, `:28C:`, `:60F:`, the entries with `:86:`, `:62F:`, `:64:` and `:65:`.
It applies the field rules of the SWIFT manual. Those rules cover the widths and the character set.
They also limit a narrative to 6 lines of 65 characters.
The amount has a comma. The years run from 1970 to 2069.

The writer checks that the opening balance and the entries add up to the closing balance, or it gives `F_BALANCE`.

An entry needs the mark and a type of four characters that starts with S, N or F.
An empty customer reference becomes `NONREF`.

**MT942.** `write_mt940` writes an interim report when the statement holds no balance.
The report holds `:20:`, `:21:`, `:25:` and `:28C:`.
It holds one or two `:34F:` lines, the `:13D:` line and the entries with `:86:`.
It holds the totals `:90D:` and `:90C:`.

The `:34F:` line holds the currency, an optional `D` or `C` mark and the amount.
The `:13D:` line holds the date, the time, a sign and the offset from the Greenwich time.
The `:90D:` and `:90C:` lines hold a count, a currency and an amount.

The writer checks the totals against the entries, or it gives `F_TOTAL`.
A report needs a floor limit, because its currency is the currency of its entries.
A report holds no balance, so a statement that carries one is a fault.

**OFX security list.** `parse_ofx_securities` reads `STOCKINFO`, `MFINFO`, `DEBTINFO`, `OPTINFO` and `OTHERINFO`.
Each one gives an `OfxSecurity`: id, id type, name, ticker, FIID, rating, memo, currency symbol, price and price date.
The price is an exact `Rational`; its text stays in `price_text`.
Every other leaf of the aggregate is a `Note`, so no value is lost. The notes of a security are a range of the array `notes`.

`write_ofx_securities` writes the securities back as a list. It checks every field against the rules before it writes.
An unknown kind is a fault. So is an empty id, a name over 120 bytes, and a currency that is not three letters.
The price becomes an exact decimal, or a fault when no decimal form exists.

The notes of a security come back as the leaves outside `SECINFO`. The writer escapes every text.

**OFX element tree.** The package has typed records for bank and credit card statements only.
`parse_ofx_tree` and `write_ofx_tree` cover every other message set: the investment statement, the sign-on request, bill pay and the rest.
An `OfxNode` holds a depth, a name and a text. Depth 0 is a child of the `OFX` root. An aggregate has no text.
The reader keeps every element and every value, in document order.

**The charset of the header.** An OFX 1.x header names the charset of the body.
When it names Windows-1252 or ISO-8859-1, every reader of the package decodes the body into UTF-8 before it parses.
This matches Python `ofxtools`, which decodes with the header charset. The flag `auto_charset` in `OfxOptions` turns the decode off.
A byte that Windows-1252 leaves undefined stays a fault.

The writer checks each name: 1 to 32 capital letters or digits.
It allows no depth that is two steps down, and no text in an aggregate. A leaf of the OFX DTD needs a text.
It checks each text for control bytes, escapes `& < >`, and writes the bytes above 127 as numeric references.

The writer also checks every element against the rules of the OFX specification.
The rules cover 386 aggregates and 46 enum sets. The table names Python `ofxtools` as its source.

The check refuses an element that the aggregate does not allow. It refuses an element out of order.
It refuses a required element that is absent. It refuses a text that breaks its kind.
It refuses a leaf where an aggregate belongs.

A name that starts with `X` and has no rule row stays unchecked with its children.
The specification keeps that range for private extensions.
Set `loose_elements` in `OfxWriteOptions` to skip the element check. `check_ofx_tree` runs the check alone.

**The network client.** `ofx_fetch` sends an OFX request over HTTPS and appends the body of the answer.
The caller builds the request with `write_ofx_tree` and parses the body with `parse_ofx` or `parse_ofx_tree`.
`OfxFetch` holds the URL, the time limit in milliseconds, the type of the content and the user agent.
The type of the content defaults to the type of the OFX 1.x form. The call gives the status code of the HTTP answer.

The client runs the `curl` program of the system as a child process. The TLS stack of the system does the crypto.
The child runs without a shell. The size of the answer never passes `max_input`.

**OFX profile.** `parse_ofx_profile` reads the `PROFRS` aggregate of a profile response.

`OfxProfile` holds the institution: name, address, phones, URL, e-mail and the date of the profile. Its field `found` tells whether the file holds a profile.

`OfxSignonInfo` holds the sign-on rules of a realm. The flags `Y` and `N` read as booleans; any other value is a fault.

`OfxMsgSet` holds one version of one message set: its kind, version, URL, security level and realm.
Every other leaf of a message set is a `Note`, so no value is lost.

The package sends no request. It reads a response that the caller got.

**References.** Python `ofxtools` and Go `ofxgo` write OFX. Python `quiffen` writes QIF. Java `prowide-core` writes MT940 and MT942.
Node `ofx-js` reads only. GnuCash and Rust `qif_parser` write no QIF.

The Python, Node and Rust MT940 libraries read only.

`ofxgo` writes the date offset as `[0:GMT]` and `ofxtools` writes `[+0:UTC]`. No standard fixes the choice, so this package writes `[0:GMT]`.
The QIF date has no standard order, so the caller chooses it.

## Limits

This package is below `v1.0.0`. These gaps against the reference libraries stay open.

- **`parse_camt` takes the header as a parameter now.** The old form was `parse_camt(input, lim, opts, statements, entries, balances, buf)`. The new form adds `header` after `opts`. A caller binds a `CamtHeader` and passes it.
- **The camt reader reads the group header and the statements.** Java `prowide-iso20022` reads 14 versions of them. Python `camt053` reads four profiles. This package reads the statement, the balances, the entries and the transaction summary of the message. The business application header of the wrapper stays unread.
- **A summary with one block for all the entries gives no total.** The block holds the sum of every entry. That sum has no sign. The reader ignores the block.
- **The XML tree of the document has no count limit.** The input limit of the package bounds it.
- **The investment statement, the sign-on request and bill pay have no typed record.** The element tree writer writes them. It checks each element against the rules. Python `ofxtools` and Go `ofxgo` model each element.
- **The element rule check has blind spots.** It does not check how many times an element may repeat. It does not check two aggregates that exclude each other. A row with no rule and a private `X` aggregate stay unchecked inside.
- **The OFX writer writes bank statements or credit card statements, not both in one call.**
- **The field rules are off by default.** The flag `check_fields` turns on the widths and the order of the manual. Java `prowide-core` holds a validation module with more rules for the tags of other message types.
- **Only five bank dialects exist.** The package reads Rabobank, ABN AMRO, ING, Regiobank and mBank. A caller reads other banks from the `:86:` text.
- **The MT940 and QIF readers do not transcode.** A byte above 127 passes through into the text. The caller calls `decode_charset` first. Node `@fin.cx/mt940` fixes the encoding of each field. The OFX readers transcode with the header charset. The package has no other charset than Windows-1252 and ISO-8859-1.
- **The network client needs the `curl` program.** Python `ofxtools` and Go `ofxgo` hold their own HTTP stack. This package runs `curl` as a child process, so the caller needs `curl` on the system. The TLS stack of the system does the crypto.
- **The answer is held in memory.** The cap is `max_input`, and `curl` enforces it. A parser bound applies after the fetch.
- **The QIF Payee, Budget and Tag sections have no standard.** GnuCash, KMyMoney and Python `quiffen` skip them. Rust `qif_parser` reads Budget and Tag. The Perl library `Finance::QIF` is the only source for the Payee list. It numbers the address lines `A0` to `A2`. This package keeps the text of each `A` line as written. A numbered file gives lines that start with the number.
- **The QIF `B` code of an account has two meanings.** GnuCash reads a budget. `Finance::QIF` reads a balance. This package keeps it as a field.
- **A price line holds three parts.** `Finance::QIF` reads three more parts, a high, a low and a volume. This package refuses a line with more than three parts.
- **The nesting limit is 16.** It was 8 before. The OFX files of the
  banks nest deeper than 8 levels.
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
- **A name cannot break out.** A name holds capital letters and digits only, so it cannot hold a tag. Python `ofxtools` writes SGML text raw.
- **A QIF list record cannot break out.** `write_qif_lists` refuses a line end and a control byte in every text. It refuses a field code of `!` or `^`, and a quote in a price symbol. Python `quiffen` escapes none of them.
- **An ambiguous QIF date is a fault.** Rust `qif_parser` guesses the order. This package asks the caller, or reads the whole file.
- **Every size has a limit.** The limits cover the input, the line, the field and the nesting of blocks. They also cover the counts of statements, entries, splits, records and fields. Python `mt940` and `quiffen` cap none of them. Python `bankstatementparser` caps the file size only. `default_limits()` holds safe values.
- **A control byte is a fault.** A NUL byte never reaches a text field. A CR without an LF is a fault too.
- **A value that is too long is a fault.** Node `@centrapay/swift-parser` keeps the first 16 characters of a long reference. The rest is lost. This package refuses the file and names the tag. The checks are linear and use no recursion.
- **An interim line cannot switch off the balance check.** A forged `:13D:` or `:34F:` line does not skip it.
- **No recursion, linear time.** A hostile file cannot overflow the stack or make the parser slow down.
- **The OFX reader has no entity trick.** A doctype and an entity
  declaration are faults. The five named entities and the numeric
  references decode once. An unknown entity stays as text. Python
  `ofxtools`, Go `ofxgo` and Node `ofx-js` have no entity machinery,
  so none of them expands an entity either.
- **The OFX reader bounds the nesting and the count of the tags.** No
  reference library does. A deep SGML body crashes `ofx-js` and
  `ofxtools` with a stack overflow.
- **No entity of a document expands.** The package `goose-xml` skips a doctype. It never expands an entity. An unknown entity is a fault. It also refuses a picture deeper than 256 levels. Java `prowide-iso20022` and Python `camt053` use a parser that reads a doctype with an internal subset.
- **The network client takes HTTPS only.** A URL with a space or a control byte is a fault. The child runs without a shell, so no URL can inject a command. The answer size is capped before the download fills the memory.
- **The security list writer checks every field.** An unknown kind is a fault. So is a missing id or name. So is a price with no finite decimal form. Python `ofxtools` writes the price through a float context.
- **The OFX tree writer checks the rules.** An unknown element is a fault. So is an element out of order. So is a required element that is absent. So is a text that breaks its kind. The reference writers trust the caller.
- **The OFX writer escapes text.** Python `ofxtools` writes the text of the SGML form raw. A memo that holds `</STMTTRN><STMTTRN>` then adds a transaction. This package writes `&`, `<` and `>` as entities. It writes a byte above 127 as a numeric reference. Both forms do this.
- **The QIF writer refuses a line end.** Python `quiffen` escapes nothing. A payee with a line end can add an amount or end the record. This package gives a fault. A field code of `!` or `^` is a fault too.
- **The MT940 writer refuses a tag line.** A narrative line that starts with a colon is a fault. So is a lone minus. So is a byte outside the SWIFT set.
- **Transcoding refuses what it cannot map.** A byte that Windows-1252 leaves undefined is a fault. So is a character that the target charset lacks. Output has the limit `max_input`.
- **The writers use no float.** An amount comes from minor units by integer division. The most negative 64-bit value writes without overflow.
- **The MT942 writer checks the totals.** A total that differs from the entries is a fault. Python `mt940` and Rust `mt940-rs` read a total and keep it. This package refuses to write a report with a wrong total.

Risks that stay:

- **The values of a dialect are untrusted text.** A bank or a payer writes them. Escape them as you escape a remittance.
- **The text of a remittance or a party name is untrusted.** The package does not escape it. Escape it yourself for HTML, SQL, a path or a command.

- **The text of a narrative, a payee or a memo is untrusted.** The package does not escape it. Escape it yourself for HTML, SQL, a path or a command.
- **The reference of an image is untrusted.** The package never fetches it. A caller that fetches it must check the host and the scheme. A reference that names a host inside the network of the caller reaches that host.
- **The default input limit is 16 MiB.** Lower it when you read from a form upload.
- **`check_fields` is off by default.** Without it a field may hold any width. Turn it on for a bank that keeps the manual, and keep `max_field` low for the rest.
- **`skip_balance_check` turns the balance protection off.** Use it only for a file you already trust.
- **The fault names the tag and the line, not the content.** The package does not mask account numbers. Do not log a statement.
- **The input must outlive the arrays.** The spans point into it.

## License

MIT
