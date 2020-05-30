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

unit console;

interface

// console.c

uses
  q_delphi,
  cvar;

var
  con_linewidth: integer;

  con_cursorspeed: single = 4;

const
  CON_TEXTSIZE = 16384;

var
  con_forcedup: qboolean; // because no entities to refresh

  con_totallines: integer; // total lines in console scrollback
  con_backscroll: integer; // lines up from bottom to display
  con_current: integer; // where next message will be printed
  con_x: integer; // offset in current line for next print
  con_text: PChar = nil;

  con_notifytime: cvar_t =
  (name: 'con_notifytime'; text: '3'); //seconds

const
  NUM_CON_TIMES = 4;

var
  con_times: array[0..NUM_CON_TIMES - 1] of single; // realtime time the line was generated
                                                    // for transparent notify lines
  con_vislines: integer;

  con_dodebuglog: qboolean;

const
  MAXCMDLINE = 256;

var
  con_initialized: qboolean = false;

  con_notifylines: integer; // scan lines to clear for notify lines

procedure Con_ToggleConsole_f;
procedure Con_Clear_f;
procedure Con_ClearNotify;
procedure Con_MessageMode_f;
procedure Con_MessageMode2_f;
procedure Con_CheckResize;
procedure Con_Init;
procedure Con_Linefeed;
procedure Con_Print(txt: PChar);
procedure Con_DebugLog(filename: PChar; fmt: PChar; const Args: array of const);
procedure Con_Printf(fmt: PChar); overload;
procedure Con_Printf(fmt: PChar; const Args: array of const); overload;
procedure Con_Printf(fmt: string); overload;
procedure Con_Printf(fmt: string; const Args: array of const); overload;
procedure Con_DPrintf(fmt: PChar); overload;
procedure Con_DPrintf(fmt: PChar; const Args: array of const); overload;
procedure Con_DPrintf(fmt: string); overload;
procedure Con_DPrintf(fmt: string; const Args: array of const); overload;
procedure Con_SafePrintf(fmt: PChar); overload;
procedure Con_SafePrintf(fmt: PChar; const Args: array of const); overload;
procedure Con_SafePrintf(fmt: string); overload;
procedure Con_SafePrintf(fmt: string; const Args: array of const); overload;
procedure Con_DrawInput;
procedure Con_DrawNotify;
procedure Con_DrawConsole(lines: integer; drawinput: qboolean);
procedure Con_NotifyBox(text: PChar);

const
  CON_LINE = #29#30#30#30#30#30#30#30#30#30#30#30#30#30#30#30#30#30#30#30#30#30#30#30#30#30#30#30#30#30#30#30#30#30#30#30#31;
implementation

uses
  keys,
  cl_main_h,
  client,
  menu,
  gl_screen,
  common,
  gl_vidnt,
  zone,
  cmd,
  snd_dma,
  host_h,
  sys_win,
  gl_draw;

(*
================
Con_ToggleConsole_f
================
*)

procedure Con_ToggleConsole_f;
begin
  if key_dest = key_console then
  begin
    if cls.state = ca_connected then
    begin
      key_dest := key_game;
      key_lines[edit_line][1] := #0; // clear any typing
      key_linepos := 1;
    end
    else
    begin
      M_Menu_Main_f;
    end;
  end
  else
    key_dest := key_console;

  SCR_EndLoadingPlaque;
  ZeroMemory(@con_times, SizeOf(con_times));
end;

(*
================
Con_Clear_f
================
*)

procedure Con_Clear_f;
begin
  if con_text <> nil then
    memset(con_text, Ord(' '), CON_TEXTSIZE);
end;


(*
================
Con_ClearNotify
================
*)

procedure Con_ClearNotify;
var
  i: integer;
begin
  for i := 0 to NUM_CON_TIMES - 1 do
    con_times[i] := 0;
end;


(*
================
Con_MessageMode_f
================
*)

procedure Con_MessageMode_f;
begin
  key_dest := key_message;
  team_message := false;
end;


(*
================
Con_MessageMode2_f
================
*)

procedure Con_MessageMode2_f;
begin
  key_dest := key_message;
  team_message := true;
end;


(*
================
Con_CheckResize

If the line width has changed, reformat the buffer.
================
*)

procedure Con_CheckResize;
var
  i, j, width, oldwidth, oldtotallines, numlines, numchars: integer;
  tbuf: array[0..CON_TEXTSIZE - 1] of char;
begin
  width := (vid.width div 8) - 2;

  if width = con_linewidth then
    exit;

  if width < 1 then // video hasn't been initialized yet
  begin
    width := 38;
    con_linewidth := width;
    con_totallines := CON_TEXTSIZE div con_linewidth;
    memset(con_text, Ord(' '), CON_TEXTSIZE);
  end
  else
  begin
    oldwidth := con_linewidth;
    con_linewidth := width;
    oldtotallines := con_totallines;
    con_totallines := CON_TEXTSIZE div con_linewidth;
    numlines := oldtotallines;

    if con_totallines < numlines then
      numlines := con_totallines;

    numchars := oldwidth;

    if con_linewidth < numchars then
      numchars := con_linewidth;

    memcpy(@tbuf, con_text, CON_TEXTSIZE);
    memset(con_text, Ord(' '), CON_TEXTSIZE);

    for i := 0 to numlines - 1 do
    begin
      for j := 0 to numchars - 1 do
      begin
        con_text[(con_totallines - 1 - i) * con_linewidth + j] :=
          tbuf[((con_current - i + oldtotallines) mod oldtotallines) * oldwidth + j];
      end;
    end;

    Con_ClearNotify;
  end;

  con_backscroll := 0;
  con_current := con_totallines - 1;
end;


(*
================
Con_Init
================
*)

procedure Con_Init;
const
  MAXGAMEDIRLEN = 1000;
var
  temp: array[0..MAXGAMEDIRLEN] of char;
  t2: PChar;
begin
  t2 := '/qconsole.log';

  con_dodebuglog := COM_CheckParm('-condebug') <> 0;

  if con_dodebuglog then
  begin
    if strlen(com_gamedir) < (MAXGAMEDIRLEN - strlen(t2)) then
    begin
      sprintf(temp, '%s%s', [com_gamedir, t2]);
      unlink(temp);
    end;
  end;

  con_text := Hunk_AllocName(CON_TEXTSIZE, 'context');
  memset(con_text, Ord(' '), CON_TEXTSIZE);
  con_linewidth := -1;
  Con_CheckResize;

  Con_Printf('Console initialized.'#10);

//
// register our commands
//
  Cvar_RegisterVariable(@con_notifytime);

  Cmd_AddCommand('toggleconsole', Con_ToggleConsole_f);
  Cmd_AddCommand('messagemode', Con_MessageMode_f);
  Cmd_AddCommand('messagemode2', Con_MessageMode2_f);
  Cmd_AddCommand('clear', Con_Clear_f);
  con_initialized := true;
end;


(*
===============
Con_Linefeed
===============
*)

procedure Con_Linefeed;
begin
  con_x := 0;
  inc(con_current);
  memset(@con_text[(con_current mod con_totallines) * con_linewidth], Ord(' '), con_linewidth);
end;

(*
================
Con_Print

Handles cursor positioning, line wrapping, etc
All console printing must go through this in order to be logged to disk
If no console is visible, the notify window will pop up.
================
*)
var
  cr_Con_Print: qboolean = false;

procedure Con_Print(txt: PChar);
var
  y: integer;
  l: integer;
  c: char;
  mask: integer;
begin
  con_backscroll := 0;

  if txt[0] = #1 then
  begin
    mask := 128; // go to colored text
    S_LocalSound('misc/talk.wav');
  // play talk wav
    inc(txt);
  end
  else if txt[0] = #2 then
  begin
    mask := 128; // go to colored text
    inc(txt);
  end
  else
    mask := 0;

  while true do
  begin
    c := txt^;
    if c = #0 then break;

  // count word length
    for l := 0 to con_linewidth - 1 do
      if txt[l] <= ' ' then
        break;

  // word wrap
    if (l <> con_linewidth) and (con_x + l > con_linewidth) then
      con_x := 0;

    inc(txt);

    if cr_Con_Print then
    begin
      dec(con_current);
      cr_Con_Print := false;
    end;


    if con_x = 0 then
    begin
      Con_Linefeed;
    // mark time for transparent overlay
      if con_current >= 0 then
        con_times[con_current mod NUM_CON_TIMES] := realtime;
    end;

    case c of
      #10:
        begin
          con_x := 0;
        end;

      #13:
        begin
          con_x := 0;
          cr_Con_Print := true;
        end;

    else // display character and advance
      begin
        y := con_current mod con_totallines;
        con_text[y * con_linewidth + con_x] := Chr(Ord(c) or mask);
        inc(con_x);
        if con_x >= con_linewidth then
          con_x := 0;
      end;
    end;

  end;
end;


(*
================
Con_DebugLog
================
*)
var
  data_Con_DebugLog: array[0..1023] of char;

procedure Con_DebugLog(filename: PChar; fmt: PChar; const Args: array of const);
var
  fd: file;
  i: integer;
  c: char;
begin
  sprintf(data_Con_DebugLog, PChar(fmt + #10#0), Args); // JVAL check!
  if fopen(filename, 'rb', fd) then
  begin
    seek(fd, filesize(fd));
    for i := 0 to 1023 do
    begin
      c := data_Con_DebugLog[i];
      if c = #0 then
        break;
      fwrite(@c, 1, 1, fd);
    end;
    fclose(fd);
  end
  else
    Sys_Printf('Con_DebugLog: can''t write to %s'#10, [filename]);
end;


(*
================
Con_Printf

Handles cursor positioning, line wrapping, etc
================
*)
const
  MAXPRINTMSG = $10000;
// FIXME: make a buffer size safe vsprintf?
var
  inupdate_Con_Printf: qboolean = false;

procedure Con_Printf(fmt: PChar);
begin
  Con_Printf(fmt, []);
end;

procedure Con_Printf(fmt: string);
begin
  Con_Printf(PChar(fmt));
end;

procedure Con_Printf(fmt: string; const Args: array of const);
begin
  Con_Printf(PChar(fmt), Args);
end;

procedure Con_Printf(fmt: PChar; const Args: array of const);
var
  msg: array[0..MAXPRINTMSG - 1] of char;
begin
  sprintf(msg, fmt, Args);

// also echo to debugging console
  Sys_Printf('%s', [msg]); // also echo to debugging console

// log all messages to file
  if con_dodebuglog then
    Con_DebugLog(va('%s/qconsole.log', [com_gamedir]), '%s', [msg]);

  if not con_initialized then
    exit;

  if cls.state = ca_dedicated then
    exit; // no graphics mode

// write it to the scrollable buffer
  Con_Print(msg);

// update the screen if the console is displayed
  if (cls.signon <> SIGNONS) and not scr_disabled_for_loading then
  begin
  // protect against infinite loop if something in SCR_UpdateScreen calls
  // Con_Printd
    if not inupdate_Con_Printf then
    begin
      inupdate_Con_Printf := true;
      SCR_UpdateScreen;                         
      inupdate_Con_Printf := false;
    end;
  end;
end;

(*
================
Con_DPrintf

A Con_Printf that only shows up if the "developer" cvar is set
================
*)

procedure Con_DPrintf(fmt: PChar);
begin
  Con_DPrintf(fmt, []);
end;

procedure Con_DPrintf(fmt: PChar; const Args: array of const);
begin
  if boolval(developer.value) then // don't confuse non-developers with techie stuff...
    Con_Printf(fmt, Args);
end;

procedure Con_DPrintf(fmt: string);
begin
  Con_DPrintf(PChar(fmt));
end;

procedure Con_DPrintf(fmt: string; const Args: array of const); overload;
begin
  Con_DPrintf(PChar(fmt), Args);
end;

(*
==================
Con_SafePrintf

Okay to call even when the screen can't be updated
==================
*)

procedure Con_SafePrintf(fmt: PChar);
begin
  Con_SafePrintf(fmt, []);
end;

procedure Con_SafePrintf(fmt: PChar; const Args: array of const);
var
  msg: array[0..1023] of char;
  temp: qboolean;
begin
  sprintf(msg, fmt, Args);

  temp := scr_disabled_for_loading;
  scr_disabled_for_loading := true;
  Con_Printf('%s', [msg]);
  scr_disabled_for_loading := temp;
end;

procedure Con_SafePrintf(fmt: string);
begin
  Con_SafePrintf(PChar(fmt));
end;

procedure Con_SafePrintf(fmt: string; const Args: array of const); overload;
begin
  Con_SafePrintf(PChar(fmt), Args);
end;


(*
==============================================================================

DRAWING

==============================================================================
*)


(*
================
Con_DrawInput

The input line scrolls horizontally if typing goes beyond the right edge
================
*)

procedure Con_DrawInput;
var
  y: integer;
  i: integer;
  text: PChar;
begin
  if (key_dest <> key_console) and not con_forcedup then
    exit; // don't draw anything

  text := key_lines[edit_line];

// add the cursor frame
  text[key_linepos] := Chr(10 + intval(realtime * con_cursorspeed) and 1);

// fill out remainder with spaces
  for i := key_linepos + 1 to con_linewidth - 1 do
    text[i] := ' ';

//  prestep if horizontally scrolling
  if key_linepos >= con_linewidth then
    text := text + 1 + key_linepos - con_linewidth;

// draw it
  y := con_vislines - 16;

  for i := 0 to con_linewidth - 1 do
    Draw_Character(((i + 1) shl 3), y, text[i]);

// remove cursor
  key_lines[edit_line][key_linepos] := #0;
end;


(*
================
Con_DrawNotify

Draws the last few lines of output transparently over the game top
================
*)

procedure Con_DrawNotify;
var
  x, v: integer;
  text: PChar;
  i: integer;
  time: single;
//  extern char chat_buffer[]; JVAL ??
begin
  v := 0;
  for i := con_current - NUM_CON_TIMES + 1 to con_current do
  begin
    if i < 0 then
      continue;
    time := con_times[i mod NUM_CON_TIMES];
    if time = 0 then
      continue;
    time := realtime - time;
    if time > con_notifytime.value then
      continue;
    text := con_text + (i mod con_totallines) * con_linewidth;

    clearnotify := 0;
    scr_copytop := 1;

    for x := 0 to con_linewidth - 1 do
      Draw_Character(((x + 1) shl 3), v, text[x]);

    inc(v, 8);
  end;


  if key_dest = key_message then
  begin
    clearnotify := 0;
    scr_copytop := 1;

    x := 0;

    Draw_String(8, v, 'say:');
    while chat_buffer[x] <> '' do
    begin
      Draw_Character(((x + 5) shl 3), v, chat_buffer[x]);
      inc(x);
    end;
    Draw_Character(((x + 5) shl 3), v, 10 + intval(realtime * con_cursorspeed) and 1);
    inc(v, 8);
  end;

  if v > con_notifylines then
    con_notifylines := v;
end;

(*
================
Con_DrawConsole

Draws the console with the solid background
The typing input line at the bottom should only be drawn if typing is allowed
================
*)

procedure Con_DrawConsole(lines: integer; drawinput: qboolean);
var
  i, x, y: integer;
  rows: integer;
  text: PChar;
  j: integer;
begin
  if lines <= 0 then
    exit;

// draw the background
  Draw_ConsoleBackground(lines);

// draw the text
  con_vislines := lines;

  rows := (lines - 16) div 8; // rows of text to draw
  y := lines - 16 - (rows shl 3); // may start slightly negative

  for i := con_current - rows + 1 to con_current do
  begin
    j := i - con_backscroll;
    if j < 0 then
      j := 0;
    text := con_text + (j mod con_totallines) * con_linewidth;

    for x := 0 to con_linewidth - 1 do
      Draw_Character(((x + 1) shl 3), y, text[x]);
    inc(y, 8);
  end;

// draw the input prompt, user text, and cursor if desired
  if drawinput then
    Con_DrawInput;
end;


(*
==================
Con_NotifyBox
==================
*)

procedure Con_NotifyBox(text: PChar);
var
  t1, t2: double;
begin
// during startup for sound / cd warnings
  Con_Printf(#10#10 + CON_LINE + #10);

  Con_Printf(text);

  Con_Printf('Press a key.'#10);
  Con_Printf(CON_LINE + #10);

  key_count := -2; // wait for a key down and up
  key_dest := key_console;

  repeat
    t1 := Sys_FloatTime;
    SCR_UpdateScreen;
    Sys_SendKeyEvents;
    t2 := Sys_FloatTime;
    realtime := realtime + t2 - t1; // make the cursor blink
  until key_count >= 0;

  Con_Printf(#10);
  key_dest := key_game;
  realtime := 0; // put the cursor back to invisible
end;

end.

 