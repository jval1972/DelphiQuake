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

unit keys;

interface

uses
  q_delphi;

procedure Key_ProcessEvent(key: integer; down: qboolean);
procedure Key_Init;
procedure Key_WriteBindings(var f: text);
procedure Key_SetBinding(keynum: integer; binding: PChar);
procedure Key_ClearStates;
function Key_KeynumToString(keynum: integer): PChar;

type
  keydest_t = (key_game, key_console, key_message, key_menu);

var
  key_dest: keydest_t;

const
  MAXCMDLINE = 256;

var
  key_lines: array[0..31] of array[0..MAXCMDLINE - 1] of char;

var
  keybindings: array[0..255] of PChar;
  key_linepos: integer;
  key_lastpress: integer;
  edit_line: integer = 0;
  key_count: integer; // incremented every key event

//============================================================================

const
  CHARBUFFERLENGTH = 32; // JVAL make this bigger??

var
  chat_buffer: array[0..CHARBUFFERLENGTH - 1] of char;
  team_message: qboolean = false;

var
  chat_bufferlen: integer = 0;


implementation

uses
  cmd,
  keys_h,
  console,
  cl_main_h,
  client,
  gl_screen,
  cvar,
  common,
  gl_vidnt,
  zone,
  menu,
  sys_win;

(*

key up events are sent even if in console mode

*)

var
  shift_down: qboolean = false;

  history_line: integer = 0;

var
  consolekeys: array[0..255] of qboolean; // if true, can't be rebound while in console
  menubound: array[0..255] of qboolean; // if true, can't be rebound while in menu
  keyshift: array[0..255] of integer; // key to map to if shift held down in console
  key_repeats: array[0..255] of integer; // if > 1, it is autorepeating
  keydown: array[0..255] of qboolean;


type
  keyname_t = record
    name: PChar;
    keynum: integer;
  end;
  Pkeyname_t = ^keyname_t;

const
  NUMKEYNAMES = 74;

  keynames: array[0..NUMKEYNAMES - 1] of keyname_t = (
    (name: 'TAB'; keynum: K_TAB),
    (name: 'ENTER'; keynum: K_ENTER),
    (name: 'ESCAPE'; keynum: K_ESCAPE),
    (name: 'SPACE'; keynum: K_SPACE),
    (name: 'BACKSPACE'; keynum: K_BACKSPACE),
    (name: 'UPARROW'; keynum: K_UPARROW),
    (name: 'DOWNARROW'; keynum: K_DOWNARROW),
    (name: 'LEFTARROW'; keynum: K_LEFTARROW),
    (name: 'RIGHTARROW'; keynum: K_RIGHTARROW),

    (name: 'ALT'; keynum: K_ALT),
    (name: 'CTRL'; keynum: K_CTRL),
    (name: 'SHIFT'; keynum: K_SHIFT),

    (name: 'F1'; keynum: K_F1),
    (name: 'F2'; keynum: K_F2),
    (name: 'F3'; keynum: K_F3),
    (name: 'F4'; keynum: K_F4),
    (name: 'F5'; keynum: K_F5),
    (name: 'F6'; keynum: K_F6),
    (name: 'F7'; keynum: K_F7),
    (name: 'F8'; keynum: K_F8),
    (name: 'F9'; keynum: K_F9),
    (name: 'F10'; keynum: K_F10),
    (name: 'F11'; keynum: K_F11),
    (name: 'F12'; keynum: K_F12),

    (name: 'INS'; keynum: K_INS),
    (name: 'DEL'; keynum: K_DEL),
    (name: 'PGDN'; keynum: K_PGDN),
    (name: 'PGUP'; keynum: K_PGUP),
    (name: 'HOME'; keynum: K_HOME),
    (name: 'END'; keynum: K_END),

    (name: 'MOUSE1'; keynum: K_MOUSE1),
    (name: 'MOUSE2'; keynum: K_MOUSE2),
    (name: 'MOUSE3'; keynum: K_MOUSE3),

    (name: 'JOY1'; keynum: K_JOY1),
    (name: 'JOY2'; keynum: K_JOY2),
    (name: 'JOY3'; keynum: K_JOY3),
    (name: 'JOY4'; keynum: K_JOY4),

    (name: 'AUX1'; keynum: K_AUX1),
    (name: 'AUX2'; keynum: K_AUX2),
    (name: 'AUX3'; keynum: K_AUX3),
    (name: 'AUX4'; keynum: K_AUX4),
    (name: 'AUX5'; keynum: K_AUX5),
    (name: 'AUX6'; keynum: K_AUX6),
    (name: 'AUX7'; keynum: K_AUX7),
    (name: 'AUX8'; keynum: K_AUX8),
    (name: 'AUX9'; keynum: K_AUX9),
    (name: 'AUX10'; keynum: K_AUX10),
    (name: 'AUX11'; keynum: K_AUX11),
    (name: 'AUX12'; keynum: K_AUX12),
    (name: 'AUX13'; keynum: K_AUX13),
    (name: 'AUX14'; keynum: K_AUX14),
    (name: 'AUX15'; keynum: K_AUX15),
    (name: 'AUX16'; keynum: K_AUX16),
    (name: 'AUX17'; keynum: K_AUX17),
    (name: 'AUX18'; keynum: K_AUX18),
    (name: 'AUX19'; keynum: K_AUX19),
    (name: 'AUX20'; keynum: K_AUX20),
    (name: 'AUX21'; keynum: K_AUX21),
    (name: 'AUX22'; keynum: K_AUX22),
    (name: 'AUX23'; keynum: K_AUX23),
    (name: 'AUX24'; keynum: K_AUX24),
    (name: 'AUX25'; keynum: K_AUX25),
    (name: 'AUX26'; keynum: K_AUX26),
    (name: 'AUX27'; keynum: K_AUX27),
    (name: 'AUX28'; keynum: K_AUX28),
    (name: 'AUX29'; keynum: K_AUX29),
    (name: 'AUX30'; keynum: K_AUX30),
    (name: 'AUX31'; keynum: K_AUX31),
    (name: 'AUX32'; keynum: K_AUX32),

    (name: 'PAUSE'; keynum: K_PAUSE),

    (name: 'MWHEELUP'; keynum: K_MWHEELUP),
    (name: 'MWHEELDOWN'; keynum: K_MWHEELDOWN),

    (name: 'SEMICOLON'; keynum: Ord(';')), // because a raw semicolon seperates commands

    (name: nil; keynum: 0)
    );

(*
==============================================================================

      LINE TYPING INTO THE CONSOLE

==============================================================================
*)


(*
====================
Key_Console

Interactive line editing and console scrollback
====================
*)

procedure Key_Console_f(key: integer);
var
  cmd: PChar;
begin
  if key = K_ENTER then
  begin
    Cbuf_AddText(@key_lines[edit_line][1]); // skip the > // JVAL check!
    Cbuf_AddText(#10);
    Con_Printf('%s'#10, [key_lines[edit_line]]);
    edit_line := (edit_line + 1) and 31;
    history_line := edit_line;
    key_lines[edit_line][0] := ']';
    key_linepos := 1;
    if cls.state = ca_disconnected then
      SCR_UpdateScreen; // force an update, because the command
                        // may take some time
    exit;
  end;

  if key = K_TAB then
  begin // command completion
    cmd := Cmd_CompleteCommand(@key_lines[edit_line][1]); // JVAL check!
    if cmd = nil then
      cmd := Cvar_CompleteVariable(@key_lines[edit_line][1]);
    if cmd <> nil then
    begin
      Q_strcpy(@key_lines[edit_line][1], cmd);
      key_linepos := Q_strlen(cmd) + 1;
      key_lines[edit_line][key_linepos] := ' ';
      inc(key_linepos);
      key_lines[edit_line][key_linepos] := #0;
      exit;
    end;
  end;

  if (key = K_BACKSPACE) or (key = K_LEFTARROW) then
  begin
    if key_linepos > 1 then
      dec(key_linepos); // JVAL mayby add PlaySound(!!!) ??
    exit;
  end;

  if key = K_UPARROW then
  begin
    repeat
      history_line := (history_line - 1) and 31;
    until not ((history_line <> edit_line) and not boolval(key_lines[history_line][1])); // JVAL SOS
    if history_line = edit_line then
      history_line := (edit_line + 1) and 31;
    Q_strcpy(key_lines[edit_line], key_lines[history_line]);
    key_linepos := Q_strlen(key_lines[edit_line]);
    exit;
  end;

  if key = K_DOWNARROW then
  begin
    if history_line = edit_line then
      exit;
    repeat
      history_line := (history_line + 1) and 31;
    until not ((history_line <> edit_line) and not boolval(key_lines[history_line][1])); // JVAL SOS
    if history_line = edit_line then
    begin
      key_lines[edit_line][0] := ']';
      key_linepos := 1;
    end
    else
    begin
      Q_strcpy(key_lines[edit_line], key_lines[history_line]);
      key_linepos := Q_strlen(key_lines[edit_line]);
    end;
    exit;
  end;

  if (key = K_PGUP) or (key = K_MWHEELUP) then
  begin
    con_backscroll := con_backscroll + 2;
    if con_backscroll > con_totallines - (vid.height shr 3) - 1 then
      con_backscroll := con_totallines - (vid.height shr 3) - 1;
    exit;
  end;

  if (key = K_PGDN) or (key = K_MWHEELDOWN) then
  begin
    con_backscroll := con_backscroll - 2;
    if con_backscroll < 0 then
      con_backscroll := 0;
    exit;
  end;

  if key = K_HOME then
  begin
    con_backscroll := con_totallines - (vid.height shr 3) - 1;
    exit;
  end;

  if key = K_END then
  begin
    con_backscroll := 0;
    exit;
  end;

  if (key < 32) or (key > 127) then
    exit; // non printable

  if key_linepos < MAXCMDLINE - 1 then
  begin
    key_lines[edit_line][key_linepos] := Chr(key);
    inc(key_linepos);
    key_lines[edit_line][key_linepos] := #0;
  end;
end;

procedure Key_Message_f(key: integer);
begin
  if key = K_ENTER then
  begin
    if team_message then
      Cbuf_AddText('say_team "')
    else
      Cbuf_AddText('say "');
    Cbuf_AddText(chat_buffer);
    Cbuf_AddText('"'#10);

    key_dest := key_game;
    chat_bufferlen := 0;
    chat_buffer[0] := #0;
    exit;
  end;

  if key = K_ESCAPE then
  begin
    key_dest := key_game;
    chat_bufferlen := 0;
    chat_buffer[0] := #0;
    exit;
  end;

  if (key < 32) or (key > 127) then
    exit; // non printable

  if key = K_BACKSPACE then
  begin
    if chat_bufferlen > 0 then
    begin
      dec(chat_bufferlen);
      chat_buffer[chat_bufferlen] := #0;
    end;
    exit;
  end;

  if chat_bufferlen = CHARBUFFERLENGTH - 1 then
    exit; // all full

  chat_buffer[chat_bufferlen] := Chr(key);
  inc(chat_bufferlen);
  chat_buffer[chat_bufferlen] := #0;
end;

//============================================================================


(*
===================
Key_StringToKeynum

Returns a key number to be used to index keybindings[] by looking at
the given string.  Single ascii characters return themselves, while
the K_* names are matched up.
===================
*)

function Key_StringToKeynum(str: PChar): integer;
var
  kn: Pkeyname_t;
begin
  if (str = nil) or (str[0] = #0) then
  begin
    result := -1;
    exit;
  end;

  if str[1] = #0 then
  begin
    result := Ord(str[0]);
    exit;
  end;

  kn := @keynames[0];
  while kn.name <> nil do
  begin
    if Q_strcasecmp(str, kn.name) = 0 then
    begin
      result := kn.keynum;
      exit;
    end;
    inc(kn);
  end;
  result := -1;
end;

(*
===================
Key_KeynumToString

Returns a string (either a single ascii char, or a K_* name) for the
given keynum.
FIXME: handle quote special (general escape sequence?)
===================
*)
var
  tinystr: array[0..1] of char;

function Key_KeynumToString(keynum: integer): PChar;
var
  kn: Pkeyname_t;
begin
  if keynum = -1 then
  begin
    result := '<KEY NOT FOUND>';
    exit;
  end;
  if (keynum > 32) and (keynum < 127) then
  begin // printable ascii
    tinystr[0] := Chr(keynum);
    tinystr[1] := #0;
    result := @tinystr[0];
    exit;
  end;

  kn := @keynames[0];
  while kn.name <> nil do
  begin
    if keynum = kn.keynum then
    begin
      result := kn.name;
      exit;
    end;
    inc(kn);
  end;

  result := '<UNKNOWN KEYNUM>';
end;


(*
===================
Key_SetBinding
===================
*)

procedure Key_SetBinding(keynum: integer; binding: PChar);
var
  n: PChar;
  l: integer;
begin
  if keynum = -1 then
    exit;

// free old bindings
  if keybindings[keynum] <> nil then
  begin
    Z_Free(keybindings[keynum]);
    keybindings[keynum] := nil;
  end;

// allocate memory for new binding
  l := Q_strlen(binding);
  n := Z_Malloc(l + 1);
  Q_strcpy(n, binding);
  n[l] := #0;
  keybindings[keynum] := n;
end;

(*
===================
Key_Unbind_f
===================
*)

procedure Key_Unbind_f;
var
  b: integer;
begin
  if Cmd_Argc_f <> 2 then
  begin
    Con_Printf('unbind <key> : remove commands from a key'#10);
    exit;
  end;

  b := Key_StringToKeynum(Cmd_Argv_f(1));
  if b = -1 then
  begin
    Con_Printf('"%s" isn''t a valid key'#10, [Cmd_Argv_f(1)]);
    exit;
  end;

  Key_SetBinding(b, '');
end;

procedure Key_Unbindall_f;
var
  i: integer;
begin
  for i := 0 to 255 do
    if keybindings[i] <> nil then
      Key_SetBinding(i, '');
end;


(*
===================
Key_Bind_f
===================
*)

procedure Key_Bind_f;
var
  i, c, b: integer;
  cmd: array[0..1023] of char;
begin
  c := Cmd_Argc_f;

  if (c <> 2) and (c <> 3) then
  begin
    Con_Printf('bind <key> [command] : attach a command to a key'#10);
    exit;
  end;
  b := Key_StringToKeynum(Cmd_Argv_f(1));
  if b = -1 then
  begin
    Con_Printf('"%s" isn''t a valid key'#10, [Cmd_Argv_f(1)]);
    exit;
  end;

  if c = 2 then
  begin
    if keybindings[b] <> nil then
      Con_Printf('"%s" = "%s"'#10, [Cmd_Argv_f(1), keybindings[b]])
    else
      Con_Printf('"%s" is not bound'#10, [Cmd_Argv_f(1)]);
    exit;
  end;

// copy the rest of the command line
  cmd[0] := #0; // start out with a null string
  for i := 2 to c - 1 do
  begin
    if i > 2 then
      strcat(cmd, ' ');
    strcat(cmd, Cmd_Argv_f(i));
  end;

  Key_SetBinding(b, cmd);
end;

(*
============
Key_WriteBindings

Writes lines containing "bind key value"
============
*)

procedure Key_WriteBindings(var f: text);
var
  i: integer;
begin
  for i := 0 to 255 do
    if keybindings[i] <> nil then
      if boolval(keybindings[i]^) then
        fprintf(f, 'bind "%s" "%s"'#10, [Key_KeynumToString(i), keybindings[i]]);
end;


(*
===================
Key_Init
===================
*)

procedure Key_Init;
var
  i: integer;
begin
  for i := 0 to 31 do
  begin
    key_lines[i][0] := ']';
    key_lines[i][1] := #0;
  end;
  key_linepos := 1;

//
// init ascii characters in console mode
//
  for i := 32 to 127 do
    consolekeys[i] := true;
  consolekeys[K_ENTER] := true;
  consolekeys[K_TAB] := true;
  consolekeys[K_LEFTARROW] := true;
  consolekeys[K_RIGHTARROW] := true;
  consolekeys[K_UPARROW] := true;
  consolekeys[K_DOWNARROW] := true;
  consolekeys[K_BACKSPACE] := true;
  consolekeys[K_PGUP] := true;
  consolekeys[K_PGDN] := true;
  consolekeys[K_SHIFT] := true;
  consolekeys[K_MWHEELUP] := true;
  consolekeys[K_MWHEELDOWN] := true;
  consolekeys[Ord('`')] := false;
  consolekeys[Ord('~')] := false;

  for i := 0 to 255 do
    keyshift[i] := i;
  for i := Ord('a') to Ord('z') do
    keyshift[i] := i - Ord('a') + Ord('A');
  keyshift[Ord('1')] := Ord('!');
  keyshift[Ord('2')] := Ord('@');
  keyshift[Ord('3')] := Ord('#');
  keyshift[Ord('4')] := Ord('$');
  keyshift[Ord('5')] := Ord('%');
  keyshift[Ord('6')] := Ord('^');
  keyshift[Ord('7')] := Ord('&');
  keyshift[Ord('8')] := Ord('*');
  keyshift[Ord('9')] := Ord('(');
  keyshift[Ord('0')] := Ord(')');
  keyshift[Ord('-')] := Ord('_');
  keyshift[Ord('=')] := Ord('+');
  keyshift[Ord(',')] := Ord('<');
  keyshift[Ord('.')] := Ord('>');
  keyshift[Ord('/')] := Ord('?');
  keyshift[Ord(';')] := Ord(':');
  keyshift[Ord('''')] := Ord('"');
  keyshift[Ord('[')] := Ord('{');
  keyshift[Ord(']')] := Ord('}');
  keyshift[Ord('`')] := Ord('~');
  keyshift[Ord('\')] := Ord('|');

  menubound[K_ESCAPE] := true;
  for i := 0 to 11 do
    menubound[K_F1 + i] := true;

//
// register our functions
//
  Cmd_AddCommand('bind', Key_Bind_f);
  Cmd_AddCommand('unbind', Key_Unbind_f);
  Cmd_AddCommand('unbindall', Key_Unbindall_f);
end;


(*
===================
Key_ProcessEvent

Called by the system between frames for both key up and key down events
Should NOT be called during an interrupt!
===================
*)

procedure Key_ProcessEvent(key: integer; down: qboolean);
var
  kb: PChar;
  cmd: array[0..1023] of char;
begin
  keydown[key] := down;

  if not down then
    key_repeats[key] := 0;

  key_lastpress := key;
  inc(key_count);
  if key_count <= 0 then
    exit; // just catching keys for Con_NotifyBox


// update auto-repeat status
  if down then
  begin
    inc(key_repeats[key]);
    if (key <> K_BACKSPACE) and (key <> K_PAUSE) and (key_repeats[key] > 1) then
      exit; // ignore most autorepeats

    if (key >= 200) and (keybindings[key] = nil) then
      Con_Printf('%s is unbound, hit F4 to set.'#10, [Key_KeynumToString(key)]);
  end;

  if key = K_SHIFT then
    shift_down := down;

//
// handle escape specialy, so the user can never unbind it
//
  if key = K_ESCAPE then
  begin
    if not down then
      exit;
    case key_dest of
      key_message:
        Key_Message_f(key);
      key_menu: M_Keydown(key);
      key_game,
        key_console:
        M_ToggleMenu_f;
    else
      Sys_Error('Bad key_dest');
    end;
    exit;
  end;

//
// key up events only generate commands if the game key binding is
// a button command (leading + sign).  These will occur even in console mode,
// to keep the character from continuing an action started before a console
// switch.  Button commands include the kenum as a parameter, so multiple
// downs can be matched with ups
//
  if not down then
  begin
    kb := keybindings[key];
    if (kb <> nil) and (kb[0] = '+') then
    begin
      sprintf(cmd, '-%s %d'#10, [PChar(@kb[1]), key]);
      Cbuf_AddText(cmd);
    end;
    if keyshift[key] <> key then
    begin
      kb := keybindings[keyshift[key]];
      if (kb <> nil) and (kb[0] = '+') then
      begin
        sprintf(cmd, '-%s %d'#10, [@kb[1], key]);
        Cbuf_AddText(cmd);
      end;
    end;
    exit;
  end;

//
// during demo playback, most keys bring up the main menu
//
  if cls.demoplayback and down and consolekeys[key] and (key_dest = key_game) then
  begin
    M_ToggleMenu_f;
    exit;
  end;

//
// if not a consolekey, send to the interpreter no matter what mode is
//
  if ((key_dest = key_menu) and menubound[key]) or
    ((key_dest = key_console) and not consolekeys[key]) or
    ((key_dest = key_game) and (not con_forcedup or not consolekeys[key])) then
  begin
    kb := keybindings[key];
    if kb <> nil then
    begin
      if kb[0] = '+' then
      begin // button commands add keynum as a parm
        sprintf(cmd, '%s %d'#10, [kb, key]);
        Cbuf_AddText(cmd);
      end
      else
      begin
        Cbuf_AddText(kb);
        Cbuf_AddText(#10);
      end;
    end;
    exit;
  end;

  if not down then
    exit; // other systems only care about key down events

  if shift_down then
    key := keyshift[key];

  case key_dest of
    key_message:
      Key_Message_f(key);
    key_menu:
      M_Keydown(key);
    key_game,
    key_console:
      Key_Console_f(key);

  else
    Sys_Error('Bad key_dest');
  end;
end;


(*
===================
Key_ClearStates
===================
*)

procedure Key_ClearStates;
var
  i: integer;
begin
  for i := 0 to 255 do
  begin
    keydown[i] := false;
    key_repeats[i] := 0;
  end;
end;


end.

