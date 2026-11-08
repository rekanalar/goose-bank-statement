// bank_statement - bank statement files for Goose.
//
// The package reads SWIFT MT940 and MT942 statements, QIF files, the
// ISO 20022 documents camt.052, camt.053 and camt.054, and OFX 1.x and
// 2.x files.
// Money is an integer count of minor units. Every parse is one linear
// pass with no recursion and bounded sizes.
//
// The repository is goose-bank-statement. The import name is
// "bank_statement".
namespace bank_statement;

import std;
import xml from "rekanalar/goose-xml@v2.0.0";
import fault;
import text;
import limits;
import amount;
import currency;
import country;
import date;
import mt940;
import mt940_write;
import swift;
import dialect;
import qif;
import write_text;
import qif_write;
import qif_lists;
import sgml;
import ofx;
import ofx_write;
import ofx_seclist;
import ofx_profile;
import ofx_tree;
import camt;
import transcode;
