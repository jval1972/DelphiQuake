// ------------------------------------------------------------------------------
// DelphiQuake, Copyright (C) 2005-2011 by Jim Valavanis
//  E-Mail: jimmyvalavanis@yahoo.gr
//
// Copyright (C) 1996-1997 Id Software, Inc.
//
// This program is free software; you can redistribute it and/or
// modify it under the terms of the GNU General Public License
// as published by the Free Software Foundation; either version 2
// of the License, or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
//
// See the GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program; if not,  write to the Free Software
// Foundation,  Inc., 59 Temple Place - Suite 330,  Boston,  MA  02111-1307, USA.
//
// ------------------------------------------------------------------------------

{$I dquake.inc}

{$Z4}

unit pr_comp;

// this file is shared by quake and qcc

interface

uses
  q_delphi;

type
  func_t = integer;
  Pfunc_t = ^func_t;
  string_t = integer;
  Pstring_t = ^string_t;

type
  etype_t = (
    ev_void,
    ev_string,
    ev_float,
    ev_vector,
    ev_entity,
    ev_field,
    ev_function,
    ev_pointer
    );

const
  OFS_NULL = 0;
  OFS_RETURN = 1;
  OFS_PARM0 = 4; // leave 3 ofs for each parm to hold vectors
  OFS_PARM1 = 7;
  OFS_PARM2 = 10;
  OFS_PARM3 = 13;
  OFS_PARM4 = 16;
  OFS_PARM5 = 19;
  OFS_PARM6 = 22;
  OFS_PARM7 = 25;
  RESERVED_OFS = 28;

const
  OP_DONE = 0;
  OP_MUL_F = 1;
  OP_MUL_V = 2;
  OP_MUL_FV = 3;
  OP_MUL_VF = 4;
  OP_DIV_F = 5;
  OP_ADD_F = 6;
  OP_ADD_V = 7;
  OP_SUB_F = 8;
  OP_SUB_V = 9;

  OP_EQ_F = 10;
  OP_EQ_V = 11;
  OP_EQ_S = 12;
  OP_EQ_E = 13;
  OP_EQ_FNC = 14;

  OP_NE_F = 15;
  OP_NE_V = 16;
  OP_NE_S = 17;
  OP_NE_E = 18;
  OP_NE_FNC = 19;

  OP_LE = 20;
  OP_GE = 21;
  OP_LT = 22;
  OP_GT = 23;

  OP_LOAD_F = 24;
  OP_LOAD_V = 25;
  OP_LOAD_S = 26;
  OP_LOAD_ENT = 27;
  OP_LOAD_FLD = 28;
  OP_LOAD_FNC = 29;

  OP_ADDRESS = 30;

  OP_STORE_F = 31;
  OP_STORE_V = 32;
  OP_STORE_S = 33;
  OP_STORE_ENT = 34;
  OP_STORE_FLD = 35;
  OP_STORE_FNC = 36;

  OP_STOREP_F = 37;
  OP_STOREP_V = 38;
  OP_STOREP_S = 39;
  OP_STOREP_ENT = 40;
  OP_STOREP_FLD = 41;
  OP_STOREP_FNC = 42;

  OP_RETURN = 43;
  OP_NOT_F = 44;
  OP_NOT_V = 45;
  OP_NOT_S = 46;
  OP_NOT_ENT = 47;
  OP_NOT_FNC = 48;
  OP_IF = 49;
  OP_IFNOT = 50;
  OP_CALL0 = 51;
  OP_CALL1 = 52;
  OP_CALL2 = 53;
  OP_CALL3 = 54;
  OP_CALL4 = 55;
  OP_CALL5 = 56;
  OP_CALL6 = 57;
  OP_CALL7 = 58;
  OP_CALL8 = 59;
  OP_STATE = 60;
  OP_GOTO = 61;
  OP_AND = 62;
  OP_OR = 63;

  OP_BITAND = 64;
  OP_BITOR = 65;

type
  dstatement_t = record
    op: unsigned_short;
    a, b, c: short;
  end;
  Pdstatement_t = ^dstatement_t;
  dstatement_tArray = array[0..$FFFF] of dstatement_t;
  Pdstatement_tArray = ^dstatement_tArray;


type
  ddef_t = record
    _type: unsigned_short; // if DEF_SAVEGLOBGAL bit is set
                            // the variable needs to be saved in savegames
    ofs: unsigned_short;
    s_name: integer;
  end;
  Pddef_t = ^ddef_t;
  ddef_tArray = array[0..$FFFF] of ddef_t;
  Pddef_tArray = ^ddef_tArray;

const
  DEF_SAVEGLOBAL = 1 shl 15;

  MAX_PARMS = 8;

type
  dfunction_t = record
    first_statement: integer; // negative numbers are builtins
    parm_start: integer;
    locals: integer; // total ints of parms + locals

    profile: integer; // runtime

    s_name: integer;
    s_file: integer; // source file defined in

    numparms: integer;
    parm_size: array[0..MAX_PARMS - 1] of byte;
  end;
  Pdfunction_t = ^dfunction_t;
  dfunction_tArray = array[0..$FFFF] of dfunction_t;
  Pdfunction_tArray = ^dfunction_tArray;

const
  PROG_VERSION = 6;

type
  dprograms_t = record
    version: integer;
    crc: integer; // check of header file

    ofs_statements: integer;
    numstatements: integer; // statement 0 is an error

    ofs_globaldefs: integer;
    numglobaldefs: integer;

    ofs_fielddefs: integer;
    numfielddefs: integer;

    ofs_functions: integer;
    numfunctions: integer; // function 0 is an empty

    ofs_strings: integer;
    numstrings: integer; // first string is a null string

    ofs_globals: integer;
    numglobals: integer;

    entityfields: integer;
  end;
  Pdprograms_t = ^dprograms_t;


implementation

end.

