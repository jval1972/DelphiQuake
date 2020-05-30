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

unit snd_dma;

// snd_dma.c -- main control for any streaming sound output device

interface

uses
  q_delphi,
  q_vector,
  sound;

procedure S_Play;
procedure S_PlayVol;
procedure S_SoundList;
procedure S_Update_;
procedure S_StopAllSounds(clear: qboolean);
procedure S_StopAllSoundsC; // JVAL remove ?
procedure S_ExtraUpdate;
procedure S_Shutdown;
procedure S_Startup;
function S_PrecacheSound(name: PChar): Psfx_t;
procedure S_ClearBuffer;
procedure S_LocalSound(sound: PChar);
procedure S_Update(origin, _forward, right, up: PVector3f);
procedure S_Init;
procedure S_StartSound(entnum: integer; entchannel: integer; sfx: Psfx_t; origin: PVector3f; fvol: single; attenuation: single);
procedure S_TouchSound(name: PChar);
procedure S_BeginPrecaching; // JVAL remove ?
procedure S_EndPrecaching; // JVAL remove ?
procedure S_StaticSound(sfx: Psfx_t; origin: PVector3f; vol: single; attenuation: single);
procedure S_StopSound(entnum: integer; entchannel: integer);

implementation

uses
  Windows,
  DirectX,
  bspconst,
  mathlib,
  cvar,
  console,
  snd_win,
  snd_dma_h,
  common,
  cmd,
  host_h,
  snd_mix,
  zone,
  sys_win,
  quakedef,
  snd_mem,
  cl_main_h,
  snd_win_h,
  gl_model_h,
  gl_model,
  in_win;

// =======================================================================
// Internal sound data & structures
// =======================================================================

var
  snd_ambient: qboolean = true;
  snd_initialized: qboolean = false;

var
  listener_origin: TVector3f;
  listener_forward: TVector3f;
  listener_right: TVector3f;
  listener_up: TVector3f;
  sound_nominal_clip_dist: Single = 1000.0;

const
  MAX_SFX = 512;

var
  known_sfx: Psfx_tArray; // hunk allocated [MAX_SFX]
  num_sfx: integer;

  ambient_sfx: array[0..NUM_AMBIENTS - 1] of Psfx_t;

var
  desired_speed: integer = 44100; //11025;
  desired_bits: integer = 16;

var
  sound_started: qboolean = false;

// ====================================================================
// User-setable variables
// ====================================================================


//
// Fake dma is a synchronous faking of the DMA progress used for
// isolating performance in the renderer.  The fakedma_updates is
// number of times S_Update() is called per second.
//

var
  fakedma: qboolean = false;
  fakedma_updates: integer = 15;


procedure S_AmbientOff;
begin
  snd_ambient := false;
end;


procedure S_AmbientOn;
begin
  snd_ambient := true;
end;


procedure S_SoundInfo_f;
begin
  if not sound_started or (shm = nil) then
  begin
    Con_Printf('sound system not started'#10);
    exit;
  end;

  Con_Printf('%5d stereo'#10, [shm.channels - 1]);
  Con_Printf('%5d samples'#10, [shm.samples]);
  Con_Printf('%5d samplepos'#10, [shm.samplepos]);
  Con_Printf('%5d samplebits'#10, [shm.samplebits]);
  Con_Printf('%5d submission_chunk'#10, [shm.submission_chunk]);
  Con_Printf('%5d speed'#10, [shm.speed]);
  Con_Printf('0x%x dma buffer'#10, [shm.buffer]); // JVAL check hex sprintf!
  Con_Printf('%5d total_channels'#10, [total_channels]);
end;


(*
================
S_Startup
================
*)

procedure S_Startup;
var
  rc: integer;
begin
  if not snd_initialized then
    exit;

  if not fakedma then
  begin
    rc := SNDDMA_Init;

    if rc = 0 then
    begin
      sound_started := false;
      exit;
    end;
  end;

  sound_started := true;
end;


(*
================
S_Init
================
*)

procedure S_Init;
begin

  Con_Printf(#10'Sound Initialization'#10);

  if COM_CheckParm('-nosound') <> 0 then
    exit;

  if COM_CheckParm('-simsound') <> 0 then
    fakedma := true;

  Cmd_AddCommand('play', S_Play);
  Cmd_AddCommand('playvol', S_PlayVol);
  Cmd_AddCommand('stopsound', S_StopAllSoundsC);
  Cmd_AddCommand('soundlist', S_SoundList);
  Cmd_AddCommand('soundinfo', S_SoundInfo_f);

  Cvar_RegisterVariable(@nosound);
  Cvar_RegisterVariable(@volume);
  Cvar_RegisterVariable(@precache);
  Cvar_RegisterVariable(@loadas8bit);
  Cvar_RegisterVariable(@bgmvolume);
  Cvar_RegisterVariable(@bgmbuffer);
  Cvar_RegisterVariable(@ambient_level);
  Cvar_RegisterVariable(@ambient_fade);
  Cvar_RegisterVariable(@snd_noextraupdate);
  Cvar_RegisterVariable(@snd_show);
  Cvar_RegisterVariable(@_snd_mixahead);

  if host_parms.memsize < $800000 then
  begin
    Cvar_SetValue('loadas8bit', 1);
    Con_Printf('loading all sounds as 8bit'#10);
  end;



  snd_initialized := true;

  S_Startup;

  SND_InitScaletable;

  known_sfx := Hunk_AllocName(MAX_SFX * SizeOf(sfx_t), 'sfx_t');
  num_sfx := 0;

// create a piece of DMA memory

  if fakedma then
  begin
    shm := Hunk_AllocName(SizeOf(shm^), 'shm');
    shm.splitbuffer := false;
    shm.samplebits := 16;
    shm.speed := 22050;
    shm.channels := 2;
    shm.samples := 32768;
    shm.samplepos := 0;
    shm.soundalive := true;
    shm.gamealive := true;
    shm.submission_chunk := 1;
    shm.buffer := Hunk_AllocName(1 shl 16, 'shmbuf');
  end;

  Con_Printf('Sound sampling rate: %d'#10, [shm.speed]);

  // provides a tick sound until washed clean

//  if boolval(shm.buffer) then
//    shm.buffer[4] := $7f; shm.buffer[5] := $7f;  // force a pop for debugging

  ambient_sfx[AMBIENT_WATER] := S_PrecacheSound('ambience/water1.wav');
  ambient_sfx[AMBIENT_SKY] := S_PrecacheSound('ambience/wind2.wav');

  S_StopAllSounds(true);
end;


// =======================================================================
// Shutdown sound engine
// =======================================================================

procedure S_Shutdown;
begin

  if not sound_started then
    exit;

  if shm <> nil then
    shm.gamealive := false;

  shm := nil;
  sound_started := false;

  if not fakedma then
    SNDDMA_Shutdown;
end;


// =======================================================================
// Load a sound
// =======================================================================

(*
==================
S_FindName

==================
*)

function S_FindName(name: PChar): Psfx_t;
var
  i: integer;
begin
  if name = nil then
    Sys_Error('S_FindName: NULL');

  if Q_strlen(name) >= MAX_QPATH then
    Sys_Error('Sound name too long: %s', [name]);

// see if already loaded
  for i := 0 to num_sfx - 1 do
    if Q_strcmp(known_sfx[i].name, name) = 0 then
    begin
      result := @known_sfx[i];
      exit;
    end;

  if num_sfx = MAX_SFX then
    Sys_Error('S_FindName: out of sfx_t');

  result := @known_sfx[num_sfx];
  strcpy(result.name, name);

  inc(num_sfx);
end;


(*
==================
S_TouchSound

==================
*)

procedure S_TouchSound(name: PChar);
var
  sfx: Psfx_t;
begin
  if not sound_started then
    exit;

  sfx := S_FindName(name);
  Cache_Check(@sfx.cache);
end;

(*
==================
S_PrecacheSound

==================
*)

function S_PrecacheSound(name: PChar): Psfx_t;
begin
  if not sound_started or (nosound.value <> 0) then
  begin
    result := nil;
    exit;
  end;

  result := S_FindName(name);

// cache it in
  if precache.value <> 0 then
    S_LoadSound(result);
end;


//=============================================================================

(*
=================
SND_PickChannel
=================
*)

function SND_PickChannel(entnum: integer; entchannel: integer): Pchannel_t;
var
  ch_idx: integer;
  first_to_die: integer;
  life_left: integer;
begin
// Check for replacement sound, or find the best one to replace
  first_to_die := -1;
  life_left := $7FFFFFFF;

  ch_idx := NUM_AMBIENTS;
  while ch_idx < NUM_AMBIENTS + MAX_DYNAMIC_CHANNELS do
  begin
    if (entchannel <> 0) and // channel 0 never overrides
      (channels[ch_idx].entnum = entnum) and
      ((channels[ch_idx].entchannel = entchannel) or (entchannel = -1)) then
    begin // allways override sound from same entity
      first_to_die := ch_idx;
      break;
    end;

    // don't let monster sounds override player sounds
    if (channels[ch_idx].entnum = cl.viewentity) and (entnum <> cl.viewentity) and boolval(channels[ch_idx].sfx) then
    begin
      inc(ch_idx);
      continue;
    end;

    if channels[ch_idx]._end - paintedtime < life_left then
    begin
      life_left := channels[ch_idx]._end - paintedtime;
      first_to_die := ch_idx;
    end;
    inc(ch_idx);
  end;

  if first_to_die = -1 then
  begin
    result := nil;
    exit;
  end;

  if boolval(channels[first_to_die].sfx) then
    channels[first_to_die].sfx := nil;

  result := @channels[first_to_die];
end;

(*
=================
SND_Spatialize
=================
*)

procedure SND_Spatialize(ch: Pchannel_t);
var
  dot: Single;
  dist: Single;
  lscale, rscale, scale: Single;
  source_vec: TVector3f;
begin
// anything coming from the view entity will allways be full volume
  if ch.entnum = cl.viewentity then
  begin
    ch.leftvol := ch.master_vol;
    ch.rightvol := ch.master_vol;
    exit;
  end;

// calculate stereo seperation and distance attenuation

  VectorSubtract(@ch.origin, @listener_origin, @source_vec);

  dist := VectorNormalize(@source_vec) * ch.dist_mult;

  dot := VectorDotProduct(@listener_right, @source_vec);

  if shm.channels = 1 then
  begin
    rscale := 1.0;
    lscale := 1.0;
  end
  else
  begin
    rscale := 1.0 + dot;
    lscale := 1.0 - dot;
  end;

// add in distance effect
  scale := (1.0 - dist) * rscale;
  ch.rightvol := intval(ch.master_vol * scale);
  if ch.rightvol < 0 then
    ch.rightvol := 0;

  scale := (1.0 - dist) * lscale;
  ch.leftvol := intval(ch.master_vol * scale);
  if ch.leftvol < 0 then
    ch.leftvol := 0;
end;


// =======================================================================
// Start a sound effect
// =======================================================================

procedure S_StartSound(entnum: integer; entchannel: integer;
  sfx: Psfx_t; origin: PVector3f; fvol: single; attenuation: single);
var
  target_chan, check: Pchannel_t;
  sc: Psfxcache_t;
  vol: integer;
  ch_idx: integer;
  skip: integer;
begin
  if not sound_started then
    exit;

  if sfx = nil then
    exit;

  if nosound.value <> 0 then
    exit;

  vol := intval(fvol * 255);

// pick a channel to play on
  target_chan := SND_PickChannel(entnum, entchannel);
  if target_chan = nil then
    exit;

// spatialize
  memset(target_chan, 0, SizeOf(target_chan^));
  VectorCopy(origin, @target_chan.origin);
  target_chan.dist_mult := attenuation / sound_nominal_clip_dist;
  target_chan.master_vol := vol;
  target_chan.entnum := entnum;
  target_chan.entchannel := entchannel;
  SND_Spatialize(target_chan);

  if (target_chan.leftvol = 0) and (target_chan.rightvol = 0) then
    exit; // not audible at all

// new channel
  sc := S_LoadSound(sfx);
  if sc = nil then
  begin
    target_chan.sfx := nil;
    exit; // couldn't load the sound's data
  end;

  target_chan.sfx := sfx;
  target_chan.pos := 0;
  target_chan._end := paintedtime + sc.length;

// if an identical sound has also been started this frame, offset the pos
// a bit to keep it from just making the first one louder
  check := @channels[NUM_AMBIENTS];
  ch_idx := NUM_AMBIENTS;
  while ch_idx < NUM_AMBIENTS + MAX_DYNAMIC_CHANNELS do
  begin
    if check <> target_chan then
    begin
      if (check.sfx = sfx) and not boolval(check.pos) then
      begin
        skip := rand mod intval(0.1 * shm.speed);
        if skip >= target_chan._end then
          skip := target_chan._end - 1;
        target_chan.pos := target_chan.pos + skip;
        target_chan._end := target_chan._end - skip;
        break;
      end;
    end;
    inc(ch_idx);
    inc(check);
  end;
end;

procedure S_StopSound(entnum: integer; entchannel: integer);
var
  i: integer;
begin
  for i := 0 to MAX_DYNAMIC_CHANNELS - 1 do
  begin
    if (channels[i].entnum = entnum) and
      (channels[i].entchannel = entchannel) then
    begin
      channels[i]._end := 0;
      channels[i].sfx := nil;
      break;
    end;
  end;
end;

procedure S_StopAllSounds(clear: qboolean);
var
  i: integer;
begin
  if not sound_started then
    exit;

  total_channels := MAX_DYNAMIC_CHANNELS + NUM_AMBIENTS; // no statics

  for i := 0 to MAX_CHANNELS - 1 do
    if boolval(channels[i].sfx) then
      channels[i].sfx := nil;

  ZeroMemory(@channels, MAX_CHANNELS * SizeOf(channel_t));

  if clear then
    S_ClearBuffer;
end;

procedure S_StopAllSoundsC;
begin
  S_StopAllSounds(true);
end;

procedure S_ClearBuffer;
var
  clear: integer;
  dwSize: DWORD;
  pData: pointer;
  reps: integer;
  ret: HRESULT;

  function get_ds_ret: HRESULT;
  var
    pfoo: pointer;
    foo: DWORD;
  begin
    pfoo := nil;
    foo := 0;
    ret := pDSBuf.Lock(0, gSndBufSize, pData, dwSize, pfoo, foo, 0);
    result := ret;
  end;

begin
  if (not sound_started) or
    (shm = nil) or
    (not boolval(shm.buffer) and (pDSBuf = nil)) then
    exit;

  if shm.samplebits = 8 then
    clear := $80
  else
    clear := 0;

  if pDSBuf <> nil then
  begin

    reps := 0;

    while get_ds_ret <> DS_OK do
    begin
      if ret <> DSERR_BUFFERLOST then
      begin
        Con_Printf('S_ClearBuffer: DS::Lock Sound Buffer Failed'#10);
        S_Shutdown;
        exit;
      end;

      inc(reps);
      if reps > 10000 then
      begin
        Con_Printf('S_ClearBuffer: DS: couldn''t restore buffer'#10);
        S_Shutdown;
        exit;
      end;
    end;

    memset(pData, clear, shm.samples * shm.samplebits div 8);

    pDSBuf.Unlock(pData, dwSize, nil, 0);

  end
  else
    memset(shm.buffer, clear, shm.samples * shm.samplebits div 8);
end;


(*
=================
S_StaticSound
=================
*)

procedure S_StaticSound(sfx: Psfx_t; origin: PVector3f; vol: single; attenuation: single);
var
  ss: Pchannel_t;
  sc: Psfxcache_t;
begin
  if sfx = nil then
    exit;

  if total_channels = MAX_CHANNELS then
  begin
    Con_Printf('total_channels = MAX_CHANNELS'#10);
    exit;
  end;

  ss := @channels[total_channels];
  inc(total_channels);

  sc := S_LoadSound(sfx);
  if sc = nil then
    exit;

  if sc.loopstart = -1 then
  begin
    Con_Printf('Sound %s not looped'#10, [sfx.name]);
    exit;
  end;

  ss.sfx := sfx;
  VectorCopy(origin, @ss.origin);
  ss.master_vol := intval(vol);
  ss.dist_mult := (attenuation / 64) / sound_nominal_clip_dist;
  ss._end := paintedtime + sc.length;

  SND_Spatialize(ss);
end;


//=============================================================================

(*
===================
S_UpdateAmbientSounds
===================
*)

procedure S_UpdateAmbientSounds;
var
  l: Pmleaf_t;
  vol: single;
  ambient_channel: integer;
  chan: Pchannel_t;
begin
  if not snd_ambient then
    exit;

// calc ambient sound levels
  if cl.worldmodel = nil then
    exit;

  l := Mod_PointInLeaf(@listener_origin, cl.worldmodel);
  if (l = nil) or (ambient_level.value = 0) then
  begin
    for ambient_channel := 0 to NUM_AMBIENTS - 1 do
      channels[ambient_channel].sfx := nil;
    exit;
  end;

  for ambient_channel := 0 to NUM_AMBIENTS - 1 do
  begin
    chan := @channels[ambient_channel];
    chan.sfx := ambient_sfx[ambient_channel];

    vol := ambient_level.value * l.ambient_sound_level[ambient_channel];
    if vol < 8 then
      vol := 0;

  // don't adjust volume too fast
    if chan.master_vol < vol then
    begin
      chan.master_vol := chan.master_vol + intval(host_frametime * ambient_fade.value);
      if chan.master_vol > vol then
        chan.master_vol := intval(vol);
    end
    else if chan.master_vol > vol then
    begin
      chan.master_vol := chan.master_vol - intval(host_frametime * ambient_fade.value);
      if chan.master_vol < vol then
        chan.master_vol := intval(vol);
    end;

    chan.rightvol := chan.master_vol;
    chan.leftvol := chan.master_vol;
  end;
end;


(*
============
S_Update

Called once each time through the main loop
============
*)

procedure S_Update(origin, _forward, right, up: PVector3f);
var
  i, j: integer;
  total: integer;
  ch: Pchannel_t;
  combine: Pchannel_t;
begin
  if not sound_started or (snd_blocked > 0) then
    exit;

  VectorCopy(origin, @listener_origin);
  VectorCopy(_forward, @listener_forward);
  VectorCopy(right, @listener_right);
  VectorCopy(up, @listener_up);

// update general area ambient sound sources
  S_UpdateAmbientSounds;

  combine := nil;

// update spatialization for static and dynamic sounds
  for i := NUM_AMBIENTS to total_channels - 1 do
  begin
    ch := @channels[i];
    if not boolval(ch.sfx) then
      continue;
    SND_Spatialize(ch); // respatialize channel
    if (ch.leftvol = 0) and (ch.rightvol = 0) then
      continue;

  // try to combine static sounds with a previous channel of the same
  // sound effect so we don't mix five torches every frame

    if i >= MAX_DYNAMIC_CHANNELS + NUM_AMBIENTS then
    begin
    // see if it can just use the last one
      if (combine <> nil) and (combine.sfx = ch.sfx) then
      begin
        combine.leftvol := combine.leftvol + ch.leftvol;
        combine.rightvol := combine.rightvol + ch.rightvol;
        ch.leftvol := 0;
        ch.rightvol := 0;
        continue;
      end;
    // search for one
      combine := @channels[MAX_DYNAMIC_CHANNELS + NUM_AMBIENTS];
      j := MAX_DYNAMIC_CHANNELS + NUM_AMBIENTS;
      while j < i do
      begin
        if combine.sfx = ch.sfx then
          break;
        inc(j);
        inc(combine);
      end;

      if j = total_channels then
        combine := nil
      else
      begin
        if combine <> ch then
        begin
          combine.leftvol := combine.leftvol + ch.leftvol;
          combine.rightvol := combine.rightvol + ch.rightvol;
          ch.leftvol := 0;
          ch.rightvol := 0;
        end;
        continue;
      end;
    end;


  end;

//
// debugging output
//
  if snd_show.value <> 0 then
  begin
    total := 0;
    ch := @channels[0];
    for i := 0 to total_channels - 1 do
    begin
      if (ch.sfx <> nil) and ((ch.leftvol <> 0) or (ch.rightvol <> 0)) then
      begin
        //Con_Printf ("%3d %3d %s\n", ch->leftvol, ch->rightvol, ch->sfx->name);
        inc(total);
      end;
      inc(ch);
    end;

    Con_Printf('----(%d)----'#10, [total]);
  end;

// mix some sound
  S_Update_;
end;

var
  buffers_GetSoundtime: integer = 0;
  oldsamplepos_GetSoundtime: integer = 0;

procedure GetSoundtime;
var
  samplepos: integer;
  fullsamples: integer;
begin
  fullsamples := shm.samples div shm.channels;

// it is possible to miscount buffers if it has wrapped twice between
// calls to S_Update.  Oh well.
  samplepos := SNDDMA_GetDMAPos;


  if samplepos < oldsamplepos_GetSoundtime then
  begin
    inc(buffers_GetSoundtime); // buffer wrapped

    if paintedtime > $40000000 then
    begin // time to chop things off to avoid 32 bit limits
      buffers_GetSoundtime := 0;
      paintedtime := fullsamples;
      S_StopAllSounds(true);
    end;
  end;
  oldsamplepos_GetSoundtime := samplepos;

  soundtime := buffers_GetSoundtime * fullsamples + samplepos div shm.channels;
end;

procedure S_ExtraUpdate;
begin
  IN_Accumulate;

  if snd_noextraupdate.value <> 0 then
    exit; // don't pollute timings
  S_Update_;
end;

procedure S_Update_;
var
  endtime: integer; // JVAL was unsigned;
  samps: integer;
  dwStatus: DWORD;
begin
  if not sound_started or (snd_blocked > 0) then
    exit;

// Updates DMA time
  GetSoundtime;

// check to make sure that we haven't overshot
  if paintedtime < soundtime then
  begin
    //Con_Printf ("S_Update_ : overflow\n");
    paintedtime := soundtime;
  end;

// mix ahead of current position
  endtime := intval(soundtime + _snd_mixahead.value * shm.speed);
  samps := (shm.samples shr (shm.channels - 1));
  if endtime - soundtime > samps then
    endtime := soundtime + samps;

// if the buffer was lost or stopped, restore it and/or restart it

  if pDSBuf <> nil then
  begin
    if pDSBuf.GetStatus(dwStatus) <> DD_OK then
      Con_Printf('Couldn''t get sound buffer status'#10);

    if dwStatus and DSBSTATUS_BUFFERLOST <> 0 then
      pDSBuf.Restore;

    if dwStatus and DSBSTATUS_PLAYING = 0 then
      pDSBuf.Play(0, 0, DSBPLAY_LOOPING);
  end;

  S_PaintChannels(endtime);

  SNDDMA_Submit;
end;

(*
===============================================================================

console functions

===============================================================================
*)

var
  hash_S_Play: integer = 345;

procedure S_Play;
var
  i: integer;
  name: array[0..255] of char;
  sfx: Psfx_t;
begin
  i := 1;
  while i < Cmd_Argc_f do
  begin
    if Q_strrchr(Cmd_Argv_f(i), '.') = nil then
    begin
      Q_strcpy(name, Cmd_Argv_f(i));
      Q_strcat(name, '.wav');
    end
    else
      Q_strcpy(name, Cmd_Argv_f(i));
    sfx := S_PrecacheSound(name);
    S_StartSound(hash_S_Play, 0, sfx, @listener_origin, 1.0, 1.0);
    inc(hash_S_Play);
    inc(i);
  end;
end;

var
  hash_S_PlayVol: integer = 543;

procedure S_PlayVol;
var
  i: integer;
  vol: single;
  name: array[0..255] of char;
  sfx: Psfx_t;
begin
  i := 1;
  while i < Cmd_Argc_f do
  begin
    if Q_strrchr(Cmd_Argv_f(i), '.') = nil then
    begin
      Q_strcpy(name, Cmd_Argv_f(i));
      Q_strcat(name, '.wav');
    end
    else
      Q_strcpy(name, Cmd_Argv_f(i));
    sfx := S_PrecacheSound(name);
    vol := Q_atof(Cmd_Argv_f(i + 1));
    S_StartSound(hash_S_PlayVol, 0, sfx, @listener_origin, vol, 1.0);
    inc(hash_S_PlayVol);
    inc(i, 2);
  end;
end;

procedure S_SoundList;
var
  i: integer;
  sfx: Psfx_t;
  sc: Psfxcache_t;
  size, total: integer;
begin
  total := 0;
  sfx := @known_sfx[0];
  for i := 0 to num_sfx - 1 do
  begin
    sc := Cache_Check(@sfx.cache);
    if sc <> nil then
    begin
      size := sc.length * sc.width * (sc.stereo + 1);
      total := total + size;
      if sc.loopstart >= 0 then
        Con_Printf('L')
      else
        Con_Printf(' ');
      Con_Printf('(%2db) %6d : %s'#10, [sc.width * 8, size, sfx.name]);
    end;
    inc(sfx);
  end;
  Con_Printf('Total resident: %d'#10, [total]);
end;


procedure S_LocalSound(sound: PChar);
var
  sfx: Psfx_t;
begin
  if nosound.value <> 0 then
    exit;
  if not sound_started then
    exit;

  sfx := S_PrecacheSound(sound);
  if sfx = nil then
    Con_Printf('S_LocalSound: can''t cache %s'#10, [sound])
  else
    S_StartSound(cl.viewentity, -1, sfx, @vec3_origin, 1, 1);
end;


procedure S_ClearPrecache; // JVAL remove ?
begin
end;

procedure S_BeginPrecaching; // JVAL remove ?
begin
end;


procedure S_EndPrecaching; // JVAL remove ?
begin
end;


end.

