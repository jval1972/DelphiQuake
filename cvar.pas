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

unit cvar;

// cvar.c -- dynamic variable tracking

interface

uses
  q_delphi;

type
  Pcvar_t = ^cvar_t;
  cvar_t = record
    name: PChar;
    text: PChar;
    archive: qboolean;   // set to true to cause it to be saved to vars.rc
    server: qboolean;    // notifies players when changed
    value: single;
    next: Pcvar_t;
  end;

function Cvar_FindVar(var_name: PChar): Pcvar_t;
function Cvar_VariableValue(var_name: PChar): single;
function Cvar_VariableString(var_name: PChar): PChar;
function Cvar_CompleteVariable(partial: PChar): PChar;
procedure Cvar_Set(var_name: PChar; value: PChar);
procedure Cvar_SetValue(var_name: PChar;  value: single); overload;
procedure Cvar_SetValue(var_name: PChar;  value: qboolean); overload;
procedure Cvar_SetValue(var_name: string;  value: single); overload;
procedure Cvar_SetValue(var_name: string;  value: qboolean); overload;
procedure Cvar_RegisterVariable(variable: Pcvar_t);
function Cvar_Command: qboolean;
procedure Cvar_WriteVariables(var f: text);

var
  cvar_vars: Pcvar_t = nil;

implementation

uses
  common,
  console,
  zone,
  sv_main,
  host,
  cmd;

var
  cvar_null_string: PChar = '';

(*
============
Cvar_FindVar
============
*)
function Cvar_FindVar(var_name: PChar): Pcvar_t;
var
  _var: Pcvar_t;
begin
  _var := cvar_vars;
  while _var <> nil do
  begin
    if Q_strcmp(var_name, _var.name) = 0 then
    begin
      result := _var;
      exit;
    end;
    _var := _var.next;
  end;

  result := nil;
end;

(*
============
Cvar_VariableValue
============
*)
function Cvar_VariableValue(var_name: PChar): single;
var
  _var: Pcvar_t;
begin
  _var := Cvar_FindVar(var_name);
  if _var = nil then
    result := 0
  else
    result := Q_atof(_var.text);
end;


(*
============
Cvar_VariableString
============
*)
function Cvar_VariableString(var_name: PChar): PChar;
var
  _var: Pcvar_t;
begin
  _var := Cvar_FindVar(var_name);
  if _var = nil then
    result := cvar_null_string
  else
    result := _var.text;
end;


(*
============
Cvar_CompleteVariable
============
*)
function Cvar_CompleteVariable(partial: PChar): PChar;
var
  _var: Pcvar_t;
  len: integer;
begin
  len := Q_strlen(partial);

  if len = 0 then
  begin
    result := nil;
    exit;
  end;

// check functions
  _var := cvar_vars;
  while _var <> nil do
  begin
    if Q_strncmp(partial, _var.name, len) = 0 then
    begin
      result := _var.name;
      exit;
    end;
    _var := _var.next;
  end;

  result := nil;
end;


(*
============
Cvar_Set
============
*)
procedure Cvar_Set(var_name: PChar; value: PChar);
var
  _var: Pcvar_t;
  changed: qboolean;
begin
  _var := Cvar_FindVar(var_name);
  if _var = nil then
  begin  // there is an error in C code if this happens
    Con_Printf('Cvar_Set: variable %s not found'#10, [var_name]);
    exit;
  end;

  changed := Q_strcmp(_var.text, value) = 0;

  Z_Free(_var.text);  // free the old value string

  _var.text := Z_Malloc(Q_strlen(value) + 1);
  Q_strcpy(_var.text, value);
  _var.value := Q_atof(_var.text);
  if _var.server and changed then
  begin
    if sv.active then
      SV_BroadcastPrintf('"%s" changed to "%s"'#10, [_var.name, _var.text]);
  end;
end;

(*
============
Cvar_SetValue
============
*)
procedure Cvar_SetValue(var_name: PChar;  value: qboolean);
var
  f: single;
begin
  if value then
    f := 1.0
  else
    f := 0.0;
  Cvar_SetValue(var_name, f);
end;

procedure Cvar_SetValue(var_name: PChar;  value: single);
var
  val: array[0..31] of char;
begin
  sprintf(val, '%f', [value]);
  Cvar_Set(var_name, val);
end;

procedure Cvar_SetValue(var_name: string;  value: single);
begin
  Cvar_SetValue(PChar(var_name), value);
end;

procedure Cvar_SetValue(var_name: string;  value: qboolean); 
begin
  Cvar_SetValue(PChar(var_name), value);
end;

(*
============
Cvar_RegisterVariable

Adds a freestanding variable to the variable list.
============
*)
procedure Cvar_RegisterVariable(variable: Pcvar_t);
var
  oldstr: PChar;
begin
// first check to see if it has allready been defined
  if Cvar_FindVar(variable.name) <> nil then
  begin
    Con_Printf('Can''t register variable %s, allready defined'#10, [variable.name]);
    exit;
  end;

// check for overlap with a command
  if Cmd_Exists(variable.name) then
  begin
    Con_Printf('Cvar_RegisterVariable: %s is a command'#10, [variable.name]);
    exit;
  end;

// copy the value off, because future sets will Z_Free it
  oldstr := variable.text;
  variable.text := Z_Malloc(Q_strlen(variable.text) + 1);
  Q_strcpy(variable.text, oldstr);
  variable.value := Q_atof(variable.text);

// link the variable in
  variable.next := cvar_vars;
  cvar_vars := variable;
end;

(*
============
Cvar_Command

Handles variable inspection and changing from the console
============
*)
function Cvar_Command: qboolean;
var
  v: Pcvar_t;
begin
// check variables
  v := Cvar_FindVar(Cmd_Argv_f(0));
  if v = nil then
  begin
    result := false;
    exit;
  end;

// perform a variable print or set
  if Cmd_Argc_f = 1 then
  begin
    Con_Printf('"%s" is "%s"'#10, [v.name, v.text]);
    result := true;
    exit;
  end;

  Cvar_Set(v.name, Cmd_Argv_f(1));
  result := true;
end;


(*
============
Cvar_WriteVariables

Writes lines containing "set variable value" for all variables
with the archive flag set to true.
============
*)
procedure Cvar_WriteVariables(var f: text);
var
  _var: Pcvar_t;
begin
  _var := cvar_vars;
  while _var <> nil do
  begin
    if _var.archive then
      fprintf(f, '%s "%s"'#10, [_var.name, _var.text]);
    _var := _var.next;
  end;
end;

end.
