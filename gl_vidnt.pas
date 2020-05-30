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

unit gl_vidnt;

interface

uses
  q_delphi,
  Windows,
  OpenGL12,
  vid_h,
  cvar,
  gl_defs;

type
  modestate_t = (MS_WINDOWED, MS_FULLSCREEN, MS_FULLDIB, MS_UNINIT);

  vmode_t = record
    _type: modestate_t;
    width: integer;
    height: integer;
    modenum: integer;
    dib: integer;
    fullscreen: integer;
    bpp: integer;
    halfscreen: integer;
    modedesc: array[0..16] of char;
  end;
  Pvmode_t = ^vmode_t;


procedure VID_HandlePause(pause: qboolean);
procedure VID_ForceLockState(lk: integer);
procedure VID_LockBuffer; // JVAL remove ?
procedure VID_UnlockBuffer; // JVAL remove ?
function VID_ForceUnlockedAndReturnState: integer;
procedure CenterWindow(hWndCenter: HWND; width, height: integer; lefttopjustify: BOOL);
function VID_SetWindowedMode(modenum: integer): qboolean;
function VID_SetFullDIBMode(modenum: integer): qboolean;
procedure VID_SetMode(modenum: integer; palette: PByteArray);
procedure VID_UpdateWindowStatus;
procedure CheckTextureExtensions;
procedure CheckArrayExtensions;
procedure CheckMultiTextureExtensions;
procedure GL_Init;
procedure GL_BeginRendering(x, y: PInteger; width, height: PInteger);
procedure GL_EndRendering;
procedure VID_SetPalette(palette: PByteArray);
procedure VID_SetDefaultMode;
procedure VID_Shutdown;
procedure ClearAllStates;
procedure AppActivate(fActive: BOOL; minimize: BOOL);
function MainWndProc(hWnd: HWND; Msg: longword; wParam: WPARAM;
  lParam: LPARAM): LRESULT; stdcall; export;
function VID_NumModes: integer;
function VID_GetModePtr(modenum: integer): Pvmode_t;
function VID_GetModeDescription(mode: integer): PChar;
function VID_GetExtModeDescription(mode: integer): PChar;
procedure VID_DescribeCurrentMode_f;
procedure VID_DescribeMode_f;
procedure VID_DescribeModes_f;
procedure VID_InitFullDIB(inst: THandle);
function VID_Is8bit: qboolean;
procedure VID_Init8bitPalette;
procedure Check_Gamma(pal: PByteArray);
procedure VID_Init(palette: PByteArray);
procedure VID_MenuDraw;
procedure VID_MenuKey(key: integer);

var
  gl_mtexable: qboolean = false;

var
  texture_mode: integer = GL_LINEAR;

var
  d_8to16table: array[0..255] of unsigned_short;
  d_8to24table: array[0..255] of unsigned;
  d_15to8table: array[0..65535] of byte;

  texture_extension_number: Integer = 1;

  vid: viddef_t; // global video state
  isPermedia: qboolean = false;
  gldepthmin, gldepthmax: single;
  mainwindow: HWND;
  window_center_x, window_center_y, window_x, window_y, window_width, window_height: integer;
  window_rect: TRect;
  bindTexFunc: BINDTEXFUNCPTR;

  gl_ztrick: cvar_t = (name: 'gl_ztrick'; text: '1');

  str_gl_vendor: PChar;
  str_gl_renderer: PChar;
  str_gl_version: PChar;
  str_gl_extensions: PChar;

var
  scr_skipupdate: qboolean;
  DDActive: qboolean;

var
  modestate: modestate_t = MS_UNINIT;

//====================================

var
  vid_mode: cvar_t = (name: 'vid_mode'; text: '0'; archive: false);// Note that 0 is MODE_WINDOWED
  _vid_default_mode: cvar_t = (name: '_vid_default_mode'; text: '0'; archive: true);// Note that 3 is MODE_FULLSCREEN_DEFAULT
  _vid_default_mode_win: cvar_t = (name: '_vid_default_mode_win'; text: '3'; archive: true);
  vid_wait: cvar_t = (name: 'vid_wait'; text: '0');
  vid_nopageflip: cvar_t = (name: 'vid_nopageflip'; text: '0'; archive: true);
  _vid_wait_override: cvar_t = (name: '_vid_wait_override'; text: '0'; archive: true);
  vid_config_x: cvar_t = (name: 'vid_config_x'; text: '1024'; archive: true);
  vid_config_y: cvar_t = (name: 'vid_config_y'; text: '768'; archive: true);
  vid_stretch_by_2: cvar_t = (name: 'vid_stretch_by_2'; text: '1'; archive: true);
  _windowed_mouse: cvar_t = (name: '_windowed_mouse'; text: '1'; archive: true);


implementation

uses
  sys_win,
  messages,
  gl_screen,
  gl_sky,
  cd_win,
  keys,
  keys_h,
  in_win,
  common,
  console,
  sbar,
  snd_win,
  mmsystem,
  cmd,
  quakedef,
  host_h,
  menu,
  wad,
  gl_draw,
  snd_dma;

const
  MAX_MODE_LIST = 30;
  VID_ROW_SIZE = 3;
  WARP_WIDTH = 320;
  WARP_HEIGHT = 200;
  MAXWIDTH = 10000;
  MAXHEIGHT = 10000;
  BASEWIDTH = 320;
  BASEHEIGHT = 200;

const
  MODE_WINDOWED = 0;
  NO_MODE = (MODE_WINDOWED - 1);
  MODE_FULLSCREEN_DEFAULT = (MODE_WINDOWED + 1);

type
  lmode_t = record
    width: integer;
    height: integer;
  end;
  Plmode_t = ^lmode_t;

const
  lowresmodes: array[0..3] of lmode_t = (
    (width: 320; height: 200),
    (width: 320; height: 240),
    (width: 400; height: 300),
    (width: 512; height: 384)
    );

var
  modelist: array[0..MAX_MODE_LIST - 1] of vmode_t;
  nummodes: integer = 0;
  badmode: vmode_t;

var
  gdevmode: DEVMODE;
  vid_initialized: qboolean = false;
  windowed, leavecurrentmode: qboolean;
  vid_canalttab: qboolean = false;
  vid_wassuspended: qboolean = false;
  windowed_mouse: qboolean;
  Icon: HICON;

var
  DIBWidth, DIBHeight: integer;
  WindowRect: TRect;
  WindowStyle, ExWindowStyle: DWORD;

var
  dibwindow: HWND;

var
  vid_modenum: integer = NO_MODE;
  vid_realmode: integer;
  vid_default: integer = MODE_WINDOWED;
  windowed_default: integer;
  vid_curpal: array[0..256 * 3 - 1] of byte;
  fullsbardraw: qboolean = false;

var
  vid_gamma: single = 1.0;

var
  baseRC: HGLRC;
  maindc: HDC;

type
  lp3DFXFUNC = procedure(i1, i2, i3, i4, i5: integer; const p: pointer);

var
  is8bit: qboolean = false;

procedure VID_HandlePause(pause: qboolean);
begin
// JVAL remove
end;

procedure VID_ForceLockState(lk: integer);
begin
// JVAL remove
end;

procedure VID_LockBuffer;
begin
// JVAL remove
end;

procedure VID_UnlockBuffer;
begin
// JVAL remove
end;

function VID_ForceUnlockedAndReturnState: integer;
begin
  result := 0;
end;

(*
void D_BeginDirectRect (int x, int y, byte *pbitmap, int width, int height)
{
//JVAL remove
}

void D_EndDirectRect (int x, int y, int width, int height)
{
//JVAL remove
}
*)

procedure CenterWindow(hWndCenter: HWND; width, height: integer; lefttopjustify: BOOL);
var
  CenterX, CenterY: integer;
begin
  CenterX := (GetSystemMetrics(SM_CXSCREEN) - width) div 2;
  CenterY := (GetSystemMetrics(SM_CYSCREEN) - height) div 2;
  if CenterX > CenterY * 2 then
    CenterX := CenterX div 2; // dual screens
  if CenterX < 0 then
    CenterX := 0;
  if CenterY < 0 then
    CenterY := 0;
  SetWindowPos(hWndCenter, 0, CenterX, CenterY, 0, 0,
    SWP_NOSIZE or SWP_NOZORDER or SWP_SHOWWINDOW or SWP_DRAWFRAME);
end;

function VID_SetWindowedMode(modenum: integer): qboolean;
var
  dc: HDC;
  width, height: integer;
  rect: TRect;
begin
  WindowRect.top := 0;
  WindowRect.left := 0;

  WindowRect.right := modelist[modenum].width;
  WindowRect.bottom := modelist[modenum].height;

  DIBWidth := modelist[modenum].width;
  DIBHeight := modelist[modenum].height;

  WindowStyle := WS_OVERLAPPED or WS_BORDER or WS_CAPTION or WS_SYSMENU or WS_MINIMIZEBOX;
  ExWindowStyle := 0;

  rect := WindowRect;
  AdjustWindowRectEx(rect, WindowStyle, false, 0);

  width := rect.right - rect.left;
  height := rect.bottom - rect.top;

  // Create the DIB window
  dibwindow := CreateWindowEx(
    ExWindowStyle,
    'WinQuake',
    'GLQuake',
    WindowStyle,
    rect.left, rect.top,
    width,
    height,
    0,
    0,
    global_hInstance,
    nil);

  if dibwindow = 0 then
    Sys_Error('Couldn''t create DIB window');

  // Center and show the DIB window
  CenterWindow(dibwindow, WindowRect.right - WindowRect.left,
    WindowRect.bottom - WindowRect.top, false);

  ShowWindow(dibwindow, SW_SHOWDEFAULT);
  UpdateWindow(dibwindow);

  modestate := MS_WINDOWED;

// because we have set the background brush for the window to NULL
// (to avoid flickering when re-sizing the window on the desktop),
// we clear the window to black when created, otherwise it will be
// empty while Quake starts up.
  dc := GetDC(dibwindow);
  PatBlt(dc, 0, 0, WindowRect.right, WindowRect.bottom, BLACKNESS);
  ReleaseDC(dibwindow, dc);

  if vid.conheight > modelist[modenum].height then
    vid.conheight := modelist[modenum].height;
  if vid.conwidth > modelist[modenum].width then
    vid.conwidth := modelist[modenum].width;
  vid.width := vid.conwidth;
  vid.height := vid.conheight;

  vid.numpages := 2;

  mainwindow := dibwindow;

  SendMessage(mainwindow, WM_SETICON, WPARAM(true), LPARAM(Icon));
  SendMessage(mainwindow, WM_SETICON, WPARAM(false), LPARAM(Icon));

  result := true;
end;


function VID_SetFullDIBMode(modenum: integer): qboolean;
var
  dc: HDC;
  width, height: integer;
  rect: TRect;
begin
  if not leavecurrentmode then
  begin
    gdevmode.dmFields := DM_BITSPERPEL or DM_PELSWIDTH or DM_PELSHEIGHT;
    gdevmode.dmBitsPerPel := modelist[modenum].bpp;
    gdevmode.dmPelsWidth := (modelist[modenum].width shl modelist[modenum].halfscreen);
    gdevmode.dmPelsHeight := modelist[modenum].height;
    gdevmode.dmSize := SizeOf(gdevmode);

    if ChangeDisplaySettings(gdevmode, CDS_FULLSCREEN) <> DISP_CHANGE_SUCCESSFUL then
      Sys_Error('Couldn''t set fullscreen DIB mode');
  end;

  modestate := MS_FULLDIB;

  WindowRect.top := 0;
  WindowRect.left := 0;

  WindowRect.right := modelist[modenum].width;
  WindowRect.bottom := modelist[modenum].height;

  DIBWidth := modelist[modenum].width;
  DIBHeight := modelist[modenum].height;

  WindowStyle := WS_POPUP;
  ExWindowStyle := 0;

  rect := WindowRect;
  AdjustWindowRectEx(rect, WindowStyle, false, 0);

  width := rect.right - rect.left;
  height := rect.bottom - rect.top;

  // Create the DIB window
  dibwindow := CreateWindowEx(
    ExWindowStyle,
    'WinQuake',
    'GLQuake',
    WindowStyle,
    rect.left, rect.top,
    width,
    height,
    0,
    0,
    global_hInstance,
    nil);

  if dibwindow = 0 then
    Sys_Error('Couldn''t create DIB window');

  ShowWindow(dibwindow, SW_SHOWDEFAULT);
  UpdateWindow(dibwindow);

  // Because we have set the background brush for the window to NULL
  // (to avoid flickering when re-sizing the window on the desktop), we
  // clear the window to black when created, otherwise it will be
  // empty while Quake starts up.
  dc := GetDC(dibwindow);
  PatBlt(dc, 0, 0, WindowRect.right, WindowRect.bottom, BLACKNESS);
  ReleaseDC(dibwindow, dc);

  if vid.conheight > modelist[modenum].height then
    vid.conheight := modelist[modenum].height;
  if vid.conwidth > modelist[modenum].width then
    vid.conwidth := modelist[modenum].width;
  vid.width := vid.conwidth;
  vid.height := vid.conheight;

  vid.numpages := 2;

// needed because we're not getting WM_MOVE messages fullscreen on NT
  window_x := 0;
  window_y := 0;

  mainwindow := dibwindow;

  SendMessage(mainwindow, WM_SETICON, WPARAM(true), LPARAM(Icon));
  SendMessage(mainwindow, WM_SETICON, WPARAM(false), LPARAM(Icon));

  result := true;
end;


procedure VID_SetMode(modenum: integer; palette: PByteArray);
var
  temp: qboolean;
  stat: qboolean;
  msg: TMsg;
begin
  if (windowed and (modenum <> 0)) or
    (not windowed and (modenum < 1)) or
    (not windowed and (modenum >= nummodes)) then
    Sys_Error('Bad video mode'#10);

// so Con_Printfs don't mess us up by forcing vid and snd updates
  temp := scr_disabled_for_loading;
  scr_disabled_for_loading := true;

  CDAudio_Pause;

  // Set either the fullscreen or windowed mode
  stat := false;
  if modelist[modenum]._type = MS_WINDOWED then
  begin
    if (_windowed_mouse.value <> 0) and (key_dest = key_game) then
    begin
      stat := VID_SetWindowedMode(modenum);
      IN_ActivateMouse;
      IN_HideMouse;
    end
    else
    begin
      IN_DeactivateMouse;
      IN_ShowMouse;
      stat := VID_SetWindowedMode(modenum);
    end;
  end
  else if modelist[modenum]._type = MS_FULLDIB then
  begin
    stat := VID_SetFullDIBMode(modenum);
    IN_ActivateMouse;
    IN_HideMouse;
  end
  else
    Sys_Error('VID_SetMode: Bad mode type in modelist');

  window_width := DIBWidth;
  window_height := DIBHeight;
  VID_UpdateWindowStatus;

  CDAudio_Resume;
  scr_disabled_for_loading := temp;

  if not stat then
    Sys_Error('Couldn''t set video mode');

// now we try to make sure we get the focus on the mode switch, because
// sometimes in some systems we don't.  We grab the foreground, then
// finish setting up, pump all our messages, and sleep for a little while
// to let messages finish bouncing around the system, then we put
// ourselves at the top of the z order, then grab the foreground again,
// Who knows if it helps, but it probably doesn't hurt
  SetForegroundWindow(mainwindow);
  VID_SetPalette(palette);
  vid_modenum := modenum;
  Cvar_SetValue('vid_mode', vid_modenum);

  while PeekMessage(msg, 0, 0, 0, PM_REMOVE) do
  begin
    TranslateMessage(msg);
    DispatchMessage(msg);
  end;

  Sleep(100);

  SetWindowPos(mainwindow, HWND_TOP, 0, 0, 0, 0,
    SWP_DRAWFRAME or SWP_NOMOVE or SWP_NOSIZE or SWP_SHOWWINDOW or
    SWP_NOCOPYBITS);

  SetForegroundWindow(mainwindow);

// fix the leftover Alt from any Alt-Tab or the like that switched us away
  ClearAllStates;

  if not msg_suppress_1 then
    Con_SafePrintf('Video mode %s initialized.'#10, [VID_GetModeDescription(vid_modenum)]);

  VID_SetPalette(palette);

  vid.recalc_refdef := true;
end;


(*
================
VID_UpdateWindowStatus
================
*)

procedure VID_UpdateWindowStatus;
begin
  window_rect.left := window_x;
  window_rect.top := window_y;
  window_rect.right := window_x + window_width;
  window_rect.bottom := window_y + window_height;
  window_center_x := (window_rect.left + window_rect.right) div 2;
  window_center_y := (window_rect.top + window_rect.bottom) div 2;

  IN_UpdateClipCursor;
end;


//====================================

const
  TEXTURE_EXT_STRING = 'GL_EXT_texture_object';


procedure CheckTextureExtensions;
var
  tmp: PChar;
  texture_ext: qboolean;
  hInstGL: THandle;
begin
  texture_ext := false;
  (* check for texture extension *)
  tmp := glGetString(GL_EXTENSIONS);
  while tmp^ <> #0 do
  begin
    if strncmp(tmp, TEXTURE_EXT_STRING, strlen(TEXTURE_EXT_STRING)) = 0 then
      texture_ext := true; // JVAL mayby break here ?
    inc(tmp);
  end;

  if not texture_ext or (COM_CheckParm('-gl11') <> 0) then
  begin
    hInstGL := LoadLibrary('opengl32.dll');

    if hInstGL = 0 then
      Sys_Error('Couldn''t load opengl32.dll'#10);

    bindTexFunc := GetProcAddress(hInstGL, 'glBindTexture');

    if not Assigned(bindTexFunc) then
      Sys_Error('No texture objects!');
    exit;
  end;

(* load library and get procedure adresses for texture extension API *)

  bindTexFunc := wglGetProcAddress('glBindTextureEXT');
  if not Assigned(bindTexFunc) then
  begin
    Sys_Error('GetProcAddress for BindTextureEXT failed');
    exit;
  end;
end;

procedure CheckArrayExtensions;
var
  tmp: PChar;
begin
  (* check for texture extension *)
  tmp := glGetString(GL_EXTENSIONS);
  while tmp^ <> #0 do
  begin
    if strncmp(tmp, 'GL_EXT_vertex_array', strlen('GL_EXT_vertex_array')) = 0 then
    begin
      glArrayElementEXT := wglGetProcAddress('glArrayElementEXT');
      glColorPointerEXT := wglGetProcAddress('glColorPointerEXT');
      glTexCoordPointerEXT := wglGetProcAddress('glTexCoordPointerEXT');
      glVertexPointerEXT := wglGetProcAddress('glVertexPointerEXT');
      if not Assigned(glArrayElementEXT) or
        not Assigned(glColorPointerEXT) or
        not Assigned(glTexCoordPointerEXT) or
        not Assigned(glVertexPointerEXT) then
        Sys_Error('GetProcAddress for vertex extension failed');
      exit;
    end;
    inc(tmp);
  end;

  Sys_Error('Vertex array extension not present');
end;

procedure CheckMultiTextureExtensions;
begin
  if (strstr(str_gl_extensions, 'GL_SGIS_multitexture') <> nil) and (COM_CheckParm('-nomtex') = 0) then
  begin
    Con_Printf('Multitexture extensions found.'#10);
    qglMTexCoord2fSGIS := wglGetProcAddress('glMTexCoord2fSGIS');
    qglSelectTextureSGIS := wglGetProcAddress('glSelectTextureSGIS');
    gl_mtexable := true;
  end;
end;

(*
===============
GL_Init
===============
*)

procedure GL_Init;
begin
  str_gl_vendor := glGetString(GL_VENDOR);
  Con_Printf('GL_VENDOR: %s'#10, [str_gl_vendor]);
  str_gl_renderer := glGetString(GL_RENDERER);
  Con_Printf('GL_RENDERER: %s'#10, [str_gl_renderer]);

  str_gl_version := glGetString(GL_VERSION);
  Con_Printf('GL_VERSION: %s'#10, [str_gl_version]);
  str_gl_extensions := glGetString(GL_EXTENSIONS);
  Con_Printf('GL_EXTENSIONS: %s'#10, [str_gl_extensions]);

//  Con_Printf ("%s %s\n", gl_renderer, gl_version);

  if strncmp(str_gl_renderer, 'PowerVR', 7) = 0 then // JVAL SOS was strnicmp
    fullsbardraw := true;

  if strncmp(str_gl_renderer, 'Permedia', 8) = 0 then // JVAL SOS was strnicmp
    isPermedia := true;

  CheckTextureExtensions;
  CheckMultiTextureExtensions;

  glClearColor(1, 0, 0, 0);
  glCullFace(GL_FRONT);
  glEnable(GL_TEXTURE_2D);

  glEnable(GL_ALPHA_TEST);
  glAlphaFunc(GL_GREATER, 0.666);

  glPolygonMode(GL_FRONT_AND_BACK, GL_FILL);
  glShadeModel(GL_FLAT);

  glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_LINEAR);
  glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR_MIPMAP_LINEAR);
  glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT);
  glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT);

  glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

  glTexEnvf(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_REPLACE);

  GL_InitSky;
end;

(*
=================
GL_BeginRendering

=================
*)

procedure GL_BeginRendering(x, y: PInteger; width, height: PInteger);
begin
//  extern cvar_t gl_clear;

  x^ := 0;
  y^ := 0;
  width^ := WindowRect.right - WindowRect.left;
  height^ := WindowRect.bottom - WindowRect.top;

end;


procedure GL_EndRendering;
begin
  if not scr_skipupdate or block_drawing then
    SwapBuffers(maindc);

// handle the mouse state when windowed if that's changed
  if modestate = MS_WINDOWED then
  begin
    if _windowed_mouse.value = 0 then
    begin
      if windowed_mouse then
      begin
        IN_DeactivateMouse;
        IN_ShowMouse;
        windowed_mouse := false;
      end;
    end
    else
    begin
      windowed_mouse := true;
      if (key_dest = key_game) and not mouseactive and ActiveApp then
      begin
        IN_ActivateMouse;
        IN_HideMouse;
      end
      else if mouseactive and (key_dest <> key_game) then
      begin
        IN_DeactivateMouse;
        IN_ShowMouse;
      end;
    end;
  end;
  if fullsbardraw then
    Sbar_Changed;
end;

procedure VID_SetPalette(palette: PByteArray);
var
  pal: PByteArray;
  r, g, b: byte;
  v: unsigned;
  r1, g1, b1: integer;
  j, k, l: integer;
  i: unsigned_short;
  table: Punsigned;
begin
//
// 8 8 8 encoding
//
  pal := palette;
  table := @d_8to24table[0];
  for i := 0 to 255 do
  begin
    r := pal[0];
    g := pal[1];
    b := pal[2];
    pal := @pal[3];

    table^ := (255 shl 24) + (r) + (g shl 8) + (b shl 16);
    inc(table);
  end;
  d_8to24table[255] := d_8to24table[255] and $FFFFFF; // 255 is transparent

  // JACK: 3D distance calcs - k is last closest, l is the distance.
  // FIXME: Precalculate this and cache to disk.
  for i := 0 to (1 shl 15) - 1 do
  begin
    (* Maps
      000000000000000
      000000000011111 = Red  = 0x1F
      000001111100000 = Blue = 0x03E0
      111110000000000 = Grn  = 0x7C00
    *)
    r := ((i and $001F) shl 3) + 4;
    g := ((i and $03E0) shr 2) + 4;
    b := ((i and $7C00) shr 7) + 4;
    pal := PByteArray(@d_8to24table[0]);
    k := 0;
    l := 10000 * 10000;
    for v := 0 to 255 do
    begin
      r1 := r - pal[0];
      g1 := g - pal[1];
      b1 := b - pal[2];
      j := (r1 * r1) + (g1 * g1) + (b1 * b1);
      if j < l then
      begin
        k := v;
        l := j;
      end;
      pal := @pal[4];
    end;
    d_15to8table[i] := k;
  end;
end;

procedure VID_SetDefaultMode;
begin
  IN_DeactivateMouse;
end;


procedure VID_Shutdown;
var
  hRC: HGLRC;
  DC: HDC;
  NULLMOD: DEVMODE;
begin
  if vid_initialized then
  begin
    vid_canalttab := false;
    hRC := wglGetCurrentContext;
    DC := wglGetCurrentDC;

    wglMakeCurrent(0, 0);

    if hRC <> 0 then
      wglDeleteContext(hRC);

    if (DC <> 0) and (dibwindow <> 0) then
      ReleaseDC(dibwindow, DC);

    if modestate = MS_FULLDIB then
    begin
      ZeroMemory(@NULLMOD, SizeOf(NULLMOD));
      ChangeDisplaySettings(NULLMOD, 0);
    end;

    if (maindc <> 0) and (dibwindow <> 0) then
      ReleaseDC(dibwindow, maindc);

    AppActivate(false, false);
  end;
end;


//==========================================================================


function bSetupPixelFormat(DC: HDC): BOOL;
var
  pfd: PIXELFORMATDESCRIPTOR;
  pixelformat: integer;
begin
  with pfd do
  begin
    nSize := sizeof(PIXELFORMATDESCRIPTOR); // size of this pfd
    nVersion := 1; // version number
    dwFlags := PFD_DRAW_TO_WINDOW or // support window
      PFD_SUPPORT_OPENGL or // support OpenGL
      PFD_DOUBLEBUFFER; // double buffered
    iPixelType := PFD_TYPE_RGBA; // RGBA type
    cColorBits := 24; // 24-bit color depth

    cRedBits := 0; // color bits ignored
    cRedShift := 0;
    cGreenBits := 0;
    cGreenShift := 0;
    cBlueBits := 0;
    cBlueShift := 0;

    cAlphaBits := 0; // no alpha buffer
    cAlphaShift := 0; // shift bit ignored

    cAccumBits := 0; // no accumulation buffer
    cAccumRedBits := 0; // accum bits ignored
    cAccumGreenBits := 0;
    cAccumBlueBits := 0;
    cAccumAlphaBits := 0;

    cDepthBits := 32; // 32-bit z-buffer
    cStencilBits := 0; // no stencil buffer
    cAuxBuffers := 0; // no auxiliary buffer
    iLayerType := PFD_MAIN_PLANE; // main layer

    bReserved := 0; // reserved

    dwLayerMask := 0; // layer masks ignored
    dwVisibleMask := 0;
    dwDamageMask := 0;
  end;

  pixelformat := ChoosePixelFormat(DC, @pfd);
  if pixelformat = 0 then
  begin
    MessageBox(0, 'ChoosePixelFormat failed', 'Error', MB_OK);
    result := false;
    exit;
  end;

  if not SetPixelFormat(DC, pixelformat, @pfd) then
  begin
    MessageBox(0, 'SetPixelFormat failed', 'Error', MB_OK); // JVAL mayby other outproc not messagebox?
    result := false;
    exit;
  end;

  result := true;
end;


var
  scantokey: array[0..127] of byte = (
//  0           1       2       3       4       5       6       7
//  8           9       A       B       C       D       E       F
    0, 27, Ord('1'), Ord('2'), Ord('3'), Ord('4'), Ord('5'), Ord('6'),
    Ord('7'), Ord('8'), Ord('9'), Ord('0'), Ord('-'), Ord('='), K_BACKSPACE, 9, // 0
    Ord('q'), Ord('w'), Ord('e'), Ord('r'), Ord('t'), Ord('y'), Ord('u'), Ord('i'),
    Ord('o'), Ord('p'), Ord('['), Ord(']'), 13, K_CTRL, Ord('a'), Ord('s'), // 1
    Ord('d'), Ord('f'), Ord('g'), Ord('h'), Ord('j'), Ord('k'), Ord('l'), Ord(';'),
    Ord(''''), Ord('`'), K_SHIFT, Ord('\'), Ord('z'), Ord('x'), Ord('c'), Ord('v'), // 2
    Ord('b'), Ord('n'), Ord('m'), Ord(')'), Ord('.'), Ord('/'), K_SHIFT, Ord('*'),
    K_ALT, Ord(' '), 0, K_F1, K_F2, K_F3, K_F4, K_F5, // 3
    K_F6, K_F7, K_F8, K_F9, K_F10, K_PAUSE, 0, K_HOME,
    K_UPARROW, K_PGUP, Ord('-'), K_LEFTARROW, Ord('5'), K_RIGHTARROW, Ord('+'), K_END, //4
    K_DOWNARROW, K_PGDN, K_INS, K_DEL, 0, 0, 0, K_F11,
    K_F12, 0, 0, 0, 0, 0, 0, 0, // 5
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, // 6
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0 // 7
    );

  shiftscantokey: array[0..127] of byte = (
//  0           1       2       3       4       5       6       7
//  8           9       A       B       C       D       E       F
    0, 27, Ord('!'), Ord('@'), Ord('#'), Ord('$'), Ord('%'), Ord('^'),
    Ord('&'), Ord('*'), Ord('('), Ord(')'), Ord('_'), Ord('+'), K_BACKSPACE, 9, // 0
    Ord('Q'), Ord('W'), Ord('E'), Ord('R'), Ord('T'), Ord('Y'), Ord('U'), Ord('I'),
    Ord('O'), Ord('P'), Ord('{'), Ord('}'), 13, K_CTRL, Ord('A'), Ord('S'), // 1
    Ord('D'), Ord('F'), Ord('G'), Ord('H'), Ord('J'), Ord('K'), Ord('L'), Ord(':'),
    Ord('"'), Ord('~'), K_SHIFT, Ord('|'), Ord('Z'), Ord('X'), Ord('C'), Ord('V'), // 2
    Ord('B'), Ord('N'), Ord('M'), Ord('<'), Ord('>'), Ord('?'), K_SHIFT, Ord('*'),
    K_ALT, Ord(' '), 0, K_F1, K_F2, K_F3, K_F4, K_F5, // 3
    K_F6, K_F7, K_F8, K_F9, K_F10, K_PAUSE, 0, K_HOME,
    K_UPARROW, K_PGUP, Ord('_'), K_LEFTARROW, Ord('%'), K_RIGHTARROW, Ord('+'), K_END, //4
    K_DOWNARROW, K_PGDN, K_INS, K_DEL, 0, 0, 0, K_F11,
    K_F12, 0, 0, 0, 0, 0, 0, 0, // 5
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, // 6
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0 // 7
    );


(*
=======
MapKey

Map from windows to quake keynums
=======
*)

function MapKey(key: integer): integer;
begin
  key := (key shr 16) and 255;
  if key > 127 then
  begin
    result := 0;
    exit;
  end;

  result := scantokey[key];
  if result = 0 then
    Con_DPrintf('key 0x%02x has no translation'#10, [key]); // JVAL check format string
end;

(*
===================================================================

MAIN WINDOW

===================================================================
*)

(*
================
ClearAllStates
================
*)

procedure ClearAllStates;
var
  i: integer;
begin
// send an up event for each key, to make sure the server clears them all
  for i := 0 to 255 do
    Key_ProcessEvent(i, false);

  Key_ClearStates;
  IN_ClearStates;
end;


var
  sound_active: BOOL = false;

procedure AppActivate(fActive: BOOL; minimize: BOOL);
(****************************************************************************
*
* Function:     AppActivate
* Parameters:   fActive - True if app is activating
*
* Description:  If the application is activating, then swap the system
*               into SYSPAL_NOSTATIC mode so that our palettes will display
*               correctly.
*
****************************************************************************)
var
  NULLMOD: DEVMODE;
begin
  ActiveApp := fActive;
  Minimized := minimize;

// enable/disable sound on focus gain/loss
  if not ActiveApp and sound_active then
  begin
    S_BlockSound;
    sound_active := false;
  end
  else if ActiveApp and not sound_active then
  begin
    S_UnblockSound;
    sound_active := true;
  end;

  if fActive then
  begin
    if modestate = MS_FULLDIB then
    begin
      IN_ActivateMouse;
      IN_HideMouse;
      if vid_canalttab and vid_wassuspended then
      begin
        vid_wassuspended := false;
        ChangeDisplaySettings(gdevmode, CDS_FULLSCREEN);
        ShowWindow(mainwindow, SW_SHOWNORMAL);
      end;
    end
    else if (modestate = MS_WINDOWED) and (_windowed_mouse.value <> 0) and (key_dest = key_game) then
    begin
      IN_ActivateMouse;
      IN_HideMouse;
    end;
  end;

  if not fActive then
  begin
    if modestate = MS_FULLDIB then
    begin
      IN_DeactivateMouse;
      IN_ShowMouse;
      if vid_canalttab then
      begin
        ZeroMemory(@NULLMOD, SizeOf(NULLMOD));
        ChangeDisplaySettings(NULLMOD, 0);
        vid_wassuspended := true;
      end;
    end
    else if (modestate = MS_WINDOWED) and (_windowed_mouse.value <> 0) then
    begin
      IN_DeactivateMouse;
      IN_ShowMouse;
    end;
  end;
end;


(* main window procedure *)

function MainWndProc(hWnd: HWND; Msg: longword; wParam: WPARAM;
  lParam: LPARAM): LRESULT; stdcall; export;
var
  fActive, temp: integer;
  fMinimized: BOOL;
//  extern unsigned int uiWheelMessage;
begin
  (* return 1 if handled message, 0 if not *)
  result := 1;

  if Msg = uiWheelMessage then
    Msg := WM_MOUSEWHEEL;

  case Msg of

    WM_KILLFOCUS:
      begin
        if modestate = MS_FULLDIB then
          ShowWindow(mainwindow, SW_SHOWMINNOACTIVE);
      end;

    WM_CREATE: ;

    WM_MOVE:
      begin
        window_x := integer(LOWORD(lParam));
        window_y := integer(HIWORD(lParam));
        VID_UpdateWindowStatus;
      end;

    WM_KEYDOWN,
      WM_SYSKEYDOWN:
      Key_ProcessEvent(MapKey(lParam), true);

    WM_KEYUP,
      WM_SYSKEYUP:
      Key_ProcessEvent(MapKey(lParam), false);
      //I_ProcessInput;

    WM_SYSCHAR: ;
    // keep Alt-Space from happening

  // this is complicated because Win32 seems to pack multiple mouse events into
  // one update sometimes, so we always check all states and look for events
    WM_LBUTTONDOWN,
      WM_LBUTTONUP,
      WM_RBUTTONDOWN,
      WM_RBUTTONUP,
      WM_MBUTTONDOWN,
      WM_MBUTTONUP,
      WM_MOUSEMOVE:
      begin
        temp := 0;

        if wParam and MK_LBUTTON <> 0 then
          temp := temp or 1;

        if wParam and MK_RBUTTON <> 0 then
          temp := temp or 2;

        if wParam and MK_MBUTTON <> 0 then
          temp := temp or 4;

        IN_MouseEvent(temp);

      end;

    // JACK: This is the mouse wheel with the Intellimouse
    // Its delta is either positive or neg, and we generate the proper
    // Event.
    WM_MOUSEWHEEL:
      begin
        if short(HIWORD(wParam)) > 0 then
        begin
          Key_ProcessEvent(K_MWHEELUP, true);
          Key_ProcessEvent(K_MWHEELUP, false);
        end
        else
        begin
          Key_ProcessEvent(K_MWHEELDOWN, true);
          Key_ProcessEvent(K_MWHEELDOWN, false);
        end;
      end;

    WM_SIZE: ;

    WM_CLOSE:
      begin
        if MessageBox(mainwindow, 'Are you sure you want to quit?', 'Confirm Exit',
          MB_YESNO or MB_SETFOREGROUND or MB_ICONQUESTION) = IDYES then
          Sys_Quit;
      end;

    WM_ACTIVATE:
      begin
        fActive := LOWORD(wParam);
        fMinimized := BOOL(HIWORD(wParam));
        AppActivate(not (fActive = WA_INACTIVE), fMinimized);

        // fix the leftover Alt from any Alt-Tab or the like that switched us away
        ClearAllStates;

      end;

    WM_DESTROY:
      begin
        if dibwindow <> 0 then
          DestroyWindow(dibwindow);

        PostQuitMessage(0);
      end;

    MM_MCINOTIFY:
      result := CDAudio_MessageHandler(hWnd, Msg, wParam, lParam);

  else
    (* pass all unhandled messages to DefWindowProc *)
    result := DefWindowProc(hWnd, Msg, wParam, lParam);
  end;

end;

(*
=================
VID_NumModes
=================
*)

function VID_NumModes: integer;
begin
  result := nummodes;
end;


(*
=================
VID_GetModePtr
=================
*)

function VID_GetModePtr(modenum: integer): Pvmode_t;
begin
  if (modenum >= 0) and (modenum < nummodes) then
    result := @modelist[modenum]
  else
    result := @badmode;
end;


(*
=================
VID_GetModeDescription
=================
*)
var
  temp_VID_GetModeDescription: array[0..99] of char;

function VID_GetModeDescription(mode: integer): PChar;
var
  pv: Pvmode_t;
begin
  if (mode < 0) or (mode >= nummodes) then
  begin
    result := nil;
    exit;
  end;

  if not leavecurrentmode then
  begin
    pv := VID_GetModePtr(mode);
    result := pv.modedesc;
  end
  else
  begin
    sprintf(temp_VID_GetModeDescription, 'Desktop resolution (%dx%d)',
      [modelist[MODE_FULLSCREEN_DEFAULT].width,
      modelist[MODE_FULLSCREEN_DEFAULT].height]);
    result := temp_VID_GetModeDescription; // JVAL mayby @temp_VID_GetModeDescription[0] ?
  end;

end;

// KJB: Added this to return the mode driver name in description for console

var
  pinfo_VID_GetExtModeDescription: array[0..39] of char;

function VID_GetExtModeDescription(mode: integer): PChar;
var
  pv: Pvmode_t;
begin
  if (mode < 0) or (mode >= nummodes) then
  begin
    result := nil;
    exit;
  end;

  pv := VID_GetModePtr(mode);
  if modelist[mode]._type = MS_FULLDIB then
  begin
    if not leavecurrentmode then
      sprintf(pinfo_VID_GetExtModeDescription, '%s fullscreen', [pv.modedesc])
    else
      sprintf(pinfo_VID_GetExtModeDescription, 'Desktop resolution (%dx%d)',
        [modelist[MODE_FULLSCREEN_DEFAULT].width,
        modelist[MODE_FULLSCREEN_DEFAULT].height]);
  end
  else
  begin
    if modestate = MS_WINDOWED then
      sprintf(pinfo_VID_GetExtModeDescription, '%s windowed', [pv.modedesc])
    else
      sprintf(pinfo_VID_GetExtModeDescription, 'windowed');
  end;

  result := pinfo_VID_GetExtModeDescription;
end;


(*
=================
VID_DescribeCurrentMode_f
=================
*)

procedure VID_DescribeCurrentMode_f;
begin
  Con_Printf('%s'#10, [VID_GetExtModeDescription(vid_modenum)]);
end;


(*
=================
VID_NumModes_f
=================
*)

procedure VID_NumModes_f;
begin
  if nummodes = 1 then
    Con_Printf('%d video mode is available'#10, [nummodes])
  else
    Con_Printf('%d video modes are available'#10, [nummodes]);
end;


(*
=================
VID_DescribeMode_f
=================
*)

procedure VID_DescribeMode_f;
var
  modenum: integer;
  tmp: qboolean;
begin
  modenum := Q_atoi(Cmd_Argv_f(1));

  tmp := leavecurrentmode;
  leavecurrentmode := false;

  Con_Printf('%s'#10, [VID_GetExtModeDescription(modenum)]);

  leavecurrentmode := tmp;
end;


(*
=================
VID_DescribeModes_f
=================
*)

procedure VID_DescribeModes_f;
var
  i, lnummodes: integer;
  tmp: qboolean;
  pinfo: PChar;
begin
  lnummodes := VID_NumModes;

  tmp := leavecurrentmode;
  leavecurrentmode := false;

  for i := 1 to lnummodes - 1 do
  begin
    VID_GetModePtr(i);
    pinfo := VID_GetExtModeDescription(i);
    Con_Printf('%2d: %s'#10, [i, pinfo]);
  end;

  leavecurrentmode := tmp;
end;


procedure VID_InitDIB(inst: THandle);
var
  wc: WNDCLASS;
begin
  (* Register the frame class *)
  wc.style := 0;
  wc.lpfnWndProc := @MainWndProc;
  wc.cbClsExtra := 0;
  wc.cbWndExtra := 0;
  wc.HInstance := inst;
  wc.hIcon := 0;
  wc.hCursor := LoadCursor(0, IDC_ARROW);
  wc.hbrBackground := 0;
  wc.lpszMenuName := nil;
  wc.lpszClassName := 'WinQuake';

  if RegisterClass(wc) = 0 then
    Sys_Error('Couldn''t register window class');

  modelist[0]._type := MS_WINDOWED;

  if COM_CheckParm('-width') <> 0 then
  begin
    modelist[0].width := Q_atoi(com_argv[COM_CheckParm('-width') + 1]);
    if modelist[0].width < 320 then
      modelist[0].width := 320;
  end
  else
    modelist[0].width := 640;

  if COM_CheckParm('-height') <> 0 then
    modelist[0].height := Q_atoi(com_argv[COM_CheckParm('-height') + 1])
  else
    modelist[0].height := modelist[0].width * 240 div 320;

  if modelist[0].height < 240 then
    modelist[0].height := 240;

  sprintf(modelist[0].modedesc, '%dx%d', [modelist[0].width, modelist[0].height]);

  modelist[0].modenum := MODE_WINDOWED;
  modelist[0].dib := 1;
  modelist[0].fullscreen := 0;
  modelist[0].halfscreen := 0;
  modelist[0].bpp := 0;

  nummodes := 1;
end;


(*
=================
VID_InitFullDIB
=================
*)

procedure VID_InitFullDIB(inst: THandle);
var
  dmode: DEVMODE;
  i, modenum, originalnummodes, existingmode, numlowresmodes: integer;
  j, bpp: integer;
  done: qboolean;
  stat: BOOL;
begin
// enumerate >8 bpp modes
  originalnummodes := nummodes;
  modenum := 0;

  repeat
    stat := EnumDisplaySettings(nil, modenum, dmode);

    if (dmode.dmBitsPerPel >= 15) and
      (dmode.dmPelsWidth <= MAXWIDTH) and
      (dmode.dmPelsHeight <= MAXHEIGHT) and
      (nummodes < MAX_MODE_LIST) then
    begin
      dmode.dmFields := DM_BITSPERPEL or
        DM_PELSWIDTH or
        DM_PELSHEIGHT;

      if ChangeDisplaySettings(dmode, CDS_TEST or CDS_FULLSCREEN) =
        DISP_CHANGE_SUCCESSFUL then
      begin
        modelist[nummodes]._type := MS_FULLDIB;
        modelist[nummodes].width := dmode.dmPelsWidth;
        modelist[nummodes].height := dmode.dmPelsHeight;
        modelist[nummodes].modenum := 0;
        modelist[nummodes].halfscreen := 0;
        modelist[nummodes].dib := 1;
        modelist[nummodes].fullscreen := 1;
        modelist[nummodes].bpp := dmode.dmBitsPerPel;
        sprintf(modelist[nummodes].modedesc, '%dx%dx%d',
          [dmode.dmPelsWidth, dmode.dmPelsHeight, dmode.dmBitsPerPel]);

      // if the width is more than twice the height, reduce it by half because this
      // is probably a dual-screen monitor
        if COM_CheckParm('-noadjustaspect') = 0 then
        begin
          if modelist[nummodes].width > 2 * modelist[nummodes].height then
          begin
            modelist[nummodes].width := modelist[nummodes].width div 2;
            modelist[nummodes].halfscreen := 1;
            sprintf(modelist[nummodes].modedesc, '%dx%dx%d',
              [modelist[nummodes].width,
              modelist[nummodes].height,
                modelist[nummodes].bpp]);
          end;
        end;

        existingmode := 0;
        for i := originalnummodes to nummodes - 1 do
        begin
          if (modelist[nummodes].width = modelist[i].width) and
            (modelist[nummodes].height = modelist[i].height) and
            (modelist[nummodes].bpp = modelist[i].bpp) then
          begin
            existingmode := 1;
            break;
          end;
        end;

        if existingmode = 0 then
          inc(nummodes);

      end;
    end;

    inc(modenum);
  until not stat;

// see if there are any low-res modes that aren't being reported
  numlowresmodes := SizeOf(lowresmodes) div SizeOf(lowresmodes[0]);
  bpp := 16;
  done := false;

  repeat
    j := 0;
    while (j < numlowresmodes) and (nummodes < MAX_MODE_LIST) do
    begin
      dmode.dmBitsPerPel := bpp;
      dmode.dmPelsWidth := lowresmodes[j].width;
      dmode.dmPelsHeight := lowresmodes[j].height;
      dmode.dmFields := DM_BITSPERPEL or DM_PELSWIDTH or DM_PELSHEIGHT;

      if ChangeDisplaySettings(dmode, CDS_TEST or CDS_FULLSCREEN) =
        DISP_CHANGE_SUCCESSFUL then
      begin
        modelist[nummodes]._type := MS_FULLDIB;
        modelist[nummodes].width := dmode.dmPelsWidth;
        modelist[nummodes].height := dmode.dmPelsHeight;
        modelist[nummodes].modenum := 0;
        modelist[nummodes].halfscreen := 0;
        modelist[nummodes].dib := 1;
        modelist[nummodes].fullscreen := 1;
        modelist[nummodes].bpp := dmode.dmBitsPerPel;
        sprintf(modelist[nummodes].modedesc, '%dx%dx%d',
          [dmode.dmPelsWidth,
          dmode.dmPelsHeight,
            dmode.dmBitsPerPel]);

        existingmode := 0;
        for i := originalnummodes to nummodes - 1 do
        begin
          if (modelist[nummodes].width = modelist[i].width) and
            (modelist[nummodes].height = modelist[i].height) and
            (modelist[nummodes].bpp = modelist[i].bpp) then
          begin
            existingmode := 1;
            break;
          end;
        end;

        if existingmode = 0 then
          inc(nummodes);
      end;
      inc(j);
    end;

    case bpp of
      16: bpp := 32;

      32: bpp := 24;

      24: done := true;
    end;
  until done;

  if nummodes = originalnummodes then
    Con_SafePrintf('No fullscreen DIB modes found'#10);
end;

function VID_Is8bit: qboolean;
begin
  result := is8bit;
end;

//const
//  GL_SHARED_TEXTURE_PALETTE_EXT = $81FB;

procedure VID_Init8bitPalette;
var
  // Check for 8bit Extensions and initialize them.
  i: integer;
  thePalette: array[0..256 * 3 - 1] of byte;
  oldPalette, newPalette: PByte;
begin
//  glColorTableEXT := {lp3DFXFUNC(}wglGetProcAddress('glColorTableEXT'){)};
  if (not Assigned(glColorTableEXT)) then exit;
  if (strstr(str_gl_extensions, 'GL_EXT_shared_texture_palette') <> nil) then exit;
  if (COM_CheckParm('-no8bit') <> 0) then exit;

  Con_SafePrintf('8-bit GL extensions enabled.'#10);
  glEnable(GL_SHARED_TEXTURE_PALETTE_EXT);
  oldPalette := PByte(@d_8to24table); //d_8to24table3dfx;
  newPalette := PByte(@thePalette); // JVAL mayby oldPalette, newPalette PInteger and loop i := 0 to 192 ??
  for i := 0 to 255 do
  begin
    newPalette^ := oldPalette^;
    inc(newPalette);
    inc(oldPalette);
    newPalette^ := oldPalette^;
    inc(newPalette);
    inc(oldPalette);
    newPalette^ := oldPalette^;
    inc(newPalette);
    inc(oldPalette);
    inc(oldPalette); // JVAL skip one bit
  end;
  glColorTableEXT(GL_SHARED_TEXTURE_PALETTE_EXT, GL_RGB, 256, GL_RGB, GL_UNSIGNED_BYTE,
    @thePalette[0]);
  is8bit := true;
end;

procedure Check_Gamma(pal: PByteArray);
var
  f, inf: single;
  palette: array[0..767] of byte;
  i: integer;
begin
  i := COM_CheckParm('-gamma');
  if i = 0 then
  begin
    if (str_gl_renderer <> nil) and (strstr(str_gl_renderer, 'Voodoo') <> nil) or
      ((str_gl_vendor <> nil) and (strstr(str_gl_vendor, '3Dfx') <> nil)) then
      vid_gamma := 1
    else
      vid_gamma := 0.7; // default to 0.7 on non-3dfx hardware
  end
  else
    vid_gamma := Q_atof(com_argv[i + 1]);

  for i := 0 to 767 do
  begin
    f := fpow((pal[i] + 1) / 256.0, vid_gamma);
    inf := f * 255 + 0.5; // JVAL check (??? mayby * 256 ????)
    if inf < 0 then
      inf := 0;
    if inf > 255 then
      inf := 255;
    palette[i] := intval(inf);
  end;

  memcpy(pal, @palette, sizeof(palette));
end;

(*
===================
VID_Init
===================
*)

procedure VID_Init(palette: PByteArray);
var
  i, existingmode: integer;
  width, height, bpp, findbpp: integer;
  gldir: array[0..MAX_OSPATH - 1] of char;
  dc: HDC;
  dmode: DEVMODE;
  done: qboolean;
begin
  ZeroMemory(@dmode, SizeOf(dmode));

  Cvar_RegisterVariable(@vid_mode);
  Cvar_RegisterVariable(@vid_wait);
  Cvar_RegisterVariable(@vid_nopageflip);
  Cvar_RegisterVariable(@_vid_wait_override);
  Cvar_RegisterVariable(@_vid_default_mode);
  Cvar_RegisterVariable(@_vid_default_mode_win);
  Cvar_RegisterVariable(@vid_config_x);
  Cvar_RegisterVariable(@vid_config_y);
  Cvar_RegisterVariable(@vid_stretch_by_2);
  Cvar_RegisterVariable(@_windowed_mouse);
  Cvar_RegisterVariable(@gl_ztrick);

  Cmd_AddCommand('vid_nummodes', VID_NumModes_f);
  Cmd_AddCommand('vid_describecurrentmode', VID_DescribeCurrentMode_f);
  Cmd_AddCommand('vid_describemode', VID_DescribeMode_f);
  Cmd_AddCommand('vid_describemodes', VID_DescribeModes_f);

  Icon := LoadIcon(global_hInstance, 'MAINICON');
  VID_InitDIB(global_hInstance);
  nummodes := 1;

  VID_InitFullDIB(global_hInstance);

  if COM_CheckParm('-window') <> 0 then
  begin
    dc := GetDC(0);

    if (GetDeviceCaps(dc, RASTERCAPS) and RC_PALETTE) <> 0 then
      Sys_Error('Can''t run in non-RGB mode');

    ReleaseDC(0, dc);

    windowed := true;

    vid_default := MODE_WINDOWED;
  end
  else
  begin
    if nummodes = 1 then
      Sys_Error('No RGB fullscreen modes available');

    windowed := false;

    if COM_CheckParm('-mode') <> 0 then
      vid_default := Q_atoi(com_argv[COM_CheckParm('-mode') + 1])
    else
    begin
      if COM_CheckParm('-current') <> 0 then
      begin
        modelist[MODE_FULLSCREEN_DEFAULT].width :=
          GetSystemMetrics(SM_CXSCREEN);
        modelist[MODE_FULLSCREEN_DEFAULT].height :=
          GetSystemMetrics(SM_CYSCREEN);
        vid_default := MODE_FULLSCREEN_DEFAULT;
        leavecurrentmode := true;
      end
      else
      begin
        if COM_CheckParm('-width') <> 0 then
          width := Q_atoi(com_argv[COM_CheckParm('-width') + 1])
        else
          width := 640;
        height := width * 3 div 4; // JVAL avoid compiler warning

        if COM_CheckParm('-bpp') <> 0 then // JVAL maybe keep COM_CheckParm() values and not call again function COM_CheckParm()
        begin
          bpp := Q_atoi(com_argv[COM_CheckParm('-bpp') + 1]);
          findbpp := 0;
        end
        else
        begin
          bpp := 15;
          findbpp := 1;
        end;

        if COM_CheckParm('-height') <> 0 then
          height := Q_atoi(com_argv[COM_CheckParm('-height') + 1]);

      // if they want to force it, add the specified mode to the list
        if (COM_CheckParm('-force') <> 0) and (nummodes < MAX_MODE_LIST) then
        begin
          modelist[nummodes]._type := MS_FULLDIB;
          modelist[nummodes].width := width;
          modelist[nummodes].height := height;
          modelist[nummodes].modenum := 0;
          modelist[nummodes].halfscreen := 0;
          modelist[nummodes].dib := 1;
          modelist[nummodes].fullscreen := 1;
          modelist[nummodes].bpp := bpp;
          sprintf(modelist[nummodes].modedesc, '%dx%dx%d',
            [dmode.dmPelsWidth,
            dmode.dmPelsHeight,
              dmode.dmBitsPerPel]);

          existingmode := 0;
          for i := nummodes to nummodes - 1 do
          begin
            if (modelist[nummodes].width = modelist[i].width) and
              (modelist[nummodes].height = modelist[i].height) and
              (modelist[nummodes].bpp = modelist[i].bpp) then
            begin
              existingmode := 1;
              break;
            end;
          end;

          if existingmode = 0 then
            inc(nummodes);
        end;

        done := false;

        repeat
          if COM_CheckParm('-height') <> 0 then
          begin
            height := Q_atoi(com_argv[COM_CheckParm('-height') + 1]);

            vid_default := 0;
            for i := 1 to nummodes - 1 do
            begin
              if (modelist[i].width = width) and
                (modelist[i].height = height) and
                (modelist[i].bpp = bpp) then
              begin
                vid_default := i;
                done := true;
                break;
              end;
            end;
          end
          else
          begin
            vid_default := 0;
            for i := 1 to nummodes - 1 do
            begin
              if (modelist[i].width = width) and (modelist[i].bpp = bpp) then
              begin
                vid_default := i;
                done := true;
                break;
              end;
            end;
          end;

          if not done then
          begin
            if findbpp <> 0 then
            begin
              case bpp of
                15: bpp := 16;
                16: bpp := 32;
                32: bpp := 24;
                24: done := true;
              end;
            end
            else
              done := true;
          end;
        until done;

        if vid_default = 0 then
          Sys_Error('Specified video mode not available');
      end;
    end;
  end;

  vid_initialized := true;

  i := COM_CheckParm('-conwidth');
  if i <> 0 then
    vid.conwidth := Q_atoi(com_argv[i + 1])
  else
    vid.conwidth := 640;

  vid.conwidth := vid.conwidth and $FFF8; // make it a multiple of eight

  if vid.conwidth < 320 then
    vid.conwidth := 320;

  // pick a conheight that matches with correct aspect
  vid.conheight := vid.conwidth * 3 div 4;

  i := COM_CheckParm('-conheight');
  if i <> 0 then
    vid.conheight := Q_atoi(com_argv[i + 1]);
  if vid.conheight < 200 then
    vid.conheight := 200;

  vid.maxwarpwidth := WARP_WIDTH;
  vid.maxwarpheight := WARP_HEIGHT;
  vid.colormap := host_colormap;
  vid.fullbright := 256 - LittleLong(PIntegerArray(@vid.colormap)[2048]);

  DestroyWindow(hwnd_dialog);

  Check_Gamma(palette);
  VID_SetPalette(palette);

  VID_SetMode(vid_default, palette);

  if not InitOpenGL then
    Sys_Error('Could not initialize GL (InitOpenGL failed).');

  maindc := GetDC(mainwindow);
  bSetupPixelFormat(maindc);

  baseRC := wglCreateContext(maindc);
  if baseRC = 0 then
    Sys_Error('Could not initialize GL (wglCreateContext failed).'#10#10'GetLastError() = %d'#10#10'Make sure you are in 65535 color mode, and try running -window.', [GetLastError]);

  if not wglMakeCurrent(maindc, baseRC) then
    Sys_Error('wglMakeCurrent failed');

  GL_Init;

  sprintf(gldir, '%s/glquake', [com_gamedir]);
  Sys_mkdir(gldir);

  vid_realmode := vid_modenum;

  vid_menudrawfn := VID_MenuDraw;
  vid_menukeyfn := VID_MenuKey;

  strcpy(badmode.modedesc, 'Bad mode');
  vid_canalttab := true;

  if COM_CheckParm('-fullsbar') <> 0 then
    fullsbardraw := true;

  // Check for 3DFX Extensions and initialize them.
  VID_Init8bitPalette;
end;


//========================================================
// Video menu stuff
//========================================================
(*
extern void M_Menu_Options_f (void);
extern void M_Print (int cx, int cy, char *str);
extern void M_PrintWhite (int cx, int cy, char *str);
extern void M_DrawCharacter (int cx, int line, int num);
extern void M_DrawTransPic (int x, int y, qpic_t *pic);
extern void M_DrawPic (int x, int y, qpic_t *pic);
*)
var
  vid_line, vid_wmodes: integer;

type
  modedesc_t = record
    modenum: integer;
    desc: PChar;
    iscur: integer;
  end;
  Pmodedesc_t = ^modedesc_t;

const
  MAX_COLUMN_SIZE = 9;
  MODE_AREA_HEIGHT = (MAX_COLUMN_SIZE + 2);
  MAX_MODEDESCS = (MAX_COLUMN_SIZE * 3);

var
  modedescs: array[0..MAX_MODEDESCS - 1] of modedesc_t;

(*
================
VID_MenuDraw
================
*)

procedure VID_MenuDraw;
var
  p: Pqpic_t;
  ptr: PChar;
  lnummodes, i, k, column, row: integer;
begin
  p := Draw_CachePic('gfx/vidmodes.lmp');
  M_DrawPic((320 - p.width) div 2, 4, p);

  vid_wmodes := 0;
  lnummodes := VID_NumModes;

  i := 1;
  while (i < lnummodes) and (vid_wmodes < MAX_MODEDESCS) do
  begin
    ptr := VID_GetModeDescription(i);
    VID_GetModePtr(i);

    k := vid_wmodes;

    modedescs[k].modenum := i;
    modedescs[k].desc := ptr;
    modedescs[k].iscur := 0;

    if i = vid_modenum then
      modedescs[k].iscur := 1;

    inc(vid_wmodes);
    inc(i);
  end;

  if vid_wmodes > 0 then
  begin
    M_Print(2 * 8, 36 + 0 * 8, 'Fullscreen Modes (WIDTHxHEIGHTxBPP)');

    column := 8;
    row := 36 + 2 * 8;

    for i := 0 to vid_wmodes - 1 do
    begin
      if modedescs[i].iscur <> 0 then
        M_PrintWhite(column, row, modedescs[i].desc)
      else
        M_Print(column, row, modedescs[i].desc);

      inc(column, 13 * 8);

      if (i mod VID_ROW_SIZE) = (VID_ROW_SIZE - 1) then
      begin
        column := 8;
        inc(row, 8);
      end;
    end;
  end;

  M_Print(3 * 8, 36 + MODE_AREA_HEIGHT * 8 + 8 * 2, 'Video modes must be set from the');
  M_Print(3 * 8, 36 + MODE_AREA_HEIGHT * 8 + 8 * 3, 'command line with -width <width>');
  M_Print(3 * 8, 36 + MODE_AREA_HEIGHT * 8 + 8 * 4, 'and -bpp <bits-per-pixel>');
  M_Print(3 * 8, 36 + MODE_AREA_HEIGHT * 8 + 8 * 6, 'Select windowed mode with -window');
end;


(*
================
VID_MenuKey
================
*)

procedure VID_MenuKey(key: integer);
begin
  if key = K_ESCAPE then
  begin
    S_LocalSound('misc/menu1.wav');
    M_Menu_Options_f;
  end;
end;


end.

