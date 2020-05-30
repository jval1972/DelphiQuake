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

unit sv_main;

// sv_main.c -- server main program

interface

uses
  q_delphi,
  q_vector,
  progs_h,
  server_h,
  gl_planes,
  common;

procedure SV_Init;
procedure SV_StartParticle(org, dir: PVector3f; const color, count: integer);
procedure SV_StartSound(entity: Pedict_t; channel: integer; sample: PChar; volume: integer; attenuation: single);
procedure SV_SendServerinfo(client: Pclient_t);
procedure SV_ConnectClient(clientnum: integer);
procedure SV_CheckForNewClients;
procedure SV_ClearDatagram;
procedure SV_AddToFatPVS(org: PVector3f; node: Pmnode_t);
function SV_FatPVS(org: PVector3f): PByteArray;
procedure SV_WriteEntitiesToClient(clent: Pedict_t; msg: Psizebuf_t);
procedure SV_CleanupEnts;
procedure SV_WriteClientdataToMessage(ent: Pedict_t; msg: Psizebuf_t);
function SV_SendClientDatagram(client: Pclient_t): qboolean;
procedure SV_UpdateToReliableMessages;
procedure SV_SendNop(client: Pclient_t);
procedure SV_SendClientMessages;
function SV_ModelIndex(name: PChar): integer;
procedure SV_CreateBaseline;
procedure SV_SendReconnect;
procedure SV_SaveSpawnparms;
procedure SV_SpawnServer(server: PChar);

var
  sv: server_t;
  svs: server_static_t;

implementation

uses
  quakedef,
  bspconst,
  cvar,
  sv_phys,
  sv_user,
  pr_cmds,
  protocol,
  sys_win,
  console,
  sound,
  pr_edict,
  host_h,
  net,
  net_main,
  pr_exec,
  gl_model,
  gl_model_h,
  mathlib,
  host,
  cl_main_h,
  client,
  cmd,
  gl_screen,
  host_cmd,
  zone,
  world;

var
  localmodels: array[0..MAX_MODELS - 1] of array[0..4] of char; // inline model names for precache

(*
==================
SV_StartParticle

Make sure the event gets sent to all clients
==================
*)

procedure SV_StartParticle(org, dir: PVector3f; const color, count: integer);
var
  i, v: integer;
begin
  if sv.datagram.cursize > MAX_DATAGRAM - 16 then
    exit;

  MSG_WriteByte(@sv.datagram, svc_particle);
  MSG_WriteCoord(@sv.datagram, org[0]);
  MSG_WriteCoord(@sv.datagram, org[1]);
  MSG_WriteCoord(@sv.datagram, org[2]);
  for i := 0 to 2 do
  begin
    v := intval(dir[i] * 16);
    if v > 127 then v := 127 else
      if v < -128 then v := -128;
    MSG_WriteChar(@sv.datagram, v);
  end;
  MSG_WriteByte(@sv.datagram, count);
  MSG_WriteByte(@sv.datagram, color);
end;

(*
==================
SV_StartSound

Each entity can have eight independant sound sources, like voice,
weapon, feet, etc.

Channel 0 is an auto-allocate channel, the others override anything
allready running on that entity/channel pair.

An attenuation of 0 will play full volume everywhere in the level.
Larger attenuations will drop off.  (max 4 attenuation)

==================
 *)

procedure SV_StartSound(entity: Pedict_t; channel: integer; sample: PChar;
  volume: integer; attenuation: single);
var
  sound_num: integer;
  field_mask: integer;
  i: integer;
  ent: integer;
begin
  if (volume < 0) or (volume > 255) then Sys_Error('SV_StartSound: volume = %d', [volume]);
  if (attenuation < 0) or (attenuation > 4) then Sys_Error('SV_StartSound: attenuation = %f', [attenuation]);
  if (channel < 0) or (channel > 7) then Sys_Error('SV_StartSound: channel = %d', [channel]);

  if sv.datagram.cursize > MAX_DATAGRAM - 16 then
    exit;

// find precache number for sound
  sound_num := 1;
  while (sound_num < MAX_SOUNDS) and (sv.sound_precache[sound_num] <> nil) do
  begin
    if strcmp(sample, sv.sound_precache[sound_num]) = 0 then
      break;
    inc(sound_num);
  end;

  if (sound_num = MAX_SOUNDS) or not (sv.sound_precache[sound_num] <> nil) then
  begin
    Con_Printf('SV_StartSound: %s not precacheed'#10, [sample]);
    exit;
  end;

  ent := NUM_FOR_EDICT(entity);

  channel := (ent shl 3) or channel;

  field_mask := 0;
  if volume <> DEFAULT_SOUND_PACKET_VOLUME then
    field_mask := field_mask or SND_VOLUME;
  if attenuation <> DEFAULT_SOUND_PACKET_ATTENUATION then
    field_mask := field_mask or SND_ATTENUATION;

// directed messages go only to the entity the are targeted on
  MSG_WriteByte(@sv.datagram, svc_sound);
  MSG_WriteByte(@sv.datagram, field_mask);
  if field_mask and SND_VOLUME <> 0 then MSG_WriteByte(@sv.datagram, volume);
  if field_mask and SND_ATTENUATION <> 0 then MSG_WriteByte(@sv.datagram, intval(attenuation * 64));
  MSG_WriteShort(@sv.datagram, channel);
  MSG_WriteByte(@sv.datagram, sound_num);
  for i := 0 to 2 do
    MSG_WriteCoord(@sv.datagram, entity.v.origin[i] + 0.5 * (entity.v.mins[i] + entity.v.maxs[i]));
end;

(*
==============================================================================

CLIENT SPAWNING

==============================================================================
*)

(*
================
SV_SendServerinfo

Sends the first message from the server to a connected client.
This will be sent on the initial connection and upon each server load.
================
*)

procedure SV_SendServerinfo(client: Pclient_t);
var
  s: PPchar;
  msg: array[0..2047] of char;
begin
  MSG_WriteByte(@client._message, svc_print);
  sprintf(msg, '%s'#10'VERSION %4.2f SERVER (%d CRC)', [Chr(2), VERSION, pr_crc]);
  MSG_WriteString(@client._message, msg);

  MSG_WriteByte(@client._message, svc_serverinfo);
  MSG_WriteLong(@client._message, PROTOCOL_VERSION);
  MSG_WriteByte(@client._message, svs.maxclients);

  if (coop.value = 0) and (deathmatch.value <> 0) then
    MSG_WriteByte(@client._message, GAME_DEATHMATCH)
  else
    MSG_WriteByte(@client._message, GAME_COOP);

  sprintf(msg, PChar(@pr_strings[sv.edicts.v._message])); // JVAL sos

  MSG_WriteString(@client._message, msg);

  s := @sv.model_precache[1];
  while s^ <> nil do
  begin
    MSG_WriteString(@client._message, s^);
    inc(s);
  end;
  MSG_WriteByte(@client._message, 0);

  s := @sv.sound_precache[1];
  while s^ <> nil do
  begin
    MSG_WriteString(@client._message, s^);
    inc(s);
  end;
  MSG_WriteByte(@client._message, 0);

// send music
  MSG_WriteByte(@client._message, svc_cdtrack);
  MSG_WriteByte(@client._message, intval(sv.edicts.v.sounds));
  MSG_WriteByte(@client._message, intval(sv.edicts.v.sounds));

// set view
  MSG_WriteByte(@client._message, svc_setview);
  MSG_WriteShort(@client._message, NUM_FOR_EDICT(client.edict));

  MSG_WriteByte(@client._message, svc_signonnum);
  MSG_WriteByte(@client._message, 1);

  client.sendsignon := true;
  client.spawned := false; // need prespawn, spawn, etc
end;

(*
================
SV_ConnectClient

Initializes a client_t for a new net connection.  This will only be called
once for a player each game, not once for each level change.
================
*)

procedure SV_ConnectClient(clientnum: integer);
var
  ent: Pedict_t;
  client: Pclient_t;
  edictnum: integer;
  netconnection: Pqsocket_t;
  i: integer;
  spawn_parms: array[0..NUM_SPAWN_PARMS - 1] of single;
begin
  client := @svs.clients[clientnum]; // JVAL check!

  Con_DPrintf('Client %s connected'#10, [client.netconnection.address]);

  edictnum := clientnum + 1;

  ent := EDICT_NUM(edictnum);

// set up the client_t
  netconnection := client.netconnection;

  if sv.loadgame then
    memcpy(@spawn_parms, @client.spawn_parms, SizeOf(spawn_parms));
  memset(client, 0, SizeOf(client^));
  client.netconnection := netconnection;

  strcpy(client.name, 'unconnected');
  client.active := true;
  client.spawned := false;
  client.edict := ent;
  client._message.data := @client.msgbuf;
  client._message.maxsize := SizeOf(client.msgbuf);
  client._message.allowoverflow := true; // we can catch it

  client.privileged := false;

  if sv.loadgame then
    memcpy(@client.spawn_parms, @spawn_parms, SizeOf(spawn_parms))
  else
  begin
  // call the progs to get default spawn parms for the new client
    PR_ExecuteProgram(pr_global_struct.SetNewParms);
    for i := 0 to NUM_SPAWN_PARMS - 1 do
      client.spawn_parms[i] := PFloatArray(@pr_global_struct.parm1)[i]; // JVAL ???
  end;

  SV_SendServerinfo(client);
end;


(*
===================
SV_CheckForNewClients

===================
*)

procedure SV_CheckForNewClients;
var
  ret: Pqsocket_t;
  i: integer;
begin
//
// check for new connections
//
  while true do
  begin
    ret := NET_CheckNewConnections;
    if ret = nil then
      break;

  //
  // init a new client structure
  //
    i := 0;
    while i < svs.maxclients do
    begin
      if not svs.clients[i].active then
        break;
      inc(i);
    end;
    if i = svs.maxclients then
      Sys_Error('Host_CheckForNewClients: no free clients');

    svs.clients[i].netconnection := ret;
    SV_ConnectClient(i);

    inc(net_activeconnections);
  end;
end;



(*
===============================================================================

FRAME UPDATES

===============================================================================
*)

(*
==================
SV_ClearDatagram

==================
*)

procedure SV_ClearDatagram;
begin
  SZ_Clear(@sv.datagram);
end;

(*
=============================================================================

The PVS must include a small area around the client to allow head bobbing
or other small motion on the client side.  Otherwise, a bob might cause an
entity that should be visible to not show up, especially when the bob
crosses a waterline.

=============================================================================
*)

var
  fatbytes: integer;
  fatpvs: array[0..MAX_MAP_LEAFS div 8] of byte;

procedure SV_AddToFatPVS(org: PVector3f; node: Pmnode_t);
var
  i: integer;
  pvs: PByteArray;
  plane: Pmplane_t;
  d: single;
begin
  while true do
  begin
  // if this is a leaf, accumulate the pvs bits
    if node.contents < 0 then
    begin
      if node.contents <> CONTENTS_SOLID then
      begin
        pvs := Mod_LeafPVS(Pmleaf_t(node), sv.worldmodel);
        for i := 0 to fatbytes - 1 do
          fatpvs[i] := fatpvs[i] or pvs[i];
      end;
      exit;
    end;

    plane := node.plane;
    d := VectorDotProduct(org, @plane.normal) - plane.dist;
    if d > 8 then
      node := node.children[0]
    else if d < -8 then
      node := node.children[1]
    else
    begin // go down both
      SV_AddToFatPVS(org, node.children[0]);
      node := node.children[1];
    end;
  end;
end;

(*
=============
SV_FatPVS

Calculates a PVS that is the inclusive or of all leafs within 8 pixels of the
given point.
=============
*)

function SV_FatPVS(org: PVector3f): PByteArray;
begin
  fatbytes := (sv.worldmodel.numleafs + 31) shr 3;
  ZeroMemory(@fatpvs, fatbytes);
  SV_AddToFatPVS(org, sv.worldmodel.nodes);
  result := @fatpvs;
end;

//=============================================================================


(*
=============
SV_WriteEntitiesToClient

=============
*)

procedure SV_WriteEntitiesToClient(clent: Pedict_t; msg: Psizebuf_t);
label
  continue1;
var
  e, i: integer;
  bits: integer;
  pvs: PByteArray;
  org: TVector3f;
  miss: single;
  ent: Pedict_t;
begin
// find the client's PVS
  VectorAdd(@clent.v.origin, @clent.v.view_ofs, @org);
  pvs := SV_FatPVS(@org);

// send over all entities (excpet the client) that touch the pvs
  ent := NEXT_EDICT(sv.edicts);
  for e := 1 to sv.num_edicts - 1 do
  begin
// ignore if not touching a PV leaf
    if ent <> clent then // clent is ALLWAYS sent
    begin
// ignore ents without visible models
      if (ent.v.modelindex = 0) or not boolval(pr_strings[ent.v.model]) then
        goto continue1;

      i := 0;
      while i < ent.num_leafs do
      begin
        if pvs[ent.leafnums[i] shr 3] and ((1 shl (ent.leafnums[i] and 7))) <> 0 then
          break;
        inc(i);
      end;

      if i = ent.num_leafs then
        goto continue1; // not visible
    end;

    if msg.maxsize - msg.cursize < 16 then
    begin
      Con_Printf('packet overflow'#10);
      exit;
    end;

// send an update
    bits := 0;

    for i := 0 to 2 do
    begin
      miss := ent.v.origin[i] - ent.baseline.origin[i];
      if (miss < -0.1) or (miss > 0.1) then bits := bits or (U_ORIGIN1 shl i);
    end;

    if ent.v.angles[0] <> ent.baseline.angles[0] then bits := bits or U_ANGLE1;
    if ent.v.angles[1] <> ent.baseline.angles[1] then bits := bits or U_ANGLE2;
    if ent.v.angles[2] <> ent.baseline.angles[2] then bits := bits or U_ANGLE3;

    if ent.v.movetype = MOVETYPE_STEP then bits := bits or U_NOLERP; // don't mess up the step animation

    if ent.baseline.colormap <> ent.v.colormap then bits := bits or U_COLORMAP;
    if ent.baseline.skin <> ent.v.skin then bits := bits or U_SKIN;
    if ent.baseline.frame <> ent.v.frame then bits := bits or U_FRAME;
    if ent.baseline.effects <> ent.v.effects then bits := bits or U_EFFECTS;
    if ent.baseline.modelindex <> ent.v.modelindex then bits := bits or U_MODEL;

    if e >= 256 then bits := bits or U_LONGENTITY;
    if bits >= 256 then bits := bits or U_MOREBITS;

  //
  // write the message
  //
    MSG_WriteByte(msg, bits or U_SIGNAL);

    if bits and U_MOREBITS <> 0 then MSG_WriteByte(msg, bits shr 8);
    if bits and U_LONGENTITY <> 0 then MSG_WriteShort(msg, e)
    else MSG_WriteByte(msg, e);

    if bits and U_MODEL <> 0 then MSG_WriteShort(msg, intval(ent.v.modelindex)); //SV !!
    if bits and U_FRAME <> 0 then MSG_WriteByte(msg, intval(ent.v.frame));
    if bits and U_COLORMAP <> 0 then MSG_WriteByte(msg, intval(ent.v.colormap));
    if bits and U_SKIN <> 0 then MSG_WriteByte(msg, intval(ent.v.skin));
    if bits and U_EFFECTS <> 0 then MSG_WriteByte(msg, intval(ent.v.effects));
    if bits and U_ORIGIN1 <> 0 then MSG_WriteCoord(msg, ent.v.origin[0]);
    if bits and U_ANGLE1 <> 0 then MSG_WriteAngle(msg, ent.v.angles[0]);
    if bits and U_ORIGIN2 <> 0 then MSG_WriteCoord(msg, ent.v.origin[1]);
    if bits and U_ANGLE2 <> 0 then MSG_WriteAngle(msg, ent.v.angles[1]);
    if bits and U_ORIGIN3 <> 0 then MSG_WriteCoord(msg, ent.v.origin[2]);
    if bits and U_ANGLE3 <> 0 then MSG_WriteAngle(msg, ent.v.angles[2]);
    continue1:
    ent := NEXT_EDICT(ent);
  end;
end;


(*
=============
SV_CleanupEnts

=============
*)

procedure SV_CleanupEnts;
var
  e: integer;
  ent: Pedict_t;
begin
  ent := NEXT_EDICT(sv.edicts);
  for e := 1 to sv.num_edicts - 1 do
  begin
    ent.v.effects := intval(ent.v.effects) and (not EF_MUZZLEFLASH);
    ent := NEXT_EDICT(ent)
  end;
end;


(*
==================
SV_WriteClientdataToMessage

==================
*)

procedure SV_WriteClientdataToMessage(ent: Pedict_t; msg: Psizebuf_t);
var
  bits: integer;
  i: integer;
  other: Pedict_t;
  items: integer;
  val: Peval_t;
begin

//
// send a damage message
//
  if (ent.v.dmg_take <> 0) or (ent.v.dmg_save <> 0) then
  begin
    other := PROG_TO_EDICT(ent.v.dmg_inflictor);
    MSG_WriteByte(msg, svc_damage);
    MSG_WriteByte(msg, intval(ent.v.dmg_save));
    MSG_WriteByte(msg, intval(ent.v.dmg_take));
    for i := 0 to 2 do
      MSG_WriteCoord(msg, other.v.origin[i] + 0.5 * (other.v.mins[i] + other.v.maxs[i]));

    ent.v.dmg_take := 0;
    ent.v.dmg_save := 0;
  end;

//
// send the current viewpos offset from the view entity
//
  SV_SetIdealPitch; // how much to look up / down ideally

// a fixangle might get lost in a dropped packet.  Oh well.
  if ent.v.fixangle <> 0 then
  begin
    MSG_WriteByte(msg, svc_setangle);
    for i := 0 to 2 do
      MSG_WriteAngle(msg, ent.v.angles[i]);
    ent.v.fixangle := 0;
  end;

  bits := 0;

  if ent.v.view_ofs[2] <> DEFAULT_VIEWHEIGHT then
    bits := bits or SU_VIEWHEIGHT;

  if ent.v.idealpitch <> 0 then
    bits := bits or SU_IDEALPITCH;

// stuff the sigil bits into the high bits of items for sbar, or else
// mix in items2
  val := GetEdictFieldValue(ent, 'items2');

  if val <> nil then
    items := intval(ent.v.items) or (intval(val._float) shl 23)
  else
    items := intval(ent.v.items) or (intval(pr_global_struct.serverflags) shl 28);

  bits := bits or SU_ITEMS;

  if intval(ent.v.flags) and FL_ONGROUND <> 0 then
    bits := bits or SU_ONGROUND;

  if ent.v.waterlevel >= 2 then
    bits := bits or SU_INWATER;

  for i := 0 to 2 do
  begin
    if ent.v.punchangle[i] <> 0 then
      bits := bits or (SU_PUNCH1 shl i);
    if ent.v.velocity[i] <> 0 then
      bits := bits or (SU_VELOCITY1 shl i);
  end;

  if ent.v.weaponframe <> 0 then
    bits := bits or SU_WEAPONFRAME;

  if ent.v.armorvalue <> 0 then
    bits := bits or SU_ARMOR;

//  if (ent->v.weapon) // JVAL check!
  bits := bits or SU_WEAPON;

// send the data

  MSG_WriteByte(msg, svc_clientdata);
  MSG_WriteShort(msg, bits);

  if bits and SU_VIEWHEIGHT <> 0 then
    MSG_WriteChar(msg, intval(ent.v.view_ofs[2]));

  if bits and SU_IDEALPITCH <> 0 then
    MSG_WriteChar(msg, intval(ent.v.idealpitch));

  for i := 0 to 2 do
  begin
    if bits and (SU_PUNCH1 shl i) <> 0 then
      MSG_WriteChar(msg, intval(ent.v.punchangle[i]));
    if bits and (SU_VELOCITY1 shl i) <> 0 then
      MSG_WriteChar(msg, intval(ent.v.velocity[i] / 16));
  end;

// [always sent]  if (bits & SU_ITEMS)
  MSG_WriteLong(msg, items);

  if bits and SU_WEAPONFRAME <> 0 then
    MSG_WriteByte(msg, intval(ent.v.weaponframe));
  if bits and SU_ARMOR <> 0 then
    MSG_WriteByte(msg, intval(ent.v.armorvalue));
  if bits and SU_WEAPON <> 0 then
    MSG_WriteByte(msg, SV_ModelIndex(@pr_strings[ent.v.weaponmodel])); // JVAL check!

  MSG_WriteShort(msg, intval(ent.v.health));
  MSG_WriteByte(msg, intval(ent.v.currentammo));
  MSG_WriteByte(msg, intval(ent.v.ammo_shells));
  MSG_WriteByte(msg, intval(ent.v.ammo_nails));
  MSG_WriteByte(msg, intval(ent.v.ammo_rockets));
  MSG_WriteByte(msg, intval(ent.v.ammo_cells));

  if standard_quake then
  begin
    MSG_WriteByte(msg, intval(ent.v.weapon));
  end
  else
  begin
    for i := 0 to 31 do
    begin
      if intval(ent.v.weapon) and (1 shl i) <> 0 then
      begin
        MSG_WriteByte(msg, i);
        break;
      end;
    end;
  end;
end;


(*
=======================
SV_SendClientDatagram
=======================
*)

function SV_SendClientDatagram(client: Pclient_t): qboolean;
var
  buf: array[0..MAX_DATAGRAM - 1] of byte;
  msg: sizebuf_t;
begin
  msg.data := @buf;
  msg.maxsize := SizeOf(buf);
  msg.cursize := 0;

  MSG_WriteByte(@msg, svc_time);
  MSG_WriteFloat(@msg, sv.time);

// add the client specific data to the datagram
  SV_WriteClientdataToMessage(client.edict, @msg);

  SV_WriteEntitiesToClient(client.edict, @msg);

// copy the server datagram if there is space
  if msg.cursize + sv.datagram.cursize < msg.maxsize then
    SZ_Write(@msg, sv.datagram.data, sv.datagram.cursize);

// send the datagram
  if NET_SendUnreliableMessage(client.netconnection, @msg) = -1 then
  begin
    SV_DropClient(true); // if the message couldn't send, kick off
    result := false;
    exit;
  end;

  result := true;
end;


(*
=======================
SV_UpdateToReliableMessages
=======================
*)

procedure SV_UpdateToReliableMessages;
var
  i, j: integer;
  client: Pclient_t;
begin
// check for changes to be sent over the reliable streams
  for i := 0 to svs.maxclients - 1 do
  begin host_client := @svs.clients[i];
    if host_client.old_frags <> host_client.edict.v.frags then
    begin
      for j := 0 to svs.maxclients - 1 do
      begin client := @svs.clients[j];
        if client.active then
        begin
          MSG_WriteByte(@client._message, svc_updatefrags);
          MSG_WriteByte(@client._message, i);
          MSG_WriteShort(@client._message, intval(host_client.edict.v.frags));
        end;
      end;
      host_client.old_frags := intval(host_client.edict.v.frags);
    end;
  end;

  for j := 0 to svs.maxclients - 1 do
  begin client := @svs.clients[j];
    if client.active then
      SZ_Write(@client._message, sv.reliable_datagram.data, sv.reliable_datagram.cursize);
  end;

  SZ_Clear(@sv.reliable_datagram);
end;


(*
=======================
SV_SendNop

Send a nop message without trashing or sending the accumulated client
message buffer
=======================
*)

procedure SV_SendNop(client: Pclient_t);
var
  msg: sizebuf_t;
  buf: array[0..3] of byte;
begin
  msg.data := @buf;
  msg.maxsize := SizeOf(buf);
  msg.cursize := 0;

  MSG_WriteChar(@msg, svc_nop);

  if NET_SendUnreliableMessage(client.netconnection, @msg) = -1 then
    SV_DropClient(true); // if the message couldn't send, kick off
  client.last_message := realtime;
end;


(*
=======================
SV_SendClientMessages
=======================
*)

procedure SV_SendClientMessages;
var
  i: integer;
begin
// update frags, names, etc
  SV_UpdateToReliableMessages;

// build individual updates

  for i := 0 to svs.maxclients - 1 do
  begin host_client := @svs.clients[i];

    if not host_client.active then
      continue;

    if host_client.spawned then
    begin
      if not SV_SendClientDatagram(host_client) then
        continue;
    end
    else
    begin
    // the player isn't totally in the game yet
    // send small keepalive messages if too much time has passed
    // send a full message when the next signon stage has been requested
    // some other message data (name changes, etc) may accumulate
    // between signon stages
      if not host_client.sendsignon then
      begin
        if realtime - host_client.last_message > 5 then
          SV_SendNop(host_client);
        continue; // don't send out non-signon messages
      end;
    end;

    // check for an overflowed message.  Should only happen
    // on a very fucked up connection that backs up a lot, then
    // changes level
    if host_client._message.overflowed then
    begin
      SV_DropClient(true);
      host_client._message.overflowed := false;
      continue;
    end;

    if (host_client._message.cursize <> 0) or host_client.dropasap then
    begin
      if not NET_CanSendMessage(host_client.netconnection) then
      begin
//        I_Printf ("can't write\n");
        continue;
      end;

      if host_client.dropasap then
        SV_DropClient(false) // went to another level
      else
      begin
        if NET_SendMessage(host_client.netconnection, @host_client._message) = -1 then
          SV_DropClient(true); // if the message couldn't send, kick off
        SZ_Clear(@host_client._message);
        host_client.last_message := realtime;
        host_client.sendsignon := false;
      end;
    end;
  end;


// clear muzzle flashes
  SV_CleanupEnts;
end;



(*
==============================================================================

SERVER SPAWNING

==============================================================================
*)

(*
================
SV_ModelIndex

================
*)

function SV_ModelIndex(name: PChar): integer;
var
  i: integer;
begin
  if (name = nil) or (name[0] = #0) then
  begin
    result := 0;
    exit;
  end;

  i := 0;
  while (i < MAX_MODELS) and (sv.model_precache[i] <> nil) do
  begin
    if strcmp(sv.model_precache[i], name) = 0 then
    begin
      result := i;
      exit;
    end;
    inc(i);
  end;

  if (i = MAX_MODELS) or (sv.model_precache[i] = nil) then
    Sys_Error('SV_ModelIndex: model %s not precached', [name]);
  result := i;
end;

(*
================
SV_CreateBaseline

================
*)

procedure SV_CreateBaseline;
var
  i: integer;
  svent: Pedict_t;
  entnum: integer;
begin
  for entnum := 0 to sv.num_edicts - 1 do
  begin
  // get the current server version
    svent := EDICT_NUM(entnum);
    if svent.free then
      continue;
    if (entnum > svs.maxclients) and (svent.v.modelindex = 0) then
      continue;

  //
  // create entity baseline
  //
    VectorCopy(@svent.v.origin, @svent.baseline.origin);
    VectorCopy(@svent.v.angles, @svent.baseline.angles);
    svent.baseline.frame := intval(svent.v.frame);
    svent.baseline.skin := intval(svent.v.skin);
    if (entnum > 0) and (entnum <= svs.maxclients) then
    begin
      svent.baseline.colormap := entnum;
      svent.baseline.modelindex := SV_ModelIndex('progs/player.mdl');
    end
    else
    begin
      svent.baseline.colormap := 0;
      svent.baseline.modelindex := SV_ModelIndex(@pr_strings[svent.v.model]); // JVAL check!
    end;

  //
  // add to the message
  //
    MSG_WriteByte(@sv.signon, svc_spawnbaseline);
    MSG_WriteShort(@sv.signon, entnum);

    MSG_WriteByte(@sv.signon, svent.baseline.modelindex);
    MSG_WriteByte(@sv.signon, svent.baseline.frame);
    MSG_WriteByte(@sv.signon, svent.baseline.colormap);
    MSG_WriteByte(@sv.signon, svent.baseline.skin);
    for i := 0 to 2 do
    begin
      MSG_WriteCoord(@sv.signon, svent.baseline.origin[i]);
      MSG_WriteAngle(@sv.signon, svent.baseline.angles[i]);
    end;
  end;
end;


(*
================
SV_SendReconnect

Tell all the clients that the server is changing levels
================
*)

procedure SV_SendReconnect;
var
  data: array[0..127] of byte;
  msg: sizebuf_t;
begin
  msg.data := @data;
  msg.cursize := 0;
  msg.maxsize := SizeOf(data);

  MSG_WriteChar(@msg, svc_stufftext);
  MSG_WriteString(@msg, 'reconnect'#10);
  NET_SendToAll(@msg, 5);

  if cls.state <> ca_dedicated then
    Cmd_ExecuteString('reconnect'#10, src_command);
end;


(*
================
SV_SaveSpawnparms

Grabs the current state of each client for saving across the
transition to another level
================
*)

procedure SV_SaveSpawnparms;
var
  i, j: integer;
begin
  svs.serverflags := intval(pr_global_struct.serverflags);

  for i := 0 to svs.maxclients - 1 do
  begin host_client := @svs.clients[i];
    if host_client.active then
    begin
    // call the progs to get default spawn parms for the new client
      pr_global_struct.self := EDICT_TO_PROG(host_client.edict);
      PR_ExecuteProgram(pr_global_struct.SetChangeParms);
      for j := 0 to NUM_SPAWN_PARMS - 1 do
        host_client.spawn_parms[j] := PFloatArray(@pr_global_struct.parm1)[j]; // JVAL check!
    end;
  end;
end;


(*
================
SV_SpawnServer

This is called at the start of each level
================
*)
procedure SV_SpawnServer(server: PChar);
var
  ent: Pedict_t;
  i: integer;
begin
  // let's not have any servers with no name
  if hostname.text[0] = #0 then
    Cvar_Set('hostname', 'UNNAMED');
  scr_centertime_off := 0;

  Con_DPrintf('SpawnServer: %s'#10, [server]);
  svs.changelevel_issued := false; // now safe to issue another

//
// tell all connected clients that we are going to a new level
//
  if sv.active then
    SV_SendReconnect;

//
// make cvars consistant
//
  if coop.value <> 0 then Cvar_SetValue('deathmatch', 0);
  current_skill := intval(skill.value + 0.5);
  if current_skill < 0 then current_skill := 0;
  if current_skill > 3 then current_skill := 3;

  Cvar_SetValue('skill', current_skill);

//
// set up the new server
//
  Host_ClearMemory;

  ZeroMemory(@sv, SizeOf(sv));

  strcpy(sv.name, server);

// load progs to get entity field count
  PR_LoadProgs;

// allocate server memory
  sv.max_edicts := MAX_EDICTS;

  sv.edicts := Hunk_AllocName(sv.max_edicts * pr_edict_size, 'edicts');

  sv.datagram.maxsize := SizeOf(sv.datagram_buf);
  sv.datagram.cursize := 0;
  sv.datagram.data := @sv.datagram_buf;

  sv.reliable_datagram.maxsize := SizeOf(sv.reliable_datagram_buf);
  sv.reliable_datagram.cursize := 0;
  sv.reliable_datagram.data := @sv.reliable_datagram_buf[0]; // JVAL check!

  sv.signon.maxsize := SizeOf(sv.signon_buf);
  sv.signon.cursize := 0;
  sv.signon.data := @sv.signon_buf[0];

// leave slots at start for clients only
  sv.num_edicts := svs.maxclients + 1;
  for i := 0 to svs.maxclients - 1 do
  begin
    ent := EDICT_NUM(i + 1);
    svs.clients[i].edict := ent;
  end;

  sv.state := ss_loading;
  sv.paused := false;

  sv.time := 1.0;

  strcpy(sv.name, server);
  sprintf(sv.modelname, 'maps/%s.bsp', [server]);
  sv.worldmodel := Mod_ForName(sv.modelname, false);
  if sv.worldmodel = nil then
  begin
    Con_Printf('Couldn''t spawn server %s'#10, [sv.modelname]);
    sv.active := false;
    exit;
  end;
  sv.models[1] := sv.worldmodel;

//
// clear world interaction links
//
  SV_ClearWorld;

  sv.sound_precache[0] := pr_strings; // JVAL check!       !! TODO

  sv.model_precache[0] := pr_strings; // JVAL check!
  sv.model_precache[1] := sv.modelname; // JVAL check!
  for i := 1 to sv.worldmodel.numsubmodels - 1 do
  begin
    sv.model_precache[i + 1] := localmodels[i];
    sv.models[i + 1] := Mod_ForName(localmodels[i], false);
  end;

//
// load the rest of the entities
//
  ent := EDICT_NUM(0);
  memset(@ent.v, 0, progs.entityfields * 4);
  ent.free := false;
  ent.v.model := integer(@sv.worldmodel.name[0]) - integer(pr_strings); // JVAL check!     TODO
  ent.v.modelindex := 1; // world model
  ent.v.solid := SOLID_BSP;
  ent.v.movetype := MOVETYPE_PUSH;

  if coop.value <> 0 then
    pr_global_struct.coop := coop.value
  else
    pr_global_struct.deathmatch := deathmatch.value;

  pr_global_struct.mapname := integer(@sv.name[0]) - integer(pr_strings);
// serverflags are for cross level information (sigils)
  pr_global_struct.serverflags := svs.serverflags;

  ED_LoadFromFile(sv.worldmodel.entities);

  sv.active := true;

// all setup is completed, any further precache statements are errors
  sv.state := ss_active;

// run two frames to allow everything to settle
  host_frametime := 0.1;
  SV_Physics;
  SV_Physics;

// create a baseline for more efficient communications
  SV_CreateBaseline;

// send serverinfo to all connected clients

  for i := 0 to svs.maxclients - 1 do
  begin host_client := @svs.clients[i];
    if host_client.active then
      SV_SendServerinfo(host_client);
  end;

  Con_DPrintf('Server spawned.'#10);
end;


{ TServer }

procedure SV_Init;
var
  i: integer;
begin
  Cvar_RegisterVariable(@sv_maxvelocity);
  Cvar_RegisterVariable(@sv_gravity);
  Cvar_RegisterVariable(@sv_friction);
  Cvar_RegisterVariable(@sv_edgefriction);
  Cvar_RegisterVariable(@sv_stopspeed);
  Cvar_RegisterVariable(@sv_maxspeed);
  Cvar_RegisterVariable(@sv_accelerate);
  Cvar_RegisterVariable(@sv_idealpitchscale);
  Cvar_RegisterVariable(@sv_aim);
  Cvar_RegisterVariable(@sv_nostep);

  for i := 0 to MAX_MODELS - 1 do
    sprintf(localmodels[i], '*%d', [i]);
end;

end.

