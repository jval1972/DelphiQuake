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

unit cmd;

// cmd.h -- Command buffer and command execution
// cmd.c -- Quake script command processing module

interface

//===========================================================================

(*

Any number of commands can be added in a frame, from several different sources.
Most commands come from either keybindings or console line input, but remote
servers can also send across commands and entire text files can be execed.

The + command line options are also added to the command buffer.

The game starts with a Cbuf_AddText ("exec quake.rc\n"); Cbuf_Execute ();

*)


uses
  q_delphi,
  common;

(*

Command execution takes a null terminated string, breaks it into tokens,
then searches for a command or variable that matches the first token.

Commands can come from three sources, but the handler functions may choose
to dissallow the action or forward it to a remote server if the source is
not apropriate.

*)

type
  xcommand_t = procedure;

  cmd_source_t = (
    src_client, // came in over a net connection as a clc_stringcmd
                        // host_client will be valid during this state.
    src_command // from the command buffer
    );

procedure Cmd_Wait_f;
procedure Cbuf_Init;
procedure Cbuf_AddText(text: PChar);
procedure Cbuf_InsertText(text: PChar);
procedure Cbuf_Execute;
procedure Cmd_StuffCmds_f;
procedure Cmd_Exec_f;
procedure Cmd_Echo_f;
function CopyString(_in: PChar): PChar;
procedure Cmd_Init;
function Cmd_Argv_f(arg: integer): PChar;
function Cmd_Args_f: PChar;
procedure Cmd_TokenizeString(text: PChar);
procedure Cmd_AddCommand(cmd_name: PChar; _function: xcommand_t);
function Cmd_Exists(cmd_name: PChar): qboolean;
function Cmd_CompleteCommand(partial: PChar): PChar;
procedure Cmd_ExecuteString(text: PChar; src: cmd_source_t);
procedure Cmd_ForwardToServer;
function Cmd_CheckParm(parm: PChar): integer;
function Cmd_Argc_f: integer;

const
  MAX_ALIAS_NAME = 32;

type
  Pcmdalias_t = ^cmdalias_t;
  cmdalias_t = record
    next: Pcmdalias_t;
    name: array[0..MAX_ALIAS_NAME - 1] of char;
    value: PChar;
  end;

var
  cmd_alias: Pcmdalias_t;

  cmd_wait: qboolean;

(*
=============================================================================

            COMMAND BUFFER

=============================================================================
*)

var
  cmd_text: sizebuf_t;
  cmd_source: cmd_source_t;


implementation

uses
  console,
  zone,
  host_h,
  sys_win,
  cvar,
  cl_main_h,
  client,
  protocol;

//=============================================================================

(*
============
Cmd_Wait_f

Causes execution of the remainder of the command buffer to be delayed until
next frame.  This allows commands like:
bind g "impulse 5 ; +attack ; wait ; -attack ; impulse 2"
============
*)

procedure Cmd_Wait_f;
begin
  cmd_wait := true;
end;


(*
============
Cbuf_Init
============
*)

procedure Cbuf_Init;
begin
// JVAL ??? sizebuf_t has a pointer field ???
  SZ_Alloc(@cmd_text, 8192); // space for commands and script files
end;


(*
============
Cbuf_AddText

Adds command text at the end of the buffer
============
*)

procedure Cbuf_AddText(text: PChar);
var
  l: integer;
begin
  l := Q_strlen(text);

  if cmd_text.cursize + l >= cmd_text.maxsize then
  begin
    Con_Printf('Cbuf_AddText: overflow'#10);
    exit;
  end;

  SZ_Write(@cmd_text, text, Q_strlen(text));
end;


(*
============
Cbuf_InsertText

Adds command text immediately after the current command
Adds a \n to the text
FIXME: actually change the command buffer to do less copying
============
*)

procedure Cbuf_InsertText(text: PChar);
var
  temp: PChar;
  templen: integer;
begin
// copy off any commands still remaining in the exec buffer
  templen := cmd_text.cursize;
  if templen > 0 then
  begin
    temp := Z_Malloc(templen);
    memcpy(temp, cmd_text.data, templen);
    SZ_Clear(@cmd_text);
  end
  else
    temp := nil; // shut up compiler

// add the entire text of the file
  Cbuf_AddText(text);

// add the copied off data
  if templen > 0 then
  begin
    SZ_Write(@cmd_text, temp, templen);
    Z_Free(temp);
  end;
end;

(*
============
Cbuf_Execute
============
*)

procedure Cbuf_Execute;
var
  i: integer;
  text: PChar;
  line: array[0..1023] of char;
  quotes: integer;
begin
  while cmd_text.cursize <> 0 do
  begin
// find a \n or ; line break
    text := PChar(cmd_text.data);

    quotes := 0;
    i := 0;
    while i < cmd_text.cursize do
    begin
      if text[i] = '"' then
        inc(quotes);
      if (quotes and 1 = 0) and (text[i] = ';') then
        break; // don't break if inside a quoted string
      if text[i] in [#13, #10] then
        break;
      inc(i);
    end;


    memcpy(@line, text, i);
    line[i] := #0;

// delete the text from the command buffer and move remaining commands down
// this is necessary because commands (exec, alias) can insert data at the
// beginning of the text buffer

    if i = cmd_text.cursize then
      cmd_text.cursize := 0
    else
    begin
      inc(i);
      cmd_text.cursize := cmd_text.cursize - i;
      memcpy(text, @text[i], cmd_text.cursize);
    end;

// execute the command line
    Cmd_ExecuteString(line, src_command);

    if cmd_wait then
    begin // skip out while text still remains in buffer, leaving it
      // for next frame
      cmd_wait := false;
      break;
    end;
  end;
end;

(*
==============================================================================

            SCRIPT COMMANDS

==============================================================================
*)

(*
===============
Cmd_StuffCmds_f

Adds command line parameters as script statements
Commands lead with a +, and continue until a - or another +
quake +prog jctest.qp +cmd amlev1
quake -nosound +cmd amlev1
===============
*)

procedure Cmd_StuffCmds_f;
var
  i, j: integer;
  s: integer;
  c: char;
  text, build: PChar;
begin
  if Cmd_Argc_f <> 1 then
  begin
    Con_Printf('stuffcmds : execute command line parameters'#10);
    exit;
  end;

// build the combined string to parse from
  s := 0;
  for i := 1 to com_argc - 1 do
  begin
    if not boolval(com_argv[i]) then
      continue; // NEXTSTEP nulls out -NXHost
    s := s + Q_strlen(com_argv[i]) + 1;
  end;
  if s = 0 then
    exit;

  text := Z_Malloc(s + 1);
  PByteArray(text)[0] := 0;
  for i := 1 to com_argc - 1 do
  begin
    if not boolval(com_argv[i]) then
      continue; // NEXTSTEP nulls out -NXHost
    Q_strcat(text, com_argv[i]);
    if (i <> com_argc - 1) then
      Q_strcat(text, ' ');
  end;

// pull out the commands
  build := Z_Malloc(s + 1);
  PByteArray(build)[0] := 0;

  i := 0;
  while i < s - 2 do // JVAL ?
  begin
    if PCharArray(text)[i] = '+' then
    begin
      inc(i);

//      for (j=i ; (text[j] != '+') && (text[j] != '-') && (text[j] != 0) ; j++);
      j := i;
      while not (text[j] in ['+', '-', #0]) do inc(j); // JVAL ??

      c := PCharArray(text)[j];
      PByteArray(text)[j] := 0;

      Q_strcat(build, text + i);
      Q_strcat(build, #10);
      text[j] := c;
      i := j - 1;
    end;
    inc(i);
  end;

  if PByteArray(build)[0] <> 0 then
    Cbuf_InsertText(build);

  Z_Free(text);
  Z_Free(build);
end;


(*
===============
Cmd_Exec_f
===============
*)

procedure Cmd_Exec_f;
var
  f: PChar;
  mark: integer;
begin
  if Cmd_Argc_f <> 2 then
  begin
    Con_Printf('exec <filename> : execute a script file'#10);
    exit;
  end;

  mark := Hunk_LowMark;
  f := PChar(COM_LoadHunkFile(Cmd_Argv_f(1)));
  if f = nil then
  begin
    Con_Printf('couldn''t exec %s'#10, [Cmd_Argv_f(1)]);
    exit;
  end;

  Con_Printf('execing %s'#10, [Cmd_Argv_f(1)]);

  Cbuf_InsertText(f);
  Hunk_FreeToLowMark(mark);
end;


(*
===============
Cmd_Echo_f

Just prints the rest of the line to the console
===============
*)

procedure Cmd_Echo_f;
var
  i: integer;
begin
  for i := 1 to Cmd_Argc_f - 1 do
    Con_Printf('%s ', [Cmd_Argv_f(i)]);
  Con_Printf(#10);
end;

(*
===============
Cmd_Alias_f

Creates a new command that executes a command string (possibly ; seperated)
===============
*)

function CopyString(_in: PChar): PChar;
var
  _out: PChar;
begin
  _out := Z_Malloc(strlen(_in) + 1);
  strcpy(_out, _in);
  result := _out;
end;

procedure Cmd_Alias_f;
var
  a: Pcmdalias_t;
  cmd: array[0..1023] of char;
  i, c: integer;
  s: PChar;
begin
  if Cmd_Argc_f = 1 then
  begin
    Con_Printf('Current alias commands:'#10);
    a := cmd_alias;
    while a <> nil do
    begin
      Con_Printf('%s : %s'#10, [a.name, a.value]);
      a := a.next;
    end;

    exit;
  end;

  s := Cmd_Argv_f(1);
  if strlen(s) >= MAX_ALIAS_NAME then
  begin
    Con_Printf('Alias name is too long'#10);
    exit;
  end;

  // if the alias allready exists, reuse it
  a := cmd_alias;
  while a <> nil do
  begin
    if strcmp(s, a.name) = 0 then
    begin
      Z_Free(a.value);
      break;
    end;
    a := a.next;
  end;

  if a = nil then
  begin
    a := Z_Malloc(SizeOf(cmdalias_t));
    a.next := cmd_alias;
    cmd_alias := a;
  end;
  strcpy(a.name, s);

// copy the rest of the command line
  cmd[0] := #0; // start out with a null string
  c := Cmd_Argc_f;
  for i := 2 to c - 1 do
  begin
    strcat(cmd, Cmd_Argv_f(i));
    if i <> c then
      strcat(cmd, ' ');
  end;
  strcat(cmd, #10);

  a.value := CopyString(cmd);
end;

(*
=============================================================================

          COMMAND EXECUTION

=============================================================================
*)

type
  Pcmd_function_t = ^cmd_function_t;
  cmd_function_t = record
    next: Pcmd_function_t;
    name: PChar;
    _function: xcommand_t;
  end;

const
  MAX_ARGS = 80;

var
  cmd_argc: integer;
  cmd_argv: array[0..MAX_ARGS - 1] of PChar;
  cmd_null_string: PChar = '';
  cmd_args: PChar = nil;

  cmd_functions: Pcmd_function_t; // possible commands to execute

(*
============
Cmd_Init
============
*)

procedure Cmd_Init;
begin
//
// register our commands
//
  Cmd_AddCommand('stuffcmds', Cmd_StuffCmds_f);
  Cmd_AddCommand('exec', Cmd_Exec_f);
  Cmd_AddCommand('echo', Cmd_Echo_f);
  Cmd_AddCommand('alias', Cmd_Alias_f);
  Cmd_AddCommand('cmd', Cmd_ForwardToServer);
  Cmd_AddCommand('wait', Cmd_Wait_f);
end;

(*
============
Cmd_Argc_f
============
*)

function Cmd_Argc_f: integer;
begin
  result := cmd_argc;
end;

(*
============
Cmd_Argv_f
============
*)

function Cmd_Argv_f(arg: integer): PChar;
begin
  if arg >= cmd_argc then
    result := cmd_null_string
  else
    result := cmd_argv[arg];
end;

(*
============
Cmd_Args_f
============
*)

function Cmd_Args_f: PChar;
begin
  result := cmd_args;
end;


(*
============
Cmd_TokenizeString

Parses the given string into command line tokens.
============
*)

procedure Cmd_TokenizeString(text: PChar);
var
  i: integer;
begin
// clear the args from the last string
  for i := 0 to cmd_argc - 1 do
    Z_Free(cmd_argv[i]);

  cmd_argc := 0;
  cmd_args := nil;

  while true do
  begin
// skip whitespace up to a /n
    while (text^ <> #0) and (text^ <= ' ') and (text^ <> #10) and (text^ <> #13) do
      inc(text);

    if text^ in [#10, #13] then
      break; // a newline seperates commands in the buffer

    if text[0] = #0 then
      exit;

    if cmd_argc = 1 then
      cmd_args := text;

    text := COM_Parse(text);
    if text = nil then
      exit;

    if cmd_argc < MAX_ARGS then
    begin
      cmd_argv[cmd_argc] := Z_Malloc(Q_strlen(com_token) + 1);
      Q_strcpy(cmd_argv[cmd_argc], com_token);
      inc(cmd_argc);
    end;
  end;
end;


(*
============
Cmd_AddCommand
============
*)

procedure Cmd_AddCommand(cmd_name: PChar; _function: xcommand_t);
var
  cmd: Pcmd_function_t;
begin
  if host_initialized then // because hunk allocation would get stomped
    Sys_Error('Cmd_AddCommand after host_initialized');

// fail if the command is a variable name
  if boolval(Cvar_VariableString(cmd_name)[0]) then
  begin
    Con_Printf('Cmd_AddCommand: %s already defined as a var'#10, [cmd_name]);
    exit;
  end;

// fail if the command already exists
  cmd := cmd_functions;
  while cmd <> nil do
  begin
    if Q_strcmp(cmd_name, cmd.name) = 0 then
    begin
      Con_Printf('Cmd_AddCommand: %s already defined'#10, [cmd_name]);
      exit;
    end;
    cmd := cmd.next;
  end;

  cmd := Hunk_Alloc(SizeOf(cmd_function_t));
  cmd.name := cmd_name;
  cmd._function := _function;
  cmd.next := cmd_functions;
  cmd_functions := cmd;
end;

(*
============
Cmd_Exists
============
*)

function Cmd_Exists(cmd_name: PChar): qboolean;
var
  cmd: Pcmd_function_t;
begin
  cmd := cmd_functions;
  while cmd <> nil do
  begin
    if Q_strcmp(cmd_name, cmd.name) = 0 then
    begin
      result := true;
      exit;
    end;
    cmd := cmd.next;
  end;

  result := false;
end;



(*
============
Cmd_CompleteCommand
============
*)

function Cmd_CompleteCommand(partial: PChar): PChar;
var
  cmd: Pcmd_function_t;
  len: integer;
begin
  len := Q_strlen(partial);

  if len = 0 then
  begin
    result := nil;
    exit;
  end;

// check functions
  cmd := cmd_functions;
  while cmd <> nil do
  begin
    if Q_strncmp(partial, cmd.name, len) = 0 then
    begin
      result := cmd.name;
      exit;
    end;
    cmd := cmd.next;
  end;

  result := nil;
end;

(*
============
Cmd_ExecuteString

A complete command line has been parsed, so try to execute it
FIXME: lookupnoadd the token to speed search?
============
*)

procedure Cmd_ExecuteString(text: PChar; src: cmd_source_t);
var
  cmd: Pcmd_function_t;
  a: Pcmdalias_t;
begin
  cmd_source := src;
  Cmd_TokenizeString(text);

// execute the command line
  if Cmd_Argc_f = 0 then
    exit; // no tokens

// check functions
  cmd := cmd_functions;
  while cmd <> nil do
  begin
    if Q_strcasecmp(cmd_argv[0], cmd.name) = 0 then
    begin
      cmd._function;
      exit;
    end;
    cmd := cmd.next;
  end;

// check alias
  a := cmd_alias;
  while a <> nil do
  begin
    if Q_strcasecmp(cmd_argv[0], a.name) = 0 then
    begin
      Cbuf_InsertText(a.value);
      exit;
    end;
    a := a.next;
  end;

// check cvars
  if not Cvar_Command then
    Con_Printf('Unknown command "%s"'#10, [Cmd_Argv_f(0)]);

end;


(*
===================
Cmd_ForwardToServer

Sends the entire command line over to the server
===================
*)

procedure Cmd_ForwardToServer;
begin
  if cls.state <> ca_connected then
  begin
    Con_Printf('Can''t "%s", not connected'#10, [Cmd_Argv_f(0)]);
    exit;
  end;

  if cls.demoplayback then
    exit; // not really connected

  MSG_WriteByte(@cls._message, clc_stringcmd);
  if Q_strcasecmp(Cmd_Argv_f(0), 'cmd') <> 0 then
  begin
    SZ_Print(@cls._message, Cmd_Argv_f(0));
    SZ_Print(@cls._message, ' ');
  end;

  if Cmd_Argc_f > 1 then
    SZ_Print(@cls._message, Cmd_Args_f)
  else
    SZ_Print(@cls._message, #10);
end;


(*
================
Cmd_CheckParm

Returns the position (1 to argc-1) in the command's argument list
where the given parameter apears, or 0 if not present
================
*)

function Cmd_CheckParm(parm: PChar): integer;
var
  i: integer;
begin
  if parm = nil then
    Sys_Error('Cmd_CheckParm: NULL');

  for i := 1 to Cmd_Argc_f - 1 do
    if Q_strcasecmp(parm, Cmd_Argv_f(i)) = 0 then
    begin
      result := i;
      exit;
    end;

  result := 0;
end;

end.

 