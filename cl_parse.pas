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

unit cl_parse;

interface

uses
  gl_model_h;

procedure CL_ParseServerMessage;

implementation

uses
  q_delphi,
  q_vector,
  cl_main_h,
  quakedef,
  host,
  gl_vidnt,
  mathlib,
  common,
  protocol,
  sound,
  snd_dma,
  sv_main,
  net_main,
  cl_demo,
  sys_win,
  console,
  cl_main,
  zone,
  gl_model,
  gl_rmisc,
  host_cmd,
  client,
  sbar,
  vid_h,
  render_h,
  gl_refrag,
  gl_screen,
  cmd,
  view,
  gl_part,
  cl_tent,
  cd_win;

const
  svc_strings: array[0..34] of PChar = (
    'svc_bad',
    'svc_nop',
    'svc_disconnect',
    'svc_updatestat',
    'svc_version', // [long] server version
    'svc_setview', // [short] entity number
    'svc_sound', // <see code>
    'svc_time', // [float] server time
    'svc_print', // [string] null terminated string
    'svc_stufftext', // [string] stuffed into client's console buffer
                          // the string should be \n terminated
    'svc_setangle', // [vec3] set the view angle to this absolute value

    'svc_serverinfo', // [long] version
                          // [string] signon string
                          // [string]..[0]model cache [string]...[0]sounds cache
                          // [string]..[0]item cache
    'svc_lightstyle', // [byte] [string]
    'svc_updatename', // [byte] [string]
    'svc_updatefrags', // [byte] [short]
    'svc_clientdata', // <shortbits + data>
    'svc_stopsound', // <see code>
    'svc_updatecolors', // [byte] [byte]
    'svc_particle', // [vec3] <variable>
    'svc_damage', // [byte] impact [byte] blood [vec3] from

    'svc_spawnstatic',
    'OBSOLETE svc_spawnbinary',
    'svc_spawnbaseline',

    'svc_temp_entity', // <variable>
    'svc_setpause',
    'svc_signonnum',
    'svc_centerprint',
    'svc_killedmonster',
    'svc_foundsecret',
    'svc_spawnstaticsound',
    'svc_intermission',
    'svc_finale', // [string] music [string] text
    'svc_cdtrack', // [byte] track [byte] looptrack
    'svc_sellscreen',
    'svc_cutscene'
    );

procedure SHOWNET(x: PChar);
begin
  if cl_shownet.value = 2 then
    Con_Printf('%3d:%s'#10, [msg_readcount - 1, x]);
end;

{ TParser }

function CL_EntityNum(num: integer): Pentity_t;
begin
  if num >= cl.num_entities then
  begin
    if num >= MAX_EDICTS then
      Host_Error('CL_EntityNum: %d is an invalid number', [num]);
    while cl.num_entities <= num do
    begin
      cl_entities[cl.num_entities].colormap := vid.colormap;
      inc(cl.num_entities);
    end;
  end;

  result := @cl_entities[num];
end;

var
  lastmsg: single = 0;

procedure CL_KeepaliveMessage;
var
  time: single;
  ret: integer;
  old: sizebuf_t;
  olddata: array[0..8191] of byte;
begin
  if sv.active then
    exit; // no need if server is local
  if cls.demoplayback then
    exit;

// read messages from server, should just be nops
  old := net_message;
  memcpy(@olddata, net_message.data, net_message.cursize);

  repeat
    ret := CL_GetMessage;
    case ret of
      0: ;
      1: Host_Error('CL_KeepaliveMessage: received a message');
      2: if MSG_ReadByte <> svc_nop then
          Host_Error('CL_KeepaliveMessage: datagram wasn''t a nop');
    else
      Host_Error('CL_KeepaliveMessage: CL_GetMessage failed');
    end;
  until ret = 0;

  net_message := old;
  memcpy(net_message.data, @olddata, net_message.cursize);

// check time
  time := Sys_FloatTime;
  if time - lastmsg < 5 then
    exit;
  lastmsg := time;

// write out a nop
  Con_Printf('--> client to server keepalive'#10);

  MSG_WriteByte(@cls._message, clc_nop);
  NET_SendMessage(cls.netcon, @cls._message);
  SZ_Clear(@cls._message);
end;

procedure CL_NewTranslation(slot: integer);
var
  i, j: integer;
  top, bottom: integer;
  dest, source: PByteArray;
begin
  if slot > cl.maxclients then
    Sys_Error('CL_NewTranslation: slot > cl.maxclients');
  dest := @cl.scores[slot].translations;
  source := vid.colormap;
  memcpy(dest, vid.colormap, SizeOf(cl.scores[slot].translations));
  top := cl.scores[slot].colors and $F0;
  bottom := ((cl.scores[slot].colors and 15) shl 4);
  R_TranslatePlayerSkin(slot);

  for i := 0 to VID_GRADES - 1 do
  begin
    if top < 128 then // the artists made some backwards ranges.  sigh.
      memcpy(@dest[TOP_RANGE], @source[top], 16)
    else
      for j := 0 to 15 do
        dest[TOP_RANGE + j] := source[top + 15 - j];

    if bottom < 128 then
      memcpy(@dest[BOTTOM_RANGE], @source[bottom], 16)
    else
      for j := 0 to 15 do
        dest[BOTTOM_RANGE + j] := source[bottom + 15 - j];
    dest := @dest[256];
    source := @source[256];
  end;
end;

procedure CL_ParseBaseline(ent: Pentity_t);
var
  i: integer;
begin
  ent.baseline.modelindex := MSG_ReadByte;
  ent.baseline.frame := MSG_ReadByte;
  ent.baseline.colormap := MSG_ReadByte;
  ent.baseline.skin := MSG_ReadByte;
  for i := 0 to 2 do
  begin
    ent.baseline.origin[i] := MSG_ReadCoord;
    ent.baseline.angles[i] := MSG_ReadAngle;
  end;
end;

procedure CL_ParseClientdata(bits: integer);
var
  i, j: integer;
begin
  if bits and SU_VIEWHEIGHT <> 0 then
    cl.viewheight := MSG_ReadChar
  else
    cl.viewheight := DEFAULT_VIEWHEIGHT;

  if bits and SU_IDEALPITCH <> 0 then
    cl.idealpitch := MSG_ReadChar
  else
    cl.idealpitch := 0;

  VectorCopy(@cl.mvelocity[0], @cl.mvelocity[1]);
  for i := 0 to 2 do
  begin
    if bits and (SU_PUNCH1 shl i) <> 0 then
      cl.punchangle[i] := MSG_ReadChar
    else
      cl.punchangle[i] := 0;
    if bits and (SU_VELOCITY1 shl i) <> 0 then
      cl.mvelocity[0][i] := MSG_ReadChar * 16
    else
      cl.mvelocity[0][i] := 0;
  end;

// [always sent]  if (bits & SU_ITEMS)
  i := MSG_ReadLong;

  if cl.items <> i then
  begin // set flash times
    Sbar_Changed;
    for j := 0 to 31 do
      if boolval(i and (1 shl j)) and (not boolval(cl.items and (1 shl j))) then
        cl.item_gettime[j] := cl.time;
    cl.items := i;
  end;

  cl.onground := (bits and SU_ONGROUND) <> 0;
  cl.inwater := (bits and SU_INWATER) <> 0;

  if bits and SU_WEAPONFRAME <> 0 then
    cl.stats[STAT_WEAPONFRAME] := MSG_ReadByte
  else
    cl.stats[STAT_WEAPONFRAME] := 0;

  if bits and SU_ARMOR <> 0 then
    i := MSG_ReadByte
  else
    i := 0;
  if cl.stats[STAT_ARMOR] <> i then
  begin
    cl.stats[STAT_ARMOR] := i;
    Sbar_Changed;
  end;

  if bits and SU_WEAPON <> 0 then
    i := MSG_ReadByte
  else
    i := 0;
  if cl.stats[STAT_WEAPON] <> i then
  begin
    cl.stats[STAT_WEAPON] := i;
    Sbar_Changed;
  end;

  i := MSG_ReadShort;
  if cl.stats[STAT_HEALTH] <> i then
  begin
    cl.stats[STAT_HEALTH] := i;
    Sbar_Changed;
  end;

  i := MSG_ReadByte;
  if cl.stats[STAT_AMMO] <> i then
  begin
    cl.stats[STAT_AMMO] := i;
    Sbar_Changed;
  end;

  for i := 0 to 3 do
  begin
    j := MSG_ReadByte;
    if cl.stats[STAT_SHELLS + i] <> j then
    begin
      cl.stats[STAT_SHELLS + i] := j;
      Sbar_Changed;
    end;
  end;

  i := MSG_ReadByte;

  if standard_quake then
  begin
    if cl.stats[STAT_ACTIVEWEAPON] <> i then
    begin
      cl.stats[STAT_ACTIVEWEAPON] := i;
      Sbar_Changed;
    end;
  end
  else
  begin
    if cl.stats[STAT_ACTIVEWEAPON] <> (1 shl i) then
    begin
      cl.stats[STAT_ACTIVEWEAPON] := (1 shl i);
      Sbar_Changed;
    end;
  end;
end;

procedure CL_ParseServerInfo;
var
  str: PChar;
  i: integer;
  nummodels, numsounds: integer;
  model_precache: array[0..MAX_MODELS - 1] of array[0..MAX_QPATH - 1] of char;
  sound_precache: array[0..MAX_SOUNDS - 1] of array[0..MAX_QPATH - 1] of char;
begin
  Con_DPrintf('Serverinfo packet received.'#10);
//
// wipe the client_state_t struct
//
  CL_ClearState;

// parse protocol version number
  i := MSG_ReadLong;
  if i <> PROTOCOL_VERSION then
  begin
    Con_Printf('Server returned version %d, not %d', [i, PROTOCOL_VERSION]);
    exit;
  end;

// parse maxclients
  cl.maxclients := MSG_ReadByte;
  if (cl.maxclients < 1) or (cl.maxclients > MAX_SCOREBOARD) then
  begin
    Con_Printf('Bad maxclients (%u) from server'#10, [cl.maxclients]);
    exit;
  end;
  cl.scores := Hunk_AllocName(cl.maxclients * SizeOf(cl.scores[0]), 'scores');

// parse gametype
  cl.gametype := MSG_ReadByte;

// parse signon message
  str := MSG_ReadString;

  strncpy(cl.levelname, str, SizeOf(cl.levelname) - 1);

// seperate the printfs so the server message can have a color
  Con_Printf(#10#10 + CON_LINE + #10#10);
  { \35 = #$1D 29  \36 = #$1E 30 \37 = #$1E 31 }
//  Con_Printf("\n\n\35\36\36\36\36\36\36\36\36\36\36\36\36\36\36\36\36\36\36\36\36\36\36\36\36\36\36\36\36\36\36\36\36\36\36\36\37\n\n");
  Con_Printf('%s%s'#10, [Chr(2), str]);

//
// first we go through and touch all of the precache data that still
// happens to be in the cache, so precaching something else doesn't
// needlessly purge it
//

// precache models
  ZeroMemory(@cl.model_precache, SizeOf(cl.model_precache));
  nummodels := 0;
  while true do
  begin
    inc(nummodels);
    str := MSG_ReadString;
    if str[0] = #0 then
      break;
    if nummodels = MAX_MODELS then
    begin
      Con_Printf('Server sent too many model precaches'#10);
      exit;
    end;
    strcpy(model_precache[nummodels], str);
    Mod_TouchModel(str);
  end;

// precache sounds
  ZeroMemory(@cl.sound_precache, SizeOf(cl.sound_precache));
  numsounds := 0;
  while true do
  begin
    inc(numsounds);
    str := MSG_ReadString;
    if str[0] = #0 then
      break;
    if numsounds = MAX_SOUNDS then
    begin
      Con_Printf('Server sent too many sound precaches'#10);
      exit;
    end;
    strcpy(sound_precache[numsounds], str);
    S_TouchSound(str);
  end;

//
// now we try to load everything else until a cache allocation fails
//

  for i := 1 to nummodels - 1 do
  begin
    cl.model_precache[i] := Mod_ForName(model_precache[i], false);
//    Con_Printf('Model %d'#10, [i]); // JVAL
    if cl.model_precache[i] = nil then
    begin
      Con_Printf('Model %s not found'#10, [model_precache[i]]);
      exit;
    end;
    CL_KeepaliveMessage;
  end;

  S_BeginPrecaching;
  for i := 1 to numsounds - 1 do
  begin
    cl.sound_precache[i] := S_PrecacheSound(sound_precache[i]);
    CL_KeepaliveMessage;
  end;
  S_EndPrecaching;

// local state
  cl_entities[0].model := cl.model_precache[1];
  cl.worldmodel := cl.model_precache[1];

  R_NewMap;

  Hunk_Check; // make sure nothing is hurt

  noclip_anglehack := false; // noclip is turned off at start
end;

procedure CL_ParseStartSoundPacket;
var
  pos: TVector3f;
  channel, ent: integer;
  sound_num: integer;
  volume: integer;
  field_mask: integer;
  attenuation: single;
  i: integer;
begin
  field_mask := MSG_ReadByte;

  if field_mask and SND_VOLUME <> 0 then
    volume := MSG_ReadByte
  else
    volume := DEFAULT_SOUND_PACKET_VOLUME;

  if field_mask and SND_ATTENUATION <> 0 then
    attenuation := MSG_ReadByte / 64.0
  else
    attenuation := DEFAULT_SOUND_PACKET_ATTENUATION;

  channel := MSG_ReadShort;
  sound_num := MSG_ReadByte;

  ent := channel div 8;
  channel := channel and 7;

  if ent > MAX_EDICTS then
    Host_Error('CL_ParseStartSoundPacket: ent = %d', [ent]);

  for i := 0 to 2 do
    pos[i] := MSG_ReadCoord;

  S_StartSound(ent, channel, cl.sound_precache[sound_num], @pos, volume / 255.0, attenuation);
end;

procedure CL_ParseStatic;
var
  ent: Pentity_t;
  i: integer;
begin
  i := cl.num_statics;
  if i >= MAX_STATIC_ENTITIES then
    Host_Error('Too many static entities');
  ent := @cl_static_entities[i];
  inc(cl.num_statics);
  CL_ParseBaseline(ent);

// copy it to the current state
  ent.model := cl.model_precache[ent.baseline.modelindex];
  ent.frame := ent.baseline.frame;
  ent.colormap := vid.colormap;
  ent.skinnum := ent.baseline.skin;
  ent.effects := ent.baseline.effects;

  VectorCopy(@ent.baseline.origin, @ent.origin);
  VectorCopy(@ent.baseline.angles, @ent.angles);
  R_AddEfrags(ent);
end;

procedure CL_ParseStaticSound;
var
  org: TVector3f;
  sound_num, vol, atten: integer;
  i: integer;
begin
  for i := 0 to 2 do
    org[i] := MSG_ReadCoord;
  sound_num := MSG_ReadByte;
  vol := MSG_ReadByte;
  atten := MSG_ReadByte;

  S_StaticSound(cl.sound_precache[sound_num], @org, vol, atten);
end;

var
  bitcounts: array[0..15] of integer = (
    0, 0, 0, 0,
    0, 0, 0, 0,
    0, 0, 0, 0,
    0, 0, 0, 0);

procedure CL_ParseUpdate(bits: integer);
var
  i: integer;
  model: PBSPModelFile;
  modnum: integer;
  forcelink: boolean;
  ent: Pentity_t;
  num: integer;
  skin: integer;
begin
  if cls.signon = SIGNONS - 1 then
  begin // first update is the final signon stage
    cls.signon := SIGNONS;
    CL_SignonReply;
  end;

  if bits and U_MOREBITS <> 0 then
  begin
    i := MSG_ReadByte;
    bits := bits or (i shl 8);
  end;

  if bits and U_LONGENTITY <> 0 then
    num := MSG_ReadShort
  else
    num := MSG_ReadByte;

  ent := CL_EntityNum(num);

  for i := 0 to 15 do
    if bits and (1 shl i) <> 0 then
      inc(bitcounts[i]);

  if ent.msgtime <> cl.mtime[1] then
    forcelink := true // no previous frame to lerp from
  else
    forcelink := false;

  ent.msgtime := cl.mtime[0];

  if bits and U_MODEL <> 0 then
  begin
    if cls.demoplayback then
      modnum := MSG_ReadByte  // JVAL
    else
    modnum := MSG_ReadShort; //Byte; SV!!
    if modnum >= MAX_MODELS then
      Host_Error('CL_ParseModel: bad modnum');
  end
  else
    modnum := ent.baseline.modelindex;

  model := cl.model_precache[modnum];
  if model <> ent.model then
  begin
    ent.model := model;
  // automatic animation (torches, etc) can be either all together
  // or randomized
    if model <> nil then
    begin
      if model.synctype = ST_RAND then
        ent.syncbase := (rand and $7FFF) / $7FFF
      else
        ent.syncbase := 0.0;
    end
    else
      forcelink := true; // hack to make null model players work
    if (num > 0) and (num <= cl.maxclients) then
      R_TranslatePlayerSkin(num - 1);
  end;

  if bits and U_FRAME <> 0 then
    ent.frame := MSG_ReadByte
  else
    ent.frame := ent.baseline.frame;

  if bits and U_COLORMAP <> 0 then
    i := MSG_ReadByte
  else
    i := ent.baseline.colormap;
  if i = 0 then
    ent.colormap := vid.colormap
  else
  begin
    if i > cl.maxclients then
      Sys_Error('i >= cl.maxclients');
    ent.colormap := @cl.scores[i - 1].translations;
  end;

  if bits and U_SKIN <> 0 then
    skin := MSG_ReadByte
  else
    skin := ent.baseline.skin;
  if skin <> ent.skinnum then
  begin
    ent.skinnum := skin;
    if (num > 0) and (num <= cl.maxclients) then
      R_TranslatePlayerSkin(num - 1);
  end;

  if bits and U_EFFECTS <> 0 then
    ent.effects := MSG_ReadByte
  else
    ent.effects := ent.baseline.effects;

// shift the known values for interpolation
  VectorCopy(@ent.msg_origins[0], @ent.msg_origins[1]);
  VectorCopy(@ent.msg_angles[0], @ent.msg_angles[1]);

  if bits and U_ORIGIN1 <> 0 then
    ent.msg_origins[0][0] := MSG_ReadCoord
  else
    ent.msg_origins[0][0] := ent.baseline.origin[0];
  if bits and U_ANGLE1 <> 0 then
    ent.msg_angles[0][0] := MSG_ReadAngle
  else
    ent.msg_angles[0][0] := ent.baseline.angles[0];

  if bits and U_ORIGIN2 <> 0 then
    ent.msg_origins[0][1] := MSG_ReadCoord
  else
    ent.msg_origins[0][1] := ent.baseline.origin[1];
  if bits and U_ANGLE2 <> 0 then
    ent.msg_angles[0][1] := MSG_ReadAngle
  else
    ent.msg_angles[0][1] := ent.baseline.angles[1];

  if bits and U_ORIGIN3 <> 0 then
    ent.msg_origins[0][2] := MSG_ReadCoord
  else
    ent.msg_origins[0][2] := ent.baseline.origin[2];
  if bits and U_ANGLE3 <> 0 then
    ent.msg_angles[0][2] := MSG_ReadAngle
  else
    ent.msg_angles[0][2] := ent.baseline.angles[2];

  if bits and U_NOLERP <> 0 then
    ent.forcelink := true;

  if forcelink then
  begin // didn't have an update last message
    VectorCopy(@ent.msg_origins[0], @ent.msg_origins[1]);
    VectorCopy(@ent.msg_origins[0], @ent.origin);
    VectorCopy(@ent.msg_angles[0], @ent.msg_angles[1]);
    VectorCopy(@ent.msg_angles[0], @ent.angles);
    ent.forcelink := true;
  end;
end;

procedure CL_ParseServerMessage;
var
  cmd: integer;
  i: integer;
begin
//
// if recording demos, copy the message out
//
  if cl_shownet.value = 1 then
    Con_Printf('%d ', [net_message.cursize])
  else if cl_shownet.value = 2 then
    Con_Printf('------------------'#10);

  cl.onground := false; // unless the server says otherwise
//
// parse the message
//
  MSG_BeginReading;

  while true do
  begin
    if msg_badread then
      Host_Error('CL_ParseServerMessage: Bad server message');

    cmd := MSG_ReadByte;

    if cmd = -1 then
    begin
      SHOWNET('END OF MESSAGE');
      exit; // end of message
    end;

  // if the high bit of the command byte is set, it is a fast update
    if cmd and 128 <> 0 then
    begin
      SHOWNET('fast update');
      CL_ParseUpdate(cmd and 127);
      continue;
    end;

    SHOWNET(svc_strings[cmd]);

  // other commands
    case cmd of
      svc_nop: ; // Con_Printf ("svc_nop\n");

      svc_time:
        begin
          cl.mtime[1] := cl.mtime[0];
          cl.mtime[0] := MSG_ReadFloat;
        end;

      svc_clientdata:
        begin
          i := MSG_ReadShort;
          CL_ParseClientdata(i);
        end;

      svc_version:
        begin
          i := MSG_ReadLong;
          if i <> PROTOCOL_VERSION then
            Host_Error('CL_ParseServerMessage: Server is protocol %d instead of %d'#10, [i, PROTOCOL_VERSION]);
        end;

      svc_disconnect:
        begin
          Host_EndGame('Server disconnected'#10, []);
//          Con_Printf('%s', [MSG_ReadString]);
        end;
      svc_print:
        begin
          Con_Printf('%s', [MSG_ReadString]);
        end;

      svc_centerprint:
        SCR_CenterPrint(MSG_ReadString);

      svc_stufftext:
        Cbuf_AddText(MSG_ReadString);

      svc_damage:
        V_ParseDamage;

      svc_serverinfo:
        begin
          CL_ParseServerInfo;
          vid.recalc_refdef := true; // leave intermission full screen
        end;

      svc_setangle:
        for i := 0 to 2 do
          cl.viewangles[i] := MSG_ReadAngle;

      svc_setview:
        cl.viewentity := MSG_ReadShort;

      svc_lightstyle:
        begin
          i := MSG_ReadByte;
          if i >= MAX_LIGHTSTYLES then
            Sys_Error('svc_lightstyle > MAX_LIGHTSTYLES');
          Q_strcpy(cl_lightstyle[i].map, MSG_ReadString);
          cl_lightstyle[i].length := Q_strlen(cl_lightstyle[i].map);
        end;

      svc_sound:
        CL_ParseStartSoundPacket;

      svc_stopsound:
        begin
          i := MSG_ReadShort;
          S_StopSound(i div 8, i and 7);
        end;

      svc_updatename:
        begin
          Sbar_Changed;
          i := MSG_ReadByte;
          if i >= cl.maxclients then
            Host_Error('CL_ParseServerMessage: svc_updatename > MAX_SCOREBOARD');
          strcpy(cl.scores[i].name, MSG_ReadString);
        end;

      svc_updatefrags:
        begin
          Sbar_Changed;
          i := MSG_ReadByte;
          if i >= cl.maxclients then
            Host_Error('CL_ParseServerMessage: svc_updatefrags > MAX_SCOREBOARD');
          cl.scores[i].frags := MSG_ReadShort;
        end;

      svc_updatecolors:
        begin
          Sbar_Changed;
          i := MSG_ReadByte;
          if i >= cl.maxclients then
            Host_Error('CL_ParseServerMessage: svc_updatecolors > MAX_SCOREBOARD');
          cl.scores[i].colors := MSG_ReadByte;
          CL_NewTranslation(i);
        end;

      svc_particle:
        R_ParseParticleEffect;

      svc_spawnbaseline:
        begin
          i := MSG_ReadShort();
          // must use CL_EntityNum() to force cl.num_entities up
          CL_ParseBaseline(CL_EntityNum(i));
        end;

      svc_spawnstatic:
        CL_ParseStatic;

      svc_temp_entity:
        CL_ParseTEnt;

      svc_setpause:
        begin
          cl.paused := MSG_ReadByte <> 0;

          if cl.paused then
          begin
            CDAudio_Pause;
            VID_HandlePause(true);
          end
          else
          begin
            CDAudio_Resume;
            VID_HandlePause(false);
          end;
        end;

      svc_signonnum:
        begin
          i := MSG_ReadByte;
          if i <= cls.signon then
            Host_Error('Received signon %d when at %d', [i, cls.signon]);
          cls.signon := i;
          CL_SignonReply;
        end;

      svc_killedmonster:
        inc(cl.stats[STAT_MONSTERS]);

      svc_foundsecret:
        inc(cl.stats[STAT_SECRETS]);

      svc_updatestat:
        begin
          i := MSG_ReadByte;
          if (i < 0) or (i >= MAX_CL_STATS) then
            Sys_Error('svc_updatestat: %d is invalid', [i]);
          cl.stats[i] := MSG_ReadLong;
        end;

      svc_spawnstaticsound:
        CL_ParseStaticSound;

      svc_cdtrack:
        begin
          cl.cdtrack := MSG_ReadByte;
          cl.looptrack := MSG_ReadByte;
          if (cls.demoplayback or cls.demorecording) and (cls.forcetrack <> -1) then
            CDAudio_Play(byte(cls.forcetrack), true)
          else
            CDAudio_Play(byte(cl.cdtrack), true);
        end;

      svc_intermission:
        begin
          cl.intermission := 1;
          cl.completed_time := intval(cl.time);
          vid.recalc_refdef := true; // go to full screen
        end;

      svc_finale:
        begin
          cl.intermission := 2;
          cl.completed_time := intval(cl.time);
          vid.recalc_refdef := true; // go to full screen
          SCR_CenterPrint(MSG_ReadString);
        end;

      svc_cutscene:
        begin
          cl.intermission := 3;
          cl.completed_time := intval(cl.time);
          vid.recalc_refdef := true; // go to full screen
          SCR_CenterPrint(MSG_ReadString);
        end;

      svc_sellscreen:
        Cmd_ExecuteString('help', src_command);

    else
      Host_Error('CL_ParseServerMessage: Illegible server message'#10);
    end
  end;
end;

end.

