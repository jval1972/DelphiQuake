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

unit sv_user;

// sv_user.c -- server code for moving users

interface

uses
  cvar,
  progs_h;

var
  sv_player: Pedict_t;

procedure SV_RunClients;
procedure SV_SetIdealPitch;

var
  sv_edgefriction: cvar_t = (name: 'edgefriction'; text: '2');
  sv_maxspeed: cvar_t = (name: 'sv_maxspeed'; text: '320'; archive: false; server: true);
  sv_accelerate: cvar_t = (name: 'sv_accelerate'; text: '10');
  sv_idealpitchscale: cvar_t = (name: 'sv_idealpitchscale'; text: '0.8'; );

implementation

uses
  q_delphi,
  q_vector,
  mathlib,
  client,
  world,
  server_h,
  quakedef,
  sv_phys,
  host_h,
  sv_main,
  view,
  common,
  net_main,
  sys_win,
  protocol,
  cmd,
  console,
  host,
  keys;

var
  fwd, right, up: TVector3f;

var
  wishdir: TVector3f;
  wishspeed: single;

// world
var
  angles: PVector3f; //PFloatArray; // JVAL mayby Pvec3_t?
  origin: PVector3f; //PFloatArray; // JVAL mayby Pvec3_t?
  velocity: PVector3f; //PFloatArray; // JVAL mayby Pvec3_t?

var
  onground: qboolean;

var
  usrcmd: usercmd_t;

(*
===============
SV_SetIdealPitch
===============
*)
const
  MAX_FORWARD = 6;

procedure SV_SetIdealPitch;
var
  angleval, sinval, cosval: single;
  tr: trace_t;
  top, bottom: TVector3f;
  z: array[0..MAX_FORWARD - 1] of single;
  i, j: integer;
  step, dir, steps: integer;
begin
  if (intval(sv_player.v.flags) and FL_ONGROUND) = 0 then
    exit;

  angleval := sv_player.v.angles[YAW] * M_PI * 2 / 360;
  sinval := sin(angleval); // JVAL mayby sincos ?
  cosval := cos(angleval);

  i := 0;
  while i < MAX_FORWARD do
  begin
    top[0] := sv_player.v.origin[0] + cosval * (i + 3) * 12;
    top[1] := sv_player.v.origin[1] + sinval * (i + 3) * 12;
    top[2] := sv_player.v.origin[2] + sv_player.v.view_ofs[2];

    bottom[0] := top[0];
    bottom[1] := top[1];
    bottom[2] := top[2] - 160;

    tr := SV_MoveEdict(@top, @vec3_origin, @vec3_origin, @bottom, 1, sv_player);
    if tr.allsolid then
      exit; // looking at a wall, leave ideal the way is was

    if tr.fraction = 1 then
      exit; // near a dropoff

    z[i] := top[2] + tr.fraction * (bottom[2] - top[2]);
    inc(i);
  end;

  dir := 0;
  steps := 0;
  for j := 1 to i - 1 do
  begin
    step := intval(z[j] - z[j - 1]);
    if (step > -ON_EPSILON) and (step < ON_EPSILON) then
      continue;

    if (dir <> 0) and ((step - dir > ON_EPSILON) or (step - dir < -ON_EPSILON)) then
      exit; // mixed changes

    inc(steps);
    dir := step;
  end;

  if dir = 0 then
  begin
    sv_player.v.idealpitch := 0;
    exit;
  end;

  if steps < 2 then
    exit;

  sv_player.v.idealpitch := -dir * sv_idealpitchscale.value;
end;


(*
==================
SV_UserFriction

==================
*)

procedure SV_UserFriction;
var
  vel: PVector3f;
  speed, newspeed, control: single;
  start, stop: TVector3f;
  friction: single;
  trace: trace_t;
begin
  vel := velocity;

  speed := sqrt(vel[0] * vel[0] + vel[1] * vel[1]);
  if speed = 0.0 then
    exit;

// if the leading edge is over a dropoff, increase friction
  start[0] := origin[0] + vel[0] / speed * 16;
  stop[0] := start[0];
  start[1] := origin[1] + vel[1] / speed * 16;
  stop[1] := start[1];
  start[2] := origin[2] + sv_player.v.mins[2];
  stop[2] := start[2] - 34;

  trace := SV_MoveEdict(@start, @vec3_origin, @vec3_origin, @stop, 1, sv_player);

  if trace.fraction = 1.0 then
    friction := sv_friction.value * sv_edgefriction.value
  else
    friction := sv_friction.value;

// apply friction
  if speed < sv_stopspeed.value then
    control := sv_stopspeed.value
  else
    control := speed;
  newspeed := speed - host_frametime * control * friction;

  if newspeed < 0 then
    newspeed := 0;
  newspeed := newspeed / speed;

  vel[0] := vel[0] * newspeed;
  vel[1] := vel[1] * newspeed;
  vel[2] := vel[2] * newspeed;
end;

(*
==============
SV_Accelerate
==============
*)
procedure SV_DoAccelerate;
var
  i: integer;
  addspeed, accelspeed, currentspeed: single;
begin
  currentspeed := VectorDotProduct(PVector3f(velocity), @wishdir);
  addspeed := wishspeed - currentspeed;
  if addspeed <= 0 then
    exit;
  accelspeed := sv_accelerate.value * host_frametime * wishspeed;
  if accelspeed > addspeed then
    accelspeed := addspeed;

  for i := 0 to 2 do
    velocity[i] := velocity[i] + accelspeed * wishdir[i];
end;

procedure SV_AirAccelerate(wishveloc: PVector3f);
var
  i: integer;
  addspeed, wishspd, accelspeed, currentspeed: single;
begin
  wishspd := VectorNormalize(wishveloc);
  if wishspd > 30 then
    wishspd := 30;
  currentspeed := VectorDotProduct(PVector3f(velocity), wishveloc);
  addspeed := wishspd - currentspeed;
  if addspeed <= 0 then
    exit;
//  accelspeed := sv_accelerate.value * host_frametime;
  accelspeed := sv_accelerate.value * wishspeed * host_frametime;
  if accelspeed > addspeed then
    accelspeed := addspeed;

  for i := 0 to 2 do
    velocity[i] := velocity[i] + accelspeed * wishveloc[i];
end;


procedure DropPunchAngle;
var
  len: single;
begin
  len := VectorNormalize(@sv_player.v.punchangle);

  len := len - 10 * host_frametime;
  if len < 0 then
    len := 0;
  VectorScale(@sv_player.v.punchangle, len, @sv_player.v.punchangle);
end;

(*
===================
SV_WaterMove

===================
*)

procedure SV_WaterMove;
var
  i: integer;
  wishvel: TVector3f;
  speed, newspeed, wishspeed, addspeed, accelspeed: single;
begin
//
// user intentions
//
  AngleVectors(@sv_player.v.v_angle, @fwd, @right, @up);

  for i := 0 to 2 do
    wishvel[i] := fwd[i] * usrcmd.forwardmove + right[i] * usrcmd.sidemove;

  if (usrcmd.forwardmove = 0) and (usrcmd.sidemove = 0) and (usrcmd.upmove = 0) then
    wishvel[2] := wishvel[2] - 60 // drift towards bottom
  else
    wishvel[2] := wishvel[2] + usrcmd.upmove;

  wishspeed := VectorLength(@wishvel);
  if wishspeed > sv_maxspeed.value then
  begin
    VectorScale(@wishvel, sv_maxspeed.value / wishspeed, @wishvel);
    wishspeed := sv_maxspeed.value;
  end;
  wishspeed := wishspeed * 0.7;

//
// water friction
//
  speed := VectorLength(PVector3f(velocity));
  if speed <> 0 then
  begin
    newspeed := speed - host_frametime * speed * sv_friction.value;
    if newspeed < 0 then
      newspeed := 0;
    VectorScale(PVector3f(velocity), newspeed / speed, PVector3f(velocity));
  end
  else
    newspeed := 0;

//
// water acceleration
//
  if wishspeed = 0.0 then
    exit;

  addspeed := wishspeed - newspeed;
  if addspeed <= 0 then
    exit;

  VectorNormalize(@wishvel);
  accelspeed := sv_accelerate.value * wishspeed * host_frametime;
  if accelspeed > addspeed then
    accelspeed := addspeed;

  for i := 0 to 2 do
    velocity[i] := velocity[i] + accelspeed * wishvel[i];
end;

procedure SV_WaterJump;
begin
  if (sv.time > sv_player.v.teleport_time) or
    (sv_player.v.waterlevel = 0) then
  begin
    sv_player.v.flags := intval(sv_player.v.flags) and (not FL_WATERJUMP);
    sv_player.v.teleport_time := 0;
  end;
  sv_player.v.velocity[0] := sv_player.v.movedir[0];
  sv_player.v.velocity[1] := sv_player.v.movedir[1];
end;


(*
===================
SV_AirMove

===================
*)

procedure SV_AirMove;
var
  i: integer;
  wishvel: TVector3f;
  fmove, smove: single;
begin
  AngleVectors(@sv_player.v.angles, @fwd, @right, @up);

  fmove := usrcmd.forwardmove;
  smove := usrcmd.sidemove;

// hack to not let you back into teleporter
  if (sv.time < sv_player.v.teleport_time) and (fmove < 0) then
    fmove := 0;

  for i := 0 to 2 do
    wishvel[i] := fwd[i] * fmove + right[i] * smove;

  if intval(sv_player.v.movetype) <> MOVETYPE_WALK then
    wishvel[2] := usrcmd.upmove
  else
    wishvel[2] := 0;

  VectorCopy(@wishvel, @wishdir);
  wishspeed := VectorNormalize(@wishdir);
  if wishspeed > sv_maxspeed.value then
  begin
    VectorScale(@wishvel, sv_maxspeed.value / wishspeed, @wishvel);
    wishspeed := sv_maxspeed.value;
  end;

  if sv_player.v.movetype = MOVETYPE_NOCLIP then
  begin // noclip
    VectorCopy(@wishvel, PVector3f(velocity))
  end
  else if onground then
  begin
    SV_UserFriction;
    SV_DoAccelerate;
  end
  else
  begin // not on ground, so little effect on velocity
    SV_AirAccelerate(@wishvel);
  end;
end;

(*
===================
SV_ClientThink

the move fields specify an intended velocity in pix/sec
the angle fields specify an exact angular motion in degrees
===================
*)

procedure SV_ClientThink;
var
  v_angle: TVector3f;
begin
  if sv_player.v.movetype = MOVETYPE_NONE then
    exit;

  onground := intval(sv_player.v.flags) and FL_ONGROUND <> 0;

  origin := @sv_player.v.origin;
  velocity := @sv_player.v.velocity;

  DropPunchAngle;

//
// if dead, behave differently
//
  if sv_player.v.health <= 0 then
    exit;

//
// angles
// show 1/3 the pitch angle and all the roll angle
  usrcmd := host_client.cmd;
  angles := @sv_player.v.angles;

  VectorAdd(@sv_player.v.v_angle, @sv_player.v.punchangle, @v_angle);
  angles[ROLL] := V_CalcRoll(@sv_player.v.angles, @sv_player.v.velocity) * 4;
  if sv_player.v.fixangle = 0 then
  begin
    angles[PITCH] := -v_angle[PITCH] / 3;
    angles[YAW] := v_angle[YAW];
  end;

  if intval(sv_player.v.flags) and FL_WATERJUMP <> 0 then
  begin
    SV_WaterJump;
    exit;
  end;
//
// walk
//
  if (sv_player.v.waterlevel >= 2) and
    (sv_player.v.movetype <> MOVETYPE_NOCLIP) then
  begin
    SV_WaterMove;
    exit;
  end;

  SV_AirMove;
end;


(*
===================
SV_ReadClientMove
===================
*)

procedure SV_ReadClientMove(move: Pusercmd_t);
var
  i: integer;
  angle: TVector3f;
  bits: integer;
begin

// read ping time
  host_client.ping_times[host_client.num_pings mod NUM_PING_TIMES] :=
    sv.time - MSG_ReadFloat;
  host_client.num_pings := host_client.num_pings + 1;

// read current angles
  for i := 0 to 2 do
    angle[i] := MSG_ReadAngle;

  VectorCopy(@angle, @host_client.edict.v.v_angle);

// read movement
  move.forwardmove := MSG_ReadShort;
  move.sidemove := MSG_ReadShort;
  move.upmove := MSG_ReadShort;

// read buttons
  bits := MSG_ReadByte;
  host_client.edict.v.button0 := bits and 1;
  host_client.edict.v.button2 := (bits and 2) div 2;

  i := MSG_ReadByte;
  if i <> 0 then
    host_client.edict.v.impulse := i;

end;

(*
===================
SV_ReadClientMessage

Returns false if the client should be killed
===================
*)

function SV_ReadClientMessage: qboolean;
label
  nextmsg;
var
  ret: integer;
  cmdnum: integer;
  s: PChar;
begin
  repeat
    nextmsg:
    ret := NET_GetMessage(host_client.netconnection);
    if ret = -1 then
    begin
      Sys_Printf('SV_ReadClientMessage: NET_GetMessage failed'#10);
      result := false;
      exit;
    end;
    if ret = 0 then
    begin
      result := true;
      exit;
    end;

    MSG_BeginReading;

    while true do
    begin
      if not host_client.active then
      begin
        result := false; // a command caused an error
        exit;
      end;

      if msg_badread then
      begin
        Sys_Printf('SV_ReadClientMessage: badread'#10);
        result := false;
        exit;
      end;

      cmdnum := MSG_ReadChar;

      case cmdnum of
        -1: goto nextmsg; // end of message

        clc_nop: ;
//        Sys_Printf ("clc_nop\n");

        clc_stringcmd:
          begin
            s := MSG_ReadString;
            if host_client.privileged then
              ret := 2
            else
              ret := 0;
            if Q_strncasecmp(s, 'status', 6) = 0 then
              ret := 1
            else if Q_strncasecmp(s, 'god', 3) = 0 then
              ret := 1
            else if Q_strncasecmp(s, 'notarget', 8) = 0 then
              ret := 1
            else if Q_strncasecmp(s, 'fly', 3) = 0 then
              ret := 1
            else if Q_strncasecmp(s, 'name', 4) = 0 then
              ret := 1
            else if Q_strncasecmp(s, 'noclip', 6) = 0 then
              ret := 1
            else if Q_strncasecmp(s, 'say', 3) = 0 then
              ret := 1
            else if Q_strncasecmp(s, 'say_team', 8) = 0 then
              ret := 1
            else if Q_strncasecmp(s, 'tell', 4) = 0 then
              ret := 1
            else if Q_strncasecmp(s, 'color', 5) = 0 then
              ret := 1
            else if Q_strncasecmp(s, 'kill', 4) = 0 then
              ret := 1
            else if Q_strncasecmp(s, 'pause', 5) = 0 then
              ret := 1
            else if Q_strncasecmp(s, 'spawn', 5) = 0 then
              ret := 1
            else if Q_strncasecmp(s, 'begin', 5) = 0 then
              ret := 1
            else if Q_strncasecmp(s, 'prespawn', 8) = 0 then
              ret := 1
            else if Q_strncasecmp(s, 'kick', 4) = 0 then
              ret := 1
            else if Q_strncasecmp(s, 'ping', 4) = 0 then
              ret := 1
            else if Q_strncasecmp(s, 'give', 4) = 0 then
              ret := 1
            else if Q_strncasecmp(s, 'ban', 3) = 0 then
              ret := 1;
            if ret = 2 then
              Cbuf_InsertText(s)
            else if ret = 1 then
              Cmd_ExecuteString(s, src_client)
            else
              Con_DPrintf('%s tried to %s'#10, [host_client.name, s]);
          end;

        clc_disconnect:
          begin
//        Sys_Printf ("SV_ReadClientMessage: client disconnected\n");
            result := false;
            exit;
          end;

        clc_move:
          begin
            SV_ReadClientMove(@host_client.cmd);
          end;
      else
        begin
          Sys_Printf('SV_ReadClientMessage: unknown command char'#10);
          result := false;
          exit;
        end;
      end;

    end;
  until ret <> 1;

  result := true;
end;


(*
==================
SV_RunClients
==================
*)

procedure SV_RunClients;
label
  continue1;
var
  i: integer;
begin
  host_client := @svs.clients[0];
  for i := 0 to svs.maxclients - 1 do
  begin
    if not host_client.active then
      goto continue1;

    sv_player := host_client.edict;

    if not SV_ReadClientMessage then
    begin
      SV_DropClient(false); // client misbehaved...
      goto continue1;
    end;

    if not host_client.spawned then
    begin
    // clear client movement until a new packet is received
      ZeroMemory(@host_client.cmd, SizeOf(host_client.cmd));
      goto continue1;
    end;

// always pause in single player if in console or menus
    if not sv.paused and ((svs.maxclients > 1) or (key_dest = key_game)) then
      SV_ClientThink;
    continue1:
    inc(host_client);
  end;
end;


end.

