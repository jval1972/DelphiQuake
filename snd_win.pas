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

unit snd_win;

interface

function SNDDMA_Init: integer;
function SNDDMA_GetDMAPos: integer;
procedure SNDDMA_Submit;
procedure SNDDMA_Shutdown;

procedure S_BlockSound;
procedure S_UnblockSound;

implementation

uses
  q_delphi,
  Windows,
  MMSystem,
  DirectX,
  sound,
  gl_vidnt,
  snd_dma_h,
  console,
  common,
  snd_win_h;

// 64K is > 1 second at 16-bit, 22050 Hz
const
  WAV_BUFFERS = 64;
  WAV_MASK = $3F;
  WAV_BUFFER_SIZE = $0400;
  SECONDARY_BUFFER_SIZE = $10000;


type
  sndinitstat_t = (SIS_SUCCESS, SIS_FAILURE, SIS_NOTAVAIL);

var
  wavonly: qboolean;
  dsound_init: qboolean;
  wav_init: qboolean;
  snd_firsttime: qboolean = true;
  snd_isdirect: qboolean;
  snd_iswave: qboolean;
  primary_format_set: qboolean;

var
  sample16: integer;
  snd_sent, snd_completed: integer;


(*
 * Global variables. Must be visible to window-procedure function
 *  so it can unlock and free the data block after it has been played.
 *)

var
  hData: THandle;
  lpData: pointer;

var
  hWaveHdr: HGLOBAL;
  lpWaveHdr: PWaveHdr;

  hWavOut: HWAVEOUT;

  mmstarttime: MMTIME;


(*
==================
S_BlockSound
==================
*)

procedure S_BlockSound;
begin

// DirectSound takes care of blocking itself
  if snd_iswave then
  begin
    inc(snd_blocked);

    if snd_blocked = 1 then
    begin
      waveOutReset(hWavOut);
    end;
  end;
end;


(*
==================
S_UnblockSound
==================
*)

procedure S_UnblockSound;
begin

// DirectSound takes care of blocking itself
  if snd_iswave then
  begin
    dec(snd_blocked);
  end;
end;


(*
==================
FreeSound
==================
*)

procedure FreeSound;
var
  i: integer;
  hdr: PWaveHdr;
begin
  if pDSBuf <> nil then
    pDSBuf.Stop;

  if pDS <> nil then
    pDS.SetCooperativeLevel(mainwindow, DSSCL_NORMAL);

  if hWavOut <> 0 then
  begin
    waveOutReset(hWavOut);

    if lpWaveHdr <> nil then
    begin
      hdr := lpWaveHdr;
      for i := 0 to WAV_BUFFERS - 1 do
      begin
        waveOutUnprepareHeader(hWavOut, hdr, SizeOf(WAVEHDR));
        inc(hdr);
      end;
    end;

    waveOutClose(hWavOut);

    if hWaveHdr <> 0 then
    begin
      GlobalUnlock(hWaveHdr);
      GlobalFree(hWaveHdr);
    end;

    if hData <> 0 then
    begin
      GlobalUnlock(hData);
      GlobalFree(hData);
    end;

  end;

  hWavOut := 0;
  hData := 0;
  hWaveHdr := 0;
  lpData := nil;
  lpWaveHdr := nil;
  dsound_init := false;
  wav_init := false;
end;


(*
==================
SNDDMA_InitDirect

Direct-Sound support
==================
*)

function SNDDMA_InitDirect: sndinitstat_t;
var
  dsbuf: DSBUFFERDESC;
  bcaps: DSBCAPS;
  dwSize, dwWrite: DWORD;
  caps: DSCAPS;
  format, pformat: tWAVEFORMATEX;
  ret: HRESULT;
  reps: integer;

  function get_ds_ret1: HRESULT;
  begin
    ret := DirectSoundCreate(nil, pDS, nil);
    result := ret;
  end;

  function get_ds_ret2: HRESULT;
  var
    foo: DWORD;
    pfoo: pointer;
  begin
    pfoo := nil;
    foo := 0;
    ret := pDSBuf.Lock(0, gSndBufSize, lpData, dwSize, pfoo, foo, 0);
    result := ret;
  end;

begin
  ZeroMemory(@sn, SizeOf(sn));

  shm := @sn;

  shm.channels := 2;
  shm.samplebits := 16;
  shm.speed := 44100; //11025;

  ZeroMemory(@format, SizeOf(format));
  format.wFormatTag := WAVE_FORMAT_PCM;
  format.nChannels := shm.channels;
  format.wBitsPerSample := shm.samplebits;
  format.nSamplesPerSec := shm.speed;
  format.nBlockAlign := format.nChannels * format.wBitsPerSample div 8;
  format.cbSize := 0;
  format.nAvgBytesPerSec := format.nSamplesPerSec * format.nBlockAlign;

  while get_ds_ret1 <> DS_OK do
  begin
    if ret <> DSERR_ALLOCATED then
    begin
      Con_SafePrintf('DirectSound create failed'#10);
      result := SIS_FAILURE;
      exit;
    end;

    if MessageBox(0,
      'The sound hardware is in use by another app.'#10#10'Select Retry to try to start sound again or Cancel to run Quake with no sound.',
      'Sound not available',
      MB_RETRYCANCEL or MB_SETFOREGROUND or MB_ICONEXCLAMATION) <> IDRETRY then
    begin
      Con_SafePrintf('DirectSoundCreate failure'#10'  hardware already in use'#10);
      result := SIS_NOTAVAIL;
      exit;
    end;
  end;

  caps.dwSize := SizeOf(caps);

  if pDS.GetCaps(caps) <> DS_OK then
  begin
    Con_SafePrintf('Couldn''t get DS caps'#10);
  end;

  if caps.dwFlags and DSCAPS_EMULDRIVER <> 0 then
  begin
    Con_SafePrintf('No DirectSound driver installed'#10);
    FreeSound;
    result := SIS_FAILURE;
    exit;
  end;

  if pDS.SetCooperativeLevel(mainwindow, DSSCL_EXCLUSIVE) <> DS_OK then
  begin
    Con_SafePrintf('Set coop level failed'#10);
    FreeSound;
    result := SIS_FAILURE;
    exit;
  end;

// get access to the primary buffer, if possible, so we can set the
// sound hardware format
  ZeroMemory(@dsbuf, SizeOf(dsbuf));
  dsbuf.dwSize := SizeOf(DSBUFFERDESC);
  dsbuf.dwFlags := DSBCAPS_PRIMARYBUFFER;
  dsbuf.dwBufferBytes := 0;
  dsbuf.lpwfxFormat := nil;

  ZeroMemory(@bcaps, SizeOf(bcaps));
  bcaps.dwSize := SizeOf(bcaps);
  primary_format_set := false;

  if COM_CheckParm('-snoforceformat') = 0 then
  begin
    if pDS.CreateSoundBuffer(dsbuf, pDSPBuf, nil) = DS_OK then
    begin
      pformat := format;

      if pDSPBuf.SetFormat(pformat) <> DS_OK then
      begin
        if snd_firsttime then
          Con_SafePrintf('Set primary sound buffer format: no'#10);
      end
      else
      begin
        if snd_firsttime then
          Con_SafePrintf('Set primary sound buffer format: yes'#10);

        primary_format_set := true;
      end;
    end;
  end;

  if not primary_format_set or (COM_CheckParm('-primarysound') = 0) then
  begin
  // create the secondary buffer we'll actually work with
    ZeroMemory(@dsbuf, SizeOf(dsbuf));
    dsbuf.dwSize := SizeOf(DSBUFFERDESC);
    dsbuf.dwFlags := DSBCAPS_CTRLFREQUENCY or DSBCAPS_LOCSOFTWARE;
    dsbuf.dwBufferBytes := SECONDARY_BUFFER_SIZE;
    dsbuf.lpwfxFormat := @format;

    ZeroMemory(@bcaps, SizeOf(bcaps));
    bcaps.dwSize := SizeOf(bcaps);

    if pDS.CreateSoundBuffer(dsbuf, pDSBuf, nil) <> DS_OK then
    begin
      Con_SafePrintf('DS:CreateSoundBuffer Failed');
      FreeSound;
      result := SIS_FAILURE;
      exit;
    end;

    shm.channels := format.nChannels;
    shm.samplebits := format.wBitsPerSample;
    shm.speed := format.nSamplesPerSec;

    if pDSBuf.GetCaps(bcaps) <> DS_OK then
    begin
      Con_SafePrintf('DS:GetCaps failed'#10);
      FreeSound;
      result := SIS_FAILURE;
      exit;
    end;

    if snd_firsttime then
      Con_SafePrintf('Using secondary sound buffer'#10);
  end
  else
  begin
    if pDS.SetCooperativeLevel(mainwindow, DSSCL_WRITEPRIMARY) <> DS_OK then
    begin
      Con_SafePrintf('Set coop level failed'#10);
      FreeSound;
      result := SIS_FAILURE;
      exit;
    end;

    if pDSPBuf.GetCaps(bcaps) <> DS_OK then
    begin
      Con_Printf('DS:GetCaps failed'#10);
      result := SIS_FAILURE;
      exit;
    end;

    pDSBuf := pDSPBuf;
    Con_SafePrintf('Using primary sound buffer'#10);
  end;

  // Make sure mixer is active
  pDSBuf.Play(0, 0, DSBPLAY_LOOPING);

  if snd_firsttime then
    Con_SafePrintf('   %d channel(s)'#10'   %d bits/sample'#10'   %d bytes/sec'#10,
      [shm.channels, shm.samplebits, shm.speed]);

  gSndBufSize := bcaps.dwBufferBytes;

// initialize the buffer
  reps := 0;

  while get_ds_ret2 <> DS_OK do
  begin
    if ret <> DSERR_BUFFERLOST then
    begin
      Con_SafePrintf('SNDDMA_InitDirect: DS::Lock Sound Buffer Failed'#10);
      FreeSound;
      result := SIS_FAILURE;
      exit;
    end;

    inc(reps);
    if reps > 10000 then
    begin
      Con_SafePrintf('SNDDMA_InitDirect: DS: couldn''t restore buffer'#10);
      FreeSound;
      result := SIS_FAILURE;
      exit;
    end;

  end;

  memset(lpData, 0, dwSize);
//    lpData[4] = lpData[5] = 0x7f;  // force a pop for debugging

  pDSBuf.Unlock(lpData, dwSize, nil, 0);

  (* we don't want anyone to access the buffer directly w/o locking it first. *)
  lpData := nil;

  pDSBuf.Stop;
  pDSBuf.GetCurrentPosition(mmstarttime.sample, dwWrite);
  pDSBuf.Play(0, 0, DSBPLAY_LOOPING);

  shm.soundalive := true;
  shm.splitbuffer := false;
  shm.samples := gSndBufSize div (shm.samplebits div 8);
  shm.samplepos := 0;
  shm.submission_chunk := 1;
  shm.buffer := lpData;
  sample16 := (shm.samplebits div 8) - 1;

  dsound_init := true;

  result := SIS_SUCCESS;
{$O+}
end;


(*
==================
SNDDM_InitWav

Crappy windows multimedia base
==================
*)

function SNDDMA_InitWav: qboolean;
var
  format: tWAVEFORMATEX;
  i: integer;
  hr: HRESULT;
  hdr: PWaveHdr;

  function get_w_ret: HRESULT;
  begin
    hr := waveOutOpen(@hWavOut, WAVE_MAPPER,
      @format,
      0, 0, CALLBACK_NULL);
    result := hr;
  end;

begin
  snd_sent := 0;
  snd_completed := 0;

  shm := @sn;

  shm.channels := 2;
  shm.samplebits := 16;
  shm.speed := 44100; // 11025;

  ZeroMemory(@format, SizeOf(format));
  format.wFormatTag := WAVE_FORMAT_PCM;
  format.nChannels := shm.channels;
  format.wBitsPerSample := shm.samplebits;
  format.nSamplesPerSec := shm.speed;
  format.nBlockAlign := format.nChannels * format.wBitsPerSample div 8;
  format.cbSize := 0;
  format.nAvgBytesPerSec := format.nSamplesPerSec * format.nBlockAlign;

  (* Open a waveform device for output using window callback. *)
  while get_w_ret <> MMSYSERR_NOERROR do
  begin
    if hr <> MMSYSERR_ALLOCATED then
    begin
      Con_SafePrintf('waveOutOpen failed'#10);
      result := false;
      exit;
    end;

    if MessageBox(0,
      'The sound hardware is in use by another app.'#10#10'Select Retry to try to start sound again or Cancel to run Quake with no sound.',
      'Sound not available',
      MB_RETRYCANCEL or MB_SETFOREGROUND or MB_ICONEXCLAMATION) <> IDRETRY then
    begin
      Con_SafePrintf('waveOutOpen failure;'#10'  hardware already in use'#10);
      result := false;
      exit;
    end;
  end;

  (*
   * Allocate and lock memory for the waveform data. The memory
   * for waveform data must be globally allocated with
   * GMEM_MOVEABLE and GMEM_SHARE flags.

  *)
  gSndBufSize := WAV_BUFFERS * WAV_BUFFER_SIZE;
  hData := GlobalAlloc(GMEM_MOVEABLE or GMEM_SHARE, gSndBufSize);
  if hData = 0 then
  begin
    Con_SafePrintf('Sound: Out of memory.'#10);
    FreeSound;
    result := false;
    exit;
  end;
  lpData := GlobalLock(hData);
  if lpData = nil then
  begin
    Con_SafePrintf('Sound: Failed to lock.'#10);
    FreeSound;
    result := false;
    exit;
  end;
  memset(lpData, 0, gSndBufSize);

  (*
   * Allocate and lock memory for the header. This memory must
   * also be globally allocated with GMEM_MOVEABLE and
   * GMEM_SHARE flags.
   *)
  hWaveHdr := GlobalAlloc(GMEM_MOVEABLE or GMEM_SHARE,
    SizeOf(WAVEHDR) * WAV_BUFFERS);

  if hWaveHdr = 0 then
  begin
    Con_SafePrintf('Sound: Failed to Alloc header.'#10);
    FreeSound;
    result := false;
    exit;
  end;

  lpWaveHdr := PWaveHdr(GlobalLock(hWaveHdr));

  if lpWaveHdr = nil then
  begin
    Con_SafePrintf('Sound: Failed to lock header.'#10);
    FreeSound;
    result := false;
    exit;
  end;

  memset(lpWaveHdr, 0, SizeOf(WAVEHDR) * WAV_BUFFERS);

  (* After allocation, set up and prepare headers. *)
  hdr := lpWaveHdr;
  for i := 0 to WAV_BUFFERS - 1 do
  begin
    hdr.dwBufferLength := WAV_BUFFER_SIZE;
    hdr.lpData := C_PChar(lpData, i * WAV_BUFFER_SIZE);

    if waveOutPrepareHeader(hWavOut, hdr, SizeOf(WAVEHDR)) <> // JVAL ?
      MMSYSERR_NOERROR then
    begin
      Con_SafePrintf('Sound: failed to prepare wave headers'#10);
      FreeSound;
      result := false;
      exit;
    end;
    inc(hdr);
  end;

  shm.soundalive := true;
  shm.splitbuffer := false;
  shm.samples := gSndBufSize div (shm.samplebits div 8);
  shm.samplepos := 0;
  shm.submission_chunk := 1;
  shm.buffer := PByteArray(lpData);
  sample16 := (shm.samplebits div 8) - 1;

  wav_init := true;

  result := true;
end;

(*
==================
SNDDMA_Init

Try to find a sound device to mix for.
Returns false if nothing is found.
==================
*)

function SNDDMA_Init: integer;
var
  stat: sndinitstat_t;
begin
  if COM_CheckParm('-wavonly') <> 0 then
    wavonly := true;

  dsound_init := false;
  wav_init := false;

  stat := SIS_FAILURE; // assume DirectSound won't initialize

  (* Init DirectSound *)
  if not wavonly then
  begin
    if snd_firsttime or snd_isdirect then
    begin
      stat := SNDDMA_InitDirect;

      if stat = SIS_SUCCESS then
      begin
        snd_isdirect := true;

        if snd_firsttime then
          Con_SafePrintf('DirectSound initialized'#10);
      end
      else
      begin
        snd_isdirect := false;
        Con_SafePrintf('DirectSound failed to init'#10);
      end;
    end;
  end;

// if DirectSound didn't succeed in initializing, try to initialize
// waveOut sound, unless DirectSound failed because the hardware is
// already allocated (in which case the user has already chosen not
// to have sound)
  if not dsound_init and (stat <> SIS_NOTAVAIL) then
  begin
    if snd_firsttime or snd_iswave then
    begin

      snd_iswave := SNDDMA_InitWav;

      if snd_iswave then
      begin
        if snd_firsttime then
          Con_SafePrintf('Wave sound initialized'#10);
      end
      else
      begin
        Con_SafePrintf('Wave sound failed to init'#10);
      end;
    end;
  end;

  snd_firsttime := false;

  if not dsound_init and not wav_init then
  begin
    if snd_firsttime then
      Con_SafePrintf('No sound device initialized'#10);

    result := 0;
    exit;
  end;

  result := 1;
end;

(*
==============
SNDDMA_GetDMAPos

return the current sample position (in mono samples read)
inside the recirculating dma buffer, so the mixing code will know
how many sample are required to fill it up.
===============
*)

function SNDDMA_GetDMAPos: integer;
var
  mtime: MMTIME;
  s: integer;
  dwWrite: DWORD;
begin
  if dsound_init then
  begin
    mtime.wType := TIME_SAMPLES;
    pDSBuf.GetCurrentPosition(mtime.sample, dwWrite); // JVAL check
    s := mtime.sample - mmstarttime.sample;
  end
  else if wav_init then
  begin
    s := snd_sent * WAV_BUFFER_SIZE;
  end
  else
  begin
    result := 0;
    exit;
  end;

  s := s shr sample16;

  s := s and (shm.samples - 1);

  result := s;
end;

(*
==============
SNDDMA_Submit

Send sound to device if buffer isn't really the dma buffer
===============
*)

procedure SNDDMA_Submit;
var
  wResult: integer;
  hdr: PWaveHdr;
begin
  if not wav_init then
    exit;

  //
  // find which sound blocks have completed
  //
  while true do
  begin
    if snd_completed = snd_sent then
    begin
      Con_DPrintf('Sound overrun'#10);
      break;
    end;

    hdr := lpWaveHdr;
    inc(hdr, snd_completed and WAV_MASK);
    if (hdr.dwFlags and WHDR_DONE) = 0 then
      break;

    inc(snd_completed); // this buffer has been played
  end;

  //
  // submit two new sound blocks
  //
  while ((snd_sent - snd_completed) shr sample16) < 4 do
  begin
    hdr := lpWaveHdr;
    inc(hdr, snd_sent and WAV_MASK);

    inc(snd_sent);
    (*
     * Now the data block can be sent to the output device. The
     * waveOutWrite function returns immediately and waveform
     * data is sent to the output device in the background.
     *)
    wResult := waveOutWrite(hWavOut, hdr, sizeof(WAVEHDR));

    if wResult <> MMSYSERR_NOERROR then
    begin
      Con_SafePrintf('Failed to write block to device'#10);
      FreeSound;
      exit;
    end;
  end;
end;


(*
==============
SNDDMA_Shutdown

Reset the sound device for exiting
===============
*)

procedure SNDDMA_Shutdown;
begin
  FreeSound;
end;


end.

