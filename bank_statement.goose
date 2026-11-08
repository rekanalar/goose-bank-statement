// bank_statement - bank statement files for Goose.
//
// The package reads SWIFT MT940 and MT942 statements and QIF files.
// Money is an integer count of minor units. Every parse is one linear
// pass with no recursion and bounded sizes.
//
// The repository is goose-bank-statement. The import name is
// "bank_statement".
namespace bank_statement;

import std;
import fault;
import text;
import limits;
import amount;
import date;
import mt940;
import qif;
