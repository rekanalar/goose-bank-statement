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
import process from "rekanalar/goose-process@v1.0.0";
import finance from "rekanalar/goose-finance@v0.1.0";
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
import ofx_spec;
import ofx_net;
import ofx_tree;
import field86;
import camt_reason;
import money_bridge;
import camt;
import transcode;
import camt_fields;
import mt940_state;
import ofx_invest;
import ofx_fields;
import qif_records;
import ofx_write_leaf;
