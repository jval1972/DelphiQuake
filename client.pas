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

unit client;

interface

uses
  q_delphi,
  q_vector,
  quakedef,
  vid_h,
  gl_model_h,
  net,
  common,
  sound;

type

  usercmd_t = record
    viewangles: TVector3f;

// intended velocities
    forwardmove: single;
    sidemove: single;
    upmove: single;
  end;
  Pusercmd_t = ^usercmd_t;

  lightstyle_t = record
    length: integer;
    map: array[0..MAX_STYLESTRING - 1] of char;
  end;
  Plightstyle_t = ^lightstyle_t;

  scoreboard_t = record
    name: array[0..MAX_SCOREBOARDNAME - 1] of char;
    entertime: single;
    frags: integer;
    colors: integer; // two 4 bit fields
    translations: array[0..VID_GRADES * 256 - 1] of byte;
  end;
  Pscoreboard_t = ^scoreboard_t;
  scoreboard_tArray = array[0..$FFFF] of scoreboard_t;
  Pscoreboard_tArray = ^scoreboard_tArray;

  cshift_t = record
    destcolor: array[0..2] of integer;
    percent: integer; // 0-256
  end;
  Pcshift_t = ^cshift_t;

const
  CSHIFT_CONTENTS = 0;
  CSHIFT_DAMAGE = 1;
  CSHIFT_BONUS = 2;
  CSHIFT_POWERUP = 3;
  NUM_CSHIFTS = 4;

  NAME_LENGTH = 64;
//
// client_state_t should hold all pieces of the client state
//

  SIGNONS = 4; // signon messages to receive before connected

  MAX_DLIGHTS = 32;

type
  dlight_t = record
    origin: TVector3f;
    radius: single;
    die: single; // stop lighting after this time
    decay: single; // drop this each second
    minlight: single; // don't add when contributing less
    key: integer;
  end;
  Pdlight_t = ^dlight_t;


const
  MAX_BEAMS = 24;

type
  beam_t = record
    entity: integer;
    model: PBSPModelFile;
    endtime: single;
    start: TVector3f;
    _end: TVector3f;
  end;
  Pbeam_t = ^beam_t;

const
  MAX_EFRAGS = 640;

  MAX_MAPSTRING = 2048;
  MAX_DEMOS = 8;
  MAX_DEMONAME = 16;
  MAX_LEVELNAME = 40;

type
  cactive_t = (
    ca_dedicated, // a dedicated server with no ability to start a client
    ca_disconnected, // full screen console with no connection
    ca_connected // valid netcon, talking to a server
    );

//
// the client_static_t structure is persistant through an arbitrary number
// of server connections
//
  client_static_t = record
    state: cactive_t;

// personalization data sent to server
    mapstring: array[0..MAX_QPATH - 1] of char;
    spawnparms: array[0..MAX_MAPSTRING - 1] of char; // to restart a level

// demo loop control
    demonum: integer; // -1 = don't play demos
    demos: array[0..MAX_DEMOS - 1] of array[0..MAX_DEMONAME - 1] of char; // when not playing

// demo recording info must be here, because record is started before
// entering a map (and clearing client_state_t)
    demorecording: qboolean;
    demoplayback: qboolean;
    timedemo: qboolean;
    forcetrack: integer; // -1 = use normal cd track
    demofile: integer;
    td_lastframe: integer; // to meter out one message a frame
    td_startframe: integer; // host_framecount at start
    td_starttime: single; // realtime at second frame of timedemo


// connection information
    signon: integer; // 0 to SIGNONS
    netcon: Pqsocket_t;
    _message: sizebuf_t; // writing buffer to send to server
  end;

//
// the client_state_t structure is wiped completely at every
// server signon
//
  client_state_t = record
    movemessages: integer; // since connecting to this server
                            // throw out the first couple, so the player
                            // doesn't accidentally do something the
                            // first frame
    cmd: usercmd_t; // last command sent to the server

// information for local display
    stats: array[0..MAX_CL_STATS - 1] of integer; // health, etc
    items: integer; // inventory bit flags
    item_gettime: array[0..31] of single; // cl.time of aquiring item, for blinking
    faceanimtime: single; // use anim frame if cl.time < this

    cshifts: array[0..NUM_CSHIFTS - 1] of cshift_t; // color shifts for damage, powerups
    prev_cshifts: array[0..NUM_CSHIFTS - 1] of cshift_t; // and content types

// the client maintains its own idea of view angles, which are
// sent to the server each frame.  The server sets punchangle when
// the view is temporarliy offset, and an angle reset commands at the start
// of each level and after teleporting.
    mviewangles: array[0..1] of TVector3f; // during demo playback viewangles is lerped
                                                            // between these
    viewangles: TVector3f;

    mvelocity: array[0..1] of TVector3f; // update by server, used for lean+bob
                                                            // (0 is newest)
    velocity: TVector3f; // lerped between mvelocity[0] and [1]

    punchangle: TVector3f; // temporary offset

// pitch drifting vars
    idealpitch: single;
    pitchvel: single;
    nodrift: qboolean;
    driftmove: single;
    laststop: double;

    viewheight: single;
    crouch: single; // local amount for smoothing stepups

    paused: qboolean; // send over by server
    onground: qboolean;
    inwater: qboolean;

    intermission: integer; // don't change view angle, full screen, etc
    completed_time: integer; // latched at intermission start

    mtime: array[0..1] of double; // the timestamp of last two messages
    time: double; // clients view of time, should be between
                                                            // servertime and oldservertime to generate
                                                            // a lerp point for other data
    oldtime: double; // previous cl.time, time-oldtime is used
                                                            // to decay light values and smooth step ups


    last_received_message: single; // (realtime) for net trouble icon

//
// information that is static for the entire time connected to a server
//
    model_precache: array[0..MAX_MODELS - 1] of PBSPModelFile;
    sound_precache: array[0..MAX_SOUNDS - 1] of Psfx_t;

    levelname: array[0..MAX_LEVELNAME - 1] of char; // for display on solo scoreboard
    viewentity: integer; // cl_entitites[cl.viewentity] = player
    maxclients: integer;
    gametype: integer;

// refresh related state
    worldmodel: PBSPModelFile; // cl_entitites[0].model
    free_efrags: Pefrag_tArray;
    num_entities: integer; // held in cl_entities array
    num_statics: integer; // held in cl_staticentities array
    viewent: entity_t; // the gun model

    cdtrack, looptrack: integer; // cd audio

// frag scoreboard
    scores: Pscoreboard_tArray; // [cl.maxclients]
  end;


const
  MAX_TEMP_ENTITIES = 64; // lightning bolts, etc
  MAX_STATIC_ENTITIES = 128; // torches, etc

//=============================================================================

//
// cl_main
//
const
  MAX_VISEDICTS = 256;

//
// cl_input
//
type
  kbutton_t = record
    down: array[0..1] of integer; // key nums holding it down
    state: integer; // low bit is down state
  end;
  Pkbutton_t = ^kbutton_t;

implementation

end.


