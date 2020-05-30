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

unit server_h;

// server.h

interface

uses
  q_delphi,
  q_vector,
  net,
  client,
  common,
  quakedef,
  progs_h,
  gl_model_h;

const
  NUM_PING_TIMES = 16;
  NUM_SPAWN_PARMS = 16;


type
  Pclient_t = ^client_t;
  client_t = record
    active: qboolean; // false = client is free
    spawned: qboolean; // false = don't send datagrams
    dropasap: qboolean; // has been told to go to another level
    privileged: qboolean; // can execute any host command
    sendsignon: qboolean; // only valid before spawned

    last_message: double; // reliable messages must be sent
                                        // periodically

    netconnection: Pqsocket_t; // communications handle

    cmd: usercmd_t; // movement
    wishdir: TVector3f; // intended motion calced from cmd

    _message: sizebuf_t; // can be added to at any time,
                         // copied and clear once per frame
    msgbuf: array[0..MAX_MSGLEN - 1] of byte;
    edict: Pedict_t; // EDICT_NUM(clientnum+1)
    name: array[0..31] of char; // for printing to other people
    colors: integer;

    ping_times: array[0..NUM_PING_TIMES - 1] of single;
    num_pings: integer; // ping_times[num_pings%NUM_PING_TIMES]

// spawn parms are carried from level to level
    spawn_parms: array[0..NUM_SPAWN_PARMS - 1] of single;

// client known data for deltas
    old_frags: integer;
  end;
  client_tArray = array[0..$FFFF] of client_t;
  Pclient_tArray = ^client_tArray;


  Pserver_static_t = ^server_static_t;
  server_static_t = record
    maxclients: integer;
    maxclientslimit: integer;
    clients: Pclient_tArray;  // [maxclients]
    serverflags: integer;     // episode completion information
    changelevel_issued: qboolean; // cleared when at SV_SpawnServer
  end;

//=============================================================================

type
  server_state_t = (ss_loading, ss_active);

type
  Pserver_t = ^server_t;
  server_t = record
    active: qboolean; // false if only a net client

    paused: qboolean;
    loadgame: qboolean; // handle connections specially

    time: double;

    lastcheck: integer; // used by PF_checkclient
    lastchecktime: double;

    name: array[0..63] of char; // map name
    modelname: array[0..63] of char; // maps/<name>.bsp, for model_precache[0]
    worldmodel: PBSPModelFile;
    model_precache: array[0..MAX_MODELS - 1] of PChar; // NULL terminated
    models: array[0..MAX_MODELS - 1] of PBSPModelFile;
    sound_precache: array[0..MAX_SOUNDS - 1] of PChar; // NULL terminated
    lightstyles: array[0..MAX_LIGHTSTYLES - 1] of PChar;
    num_edicts: integer;
    max_edicts: integer;
    edicts: Pedict_t; // can NOT be array indexed, because
                      // edict_t is variable sized, but can
                      // be used to reference the world ent
    state: server_state_t; // some actions are only valid during load

    datagram: sizebuf_t;
    datagram_buf: array[0..MAX_DATAGRAM - 1] of byte;

    reliable_datagram: sizebuf_t; // copied to all clients at end of frame
    reliable_datagram_buf: array[0..MAX_DATAGRAM - 1] of byte;

    signon: sizebuf_t;
    signon_buf: array[0..8191] of byte;
  end;


//=============================================================================

// edict->movetype values
const
  MOVETYPE_NONE = 0; // never moves
  MOVETYPE_ANGLENOCLIP = 1;
  MOVETYPE_ANGLECLIP = 2;
  MOVETYPE_WALK = 3; // gravity
  MOVETYPE_STEP = 4; // gravity, special edge handling
  MOVETYPE_FLY = 5;
  MOVETYPE_TOSS = 6; // gravity
  MOVETYPE_PUSH = 7; // no clip to world, push and crush
  MOVETYPE_NOCLIP = 8;
  MOVETYPE_FLYMISSILE = 9; // extra size to monsters
  MOVETYPE_BOUNCE = 10;

// edict->solid values
  SOLID_NOT = 0; // no interaction with other objects
  SOLID_TRIGGER = 1; // touch on edge, but not blocking
  SOLID_BBOX = 2; // touch on edge, block
  SOLID_SLIDEBOX = 3; // touch on edge, but not an onground
  SOLID_BSP = 4; // bsp clip, touch on edge, block

// edict->deadflag values
  DEAD_NO = 0;
  DEAD_DYING = 1;
  DEAD_DEAD = 2;

  DAMAGE_NO = 0;
  DAMAGE_YES = 1;
  DAMAGE_AIM = 2;

// edict->flags
  FL_FLY = 1;
  FL_SWIM = 2;
  FL_CONVEYOR = 4;
  FL_CLIENT = 8;
  FL_INWATER = 16;
  FL_MONSTER = 32;
  FL_GODMODE = 64;
  FL_NOTARGET = 128;
  FL_ITEM = 256;
  FL_ONGROUND = 512;
  FL_PARTIALGROUND = 1024;// not all corners are valid
  FL_WATERJUMP = 2048;    // player jumping out of water
  FL_JUMPRELEASED = 4096; // for jump debouncing

// entity effects

  EF_BRIGHTFIELD = 1;
  EF_MUZZLEFLASH = 2;
  EF_BRIGHTLIGHT = 4;
  EF_DIMLIGHT = 8;
  SPAWNFLAG_NOT_EASY = 256;
  SPAWNFLAG_NOT_MEDIUM = 512;
  SPAWNFLAG_NOT_HARD = 1024;
  SPAWNFLAG_NOT_DEATHMATCH = 2048;

//============================================================================

implementation

end.

