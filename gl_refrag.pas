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

unit gl_refrag;

interface

uses
  gl_model_h,
  gl_planes;

procedure R_RemoveEfrags(ent: Pentity_t);
procedure R_SplitEntityOnNode(node: Pmnode_t);
procedure R_AddEfrags(ent: Pentity_t);
procedure R_StoreEfrags(ppefrag: PPefrag_t);

implementation

uses
  q_vector,
  bspconst,
  client,
  cl_main_h,
  console,
  gl_rmain_h,
  sys_win;

var
  r_pefragtopnode: Pmnode_t;


//===========================================================================

(*
===============================================================================

          ENTITY FRAGMENT FUNCTIONS

===============================================================================
*)

var
  lastlink: PPefrag_t;

  r_emins, r_emaxs: TVector3f;

  r_addent: Pentity_t;


(*
================
R_RemoveEfrags

Call when removing an object from the world or moving it to another position
================
*)

procedure R_RemoveEfrags(ent: Pentity_t);
var
  ef, old, walk: Pefrag_t;
  prev: PPefrag_t;
begin
  ef := ent.efrag;

  while ef <> nil do
  begin
    prev := @ef.leaf.efrags;
    while true do
    begin
      walk := prev^;
      if walk = nil then
        break;
      if walk = ef then
      begin // remove this fragment
        prev^ := ef.leafnext;
        break;
      end
      else
        prev := @walk.leafnext;
    end;

    old := ef;
    ef := ef.entnext;

  // put it on the free list
    old.entnext := @cl.free_efrags[0];
    cl.free_efrags := Pefrag_tArray(old);
  end;

  ent.efrag := nil;
end;

(*
===================
R_SplitEntityOnNode
===================
*)

procedure R_SplitEntityOnNode(node: Pmnode_t);
var
  ef: Pefrag_t;
  splitplane: Pmplane_t;
  leaf: Pmleaf_t;
  sides: integer;
begin
  if node.contents = CONTENTS_SOLID then
    exit;

// add an efrag if the node is a leaf

  if node.contents < 0 then
  begin
    if r_pefragtopnode = nil then
      r_pefragtopnode := node;

    leaf := Pmleaf_t(node);

// grab an efrag off the free list
    ef := @cl.free_efrags[0];
    if ef = nil then
    begin
      Con_Printf('Too many efrags!'#10);
      exit; // no free fragments...
    end;
    cl.free_efrags := Pefrag_tArray(cl.free_efrags[0].entnext);

    ef.entity := r_addent;

// add the entity link
    lastlink^ := ef;
    lastlink := @ef.entnext;
    ef.entnext := nil;

// set the leaf links
    ef.leaf := leaf;
    ef.leafnext := leaf.efrags;
    leaf.efrags := ef;

    exit;
  end;

// NODE_MIXED

  splitplane := node.plane;
  sides := BOX_ON_PLANE_SIDE(@r_emins, @r_emaxs, splitplane);

  if sides = 3 then
  begin
  // split on this plane
  // if this is the first splitter of this bmodel, remember it
    if r_pefragtopnode = nil then
      r_pefragtopnode := node;
  end;

// recurse down the contacted sides
  if sides and 1 <> 0 then
    R_SplitEntityOnNode(node.children[0]);

  if sides and 2 <> 0 then
    R_SplitEntityOnNode(node.children[1]);
end;



(*
===========
R_AddEfrags
===========
*)

procedure R_AddEfrags(ent: Pentity_t);
var
  entmodel: PBSPModelFile;
  i: integer;
begin
  if ent.model = nil then
    exit;

  r_addent := ent;

  lastlink := @ent.efrag;
  r_pefragtopnode := nil;

  entmodel := ent.model;

  for i := 0 to 2 do
  begin
    r_emins[i] := ent.origin[i] + entmodel.mins[i];
    r_emaxs[i] := ent.origin[i] + entmodel.maxs[i];
  end;

  R_SplitEntityOnNode(cl.worldmodel.nodes);

  ent.topnode := r_pefragtopnode;
end;


(*
================
R_StoreEfrags

// FIXME: a lot of this goes away with edge-based
================
*)

procedure R_StoreEfrags(ppefrag: PPefrag_t);
var
  pent: Pentity_t;
  clmodel: PBSPModelFile;
  pefrag: Pefrag_t;
begin
  while ppefrag^ <> nil do
  begin
    pefrag := ppefrag^;
    pent := pefrag.entity;
    clmodel := pent.model;

    case clmodel._type of
      mod_alias,
        mod_brush,
        mod_sprite:
        begin
          pent := pefrag.entity;

          if (pent.visframe <> r_framecount) and
            (cl_numvisedicts < MAX_VISEDICTS) then
          begin
            cl_visedicts[cl_numvisedicts] := pent;
            inc(cl_numvisedicts);

            // mark that we've recorded this entity for this frame
            pent.visframe := r_framecount;
          end;

          ppefrag := @pefrag.leafnext;
        end;

    else
      Sys_Error('R_StoreEfrags: Bad entity type %d'#10, [Ord(clmodel._type)]);
    end;
  end;
end;

end.

