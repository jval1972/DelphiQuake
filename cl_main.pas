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

unit cl_main;

interface

uses
  q_delphi,
  client;

procedure CL_ClearState;

procedure CL_Disconnect;

procedure CL_Disconnect_f;

procedure CL_EstablishConnection(host: PChar);

procedure CL_SignonReply;

procedure CL_NextDemo;

procedure CL_PrintEntities_f;

function CL_AllocDlight(key: integer): Pdlight_t;

procedure CL_DecayLights;

function CL_LerpPoint: single;

procedure CL_RelinkEntities;

function CL_ReadFromServer: integer;

procedure CL_SendCmd;

procedure CL_Init;

procedure CL_AdjustPitch;

implementation

// cl_main.c  -- client main loop

uses
  q_vector,
  cvar,
  gl_model_h,
  quakedef,
  sv_main,
  host,
  cl_main_h,
  common,
  cl_tent,
  snd_dma,
  cl_demo,
  console,
  protocol,
  net_main,
  zone,
  gl_screen,
  cmd,
  mathlib,
  gl_refrag,
  gl_part,
  chase,
  host_h,
  cl_parse,
  cl_input,
  in_win;

procedure CL_Disconnect_f;
begin
  CL_Disconnect;
  if sv.active then
    Host_ShutdownServer(false);
end;

procedure CL_PrintEntities_f;
var
  ent: Pentity_t;
  i: integer;
begin
  ent := @cl_entities[0];
  for i := 0 to cl.num_entities - 1 do
  begin
    Con_Printf('%3d:', [i]);
    if ent.model = nil then
      Con_Printf('EMPTY'#10)
    else
      Con_Printf('%s:%2d  (%5.1f,%5.1f,%5.1f) [%5.1f %5.1f %5.1f]'#10,
        [ent.model.name, ent.frame, ent.origin[0], ent.origin[1], ent.origin[2], ent.angles[0], ent.angles[1], ent.angles[2]]);
    inc(ent);
  end;
end;

{ TClientMain }

procedure CL_AdjustPitch;
begin
  if cl.viewangles[PITCH] > 80 then
    cl.viewangles[PITCH] := 80
  else if cl.viewangles[PITCH] < -70 then
    cl.viewangles[PITCH] := -70;
end;

function CL_AllocDlight(key: integer): Pdlight_t;
var
  i: integer;
  dl: Pdlight_t;
begin
// first look for an exact key match
  if key <> 0 then
  begin
    dl := @cl_dlights;
    for i := 0 to MAX_DLIGHTS - 1 do
    begin
      if dl.key = key then
      begin
        memset(dl, 0, SizeOf(dl^));
        dl.key := key;
        result := dl;
        exit;
      end;
      inc(dl);
    end;
  end;

// then look for anything else
  dl := @cl_dlights[0];
  for i := 0 to MAX_DLIGHTS - 1 do
  begin
    if dl.die < cl.time then
    begin
      memset(dl, 0, SizeOf(dlight_t));
      dl.key := key;
      result := dl;
      exit;
    end;
    inc(dl);
  end;

  dl := @cl_dlights[0];
  memset(dl, 0, SizeOf(dlight_t));
  dl.key := key;
  result := dl;
end;

procedure CL_ClearState;
var
  i: integer;
begin
  if not sv.active then
    Host_ClearMemory;

// wipe the entire cl structure
  ZeroMemory(@cl, SizeOf(cl));

  SZ_Clear(@cls._message);

// clear other arrays
  ZeroMemory(@cl_efrags, SizeOf(cl_efrags));
  ZeroMemory(@cl_entities, SizeOf(cl_entities));
  ZeroMemory(@cl_dlights, SizeOf(cl_dlights));
  ZeroMemory(@cl_lightstyle, SizeOf(cl_lightstyle));
  CL_ClearTEnts;
//
// allocate the efrags and chain together into a free list
//
  cl.free_efrags := @cl_efrags;
  for i := 0 to MAX_EFRAGS - 2 do
    cl.free_efrags[i].entnext := @cl.free_efrags[i + 1];
  cl.free_efrags[MAX_EFRAGS - 1].entnext := nil;
end;

procedure CL_DecayLights;
var
  i: integer;
  dl: Pdlight_t;
  time: single;
begin
  time := cl.time - cl.oldtime;

  dl := @cl_dlights[0];
  for i := 0 to MAX_DLIGHTS - 1 do
  begin
    if (dl.die < cl.time) or (dl.radius = 0) then
    else
    begin
      dl.radius := dl.radius - time * dl.decay;
      if dl.radius < 0 then
        dl.radius := 0;
    end;
    inc(dl);
  end;
end;

procedure CL_Disconnect;
begin
// stop sounds (especially looping!)
  S_StopAllSounds(true);

// bring the console down and fade the colors back to normal
//  SCR_BringDownConsole ();

// if running a local server, shut it down
  if cls.demoplayback then
    CL_StopPlayback
  else

    if cls.state = ca_connected then
    begin
      if cls.demorecording then
        CL_Stop_f;

      Con_DPrintf('Sending clc_disconnect'#10);
      SZ_Clear(@cls._message);
      MSG_WriteByte(@cls._message, clc_disconnect);
      NET_SendUnreliableMessage(cls.netcon, @cls._message);
      SZ_Clear(@cls._message);
      NET_Close(cls.netcon);

      cls.state := ca_disconnected;
      if sv.active then
        Host_ShutdownServer(false);
    end;

  cls.demoplayback := false;
  cls.timedemo := false;
  cls.signon := 0;
end;

procedure CL_EstablishConnection(host: PChar);
begin
  if cls.state = ca_dedicated then
    exit;

  if cls.demoplayback then
    exit;

  CL_Disconnect;

  cls.netcon := NET_Connect(host);
  if cls.netcon = nil then
    Host_Error('CL_Connect: connect failed'#10);
  Con_DPrintf('CL_EstablishConnection: connected to %s'#10, [host]);

  cls.demonum := -1; // not in the demo loop now
  cls.state := ca_connected;
  cls.signon := 0; // need all the signon messages before playing
end;

procedure CL_Init;
begin
  SZ_Alloc(@cls._message, 1024);

  CL_InitInput;
  CL_InitTEnts;

//
// register our commands
//
  Cvar_RegisterVariable(@cl_name);
  Cvar_RegisterVariable(@cl_color);
  Cvar_RegisterVariable(@cl_upspeed);
  Cvar_RegisterVariable(@cl_forwardspeed);
  Cvar_RegisterVariable(@cl_backspeed);
  Cvar_RegisterVariable(@cl_sidespeed);
  Cvar_RegisterVariable(@cl_movespeedkey);
  Cvar_RegisterVariable(@cl_yawspeed);
  Cvar_RegisterVariable(@cl_pitchspeed);
  Cvar_RegisterVariable(@cl_anglespeedkey);
  Cvar_RegisterVariable(@cl_shownet);
  Cvar_RegisterVariable(@cl_nolerp);
  Cvar_RegisterVariable(@lookspring);
  Cvar_RegisterVariable(@lookstrafe);
  Cvar_RegisterVariable(@sensitivity);

  Cvar_RegisterVariable(@m_pitch);
  Cvar_RegisterVariable(@m_yaw);
  Cvar_RegisterVariable(@m_forward);
  Cvar_RegisterVariable(@m_side);

//  Cvar_RegisterVariable (&cl_autofire);

  Cmd_AddCommand('entities', CL_PrintEntities_f);
  Cmd_AddCommand('disconnect', CL_Disconnect_f);
  Cmd_AddCommand('record', CL_Record_f);
  Cmd_AddCommand('stop', CL_Stop_f);
  Cmd_AddCommand('playdemo', CL_PlayDemo_f);
  Cmd_AddCommand('timedemo', CL_TimeDemo_f);
end;

function CL_LerpPoint: single;
var
  f, frac: single;
begin
  f := cl.mtime[0] - cl.mtime[1];

  if (f = 0) or (cl_nolerp.value <> 0) or cls.timedemo or sv.active then
  begin
    cl.time := cl.mtime[0];
    result := 1;
    exit;
  end;

  if f > 0.1 then
  begin // dropped packet, or start of demo
    cl.mtime[1] := cl.mtime[0] - 0.1;
    f := 0.1;
  end;
  frac := (cl.time - cl.mtime[1]) / f;
  if frac < 0 then
  begin
    if frac < -0.01 then
    begin
      cl.time := cl.mtime[1];
    end;
    frac := 0;
  end
  else if frac > 1 then
  begin
    if frac > 1.01 then
    begin
      cl.time := cl.mtime[0];
    end;
    frac := 1;
  end;

  result := frac;
end;

procedure CL_NextDemo;
var
  str: array[0..1023] of char;
begin
  if cls.demonum = -1 then
    exit; // don't play demos

  SCR_BeginLoadingPlaque;

  if (cls.demos[cls.demonum][0] = #0) or (cls.demonum = MAX_DEMOS) then
  begin
    cls.demonum := 0;
    if cls.demos[cls.demonum][0] = #0 then
    begin
      Con_Printf('No demos listed with startdemos'#10);
      cls.demonum := -1;
      exit;
    end;
  end;

  sprintf(str, 'playdemo %s'#10, [cls.demos[cls.demonum]]);
  Cbuf_InsertText(str);
  inc(cls.demonum);
end;

function CL_ReadFromServer: integer;
var
  ret: integer;
begin
  cl.oldtime := cl.time;
  cl.time := cl.time + host_frametime;

  repeat
    ret := CL_GetMessage;
    if ret = -1 then
      Host_Error('CL_ReadFromServer: lost server connection');
    if ret = 0 then
      break;

    cl.last_received_message := realtime;
    CL_ParseServerMessage;
  until not ((ret <> 0) and (cls.state = ca_connected));

  if cl_shownet.value <> 0 then
    Con_Printf(#10);

  CL_RelinkEntities;
  CL_UpdateTEnts;

//
// bring the links up to date
//
  result := 0;
end;

procedure CL_RelinkEntities;
var
  ent: Pentity_t;
  i, j: integer;
  frac, f, d: single;
  delta: TVector3f;
  bobjrotate: single;
  oldorg: TVector3f;
  dl: Pdlight_t;
  fv, rv, uv: TVector3f;
begin
// determine partial update time
  frac := CL_LerpPoint;

  cl_numvisedicts := 0;

//
// interpolate player info
//
  for i := 0 to 2 do
    cl.velocity[i] := cl.mvelocity[1][i] +
      frac * (cl.mvelocity[0][i] - cl.mvelocity[1][i]);

  if cls.demoplayback then
  begin
  // interpolate the angles
    for j := 0 to 2 do
    begin
      d := cl.mviewangles[0][j] - cl.mviewangles[1][j];
      if d > 180 then
        d := d - 360
      else if d < -180 then
        d := d + 360;
      cl.viewangles[j] := cl.mviewangles[1][j] + frac * d;
    end;
  end;

  bobjrotate := anglemod(100 * cl.time);

// start on the entity after the world
  for i := 1 to cl.num_entities - 1 do
  begin
    ent := @cl_entities[i];
    if ent.model = nil then
    begin // empty slot
      if ent.forcelink then
        R_RemoveEfrags(ent); // just became empty
      continue;
    end;

// if the object wasn't included in the last packet, remove it
    if ent.msgtime <> cl.mtime[0] then
    begin
      ent.model := nil;
      continue;
    end;

    VectorCopy(@ent.origin, @oldorg);

    if ent.forcelink then
    begin // the entity was not updated in the last message
          // so move to the final spot
      VectorCopy(@ent.msg_origins[0], @ent.origin);
      VectorCopy(@ent.msg_angles[0], @ent.angles);
    end
    else
    begin // if the delta is large, assume a teleport and don't lerp
      f := frac;
      for j := 0 to 2 do
      begin
        delta[j] := ent.msg_origins[0][j] - ent.msg_origins[1][j];
        if (delta[j] > 100) or (delta[j] < -100) then
          f := 1; // assume a teleportation, not a motion
      end;

    // interpolate the origin and angles
      for j := 0 to 2 do
      begin
        ent.origin[j] := ent.msg_origins[1][j] + f * delta[j];

        d := ent.msg_angles[0][j] - ent.msg_angles[1][j];
        if d > 180 then
          d := d - 360
        else if d < -180 then
          d := d + 360;
        ent.angles[j] := ent.msg_angles[1][j] + f * d;
      end;

    end;

// rotate binary objects locally
    if ent.model.flags and EF_ROTATE <> 0 then
      ent.angles[1] := bobjrotate;

    if ent.effects and EF_BRIGHTFIELD <> 0 then
      R_EntityParticles(ent);
    if ent.effects and EF_MUZZLEFLASH <> 0 then
    begin

      dl := CL_AllocDlight(i);
      VectorCopy(@ent.origin, @dl.origin);
      dl.origin[2] := dl.origin[2] + 16;
      AngleVectors(@ent.angles, @fv, @rv, @uv);

      VectorMA(@dl.origin, 18, @fv, @dl.origin);
      dl.radius := 200 + (rand and 31);
      dl.minlight := 32;
      dl.die := cl.time + 0.1;
    end;
    if ent.effects and EF_BRIGHTLIGHT <> 0 then
    begin
      dl := CL_AllocDlight(i);
      VectorCopy(@ent.origin, @dl.origin);
      dl.origin[2] := dl.origin[2] + 16;
      dl.radius := 400 + (rand and 31);
      dl.die := cl.time + 0.001;
    end;
    if ent.effects and EF_DIMLIGHT <> 0 then
    begin
      dl := CL_AllocDlight(i);
      VectorCopy(@ent.origin, @dl.origin);
      dl.radius := 200 + (rand and 31);
      dl.die := cl.time + 0.001;
    end;
    if ent.model.flags and EF_GIB <> 0 then
      R_RocketTrail(@oldorg, @ent.origin, 2)
    else if ent.model.flags and EF_ZOMGIB <> 0 then
      R_RocketTrail(@oldorg, @ent.origin, 4)
    else if ent.model.flags and EF_TRACER <> 0 then
      R_RocketTrail(@oldorg, @ent.origin, 3)
    else if ent.model.flags and EF_TRACER2 <> 0 then
      R_RocketTrail(@oldorg, @ent.origin, 5)
    else if ent.model.flags and EF_ROCKET <> 0 then
    begin
      R_RocketTrail(@oldorg, @ent.origin, 0);
      dl := CL_AllocDlight(i);
      VectorCopy(@ent.origin, @dl.origin);
      dl.radius := 200;
      dl.die := cl.time + 0.01;
    end
    else if ent.model.flags and EF_GRENADE <> 0 then
      R_RocketTrail(@oldorg, @ent.origin, 1)
    else if ent.model.flags and EF_TRACER3 <> 0 then
      R_RocketTrail(@oldorg, @ent.origin, 6);

    ent.forcelink := false;

    if (i = cl.viewentity) and (chase_active.value = 0) then
      continue;

    if cl_numvisedicts < MAX_VISEDICTS then
    begin
      cl_visedicts[cl_numvisedicts] := ent;
      inc(cl_numvisedicts);
    end;
  end;
end;

procedure CL_SendCmd;
var
  cmd: usercmd_t;
begin
  if cls.state <> ca_connected then
    exit;

  if cls.signon = SIGNONS then
  begin
  // get basic movement from keyboard
    CL_BaseMove(@cmd);

  // allow mice or other external controllers to add to the move
    IN_Move(@cmd);

  // send the unreliable message
    CL_SendMove(@cmd);

  end;

  if cls.demoplayback then
  begin
    SZ_Clear(@cls._message);
    exit;
  end;

// send the reliable message
  if cls._message.cursize = 0 then
    exit; // no message at all

  if not NET_CanSendMessage(cls.netcon) then
  begin
    Con_DPrintf('CL_WriteToServer: can''t send'#10);
    exit;
  end;

  if NET_SendMessage(cls.netcon, @cls._message) = -1 then
    Host_Error('CL_WriteToServer: lost server connection');

  SZ_Clear(@cls._message);
end;

procedure CL_SignonReply;
var
  str: array[0..8191] of char;
begin
  Con_DPrintf('CL_SignonReply: %d'#10, [cls.signon]);

  case cls.signon of
    1:
      begin
        MSG_WriteByte(@cls._message, clc_stringcmd);
        MSG_WriteString(@cls._message, 'prespawn');
      end;

    2:
      begin
        MSG_WriteByte(@cls._message, clc_stringcmd);
        MSG_WriteString(@cls._message, va('name "%s"'#10, [cl_name.text]));

        MSG_WriteByte(@cls._message, clc_stringcmd);
        MSG_WriteString(@cls._message, va('color %d %d'#10, [(intval(cl_color.value) shr 4), intval(cl_color.value) and 15]));

        MSG_WriteByte(@cls._message, clc_stringcmd);
        sprintf(str, 'spawn %s', [cls.spawnparms]);
        MSG_WriteString(@cls._message, str);
      end;

    3:
      begin
        MSG_WriteByte(@cls._message, clc_stringcmd);
        MSG_WriteString(@cls._message, 'begin');
        Cache_Report; // print remaining memory
      end;

    4:
      SCR_EndLoadingPlaque; // allow normal screen updates
  end;
end;

end.

