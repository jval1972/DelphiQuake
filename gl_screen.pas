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

unit gl_screen;

// screen.c -- master for refresh, status bar, console, chat, notify, etc

interface

uses
  q_delphi,
  cvar;

var
  glx, gly, glwidth, glheight: integer;

procedure SCR_CenterPrint(str: PChar);
procedure SCR_SizeDown_f;
procedure SCR_Init;
procedure SCR_DrawRam;
procedure SCR_DrawTurtle;
procedure SCR_DrawNet;
procedure SCR_DrawPause;
procedure SCR_SetUpToDrawConsole;
procedure SCR_DrawConsole;
procedure SCR_ScreenShot_f;
procedure SCR_BeginLoadingPlaque;
procedure SCR_EndLoadingPlaque;
procedure SCR_DrawNotifyString;
function SCR_ModalMessage(text: PChar): qboolean;
procedure SCR_BringDownConsole;
procedure SCR_TileClear;
procedure SCR_UpdateScreen;

var
  scr_disabled_for_loading: qboolean;

var
  scr_viewsize: cvar_t = (name: 'viewsize'; text: '100'; archive: true);
  scr_fov: cvar_t = (name: 'fov'; text: '90'); // 10 - 170
  scr_conspeed: cvar_t = (name: 'scr_conspeed'; text: '300');
  scr_centertime: cvar_t = (name: 'scr_centertime'; text: '2');
  scr_showram: cvar_t = (name: 'showram'; text: '1');
  scr_showturtle: cvar_t = (name: 'showturtle'; text: '0');
  scr_showpause: cvar_t = (name: 'showpause'; text: '1');
  scr_printspeed: cvar_t = (name: 'scr_printspeed'; text: '8');
  gl_triplebuffer: cvar_t = (name: 'gl_triplebuffer'; text: '1'; archive: true);

// only the refresh window will be updated unless these variables are flagged
var
  scr_copytop: integer;
  scr_copyeverything: qboolean; // JVAL mayby remove ????
  scr_con_current: single;
  scr_fullupdate: integer;
  scr_centertime_off: single;

  clearnotify: integer;

  block_drawing: qboolean;


implementation

uses
  mathlib,
  wad,
  vid_h,
  cl_main_h,
  gl_vidnt,
  gl_draw,
  host_h,
  keys,
  sys_win,
  sbar,
  gl_rmain,
  cmd,
  console,
  client,
  quakedef,
  common,
  OpenGL12,
  snd_dma,
  keys_h,
  view,
  menu;

(*

background clear
rendering
turtle/net/ram icons
sbar
centerprint / slow centerprint
notify lines
intermission / finale overlay
loading plaque
console
menu

required background clears
required update regions


syncronous draw mode or async
One off screen buffer, with updates either copied or xblited
Need to double buffer?


async draw will require the refresh area to be cleared, because it will be
xblited, but sync draw can just ignore it.

sync
draw

CenterPrint ()
SlowPrint ()
Screen_Update ();
Con_Printf ();

net
turn off messages option

the refresh is allways rendered, unless the console is full screen


console is:
  notify lines
  half
  full


*)

var
  scr_conlines: single; // lines of console to display // JVAL mayby integer??

  oldscreensize, oldfov: single;

var
  scr_initialized: qboolean = false; // ready to draw

  scr_ram: Pqpic_t;
  scr_net: Pqpic_t;
  scr_turtle: Pqpic_t;

  clearconsole: integer;

  scr_vrect: vrect_t;

  scr_drawloading: qboolean;
  scr_disabled_time: single;

(*
===============================================================================

CENTER PRINTING

===============================================================================
*)

var
  scr_centerstring: array[0..1023] of char;
  scr_centertime_start: single; // for slow victory printing
  scr_center_lines: integer;
  scr_erase_lines: integer;
  scr_erase_center: integer;

(*
==============
SCR_CenterPrint

Called for important messages that should stay in the center of the screen
for a few moments
==============
*)

procedure SCR_CenterPrint(str: PChar);
begin
  strncpy(scr_centerstring, str, SizeOf(scr_centerstring) - 1);
  scr_centertime_off := scr_centertime.value;
  scr_centertime_start := cl.time;

// count the number of lines for centering
  scr_center_lines := 1;
  while str^ <> #0 do
  begin
    if str^ = #10 then
      inc(scr_center_lines);
    inc(str);
  end;
end;


procedure SCR_DrawCenterString;
var
  start: PChar;
  l: integer;
  j: integer;
  x, y: integer;
  remaining: integer;
begin
// the finale prints the characters one at a time
  if cl.intermission <> 0 then
    remaining := intval(scr_printspeed.value * (cl.time - scr_centertime_start))
  else
    remaining := 9999;

  scr_erase_center := 0;
  start := scr_centerstring;

  if scr_center_lines <= 4 then
    y := intval(vid.height * 0.35)
  else
    y := 48;

  while true do
  begin
  // scan the width of the line
    l := 0;
    while (l < 40) and not (start[l] in [#0, #10]) do // JVAL check this
      inc(l);
    x := (vid.width - l * 8) div 2;
    for j := 0 to l - 1 do
    begin
      Draw_Character(x, y, start[j]);
      if remaining = 0 then
        exit;
      dec(remaining);
      inc(x, 8);
    end;

    inc(y, 8);

    while (start^ <> #0) and (start <> #10) do
      inc(start);

    if start^ = #0 then
      break;
    inc(start); // skip the \n
  end;
end;

procedure SCR_CheckDrawCenterString;
begin
  scr_copytop := 1;
  if scr_center_lines > scr_erase_lines then
    scr_erase_lines := scr_center_lines;

  scr_centertime_off := scr_centertime_off - host_frametime;

  if (scr_centertime_off <= 0) and not boolval(cl.intermission) then
    exit;
  if key_dest <> key_game then
    exit;

  SCR_DrawCenterString;
end;

//=============================================================================

(*
====================
CalcFov
====================
*)

function CalcFov(fov_x: single; width, height: single): single;
var
  x: single;
begin
  if (fov_x < 1) or (fov_x > 179) then
    Sys_Error('Bad fov: %f', [fov_x]);

  x := width / ftan(fov_x / 360 * M_PI);

  result := fatan(height / x);

  result := result * 360 / M_PI;

end;

(*
=================
SCR_CalcRefdef

Must be called whenever vid changes
Internal use only
=================
*)

procedure SCR_CalcRefdef;
var
  size: single;
  h: integer;
  full: qboolean;
begin
  full := false;

  scr_fullupdate := 0; // force a background redraw
  vid.recalc_refdef := false;

// force the status bar to redraw
  Sbar_Changed;

//========================================

// bound viewsize
  if scr_viewsize.value < 30 then
    Cvar_Set('viewsize', '30')
  else if scr_viewsize.value > 120 then
    Cvar_Set('viewsize', '120');

// bound field of view
  if scr_fov.value < 10 then Cvar_Set('fov', '10');
  if scr_fov.value > 170 then Cvar_Set('fov', '170');

// intermission is always full screen
  if cl.intermission <> 0 then
    size := 120
  else
    size := scr_viewsize.value;

  if size >= 120 then sb_lines := 0 // no status bar at all
  else if size >= 110 then sb_lines := 24 // no inventory
  else sb_lines := 24 + 16 + 8;

  if scr_viewsize.value >= 100.0 then
  begin
    full := true;
    size := 100.0;
  end
  else
    size := scr_viewsize.value;
  if cl.intermission <> 0 then
  begin
    full := true;
    size := 100;
    sb_lines := 0;
  end;
  size := size / 100.0;

  h := vid.height - sb_lines;

  r_refdef.vrect.width := intval(vid.width * size);
  if r_refdef.vrect.width < 96 then
  begin
    size := 96.0 / r_refdef.vrect.width;
    r_refdef.vrect.width := 96; // min for icons
  end;

  r_refdef.vrect.height := intval(vid.height * size);
  if r_refdef.vrect.height > vid.height - sb_lines then
    r_refdef.vrect.height := vid.height - sb_lines;
  if r_refdef.vrect.height > vid.height then
    r_refdef.vrect.height := vid.height;
  r_refdef.vrect.x := (vid.width - r_refdef.vrect.width) div 2;
  if full then
    r_refdef.vrect.y := 0
  else
    r_refdef.vrect.y := (h - r_refdef.vrect.height) div 2;

  r_refdef.fov_x := scr_fov.value;
  r_refdef.fov_y := CalcFov(r_refdef.fov_x, r_refdef.vrect.width, r_refdef.vrect.height);

  scr_vrect := r_refdef.vrect;
end;


(*
=================
SCR_SizeUp_f

Keybinding command
=================
*)

procedure SCR_SizeUp_f;
begin
  Cvar_SetValue('viewsize', scr_viewsize.value + 10);
  vid.recalc_refdef := true;
end;


(*
=================
SCR_SizeDown_f

Keybinding command
=================
*)

procedure SCR_SizeDown_f;
begin
  Cvar_SetValue('viewsize', scr_viewsize.value - 10);
  vid.recalc_refdef := true;
end;

//============================================================================

(*
==================
SCR_Init
==================
*)

procedure SCR_Init;
begin

  Cvar_RegisterVariable(@scr_fov);
  Cvar_RegisterVariable(@scr_viewsize);
  Cvar_RegisterVariable(@scr_conspeed);
  Cvar_RegisterVariable(@scr_showram);
  Cvar_RegisterVariable(@scr_showturtle);
  Cvar_RegisterVariable(@scr_showpause);
  Cvar_RegisterVariable(@scr_centertime);
  Cvar_RegisterVariable(@scr_printspeed);
  Cvar_RegisterVariable(@gl_triplebuffer);

//
// register our commands
//
  Cmd_AddCommand('screenshot', SCR_ScreenShot_f);
  Cmd_AddCommand('sizeup', SCR_SizeUp_f);
  Cmd_AddCommand('sizedown', SCR_SizeDown_f);

  scr_ram := Draw_PicFromWad('ram');
  scr_net := Draw_PicFromWad('net');
  scr_turtle := Draw_PicFromWad('turtle');

  scr_initialized := true;
end;



(*
==============
SCR_DrawRam
==============
*)

procedure SCR_DrawRam;
begin
  if scr_showram.value = 0 then
    exit;

  if not r_cache_thrash then
    exit;

  Draw_Pic(scr_vrect.x + 32, scr_vrect.y, scr_ram);
end;

(*
==============
SCR_DrawTurtle
==============
*)
var
  count_SCR_DrawTurtle: integer;

procedure SCR_DrawTurtle;
begin
  if scr_showturtle.value = 0 then
    exit;

  if host_frametime < 0.1 then
  begin
    count_SCR_DrawTurtle := 0;
    exit;
  end;

  inc(count_SCR_DrawTurtle);
  if count_SCR_DrawTurtle < 3 then
    exit;

  Draw_Pic(scr_vrect.x, scr_vrect.y, scr_turtle);
end;

(*
==============
SCR_DrawNet
==============
*)

procedure SCR_DrawNet;
begin
  if realtime - cl.last_received_message < 0.3 then
    exit;

  if cls.demoplayback then
    exit;

  Draw_Pic(scr_vrect.x + 64, scr_vrect.y, scr_net);
end;

(*
==============
DrawPause
==============
*)

procedure SCR_DrawPause;
var
  pic: Pqpic_t;
begin
  if not boolval(scr_showpause.value) then // turn off for screenshots
    exit;

  if not cl.paused then
    exit;

  pic := Draw_CachePic('gfx/pause.lmp');
  Draw_Pic((vid.width - pic.width) div 2,
    (vid.height - 48 - pic.height) div 2, pic);
end;



(*
==============
SCR_DrawLoading_f
==============
*)

procedure SCR_DrawLoading_f;
var
  pic: Pqpic_t;
begin
  if not scr_drawloading then
    exit;

  pic := Draw_CachePic('gfx/loading.lmp');
  Draw_Pic((vid.width - pic.width) div 2,
    (vid.height - 48 - pic.height) div 2, pic);
end;



//=============================================================================


(*
==================
SCR_SetUpToDrawConsole
==================
*)

procedure SCR_SetUpToDrawConsole;
begin
  Con_CheckResize;

  if scr_drawloading then
    exit; // never a console with loading plaque

// decide on the height of the console
  con_forcedup := not boolval(cl.worldmodel) or (cls.signon <> SIGNONS);

  if con_forcedup then
  begin
    scr_conlines := vid.height; // full screen
    scr_con_current := scr_conlines;
  end
  else if key_dest = key_console then
    scr_conlines := vid.height / 2 // half screen
  else
    scr_conlines := 0; // none visible

  if scr_conlines < scr_con_current then
  begin
    scr_con_current := scr_con_current - scr_conspeed.value * host_frametime;
    if scr_conlines > scr_con_current then
      scr_con_current := scr_conlines;

  end
  else if scr_conlines > scr_con_current then
  begin
    scr_con_current := scr_con_current + scr_conspeed.value * host_frametime;
    if scr_conlines < scr_con_current then
      scr_con_current := scr_conlines;
  end;

  if clearconsole < vid.numpages then
    Sbar_Changed
  else if clearnotify < vid.numpages then
  else
    con_notifylines := 0;
  inc(clearconsole);
  inc(clearnotify);
end;

(*
==================
SCR_DrawConsole
==================
*)

procedure SCR_DrawConsole;
begin
  if boolval(scr_con_current) then
  begin
    scr_copyeverything := true;
    Con_DrawConsole(intval(scr_con_current), true);
    clearconsole := 0;
  end
  else
  begin
    if (key_dest = key_game) or (key_dest = key_message) then
      Con_DrawNotify; // only draw notify in game
  end;
end;


(*
==============================================================================

            SCREEN SHOTS

==============================================================================
*)

type
  TargaHeader = record
    id_length, colormap_type, image_type: byte;
    colormap_index, colormap_length: word;
    colormap_size: byte;
    x_origin, y_origin, width, height: word;
    pixel_size, attributes: Byte;
  end;


(*
==================
SCR_ScreenShot_f
==================
*)

procedure SCR_ScreenShot_f;
var
  buffer: PByteArray;
  pcxname: array[0..79] of char;
  checkname: array[0..MAX_OSPATH - 1] of char;
  i: integer;
  snum: string[3];
begin
//
// find a file name to save it to
//
  strcpy(pcxname, 'quake000.tga');

  i := 0;
  while i <= 999 do
  begin
    snum := IntToStrZfill(3, i);
    pcxname[5] := snum[1];
    pcxname[6] := snum[2];
    pcxname[7] := snum[3];
    sprintf(checkname, '%s/%s', [com_gamedir, pcxname]);
    if Sys_FileTime(checkname) = -1 then
      break; // file doesn't exist
    inc(i);
  end;
  if i = 1000 then
  begin
    Con_Printf('SCR_ScreenShot_f: Couldn''t create a TGA file'#10);
    exit;
  end;


  buffer := malloc(glwidth * glheight * 4 + 18);
  ZeroMemory(buffer, 18);
  buffer[2] := 2; // uncompressed type
  buffer[12] := glwidth and 255;
  buffer[13] := glwidth shr 8;
  buffer[14] := glheight and 255;
  buffer[15] := glheight shr 8;
  buffer[16] := 32; // pixel size

  glReadPixels(glx, gly, glwidth, glheight, GL_BGRA, GL_UNSIGNED_BYTE, @buffer[18]);

  COM_WriteFile(pcxname, buffer, glwidth * glheight * 4 + 18);

  memfree(pointer(buffer), glwidth * glheight * 4 + 18);
  Con_Printf('Wrote %s'#10, [pcxname]);
end;


//=============================================================================


(*
===============
SCR_BeginLoadingPlaque

================
*)

procedure SCR_BeginLoadingPlaque;
begin
  S_StopAllSounds(true);

  if cls.state <> ca_connected then
    exit;

  if cls.signon <> SIGNONS then
    exit;

// redraw with no console and the loading plaque
  Con_ClearNotify;
  scr_centertime_off := 0;
  scr_con_current := 0;

  scr_drawloading := true;
  scr_fullupdate := 0;
  Sbar_Changed;
  SCR_UpdateScreen;
  scr_drawloading := false;

  scr_disabled_for_loading := true;
  scr_disabled_time := realtime;
  scr_fullupdate := 0;
end;

(*
===============
SCR_EndLoadingPlaque

================
*)

procedure SCR_EndLoadingPlaque;
begin
  scr_disabled_for_loading := false;
  scr_fullupdate := 0;
  Con_ClearNotify;
end;

//=============================================================================

var
  scr_notifystring: PChar;
  scr_drawdialog: qboolean;

procedure SCR_DrawNotifyString;
var
  start: PChar;
  l: integer;
  j: integer;
  x, y: integer;
begin
  start := scr_notifystring;

  y := intval(vid.height * 0.35);

  while true do
  begin
  // scan the width of the line
    l := 0;
    while l < 40 do
    begin
      if start[l] in [#0, #10] then
        break;
      inc(l);
    end;

    x := (vid.width - l * 8) div 2;
    for j := 0 to l - 1 do
    begin
      Draw_Character(x, y, start[j]);
      inc(x, 8);
    end;

{    while (start^ <> #0) and (start^ <> #10) do
      inc(start);}
    if l = 40 then
      break;

    start := @start[l];

    if start^ = #0 then
      break;

    inc(y, 8);
    inc(start); // skip the \n
  end;
end;

(*
==================
SCR_ModalMessage

Displays a text string in the center of the screen and waits for a Y or N
keypress.
==================
*)

function SCR_ModalMessage(text: PChar): qboolean;
begin
  if cls.state = ca_dedicated then
  begin
    result := true;
    exit;
  end;

  scr_notifystring := text;

// draw a fresh screen
  scr_fullupdate := 0;
  scr_drawdialog := true;
  SCR_UpdateScreen;
  scr_drawdialog := false;

  S_ClearBuffer; // so dma doesn't loop current sound

  repeat
    key_count := -1; // wait for a key down and up
    Sys_SendKeyEvents;
  until key_lastpress in [Ord('y'), Ord('n'), K_ESCAPE];

  scr_fullupdate := 0;
  SCR_UpdateScreen;

  result := key_lastpress = Ord('y');
end;


//=============================================================================

(*
===============
SCR_BringDownConsole

Brings the console down and fades the palettes back to normal
================
*)

procedure SCR_BringDownConsole;
var
  i: integer;
begin
  scr_centertime_off := 0;

  i := 0;
  while (i < 20) and (scr_conlines <> scr_con_current) do
  begin
    SCR_UpdateScreen;
    inc(i);
  end;

  cl.cshifts[0].percent := 0; // no area contents palette on next frame
  VID_SetPalette(host_basepal);
end;

procedure SCR_TileClear;
begin
  if r_refdef.vrect.x > 0 then
  begin
    // left
    Draw_TileClear(0, 0, r_refdef.vrect.x, vid.height - sb_lines);
    // right
    Draw_TileClear(r_refdef.vrect.x + r_refdef.vrect.width, 0,
      vid.width - r_refdef.vrect.x + r_refdef.vrect.width,
      vid.height - sb_lines);
  end;
  if r_refdef.vrect.y > 0 then
  begin
    // top
    Draw_TileClear(r_refdef.vrect.x, 0,
      r_refdef.vrect.x + r_refdef.vrect.width,
      r_refdef.vrect.y);
    // bottom
    Draw_TileClear(r_refdef.vrect.x,
      r_refdef.vrect.y + r_refdef.vrect.height,
      r_refdef.vrect.width,
      vid.height - sb_lines -
      (r_refdef.vrect.height + r_refdef.vrect.y));
  end;
end;

(*
==================
SCR_UpdateScreen

This is called every frame, and can also be called explicitly to flush
text to the screen.

WARNING: be very careful calling this from elsewhere, because the refresh
needs almost the entire 256k of stack space!
==================
*)
var
  oldscr_viewsize: single;

procedure SCR_UpdateScreen;
begin
  if block_drawing then
    exit;

  vid.numpages := 2 + intval(gl_triplebuffer.value);

  scr_copytop := 0;
  scr_copyeverything := false;

  if scr_disabled_for_loading then
  begin
    if realtime - scr_disabled_time > 60 then
    begin
      scr_disabled_for_loading := false;
      Con_Printf('load failed.'#10);
    end
    else
      exit;
  end;

  if not scr_initialized or not con_initialized then
    exit; // not initialized yet


  GL_BeginRendering(@glx, @gly, @glwidth, @glheight);

  //
  // determine size of refresh window
  //
  if oldfov <> scr_fov.value then
  begin
    oldfov := scr_fov.value;
    vid.recalc_refdef := true;
  end;

  if oldscreensize <> scr_viewsize.value then
  begin
    oldscreensize := scr_viewsize.value;
    vid.recalc_refdef := true;
  end;

  if vid.recalc_refdef then
    SCR_CalcRefdef;

//
// do 3D refresh drawing, and then update the screen
//
  SCR_SetUpToDrawConsole;

  V_RenderView;

  GL_Set2D;

  //
  // draw any areas not covered by the refresh
  //
  SCR_TileClear;

  if scr_drawdialog then
  begin
    Sbar_Draw;
    Draw_FadeScreen;
    SCR_DrawNotifyString;
    scr_copyeverything := true;
  end
  else if scr_drawloading then
  begin
    SCR_DrawLoading_f;
    Sbar_Draw;
  end
  else if (cl.intermission = 1) and (key_dest = key_game) then
    Sbar_IntermissionOverlay
  else if (cl.intermission = 2) and (key_dest = key_game) then
  begin
    Sbar_FinaleOverlay;
    SCR_CheckDrawCenterString;
  end
  else
  begin
    if crosshair.value <> 0 then
      Draw_Character(scr_vrect.x + scr_vrect.width div 2, scr_vrect.y + scr_vrect.height div 2, '+');

    SCR_DrawRam;
    SCR_DrawNet;
    SCR_DrawTurtle;
    SCR_DrawPause;
    SCR_CheckDrawCenterString;
    Sbar_Draw;
    SCR_DrawConsole;
    M_Draw;
  end;

  V_UpdatePalette;

  GL_EndRendering;
end;


end.


