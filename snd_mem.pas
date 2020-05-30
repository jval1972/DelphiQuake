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

unit snd_mem;

// snd_mem.c: sound caching

interface

uses
  q_delphi,
  sound;

procedure ResampleSfx(sfx: Psfx_t; inrate: integer; inwidth: integer; data: PByteArray);
function S_LoadSound(s: Psfx_t): Psfxcache_t;
function GetWavinfo(name: PChar; wav: PByteArray; wavlength: integer): wavinfo_t;

implementation

uses
  zone,
  snd_dma_h,
  common,
  console,
  sys_win;

(*
================
ResampleSfx
================
*)

procedure ResampleSfx(sfx: Psfx_t; inrate: integer; inwidth: integer; data: PByteArray);
var
  outcount: integer;
  srcsample: integer;
  stepscale: single;
  i: integer;
  sample, samplefrac, fracstep: integer;
  sc: Psfxcache_t;
begin
  sc := Cache_Check(@sfx.cache);
  if sc = nil then
    exit;

  stepscale := inrate / shm.speed; // this is usually 0.5, 1, or 2

  outcount := intval(sc.length / stepscale);
  sc.length := outcount;
  if sc.loopstart <> -1 then
    sc.loopstart := intval(sc.loopstart / stepscale);

  sc.speed := shm.speed;
  if loadas8bit.value <> 0 then
    sc.width := 1
  else
    sc.width := inwidth;
  sc.stereo := 0;

// resample / decimate to the current source rate

  if (stepscale = 1) and (inwidth = 1) and (sc.width = 1) then
  begin
// fast special case
    for i := 0 to outcount - 1 do
      signed_char(sc.data[i]) := data[i] - 128; // JVAL ???
  end
  else
  begin
// general case
    samplefrac := 0;
    fracstep := intval(stepscale * 256);
    for i := 0 to outcount - 1 do
    begin
      srcsample := samplefrac div 256;
      samplefrac := samplefrac + fracstep;
      if inwidth = 2 then
        sample := LittleShort(PshortArray(data)[srcsample])
      else
        sample := ((data[srcsample] - 128) shl 8); // JVAL check!
      if sc.width = 2 then
        PShortArray(@sc.data)[i] := sample
      else
        sc.data[i] := sample div 256;
    end;
  end;
end;

//=============================================================================

(*
==============
S_LoadSound
==============
*)

function S_LoadSound(s: Psfx_t): Psfxcache_t;
var
  namebuffer: array[0..255] of char;
  data: PByteArray;
  info: wavinfo_t;
  len: integer;
  stepscale: single;
  sc: Psfxcache_t;
  stackbuf: array[0..1 * 1024 - 1] of byte; // avoid dirtying the cache heap // JVAL ???
begin
// see if still in memory
  sc := Cache_Check(@s.cache);
  if sc <> nil then
  begin
    result := sc;
    exit;
  end;

//Con_Printf ("S_LoadSound: %x\n", (int)stackbuf);
// load it in
  Q_strcpy(namebuffer, 'sound/');
  Q_strcat(namebuffer, s.name);

//  Con_Printf ("loading %s\n",namebuffer);

  data := COM_LoadStackFile(namebuffer, @stackbuf, SizeOf(stackbuf)); // JVAL check stackbuf

  if data = nil then
  begin
    Con_Printf('Couldn''t load %s'#10, [namebuffer]);
    result := nil;
    exit;
  end;

  info := GetWavinfo(s.name, data, com_filesize);
  if info.channels <> 1 then
  begin
    Con_Printf('%s is a stereo sample'#10, [s.name]);
    result := nil;
    exit;
  end;

  stepscale := info.rate / shm.speed;
  len := intval(info.samples / stepscale);

  len := len * info.width * info.channels;

  sc := Cache_Alloc(@s.cache, len + SizeOf(sfxcache_t), s.name);
  if sc = nil then
  begin
    result := nil;
    exit;
  end;

  sc.length := info.samples;
  sc.loopstart := info.loopstart;
  sc.speed := info.rate;
  sc.width := info.width;
  sc.stereo := info.channels;

  ResampleSfx(s, sc.speed, sc.width, @data[info.dataofs]);

  result := sc;
end;



(*
===============================================================================

WAV loading

===============================================================================
*)

var
  data_p: PByte;
  iff_end: PByte;
  last_chunk: PByte;
  iff_data: PByte;
  iff_chunk_len: integer;


function GetLittleShort: short; // JVAL check shifts, negative values???
begin
  result := data_p^;
  inc(data_p);
  result := result + data_p^ * 256;
  inc(data_p);
end;

function GetLittleLong: integer; // JVAL check shifts, negative values???
begin
  result := data_p^;
  inc(data_p);
  result := result + data_p^ * 256;
  inc(data_p);
  result := result + data_p^ * (256 * 256);
  inc(data_p);
  result := result + data_p^ * (256 * 256 * 256);
  inc(data_p);
end;

procedure FindNextChunk(name: PChar);
begin
  while true do
  begin
    data_p := last_chunk;

    if integer(data_p) >= integer(iff_end) then
    begin // didn't find the chunk
      data_p := nil;
      exit;
    end;

    inc(data_p, 4);
    iff_chunk_len := GetLittleLong;
    if iff_chunk_len < 0 then
    begin
      data_p := nil;
      exit;
    end;
//    if (iff_chunk_len > 1024*1024)
//      Sys_Error ("FindNextChunk: %d length is past the 1 meg sanity limit", iff_chunk_len);
    dec(data_p, 8);
    last_chunk := data_p;
    inc(last_chunk, 8 + ((iff_chunk_len + 1) and (not 1)));
    if Q_strncmp(PChar(data_p), name, 4) = 0 then
      exit;
  end;
end;

procedure FindChunk(name: PChar);
begin
  last_chunk := iff_data;
  FindNextChunk(name);
end;


procedure DumpChunks;
var
  str: array[0..4] of char;
begin
  str[4] := #0;
  data_p := iff_data;
  repeat
    memcpy(@str[0], data_p, 4);
    inc(data_p, 4);
    iff_chunk_len := GetLittleLong;
    Con_Printf('0x%x : %s (%d)'#10, [integer(data_p) - 4, @str[0], iff_chunk_len]);
    inc(data_p, (iff_chunk_len + 1) and (not 1));
  until integer(data_p) >= integer(iff_end);
end;


(*
============
GetWavinfo
============
*)

function GetWavinfo(name: PChar; wav: PByteArray; wavlength: integer): wavinfo_t;
var
  i: integer;
  format: integer;
  samples: integer;
begin
  ZeroMemory(@result, SizeOf(result));

  if wav = nil then
    exit;

  iff_data := @wav[0];
  iff_end := @wav[wavlength];

// find "RIFF" chunk
  FindChunk('RIFF');
  if not ((data_p <> nil) and (Q_strncmp(C_PChar(data_p, 8), 'WAVE', 4) = 0)) then
  begin
    Con_Printf('Missing RIFF/WAVE chunks'#10);
    exit;
  end;

// get "fmt " chunk
  iff_data := data_p;
  inc(iff_data, 12);
// DumpChunks ();

  FindChunk('fmt ');
  if data_p = nil then
  begin
    Con_Printf('Missing fmt chunk'#10);
    exit;
  end;
  inc(data_p, 8);
  format := GetLittleShort;
  if format <> 1 then
  begin
    Con_Printf('Microsoft PCM format only'#10);
    exit;
  end;

  result.channels := GetLittleShort();
  result.rate := GetLittleLong();
  inc(data_p, 4 + 2);
  result.width := GetLittleShort div 8;

// get cue chunk
  FindChunk('cue ');
  if data_p <> nil then
  begin
    inc(data_p, 32);
    result.loopstart := GetLittleLong;
//    Con_Printf("loopstart=%d\n", sfx->loopstart);

  // if the next chunk is a LIST chunk, look for a cue length marker
    FindNextChunk('LIST');
    if data_p <> nil then
    begin
      if strncmp(C_PChar(data_p, 28), 'mark', 4) = 0 then
      begin // this is not a proper parse, but it works with cooledit...
        inc(data_p, 24);
        i := GetLittleLong; // samples in loop
        result.samples := result.loopstart + i; // JVAL pointers ???
//        Con_Printf("looped length: %d\n", i);
      end;
    end;
  end
  else
    result.loopstart := -1;

// find data chunk
  FindChunk('data');
  if data_p = nil then
  begin
    Con_Printf('Missing data chunk'#10);
    exit;
  end;

  inc(data_p, 4);
  samples := GetLittleLong div result.width;

  if result.samples <> 0 then
  begin
    if samples < result.samples then
      Sys_Error('Sound %s has a bad loop length', [name]);
  end
  else
    result.samples := samples;

  result.dataofs := integer(data_p) - integer(wav); // JVAL check!

end;


end.

