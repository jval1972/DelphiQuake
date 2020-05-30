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

unit pr_exec;

interface

uses
  q_delphi,
  pr_comp;

procedure PR_ExecuteProgram(fnum: func_t);
procedure PR_Profile_f;
procedure PR_RunError(error: PChar); overload;
procedure PR_RunError(error: PChar; const Args: array of const); overload;

var
  pr_argc: integer;

var
  pr_trace: qboolean;
  pr_xfunction: Pdfunction_t;

implementation

uses
  console,
  pr_edict,
  host,
  sys_win,
  progs_h,
  sv_main,
  server_h,
  pr_cmds;

type
  prstack_t = record
    s: integer;
    f: Pdfunction_t;
  end;
  Pprstack_t = ^prstack_t;

const
  MAX_STACK_DEPTH = 32;

var
  pr_stack: array[0..MAX_STACK_DEPTH - 1] of prstack_t;
  pr_depth: integer;

const
  LOCALSTACK_SIZE = 2048;

var
  localstack: array[0..LOCALSTACK_SIZE - 1] of integer;
  localstack_used: integer;

var
  pr_xstatement: integer;

const
  NUMOPNAMES = 66;
  pr_opnames: array[0..NUMOPNAMES - 1] of PChar = (
    'DONE',

    'MUL_F',
    'MUL_V',
    'MUL_FV',
    'MUL_VF',

    'DIV',

    'ADD_F',
    'ADD_V',

    'SUB_F',
    'SUB_V',

    'EQ_F',
    'EQ_V',
    'EQ_S',
    'EQ_E',
    'EQ_FNC',

    'NE_F',
    'NE_V',
    'NE_S',
    'NE_E',
    'NE_FNC',

    'LE',
    'GE',
    'LT',
    'GT',

    'INDIRECT',
    'INDIRECT',
    'INDIRECT',
    'INDIRECT',
    'INDIRECT',
    'INDIRECT',

    'ADDRESS',

    'STORE_F',
    'STORE_V',
    'STORE_S',
    'STORE_ENT',
    'STORE_FLD',
    'STORE_FNC',

    'STOREP_F',
    'STOREP_V',
    'STOREP_S',
    'STOREP_ENT',
    'STOREP_FLD',
    'STOREP_FNC',

    'RETURN',

    'NOT_F',
    'NOT_V',
    'NOT_S',
    'NOT_ENT',
    'NOT_FNC',

    'IF',
    'IFNOT',

    'CALL0',
    'CALL1',
    'CALL2',
    'CALL3',
    'CALL4',
    'CALL5',
    'CALL6',
    'CALL7',
    'CALL8',

    'STATE',

    'GOTO',

    'AND',
    'OR',

    'BITAND',
    'BITOR'
    );


//=============================================================================

(*
=================
PR_PrintStatement
=================
*)

procedure PR_PrintStatement(s: Pdstatement_t);
var
  i: integer;
begin
  if unsigned(s.op) < NUMOPNAMES then
  begin
    Con_Printf('%s ', [pr_opnames[s.op]]);
    i := strlen(pr_opnames[s.op]);
    while i < 10 do
    begin
      Con_Printf(' ');
      inc(i);
    end;
  end;

  if (s.op = OP_IF) or (s.op = OP_IFNOT) then
    Con_Printf('%sbranch %d', [PR_GlobalString(s.a), s.b])
  else if s.op = OP_GOTO then
  begin
    Con_Printf('branch %d', [s.a]);
  end
  else if unsigned(s.op - OP_STORE_F) < 6 then
  begin
    Con_Printf('%s', [PR_GlobalString(s.a)]);
    Con_Printf('%s', [PR_GlobalStringNoContents(s.b)]);
  end
  else
  begin
    if boolval(s.a) then
      Con_Printf('%s', [PR_GlobalString(s.a)]);
    if boolval(s.b) then
      Con_Printf('%s', [PR_GlobalString(s.b)]);
    if boolval(s.c) then
      Con_Printf('%s', [PR_GlobalStringNoContents(s.c)]);
  end;
  Con_Printf(#10);
end;

(*
============
PR_StackTrace
============
*)

procedure PR_StackTrace;
var
  f: Pdfunction_t;
  i: integer;
begin
  if pr_depth = 0 then
  begin
    Con_Printf('<NO STACK>'#10);
    exit;
  end;

  pr_stack[pr_depth].f := pr_xfunction;
  for i := pr_depth downto 0 do
  begin
    f := pr_stack[i].f;

    if f = nil then
      Con_Printf('<NO FUNCTION>'#10)
    else
      Con_Printf('%12s : %s'#10, [PChar(@pr_strings[f.s_file]), PChar(@pr_strings[f.s_name])]) // JVAL mayby function get_pr_string(offs): PChar;
  end;
end;


(*
============
PR_Profile_f

============
*)

procedure PR_Profile_f;
var
  f, best: Pdfunction_t;
  max: integer;
  num: integer;
  i: integer;
begin
  num := 0;
  repeat
    max := 0;
    best := nil;
    for i := 0 to progs.numfunctions - 1 do
    begin
      f := @pr_functions[i];
      if f.profile > max then
      begin
        max := f.profile;
        best := f;
      end;
    end;
    if best <> nil then
    begin
      if num < 10 then
        Con_Printf('%7d %s'#10, [best.profile, PChar(@pr_strings[best.s_name])]);
      inc(num);
      best.profile := 0;
    end;
  until best = nil;
end;


(*
============
PR_RunError

Aborts the currently executing function
============
*)

procedure PR_RunError(error: PChar);
begin
  PR_RunError(error, []);
end;

procedure PR_RunError(error: PChar; const Args: array of const);
var
  str: array[0..1023] of char;
begin
  sprintf(str, error, Args);

  PR_PrintStatement(@pr_statements[pr_xstatement]);
  PR_StackTrace;
  Con_Printf('%s'#10, [str]);

  pr_depth := 0; // dump the stack so host_error can shutdown functions

  Host_Error('Program error');
end;

(*
============================================================================
PR_ExecuteProgram

The interpretation main loop
============================================================================
*)

(*
====================
PR_EnterFunction

Returns the new program statement counter
====================
*)

function PR_EnterFunction(f: Pdfunction_t): integer;
var
  i, j, c, o: integer;
begin
  pr_stack[pr_depth].s := pr_xstatement;
  pr_stack[pr_depth].f := pr_xfunction;
  inc(pr_depth);
  if pr_depth >= MAX_STACK_DEPTH then
    PR_RunError('stack overflow');

// save off any locals that the new function steps on
  c := f.locals;
  if localstack_used + c > LOCALSTACK_SIZE then
    PR_RunError('PR_ExecuteProgram: locals stack overflow'#10);

  for i := 0 to c - 1 do
    localstack[localstack_used + i] := PIntegerArray(pr_globals)[f.parm_start + i];
  inc(localstack_used, c);

// copy parameters
  o := f.parm_start;
  for i := 0 to f.numparms - 1 do
  begin
    for j := 0 to f.parm_size[i] - 1 do
    begin
      PIntegerArray(pr_globals)[o] := PIntegerArray(pr_globals)[OFS_PARM0 + i * 3 + j];
      inc(o);
    end;
  end;

  pr_xfunction := f;
  result := f.first_statement - 1; // offset the s++
end;

(*
====================
PR_LeaveFunction
====================
*)

function PR_LeaveFunction: integer;
var
  i, c: integer;
begin
  if pr_depth <= 0 then
    Sys_Error('prog stack underflow');

// restore locals from the stack
  c := pr_xfunction.locals;
  dec(localstack_used, c);
  if localstack_used < 0 then
    PR_RunError('PR_ExecuteProgram: locals stack underflow'#10);

  for i := 0 to c - 1 do
    PIntegerArray(pr_globals)[pr_xfunction.parm_start + i] := localstack[localstack_used + i];

// up stack
  dec(pr_depth);
  pr_xfunction := pr_stack[pr_depth].f;
  result := pr_stack[pr_depth].s;
end;


(*
====================
PR_ExecuteProgram
====================
*)

procedure PR_ExecuteProgram(fnum: func_t);
var
  a, b, c: Peval_t;
  s: integer;
  st: Pdstatement_t;
  f, newf: Pdfunction_t;
  runaway: integer;
  i: integer;
  ed: Pedict_t;
  exitdepth: integer;
  ptr: Peval_t;
begin
  if (fnum = 0) or (fnum >= progs.numfunctions) then
  begin
    if pr_global_struct.self <> 0 then
      ED_Print(PROG_TO_EDICT(pr_global_struct.self));
    Host_Error('PR_ExecuteProgram: NULL function');
  end;

  f := @pr_functions[fnum];

  runaway := 100000;
  pr_trace := false;

// make a stack frame
  exitdepth := pr_depth;

  s := PR_EnterFunction(f);

  while true do
  begin
    inc(s); // next statement

    st := @pr_statements[s];
    a := Peval_t(@pr_globals[st.a]);
    b := Peval_t(@pr_globals[st.b]);
    c := Peval_t(@pr_globals[st.c]);

    dec(runaway);
    if runaway = 0 then
      PR_RunError('runaway loop error');

    inc(pr_xfunction.profile);
    pr_xstatement := s;

    if pr_trace then
      PR_PrintStatement(st);

    case st.op of
      OP_ADD_F:
        begin
          c._float := a._float + b._float;
        end;

      OP_ADD_V:
        begin
          c.vector[0] := a.vector[0] + b.vector[0];
          c.vector[1] := a.vector[1] + b.vector[1];
          c.vector[2] := a.vector[2] + b.vector[2];
        end;

      OP_SUB_F:
        begin
          c._float := a._float - b._float;
        end;

      OP_SUB_V:
        begin
          c.vector[0] := a.vector[0] - b.vector[0];
          c.vector[1] := a.vector[1] - b.vector[1];
          c.vector[2] := a.vector[2] - b.vector[2];
        end;

      OP_MUL_F:
        begin
          c._float := a._float * b._float;
        end;

      OP_MUL_V:
        begin
          c._float := a.vector[0] * b.vector[0] +
            a.vector[1] * b.vector[1] +
            a.vector[2] * b.vector[2];
        end;

      OP_MUL_FV:
        begin
          c.vector[0] := a._float * b.vector[0];
          c.vector[1] := a._float * b.vector[1];
          c.vector[2] := a._float * b.vector[2];
        end;

      OP_MUL_VF:
        begin
          c.vector[0] := b._float * a.vector[0];
          c.vector[1] := b._float * a.vector[1];
          c.vector[2] := b._float * a.vector[2];
        end;

      OP_DIV_F:
        begin
          c._float := a._float / b._float;
        end;

      OP_BITAND:
        begin
          c._float := intval(a._float) and intval(b._float);
        end;

      OP_BITOR:
        begin
          c._float := intval(a._float) or intval(b._float);
        end;


      OP_GE:
        begin
          c._float := floatval(a._float >= b._float);
        end;

      OP_LE:
        begin
          c._float := floatval(a._float <= b._float);
        end;

      OP_GT:
        begin
          c._float := floatval(a._float > b._float);
        end;

      OP_LT:
        begin
          c._float := floatval(a._float < b._float);
        end;

      OP_AND:
        begin
          c._float := floatval(boolval(a._float) and boolval(b._float));
        end;

      OP_OR:
        begin
          c._float := floatval(boolval(a._float) or boolval(b._float));
        end;

      OP_NOT_F:
        begin
          c._float := floatval(not boolval(a._float));
        end;

      OP_NOT_V:
        begin
          c._float := floatval(not boolval(a.vector[0]) and not boolval(a.vector[1]) and not boolval(a.vector[2]));
        end;

      OP_NOT_S:
        begin
          c._float := floatval(not boolval(a._string) or not boolval(pr_strings[a._string]));
        end;

      OP_NOT_FNC:
        begin
          c._float := floatval(not boolval(a.func));
        end;

      OP_NOT_ENT:
        begin
          c._float := floatval((PROG_TO_EDICT(a.edict) = sv.edicts));
        end;

      OP_EQ_F:
        begin
          c._float := floatval(a._float = b._float);
        end;

      OP_EQ_V:
        begin
          c._float := floatval((a.vector[0] = b.vector[0]) and
            (a.vector[1] = b.vector[1]) and
            (a.vector[2] = b.vector[2]));
        end;

      OP_EQ_S:
        begin
          c._float := floatval(strcmp(@pr_strings[a._string], @pr_strings[b._string]) = 0);
        end;

      OP_EQ_E:
        begin
          c._float := floatval(a._int = b._int);
        end;

      OP_EQ_FNC:
        begin
          c._float := floatval(a.func = b.func);
        end;

      OP_NE_F:
        begin
          c._float := floatval(a._float <> b._float);
        end;

      OP_NE_V:
        begin
          c._float := floatval((a.vector[0] <> b.vector[0]) or
            (a.vector[1] <> b.vector[1]) or
            (a.vector[2] <> b.vector[2]));
        end;

      OP_NE_S:
        begin
          c._float := strcmp(@pr_strings[a._string], // JVAL mayby intval(boolval(strcmp... ?
            @pr_strings[b._string]);
        end;

      OP_NE_E:
        begin
          c._float := floatval(a._int <> b._int);
        end;

      OP_NE_FNC:
        begin
          c._float := floatval(a.func <> b.func);
        end;

//==================
      OP_STORE_F,
        OP_STORE_ENT,
        OP_STORE_FLD, // integers
        OP_STORE_S,
        OP_STORE_FNC: // pointers
        begin
          b._int := a._int;
        end;

      OP_STORE_V:
        begin
          b.vector[0] := a.vector[0];
          b.vector[1] := a.vector[1];
          b.vector[2] := a.vector[2];
        end;

      OP_STOREP_F,
        OP_STOREP_ENT,
        OP_STOREP_FLD, // integers
        OP_STOREP_S,
        OP_STOREP_FNC: // pointers
        begin
          ptr := Peval_t(integer(sv.edicts) + b._int);
          ptr._int := a._int;
        end;

      OP_STOREP_V:
        begin
          ptr := Peval_t(integer(sv.edicts) + b._int);
          ptr.vector[0] := a.vector[0];
          ptr.vector[1] := a.vector[1];
          ptr.vector[2] := a.vector[2];
        end;

      OP_ADDRESS:
        begin
          ed := PROG_TO_EDICT(a.edict);
          if (ed = Pedict_t(sv.edicts)) and (sv.state = ss_active) then
            PR_RunError('assignment to world entity');
          c._int := integer(@PIntegerArray(@ed.v)[b._int]) - integer(sv.edicts); // JVAL check!
        end;

      OP_LOAD_F,
        OP_LOAD_FLD,
        OP_LOAD_ENT,
        OP_LOAD_S,
        OP_LOAD_FNC:
        begin
          ed := PROG_TO_EDICT(a.edict);
          a := Peval_t(@PIntegerArray(@ed.v)[b._int]); // JVAL check!
          c._int := a._int;
        end;

      OP_LOAD_V:
        begin
          ed := PROG_TO_EDICT(a.edict);
          a := Peval_t(@PIntegerArray(@ed.v)[b._int]);
          c.vector[0] := a.vector[0];
          c.vector[1] := a.vector[1];
          c.vector[2] := a.vector[2];
        end;

//==================

      OP_IFNOT:
        begin
          if not boolval(a._int) then
            inc(s, st.b - 1); // offset the s++
        end;

      OP_IF:
        begin
          if boolval(a._int) then
            inc(s, st.b - 1); // offset the s++
        end;

      OP_GOTO:
        begin
          inc(s, st.a - 1); // offset the s++
        end;

      OP_CALL0,
        OP_CALL1,
        OP_CALL2,
        OP_CALL3,
        OP_CALL4,
        OP_CALL5,
        OP_CALL6,
        OP_CALL7,
        OP_CALL8:
        begin
          pr_argc := st.op - OP_CALL0;
          if a.func = 0 then
            PR_RunError('NULL function');

          newf := @pr_functions[a.func];

          if newf.first_statement < 0 then
          begin // negative statements are built in functions
            i := -newf.first_statement;
            if i >= pr_numbuiltins then
              PR_RunError('Bad builtin call number');
            pr_builtin[i]; // JVAL check!
          end
          else // JVAL CHECK!
            s := PR_EnterFunction(newf);
        end;

      OP_DONE,
        OP_RETURN:
        begin
          pr_globals[OFS_RETURN] := pr_globals[st.a];
          pr_globals[OFS_RETURN + 1] := pr_globals[st.a + 1];
          pr_globals[OFS_RETURN + 2] := pr_globals[st.a + 2];

          s := PR_LeaveFunction;
          if pr_depth = exitdepth then
            exit; // all done
        end;

      OP_STATE:
        begin
          ed := PROG_TO_EDICT(pr_global_struct.self);
          ed.v.nextthink := pr_global_struct.time + 0.1;
          if a._float <> ed.v.frame then
          begin
            ed.v.frame := a._float;
          end;
          ed.v.think := b.func;
        end;

    else
      PR_RunError('Bad opcode %d', [st.op]);
    end;
  end;
end;


end.
