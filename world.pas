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

unit world;

interface

uses
  q_delphi,
  q_vector,
  progs_h,
  gl_model_h;


type
  Pplane_t = ^plane_t;
  plane_t = record
    normal: TVector3f;
    dist: single;
  end;

  Ptrace_t = ^trace_t;
  trace_t = record
    allsolid: qboolean; // if true, plane is not valid
    startsolid: qboolean; // if true, the initial point was in a solid area
    inopen, inwater: qboolean;
    fraction: single; // time completed, 1.0 = didn't hit anything
    endpos: TVector3f; // final position
    plane: plane_t; // surface normal at impact
    ent: Pedict_t; // entity the surface is on
  end;

const
  MOVE_NORMAL = 0;
  MOVE_NOMONSTERS = 1;
  MOVE_MISSILE = 2;

procedure SV_ClearWorld;
// called after the world model has been loaded, before linking any entities

procedure SV_UnlinkEdict(ent: Pedict_t);
// call before removing an entity, and before trying to move one,
// so it doesn't clip against itself
// flags ent->v.modified

procedure SV_LinkEdict(ent: Pedict_t; touch_triggers: qboolean);
// Needs to be called any time an entity changes origin, mins, maxs, or solid
// flags ent->v.modified
// sets ent->v.absmin and ent->v.absmax
// if touchtriggers, calls prog functions for the intersected triggers

function SV_PointContents(p: PVector3f): integer;
function SV_TruePointContents(p: PVector3f): integer;
// returns the CONTENTS_* value from the world at the given point.
// does not check any entities at all
// the non-true version remaps the water current contents to content_water

function SV_TestEntityPosition(ent: Pedict_t): Pedict_t;

function SV_MoveEdict(start, mins, maxs, _end: PVector3f; _type: integer;
  passedict: Pedict_t): trace_t;
// mins and maxs are reletive

// if the entire move stays in a solid volume, trace.allsolid will be set

// if the starting point is in a solid, it will be allowed to move out
// to an open area

// nomonsters is used for line of sight or edge testing, where mosnters
// shouldn't be considered solid objects

// passedict is explicitly excluded from clipping checks (normally NULL)

function SV_RecursiveHullCheck(hull: Phull_t; num: integer; p1f, p2f: single;
  p1, p2: PVector3f; trace: Ptrace_t): qboolean;

implementation

// world.c -- world query functions

uses
  mathlib,
  bsptypes,
  bspconst,
  gl_planes,
  server_h,
  sys_win,
  sv_main,
  common,
  pr_edict,
  pr_exec,
  console;

(*

entities never clip against themselves, or their owner

line of sight checks trace.crosscontent, but bullets don't

*)


type
  Pmoveclip_t = ^moveclip_t;
  moveclip_t = record
    boxmins, boxmaxs: TVector3f; // enclose the test object along entire move
    mins, maxs: PVector3f; // size of the moving object
    mins2, maxs2: TVector3f; // size when clipping against mosnters
    start, _end: PVector3f;
    trace: trace_t;
    _type: integer;
    passedict: Pedict_t;
  end;


function SV_HullPointContents(hull: Phull_t; num: integer; p: PVector3f): integer; forward;

(*
===============================================================================

HULL BOXES

===============================================================================
*)

var
  box_hull: hull_t;

const
  NUMBOXES = 5;

var
  box_clipnodes: array[0..NUMBOXES] of TBSPClipNode;
  box_planes: array[0..NUMBOXES] of mplane_t;

(*
===================
SV_InitBoxHull

Set up the planes and clipnodes so that the six floats of a bounding box
can just be stored out and get a proper hull_t structure.
===================
*)

procedure SV_InitBoxHull;
var
  i: integer;
  side: integer;
begin
  box_hull.clipnodes := @box_clipnodes[0];
  box_hull.planes := @box_planes[0];
  box_hull.firstclipnode := 0;
  box_hull.lastclipnode := NUMBOXES;

  for i := 0 to NUMBOXES do
  begin
    box_clipnodes[i].PlaneIndex := i;

    side := i and 1;

    box_clipnodes[i].children[side] := CONTENTS_EMPTY;
    if i <> NUMBOXES then
      box_clipnodes[i].children[side xor 1] := i + 1
    else
      box_clipnodes[i].children[side xor 1] := CONTENTS_SOLID;

    box_planes[i].PlaneType := i shr 1;
    box_planes[i].normal[i shr 1] := 1;
  end;

end;


(*
===================
SV_HullForBox

To keep everything totally uniform, bounding boxes are turned into small
BSP trees instead of being compared directly.
===================
*)

function SV_HullForBox(mins, maxs: PVector3f): Phull_t;
begin
  box_planes[0].dist := maxs[0];
  box_planes[1].dist := mins[0];
  box_planes[2].dist := maxs[1];
  box_planes[3].dist := mins[1];
  box_planes[4].dist := maxs[2];
  box_planes[5].dist := mins[2];

  result := @box_hull;
end;



(*
================
SV_HullForEntity

Returns a hull that can be used for testing or clipping an object of mins/maxs
size.
Offset is filled in to contain the adjustment that must be added to the
testing object's origin to get a point to use with the returned hull.
================
*)

function SV_HullForEntity(ent: Pedict_t; mins, maxs: PVector3f; offset: PVector3f): Phull_t;
var
  model: PBSPModelFile;
  size: TVector3f;
  hullmins, hullmaxs: TVector3f;
begin

// decide which clipping hull to use, based on the size
  if ent.v.solid = SOLID_BSP then
  begin // explicit hulls in the BSP model
    if ent.v.movetype <> MOVETYPE_PUSH then
      Sys_Error('SOLID_BSP without MOVETYPE_PUSH');

    model := sv.models[intval(ent.v.modelindex)];

    if (not Assigned(model)) or (model._type <> mod_brush) then
      Sys_Error('MOVETYPE_PUSH with a non bsp model');

    VectorSubtract(maxs, mins, @size);
    if size[0] < 3 then
      result := @model.hulls[0]
    else if size[0] <= 32 then
      result := @model.hulls[1]
    else
      result := @model.hulls[2];

// calculate an offset value to center the origin
    VectorSubtract(@result.clip_mins[0], mins, offset);
    VectorAdd(offset, @ent.v.origin[0], offset);
  end
  else
  begin // create a temp hull from bounding box sizes

    VectorSubtract(@ent.v.mins[0], maxs, @hullmins[0]);
    VectorSubtract(@ent.v.maxs[0], mins, @hullmaxs[0]);
    result := SV_HullForBox(@hullmins[0], @hullmaxs[0]);

    VectorCopy(@ent.v.origin[0], offset);
  end;

end;

(*
===============================================================================

ENTITY AREA CHECKING

===============================================================================
*)

type
  Pareanode_t = ^areanode_t;
  areanode_t = record
    axis: integer; // -1 := leaf node
    dist: single;
    children: array[0..1] of Pareanode_t;
    trigger_edicts: link_t;
    solid_edicts: link_t;
  end;

const
  AREA_DEPTH = 4;
  AREA_NODES = 32;

var
  sv_areanodes: array[0..AREA_NODES - 1] of areanode_t;
  sv_numareanodes: integer;

(*
===============
SV_CreateAreaNode

===============
*)

function SV_CreateAreaNode(depth: integer; mins, maxs: PVector3f): Pareanode_t;
var
  size: TVector3f;
  mins1, maxs1, mins2, maxs2: TVector3f;
  anode: Pareanode_t;
begin
  anode := @sv_areanodes[sv_numareanodes];
  inc(sv_numareanodes);

  ClearLink(@anode.trigger_edicts);
  ClearLink(@anode.solid_edicts);

  if depth = AREA_DEPTH then
  begin
    anode.axis := -1;
    anode.children[0] := nil;
    anode.children[1] := nil;
    Result := anode;
    exit;
  end;

  VectorSubtract(maxs, mins, @size[0]);
  if size[0] > size[1] then
    anode.axis := 0
  else
    anode.axis := 1;

  anode.dist := 0.5 * (maxs[anode.axis] + mins[anode.axis]);
  VectorCopy(mins, @mins1[0]);
  VectorCopy(mins, @mins2[0]);
  VectorCopy(maxs, @maxs1[0]);
  VectorCopy(maxs, @maxs2[0]);

  maxs1[anode.axis] := anode.dist;
  mins2[anode.axis] := anode.dist;

  anode.children[0] := SV_CreateAreaNode(depth + 1, @mins2[0], @maxs2[0]);
  anode.children[1] := SV_CreateAreaNode(depth + 1, @mins1[0], @maxs1[0]);

  Result := anode;
end;

(*
===============
SV_ClearWorld

===============
*)

procedure SV_ClearWorld;
begin
  SV_InitBoxHull;

  memset(@sv_areanodes[0], 0, SizeOf(sv_areanodes));
  sv_numareanodes := 0;
  SV_CreateAreaNode(0, @sv.worldmodel.mins[0], @sv.worldmodel.maxs[0]);
end;


(*
===============
SV_UnlinkEdict

===============
*)

procedure SV_UnlinkEdict(ent: Pedict_t);
begin
  if not Assigned(ent.area.prev) then
    exit; // not linked in anywhere

  RemoveLink(@ent.area);
  ent.area.prev := nil;
  ent.area.next := nil;
end;


(*
====================
SV_TouchLinks
====================
*)

procedure SV_TouchLinks(ent: Pedict_t; node: Pareanode_t);
label
  continue1;
var
  l, next: Plink_t;
  touch: Pedict_t;
  old_self, old_other: integer;
begin
// touch linked edicts
  l := node.trigger_edicts.next;
  while l <> @node.trigger_edicts do
  begin
    next := l.next;
    touch := EDICT_FROM_AREA(l);
    if touch = ent then
      goto continue1;

    if (not Boolean(touch.v.touch)) or (touch.v.solid <> SOLID_TRIGGER) then
      goto continue1;

    if (ent.v.absmin[0] > touch.v.absmax[0]) or
      (ent.v.absmin[1] > touch.v.absmax[1]) or
      (ent.v.absmin[2] > touch.v.absmax[2]) or
      (ent.v.absmax[0] < touch.v.absmin[0]) or
      (ent.v.absmax[1] < touch.v.absmin[1]) or
      (ent.v.absmax[2] < touch.v.absmin[2]) then
      goto continue1;

    old_self := pr_global_struct.self;
    old_other := pr_global_struct.other;

    pr_global_struct.self := EDICT_TO_PROG(touch);
    pr_global_struct.other := EDICT_TO_PROG(ent);
    pr_global_struct.time := sv.time;
    PR_ExecuteProgram(touch.v.touch);

    pr_global_struct.self := old_self;
    pr_global_struct.other := old_other;

    continue1:
    l := next;
  end;

// recurse down both sides
  if node.axis = -1 then
    exit;

  if ent.v.absmax[node.axis] > node.dist then
    SV_TouchLinks(ent, node.children[0]);
  if ent.v.absmin[node.axis] < node.dist then
    SV_TouchLinks(ent, node.children[1]);
end;


(*
===============
SV_FindTouchedLeafs

===============
*)

procedure SV_FindTouchedLeafs(ent: Pedict_t; node: Pmnode_t);
var
  splitplane: Pmplane_t;
  leaf: Pmleaf_t;
  sides: integer;
  leafnum: integer;
begin
  if node.contents = CONTENTS_SOLID then
    exit;

// add an efrag if the node is a leaf

  if node.contents < 0 then
  begin
    if ent.num_leafs = MAX_ENT_LEAFS then
      exit;

    leaf := Pmleaf_t(node);
    leafnum := (integer(leaf) - integer(sv.worldmodel.leafs)) div SizeOf(leaf^) - 1; //!!

    ent.leafnums[ent.num_leafs] := leafnum;
    inc(ent.num_leafs);
    exit;
  end;

// NODE_MIXED

  splitplane := node.plane;
  sides := BOX_ON_PLANE_SIDE(@ent.v.absmin[0], @ent.v.absmax[0], splitplane);

// recurse down the contacted sides
  if Boolval(sides and 1) then
    SV_FindTouchedLeafs(ent, node.children[0]);

  if Boolval(sides and 2) then
    SV_FindTouchedLeafs(ent, node.children[1]);
end;

(*
===============
SV_LinkEdict

===============
*)

procedure SV_LinkEdict(ent: Pedict_t; touch_triggers: qboolean);
var
  node: Pareanode_t;
begin
  if Assigned(ent.area.prev) then
    SV_UnlinkEdict(ent); // unlink from old position

  if ent = sv.edicts then
    exit; // don't add the world

  if ent.free then
    exit;

// set the abs box
  VectorAdd(@ent.v.origin[0], @ent.v.mins[0], @ent.v.absmin[0]);
  VectorAdd(@ent.v.origin[0], @ent.v.maxs[0], @ent.v.absmax[0]);

//
// to make items easier to pick up and allow them to be grabbed off
// of shelves, the abs sizes are expanded
//
  if Boolval(intval(ent.v.flags) and FL_ITEM) then
  begin
    ent.v.absmin[0] := ent.v.absmin[0] - 15;
    ent.v.absmin[1] := ent.v.absmin[1] - 15;
    ent.v.absmax[0] := ent.v.absmax[0] + 15;
    ent.v.absmax[1] := ent.v.absmax[1] + 15;
  end
  else
  begin // because movement is clipped an epsilon away from an actual edge,
        // we must fully check even when bounding boxes don't quite touch
    ent.v.absmin[0] := ent.v.absmin[0] - 1;
    ent.v.absmin[1] := ent.v.absmin[1] - 1;
    ent.v.absmin[2] := ent.v.absmin[2] - 1;
    ent.v.absmax[0] := ent.v.absmax[0] + 1;
    ent.v.absmax[1] := ent.v.absmax[1] + 1;
    ent.v.absmax[2] := ent.v.absmax[2] + 1;
  end;

// link to PVS leafs
  ent.num_leafs := 0;
  if boolval(ent.v.modelindex) then
    SV_FindTouchedLeafs(ent, sv.worldmodel.nodes);

  if ent.v.solid = SOLID_NOT then
    exit;

// find the first node that the ent's box crosses
  node := @sv_areanodes[0];
  while true do
  begin
    if node.axis = -1 then
      break;
    if ent.v.absmin[node.axis] > node.dist then
      node := node.children[0]
    else if ent.v.absmax[node.axis] < node.dist then
      node := node.children[1]
    else
      break; // crosses the node
  end;

// link it in

  if ent.v.solid = SOLID_TRIGGER then
    InsertLinkBefore(@ent.area, @node.trigger_edicts)
  else
    InsertLinkBefore(@ent.area, @node.solid_edicts);

// if touch_triggers, touch all entities at this node and decend for more
  if touch_triggers then
    SV_TouchLinks(ent, @sv_areanodes[0]);
end;



(*
===============================================================================

POINT TESTING IN HULLS

===============================================================================
*)

(*
==================
SV_HullPointContents

==================
*)

function SV_HullPointContents(hull: Phull_t; num: integer; p: PVector3f): integer;
var
  d: single;
  node: PBSPClipNode;
  plane: Pmplane_t;
begin
  while num >= 0 do
  begin
    if (num < hull.firstclipnode) or (num > hull.lastclipnode) then
      Sys_Error('SV_HullPointContents: bad node number');

    node := @PBSPClipNodeArray(hull.clipnodes)[num];
    plane := @Pmplane_tArray(hull.planes)[node.PlaneIndex];

    if plane.PlaneType < 3 then
      d := p[plane.PlaneType] - plane.dist
    else
      d := VectorDotProduct(@plane.normal[0], p) - plane.dist;
    if d < 0 then
      num := node.children[1]
    else
      num := node.children[0];
  end;

  result := num;
end;


(*
==================
SV_PointContents

==================
*)

function SV_TruePointContents(p: PVector3f): integer;
begin
  result := SV_HullPointContents(@sv.worldmodel.hulls[0], 0, p);
end;

function SV_PointContents(p: PVector3f): integer;
begin
  result := SV_TruePointContents(p);
  if (result <= CONTENTS_CURRENT_0) and (result >= CONTENTS_CURRENT_DOWN) then
    result := CONTENTS_WATER;
end;

//===========================================================================

(*
============
SV_TestEntityPosition

This could be a lot more efficient...
============
*)

function SV_TestEntityPosition(ent: Pedict_t): Pedict_t;
var
  trace: trace_t;
begin
  trace := SV_MoveEdict(@ent.v.origin[0], @ent.v.mins[0], @ent.v.maxs[0], @ent.v.origin[0], 0, ent);

  if trace.startsolid then
    result := sv.edicts
  else
    result := nil;
end;


(*
===============================================================================

LINE TESTING IN HULLS

===============================================================================
*)

// 1/32 epsilon to keep floating point happy
const
  DIST_EPSILON = 0.03125;

(*
==================
SV_RecursiveHullCheck

==================
*)
//var
// numnums: integer = 0;
// nums: array[0..1000000] of integer;

function SV_RecursiveHullCheck(hull: Phull_t; num: integer; p1f, p2f: single; p1, p2: PVector3f; trace: Ptrace_t): qboolean;
var
  node: PBSPClipNode;
  plane: Pmplane_t;
  t1, t2: single;
  frac: single;
  i: integer;
  mid: TVector3f;
  side: integer;
  midf: single;
begin
//nums[numnums] := num;
//inc(numnums);

// check for empty
  if num < 0 then
  begin
    if num <> CONTENTS_SOLID then
    begin
      trace.allsolid := false;
      if num = CONTENTS_EMPTY then
        trace.inopen := true
      else
        trace.inwater := true;
    end
    else
      trace.startsolid := true;
    result := true; // empty
    exit;
  end;

  if (num < hull.firstclipnode) or (num > hull.lastclipnode) then
    Sys_Error('SV_RecursiveHullCheck: bad node number');

//
// find the point distances
//
  node := @PBSPClipNodeArray(hull.clipnodes)[num];
  plane := @Pmplane_tArray(hull.planes)[node.PlaneIndex];

  if plane.PlaneType < 3 then
  begin
    t1 := p1[plane.PlaneType] - plane.dist;
    t2 := p2[plane.PlaneType] - plane.dist;
  end
  else
  begin
    t1 := VectorDotProduct(@plane.normal, p1) - plane.dist;
    t2 := VectorDotProduct(@plane.normal, p2) - plane.dist;
  end;

  if (t1 >= 0) and (t2 >= 0) then
  begin
    result := SV_RecursiveHullCheck(hull, node.children[0], p1f, p2f, p1, p2, trace);
    exit;
  end;
  if (t1 < 0) and (t2 < 0) then
  begin
    result := SV_RecursiveHullCheck(hull, node.children[1], p1f, p2f, p1, p2, trace);
    exit;
  end;

// put the crosspoint DIST_EPSILON pixels on the near side
  if t1 < 0 then frac := (t1 + DIST_EPSILON) / (t1 - t2)
  else frac := (t1 - DIST_EPSILON) / (t1 - t2);
  if frac < 0 then frac := 0;
  if frac > 1 then frac := 1;

  midf := p1f + (p2f - p1f) * frac;
  for i := 0 to 2 do
    mid[i] := p1[i] + frac * (p2[i] - p1[i]);

  side := Integer {intval}(t1 < 0); //!!

// move up to the node
  if not SV_RecursiveHullCheck(hull, node.children[side], p1f, midf, p1, @mid[0], trace) then
  begin
    result := false;
    exit;
  end;

  if SV_HullPointContents(hull, node.children[side xor 1], @mid) <> CONTENTS_SOLID then
  begin // go past the node
    result := SV_RecursiveHullCheck(hull, node.children[side xor 1], midf, p2f, @mid[0], p2, trace);
    exit;
  end;

  if trace.allsolid then
  begin
    result := false; // never got out of the solid area
    exit;
  end;

//==================
// the other side of the node is solid, this is the impact point
//==================
  if side = 0 then
  begin
    VectorCopy(@plane.normal[0], @trace.plane.normal[0]);
    trace.plane.dist := plane.dist;
  end
  else
  begin
    VectorSubtract(@vec3_origin[0], @plane.normal[0], @trace.plane.normal[0]);
    trace.plane.dist := -plane.dist;
  end;

  while SV_HullPointContents(hull, hull.firstclipnode, @mid[0]) = CONTENTS_SOLID do
  begin // shouldn't really happen, but does occasionally
    frac := frac - 0.1;
    if frac < 0 then
    begin
      trace.fraction := midf;
      VectorCopy(@mid[0], @trace.endpos[0]);
      Con_DPrintf('backup past 0'#10);
      result := false;
      exit;
    end;
    midf := p1f + (p2f - p1f) * frac;
    for i := 0 to 2 do
      mid[i] := p1[i] + frac * (p2[i] - p1[i]);
  end;

  trace.fraction := midf;
  VectorCopy(@mid[0], @trace.endpos[0]);

  result := false;
end;


(*
==================
SV_ClipMoveToEntity

Handles selection or creation of a clipping hull, and offseting (and
eventually rotation) of the _end points
==================
*)

function SV_ClipMoveToEntity(ent: Pedict_t; start, mins, maxs, _end: PVector3f): trace_t;
var
  offset: TVector3f;
  start_l, end_l: TVector3f;
  hull: Phull_t;
begin

// fill in a default trace
  memset(@result, 0, SizeOf(trace_t));
  result.fraction := 1;
  result.allsolid := true;
  VectorCopy(_end, @result.endpos[0]);

// get the clipping hull
  hull := SV_HullForEntity(ent, mins, maxs, @offset[0]);

  VectorSubtract(start, @offset[0], @start_l[0]);
  VectorSubtract(_end, @offset[0], @end_l[0]);

// result a line through the apropriate clipping hull
  SV_RecursiveHullCheck(hull, hull.firstclipnode, 0, 1, @start_l[0], @end_l[0], @result);

// fix result up by the offset
  if result.fraction <> 1 then
    VectorAdd(@result.endpos[0], @offset[0], @result.endpos[0]);

// did we clip the move?
  if (result.fraction < 1) or result.startsolid then
    result.ent := ent;

end;

//===========================================================================

(*
====================
SV_ClipToLinks

Mins and maxs enclose the entire area swept by the move
====================
*)

procedure SV_ClipToLinks(node: Pareanode_t; clip: Pmoveclip_t);
label
  continue1;
var
  l, next: Plink_t;
  touch: Pedict_t;
  trace: trace_t;
begin
// touch linked edicts
  l := node.solid_edicts.next;
  while l <> @node.solid_edicts do
  begin
    next := l.next;
    touch := EDICT_FROM_AREA(l);
    if touch.v.solid = SOLID_NOT then
      goto continue1;
    if touch = clip.passedict then
      goto continue1;
    if touch.v.solid = SOLID_TRIGGER then
      Sys_Error('Trigger in clipping list');

    if (clip._type = MOVE_NOMONSTERS) and (touch.v.solid <> SOLID_BSP) then
      goto continue1;

    if (clip.boxmins[0] > touch.v.absmax[0]) or
      (clip.boxmins[1] > touch.v.absmax[1]) or
      (clip.boxmins[2] > touch.v.absmax[2]) or
      (clip.boxmaxs[0] < touch.v.absmin[0]) or
      (clip.boxmaxs[1] < touch.v.absmin[1]) or
      (clip.boxmaxs[2] < touch.v.absmin[2]) then
      goto continue1;

    if boolval(clip.passedict) and boolval(clip.passedict.v.size[0]) and (not boolval(touch.v.size[0])) then
      goto continue1; // points never interact

  // might intersect, so do an exact clip
    if clip.trace.allsolid then
      exit;
    if Assigned(clip.passedict) then
    begin
      if PROG_TO_EDICT(touch.v.owner) = clip.passedict then
        goto continue1; // don't clip against own missiles
      if PROG_TO_EDICT(clip.passedict.v.owner) = touch then
        goto continue1; // don't clip against owner
    end;

    if Boolval(intval(touch.v.flags) and FL_MONSTER) then
      trace := SV_ClipMoveToEntity(touch, clip.start, @clip.mins2[0], @clip.maxs2[0], clip._end)
    else
      trace := SV_ClipMoveToEntity(touch, clip.start, clip.mins, clip.maxs, clip._end);
    if trace.allsolid or trace.startsolid or (trace.fraction < clip.trace.fraction) then
    begin
      trace.ent := touch;
      if clip.trace.startsolid then
      begin
        clip.trace := trace;
        clip.trace.startsolid := true;
      end
      else
        clip.trace := trace;
    end
    else if trace.startsolid then
      clip.trace.startsolid := true;

    continue1:
    l := next;
  end;

// recurse down both sides
  if node.axis = -1 then
    exit;

  if clip.boxmaxs[node.axis] > node.dist then
    SV_ClipToLinks(node.children[0], clip);
  if clip.boxmins[node.axis] < node.dist then
    SV_ClipToLinks(node.children[1], clip);
end;


(*
==================
SV_MoveBounds
==================
*)

procedure SV_MoveBounds(start, mins, maxs, _end, boxmins, boxmaxs: PVector3f);
var
  i: integer;
begin
  for i := 0 to 2 do
  begin
    if _end[i] > start[i] then
    begin
      boxmins[i] := start[i] + mins[i] - 1;
      boxmaxs[i] := _end[i] + maxs[i] + 1;
    end
    else
    begin
      boxmins[i] := _end[i] + mins[i] - 1;
      boxmaxs[i] := start[i] + maxs[i] + 1;
    end;
  end;
end;

(*
==================
SV_Move // changed to SV_MoveEdict
==================
*)

function SV_MoveEdict(start, mins, maxs, _end: PVector3f; _type: integer; passedict: Pedict_t): trace_t;
var
  clip: moveclip_t;
  i: integer;
begin
  memset(@clip, 0, SizeOf(moveclip_t));

// clip to world
  clip.trace := SV_ClipMoveToEntity(sv.edicts, start, mins, maxs, _end);

  clip.start := start;
  clip._end := _end;
  clip.mins := mins;
  clip.maxs := maxs;
  clip._type := _type;
  clip.passedict := passedict;

  if _type = MOVE_MISSILE then
  begin
    for i := 0 to 2 do
    begin
      clip.mins2[i] := -15;
      clip.maxs2[i] := 15;
    end;
  end
  else
  begin
    VectorCopy(mins, @clip.mins2[0]);
    VectorCopy(maxs, @clip.maxs2[0]);
  end;


// create the bounding box of the entire move
  SV_MoveBounds(start, @clip.mins2[0], @clip.maxs2[0], _end, @clip.boxmins[0], @clip.boxmaxs[0]);

// clip to entities
  SV_ClipToLinks(@sv_areanodes[0], @clip);

  result := clip.trace;
end;

end.

