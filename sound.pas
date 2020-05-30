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

unit sound;

interface

uses
  q_delphi,
  q_vector,
  quakedef,
  zone;

const
  DEFAULT_SOUND_PACKET_VOLUME = 255;
  DEFAULT_SOUND_PACKET_ATTENUATION = 1.0;

// !!! if this is changed, it much be changed in asm_i386.h too !!!
type
  portable_samplepair_t = record
    left: integer;
    right: integer;
  end;

type
  Psfx_t = ^sfx_t;
  sfx_t = record
    name: array[0..MAX_QPATH - 1] of char;
    cache: cache_user_t;
  end;
  sfx_tArray = array[0..$FFFF] of sfx_t;
  Psfx_tArray = ^sfx_tArray;


// !!! if this is changed, it much be changed in asm_i386.h too !!!
type
  Psfxcache_t = ^sfxcache_t;
  sfxcache_t = record
    length: integer;
    loopstart: integer;
    speed: integer;
    width: integer;
    stereo: integer;
    data: array[0..0] of byte; //array[0..0] of byte;  // variable sized // vj mayby PByte ?
  end;

type
  Pdma_t = ^dma_t;
  dma_t = record
    gamealive: qboolean;
    soundalive: qboolean;
    splitbuffer: qboolean;
    channels: integer;
    samples: integer; // mono samples in buffer
    submission_chunk: integer; // don't mix less than this #
    samplepos: integer; // in mono samples
    samplebits: integer;
    speed: integer;
    buffer: PByteArray;
  end;

// !!! if this is changed, it much be changed in asm_i386.h too !!!
type
  Pchannel_t = ^channel_t;
  channel_t = record
    sfx: Psfx_t; // sfx number
    leftvol: integer; // 0-255 volume
    rightvol: integer; // 0-255 volume
    _end: integer; // end time in global paintsamples
    pos: integer; // sample position in sfx
    looping: integer; // where to loop, -1 = no looping
    entnum: integer; // to allow overriding a specific sound
    entchannel: integer; //
    origin: TVector3f; // origin of sound effect
    dist_mult: Single; // distance multiplier (attenuation/clipK)
    master_vol: integer; // 0-255 master volume
  end;

type
  wavinfo_t = record
    rate: integer;
    width: integer;
    channels: integer;
    loopstart: integer;
    samples: integer;
    dataofs: integer; // chunk starts this many bytes from file start
  end;


// ====================================================================
// User-setable variables
// ====================================================================

const
  MAX_CHANNELS = 128;
  MAX_DYNAMIC_CHANNELS = 8;


implementation

end.
