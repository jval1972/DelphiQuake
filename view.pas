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

unit view;

// view.c -- player eye positioning

interface

uses
  q_vector,
  cvar;

procedure V_UpdatePalette;
procedure V_RenderView;
procedure V_Init;
function V_CalcRoll(angles: PVector3f; velocity: PVector3f): single;
procedure V_StartPitchDrift;
procedure V_StopPitchDrift;
procedure V_SetContentsColor(contents: integer);
procedure V_CalcBlend;
procedure V_ParseDamage;

var
  ramps: array[0..2] of array[0..255] of byte;
  v_blend: array[0..3] of single; // rgba 0.0 - 1.0

var
  v_gamma: cvar_t = (name: 'gamma'; text: '1'; archive: true);
  crosshair: cvar_t = (name: 'crosshair'; text: '0'; archive: true);

implementation

uses
  q_delphi,
  bspconst,
  mathlib,
  host_cmd,
  cl_input,
  cl_main_h,
  host_h,
  quakedef,
  client,
  gl_vidnt,
  gl_model_h,
  common,
  cmd,
  gl_rmain,
  gl_screen,
  chase,
  console,
  gl_rlight, sv_user, server_h;

(*

The view is allowed to move slightly from it's true position for bobbing,
but if it exceeds 8 pixels linear distance (spherical, not box), the list of
entities sent from the server may not include everything in the pvs, especially
when crossing a water boudnary.

*)
var
  lcd_x: cvar_t = (name: 'lcd_x'; text: '0');
  lcd_yaw: cvar_t = (name: 'lcd_yaw'; text: '0');

  scr_ofsx: cvar_t = (name: 'scr_ofsx'; text: '0'; archive: false);
  scr_ofsy: cvar_t = (name: 'scr_ofsy'; text: '0'; archive: false);
  scr_ofsz: cvar_t = (name: 'scr_ofsz'; text: '0'; archive: false);

  cl_rollspeed: cvar_t = (name: 'cl_rollspeed'; text: '200');
  cl_rollangle: cvar_t = (name: 'cl_rollangle'; text: '2.0');

  cl_bob: cvar_t = (name: 'cl_bob'; text: '0.02'; archive: false);
  cl_bobcycle: cvar_t = (name: 'cl_bobcycle'; text: '0.6'; archive: false);
  cl_bobup: cvar_t = (name: 'cl_bobup'; text: '0.5'; archive: false);

  v_kicktime: cvar_t = (name: 'v_kicktime'; text: '0.5'; archive: false);
  v_kickroll: cvar_t = (name: 'v_kickroll'; text: '0.6'; archive: false);
  v_kickpitch: cvar_t = (name: 'v_kickpitch'; text: '0.6'; archive: false);

  v_iyaw_cycle: cvar_t = (name: 'v_iyaw_cycle'; text: '2'; archive: false);
  v_iroll_cycle: cvar_t = (name: 'v_iroll_cycle'; text: '0.5'; archive: false);
  v_ipitch_cycle: cvar_t = (name: 'v_ipitch_cycle'; text: '1'; archive: false);
  v_iyaw_level: cvar_t = (name: 'v_iyaw_level'; text: '0.3'; archive: false);
  v_iroll_level: cvar_t = (name: 'v_iroll_level'; text: '0.1'; archive: false);
  v_ipitch_level: cvar_t = (name: 'v_ipitch_level'; text: '0.3'; archive: false);

  v_idlescale: cvar_t = (name: 'v_idlescale'; text: '0'; archive: false);

  cl_crossx: cvar_t = (name: 'cl_crossx'; text: '0'; archive: false);
  cl_crossy: cvar_t = (name: 'cl_crossy'; text: '0'; archive: false);

  gl_cshiftpercent: cvar_t = (name: 'gl_cshiftpercent'; text: '100'; archive: false);

var
  v_dmg_time, v_dmg_roll, v_dmg_pitch: single;

(*
===============
V_CalcRoll

Used by view and sv_user
===============
*)
var
  _forward, right, up: TVector3f;

function V_CalcRoll(angles: PVector3f; velocity: PVector3f): single;
var
  sign: single;
  side: single;
  value: single;
begin
  AngleVectors(angles, @_forward, @right, @up);
  side := VectorDotProduct(velocity, @right);
  sign := decide(side < 0, -1, 1);
  side := abs(side);

  value := cl_rollangle.value;
//  if (cl.inwater)
//    value *= 6;

  if side < cl_rollspeed.value then
    side := side * value / cl_rollspeed.value
  else
    side := value;

  result := side * sign;
end;


(*
===============
V_CalcBob

===============
*)

function V_CalcBob: single;
var
  cycle: single;
begin
  cycle := cl.time - intval(cl.time / cl_bobcycle.value) * cl_bobcycle.value;
  cycle := cycle / cl_bobcycle.value;
  if cycle < cl_bobup.value then
    cycle := M_PI * cycle / cl_bobup.value
  else
    cycle := M_PI + M_PI * (cycle - cl_bobup.value) / (1.0 - cl_bobup.value);

// result is proportional to velocity in the xy plane
// (don't count Z, or jumping messes it up)

  result := sqrt(cl.velocity[0] * cl.velocity[0] + cl.velocity[1] * cl.velocity[1]) * cl_bob.value;
//Con_Printf('speed: %5.1f\n', Length(cl.velocity));
  result := result * 0.3 + result * 0.7 * sin(cycle);
  if result > 4 then
    result := 4
  else if result < -7 then
    result := -7;
end;


//=============================================================================

var
  v_centermove: cvar_t = (name: 'v_centermove'; text: '0.15'; archive: false);
  v_centerspeed: cvar_t = (name: 'v_centerspeed'; text: '500');


procedure V_StartPitchDrift;
begin
  if cl.laststop = cl.time then
    exit; // something else is keeping it from drifting

  if cl.nodrift or (cl.pitchvel = 0) then
  begin
    cl.pitchvel := v_centerspeed.value;
    cl.nodrift := false;
    cl.driftmove := 0;
  end;
end;

procedure V_StopPitchDrift;
begin
  cl.laststop := cl.time;
  cl.nodrift := true;
  cl.pitchvel := 0;
end;

(*
===============
V_DriftPitch

Moves the client pitch angle towards cl.idealpitch sent by the server.

If the user is adjusting pitch manually, either with lookup/lookdown,
mlook and mouse, or klook and keyboard, pitch drifting is constantly stopped.

Drifting is enabled when the center view key is hit, mlook is released and
lookspring is non 0, or when
===============
*)

procedure V_DriftPitch;
var
  delta, move: single;
begin
  if noclip_anglehack or (not cl.onground) or cls.demoplayback then
  begin
    cl.driftmove := 0;
    cl.pitchvel := 0;
    exit;
  end;

// don't count small mouse motion
  if cl.nodrift then
  begin
    if abs(cl.cmd.forwardmove) < cl_forwardspeed.value then
      cl.driftmove := 0
    else
      cl.driftmove := cl.driftmove + host_frametime;

    if cl.driftmove > v_centermove.value then
    begin
      V_StartPitchDrift;
    end;
    exit;
  end;

  delta := cl.idealpitch - cl.viewangles[PITCH];

  if delta = 0 then
  begin
    cl.pitchvel := 0;
    exit;
  end;

  move := host_frametime * cl.pitchvel;
  cl.pitchvel := cl.pitchvel + host_frametime * v_centerspeed.value;

//Con_Printf('move: %f (%f)\n', move, host_frametime);

  if delta > 0 then
  begin
    if move > delta then
    begin
      cl.pitchvel := 0;
      move := delta;
    end;
    cl.viewangles[PITCH] := cl.viewangles[PITCH] + move;
  end
  else if delta < 0 then
  begin
    if move > -delta then
    begin
      cl.pitchvel := 0;
      move := -delta;
    end;
    cl.viewangles[PITCH] := cl.viewangles[PITCH] - move;
  end;
end;





(*
==============================================================================

            PALETTE FLASHES

==============================================================================
*)

var
  cshift_empty: cshift_t = (destcolor: (130, 80, 50); percent: 0);
  cshift_water: cshift_t = (destcolor: (130, 80, 50); percent: 128);
  cshift_slime: cshift_t = (destcolor: (0, 25, 5); percent: 150);
  cshift_lava: cshift_t = (destcolor: (255, 80, 0); percent: 150);

var
  gammatable: array[0..255] of byte; // palette is sent through this

procedure BuildGammaTable(g: single);
var
  i, inf: integer;
begin
  if g = 1.0 then
  begin
    for i := 0 to 255 do
      gammatable[i] := i;
    exit;
  end;

  for i := 0 to 255 do
  begin
    inf := intval(255 * fpow((i + 0.5) / 255.5, g) + 0.5);
    if inf < 0 then
      inf := 0
    else if inf > 255 then
      inf := 255;
    gammatable[i] := inf;
  end;
end;

(*
=================
V_CheckGamma
=================
*)
var
  oldgammavalue: single;

function V_CheckGamma: qboolean;
begin
  if v_gamma.value = oldgammavalue then
  begin
    result := false;
    exit;
  end;

  oldgammavalue := v_gamma.value;

  BuildGammaTable(v_gamma.value);
  vid.recalc_refdef := true; // force a surface cache flush

  result := true;
end;



(*
===============
V_ParseDamage
===============
*)

procedure V_ParseDamage;
var
  armor, blood: integer;
  from: TVector3f;
  i: integer;
  _forward, right, up: TVector3f;
  ent: Pentity_t;
  side: single;
  count: single;
begin
  armor := MSG_ReadByte;
  blood := MSG_ReadByte;
  for i := 0 to 2 do
    from[i] := MSG_ReadCoord;

  count := blood * 0.5 + armor * 0.5;
  if count < 10 then
    count := 10;

  cl.faceanimtime := cl.time + 0.2; // but sbar face into pain frame

  cl.cshifts[CSHIFT_DAMAGE].percent := cl.cshifts[CSHIFT_DAMAGE].percent + intval(3 * count);
  if cl.cshifts[CSHIFT_DAMAGE].percent < 0 then
    cl.cshifts[CSHIFT_DAMAGE].percent := 0
  else if cl.cshifts[CSHIFT_DAMAGE].percent > 150 then
    cl.cshifts[CSHIFT_DAMAGE].percent := 150;

  if armor > blood then
  begin
    cl.cshifts[CSHIFT_DAMAGE].destcolor[0] := 200;
    cl.cshifts[CSHIFT_DAMAGE].destcolor[1] := 100;
    cl.cshifts[CSHIFT_DAMAGE].destcolor[2] := 100;
  end
  else if armor <> 0 then
  begin
    cl.cshifts[CSHIFT_DAMAGE].destcolor[0] := 220;
    cl.cshifts[CSHIFT_DAMAGE].destcolor[1] := 50;
    cl.cshifts[CSHIFT_DAMAGE].destcolor[2] := 50;
  end
  else
  begin
    cl.cshifts[CSHIFT_DAMAGE].destcolor[0] := 255;
    cl.cshifts[CSHIFT_DAMAGE].destcolor[1] := 0;
    cl.cshifts[CSHIFT_DAMAGE].destcolor[2] := 0;
  end;

//
// calculate view angle kicks
//
  ent := @cl_entities[cl.viewentity];

  VectorSubtract(@from, @ent.origin, @from);
  VectorNormalize(@from);

  AngleVectors(@ent.angles, @_forward, @right, @up);

  side := VectorDotProduct(@from, @right);
  v_dmg_roll := count * side * v_kickroll.value;

  side := VectorDotProduct(@from, @_forward);
  v_dmg_pitch := count * side * v_kickpitch.value;

  v_dmg_time := v_kicktime.value;
end;


(*
==================
V_cshift_f
==================
*)

procedure V_cshift_f;
begin
  cshift_empty.destcolor[0] := atoi(Cmd_Argv_f(1));
  cshift_empty.destcolor[1] := atoi(Cmd_Argv_f(2));
  cshift_empty.destcolor[2] := atoi(Cmd_Argv_f(3));
  cshift_empty.percent := atoi(Cmd_Argv_f(4));
end;


(*
==================
V_BonusFlash_f

When you run over an item, the server sends this command
==================
*)

procedure V_BonusFlash_f;
begin
  cl.cshifts[CSHIFT_BONUS].destcolor[0] := 215;
  cl.cshifts[CSHIFT_BONUS].destcolor[1] := 186;
  cl.cshifts[CSHIFT_BONUS].destcolor[2] := 69;
  cl.cshifts[CSHIFT_BONUS].percent := 50;
end;

(*
=============
V_SetContentsColor

Underwater, lava, etc each has a color shift
=============
*)

procedure V_SetContentsColor(contents: integer);
begin
  case contents of
    CONTENTS_EMPTY,
      CONTENTS_SOLID:
      cl.cshifts[CSHIFT_CONTENTS] := cshift_empty;

    CONTENTS_LAVA:
      cl.cshifts[CSHIFT_CONTENTS] := cshift_lava;

    CONTENTS_SLIME:
      cl.cshifts[CSHIFT_CONTENTS] := cshift_slime;

  else
    cl.cshifts[CSHIFT_CONTENTS] := cshift_water;
  end;
end;

(*
=============
V_CalcPowerupCshift
=============
*)

procedure V_CalcPowerupCshift;
begin
  if cl.items and IT_QUAD <> 0 then
  begin
    cl.cshifts[CSHIFT_POWERUP].destcolor[0] := 0;
    cl.cshifts[CSHIFT_POWERUP].destcolor[1] := 0;
    cl.cshifts[CSHIFT_POWERUP].destcolor[2] := 255;
    cl.cshifts[CSHIFT_POWERUP].percent := 30;
  end
  else if cl.items and IT_SUIT <> 0 then
  begin
    cl.cshifts[CSHIFT_POWERUP].destcolor[0] := 0;
    cl.cshifts[CSHIFT_POWERUP].destcolor[1] := 255;
    cl.cshifts[CSHIFT_POWERUP].destcolor[2] := 0;
    cl.cshifts[CSHIFT_POWERUP].percent := 20;
  end
  else if cl.items and IT_INVISIBILITY <> 0 then
  begin
    cl.cshifts[CSHIFT_POWERUP].destcolor[0] := 100;
    cl.cshifts[CSHIFT_POWERUP].destcolor[1] := 100;
    cl.cshifts[CSHIFT_POWERUP].destcolor[2] := 100;
    cl.cshifts[CSHIFT_POWERUP].percent := 100;
  end
  else if cl.items and IT_INVULNERABILITY <> 0 then
  begin
    cl.cshifts[CSHIFT_POWERUP].destcolor[0] := 255;
    cl.cshifts[CSHIFT_POWERUP].destcolor[1] := 255;
    cl.cshifts[CSHIFT_POWERUP].destcolor[2] := 0;
    cl.cshifts[CSHIFT_POWERUP].percent := 30;
  end
  else
    cl.cshifts[CSHIFT_POWERUP].percent := 0;
end;

(*
=============
V_CalcBlend
=============
*)

procedure V_CalcBlend;
var
  r, g, b, a, a2: single;
  j: integer;
begin
  r := 0;
  g := 0;
  b := 0;
  a := 0;

  for j := 0 to NUM_CSHIFTS - 1 do
  begin
    if gl_cshiftpercent.value = 0 then
      continue;

    a2 := ((cl.cshifts[j].percent * gl_cshiftpercent.value) / 100.0) / 255.0;

    if a2 = 0.0 then
      continue;
    a := a + a2 * (1 - a);
    a2 := a2 / a;
    r := r * (1 - a2) + cl.cshifts[j].destcolor[0] * a2;
    g := g * (1 - a2) + cl.cshifts[j].destcolor[1] * a2;
    b := b * (1 - a2) + cl.cshifts[j].destcolor[2] * a2;
  end;

  v_blend[0] := r / 255.0;
  v_blend[1] := g / 255.0;
  v_blend[2] := b / 255.0;
  v_blend[3] := a;
  if v_blend[3] > 1 then
    v_blend[3] := 1
  else if v_blend[3] < 0 then
    v_blend[3] := 0;
end;

(*
=============
V_UpdatePalette
=============
*)

procedure V_UpdatePalette;
var
  i, j: integer;
  _new: qboolean;
  basepal, newpal: PByteArray;
  pal: array[0..767] of byte;
  r, g, b, a: single;
  ir, ig, ib: integer;
  force: qboolean;
begin
  V_CalcPowerupCshift;

  _new := false;

  for i := 0 to NUM_CSHIFTS - 1 do
  begin
    if cl.cshifts[i].percent <> cl.prev_cshifts[i].percent then
    begin
      _new := true;
      cl.prev_cshifts[i].percent := cl.cshifts[i].percent;
    end;
    for j := 0 to 2 do
      if cl.cshifts[i].destcolor[j] <> cl.prev_cshifts[i].destcolor[j] then
      begin
        _new := true;
        cl.prev_cshifts[i].destcolor[j] := cl.cshifts[i].destcolor[j];
      end;
  end;

// drop the damage value
  cl.cshifts[CSHIFT_DAMAGE].percent := cl.cshifts[CSHIFT_DAMAGE].percent - intval(host_frametime * 150);
  if cl.cshifts[CSHIFT_DAMAGE].percent <= 0 then
    cl.cshifts[CSHIFT_DAMAGE].percent := 0;

// drop the bonus value
  cl.cshifts[CSHIFT_BONUS].percent := cl.cshifts[CSHIFT_BONUS].percent - intval(host_frametime * 100);
  if cl.cshifts[CSHIFT_BONUS].percent <= 0 then
    cl.cshifts[CSHIFT_BONUS].percent := 0;

  force := V_CheckGamma;
  if not _new and not force then
    exit;

  V_CalcBlend;

  a := v_blend[3];
  r := 255 * v_blend[0] * a;
  g := 255 * v_blend[1] * a;
  b := 255 * v_blend[2] * a;

  a := 1 - a;
  for i := 0 to 255 do
  begin
    ir := intval(i * a + r);
    ig := intval(i * a + g);
    ib := intval(i * a + b);
    if ir > 255 then
      ir := 255;
    if ig > 255 then
      ig := 255;
    if ib > 255 then
      ib := 255;

    ramps[0][i] := gammatable[ir];
    ramps[1][i] := gammatable[ig];
    ramps[2][i] := gammatable[ib];
  end;

  basepal := host_basepal;
  newpal := @pal;

  for i := 0 to 255 do
  begin
    ir := basepal[0];
    ig := basepal[1];
    ib := basepal[2];
    basepal := @basepal[3];

    newpal[0] := ramps[0][ir];
    newpal[1] := ramps[1][ig];
    newpal[2] := ramps[2][ib];
    newpal := @newpal[3];
  end;

end;

(*
==============================================================================

            VIEW RENDERING

==============================================================================
*)

function angledelta(a: single): single;
begin
  result := anglemod(a);
  if result > 180 then
    result := result - 360;
end;

(*
==================
CalcGunAngle
==================
*)
var
  oldyaw: single = 0.0;
  oldpitch: single = 0.0;

procedure CalcGunAngle;
var
  _yaw, _pitch, _move: single;
begin
  _yaw := r_refdef.viewangles[YAW];
  _pitch := -r_refdef.viewangles[PITCH];

  _yaw := angledelta(_yaw - r_refdef.viewangles[YAW]) * 0.4;
  if _yaw > 10 then
    _yaw := 10
  else if _yaw < -10 then
    _yaw := -10;
  _pitch := angledelta(-_pitch - r_refdef.viewangles[PITCH]) * 0.4;
  if _pitch > 10 then
    _pitch := 10
  else if _pitch < -10 then
    _pitch := -10;
  _move := host_frametime * 20;
  if _yaw > oldyaw then
  begin
    if oldyaw + _move < _yaw then
      _yaw := oldyaw + _move;
  end
  else
  begin
    if oldyaw - _move > _yaw then
      _yaw := oldyaw - _move;
  end;

  if _pitch > oldpitch then
  begin
    if oldpitch + _move < _pitch then
      _pitch := oldpitch + _move;
  end
  else
  begin
    if oldpitch - _move > _pitch then
      _pitch := oldpitch - _move;
  end;

  oldyaw := _yaw;
  oldpitch := _pitch;

  cl.viewent.angles[YAW] := r_refdef.viewangles[YAW] + _yaw;
  cl.viewent.angles[PITCH] := -(r_refdef.viewangles[PITCH] + _pitch);

  cl.viewent.angles[ROLL] := cl.viewent.angles[ROLL] -
    v_idlescale.value * sin(cl.time * v_iroll_cycle.value) * v_iroll_level.value;
  cl.viewent.angles[PITCH] := cl.viewent.angles[PITCH] -
    v_idlescale.value * sin(cl.time * v_ipitch_cycle.value) * v_ipitch_level.value;
  cl.viewent.angles[YAW] := cl.viewent.angles[YAW] -
    v_idlescale.value * sin(cl.time * v_iyaw_cycle.value) * v_iyaw_level.value;
end;

(*
==============
V_BoundOffsets
==============
*)

procedure V_BoundOffsets;
var
  ent: Pentity_t;
begin
  ent := @cl_entities[cl.viewentity];

// absolutely bound refresh reletive to entity clipping hull
// so the view can never be inside a solid wall

  if r_refdef.vieworg[0] < ent.origin[0] - 14 then
    r_refdef.vieworg[0] := ent.origin[0] - 14
  else if r_refdef.vieworg[0] > ent.origin[0] + 14 then
    r_refdef.vieworg[0] := ent.origin[0] + 14;
  if r_refdef.vieworg[1] < ent.origin[1] - 14 then
    r_refdef.vieworg[1] := ent.origin[1] - 14
  else if r_refdef.vieworg[1] > ent.origin[1] + 14 then
    r_refdef.vieworg[1] := ent.origin[1] + 14;
  if r_refdef.vieworg[2] < ent.origin[2] - 22 then
    r_refdef.vieworg[2] := ent.origin[2] - 22
  else if r_refdef.vieworg[2] > ent.origin[2] + 30 then
    r_refdef.vieworg[2] := ent.origin[2] + 30;
end;

(*
==============
V_AddIdle

Idle swaying
==============
*)

procedure V_AddIdle;
begin
  r_refdef.viewangles[ROLL] := r_refdef.viewangles[ROLL] +
    v_idlescale.value * sin(cl.time * v_iroll_cycle.value) * v_iroll_level.value;
  r_refdef.viewangles[PITCH] := r_refdef.viewangles[PITCH] +
    v_idlescale.value * sin(cl.time * v_ipitch_cycle.value) * v_ipitch_level.value;
  r_refdef.viewangles[YAW] := r_refdef.viewangles[YAW] +
    v_idlescale.value * sin(cl.time * v_iyaw_cycle.value) * v_iyaw_level.value;
end;


(*
==============
V_CalcViewRoll

Roll is induced by movement and damage
==============
*)

procedure V_CalcViewRoll;
var
  side: single;
begin
  side := V_CalcRoll(@cl_entities[cl.viewentity].angles, @cl.velocity);
  r_refdef.viewangles[ROLL] := r_refdef.viewangles[ROLL] + side;

  if sv_player <> nil then
    if intval(sv_player.v.flags) and FL_GODMODE <> 0 then
      exit; // JVAL added handling when in god mod

  if v_dmg_time > 0 then // JVAL here correct the god mod bug inside water ???
  begin
    r_refdef.viewangles[ROLL] := r_refdef.viewangles[ROLL] +
      v_dmg_time / v_kicktime.value * v_dmg_roll;
    r_refdef.viewangles[PITCH] := r_refdef.viewangles[PITCH] +
      v_dmg_time / v_kicktime.value * v_dmg_pitch;
    v_dmg_time := v_dmg_time - host_frametime;
  end;

  if cl.stats[STAT_HEALTH] <= 0 then
  begin
    r_refdef.viewangles[ROLL] := 80; // dead view angle
    exit;
  end;

end;


(*
==================
V_CalcIntermissionRefdef

==================
*)

procedure V_CalcIntermissionRefdef;
var
  ent, view: Pentity_t;
  old: single;
begin
// ent is the player model (visible when out of body)
  ent := @cl_entities[cl.viewentity];
// view is the weapon model (only visible from inside body)
  view := @cl.viewent;

  VectorCopy(@ent.origin, @r_refdef.vieworg);
  VectorCopy(@ent.angles, @r_refdef.viewangles);
  view.model := nil;

// allways idle in intermission
  old := v_idlescale.value;
  v_idlescale.value := 1;
  V_AddIdle;
  v_idlescale.value := old;
end;

(*
==================
V_CalcRefdef

==================
*)
var
  oldz: single = 0.0;

procedure V_CalcRefdef;
var
  ent, view: Pentity_t;
  i: integer;
  _forward, right, up: TVector3f;
  angles: TVector3f;
  bob: single;
  steptime: single;
begin
  V_DriftPitch;

// ent is the player model (visible when out of body)
  ent := @cl_entities[cl.viewentity];
// view is the weapon model (only visible from inside body)
  view := @cl.viewent;


// transform the view offset by the model's matrix to get the offset from
// model origin for the view
  ent.angles[YAW] := cl.viewangles[YAW]; // the model should face
                                          // the view dir
  ent.angles[PITCH] := -cl.viewangles[PITCH]; // the model should face
                                              // the view dir


  bob := V_CalcBob;

// refresh position
  VectorCopy(@ent.origin, @r_refdef.vieworg);
  r_refdef.vieworg[2] := r_refdef.vieworg[2] + cl.viewheight + bob;

// never let it sit exactly on a node line, because a water plane can
// dissapear when viewed with the eye exactly on it.
// the server protocol only specifies to 1/16 pixel, so add 1/32 in each axis
  r_refdef.vieworg[0] := r_refdef.vieworg[0] + 1.0 / 32;
  r_refdef.vieworg[1] := r_refdef.vieworg[1] + 1.0 / 32;
  r_refdef.vieworg[2] := r_refdef.vieworg[2] + 1.0 / 32;

  VectorCopy(@cl.viewangles, @r_refdef.viewangles);
  V_CalcViewRoll;
  V_AddIdle;

// offsets
  angles[PITCH] := -ent.angles[PITCH]; // because entity pitches are
                                        //  actually backward
  angles[YAW] := ent.angles[YAW];
  angles[ROLL] := ent.angles[ROLL];

  AngleVectors(@angles, @_forward, @right, @up);

  for i := 0 to 2 do
    r_refdef.vieworg[i] := r_refdef.vieworg[i] +
      scr_ofsx.value * _forward[i] + scr_ofsy.value * right[i] + scr_ofsz.value * up[i];


  V_BoundOffsets;

// set up gun position
  VectorCopy(@cl.viewangles, @view.angles);

  CalcGunAngle;

  VectorCopy(@ent.origin, @view.origin);
  view.origin[2] := view.origin[2] + cl.viewheight;

  for i := 0 to 2 do
    view.origin[i] := view.origin[i] + _forward[i] * bob * 0.4;

  view.origin[2] := view.origin[2] + bob;

// fudge position around to keep amount of weapon visible
// roughly equal with different FOV

  if scr_viewsize.value = 110 then
    view.origin[2] := view.origin[2] + 1
  else if scr_viewsize.value = 100 then
    view.origin[2] := view.origin[2] + 2
  else if scr_viewsize.value = 90 then
    view.origin[2] := view.origin[2] + 1
  else if scr_viewsize.value = 80 then
    view.origin[2] := view.origin[2] + 0.5;

  view.model := cl.model_precache[cl.stats[STAT_WEAPON]];
  view.frame := cl.stats[STAT_WEAPONFRAME];
  view.colormap := vid.colormap;

// set up the refresh position
  VectorAdd(@r_refdef.viewangles, @cl.punchangle, @r_refdef.viewangles);

// smooth out stair step ups
  if cl.onground and (ent.origin[2] - oldz > 0) then
  begin

    steptime := cl.time - cl.oldtime;
    if steptime < 0 then
//FIXME    I_Error('steptime < 0');
      steptime := 0;

    oldz := oldz + steptime * 80;
    if oldz > ent.origin[2] then
      oldz := ent.origin[2];
    if ent.origin[2] - oldz > 12 then
      oldz := ent.origin[2] - 12;
    r_refdef.vieworg[2] := r_refdef.vieworg[2] + oldz - ent.origin[2];
    view.origin[2] := view.origin[2] + oldz - ent.origin[2];
  end
  else
    oldz := ent.origin[2];

  if chase_active.value <> 0 then
    Chase_Update;
end;

(*
==================
V_RenderView

The player's clipping box goes from (-16 -16 -24) to (16 16 32) from
the entity origin, so any view position inside that will be valid
==================
*)

procedure V_RenderView;
var
  i: integer;
begin
  if con_forcedup then
    exit;

// don't allow cheats in multiplayer
  if cl.maxclients > 1 then
  begin
    Cvar_Set('scr_ofsx', '0');
    Cvar_Set('scr_ofsy', '0');
    Cvar_Set('scr_ofsz', '0');
  end;

  if cl.intermission <> 0 then
  begin // intermission / finale rendering
    V_CalcIntermissionRefdef;
  end
  else
  begin
    if not cl.paused then (* and (sv.maxclients > 1 or key_dest = key_game) *)
      V_CalcRefdef;
  end;

  R_PushDlights;

  if lcd_x.value <> 0 then
  begin
    //
    // render two interleaved views
    //
    vid.rowbytes := vid.rowbytes * 2;
    vid.aspect := vid.aspect * 0.5;

    r_refdef.viewangles[YAW] := r_refdef.viewangles[YAW] - lcd_yaw.value;
    for i := 0 to 2 do
      r_refdef.vieworg[i] := r_refdef.vieworg[i] - right[i] * lcd_x.value;
    R_RenderView;

    inc(vid.buffer, vid.rowbytes div 2);

    R_PushDlights;

    r_refdef.viewangles[YAW] := r_refdef.viewangles[YAW] + lcd_yaw.value * 2;
    for i := 0 to 2 do
      r_refdef.vieworg[i] := r_refdef.vieworg[i] + 2 * right[i] * lcd_x.value;

    R_RenderView;

    dec(vid.buffer, vid.rowbytes div 2);

    r_refdef.vrect.height := r_refdef.vrect.height * 2;

    vid.rowbytes := vid.rowbytes div 2;
    vid.aspect := vid.aspect * 2;
  end
  else
    R_RenderView;
end;

//============================================================================

(*
=============
V_Init
=============
*)

procedure V_Init;
begin
  Cmd_AddCommand('v_cshift', V_cshift_f);
  Cmd_AddCommand('bf', V_BonusFlash_f);
  Cmd_AddCommand('centerview', V_StartPitchDrift);

  Cvar_RegisterVariable(@lcd_x);
  Cvar_RegisterVariable(@lcd_yaw);

  Cvar_RegisterVariable(@v_centermove);
  Cvar_RegisterVariable(@v_centerspeed);

  Cvar_RegisterVariable(@v_iyaw_cycle);
  Cvar_RegisterVariable(@v_iroll_cycle);
  Cvar_RegisterVariable(@v_ipitch_cycle);
  Cvar_RegisterVariable(@v_iyaw_level);
  Cvar_RegisterVariable(@v_iroll_level);
  Cvar_RegisterVariable(@v_ipitch_level);

  Cvar_RegisterVariable(@v_idlescale);
  Cvar_RegisterVariable(@crosshair);
  Cvar_RegisterVariable(@cl_crossx);
  Cvar_RegisterVariable(@cl_crossy);
  Cvar_RegisterVariable(@gl_cshiftpercent);

  Cvar_RegisterVariable(@scr_ofsx);
  Cvar_RegisterVariable(@scr_ofsy);
  Cvar_RegisterVariable(@scr_ofsz);
  Cvar_RegisterVariable(@cl_rollspeed);
  Cvar_RegisterVariable(@cl_rollangle);
  Cvar_RegisterVariable(@cl_bob);
  Cvar_RegisterVariable(@cl_bobcycle);
  Cvar_RegisterVariable(@cl_bobup);

  Cvar_RegisterVariable(@v_kicktime);
  Cvar_RegisterVariable(@v_kickroll);
  Cvar_RegisterVariable(@v_kickpitch);

  BuildGammaTable(1.0); // no gamma yet
  Cvar_RegisterVariable(@v_gamma);
end;



end.

 