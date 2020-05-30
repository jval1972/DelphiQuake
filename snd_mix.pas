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

unit snd_mix;

// snd_mix.c -- portable code to mix sounds for snd_dma.c

interface

procedure SND_InitScaletable;
procedure S_PaintChannels(endtime: integer);

implementation

uses
  q_delphi,
  Windows,
  DirectX,
  sound,
  snd_dma,
  snd_win_h,
  snd_dma_h,
  console,
  snd_mem;

const
  PAINTBUFFER_SIZE = 512;

var
  paintbuffer: array[0..PAINTBUFFER_SIZE - 1] of portable_samplepair_t;
  snd_scaletable: array[0..31, 0..255] of integer;
  snd_p: PIntegerArray;
  snd_linear_count, snd_vol: integer;
  snd_out: PShortArray;

procedure Snd_WriteLinearBlastStereo16;
var
  i: integer;
  val: Integer;
begin
  i := 0;
  while i < snd_linear_count do
  begin
    val := (snd_p[i] * snd_vol) div 256;
    if val > $7FFF then
      snd_out[i] := $7FFF
    else if val < short($8000) then
      snd_out[i] := short($8000)
    else snd_out[i] := val;

    inc(i, 1);
  end;
end;

procedure S_Restart;
begin
  S_Shutdown;
  S_Startup;
end;

procedure S_TransferStereo16(endtime: integer);
var
  lpos: integer;
  lpaintedtime: integer;
  pbuf, pbuf2: pointer;
  reps: integer;
  dwSize, dwSize2: DWORD;
  ret: HRESULT;

  function get_ds_ret: HRESULT;
  begin
    ret := pDSBuf.Lock(0, gSndBufSize, pbuf, dwSize, // JVAL check params!
      pbuf2, dwSize2, 0);
    result := ret;
  end;

begin
  snd_vol := intval(volume.value * 256);

  snd_p := PIntegerArray(@paintbuffer[0]);
  lpaintedtime := paintedtime;

  if pDSBuf <> nil then
  begin
    reps := 0;

    while get_ds_ret <> DS_OK do
    begin
      if ret <> DSERR_BUFFERLOST then
      begin
        Con_Printf('S_TransferStereo16: DS::Lock Sound Buffer Failed'#10);
        S_Restart;
        exit;
      end;

      inc(reps);
      if reps > 10000 then
      begin
        Con_Printf('S_TransferStereo16: DS: couldn''t restore buffer'#10);
        S_Restart;
        exit;
      end;
    end;
  end
  else
  begin
    pbuf := shm.buffer;
  end;

  while lpaintedtime < endtime do
  begin
  // handle recirculating buffer issues
    lpos := lpaintedtime and ((shm.samples div 2) - 1);

    snd_out := @PShortArray(pbuf)[lpos shl 1];

    snd_linear_count := (shm.samples div 2) - lpos;
    if lpaintedtime + snd_linear_count > endtime then
      snd_linear_count := endtime - lpaintedtime;

    snd_linear_count := snd_linear_count shl 1;

  // write a linear blast of samples
    Snd_WriteLinearBlastStereo16;

//    inc(snd_p, snd_linear_count);
    snd_p := @snd_p[snd_linear_count];
    inc(lpaintedtime, snd_linear_count div 2);
  end;

  if pDSBuf <> nil then
    pDSBuf.Unlock(pbuf, dwSize, nil, 0);
end;

procedure S_TransferPaintBuffer(endtime: integer);
var
  out_idx: integer;
  count: integer;
  out_mask: integer;
  p: PInteger;
  step: integer;
  val: integer;
  snd_vol: integer;
  pbuf, pbuf2: pointer;
  reps: integer;
  dwSize, dwSize2: DWORD;
  ret: HRESULT;
  out16: PShortArray;
  out8: PByteArray;
  dwNewpos, dwWrite: DWORD;

  function get_ds_ret: HRESULT;
  begin
    ret := pDSBuf.Lock(0, gSndBufSize, pbuf, dwSize,
      pbuf2, dwSize2, 0);
    result := ret;
  end;

begin
  if (shm.samplebits = 16) and (shm.channels = 2) then
  begin
    S_TransferStereo16(endtime);
    exit;
  end;

  p := PInteger(@paintbuffer[0]);
  count := (endtime - paintedtime) * shm.channels;
  out_mask := shm.samples - 1;
  out_idx := (paintedtime * shm.channels) and out_mask; // JVAL check priotities!
  step := 3 - shm.channels;
  snd_vol := intval(volume.value * 256);

  if pDSBuf <> nil then
  begin
    reps := 0;

    while get_ds_ret <> DS_OK do
    begin
      if ret <> DSERR_BUFFERLOST then
      begin
        Con_Printf('S_TransferPaintBuffer: DS::Lock Sound Buffer Failed'#10);
        S_Restart;
        exit;
      end;

      inc(reps);
      if reps > 10000 then
      begin
        Con_Printf('S_TransferPaintBuffer: DS: couldn''t restore buffer'#10);
        S_Restart;
        exit;
      end;
    end;
  end
  else
  begin
    pbuf := shm.buffer;
  end;

  if shm.samplebits = 16 then
  begin
    out16 := PShortArray(pbuf);
    while count <> 0 do
    begin
      val := (p^ * snd_vol) div 256;
      inc(p, step);
      if val > $7FFF then
        val := $7FFF
      else if val < short($8000) then
        val := short($8000);
      out16[out_idx] := val;
      out_idx := (out_idx + 1) and out_mask;
      dec(count);
    end;
  end
  else if shm.samplebits = 8 then
  begin
    out8 := PByteArray(pbuf);
    while count <> 0 do
    begin
      val := (p^ * snd_vol) div 256;
      inc(p, step);
      if val > $7FFF then
        val := $7FFF
      else if val < short($8000) then
        val := short($8000);
      out8[out_idx] := (val div 256) + 128;
      out_idx := (out_idx + 1) and out_mask;
      dec(count);
    end;
  end;

  if pDSBuf <> nil then
  begin
//    il = paintedtime;
//    ir = endtime - paintedtime;

//    ir += il;

    pDSBuf.Unlock(pbuf, dwSize, nil, 0);
    pDSBuf.GetCurrentPosition(dwNewpos, dwWrite);

//    if ((dwNewpos >= il) && (dwNewpos <= ir))
//      Con_Printf("%d-%d p %d c\n", il, ir, dwNewpos);
  end;
end;


(*
===============================================================================

CHANNEL MIXING

===============================================================================
*)

procedure SND_PaintChannelFrom8(ch: Pchannel_t; sc: Psfxcache_t; count: integer);
var
  data: integer;
  lscale, rscale: PIntegerArray;
  sfx: PByteArray;
  i: integer;
begin
  if ch.leftvol > 255 then
    ch.leftvol := 255;
  if ch.rightvol > 255 then
    ch.rightvol := 255;

  lscale := @snd_scaletable[ch.leftvol div 8, 0];
  rscale := @snd_scaletable[ch.rightvol div 8, 0];
  sfx := @sc.data[ch.pos];

  for i := 0 to count - 1 do
  begin
    data := signed_char(sfx[i]);
    paintbuffer[i].left := paintbuffer[i].left + lscale[data];
    paintbuffer[i].right := paintbuffer[i].right + rscale[data];
  end;

  ch.pos := ch.pos + count;
end;



procedure SND_PaintChannelFrom16(ch: Pchannel_t; sc: Psfxcache_t; count: integer);
var
  data: integer;
  left, right: integer;
  leftvol, rightvol: integer;
  sfx: PShortArray;
  i: integer;
begin
  leftvol := ch.leftvol;
  rightvol := ch.rightvol;
  sfx := @PShortArray(@sc.data)[ch.pos];

  for i := 0 to count - 1 do
  begin
    data := sfx[i];
    left := (data * leftvol) div 256;
    right := (data * rightvol) div 256;
    paintbuffer[i].left := paintbuffer[i].left + left;
    paintbuffer[i].right := paintbuffer[i].right + right;
  end;

  ch.pos := ch.pos + count;
end;


procedure S_PaintChannels(endtime: integer);
var
  i: integer;
  _end: integer;
  ch: Pchannel_t;
  sc: Psfxcache_t;
  ltime, count: integer;
begin
  while paintedtime < endtime do
  begin
  // if paintbuffer is smaller than DMA buffer
    _end := endtime;
    if endtime - paintedtime > PAINTBUFFER_SIZE then
      _end := paintedtime + PAINTBUFFER_SIZE;

  // clear the paint buffer
    ZeroMemory(@paintbuffer[0], (_end - paintedtime) * SizeOf(portable_samplepair_t));

  // paint in the channels.
    for i := 0 to total_channels - 1 do
    begin
      ch := @channels[i];
      if ch.sfx = nil then
        continue;
      if (ch.leftvol = 0) and (ch.rightvol = 0) then
        continue;
      sc := S_LoadSound(ch.sfx);
      if sc = nil then
        continue;

      ltime := paintedtime;

      while ltime < _end do
      begin // paint up to end
        if ch._end < _end then
          count := ch._end - ltime
        else
          count := _end - ltime;

        if count > 0 then
        begin
          if sc.width = 1 then
            SND_PaintChannelFrom8(ch, sc, count)
          else
            SND_PaintChannelFrom16(ch, sc, count);

          inc(ltime, count);
        end;

      // if at end of loop, restart
        if ltime >= ch._end then
        begin
          if sc.loopstart >= 0 then
          begin
            ch.pos := sc.loopstart;
            ch._end := ltime + sc.length - ch.pos;
          end
          else
          begin // channel just stopped
            ch.sfx := nil;
            break;
          end;
        end;
      end;

    end;

  // transfer out according to DMA format
    S_TransferPaintBuffer(_end);
    paintedtime := _end;
  end;
end;

procedure SND_InitScaletable;
var
  i, j: integer;
begin
  for i := 0 to 31 do
    for j := 0 to 255 do
      snd_scaletable[i][j] := signed_char(j) * i * 8;
end;


end.

