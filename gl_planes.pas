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

unit gl_planes;

interface

uses
  q_delphi,
  q_vector,
  bspconst;

const
  VERTEXSIZE = 7;

// plane_t structure
// !!! if this is changed, it must be changed in asm_i386.h too !!!
type
  Pmplane_t = ^mplane_t;
  mplane_t = record
    normal: TVector3f;
    dist: single;
    PlaneType: byte; // for texture axis selection and fast side tests
    signbits: byte; // signx + signy<<1 + signz<<1
    pad: array[0..1] of byte;
  end;
  mplane_tArray = array[0..$FFFF] of mplane_t;
  Pmplane_tArray = ^mplane_tArray;


type
  PPmsurface_t = ^Pmsurface_t;
  Pmsurface_t = ^msurface_t;
  Ptexture_t = ^texture_t;
  PPtexture_t = ^Ptexture_t;
  Pglpoly_t = ^glpoly_t;
  Pmedge_t = ^medge_t;
  Pmtexinfo_t = ^mtexinfo_t;
  Pmnode_t = ^mnode_t;


  msurface_t = record
    visframe: integer; // should be drawn when node is crossed
    plane: Pmplane_t;
    flags: integer;

    firstedge: integer; // look up in model->surfedges[], negative numbers
    numedges: integer; // are backwards edges

    texturemins: array[0..1] of short;
    extents: array[0..1] of short;

    light_s, light_t: integer; // gl lightmap coordinates

    polys: Pglpoly_t; // multiple if warped
    texturechain: Pmsurface_t;

    texinfo: Pmtexinfo_t;

// lighting info
    dlightframe: integer;
    dlightbits: integer;

    lightmaptexturenum: integer;
    styles: array[0..MAXLIGHTMAPS - 1] of byte;
    cached_light: array[0..MAXLIGHTMAPS - 1] of integer; // values currently used in lightmap
    cached_dlight: qboolean; // true if dynamic light in cache
    samples: PByteArray; // [numstyles*surfsize]
  end;
  msurface_tArray = array[0..$FFFF] of msurface_t;
  Pmsurface_tArray = ^msurface_tArray;
  msurface_tPArray = array[0..$FFFF] of Pmsurface_t;
  Pmsurface_tPArray = ^msurface_tPArray;

  texture_t = record
    name: array[0..15] of char;
    width: unsigned;
    height: unsigned;
    gl_texturenum: integer;
    texturechain: Pmsurface_t; // for gl_texsort drawing
    anim_total: integer; // total tenths in sequence ( 0 = no)
    anim_min, anim_max: integer; // time for this frame min <=time< max
    anim_next: Ptexture_t; // in the animation sequence
    alternate_anims: Ptexture_t; // bmodels in frmae 1 use these
    offsets: array[0..MIPLEVELS - 1] of unsigned; // four mip maps stored
  end;
  texture_tPArray = array[0..$FFFF] of Ptexture_t;
  Ptexture_tPArray = ^texture_tPArray;

  glpoly_t = record
    next: Pglpoly_t;
    chain: Pglpoly_t;
    numverts: integer;
    flags: integer; // for SURF_UNDERWATER
    verts: array[0..3, 0..VERTEXSIZE - 1] of single; // variable sized (xyz s1t1 s2t2)
  end;

  mnode_t = record
// common with leaf
    contents: integer; // 0, to differentiate from leafs
    visframe: integer; // node needs to be traversed if current

    minmaxs: array[0..5] of single; // for bounding box culling

    parent: Pmnode_t;

// node specific
    plane: Pmplane_t;
    children: array[0..1] of Pmnode_t;

    firstsurface: unsigned_short;
    numsurfaces: unsigned_short;
  end;
  mnode_tArray = array[0..$FFFF] of mnode_t;
  Pmnode_tArray = ^mnode_tArray;

  medge_t = record
    v: array[0..1] of unsigned_short;
    cachededgeoffset: unsigned_int;
  end;
  medge_tArray = array[0..$FFFF] of medge_t;
  Pmedge_tArray = ^medge_tArray;

  mtexinfo_t = record
    vecs: array[0..1, 0..3] of single;
    mipadjust: single;
    texture: Ptexture_t;
    flags: integer;
  end;
  mtexinfo_tArray = array[0..$FFFF] of mtexinfo_t;
  Pmtexinfo_tArray = ^mtexinfo_tArray;

// JVAL moved from mathlib.c
function BoxOnPlaneSide(emins: PVector3f; emaxs: PVector3f; p: Pmplane_t): integer;

// JVAL moved from mathlib.h
function BOX_ON_PLANE_SIDE(emins: PVector3f; emaxs: PVector3f; p: Pmplane_t): integer;

implementation

uses
  sys_win;

(*
==================
BOPS_Error

Split out like this for ASM to call.
==================
*)

procedure BOPS_Error;
begin
  Sys_Error('BoxOnPlaneSide:  Bad signbits');
end;


(*
==================
BoxOnPlaneSide

Returns 1, 2, or 1 + 2
==================
*)

function BoxOnPlaneSide(emins: PVector3f; emaxs: PVector3f; p: Pmplane_t): integer;
var
  dist1, dist2: single;
begin
// general case
  case p.signbits of // JVAL change with if??? same values to dist1, dist2
    0:
      begin
        dist1 := p.normal[0] * emaxs[0] + p.normal[1] * emaxs[1] + p.normal[2] * emaxs[2];
        dist2 := p.normal[0] * emins[0] + p.normal[1] * emins[1] + p.normal[2] * emins[2];
      end;
    1:
      begin
        dist1 := p.normal[0] * emins[0] + p.normal[1] * emaxs[1] + p.normal[2] * emaxs[2];
        dist2 := p.normal[0] * emaxs[0] + p.normal[1] * emins[1] + p.normal[2] * emins[2];
      end;
    2:
      begin
        dist1 := p.normal[0] * emaxs[0] + p.normal[1] * emins[1] + p.normal[2] * emaxs[2];
        dist2 := p.normal[0] * emins[0] + p.normal[1] * emaxs[1] + p.normal[2] * emins[2];
      end;
    3:
      begin
        dist1 := p.normal[0] * emins[0] + p.normal[1] * emins[1] + p.normal[2] * emaxs[2];
        dist2 := p.normal[0] * emaxs[0] + p.normal[1] * emaxs[1] + p.normal[2] * emins[2];
      end;
    4:
      begin
        dist1 := p.normal[0] * emaxs[0] + p.normal[1] * emaxs[1] + p.normal[2] * emins[2];
        dist2 := p.normal[0] * emins[0] + p.normal[1] * emins[1] + p.normal[2] * emaxs[2];
      end;
    5:
      begin
        dist1 := p.normal[0] * emins[0] + p.normal[1] * emaxs[1] + p.normal[2] * emins[2];
        dist2 := p.normal[0] * emaxs[0] + p.normal[1] * emins[1] + p.normal[2] * emaxs[2];
      end;
    6:
      begin
        dist1 := p.normal[0] * emaxs[0] + p.normal[1] * emins[1] + p.normal[2] * emins[2];
        dist2 := p.normal[0] * emins[0] + p.normal[1] * emaxs[1] + p.normal[2] * emaxs[2];
      end;
    7:
      begin
        dist1 := p.normal[0] * emins[0] + p.normal[1] * emins[1] + p.normal[2] * emins[2];
        dist2 := p.normal[0] * emaxs[0] + p.normal[1] * emaxs[1] + p.normal[2] * emaxs[2];
      end;
  else
    begin
      dist1 := 0;
      dist2 := 0; // shut up compiler
      BOPS_Error;
    end;
  end;

  result := 0;
  if dist1 >= p.dist then
    result := 1;
  if dist2 < p.dist then
    result := result or 2;
end;

function BOX_ON_PLANE_SIDE(emins: PVector3f; emaxs: PVector3f; p: Pmplane_t): integer;
begin
  if p.PlaneType < 3 then
  begin
    if p.dist <= emins[p.PlaneType] then
      result := 1
    else if p.dist >= emaxs[p.PlaneType] then
      result := 2
    else
      result := 3
  end
  else
    result := BoxOnPlaneSide(emins, emaxs, p);
end;

end.

