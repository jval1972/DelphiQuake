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

unit snd_dma_h;

interface

uses
  sound,
  cvar;

// ====================================================================
var
  snd_blocked: integer = 0;

// pointer should go away
var
  shm: Pdma_t = nil; // JVAL was volatile
  sn: dma_t; // JVAL was volatile

var
  bgmvolume: cvar_t = (name: 'bgmvolume'; text: '1'; archive: true);
  volume: cvar_t = (name: 'volume'; text: '0.7'; archive: true);

  nosound: cvar_t = (name: 'nosound'; text: '0');
  precache: cvar_t = (name: 'precache'; text: '1');
  loadas8bit: cvar_t = (name: 'loadas8bit'; text: '0');
  bgmbuffer: cvar_t = (name: 'bgmbuffer'; text: '4096');
  ambient_level: cvar_t = (name: 'ambient_level'; text: '0.3');
  ambient_fade: cvar_t = (name: 'ambient_fade'; text: '100');
  snd_noextraupdate: cvar_t = (name: 'snd_noextraupdate'; text: '0');
  snd_show: cvar_t = (name: 'snd_show'; text: '0');
  _snd_mixahead: cvar_t = (name: '_snd_mixahead'; text: '0.1'; archive: true);


// =======================================================================
// Internal sound data & structures
// =======================================================================

var
  soundtime: integer; // sample PAIRS
  paintedtime: integer; // sample PAIRS

var
  channels: array[0..MAX_CHANNELS - 1] of channel_t;
  total_channels: integer;

implementation

end.


