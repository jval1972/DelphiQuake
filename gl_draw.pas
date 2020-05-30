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

unit gl_draw;

// draw.c -- this is the only file outside the refresh that touches the
// vid buffer

interface

uses
  q_delphi,
  OpenGL12,
  wad,
  cvar;

function Scrap_AllocBlock(w, h: integer; x, y: Pinteger): integer;
procedure Scrap_Upload;
function Draw_PicFromWad(name: PChar): Pqpic_t;
function Draw_CachePic(path: PChar): Pqpic_t;
procedure Draw_CharToConback(num: integer; dest: PByteArray);
procedure Draw_TextureMode_f;
procedure Draw_Init;
procedure Draw_Character(x, y: integer; chr: char); overload;
procedure Draw_Character(x, y: integer; num: integer); overload;
procedure Draw_String(x, y: integer; str: PChar);
procedure Draw_DebugChar(num: char);
procedure Draw_AlphaPic(x, y: integer; pic: Pqpic_t; alpha: single);
procedure Draw_Pic(x, y: integer; pic: Pqpic_t);
procedure Draw_TransPic(x, y: integer; pic: Pqpic_t);
procedure Draw_TransPicTranslate(x, y: integer; pic: Pqpic_t; translation: PByteArray);
procedure Draw_ConsoleBackground(lines: integer);
procedure Draw_TileClear(x, y: integer; w, h: integer);
procedure Draw_Fill(x, y: integer; w, h: integer; c: integer);
procedure Draw_FadeScreen;
procedure Draw_BeginDisc;
procedure Draw_EndDisc;

procedure GL_Set2D;

var
  draw_disc: Pqpic_t;


implementation

uses
  gl_texture,
  gl_vidnt,
  sys_win,
  quakedef,
  common,
  cmd,
  console,
  zone,
  host_h,
  sbar,
  gl_screen;

(*
=============================================================================

  scrap allocation

  Allocate all the little status bar obejcts into a single texture
  to crutch up stupid hardware / drivers

=============================================================================
*)

// returns a texture number and the position inside it

function Scrap_AllocBlock(w, h: integer; x, y: Pinteger): integer;
var
  i, j: integer;
  best, best2: integer;
  texnum: integer;
begin
  for texnum := 0 to MAX_SCRAPS - 1 do
  begin
    best := BLOCK_HEIGHT;

    for i := 0 to BLOCK_WIDTH - w - 1 do
    begin
      best2 := 0;

      for j := 0 to w - 1 do
      begin
        if scrap_allocated[texnum][i + j] >= best then
          break;
        if scrap_allocated[texnum][i + j] > best2 then
          best2 := scrap_allocated[texnum][i + j];
      end;
      if j = w then
      begin // this is a valid spot
        x^ := i;
        y^ := best2;
        best := best2;
      end;
    end;

    if best + h > BLOCK_HEIGHT then
      continue;

    for i := 0 to w - 1 do
      scrap_allocated[texnum][x^ + i] := best + h;

    result := texnum;
    exit;
  end;

  Sys_Error('Scrap_AllocBlock: full');
  result := -1;
end;

var
  scrap_uploads: integer = 0;

procedure Scrap_Upload;
var
  texnum: integer;
begin
  inc(scrap_uploads);

  for texnum := 0 to MAX_SCRAPS - 1 do
  begin
    GL_Bind(scrap_texnum + texnum);
    GL_Upload8(@scrap_texels[texnum], BLOCK_WIDTH, BLOCK_HEIGHT, false, true);
  end;
  scrap_dirty := false;
end;

//=============================================================================
(* Support Routines *)

type
  Pcachepic_t = ^cachepic_t;
  cachepic_t = record
    name: array[0..MAX_QPATH - 1] of char;
    pic: qpic_t;
    padding: array[0..31] of byte; // for appended glpic
  end;

const
  MAX_CACHED_PICS = 128;

var
  menu_cachepics: array[0..MAX_CACHED_PICS - 1] of cachepic_t;
  menu_numcachepics: integer;

  menuplyr_pixels: array[0..4096 - 1] of byte;

  pic_texels: integer;
  pic_count: integer;

function Draw_PicFromWad(name: PChar): Pqpic_t;
var
  p: Pqpic_t;
  gl: Pglpic_t;
  x, y: integer;
  i, j, k: integer;
  texnum: integer;
begin
  p := W_GetLumpName(name);
  gl := Pglpic_t(@p.data);

  // load little ones into the scrap
  if (p.width < 64) and (p.height < 64) then
  begin
    texnum := Scrap_AllocBlock(p.width, p.height, @x, @y);
    scrap_dirty := true;
    k := 0;
    for i := 0 to p.height - 1 do
      for j := 0 to p.width - 1 do
      begin
        scrap_texels[texnum][(y + i) * BLOCK_WIDTH + x + j] := p.data[k];
        inc(k);
      end;
    texnum := texnum + scrap_texnum;
    gl.texnum := texnum;
    gl.sl := (x + 0.01) / BLOCK_WIDTH;
    gl.sh := (x + p.width - 0.01) / BLOCK_WIDTH;
    gl.tl := (y + 0.01) / BLOCK_WIDTH;
    gl.th := (y + p.height - 0.01) / BLOCK_WIDTH;

    inc(pic_count);
    pic_texels := pic_texels + p.width * p.height;
  end
  else
  begin
    gl.texnum := GL_LoadPicTexture(p);
    gl.sl := 0;
    gl.sh := 1;
    gl.tl := 0;
    gl.th := 1;
  end;
  result := p;
end;


(*
================
Draw_CachePic
================
*)

function Draw_CachePic(path: PChar): Pqpic_t;
var
  pic: Pcachepic_t;
  i: integer;
  dat: Pqpic_t;
  gl: Pglpic_t;
begin
  pic := @menu_cachepics[0];
  for i := 0 to menu_numcachepics - 1 do
  begin
    if strcmp(path, pic.name) = 0 then
    begin
      result := @pic.pic;
      exit;
    end;
    inc(pic);
  end;

  if menu_numcachepics = MAX_CACHED_PICS then
    Sys_Error('menu_numcachepics = MAX_CACHED_PICS');
  inc(menu_numcachepics);
  strcpy(pic.name, path);

//
// load the pic from disk
//
  dat := Pqpic_t(COM_LoadTempFile(path));
  if dat = nil then
    Sys_Error('Draw_CachePic: failed to load %s', [path]);
  SwapPic(dat);

  // HACK HACK HACK --- we need to keep the bytes for
  // the translatable player picture just for the menu
  // configuration dialog
  if strcmp(path, 'gfx/menuplyr.lmp') = 0 then
    memcpy(@menuplyr_pixels, @dat.data, dat.width * dat.height);

  pic.pic.width := dat.width;
  pic.pic.height := dat.height;

  gl := Pglpic_t(@pic.pic.data);
  gl.texnum := GL_LoadPicTexture(dat);
  gl.sl := 0;
  gl.sh := 1;
  gl.tl := 0;
  gl.th := 1;

  result := @pic.pic;
end;


procedure Draw_CharToConback(num: integer; dest: PByteArray);
var
  row, col: integer;
  source: PByteArray;
  drawline: integer;
  x: integer;
begin
  row := num div 16;
  col := num and 15;
  source := @draw_chars[(row shl 10) + (col shl 3)];

  drawline := 8;

  while drawline <> 0 do
  begin
    for x := 0 to 7 do
      if source[x] <> 255 then
        dest[x] := $60 + source[x];
    source := PByteArray(@source[128]);
    dest := PByteArray(@dest[320]);
    dec(drawline);
  end;
end;

type
  glmode_t = record
    name: PChar;
    minimize, maximize: integer;
  end;

const
  NUMGLMODES = 6;
var
  modes: array[0..NUMGLMODES - 1] of glmode_t = (
    (name: 'GL_NEAREST'; minimize: GL_NEAREST; maximize: GL_NEAREST),
    (name: 'GL_LINEAR'; minimize: GL_LINEAR; maximize: GL_LINEAR),
    (name: 'GL_NEAREST_MIPMAP_NEAREST'; minimize: GL_NEAREST_MIPMAP_NEAREST; maximize: GL_NEAREST),
    (name: 'GL_LINEAR_MIPMAP_NEAREST'; minimize: GL_LINEAR_MIPMAP_NEAREST; maximize: GL_LINEAR),
    (name: 'GL_NEAREST_MIPMAP_LINEAR'; minimize: GL_NEAREST_MIPMAP_LINEAR; maximize: GL_NEAREST),
    (name: 'GL_LINEAR_MIPMAP_LINEAR'; minimize: GL_LINEAR_MIPMAP_LINEAR; maximize: GL_LINEAR)
    );

(*
===============
Draw_TextureMode_f
===============
*)

procedure Draw_TextureMode_f;
var
  i: integer;
  glt: Pgltexture_t;
begin
  if Cmd_Argc_f = 1 then
  begin
    for i := 0 to NUMGLMODES - 1 do
      if gl_filter_min = modes[i].minimize then
      begin
        Con_Printf('%s'#10, [modes[i].name]);
        exit;
      end;
    Con_Printf('current filter is unknown???'#10);
    exit;
  end;

  i := 0;
  while i < NUMGLMODES do
  begin
    if Q_strcasecmp(modes[i].name, Cmd_Argv_f(1)) = 0 then
      break;
    inc(i);
  end;
  if i = NUMGLMODES then
  begin
    Con_Printf('bad filter name'#10);
    exit;
  end;

  gl_filter_min := modes[i].minimize;
  gl_filter_max := modes[i].maximize;

  // change all the existing mipmap texture objects
  glt := @gltextures[0];
  for i := 0 to numgltextures - 1 do
  begin
    if glt.mipmap then
    begin
      GL_Bind(glt.texnum);
      glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, gl_filter_min);
      glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, gl_filter_max);
    end;
    inc(glt);
  end;
end;

(*
===============
Draw_Init
===============
*)

procedure Draw_Init;
var
  i: integer;
  cb: Pqpic_t;
  dest: PByteArray;
  x, y: integer;
  ver: array[0..39] of char;
  gl: Pglpic_t;
  start: integer;
  sz: integer;
begin
  Cvar_RegisterVariable(@gl_nobind);
  Cvar_RegisterVariable(@gl_max_size);
  Cvar_RegisterVariable(@gl_picmip);

  // 3dfx can only handle 256 wide textures
  if (Q_strncasecmp(str_gl_renderer, '3dfx', 4) = 0) or
    (strstr(str_gl_renderer, 'Glide') <> nil) then
    Cvar_SetValue('gl_max_size', 256)
  else
  begin
    glGetIntegerv(GL_MAX_TEXTURE_SIZE, @sz);
    Cvar_SetValue('gl_max_size', sz);
  end;

  Cmd_AddCommand('gl_texturemode', @Draw_TextureMode_f);

  // load the console background and the charset
  // by hand, because we need to write the version
  // string into the background before turning
  // it into a texture
  draw_chars := W_GetLumpName('conchars');
  for i := 0 to 256 * 64 - 1 do
    if draw_chars[i] = 0 then
      draw_chars[i] := 255; // proper transparent color

  // now turn them into textures
  char_texture := GL_LoadTexture('charset', 128, 128, draw_chars, false, true);

  start := Hunk_LowMark;

  cb := Pqpic_t(COM_LoadTempFile('gfx/conback.lmp'));
  if cb = nil then
    Sys_Error('Couldn''t load gfx/conback.lmp');
  SwapPic(cb);

  // hack the version number directly into the pic
  sprintf(ver, '(gl %4.2f) %4.2f', [GLQUAKE_VERSION, VERSION]);
  dest := @cb.data[320 * 186 + 320 - 11 - 8 * strlen(ver)];
  y := strlen(ver);
  for x := 0 to y - 1 do
    Draw_CharToConback(Ord(ver[x]), @dest[(x shl 3)]);

  conback.width := cb.width;
  conback.height := cb.height;

  glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
  glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);

  gl := Pglpic_t(@conback.data);
  gl.texnum := GL_LoadTexture('conback', conback.width, conback.height, @cb.data, false, false);
  gl.sl := 0;
  gl.sh := 1;
  gl.tl := 0;
  gl.th := 1;
  conback.width := vid.width;
  conback.height := vid.height;

  // free loaded console
  Hunk_FreeToLowMark(start);

  // save a texture slot for translated picture
  translate_texture := texture_extension_number;
  inc(texture_extension_number);

  // save slots for scraps
  scrap_texnum := texture_extension_number;
  texture_extension_number := texture_extension_number + MAX_SCRAPS;

  //
  // get the other pics we need
  //
  draw_disc := Draw_PicFromWad('disc');
  draw_backtile := Draw_PicFromWad('backtile');
end;



(*
================
Draw_Character

Draws one 8*8 graphics character with 0 being transparent.
It can be clipped to the top of the screen to allow the console to be
smoothly scrolled off.
================
*)

procedure Draw_Character(x, y: integer; chr: char);
begin
  Draw_Character(x, y, Ord(chr));
end;

procedure Draw_Character(x, y: integer; num: integer);
var
  row, col: integer;
  frow, fcol, size: single;
begin
  if num = 32 then
    exit; // space

  num := num and 255;

  if y <= -8 then
    exit; // totally off screen

  row := num shr 4;
  col := num and 15;

  frow := row * 0.0625;
  fcol := col * 0.0625;
  size := 0.0625;

  GL_Bind(char_texture);

  glBegin(GL_QUADS);
  glTexCoord2f(fcol, frow);
  glVertex2f(x, y);
  glTexCoord2f(fcol + size, frow);
  glVertex2f(x + 8, y);
  glTexCoord2f(fcol + size, frow + size);
  glVertex2f(x + 8, y + 8);
  glTexCoord2f(fcol, frow + size);
  glVertex2f(x, y + 8);
  glEnd;
end;

(*
================
Draw_String
================
*)

procedure Draw_String(x, y: integer; str: PChar);
begin
  if str <> nil then
    while str^ <> #0 do
    begin
      Draw_Character(x, y, str^);
      inc(str);
      inc(x, 8);
    end;
end;

(*
================
Draw_DebugChar

Draws a single character directly to the upper right corner of the screen.
This is for debugging lockups by drawing different chars in different parts
of the code.
================
*)

procedure Draw_DebugChar(num: char);
begin
end;

(*
=============
Draw_AlphaPic
=============
*)

procedure Draw_AlphaPic(x, y: integer; pic: Pqpic_t; alpha: single);
var
  gl: Pglpic_t;
begin
  if scrap_dirty then
    Scrap_Upload;
  gl := Pglpic_t(@pic.data);
  glDisable(GL_ALPHA_TEST);
  glEnable(GL_BLEND);
//  glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
//  glCullFace(GL_FRONT);
  glColor4f(1, 1, 1, alpha);
  GL_Bind(gl.texnum);
  glBegin(GL_QUADS);
  glTexCoord2f(gl.sl, gl.tl);
  glVertex2f(x, y);
  glTexCoord2f(gl.sh, gl.tl);
  glVertex2f(x + pic.width, y);
  glTexCoord2f(gl.sh, gl.th);
  glVertex2f(x + pic.width, y + pic.height);
  glTexCoord2f(gl.sl, gl.th);
  glVertex2f(x, y + pic.height);
  glEnd;
  glColor4f(1, 1, 1, 1);
  glEnable(GL_ALPHA_TEST);
  glDisable(GL_BLEND);
end;


(*
=============
Draw_Pic
=============
*)

procedure Draw_Pic(x, y: integer; pic: Pqpic_t);
var
  gl: Pglpic_t;
begin
  if scrap_dirty then
    Scrap_Upload;
  gl := Pglpic_t(@pic.data);
  glColor4f(1, 1, 1, 1);
  GL_Bind(gl.texnum);
  glBegin(GL_QUADS);
  glTexCoord2f(gl.sl, gl.tl);
  glVertex2f(x, y);
  glTexCoord2f(gl.sh, gl.tl);
  glVertex2f(x + pic.width, y);
  glTexCoord2f(gl.sh, gl.th);
  glVertex2f(x + pic.width, y + pic.height);
  glTexCoord2f(gl.sl, gl.th);
  glVertex2f(x, y + pic.height);
  glEnd;
end;


(*
=============
Draw_TransPic
=============
*)

procedure Draw_TransPic(x, y: integer; pic: Pqpic_t);
begin
  if (x < 0) or ((x + pic.width) > vid.width) or
    (y < 0) or ((y + pic.height) > vid.height) then
  begin
    Sys_Error('Draw_TransPic: bad coordinates');
  end;

  Draw_Pic(x, y, pic);
end;


(*
=============
Draw_TransPicTranslate

Only used for the player color selection menu
=============
*)

procedure Draw_TransPicTranslate(x, y: integer; pic: Pqpic_t; translation: PByteArray);
var
  v, u: integer;
  trans: array[0..64 * 64 - 1] of unsigned;
  dest: PunsignedArray;
  src: PByteArray;
  p: integer;
begin
  GL_Bind(translate_texture);

  dest := @trans[0];
  for v := 0 to 63 do
  begin
    src := @menuplyr_pixels[((v * pic.height) shr 6) * pic.width];
    for u := 0 to 63 do
    begin
      p := src[(u * pic.width) shr 6];
      if p = 255 then
        dest[u] := p
      else
        dest[u] := d_8to24table[translation[p]];
    end;
    dest := @dest[64];
  end;

  glTexImage2D(GL_TEXTURE_2D, 0, gl_alpha_format, 64, 64, 0, GL_RGBA, GL_UNSIGNED_BYTE, @trans);

  glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
  glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);

  glColor3f(1, 1, 1);
  glBegin(GL_QUADS);
  glTexCoord2f(0, 0);
  glVertex2f(x, y);
  glTexCoord2f(1, 0);
  glVertex2f(x + pic.width, y);
  glTexCoord2f(1, 1);
  glVertex2f(x + pic.width, y + pic.height);
  glTexCoord2f(0, 1);
  glVertex2f(x, y + pic.height);
  glEnd;
end;


(*
================
Draw_ConsoleBackground

================
*)

procedure Draw_ConsoleBackground(lines: integer);
var
  y: integer;
begin
  y := (vid.height * 3) shr 2;

  if lines > y then
    Draw_Pic(0, lines - vid.height, conback)
  else
    Draw_AlphaPic(0, lines - vid.height, conback, (1.2 * lines) / y);
end;


(*
=============
Draw_TileClear

This repeats a 64*64 tile graphic to fill the screen around a sized down
refresh window.
=============
*)

procedure Draw_TileClear(x, y: integer; w, h: integer);
begin
  glColor3f(1, 1, 1);
  GL_Bind(PInteger(@draw_backtile.data)^);
  glBegin(GL_QUADS);
  glTexCoord2f(x / 64.0, y / 64.0);
  glVertex2f(x, y);
  glTexCoord2f((x + w) / 64.0, y / 64.0);
  glVertex2f(x + w, y);
  glTexCoord2f((x + w) / 64.0, (y + h) / 64.0);
  glVertex2f(x + w, y + h);
  glTexCoord2f(x / 64.0, (y + h) / 64.0);
  glVertex2f(x, y + h);
  glEnd;
end;


(*
=============
Draw_Fill

Fills a box of pixels with a single color
=============
*)

procedure Draw_Fill(x, y: integer; w, h: integer; c: integer);
begin
  glDisable(GL_TEXTURE_2D);
  glColor3f(host_basepal[c * 3] / 255.0,
    host_basepal[c * 3 + 1] / 255.0,
    host_basepal[c * 3 + 2] / 255.0);

  glBegin(GL_QUADS);

  glVertex2f(x, y);
  glVertex2f(x + w, y);
  glVertex2f(x + w, y + h);
  glVertex2f(x, y + h);

  glEnd;
  glColor3f(1, 1, 1);
  glEnable(GL_TEXTURE_2D);
end;

//=============================================================================

(*
================
Draw_FadeScreen

================
*)

procedure Draw_FadeScreen;
begin
  glEnable(GL_BLEND);
  glDisable(GL_TEXTURE_2D);
  glColor4f(0, 0, 0, 0.8);
  glBegin(GL_QUADS);

  glVertex2f(0, 0);
  glVertex2f(vid.width, 0);
  glVertex2f(vid.width, vid.height);
  glVertex2f(0, vid.height);

  glEnd;
  glColor4f(1, 1, 1, 1);
  glEnable(GL_TEXTURE_2D);
  glDisable(GL_BLEND);

  Sbar_Changed;
end;

//=============================================================================

(*
================
Draw_BeginDisc

Draws the little blue disc in the corner of the screen.
Call before beginning any disc IO.
================
*)

procedure Draw_BeginDisc;
begin
  if draw_disc = nil then
    exit;
  glDrawBuffer(GL_FRONT);
  Draw_Pic(vid.width - 24, 0, draw_disc);
  glDrawBuffer(GL_BACK);
end;


(*
================
Draw_EndDisc

Erases the disc icon.
Call after completing any disc IO
================
*)

procedure Draw_EndDisc;
begin
end;

(*
================
GL_Set2D

Setup as if the screen was 320*200
================
*)

procedure GL_Set2D;
begin
  glViewport(glx, gly, glwidth, glheight);

  glMatrixMode(GL_PROJECTION);
  glLoadIdentity;
  glOrtho(0, vid.width, vid.height, 0, -99999, 99999);

  glMatrixMode(GL_MODELVIEW);
  glLoadIdentity;

  glDisable(GL_DEPTH_TEST);
  glDisable(GL_CULL_FACE);
  glDisable(GL_BLEND);
  glEnable(GL_ALPHA_TEST);
//  glDisable (GL_ALPHA_TEST);

  glColor4f(1, 1, 1, 1);
end;

//====================================================================

initialization
  conback := Pqpic_t(@conback_buffer);

end.

