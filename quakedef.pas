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

unit quakedef;

interface

uses
  q_vector;

const
  __DATE__ = 'Nov 03 2005';
  __TIME__ = '12:00';

const
  VERSION = 1.09;
  GLQUAKE_VERSION = 1.0;
  D3DQUAKE_VERSION = 0.01;
  WINQUAKE_VERSION = 0.996;

  GAMENAME = 'id1'; // directory to look in by default

  UNALIGNED_OK = 0;

// !!! if this is changed, it must be changed in d_ifacea.h too !!!
  CACHE_SIZE = 32; // used to align key data structures

  MINIMUM_MEMORY = $550000;
  MINIMUM_MEMORY_LEVELPAK = MINIMUM_MEMORY + $100000;

  MAX_NUM_ARGVS = 50;

type
  PArgvArray = ^TArgvArray;
  TArgvArray = array[0..MAX_NUM_ARGVS] of PChar;

const
  PITCH = 0;  // up / down
  YAW = 1;    // left / right
  ROLL = 2;   // fall over

  MAX_QPATH = 64;   // max length of a quake game pathname
  MAX_OSPATH = 256; // max length of a filesystem pathname // JVAL changed from 128

  ON_EPSILON = 0.1; // point on plane side epsilon

  MAX_MSGLEN = 8000;    // max length of a reliable message
  MAX_DATAGRAM = 1024;  // max length of unreliable message

//
// per-level limits
//
  MAX_EDICTS = 600; // FIXME: ouch! ouch! ouch!
  MAX_LIGHTSTYLES = 64;
  MAX_MODELS = 512; // these are sent over the net as bytes
  MAX_SOUNDS = 256; // so they cannot be blindly increased

  SAVEGAME_COMMENT_LENGTH = 39;

  MAX_STYLESTRING = 64;

//
// stats are integers communicated to the client by the server
//
  MAX_CL_STATS = 32;
  STAT_HEALTH = 0;
  STAT_FRAGS = 1;
  STAT_WEAPON = 2;
  STAT_AMMO = 3;
  STAT_ARMOR = 4;
  STAT_WEAPONFRAME = 5;
  STAT_SHELLS = 6;
  STAT_NAILS = 7;
  STAT_ROCKETS = 8;
  STAT_CELLS = 9;
  STAT_ACTIVEWEAPON = 10;
  STAT_TOTALSECRETS = 11;
  STAT_TOTALMONSTERS = 12;
  STAT_SECRETS = 13; // bumped on client side by svc_foundsecret
  STAT_MONSTERS = 14; // bumped by svc_killedmonster

// stock defines

  IT_SHOTGUN = 1;
  IT_SUPER_SHOTGUN = 2;
  IT_NAILGUN = 4;
  IT_SUPER_NAILGUN = 8;
  IT_GRENADE_LAUNCHER = 6;
  IT_ROCKET_LAUNCHER = 32;
  IT_LIGHTNING = 64;
  IT_SUPER_LIGHTNING = 128;
  IT_SHELLS = 256;
  IT_NAILS = 512;
  IT_ROCKETS = 1024;
  IT_CELLS = 2048;
  IT_AXE = 4096;
  IT_ARMOR1 = 8192;
  IT_ARMOR2 = 16384;
  IT_ARMOR3 = 32768;
  IT_SUPERHEALTH = 65536;
  IT_KEY1 = 131072;
  IT_KEY2 = 262144;
  IT_INVISIBILITY = 524288;
  IT_INVULNERABILITY = 1048576;
  IT_SUIT = 2097152;
  IT_QUAD = 4194304;
  IT_SIGIL1 = (1 shl 28);
  IT_SIGIL2 = (1 shl 29);
  IT_SIGIL3 = (1 shl 30);
  IT_SIGIL4 = (1 shl 31);

//===========================================
//rogue changed and added defines

  RIT_SHELLS = 128;
  RIT_NAILS = 256;
  RIT_ROCKETS = 512;
  RIT_CELLS = 1024;
  RIT_AXE = 2048;
  RIT_LAVA_NAILGUN = 4096;
  RIT_LAVA_SUPER_NAILGUN = 8192;
  RIT_MULTI_GRENADE = 16384;
  RIT_MULTI_ROCKET = 32768;
  RIT_PLASMA_GUN = 65536;
  RIT_ARMOR1 = 8388608;
  RIT_ARMOR2 = 16777216;
  RIT_ARMOR3 = 33554432;
  RIT_LAVA_NAILS = 67108864;
  RIT_PLASMA_AMMO = 134217728;
  RIT_MULTI_ROCKETS = 268435456;
  RIT_SHIELD = 536870912;
  RIT_ANTIGRAV = 1073741824;
  RIT_SUPERHEALTH = 2147483648;

//MED 01/04/97 added hipnotic defines
//===========================================
//hipnotic added defines
  HIT_PROXIMITY_GUN_BIT = 16;
  HIT_MJOLNIR_BIT = 7;
  HIT_LASER_CANNON_BIT = 23;
  HIT_PROXIMITY_GUN = (1 shl HIT_PROXIMITY_GUN_BIT);
  HIT_MJOLNIR = (1 shl HIT_MJOLNIR_BIT);
  HIT_LASER_CANNON = (1 shl HIT_LASER_CANNON_BIT);
  HIT_WETSUIT = (1 shl (23 + 2));
  HIT_EMPATHY_SHIELDS = (1 shl (23 + 3));

//===========================================

  MAX_SCOREBOARD = 32;
  MAX_SCOREBOARDNAME = 32;

  SOUND_CHANNELS = 8;

type
  entity_state_t = record
    origin: TVector3f;
    angles: TVector3f;
    modelindex: integer;
    frame: integer;
    colormap: integer;
    skin: integer;
    effects: integer;
  end;
  Pentity_state_t = ^entity_state_t;

//=============================================================================

// the host system specifies the base of the directory tree, the
// command line parms passed to the program, and the amount of memory
// available for the program to use

type
  quakeparms_t = record
    basedir: PChar;
    cachedir: PChar; // for development over ISDN lines
    argc: integer;
    argv: PArgvArray;
    membase: pointer;
    memsize: longword;
  end;
  Pquakeparms_t = ^quakeparms_t;

//=============================================================================

type
  synctype_t = (ST_SYNC, ST_RAND);

implementation

end.

