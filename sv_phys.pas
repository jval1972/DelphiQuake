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

unit sv_phys;

// sv_phys.c

interface

uses
  cvar;

var
  sv_friction: cvar_t = (name: 'sv_friction'; text: '4'; archive: false; server: true);
  sv_stopspeed: cvar_t = (name: 'sv_stopspeed'; text: '100');
  sv_gravity: cvar_t = (name: 'sv_gravity'; text: '800'; archive: false; server: true);
  sv_maxvelocity: cvar_t = (name: 'sv_maxvelocity'; text: '2000');
  sv_nostep: cvar_t = (name: 'sv_nostep'; text: '0');

procedure SV_Physics;

implementation

uses
  q_delphi,
  q_vector,
  bspconst,
  mathlib,
  progs_h,
  sv_main,
  server_h,
  world,
  console,
  pr_edict,
  host_h,
  pr_exec,
  sys_win,
  quakedef,
  sv_user,
  sv_move;

(*


pushmove objects do not obey gravity, and do not interact with each other
or trigger fields, but block normal movement and push normal objects when
they move.

onground is set for toss objects when they come to a complete rest.
it is set for steping or walking objects

doors, plats, etc are SOLID_BSP, and MOVETYPE_PUSH
bonus items are SOLID_TRIGGER touch, and MOVETYPE_TOSS
corpses are SOLID_NOT and MOVETYPE_TOSS
crates are SOLID_BBOX and MOVETYPE_TOSS
walking monsters are SOLID_SLIDEBOX and MOVETYPE_STEP
flying/floating monsters are SOLID_SLIDEBOX and MOVETYPE_FLY

solid_edge items only clip against bsp models.

*)

const
  MOVE_EPSILON = 0.01;

(*
================
SV_CheckAllEnts
================
*)

procedure SV_CheckAllEnts;
label
  continue1;
var
  e: integer;
  check: Pedict_t;
begin
// see if any solid entities are inside the final position
  check := NEXT_EDICT(sv.edicts);
  for e := 1 to sv.num_edicts - 1 do
  begin
    if check.free then
      goto continue1;
    if intval(check.v.movetype) in [MOVETYPE_PUSH, MOVETYPE_NONE, MOVETYPE_NOCLIP] then
      goto continue1;

    if SV_TestEntityPosition(check) <> nil then
      Con_Printf('entity in invalid position'#10);
    continue1:
    check := NEXT_EDICT(check);
  end;
end;

(*
================
SV_CheckVelocity
================
*)

procedure SV_CheckVelocity(ent: Pedict_t);
var
  i: integer;
begin
//
// bound velocity
//
  for i := 0 to 2 do
  begin
    if IS_NAN(ent.v.velocity[i]) then
    begin
      Con_Printf('Got a NaN velocity on %s'#10, [PChar(@pr_strings[ent.v.classname])]); // JVAL check
      ent.v.velocity[i] := 0;
    end;
    if IS_NAN(ent.v.origin[i]) then
    begin
      Con_Printf('Got a NaN origin on %s'#10, [PChar(@pr_strings[ent.v.classname])]); // JVAL check
      ent.v.origin[i] := 0;
    end;
    if ent.v.velocity[i] > sv_maxvelocity.value then
      ent.v.velocity[i] := sv_maxvelocity.value
    else if ent.v.velocity[i] < -sv_maxvelocity.value then
      ent.v.velocity[i] := -sv_maxvelocity.value;
  end;
end;


(*
=============
SV_RunThink

Runs thinking code if time.  There is some play in the exact time the think
function will be called, because it is called before any movement is done
in a frame.  Not used for pushmove objects, because they must be exact.
Returns false if the entity removed itself.
=============
*)

function SV_RunThink(ent: Pedict_t): qboolean;
var
  thinktime: single;
begin
  thinktime := ent.v.nextthink;
  if (thinktime <= 0) or (thinktime > sv.time + host_frametime) then
  begin
    result := true;
    exit;
  end;

  if thinktime < sv.time then
    thinktime := sv.time; // don't let things stay in the past.
                          // it is possible to start that way
                          // by a trigger with a local time.
  ent.v.nextthink := 0;
  pr_global_struct.time := thinktime;
  pr_global_struct.self := EDICT_TO_PROG(ent);
  pr_global_struct.other := EDICT_TO_PROG(sv.edicts);
  PR_ExecuteProgram(ent.v.think);
  result := not ent.free;
end;

(*
==================
SV_Impact

Two entities have touched, so run their touch functions
==================
*)

procedure SV_Impact(e1, e2: Pedict_t);
var
  old_self, old_other: integer;
begin
  old_self := pr_global_struct.self;
  old_other := pr_global_struct.other;

  pr_global_struct.time := sv.time;
  if (e1.v.touch <> 0) and (e1.v.solid <> SOLID_NOT) then
  begin
    pr_global_struct.self := EDICT_TO_PROG(e1);
    pr_global_struct.other := EDICT_TO_PROG(e2);
    PR_ExecuteProgram(e1.v.touch);
  end;

  if (e2.v.touch <> 0) and (e2.v.solid <> SOLID_NOT) then
  begin
    pr_global_struct.self := EDICT_TO_PROG(e2);
    pr_global_struct.other := EDICT_TO_PROG(e1);
    PR_ExecuteProgram(e2.v.touch);
  end;

  pr_global_struct.self := old_self;
  pr_global_struct.other := old_other;
end;


(*
==================
ClipVelocity

Slide off of the impacting object
returns the blocked flags (1 := floor, 2 := step / wall)
==================
*)
const
  STOP_EPSILON = 0.1;

function ClipVelocity(_in, normal, _out: PVector3f; overbounce: single): integer;
var
  backoff: single;
  change: single;
  i: integer;
begin
  result := 0;
  if normal[2] > 0 then
    result := result or 1; // floor
  if normal[2] = 0 then
    result := result or 2; // step

  backoff := VectorDotProduct(_in, normal) * overbounce;

  for i := 0 to 2 do
  begin
    change := normal[i] * backoff;
    _out[i] := _in[i] - change;
    if (_out[i] > -STOP_EPSILON) and (_out[i] < STOP_EPSILON) then
      _out[i] := 0;
  end;
end;


(*
============
SV_FlyMove

The basic solid body movement clip that slides along multiple planes
Returns the clipflags if the velocity was modified (hit something solid)
1 := floor
2 := wall / step
4 := dead stop
If steptrace is not NULL, the trace of any vertical wall hit will be stored
============
*)
const
  MAX_CLIP_PLANES = 5;

function SV_FlyMove(ent: Pedict_t; time: single; steptrace: Ptrace_t): integer;
var
  bumpcount, numbumps: integer;
  dir: TVector3f;
  d: single;
  numplanes: integer;
  planes: array[0..MAX_CLIP_PLANES - 1] of TVector3f;
  primal_velocity, original_velocity, new_velocity: TVector3f;
  i, j: integer;
  trace: trace_t;
  _end: TVector3f;
  time_left: single;
  blocked: integer;
begin
  numbumps := 4;

  blocked := 0;
  VectorCopy(@ent.v.velocity, @original_velocity);
  VectorCopy(@ent.v.velocity, @primal_velocity);
  numplanes := 0;

  time_left := time;

  for bumpcount := 0 to numbumps - 1 do
  begin
    if (ent.v.velocity[0] = 0) and (ent.v.velocity[1] = 0) and (ent.v.velocity[2] = 0) then
      break;

    for i := 0 to 2 do
      _end[i] := ent.v.origin[i] + time_left * ent.v.velocity[i];

    trace := SV_MoveEdict(@ent.v.origin, @ent.v.mins, @ent.v.maxs, @_end, 0, ent);

    if trace.allsolid then
    begin // entity is trapped in another solid
      VectorCopy(@vec3_origin, @ent.v.velocity);
      result := 3;
      exit;
    end;

    if trace.fraction > 0 then
    begin // actually covered some distance
      VectorCopy(@trace.endpos, @ent.v.origin);
      VectorCopy(@ent.v.velocity, @original_velocity);
      numplanes := 0;
    end;

    if trace.fraction = 1 then
      break; // moved the entire distance

    if not boolval(trace.ent) then
      Sys_Error('SV_FlyMove: !trace.ent');

    if trace.plane.normal[2] > 0.7 then
    begin
      blocked := blocked or 1; // floor
      if trace.ent.v.solid = SOLID_BSP then
      begin
        ent.v.flags := intval(ent.v.flags) or FL_ONGROUND;
        ent.v.groundentity := EDICT_TO_PROG(trace.ent);
      end;
    end;
    if trace.plane.normal[2] = 0 then
    begin
      blocked := blocked or 2; // step
      if steptrace <> nil then
        steptrace^ := trace; // save for player extrafriction
    end;

//
// run the impact function
//
    SV_Impact(ent, trace.ent);
    if ent.free then
      break; // removed by the impact function


    time_left := time_left - time_left * trace.fraction;

  // cliped to another plane
    if numplanes >= MAX_CLIP_PLANES then
    begin // this shouldn't really happen
      VectorCopy(@vec3_origin, @ent.v.velocity);
      result := 3;
      exit;
    end;

    VectorCopy(@trace.plane.normal, @planes[numplanes]);
    inc(numplanes);

//
// modify original_velocity so it parallels all of the clip planes
//
    i := 0;
    while i < numplanes do
    begin
      ClipVelocity(@original_velocity, @planes[i], @new_velocity, 1);
      j := 0;
      while j < numplanes do
      begin
        if j <> i then
        begin
          if VectorDotProduct(@new_velocity, @planes[j]) < 0 then
            break; // not ok
        end;
        inc(j);
      end;
      if j = numplanes then
        break;
      inc(i);
    end;

    if i <> numplanes then
    begin // go along this plane
      VectorCopy(@new_velocity, @ent.v.velocity);
    end
    else
    begin // go along the crease
      if numplanes <> 2 then
      begin
        VectorCopy(@vec3_origin, @ent.v.velocity);
        result := 7;
        exit;
      end;
      CrossProduct(@planes[0], @planes[1], @dir);
      d := VectorDotProduct(@dir, @ent.v.velocity);
      VectorScale(@dir, d, @ent.v.velocity);
    end;

//
// if original velocity is against the original velocity, stop dead
// to avoid tiny occilations in sloping corners
//
    if VectorDotProduct(@ent.v.velocity, @primal_velocity) <= 0 then
    begin
      VectorCopy(@vec3_origin, @ent.v.velocity);
      result := blocked;
      exit;
    end;
  end;

  result := blocked;
end;


(*
============
SV_AddGravity

============
*)

procedure SV_AddGravity(ent: Pedict_t);
var
  ent_gravity: single;
  val: Peval_t;
begin
  val := GetEdictFieldValue(ent, 'gravity');
  if (val <> nil) and (val._float <> 0) then
    ent_gravity := val._float
  else
    ent_gravity := 1.0;
  ent.v.velocity[2] := ent.v.velocity[2] - ent_gravity * sv_gravity.value * host_frametime;
end;


(*
===============================================================================

PUSHMOVE

===============================================================================
*)

(*
============
SV_PushEntity

Does not change the entities velocity at all
============
*)

function SV_PushEntity(ent: Pedict_t; push: PVector3f): trace_t;
var
  trace: trace_t;
  _end: TVector3f;
begin
  VectorAdd(@ent.v.origin, push, @_end);

  if ent.v.movetype = MOVETYPE_FLYMISSILE then
    trace := SV_MoveEdict(@ent.v.origin, @ent.v.mins, @ent.v.maxs, @_end, MOVE_MISSILE, ent)
  else if (ent.v.solid = SOLID_TRIGGER) or (ent.v.solid = SOLID_NOT) then
  // only clip against bmodels
    trace := SV_MoveEdict(@ent.v.origin, @ent.v.mins, @ent.v.maxs, @_end, MOVE_NOMONSTERS, ent)
  else
    trace := SV_MoveEdict(@ent.v.origin, @ent.v.mins, @ent.v.maxs, @_end, MOVE_NORMAL, ent);

  VectorCopy(@trace.endpos, @ent.v.origin);
  SV_LinkEdict(ent, true);

  if trace.ent <> nil then
    SV_Impact(ent, trace.ent);

  result := trace;
end;


(*
============
SV_PushMove

============
*)

procedure SV_PushMove(pusher: Pedict_t; movetime: single);
label
  continue1;
var
  i, e: integer;
  check, block: Pedict_t;
  mins, maxs, move: TVector3f;
  entorig, pushorig: TVector3f;
  num_moved: integer;
  moved_edict: array[0..MAX_EDICTS - 1] of Pedict_t;
  moved_from: array[0..MAX_EDICTS - 1] of TVector3f;
begin
  if (pusher.v.velocity[0] = 0) and (pusher.v.velocity[1] = 0) and (pusher.v.velocity[2] = 0) then
  begin
    pusher.v.ltime := pusher.v.ltime + movetime;
    exit;
  end;

  for i := 0 to 2 do
  begin
    move[i] := pusher.v.velocity[i] * movetime;
    mins[i] := pusher.v.absmin[i] + move[i];
    maxs[i] := pusher.v.absmax[i] + move[i];
  end;

  VectorCopy(@pusher.v.origin[0], @pushorig[0]);

// move the pusher to it's final position

  VectorAdd(@pusher.v.origin[0], @move[0], @pusher.v.origin[0]);
  pusher.v.ltime := pusher.v.ltime + movetime;
  SV_LinkEdict(pusher, false);


// see if any solid entities are inside the final position
  num_moved := 0;
  check := NEXT_EDICT(sv.edicts);
  for e := 1 to sv.num_edicts - 1 do
  begin
    if check.free then
      goto continue1;
    if intval(check.v.movetype) in [MOVETYPE_PUSH, MOVETYPE_NONE, MOVETYPE_NOCLIP] then
      goto continue1;

  // if the entity is standing on the pusher, it will definately be moved
    if not (((intval(check.v.flags) and FL_ONGROUND) <> 0) and
      (PROG_TO_EDICT(check.v.groundentity) = pusher)) then
    begin
      if (check.v.absmin[0] >= maxs[0]) or
        (check.v.absmin[1] >= maxs[1]) or
        (check.v.absmin[2] >= maxs[2]) or
        (check.v.absmax[0] <= mins[0]) or
        (check.v.absmax[1] <= mins[1]) or
        (check.v.absmax[2] <= mins[2]) then
        goto continue1;

    // see if the ent's bbox is inside the pusher's final position
      if SV_TestEntityPosition(check) = nil then
        goto continue1;
    end;

  // remove the onground flag for non-players
    if (check.v.movetype <> MOVETYPE_WALK) then
      check.v.flags := intval(check.v.flags) and (not FL_ONGROUND);

    VectorCopy(@check.v.origin, @entorig);
    VectorCopy(@check.v.origin, @moved_from[num_moved]);
    moved_edict[num_moved] := check;
    inc(num_moved);

    // try moving the contacted entity
    pusher.v.solid := SOLID_NOT;
    SV_PushEntity(check, @move);
    pusher.v.solid := SOLID_BSP;

  // if it is still inside the pusher, block
    block := SV_TestEntityPosition(check);
    if block <> nil then
    begin // fail the move
      if check.v.mins[0] = check.v.maxs[0] then
        goto continue1;
      if intval(check.v.solid) in [SOLID_NOT, SOLID_TRIGGER] then
      begin // corpse
        check.v.mins[0] := 0;
        check.v.mins[1] := 0;
        VectorCopy(@check.v.mins, @check.v.maxs);
        goto continue1;
      end;

      VectorCopy(@entorig, @check.v.origin);
      SV_LinkEdict(check, true);

      VectorCopy(@pushorig, @pusher.v.origin);
      SV_LinkEdict(pusher, false);
      pusher.v.ltime := pusher.v.ltime - movetime;

      // if the pusher has a "blocked" function, call it
      // otherwise, just stay in place until the obstacle is gone
      if pusher.v.blocked <> 0 then
      begin
        pr_global_struct.self := EDICT_TO_PROG(pusher);
        pr_global_struct.other := EDICT_TO_PROG(check);
        PR_ExecuteProgram(pusher.v.blocked);
      end;

    // move back any entities we already moved
      for i := 0 to num_moved - 1 do
      begin
        VectorCopy(@moved_from[i], @moved_edict[i].v.origin);
        SV_LinkEdict(moved_edict[i], false);
      end;
      exit;
    end;
    continue1:
    check := NEXT_EDICT(check);
  end;

end;

(*
================
SV_Physics_Pusher

================
*)

procedure SV_Physics_Pusher(ent: Pedict_t);
var
  thinktime: single;
  oldltime: single;
  movetime: single;
begin
  oldltime := ent.v.ltime;

  thinktime := ent.v.nextthink;
  if thinktime < ent.v.ltime + host_frametime then
  begin
    movetime := thinktime - ent.v.ltime;
    if movetime < 0 then
      movetime := 0;
  end
  else
    movetime := host_frametime;

  if movetime <> 0 then
  begin
    SV_PushMove(ent, movetime); // advances ent.v.ltime if not blocked
  end;

  if (thinktime > oldltime) and (thinktime <= ent.v.ltime) then
  begin
    ent.v.nextthink := 0;
    pr_global_struct.time := sv.time;
    pr_global_struct.self := EDICT_TO_PROG(ent);
    pr_global_struct.other := EDICT_TO_PROG(sv.edicts);
    PR_ExecuteProgram(ent.v.think);
    if ent.free then
      exit;
  end;

end;


(*
===============================================================================

CLIENT MOVEMENT

===============================================================================
*)

(*
=============
SV_CheckStuck

This is a big hack to try and fix the rare case of getting stuck in the world
clipping hull.
=============
*)

procedure SV_CheckStuck(ent: Pedict_t);
var
  i, j: integer;
  z: integer;
  org: TVector3f;
begin
  if SV_TestEntityPosition(ent) = nil then
  begin
    VectorCopy(@ent.v.origin, @ent.v.oldorigin);
    exit;
  end;

  VectorCopy(@ent.v.origin, @org);
  VectorCopy(@ent.v.oldorigin, @ent.v.origin);
  if SV_TestEntityPosition(ent) = nil then
  begin
    Con_DPrintf('Unstuck.'#10);
    SV_LinkEdict(ent, true);
    exit;
  end;

  for z := 0 to 17 do
    for i := -1 to 1 do
      for j := -1 to 1 do
      begin
        ent.v.origin[0] := org[0] + i;
        ent.v.origin[1] := org[1] + j;
        ent.v.origin[2] := org[2] + z;
        if SV_TestEntityPosition(ent) = nil then
        begin
          Con_DPrintf('Unstuck.'#10);
          SV_LinkEdict(ent, true);
          exit;
        end;
      end;

  VectorCopy(@org, @ent.v.origin);
  Con_DPrintf('player is stuck.'#10);
end;


(*
=============
SV_CheckWater
=============
*)

function SV_CheckWater(ent: Pedict_t): qboolean;
var
  point: TVector3f;
  cont: integer;
begin
  point[0] := ent.v.origin[0];
  point[1] := ent.v.origin[1];
  point[2] := ent.v.origin[2] + ent.v.mins[2] + 1;

  ent.v.waterlevel := 0;
  ent.v.watertype := CONTENTS_EMPTY;
  cont := SV_PointContents(@point[0]);
  if cont <= CONTENTS_WATER then
  begin
    ent.v.watertype := cont;
    ent.v.waterlevel := 1;
    point[2] := ent.v.origin[2] + (ent.v.mins[2] + ent.v.maxs[2]) * 0.5;
    cont := SV_PointContents(@point);
    if cont <= CONTENTS_WATER then
    begin
      ent.v.waterlevel := 2;
      point[2] := ent.v.origin[2] + ent.v.view_ofs[2];
      cont := SV_PointContents(@point);
      if cont <= CONTENTS_WATER then
        ent.v.waterlevel := 3;
    end;
  end;

  result := ent.v.waterlevel > 1;
end;

(*
============
SV_WallFriction

============
*)

procedure SV_WallFriction(ent: Pedict_t; trace: Ptrace_t);
var
  _forward, right, up: TVector3f;
  d, i: single;
  into, side: TVector3f;
begin
  AngleVectors(@ent.v.v_angle, @_forward, @right, @up);
  d := VectorDotProduct(@trace.plane.normal, @_forward);

  d := d + 0.5;
  if d >= 0 then
    exit;

// cut the tangential velocity
  i := VectorDotProduct(@trace.plane.normal, @ent.v.velocity);
  VectorScale(@trace.plane.normal, i, @into);
  VectorSubtract(@ent.v.velocity, @into, @side);

  ent.v.velocity[0] := side[0] * (1 + d);
  ent.v.velocity[1] := side[1] * (1 + d);
end;


(*
=====================
SV_TryUnstick

Player has come to a dead stop, possibly due to the problem with limited
float precision at some angle joins in the BSP hull.

Try fixing by pushing one pixel in each direction.

This is a hack, but in the interest of good gameplay...
======================
*)

function SV_TryUnstick(ent: Pedict_t; oldvel: PVector3f): integer;
var
  i: integer;
  oldorg: TVector3f;
  dir: TVector3f;
  clip: integer;
  steptrace: trace_t;
begin
  VectorCopy(@ent.v.origin, @oldorg);
  VectorCopy(@vec3_origin, @dir);

  for i := 0 to 7 do
  begin
// try pushing a little in an axial direction
    case i of
      0:
        begin
          dir[0] := 2;
          dir[1] := 0;
        end;
      1:
        begin
          dir[0] := 0;
          dir[1] := 2;
        end;
      2:
        begin
          dir[0] := -2;
          dir[1] := 0;
        end;
      3:
        begin
          dir[0] := 0;
          dir[1] := -2;
        end;
      4:
        begin
          dir[0] := 2;
          dir[1] := 2;
        end;
      5:
        begin
          dir[0] := -2;
          dir[1] := 2;
        end;
      6:
        begin
          dir[0] := 2;
          dir[1] := -2;
        end;
      7:
        begin
          dir[0] := -2;
          dir[1] := -2;
        end;
    end;

    SV_PushEntity(ent, @dir);

// retry the original move
    ent.v.velocity[0] := oldvel[0];
    ent.v.velocity[1] := oldvel[1];
    ent.v.velocity[2] := 0;
    clip := SV_FlyMove(ent, 0.1, @steptrace);

    if (abs(oldorg[1] - ent.v.origin[1]) > 4) or
      (abs(oldorg[0] - ent.v.origin[0]) > 4) then
    begin
//Con_DPrintf ("unstuck!\n");
      result := clip;
      exit;
    end;

// go back to the original pos and try again
    VectorCopy(@oldorg, @ent.v.origin);
  end;

  VectorCopy(@vec3_origin, @ent.v.velocity);
  result := 7; // still not moving
end;


(*
=====================
SV_WalkMove

Only used by players
======================
*)

procedure SV_WalkMove(ent: Pedict_t);
var
  upmove, downmove: TVector3f;
  oldorg, oldvel: TVector3f;
  nosteporg, nostepvel: TVector3f;
  clip: integer;
  oldonground: integer;
  steptrace, downtrace: trace_t;
begin
//
// do a regular slide move unless it looks like you ran into a step
//
  oldonground := intval(ent.v.flags) and FL_ONGROUND;
  ent.v.flags := intval(ent.v.flags) and (not FL_ONGROUND);

  VectorCopy(@ent.v.origin, @oldorg);
  VectorCopy(@ent.v.velocity, @oldvel);

  clip := SV_FlyMove(ent, host_frametime, @steptrace);

  if (clip and 2) = 0 then
    exit; // move didn't block on a step

  if (oldonground = 0) and (ent.v.waterlevel = 0) then
    exit; // don't stair up while jumping

  if ent.v.movetype <> MOVETYPE_WALK then
    exit; // gibbed by a trigger

  if boolval(sv_nostep.value) then
    exit;

  if intval(sv_player.v.flags) and FL_WATERJUMP <> 0 then
    exit;

  VectorCopy(@ent.v.origin, @nosteporg);
  VectorCopy(@ent.v.velocity, @nostepvel);

//
// try moving up and forward to go up a step
//
  VectorCopy(@oldorg, @ent.v.origin); // back to start pos

  VectorCopy(@vec3_origin, @upmove);
  VectorCopy(@vec3_origin, @downmove);
  upmove[2] := STEPSIZE;
  downmove[2] := -STEPSIZE + oldvel[2] * host_frametime;

// move up
  SV_PushEntity(ent, @upmove); // FIXME: don't link?

// move forward
  ent.v.velocity[0] := oldvel[0];
  ent.v.velocity[1] := oldvel[1];
  ent.v.velocity[2] := 0;
  clip := SV_FlyMove(ent, host_frametime, @steptrace);

// check for stuckness, possibly due to the limited precision of floats
// in the clipping hulls
  if clip <> 0 then
  begin
    if (abs(oldorg[1] - ent.v.origin[1]) < 0.03125) and
      (abs(oldorg[0] - ent.v.origin[0]) < 0.03125) then
    begin // stepping up didn't make any progress
      clip := SV_TryUnstick(ent, @oldvel);
    end;
  end;

// extra friction based on view angle
  if clip and 2 <> 0 then
    SV_WallFriction(ent, @steptrace);

// move down
  downtrace := SV_PushEntity(ent, @downmove); // FIXME: don't link?

  if downtrace.plane.normal[2] > 0.7 then
  begin
    if ent.v.solid = SOLID_BSP then
    begin
      ent.v.flags := intval(ent.v.flags) or FL_ONGROUND;
      ent.v.groundentity := EDICT_TO_PROG(downtrace.ent);
    end;
  end
  else
  begin
// if the push down didn't end up on good ground, use the move without
// the step up.  This happens near wall / slope combinations, and can
// cause the player to hop up higher on a slope too steep to climb
    VectorCopy(@nosteporg, @ent.v.origin);
    VectorCopy(@nostepvel, @ent.v.velocity);
  end;
end;


(*
=============
SV_CheckWaterTransition

=============
*)

procedure SV_CheckWaterTransition(ent: Pedict_t);
var
  cont: integer;
begin
  cont := SV_PointContents(@ent.v.origin);
  if not boolval(ent.v.watertype) then
  begin // just spawned here
    ent.v.watertype := cont;
    ent.v.waterlevel := 1;
    exit;
  end;

  if cont <= CONTENTS_WATER then
  begin
    if ent.v.watertype = CONTENTS_EMPTY then
    begin // just crossed into water
      SV_StartSound(ent, 0, 'misc/h2ohit1.wav', 255, 1);
    end;
    ent.v.watertype := cont;
    ent.v.waterlevel := 1;
  end
  else
  begin
    if ent.v.watertype <> CONTENTS_EMPTY then
    begin // just crossed into water
      SV_StartSound(ent, 0, 'misc/h2ohit1.wav', 255, 1);
    end;
    ent.v.watertype := CONTENTS_EMPTY;
    ent.v.waterlevel := cont;
  end;
end;


(*
=============
SV_Physics_Toss

Toss, bounce, and fly movement.  When onground, do nothing.
=============
*)

procedure SV_Physics_Toss(ent: Pedict_t);
var
  trace: trace_t;
  move: TVector3f;
  backoff: single;
begin
  // regular thinking
  if not SV_RunThink(ent) then
    exit;

// if onground, return without moving
  if intval(ent.v.flags) and FL_ONGROUND <> 0 then
    exit;

  SV_CheckVelocity(ent);

// add gravity
  if (ent.v.movetype <> MOVETYPE_FLY) and
    (ent.v.movetype <> MOVETYPE_FLYMISSILE) then
    SV_AddGravity(ent);

// move angles
  VectorMA(@ent.v.angles, host_frametime, @ent.v.avelocity, @ent.v.angles);

// move origin
  VectorScale(@ent.v.velocity, host_frametime, @move);
  trace := SV_PushEntity(ent, @move);
  if trace.fraction = 1 then
    exit;
  if ent.free then
    exit;

  if ent.v.movetype = MOVETYPE_BOUNCE then
    backoff := 1.5
  else
    backoff := 1;

  ClipVelocity(@ent.v.velocity, @trace.plane.normal, @ent.v.velocity, backoff);

// stop if on ground
  if trace.plane.normal[2] > 0.7 then
  begin
    if (ent.v.velocity[2] < 60) or (ent.v.movetype <> MOVETYPE_BOUNCE) then
    begin
      ent.v.flags := intval(ent.v.flags) or FL_ONGROUND;
      ent.v.groundentity := EDICT_TO_PROG(trace.ent);
      VectorCopy(@vec3_origin, @ent.v.velocity);
      VectorCopy(@vec3_origin, @ent.v.avelocity);
    end;
  end;

// check for in water
  SV_CheckWaterTransition(ent);
end;


(*
================
SV_Physics_Client

Player character actions
================
*)

procedure SV_Physics_Client(ent: Pedict_t; num: integer);
begin
  if not svs.clients[num - 1].active then
    exit; // unconnected slot

//
// call standard client pre-think
//
  pr_global_struct.time := sv.time;
  pr_global_struct.self := EDICT_TO_PROG(ent);
  PR_ExecuteProgram(pr_global_struct.PlayerPreThink);

//
// do a move
//
  SV_CheckVelocity(ent);

//
// decide which move function to call
//
  case intval(ent.v.movetype) of
    MOVETYPE_NONE:
      begin
        if not SV_RunThink(ent) then
          exit;
      end;

    MOVETYPE_WALK:
      begin
        if not SV_RunThink(ent) then
          exit;
        if (not SV_CheckWater(ent)) and (not boolval(intval(ent.v.flags) and FL_WATERJUMP)) then
          SV_AddGravity(ent);
        SV_CheckStuck(ent);
        SV_WalkMove(ent);
      end;

    MOVETYPE_TOSS,
      MOVETYPE_BOUNCE:
      begin
        SV_Physics_Toss(ent);
      end;

    MOVETYPE_FLY:
      begin
        if not SV_RunThink(ent) then
          exit;
        SV_FlyMove(ent, host_frametime, nil);
      end;

    MOVETYPE_NOCLIP:
      begin
        if not SV_RunThink(ent) then
          exit;
        VectorMA(@ent.v.origin, host_frametime, @ent.v.velocity, @ent.v.origin);
      end;

  else
    Sys_Error('SV_Physics_client: bad movetype %d', [int(ent.v.movetype)]);
  end;

//
// call standard player post-think
//
  SV_LinkEdict(ent, true);

  pr_global_struct.time := sv.time;
  pr_global_struct.self := EDICT_TO_PROG(ent);
  PR_ExecuteProgram(pr_global_struct.PlayerPostThink);
end;

//============================================================================

(*
=============
SV_Physics_None

Non moving objects can only think
=============
*)

procedure SV_Physics_None(ent: Pedict_t);
begin
// regular thinking
  SV_RunThink(ent);
end;

(*
=============
SV_Physics_Noclip

A moving object that doesn't obey physics
=============
*)

procedure SV_Physics_Noclip(ent: Pedict_t);
begin
// regular thinking
  if SV_RunThink(ent) then
  begin
    VectorMA(@ent.v.angles, host_frametime, @ent.v.avelocity, @ent.v.angles);
    VectorMA(@ent.v.origin, host_frametime, @ent.v.velocity, @ent.v.origin);

    SV_LinkEdict(ent, false);
  end;
end;

(*
==============================================================================

TOSS / BOUNCE

==============================================================================
*)

(*
===============================================================================

STEPPING MOVEMENT

===============================================================================
*)

(*
=============
SV_Physics_Step

Monsters freefall when they don't have a ground entity, otherwise
all movement is done with discrete steps.

This is also used for objects that have become still on the ground, but
will fall if the floor is pulled out from under them.
=============
*)

procedure SV_Physics_Step(ent: Pedict_t);
var
  hitsound: qboolean;
begin
// freefall if not onground
  if (intval(ent.v.flags) and (FL_ONGROUND or FL_FLY or FL_SWIM)) = 0 then
  begin
    if ent.v.velocity[2] < sv_gravity.value * -0.1 then
      hitsound := true
    else
      hitsound := false;

    SV_AddGravity(ent);
    SV_CheckVelocity(ent);
    SV_FlyMove(ent, host_frametime, nil);
    SV_LinkEdict(ent, true);

    if intval(ent.v.flags) and FL_ONGROUND <> 0 then // just hit ground
    begin
      if hitsound then
        SV_StartSound(ent, 0, 'demon/dland2.wav', 255, 1);
    end;
  end;

// regular thinking
  SV_RunThink(ent);

  SV_CheckWaterTransition(ent);
end;

//============================================================================

(*
================
SV_Physics

================
*)

procedure SV_Physics;
var
  i: integer;
  ent: Pedict_t;
begin
// let the progs know that a new frame has started
  pr_global_struct.self := EDICT_TO_PROG(sv.edicts);
  pr_global_struct.other := EDICT_TO_PROG(sv.edicts);
  pr_global_struct.time := sv.time;
  PR_ExecuteProgram(pr_global_struct.StartFrame);

//SV_CheckAllEnts ();

//
// treat each object in turn
//
  ent := sv.edicts;
  for i := 0 to sv.num_edicts - 1 do
  begin
    if not ent.free then
    begin

      if pr_global_struct.force_retouch <> 0 then
      begin
        SV_LinkEdict(ent, true); // force retouch even for stationary
      end;

      if (i > 0) and (i <= svs.maxclients) then
        SV_Physics_Client(ent, i)
      else if ent.v.movetype = MOVETYPE_PUSH then
        SV_Physics_Pusher(ent)
      else if ent.v.movetype = MOVETYPE_NONE then
        SV_Physics_None(ent)
      else if ent.v.movetype = MOVETYPE_NOCLIP then
        SV_Physics_Noclip(ent)
      else if ent.v.movetype = MOVETYPE_STEP then
        SV_Physics_Step(ent)
      else if intval(ent.v.movetype) in [MOVETYPE_TOSS, MOVETYPE_BOUNCE, MOVETYPE_FLY, MOVETYPE_FLYMISSILE] then
        SV_Physics_Toss(ent)
      else
        Sys_Error('SV_Physics: bad movetype %d', [int(ent.v.movetype)]);
    end;
    ent := NEXT_EDICT(ent)
  end;

  if pr_global_struct.force_retouch <> 0 then
    pr_global_struct.force_retouch := pr_global_struct.force_retouch - 1;

  sv.time := sv.time + host_frametime;
end;

end.

