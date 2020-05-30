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

unit protocol;

// protocol.h -- communications protocols

interface

const
  PROTOCOL_VERSION = 15;

// if the high bit of the servercmd is set, the low bits are fast update flags:
  U_MOREBITS = (1 shl 0);
  U_ORIGIN1 = (1 shl 1);
  U_ORIGIN2 = (1 shl 2);
  U_ORIGIN3 = (1 shl 3);
  U_ANGLE2 = (1 shl 4);
  U_NOLERP = (1 shl 5); // don't interpolate movement
  U_FRAME = (1 shl 6);
  U_SIGNAL = (1 shl 7); // just differentiates from other updates

// svc_update can pass all of the fast update bits, plus more
  U_ANGLE1 = (1 shl 8);
  U_ANGLE3 = (1 shl 9);
  U_MODEL = (1 shl 10);
  U_COLORMAP = (1 shl 11);
  U_SKIN = (1 shl 12);
  U_EFFECTS = (1 shl 13);
  U_LONGENTITY = (1 shl 14);


  SU_VIEWHEIGHT = (1 shl 0);
  SU_IDEALPITCH = (1 shl 1);
  SU_PUNCH1 = (1 shl 2);
  SU_PUNCH2 = (1 shl 3);
  SU_PUNCH3 = (1 shl 4);
  SU_VELOCITY1 = (1 shl 5);
  SU_VELOCITY2 = (1 shl 6);
  SU_VELOCITY3 = (1 shl 7);
//define  SU_AIMENT   = (1 shl 8)  AVAILABLE BIT
  SU_ITEMS = (1 shl 9);
  SU_ONGROUND = (1 shl 10); // no data follows, the bit is it
  SU_INWATER = (1 shl 11); // no data follows, the bit is it
  SU_WEAPONFRAME = (1 shl 12);
  SU_ARMOR = (1 shl 13);
  SU_WEAPON = (1 shl 14);

// a sound with no channel is a local only sound
  SND_VOLUME = (1 shl 0); // a byte
  SND_ATTENUATION = (1 shl 1); // a byte
  SND_LOOPING = (1 shl 2); // a long


// defaults for clientinfo messages
  DEFAULT_VIEWHEIGHT = 22;


// game types sent by serverinfo
// these determine which intermission screen plays
  GAME_COOP = 0;
  GAME_DEATHMATCH = 1;

//==================
// note that there are some defs.qc that mirror to these numbers
// also related to svc_strings[] in cl_parse
//==================

//
// server to client
//
  svc_bad = 0;
  svc_nop = 1;
  svc_disconnect = 2;
  svc_updatestat = 3; // [byte] [long]
  svc_version = 4; // [long] server version
  svc_setview = 5; // [short] entity number
  svc_sound = 6; // <see code>
  svc_time = 7; // [float] server time
  svc_print = 8; // [string] null terminated string
  svc_stufftext = 9; // [string] stuffed into client's console buffer
                                  // the string should be \n terminated
  svc_setangle = 10; // [angle3] set the view angle to this absolute value

  svc_serverinfo = 11; // [long] version
                                  // [string] signon string
                                  // [string]..[0]model cache
                                  // [string]...[0]sounds cache
  svc_lightstyle = 12; // [byte] [string]
  svc_updatename = 13; // [byte] [string]
  svc_updatefrags = 14; // [byte] [short]
  svc_clientdata = 15; // <shortbits + data>
  svc_stopsound = 16; // <see code>
  svc_updatecolors = 17; // [byte] [byte]
  svc_particle = 18; // [vec3] <variable>
  svc_damage = 19;

  svc_spawnstatic = 20;
//  svc_spawnbinary    21
  svc_spawnbaseline = 22;

  svc_temp_entity = 23;

  svc_setpause = 24; // [byte] on / off
  svc_signonnum = 25; // [byte]  used for the signon sequence

  svc_centerprint = 26; // [string] to put in center of the screen

  svc_killedmonster = 27;
  svc_foundsecret = 28;

  svc_spawnstaticsound = 29; // [coord3] [byte] samp [byte] vol [byte] aten

  svc_intermission = 30; // [string] music
  svc_finale = 31; // [string] music [string] text

  svc_cdtrack = 32; // [byte] track [byte] looptrack
  svc_sellscreen = 33;

  svc_cutscene = 34;

//
// client to server
//
  clc_bad = 0;
  clc_nop = 1;
  clc_disconnect = 2;
  clc_move = 3; // [usercmd_t]
  clc_stringcmd = 4; // [string] message


//
// temp entity events
//
  TE_SPIKE = 0;
  TE_SUPERSPIKE = 1;
  TE_GUNSHOT = 2;
  TE_EXPLOSION = 3;
  TE_TAREXPLOSION = 4;
  TE_LIGHTNING1 = 5;
  TE_LIGHTNING2 = 6;
  TE_WIZSPIKE = 7;
  TE_KNIGHTSPIKE = 8;
  TE_LIGHTNING3 = 9;
  TE_LAVASPLASH = 10;
  TE_TELEPORT = 11;
  TE_EXPLOSION2 = 12;
  TE_BEAM = 13;

implementation

end.

