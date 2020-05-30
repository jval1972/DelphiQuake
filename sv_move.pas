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

unit sv_move;

// sv_move.c -- monster movement

interface

uses
  q_delphi,
  q_vector,
  progs_h;

function SV_movestep(ent: Pedict_t; move: PVector3f; relink: qboolean): qboolean;
function SV_CheckBottom(ent: Pedict_t): qboolean;
procedure SV_MoveToGoal;

const
  STEPSIZE = 18;

implementation

uses
  mathlib,
  bspconst,
  world,
  server_h,
  sv_main,
  pr_cmds,
  pr_edict,
  quakedef,
  pr_comp;

(*
=============
SV_CheckBottom

Returns false if any part of the bottom of the entity is off an edge that
is not a staircase.

=============
*)
var
  c_yes: integer = 0; // JVAL mayby remove...
  c_no: integer = 0;

function SV_CheckBottom(ent: Pedict_t): qboolean;
label
  realcheck;
var
  mins, maxs, start, stop: TVector3f;
  trace: trace_t;
  x, y: integer;
  mid, bottom: single;
begin
  VectorAdd(@ent.v.origin[0], @ent.v.mins[0], @mins[0]);
  VectorAdd(@ent.v.origin[0], @ent.v.maxs[0], @maxs[0]);

// if all of the points under the corners are solid world, don't bother
// with the tougher checks
// the corners must be within 16 of the midpoint
  start[2] := mins[2] - 1;
  for x := 0 to 1 do
    for y := 0 to 1 do
    begin
      if x = 1 then start[0] := maxs[0] else start[0] := mins[0];
      if y = 1 then start[1] := maxs[1] else start[1] := mins[1];

      if SV_PointContents(@start[0]) <> CONTENTS_SOLID then
        goto realcheck;
    end;

  inc(c_yes);
  result := true; // we got out easy
  exit;

  realcheck:
  inc(c_no);
//
// check it for real...
//
  start[2] := mins[2];

// the midpoint must be within 16 of the bottom
  start[0] := (mins[0] + maxs[0]) * 0.5;
  stop[0] := start[0];
  start[1] := (mins[1] + maxs[1]) * 0.5;
  stop[1] := start[1];
  stop[2] := start[2] - 2 * STEPSIZE;
  trace := SV_MoveEdict(@start[0], @vec3_origin[0], @vec3_origin[0], @stop[0], 1, ent);

  if trace.fraction = 1.0 then
  begin
    result := false;
    exit;
  end;
  mid := trace.endpos[2];
  bottom := mid;

// the corners must be within 16 of the midpoint
  for x := 0 to 1 do
    for y := 0 to 1 do
    begin
      if x = 0 then
      begin
        start[0] := mins[0];
        stop[0] := mins[0];
      end
      else
      begin
        start[0] := maxs[0];
        stop[0] := maxs[0];
      end;
      if y = 0 then
      begin
        start[1] := mins[1];
        stop[1] := mins[1];
      end
      else
      begin
        start[1] := maxs[1];
        stop[1] := maxs[1];
      end;

      trace := SV_MoveEdict(@start[0], @vec3_origin[0], @vec3_origin[0], @stop[0], 1, ent);

      if (trace.fraction <> 1.0) and (trace.endpos[2] > bottom) then
        bottom := trace.endpos[2];
      if (trace.fraction = 1.0) or (mid - trace.endpos[2] > STEPSIZE) then
      begin
        result := false;
        exit;
      end;
    end;

  inc(c_yes);
  result := true;
end;


(*
=============
SV_movestep

Called by monster program code.
The move will be adjusted for slopes and stairs, but if the move isn't
possible, no move is done, false is returned, and
pr_global_struct.trace_normal is set to the normal of the blocking wall
=============
*)

function SV_movestep(ent: Pedict_t; move: PVector3f; relink: qboolean): qboolean;
var
  dz: single;
  oldorg, neworg, _end: TVector3f;
  trace: trace_t;
  i: integer;
  enemy: Pedict_t;
begin
// try the move
  VectorCopy(@ent.v.origin[0], @oldorg[0]);
  VectorAdd(@ent.v.origin[0], move, @neworg[0]);

// flying monsters don't step up
  if boolval(intval(ent.v.flags) and (FL_SWIM or FL_FLY)) then
  begin
  // try one move with vertical motion, then one without
    for i := 0 to 1 do
    begin
      VectorAdd(@ent.v.origin[0], move, @neworg[0]);
      enemy := PROG_TO_EDICT(ent.v.enemy);
      if (i = 0) and (enemy <> sv.edicts) then
      begin
        dz := ent.v.origin[2] - PROG_TO_EDICT(ent.v.enemy).v.origin[2];
        if dz > 40 then
          neworg[2] := neworg[2] - 8;
        if dz < 30 then
          neworg[2] := neworg[2] + 8;
      end;
      trace := SV_MoveEdict(@ent.v.origin[0], @ent.v.mins[0], @ent.v.maxs[0], @neworg[0], 0, ent);

      if trace.fraction = 1 then
      begin
        if ((intval(ent.v.flags) and FL_SWIM) <> 0) and (SV_PointContents(@trace.endpos[0]) = CONTENTS_EMPTY) then
        begin
          result := false; // swim monster left water
          exit;
        end;

        VectorCopy(@trace.endpos[0], @ent.v.origin[0]);
        if relink then
          SV_LinkEdict(ent, true);
        result := true;
        exit;
      end;

      if enemy = sv.edicts then
        break;
    end;

    result := false;
    exit;
  end;

// push down from a step height above the wished position
  neworg[2] := neworg[2] + STEPSIZE;
  VectorCopy(@neworg[0], @_end[0]);
  _end[2] := _end[2] - STEPSIZE * 2;

  trace := SV_MoveEdict(@neworg[0], @ent.v.mins[0], @ent.v.maxs[0], @_end[0], 0, ent);

  if trace.allsolid then
  begin
    result := false;
    exit;
  end;

  if trace.startsolid then
  begin
    neworg[2] := neworg[2] - STEPSIZE;
    trace := SV_MoveEdict(@neworg[0], @ent.v.mins[0], @ent.v.maxs[0], @_end[0], 0, ent);
    if trace.allsolid or trace.startsolid then
    begin
      result := false;
      exit;
    end;
  end;
  if trace.fraction = 1 then
  begin
  // if monster had the ground pulled out, go ahead and fall
    if intval(ent.v.flags) and FL_PARTIALGROUND <> 0 then
    begin
      VectorAdd(@ent.v.origin[0], move, @ent.v.origin[0]);
      if relink then
        SV_LinkEdict(ent, true);
      ent.v.flags := intval(ent.v.flags) and (not FL_ONGROUND);
//  Con_Printf ("fall down\n");
      result := true;
      exit;
    end;

    result := false; // walked off an edge
    exit;
  end;

// check point traces down for dangling corners
  VectorCopy(@trace.endpos[0], @ent.v.origin[0]);

  if not SV_CheckBottom(ent) then
  begin
    if intval(ent.v.flags) and FL_PARTIALGROUND <> 0 then
    begin // entity had floor mostly pulled out from underneath it
          // and is trying to correct
      if relink then
        SV_LinkEdict(ent, true);
      result := true;
      exit;
    end;
    VectorCopy(@oldorg[0], @ent.v.origin[0]);
    result := false;
    exit;
  end;

  if intval(ent.v.flags) and FL_PARTIALGROUND <> 0 then
  begin
//    Con_Printf ("back on ground\n");
    ent.v.flags := intval(ent.v.flags) and (not FL_PARTIALGROUND);
  end;
  ent.v.groundentity := EDICT_TO_PROG(trace.ent);

// the move is ok
  if relink then
    SV_LinkEdict(ent, true);
  result := true;
end;


//============================================================================

(*
======================
SV_StepDirection

Turns to the movement direction, and walks the current distance if
facing it.

======================
*)

function SV_StepDirection(ent: Pedict_t; _yaw: single; dist: single): qboolean;
var
  move, oldorigin: TVector3f;
  delta: single;
begin
  ent.v.ideal_yaw := _yaw;
  PF_changeyaw;

  _yaw := _yaw * M_PI * 2 / 360;
  move[0] := cos(_yaw) * dist; // JVAL mayby SinCos ?
  move[1] := sin(_yaw) * dist;
  move[2] := 0;

  VectorCopy(@ent.v.origin[0], @oldorigin[0]);
  if SV_movestep(ent, @move[0], false) then
  begin
    delta := ent.v.angles[YAW] - ent.v.ideal_yaw;
    if (delta > 45) and (delta < 315) then
    begin // not turned far enough, so don't take the step
      VectorCopy(@oldorigin[0], @ent.v.origin[0]);
    end;
    SV_LinkEdict(ent, true);
    result := true;
    exit;
  end;
  SV_LinkEdict(ent, true);

  result := false;
end;

(*
======================
SV_FixCheckBottom

======================
*)

procedure SV_FixCheckBottom(ent: Pedict_t);
begin
//  Con_Printf ("SV_FixCheckBottom\n");

  ent.v.flags := intval(ent.v.flags) or FL_PARTIALGROUND;
end;



(*
================
SV_NewChaseDir

================
*)
const
  DI_NODIR = -1;

procedure SV_NewChaseDir(actor: Pedict_t; enemy: Pedict_t; dist: single);
var
  deltax, deltay: single;
  d: array[0..2] of single;
  tdir, olddir, turnaround: single;
begin
  olddir := anglemod(int(actor.v.ideal_yaw / 45) * 45);
  turnaround := anglemod(olddir - 180);

  deltax := enemy.v.origin[0] - actor.v.origin[0];
  deltay := enemy.v.origin[1] - actor.v.origin[1];
  if deltax > 10 then
    d[1] := 0
  else if deltax < -10 then
    d[1] := 180
  else
    d[1] := DI_NODIR;
  if deltay < -10 then
    d[2] := 270
  else if deltay > 10 then
    d[2] := 90
  else
    d[2] := DI_NODIR;

// try direct route
  if (d[1] <> DI_NODIR) and (d[2] <> DI_NODIR) then
  begin
    if d[1] = 0 then
      tdir := decide(d[2] = 90, 45, 315)
    else
      tdir := decide(d[2] = 90, 135, 215);

    if (tdir <> turnaround) and SV_StepDirection(actor, tdir, dist) then
      exit;
  end;

// try other directions
  if boolval((rand and 3) and 1) or (abs(deltay) > abs(deltax)) then
  begin
    tdir := d[1];
    d[1] := d[2];
    d[2] := tdir;
  end;

  if (d[1] <> DI_NODIR) and (d[1] <> turnaround) and SV_StepDirection(actor, d[1], dist) then
    exit;

  if (d[2] <> DI_NODIR) and (d[2] <> turnaround) and SV_StepDirection(actor, d[2], dist) then
    exit;

(* there is no direct path to the player, so pick another direction *)

  if (olddir <> DI_NODIR) and SV_StepDirection(actor, olddir, dist) then
    exit;

  if rand and 1 <> 0 then (*randomly determine direction of search*)
  begin
    tdir := 0;
    while tdir <= 315 do
    begin
      if (tdir <> turnaround) and SV_StepDirection(actor, tdir, dist) then
        exit;
      tdir := tdir + 45;
    end;
  end
  else
  begin
    tdir := 315;
    while tdir >= 0 do
    begin
      if (tdir <> turnaround) and SV_StepDirection(actor, tdir, dist) then
        exit;
      tdir := tdir - 45;
    end;
  end;

  if (turnaround <> DI_NODIR) and SV_StepDirection(actor, turnaround, dist) then
    exit;

  actor.v.ideal_yaw := olddir; // can't move

// if a bridge was pulled out from underneath a monster, it may not have
// a valid standing position at all

  if not SV_CheckBottom(actor) then
    SV_FixCheckBottom(actor);

end;


(*
======================
SV_CloseEnough

======================
*)

function SV_CloseEnough(ent: Pedict_t; goal: Pedict_t; const dist: single): qboolean;
var
  i: integer;
begin
  for i := 0 to 2 do
  begin
    if goal.v.absmin[i] > ent.v.absmax[i] + dist then
    begin
      result := false;
      exit;
    end;
    if goal.v.absmax[i] < ent.v.absmin[i] - dist then
    begin
      result := false;
      exit;
    end;
  end;
  result := true;
end;


(*
======================
SV_MoveToGoal

======================
*)

procedure SV_MoveToGoal;
var
  ent, goal: Pedict_t;
  dist: single;
begin
  ent := PROG_TO_EDICT(pr_global_struct.self);
  goal := PROG_TO_EDICT(ent.v.goalentity);
  dist := G_FLOAT(OFS_PARM0)^;

  if (intval(ent.v.flags) and (FL_ONGROUND or FL_FLY or FL_SWIM)) = 0 then
  begin
    G_FLOAT(OFS_RETURN)^ := 0;
    exit;
  end;

// if the next step hits the enemy, return immediately
  if (PROG_TO_EDICT(ent.v.enemy) <> sv.edicts) and SV_CloseEnough(ent, goal, dist) then
    exit;

// bump around...
  if ((rand and 3) = 1) or (not SV_StepDirection(ent, ent.v.ideal_yaw, dist)) then
    SV_NewChaseDir(ent, goal, dist);

end;


end.

 