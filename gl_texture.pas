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

unit gl_texture;

interface

uses
  q_delphi,
  OpenGL12,
  wad,
  cvar;

// TODO Remove it :)
const
  MAX_GLTEXTURES = 1024;

type
  glpic_t = record
    texnum: integer;
    sl, tl, sh, th: single;
  end;
  Pglpic_t = ^glpic_t;

type
  gltexture_t = record
    texnum: integer;
    identifier: array[0..63] of char;
    width, height: integer;
    mipmap: qboolean;
  end;
  Pgltexture_t = ^gltexture_t;

var
  conback_buffer: array[0..SizeOf(qpic_t) + SizeOf(glpic_t)] of byte;
  conback: Pqpic_t;
  translate_texture: integer;
  char_texture: integer;
  numgltextures: integer = 0;
  draw_chars: PByteArray; // 8*8 graphic characters
  draw_backtile: Pqpic_t;
  gltextures: array[0..MAX_GLTEXTURES - 1] of gltexture_t;

const
  MAX_SCRAPS = 2;
  BLOCK_WIDTH = 256;
  BLOCK_HEIGHT = 256;
var
  scrap_allocated: array[0..MAX_SCRAPS - 1, 0..BLOCK_WIDTH - 1] of integer;
  scrap_texels: array[0..MAX_SCRAPS - 1, 0..BLOCK_WIDTH * BLOCK_HEIGHT * 4 - 1] of byte;
  scrap_dirty: qboolean;
  scrap_texnum: integer;
///////////////////////////
var
  gl_nobind: cvar_t = (name: 'gl_nobind'; text: '0');
  gl_max_size: cvar_t = (name: 'gl_max_size'; text: '1024');
  gl_picmip: cvar_t = (name: 'gl_picmip'; text: '0');

  currenttexture: integer = -1; // to avoid unnecessary texture sets

const
  DEFAULT_LIGHTMAP_FORMAT = GL_LUMINANCE;

var
  gl_lightmap_format: integer = DEFAULT_LIGHTMAP_FORMAT; //4;

  gl_solid_format: integer = 3;
  gl_alpha_format: integer = 4;

  gl_filter_min: integer = GL_LINEAR_MIPMAP_NEAREST;
  gl_filter_max: integer = GL_LINEAR;
  textures_path: string = '';

type
  TPalette = array[0..255, 0..2] of byte;
  PPalette = ^TPalette;

procedure GL_Bind(texnum: integer);
procedure GL_Upload8_EXT(data: PByteArray; width, height: integer; mipmap: qboolean; alpha: qboolean);
procedure GL_Upload8(data: PByteArray; width, height: integer; mipmap: qboolean; alpha: qboolean);
function GL_LoadTexture(identifier: PChar; width, height: integer; data: PByteArray; mipmap: qboolean; alpha: qboolean): integer;
function GL_LoadTexture24(identifier: PChar; width, height: integer; data: PByteArray; mipmap: qboolean; alpha: qboolean; Palette: PPalette): integer;
function GL_LoadPicTexture(pic: Pqpic_t): integer;
procedure GL_SelectTexture(target: TGLenum);

implementation

uses
  gl_vidnt,
  t_main,
  sys_win,
  gl_defs,
  gl_rmain;

const
  GL_COLOR_INDEX8_EXT = $80E5;

var
  texels: integer;

procedure GL_Bind(texnum: integer);
begin
  if gl_nobind.value <> 0 then texnum := char_texture;
  if currenttexture = texnum then exit;
  currenttexture := texnum;
  bindTexFunc(GL_TEXTURE_2D, texnum);
end;

function GL_GetTexDimension(value: integer): integer;
begin
  result := 1;
  while result < value do
    result := result * 2;
  if result > intval(gl_max_size.value) then
    result := intval(gl_max_size.value);
end;


function GL_LoadExternalTexture(const texname: string; const texid: TGLUint;
  const use_mipmapping, transparent: qboolean; var twidth, theight: Integer): qboolean;
var
  t: PTexture;
begin
  t := T_LoadHiResTexture(texname);
  if t = nil then
  begin
    result := false;
    exit;
  end;

  t.ConvertTo32bit;
  t.SwapRGB;
  if not t.ExternalAlphaPresent then
  begin
    if transparent then
      t.SetDefaultAlphaChannel
    else
    begin
      t.Adjust32bitTransparency;
      t.SetAlphaChannel(255);
    end;
  end;
  twidth := GL_GetTexDimension(t.GetWidth);
  theight := GL_GetTexDimension(t.GetHeight);
  t.ScaleTo(twidth, theight);

  //glGenTextures(1, @texid);
  glBindTexture(GL_TEXTURE_2D, texid);

  if use_mipmapping then
  begin
    gluBuild2DMipmaps(GL_TEXTURE_2D, 3,
                      twidth, theight,
                      GL_RGBA, GL_UNSIGNED_BYTE, t.GetImage);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR_MIPMAP_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_LINEAR);
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MAX_ANISOTROPY_EXT, 2.0);
  end
  else
  begin
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8,
                 twidth, theight,
                 0, GL_RGBA, GL_UNSIGNED_BYTE, t.GetImage);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
  end;
  dispose(t, destroy);
  Result := True;
end;

(*
================
GL_FindTexture
================
*)

function GL_FindTexture(identifier: PChar): integer;
var
  i: integer;
  glt: Pgltexture_t;
begin
  result := -1;
  if identifier[0] = #0 then exit;
  glt := @gltextures[0];
  for i := 0 to numgltextures - 1 do
  begin
    if strcmp(identifier, glt.identifier) = 0 then
    begin
      result := glt.texnum;
      exit;
    end;
    inc(glt);
  end;

end;

(*
================
GL_ResampleTexture
================
*)

procedure GL_ResampleTexture(_in: PunsignedArray; inwidth, inheight: integer;
  _out: PunsignedArray; outwidth, outheight: integer);
var
  i, j: integer;
  inrow: PunsignedArray;
  frac, fracstep: unsigned;
begin
  fracstep := inwidth * $10000 div outwidth;
  for i := 0 to outheight - 1 do
  begin
    inrow := @_in[inwidth * (i * inheight div outheight)];
    frac := fracstep div 2;
    j := 0;
    while j < outwidth do
    begin
      _out[j] := inrow[frac shr 16];
      frac := frac + fracstep;
      inc(j);
      _out[j] := inrow[frac shr 16];
      frac := frac + fracstep;
      inc(j);
      _out[j] := inrow[frac shr 16];
      frac := frac + fracstep;
      inc(j);
      _out[j] := inrow[frac shr 16];
      frac := frac + fracstep;
      inc(j);
    end;
    _out := @_out[outwidth];
  end;
end;

(*
================
GL_Resample8BitTexture -- JACK
================
*)

procedure GL_Resample8BitTexture(_in: PByteArray; inwidth, inheight: integer;
  _out: PByteArray; outwidth, outheight: integer);
var
  i, j: integer;
  inrow: PByteArray;
  frac, fracstep: unsigned;
begin
  fracstep := inwidth * $10000 div outwidth;
  for i := 0 to outheight - 1 do
  begin
    inrow := @_in[inwidth * (i * inheight div outheight)];
    frac := fracstep div 2;
    j := 0;
    while j < outwidth do
    begin
      _out[j] := inrow[frac shr 16];
      frac := frac + fracstep;
      inc(j);
      _out[j] := inrow[frac shr 16];
      frac := frac + fracstep;
      inc(j);
      _out[j] := inrow[frac shr 16];
      frac := frac + fracstep;
      inc(j);
      _out[j] := inrow[frac shr 16];
      frac := frac + fracstep;
      inc(j);
    end;
    _out := @_out[outwidth];
  end;
end;

(*
================
GL_MipMap

Operates in place, quartering the size of the texture
================
*)

procedure GL_MipMap(_in: PByteArray; width, height: integer);
var
  i, j: integer;
  _out: PByteArray;
begin
  width := width * 4;
  height := height div 2;
  _out := _in;
  for i := 0 to height - 1 do
  begin
    j := 0;
    while j < width do
    begin
      _out[0] := (_in[0] + _in[4] + _in[width] + _in[width + 4]) div 4;
      _out[1] := (_in[1] + _in[5] + _in[width + 1] + _in[width + 5]) div 4;
      _out[2] := (_in[2] + _in[6] + _in[width + 2] + _in[width + 6]) div 4;
      _out[3] := (_in[3] + _in[7] + _in[width + 3] + _in[width + 7]) div 4;
      _out := @_out[4];
      _in := @_in[8];
      inc(j, 8);
    end;
    _in := @_in[width];
  end;
end;

(*
================
GL_MipMap8Bit

Mipping for 8 bit textures
================
*)

procedure GL_MipMap8Bit(_in: PByteArray; width, height: integer);
var
  i, j: integer;
  r, g, b: unsigned_short;
  _out, at1, at2, at3, at4: PByteArray;
begin
//  width <<=2;
  height := height div 2;
  _out := _in;
  for i := 0 to height - 1 do
  begin
    j := 0;
    while j < width do
    begin
      at1 := PByteArray(d_8to24table[_in[0]]);
      at2 := PByteArray(d_8to24table[_in[1]]);
      at3 := PByteArray(d_8to24table[_in[width]]);
      at4 := PByteArray(d_8to24table[_in[width + 1]]);

      r := at1[0] + at2[0] + at3[0] + at4[0];
      r := r shr 5;
      g := at1[1] + at2[1] + at3[1] + at4[1];
      g := g shr 5;
      b := at1[2] + at2[2] + at3[2] + at4[2];
      b := b shr 5;

      _out[0] := d_15to8table[r + (g shl 5) + (b shl 10)];
      _out := @_out[1];
      _in := @_in[2];
      inc(j, 2);
    end;
    _in := @_in[width];
  end;
end;

procedure GL_Upload24(data: PByteArray; width, height: integer; mipmap: qboolean; alpha: qboolean);
begin
//  glTexImage2D(GL_TEXTURE_2D, 0, 3, width, height, 0, GL_RGB, GL_UNSIGNED_BYTE, data);
  gluBuild2DMipmaps(GL_TEXTURE_2D, 3, width, height, GL_RGB, GL_UNSIGNED_BYTE, data);

  if mipmap then
  begin
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, gl_filter_min);
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, gl_filter_max);
  end
  else
  begin
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, gl_filter_max);
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, gl_filter_max);
  end;
end;

(*
===============
GL_Upload32
===============
*)

procedure GL_Upload32(data: PunsignedArray; width, height: integer;
  mipmap: qboolean; alpha: qboolean);
label
  done;
var
  samples: integer;
  scaled_width, scaled_height: integer;
  miplevel: integer;
  scaled_GL_Upload32: PunsignedArray;
  sz: integer;
begin
  scaled_width := 1;
  while scaled_width < width do
    scaled_width := scaled_width * 2;

  scaled_height := 1;
  while scaled_height < height do
    scaled_height := scaled_height * 2;

  scaled_width := scaled_width shr intval(gl_picmip.value);
  scaled_height := scaled_height shr intval(gl_picmip.value);

  if scaled_width > gl_max_size.value then
    scaled_width := intval(gl_max_size.value);
  if scaled_height > gl_max_size.value then
    scaled_height := intval(gl_max_size.value);

  sz := scaled_width * scaled_height * 4;
  scaled_GL_Upload32 := malloc(sz);

  samples := decide(alpha, gl_alpha_format, gl_solid_format);

  texels := texels + scaled_width * scaled_height;

  if (scaled_width = width) and (scaled_height = height) then
  begin
    if not mipmap then
    begin
      glTexImage2D(GL_TEXTURE_2D, 0, samples, scaled_width, scaled_height, 0, GL_RGBA, GL_UNSIGNED_BYTE, data);
      goto done;
    end;
    memcpy(scaled_GL_Upload32, data, width * height * 4);
  end
  else
    GL_ResampleTexture(data, width, height, scaled_GL_Upload32, scaled_width, scaled_height);

  glTexImage2D(GL_TEXTURE_2D, 0, samples, scaled_width, scaled_height, 0, GL_RGBA, GL_UNSIGNED_BYTE, scaled_GL_Upload32);
  if mipmap then
  begin
    miplevel := 0;
    while (scaled_width > 1) or (scaled_height > 1) do
    begin
      GL_MipMap(PByteArray(scaled_GL_Upload32), scaled_width, scaled_height);
      scaled_width := scaled_width div 2;
      scaled_height := scaled_height div 2;
      if scaled_width < 1 then
        scaled_width := 1;
      if scaled_height < 1 then
        scaled_height := 1;
      inc(miplevel);
      glTexImage2D(GL_TEXTURE_2D, miplevel, samples, scaled_width, scaled_height, 0, GL_RGBA, GL_UNSIGNED_BYTE, scaled_GL_Upload32);
    end;
  end;
done:

  memfree(Pointer(scaled_GL_Upload32), sz);

  if mipmap then
  begin
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, gl_filter_min);
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, gl_filter_max);
  end
  else
  begin
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, gl_filter_max);
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, gl_filter_max);
  end;
end;

procedure GL_Upload8_EXT(data: PByteArray; width, height: integer;
  mipmap: qboolean; alpha: qboolean);
label
  done;
var
  i, s: integer;
  scaled_width, scaled_height: integer;
  miplevel: integer;
  scaled_GL_Upload8: PByteArray;
  sz: integer;
begin
  s := width * height;
  // if there are no transparent pixels, make it a 3 component
  // texture even if it was specified as otherwise
  if alpha then
  begin
    for i := 0 to s - 1 do
    begin
      if data[i] = 255 then
      begin
        break;
      end;
    end;

//    if alpha and noalpha then
//      alpha := false;
  end;

  // JVAL mayby new proc for scaled_width / scaled_height calculation ??
  // (same code as GL_Upload32)
  scaled_width := 1;
  while scaled_width < width do
    scaled_width := scaled_width * 2;

  scaled_height := 1;
  while scaled_height < height do
    scaled_height := scaled_height * 2;

  scaled_width := scaled_width shr intval(gl_picmip.value);
  scaled_height := scaled_height shr intval(gl_picmip.value);

  if scaled_width > gl_max_size.value then
    scaled_width := intval(gl_max_size.value);
  if scaled_height > gl_max_size.value then
    scaled_height := intval(gl_max_size.value);

  sz := scaled_width * scaled_height;
  scaled_GL_Upload8 := malloc(sz);

  texels := texels + scaled_width * scaled_height;

  if (scaled_width = width) and (scaled_height = height) then
  begin
    if not mipmap then
    begin
      glTexImage2D(GL_TEXTURE_2D, 0, GL_COLOR_INDEX8_EXT, scaled_width, scaled_height, 0, GL_COLOR_INDEX, GL_UNSIGNED_BYTE, data);
      goto done;
    end;
    memcpy(scaled_GL_Upload8, data, width * height);
  end
  else
    GL_Resample8BitTexture(data, width, height, scaled_GL_Upload8, scaled_width, scaled_height);

  glTexImage2D(GL_TEXTURE_2D, 0, GL_COLOR_INDEX8_EXT, scaled_width, scaled_height, 0, GL_COLOR_INDEX, GL_UNSIGNED_BYTE, scaled_GL_Upload8);
  if mipmap then
  begin

    miplevel := 0;
    while (scaled_width > 1) or (scaled_height > 1) do
    begin
      GL_MipMap8Bit(scaled_GL_Upload8, scaled_width, scaled_height);
      scaled_width := scaled_width div 2;
      scaled_height := scaled_height div 2;
      if scaled_width < 1 then
        scaled_width := 1;
      if scaled_height < 1 then
        scaled_height := 1;
      inc(miplevel);
      glTexImage2D(GL_TEXTURE_2D, miplevel, GL_COLOR_INDEX8_EXT, scaled_width, scaled_height, 0, GL_COLOR_INDEX, GL_UNSIGNED_BYTE, scaled_GL_Upload8);
    end;
  end;
  done:

  memfree(Pointer(scaled_GL_Upload8), sz);
  if mipmap then
  begin
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, gl_filter_min);
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, gl_filter_max);
  end
  else
  begin
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, gl_filter_max);
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, gl_filter_max);
  end;
end;

(*
===============
GL_Upload8
===============
*)
procedure GL_Upload8(data: PByteArray; width, height: integer;
  mipmap: qboolean; alpha: qboolean);
var
  i, s: integer;
  noalpha: qboolean;
  p: integer;
  trans_GL_Upload8: PunsignedArray;
  sz: integer;
begin
  s := width * height;
  sz := s * SizeOf(unsigned);
  trans_GL_Upload8 := malloc(sz);
  // if there are no transparent pixels, make it a 3 component
  // texture even if it was specified as otherwise
  if alpha then
  begin
    noalpha := true;
    for i := 0 to s - 1 do
    begin
      p := data[i];
      if p = 255 then
        noalpha := false;
      trans_GL_Upload8[i] := d_8to24table[p];
    end;

    if alpha and noalpha then
      alpha := false;
  end
  else
  begin
    if s and 3 <> 0 then
      Sys_Error('GL_Upload8: s&3');
    i := 0;
    while i < s do
    begin
      trans_GL_Upload8[i] := d_8to24table[data[i]];
      inc(i);
    end;
  end;

  if VID_Is8bit and (not alpha) and (data <> @scrap_texels[0]) then
    GL_Upload8_EXT(data, width, height, mipmap, alpha)
  else
    GL_Upload32(trans_GL_Upload8, width, height, mipmap, alpha);
  memfree(pointer(trans_GL_Upload8), sz);
end;

(*
================
GL_LoadTexture
================
*)

function GL_LoadTexture(identifier: PChar; width, height: integer; data: PByteArray; mipmap: qboolean; alpha: qboolean): integer;
var
  glt: Pgltexture_t;
  fn: string;
begin
  // see if the texture is allready present
  result := GL_FindTexture(identifier);
  if result = -1 then
  begin
    glt := @gltextures[numgltextures];
    inc(numgltextures);
  end
  else
    exit;

  strcpy(glt.identifier, identifier);

  if glt.identifier <> '' then
  begin
    //
    //loadname
    fn := '';
    if textures_path <> '' then
      fn := textures_path + '/';
    fn := 'textures/' + fn + glt.identifier;

    if GL_LoadExternalTexture(fn, texture_extension_number, mipmap, alpha, glt.width, glt.height) then
    begin
      glt.texnum := texture_extension_number;
      result := texture_extension_number;
      glt.mipmap := mipmap;
      inc(texture_extension_number);
      exit;
    end;
  end;

  glt.texnum := texture_extension_number;
  glt.width := width;
  glt.height := height;
  glt.mipmap := mipmap;

  GL_Bind(texture_extension_number);

  if Assigned(data) then GL_Upload8(data, width, height, mipmap, alpha)
  else
  begin
   // TODO !!
  end;

  result := texture_extension_number;

  inc(texture_extension_number);
end;

function GL_LoadTexture24(identifier: PChar; width, height: integer; data: PByteArray; mipmap: qboolean; alpha: qboolean; Palette: PPalette): integer;
var
  i, j: integer;
  glt: Pgltexture_t;
  fn: string;
  buff: array of byte;
  offset: Integer;
begin
  // see if the texture is allready present
  Result := GL_FindTexture(identifier);
  if Result = -1 then
  begin
    glt := @gltextures[numgltextures];
    inc(numgltextures);
  end
  else
    exit;
  //if (width <> glt.width) or (height <> glt.height) then Sys_Error('GL_LoadTexture: cache mismatch');

  strcpy(glt.identifier, identifier);

  if glt.identifier <> '' then
  begin
    //
    //loadname
    fn := ''; if textures_path <> '' then fn := textures_path + '/'; fn := 'textures/' + fn + glt.identifier;
    fn := ReplaceStrAll(fn, '~', '');

    if GL_LoadExternalTexture(fn, texture_extension_number, mipmap, alpha, glt.width, glt.height) then
    begin
      glt.texnum := texture_extension_number;
      result := texture_extension_number;
      glt.mipmap := mipmap;
      inc(texture_extension_number);
      exit;
    end;
  end;

  glt.texnum := texture_extension_number;
  glt.width := width;
  glt.height := height;
  glt.mipmap := mipmap;

  if Assigned(data) then
  begin
    GL_Bind(texture_extension_number);

    SetLength(buff, width * height * 3);
    for i := 0 to width - 1 do
      for j := 0 to height - 1 do
      begin
        offset := (j * width + i);
        buff[offset * 3 + 0] := Palette[data[offset], 0];
        buff[offset * 3 + 1] := Palette[data[offset], 1];
        buff[offset * 3 + 2] := Palette[data[offset], 2];
      end;
    GL_Upload24(@buff[0], width, height, mipmap, alpha);
  end;

  result := texture_extension_number;

  inc(texture_extension_number);
end;
(*
================
GL_LoadPicTexture
================
*)

function GL_LoadPicTexture(pic: Pqpic_t): integer;
begin
  result := GL_LoadTexture('', pic.width, pic.height, @pic.data, false, true);
end;

(****************************************)

var
  oldtarget: TGLenum = TEXTURE0_SGIS;

procedure GL_SelectTexture(target: TGLenum);
begin
  if not gl_mtexable then
    exit;

  qglSelectTextureSGIS(target);
  if target = oldtarget then
    exit;
  cnttextures[oldtarget - TEXTURE0_SGIS] := currenttexture;
  currenttexture := cnttextures[target - TEXTURE0_SGIS];
  oldtarget := target;
end;

end.

