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

unit cl_input;

interface

uses
  client,
  cvar;

(*
===============================================================================

KEY BUTTONS

Continuous button event tracking is complicated by the fact that two different
input sources (say, mouse button 1 and the control key) can both press the
same button, but the button should only be released when both of the
pressing key have been released.

When a key event issues a button command (+forward, +attack, etc), it appends
its key number as a parameter to the command so it can be matched up with
the release.

state bit 0 is the current state of the key
state bit 1 is edge triggered on the up to down transition
state bit 2 is edge triggered on the down to up transition

===============================================================================
*)

procedure KeyDown(b: Pkbutton_t);
procedure KeyUp(b: Pkbutton_t);
procedure CL_InitInput;
procedure CL_BaseMove(cmd: Pusercmd_t);
procedure CL_SendMove(cmd: Pusercmd_t);

//==========================================================================

var
  cl_upspeed: cvar_t = (name: 'cl_upspeed'; text: '200');
  cl_forwardspeed: cvar_t = (name: 'cl_forwardspeed'; text: '200'; archive: true);
  cl_backspeed: cvar_t = (name: 'cl_backspeed'; text: '200'; archive: true);
  cl_sidespeed: cvar_t = (name: 'cl_sidespeed'; text: '350');

  cl_movespeedkey: cvar_t = (name: 'cl_movespeedkey'; text: '2.0');

  cl_yawspeed: cvar_t = (name: 'cl_yawspeed'; text: '140');
  cl_pitchspeed: cvar_t = (name: 'cl_pitchspeed'; text: '150');

  cl_anglespeedkey: cvar_t = (name: 'cl_anglespeedkey'; text: '1.5');

var
  in_mlook: kbutton_t;
  in_strafe, in_speed: kbutton_t;

implementation

uses
  q_delphi,
  cmd,
  console,
  cl_main_h,
  view,
  common,
  host_h,
  quakedef,
  mathlib,
  protocol,
  net_main,
  cl_main;

var
  in_klook: kbutton_t;
  in_left, in_right, in_forward, in_back: kbutton_t;
  in_lookup, in_lookdown, in_moveleft, in_moveright: kbutton_t;
  in_use, in_jump, in_attack: kbutton_t;
  in_up, in_down: kbutton_t;

  _in_impulse: integer;

procedure KeyDown(b: Pkbutton_t);
var
  k: integer;
  c: PChar;
begin
  c := Cmd_Argv_f(1);
  if c[0] <> #0 then
    k := atoi(c)
  else
    k := -1;

  if (k = b.down[0]) or (k = b.down[1]) then
    exit;

  if b.down[0] = 0 then
    b.down[0] := k
  else

    if b.down[1] = 0 then
      b.down[1] := k
    else
    begin
      Con_Printf('Three keys down for a button!\n');
      exit;
    end;

  if b.state and 1 = 0 then
    b.state := b.state or (1 + 2);
end;

procedure KeyUp(b: Pkbutton_t);
var
  k: integer;
  c: PChar;
begin
  c := Cmd_Argv_f(1);

  if c[0] <> #0 then
    k := atoi(c)
  else
  begin
    b.down[0] := 0;
    b.down[1] := 0;
    b.state := 4;
    exit;
  end;

  if b.down[0] = k then
    b.down[0] := 0
  else

    if b.down[1] = k then
      b.down[1] := 0
    else
      exit;

  if (b.down[0] <> 0) or (b.down[1] <> 0) then
    exit;

  if b.state and 1 <> 0 then
  begin
    b.state := b.state and (not 1);
    b.state := b.state or 4;
  end;
end;

procedure IN_KLookDown;
begin
  KeyDown(@in_klook);
end;

procedure IN_KLookUp;
begin
  KeyUp(@in_klook);
end;

procedure IN_MLookDown;
begin
  KeyDown(@in_mlook);
end;

procedure IN_MLookUp;
begin
  KeyUp(@in_mlook);
  if not boolval(in_mlook.state and 1) and boolval(lookspring.value) then
    V_StartPitchDrift;
end;

procedure IN_UpDown;
begin
  KeyDown(@in_up);
end;

procedure IN_UpUp;
begin
  KeyUp(@in_up);
end;

procedure IN_DownDown;
begin
  KeyDown(@in_down);
end;

procedure IN_DownUp;
begin
  KeyUp(@in_down);
end;

procedure IN_LeftDown;
begin
  KeyDown(@in_left);
end;

procedure IN_LeftUp;
begin
  KeyUp(@in_left);
end;

procedure IN_RightDown;
begin
  KeyDown(@in_right);
end;

procedure IN_RightUp;
begin
  KeyUp(@in_right);
end;

procedure IN_ForwardDown;
begin
  KeyDown(@in_forward);
end;

procedure IN_ForwardUp;
begin
  KeyUp(@in_forward);
end;

procedure IN_BackDown;
begin
  KeyDown(@in_back);
end;

procedure IN_BackUp;
begin
  KeyUp(@in_back);
end;

procedure IN_LookupDown;
begin
  KeyDown(@in_lookup);
end;

procedure IN_LookupUp;
begin
  KeyUp(@in_lookup);
end;

procedure IN_LookdownDown;
begin
  KeyDown(@in_lookdown);
end;

procedure IN_LookdownUp;
begin
  KeyUp(@in_lookdown);
end;

procedure IN_MoveleftDown;
begin
  KeyDown(@in_moveleft);
end;

procedure IN_MoveleftUp;
begin
  KeyUp(@in_moveleft);
end;

procedure IN_MoverightDown;
begin
  KeyDown(@in_moveright);
end;

procedure IN_MoverightUp;
begin
  KeyUp(@in_moveright);
end;

procedure IN_SpeedDown;
begin
  KeyDown(@in_speed);
end;

procedure IN_SpeedUp;
begin
  KeyUp(@in_speed);
end;

procedure IN_StrafeDown;
begin
  KeyDown(@in_strafe);
end;

procedure IN_StrafeUp;
begin
  KeyUp(@in_strafe);
end;

procedure IN_AttackDown;
begin
  KeyDown(@in_attack);
end;

procedure IN_AttackUp;
begin
  KeyUp(@in_attack);
end;

procedure IN_UseDown;
begin
  KeyDown(@in_use);
end;

procedure IN_UseUp;
begin
  KeyUp(@in_use);
end;

procedure IN_JumpDown;
begin
  KeyDown(@in_jump);
end;

procedure IN_JumpUp;
begin
  KeyUp(@in_jump);
end;

procedure IN_Impulse;
begin
  _in_impulse := Q_atoi(Cmd_Argv_f(1));
end;

(*
===============
CL_KeyState

Returns 0.25 if a key was pressed and released during the frame,
0.5 if it was pressed and held
0 if held then released, and
1.0 if held for the entire time
===============
*)

function CL_KeyState(key: Pkbutton_t): single;
var
  impulsedown, impulseup, down: qboolean;
  val: single;
begin
  impulsedown := Boolval(key.state and 2);
  impulseup := Boolval(key.state and 4);
  down := Boolval(key.state and 1);
  val := 0;

  if impulsedown and (not impulseup) then

    if down then
      val := 0.5
    else
      val := 0;

  if impulseup and (not impulsedown) then

    if down then
      val := 0
    else
      val := 0;

  if (not impulsedown) and (not impulseup) then

    if down then
      val := 1.0
    else
      val := 0;

  if impulsedown and impulseup then

    if down then
      val := 0.75
    else
      val := 0.25;

  key.state := key.state and 1;

  Result := val;
end;

(*
================
CL_AdjustAngles

Moves the local angle positions
================
*)

procedure CL_AdjustAngles;
var
  speed: single;
  up, down: single;
begin
  if boolval(in_speed.state and 1) then
    speed := host_frametime * cl_anglespeedkey.value
  else
    speed := host_frametime;

  if not boolval(in_strafe.state and 1) then
  begin
    cl.viewangles[YAW] := cl.viewangles[YAW] - speed * cl_yawspeed.value * CL_KeyState(@in_right);
    cl.viewangles[YAW] := cl.viewangles[YAW] + speed * cl_yawspeed.value * CL_KeyState(@in_left);
    cl.viewangles[YAW] := anglemod(cl.viewangles[YAW]);
  end;

  if boolval(in_klook.state and 1) then
  begin
    V_StopPitchDrift();
    cl.viewangles[PITCH] := cl.viewangles[PITCH] - speed * cl_pitchspeed.value * CL_KeyState(@in_forward);
    cl.viewangles[PITCH] := cl.viewangles[PITCH] + speed * cl_pitchspeed.value * CL_KeyState(@in_back);
  end;
  up := CL_KeyState(@in_lookup);
  down := CL_KeyState(@in_lookdown);
  cl.viewangles[PITCH] := cl.viewangles[PITCH] - speed * cl_pitchspeed.value * up;
  cl.viewangles[PITCH] := cl.viewangles[PITCH] + speed * cl_pitchspeed.value * down;

  if (up <> 0) or (down <> 0) then
    V_StopPitchDrift();

  if cl.viewangles[PITCH] > 80 then
    cl.viewangles[PITCH] := 80;

  if cl.viewangles[PITCH] < -70 then
    cl.viewangles[PITCH] := -70;

  if cl.viewangles[ROLL] > 50 then
    cl.viewangles[ROLL] := 50;

  if cl.viewangles[ROLL] < -50 then
    cl.viewangles[ROLL] := -50;
end;

(*
================
CL_BaseMove

Send the intended movement message to the server
================
*)

procedure CL_BaseMove(cmd: Pusercmd_t);
begin
  if cls.signon <> SIGNONS then
    exit;

  CL_AdjustAngles();
  ZeroMemory(cmd, sizeof(cmd^));

  if boolval(in_strafe.state and 1) then
  begin
    cmd.sidemove := cmd.sidemove + cl_sidespeed.value * CL_KeyState(@in_right);
    cmd.sidemove := cmd.sidemove - cl_sidespeed.value * CL_KeyState(@in_left);
  end;
  cmd.sidemove := cmd.sidemove + cl_sidespeed.value * CL_KeyState(@in_moveright);
  cmd.sidemove := cmd.sidemove - cl_sidespeed.value * CL_KeyState(@in_moveleft);
  cmd.upmove := cmd.upmove + cl_upspeed.value * CL_KeyState(@in_up);
  cmd.upmove := cmd.upmove - cl_upspeed.value * CL_KeyState(@in_down);

  if not Boolval(in_klook.state and 1) then
  begin
    cmd.forwardmove := cmd.forwardmove + cl_forwardspeed.value * CL_KeyState(@in_forward);
    cmd.forwardmove := cmd.forwardmove - cl_backspeed.value * CL_KeyState(@in_back);
  end;

  if Boolval(in_speed.state and 1) then
  begin
    cmd.forwardmove := cmd.forwardmove * cl_movespeedkey.value;
    cmd.sidemove := cmd.sidemove * cl_movespeedkey.value;
    cmd.upmove := cmd.upmove * cl_movespeedkey.value;
  end;
end;



(*
==============
CL_SendMove
==============
*)

procedure CL_SendMove(cmd: Pusercmd_t);
var
  i: integer;
  bits: integer;
  buf: sizebuf_t;
  data: array[0..127] of byte;
begin
  buf.maxsize := 128;
  buf.cursize := 0;
  buf.data := @data;

  cl.cmd := cmd^;

//
// send the movement message
//
  MSG_WriteByte(@buf, clc_move);

  MSG_WriteFloat(@buf, cl.mtime[0]); // so server can get ping times

  for i := 0 to 2 do
    MSG_WriteAngle(@buf, cl.viewangles[i]);

  MSG_WriteShort(@buf, intval(cmd.forwardmove));
  MSG_WriteShort(@buf, intval(cmd.sidemove));
  MSG_WriteShort(@buf, intval(cmd.upmove));

//
// send button bits
//
  bits := 0;

  if in_attack.state and 3 <> 0 then
    bits := bits or 1;
  in_attack.state := in_attack.state and (not 2);

  if in_jump.state and 3 <> 0 then
    bits := bits or 2;
  in_jump.state := in_jump.state and (not 2);

  MSG_WriteByte(@buf, bits);

  MSG_WriteByte(@buf, _in_impulse);
  _in_impulse := 0;

//
// deliver the message
//
  if cls.demoplayback then
    exit;

//
// allways dump the first two message, because it may contain leftover inputs
// from the last level
//
  inc(cl.movemessages);
  if cl.movemessages <= 2 then
    exit;

  if NET_SendUnreliableMessage(cls.netcon, @buf) = -1 then
  begin
    Con_Printf('CL_SendMove: lost server connection'#10);
    CL_Disconnect;
  end;
end;

(*
============
CL_InitInput
============
*)

procedure CL_InitInput;
begin
  Cmd_AddCommand('+moveup', IN_UpDown);
  Cmd_AddCommand('-moveup', IN_UpUp);
  Cmd_AddCommand('+movedown', IN_DownDown);
  Cmd_AddCommand('-movedown', IN_DownUp);
  Cmd_AddCommand('+left', IN_LeftDown);
  Cmd_AddCommand('-left', IN_LeftUp);
  Cmd_AddCommand('+right', IN_RightDown);
  Cmd_AddCommand('-right', IN_RightUp);
  Cmd_AddCommand('+forward', IN_ForwardDown);
  Cmd_AddCommand('-forward', IN_ForwardUp);
  Cmd_AddCommand('+back', IN_BackDown);
  Cmd_AddCommand('-back', IN_BackUp);
  Cmd_AddCommand('+lookup', IN_LookupDown);
  Cmd_AddCommand('-lookup', IN_LookupUp);
  Cmd_AddCommand('+lookdown', IN_LookdownDown);
  Cmd_AddCommand('-lookdown', IN_LookdownUp);
  Cmd_AddCommand('+strafe', IN_StrafeDown);
  Cmd_AddCommand('-strafe', IN_StrafeUp);
  Cmd_AddCommand('+moveleft', IN_MoveleftDown);
  Cmd_AddCommand('-moveleft', IN_MoveleftUp);
  Cmd_AddCommand('+moveright', IN_MoverightDown);
  Cmd_AddCommand('-moveright', IN_MoverightUp);
  Cmd_AddCommand('+speed', IN_SpeedDown);
  Cmd_AddCommand('-speed', IN_SpeedUp);
  Cmd_AddCommand('+attack', IN_AttackDown);
  Cmd_AddCommand('-attack', IN_AttackUp);
  Cmd_AddCommand('+use', IN_UseDown);
  Cmd_AddCommand('-use', IN_UseUp);
  Cmd_AddCommand('+jump', IN_JumpDown);
  Cmd_AddCommand('-jump', IN_JumpUp);
  Cmd_AddCommand('impulse', IN_Impulse);
  Cmd_AddCommand('+klook', IN_KLookDown);
  Cmd_AddCommand('-klook', IN_KLookUp);
  Cmd_AddCommand('+mlook', IN_MLookDown);
  Cmd_AddCommand('-mlook', IN_MLookUp);
end;


end.

