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

unit wad;

// wad.h

interface

//===============
//   TYPES
//===============

const
  CMP_NONE = 0;
  CMP_LZSS = 1;

  TYP_NONE = 0;
  TYP_LABEL = 1;

  TYP_LUMPY = 64;   // 64 + grab command number
  TYP_PALETTE = 64;
  TYP_QTEX = 65;
  TYP_QPIC = 66;
  TYP_SOUND = 67;
  TYP_MIPTEX = 68;

type
  Pqpic_t = ^qpic_t;
  qpic_t = record
    width, height: integer;
    data: array[0..3] of byte;      // variably sized
  end;


type
  Pwadinfo_t = ^wadinfo_t;
  wadinfo_t = record
    identification: array[0..3] of char;  // should be WAD2 or 2DAW
    numlumps: integer;
    infotableofs: integer;
  end;

type
  Plumpinfo_t = ^lumpinfo_t;
  lumpinfo_t = record
    filepos: integer;
    disksize: integer;
    size: integer;              // uncompressed
    _type: byte;
    compression: char;
    pad1, pad2: char;
    name: array[0..15] of char; // must be null terminated
  end;

procedure W_CleanupName(_in, _out: PChar);
procedure W_LoadWadFile(filename: PChar);
function W_GetLumpinfo(name: PChar): Plumpinfo_t;
function W_GetLumpName(name: PChar): pointer;
procedure SwapPic(pic: Pqpic_t);


implementation

// wad.c

uses
  q_delphi,
  common,
  sys_win;

var
  wad_numlumps: integer;
  wad_lumps: Plumpinfo_t;
  wad_base: PByteArray;


(*
==================
W_CleanupName

Lowercases name and pads with spaces and a terminating 0 to the length of
lumpinfo_t->name.
Used so lumpname lookups can proceed rapidly by comparing 4 chars at a time
Space padding is so names can be printed nicely in tables.
Can safely be performed in place.
==================
*)
procedure W_CleanupName(_in, _out: PChar);
var
  i: integer;
  c: char;
begin
  i := 0;
  while i < 16 do
  begin
    c := _in[i];
    if c = #0 then
      break;

    if (c >= 'A') and (c <= 'Z') then
      c := Chr(Ord(c) + Ord('a') - Ord('A'));
    _out[i] := c;
    inc(i);
  end;

  while i < 16 do
  begin
    _out[i] := #0;
    inc(i);
  end;
end;


(*
=============================================================================

automatic byte swapping

=============================================================================
*)

procedure SwapPic(pic: Pqpic_t);
begin
  pic.width := LittleLong(pic.width);
  pic.height := LittleLong(pic.height);
end;


(*
====================
W_LoadWadFile
====================
*)
procedure W_LoadWadFile(filename: PChar);
var
  lump_p: Plumpinfo_t;
  header: Pwadinfo_t;
  i: unsigned;
  infotableofs: integer;
begin
  wad_base := COM_LoadHunkFile(filename);
  if wad_base = nil then
    Sys_Error('W_LoadWadFile: couldn''t load %s', [filename]);

  header := Pwadinfo_t(wad_base);

  if (header.identification[0] <> 'W') or
     (header.identification[1] <> 'A') or
     (header.identification[2] <> 'D') or
     (header.identification[3] <> '2') then
    Sys_Error('Wad file %s doesn''t have WAD2 id'#10, [filename]);

  wad_numlumps := LittleLong(header.numlumps);
  infotableofs := LittleLong(header.infotableofs);
  wad_lumps := Plumpinfo_t(@wad_base[infotableofs]);

  lump_p := wad_lumps;
  for i := 0 to wad_numlumps - 1 do
  begin
    lump_p.filepos := LittleLong(lump_p.filepos);
    lump_p.size := LittleLong(lump_p.size);
    W_CleanupName(lump_p.name, lump_p.name);
    if lump_p._type = TYP_QPIC then
      SwapPic(Pqpic_t(@wad_base[lump_p.filepos]));
    inc(lump_p);
  end;
end;


(*
=============
W_GetLumpinfo
=============
*)
function W_GetLumpinfo(name: PChar): Plumpinfo_t;
var
  i: integer;
  clean: array[0..15] of char;
begin
  W_CleanupName(name, @clean[0]);

  result := wad_lumps;
  for i := 0 to wad_numlumps - 1 do
  begin
    if strcmp(clean, result.name) = 0 then
      exit;
    inc(result);
  end;

  Sys_Error('W_GetLumpinfo: %s not found', [name]);
  result := nil;
end;

function W_GetLumpName(name: PChar): pointer;
var
  lump: Plumpinfo_t;
begin
  lump := W_GetLumpinfo(name);

  result := pointer(@wad_base[lump.filepos]);
end;

function W_GetLumpNum(num: integer): pointer;
var
  lump: Plumpinfo_t;
begin
  if (num < 0) or (num > wad_numlumps) then
    Sys_Error('W_GetLumpNum: bad number: %d', [num]);

  lump := wad_lumps;
  inc(lump, num);

  result := pointer(@wad_base[lump.filepos]);
end;


end.
