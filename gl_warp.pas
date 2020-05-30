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

unit gl_warp;

// gl_warp.c -- sky and water polygons

interface

uses
  q_delphi,
  gl_planes;

var
  skytexturenum: integer;
  solidskytexture: integer;
  alphaskytexture: integer;
  speedscale: single; // for top sky and bottom sky

procedure R_InitSky(mt: Ptexture_t);
procedure GL_SubdivideSurface(fa: Pmsurface_t);
procedure EmitWaterPolys(fa: Pmsurface_t);
procedure EmitSkyPolys(fa: Pmsurface_t);
procedure EmitBothSkyLayers(fa: Pmsurface_t);
procedure R_DrawSkyChain(s: Pmsurface_t);

implementation

uses
  q_vector,
  mathlib,
  sys_win,
  gl_model,
  gl_sky,
  bspfile,
  OpenGL12,
  zone,
  host_h,
  cl_main_h,
  gl_rmain_h,
  gl_rsurf,
  gl_texture,
  gl_vidnt;

var
  warpface: Pmsurface_t;

//extern cvar_t gl_subdivide_size;

procedure BoundPoly(numverts: integer; verts: PFloatArray; mins: PVector3f; maxs: PVector3f);
var
  i, j: integer;
  v: Psingle;
begin
  mins[0] := 9999;
  mins[1] := 9999;
  mins[2] := 9999;
  maxs[0] := -9999;
  maxs[1] := -9999;
  maxs[2] := -9999;

  v := @verts[0];
  for i := 0 to numverts - 1 do
    for j := 0 to 2 do // JVAL mayby crack loop -> a bit faster ?
    begin
      if v^ < mins[j] then mins[j] := v^;
      if v^ > maxs[j] then maxs[j] := v^;
      inc(v);
    end;
end;

procedure SubdividePolygon(numverts: integer; verts: PFloatArray);
var
  i, j, k: integer;
  mins, maxs: TVector3f;
  m: single;
  v: Psingle;
  front, back: array[0..63] of TVector3f;
  f, b: integer;
  dist: array[0..63] of single;
  frac: single;
  poly: Pglpoly_t;
  s, t: single;
  tmp: single;
begin
  if numverts > 60 then
    Sys_Error('numverts = %d', [numverts]);

  BoundPoly(numverts, verts, @mins, @maxs);

  for i := 0 to 2 do
  begin
    m := (mins[i] + maxs[i]) * 0.5;
    m := gl_subdivide_size.value * floor(m / gl_subdivide_size.value + 0.5);
    if maxs[i] - m < 8 then
      continue;
    if m - mins[i] < 8 then
      continue;

    // cut it
    v := @verts[i];
    for j := 0 to numverts - 1 do
    begin
      dist[j] := v^ - m;
      inc(v, 3);
    end;

    // wrap cases
    dist[numverts] := dist[0];
    dec(v, i);
    VectorCopy(PVector3f(verts), PVector3f(v));

    f := 0;
    b := 0;
    v := @verts[0];
    for j := 0 to numverts - 1 do
    begin
      if dist[j] >= 0 then
      begin
        VectorCopy(PVector3f(v), @front[f]);
        inc(f);
      end;
      if dist[j] <= 0 then
      begin
        VectorCopy(PVector3f(v), @back[b]);
        inc(b);
      end;
      if (dist[j] = 0) or (dist[j + 1] = 0) then
      else if (dist[j] > 0) <> (dist[j + 1] > 0) then
      begin
        // clip point
        frac := dist[j] / (dist[j] - dist[j + 1]);
        for k := 0 to 2 do
        begin
          tmp := PVector3f(v)[k] + frac * (PVector3f(v)[3 + k] - PVector3f(v)[k]);
          front[f][k] := tmp;
          back[b][k] := tmp;
        end;
        inc(f);
        inc(b);
      end;
      inc(v, 3);
    end;

    SubdividePolygon(f, @front[0]);
    SubdividePolygon(b, @back[0]);
    exit;
  end;

  poly := Hunk_Alloc(SizeOf(glpoly_t) + (numverts - 4) * VERTEXSIZE * SizeOf(single));
  poly.next := warpface.polys;
  warpface.polys := poly;
  poly.numverts := numverts;
  for i := 0 to numverts - 1 do
  begin
    VectorCopy(@verts[0], @poly.verts[i]);
    s := VectorDotProduct(@verts[0], @warpface.texinfo.vecs[0]);
    t := VectorDotProduct(@verts[0], @warpface.texinfo.vecs[1]);
    poly.verts[i][3] := s;
    poly.verts[i][4] := t;
    verts := @verts[3];
  end;
end;

(*
================
GL_SubdivideSurface

Breaks a polygon up along axial 64 unit
boundaries so that turbulent and sky warps
can be done reasonably.
================
*)

procedure GL_SubdivideSurface(fa: Pmsurface_t);
var
  verts: array[0..63] of TVector3f;
  numverts: integer;
  i: integer;
  lindex: integer;
  vec: PVector3f;
begin
  warpface := fa;

  //
  // convert edges back to a normal polygon
  //
  numverts := 0;
  for i := 0 to fa.numedges - 1 do
  begin
    lindex := loadmodel.surfedges[fa.firstedge + i];

    if lindex > 0 then vec := @loadmodel.vertexes[loadmodel.edges[lindex].v[0]].position
    else vec := @loadmodel.vertexes[loadmodel.edges[-lindex].v[1]].position;
    VectorCopy(vec, @verts[numverts]);
    inc(numverts);
  end;

  SubdividePolygon(numverts, @verts[0]);
end;

//=========================================================



// speed up sin calculations - Ed
const
  turbsin: array[0..255] of single = (
{$INCLUDE gl_warp_sin.inc}
    );

const
  TURBSCALE = (256.0 / (2 * M_PI));

(*
=============
EmitWaterPolys

Does a water warp on the pre-fragmented glpoly_t chain
=============
*)

procedure EmitWaterPolys(fa: Pmsurface_t);
var
  p: Pglpoly_t;
  v: PFloatArray;
  i: integer;
  s, t, os, ot: single;
begin
  p := fa.polys;
  while p <> nil do
  begin
    glBegin(GL_POLYGON);
    v := @p.verts[0];
    for i := 0 to p.numverts - 1 do
    begin
      os := v[3];
      ot := v[4];

      s := os + turbsin[intval((ot * 0.125 + cl.time) * TURBSCALE) and 255];
      s := s * (1.0 / 64);

      t := ot + turbsin[intval((os * 0.125 + cl.time) * TURBSCALE) and 255];
      t := t * (1.0 / 64);

      glTexCoord2f(s, t);
      glVertex3fv(@v[0]);
      v := @v[VERTEXSIZE]; // JVAL check this
    end;
    glEnd;
    p := p.next;
  end;
end;




(*
=============
EmitSkyPolys
=============
*)

procedure EmitSkyPolys(fa: Pmsurface_t);
var
  p: Pglpoly_t;
  v: PVector3f;
  i: integer;
  s, t: single;
  dir: TVector3f;
  length: single;
begin
  p := fa.polys;
  while p <> nil do
  begin
    glBegin(GL_POLYGON);
    v := @p.verts[0];
    for i := 0 to p.numverts - 1 do
    begin
      VectorSubtract(v, @r_origin, @dir);
      dir[2] := dir[2] * 3; // flatten the sphere

      length := dir[0] * dir[0] + dir[1] * dir[1] + dir[2] * dir[2];
      length := sqrt(length);
      length := 6 * 63 / length;

      dir[0] := dir[0] * length;
      dir[1] := dir[1] * length;

      s := (speedscale + dir[0]) * (1.0 / 128);
      t := (speedscale + dir[1]) * (1.0 / 128);

      glTexCoord2f(s, t);
      glVertex3fv(@v[0]);

      v := @PFloatArray(v)[VERTEXSIZE]; // JVAL check this. mayby inc(v, VERTEXSIZE) ??
    end;
    glEnd;
    p := p.next;
  end;
end;

(*
===============
EmitBothSkyLayers

Does a sky warp on the pre-fragmented glpoly_t chain
This will be called for brushmodels, the world
will have them chained together.
===============
*)

procedure EmitBothSkyLayers(fa: Pmsurface_t);
begin
  if gl_drawskydome.value <> 0 then
  begin
    dodrawsky := True;
    exit;
  end;

  GL_DisableMultitexture;

  GL_Bind(solidskytexture);
  speedscale := realtime * 8;
  speedscale := speedscale - intval(speedscale) and (not 127); // JVAL check this

  EmitSkyPolys(fa);

  glEnable(GL_BLEND);
  GL_Bind(alphaskytexture);
  speedscale := realtime * 16;
  speedscale := speedscale - intval(speedscale) and (not 127); // JVAL check this

  EmitSkyPolys(fa);

  glDisable(GL_BLEND);
end;

(*
=================
R_DrawSkyChain
=================
*)

procedure R_DrawSkyChain(s: Pmsurface_t);
var
  fa: Pmsurface_t;
begin
  if gl_drawskydome.value <> 0 then
  begin
    dodrawsky := True;
    exit;
  end;

  GL_DisableMultitexture;

  // used when gl_texsort is on
  GL_Bind(solidskytexture);
  speedscale := realtime * 8;
  speedscale := speedscale - (intval(speedscale) and (not 127));

  fa := s;
  while fa <> nil do
  begin
    EmitSkyPolys(fa);
    fa := fa.texturechain;
  end;

  glEnable(GL_BLEND);
  GL_Bind(alphaskytexture);
  speedscale := realtime * 16;
  speedscale := speedscale - (intval(speedscale) and (not 127));

  fa := s;
  while fa <> nil do
  begin
    EmitSkyPolys(fa);
    fa := fa.texturechain;
  end;

  glDisable(GL_BLEND);
end;

procedure R_InitSky(mt: Ptexture_t);
var
  i, j, p: integer;
  src: PByteArray;
  trans: array[0..128 * 128 - 1] of unsigned;
  transpix: unsigned;
  r, g, b: integer;
  rgba: PUnsigned;
begin
  src := @(PByteArray(mt)[mt.offsets[0]]);

  // make an average value for the back to avoid
  // a fringe on the top level

  r := 0;
  g := 0;
  b := 0;
  for i := 0 to 127 do
    for j := 0 to 127 do
    begin
      p := src[i * 256 + j + 128];
      rgba := @d_8to24table[p];
      trans[(i * 128) + j] := rgba^;
      r := r + PByteArray(rgba)[0];
      g := g + PByteArray(rgba)[1];
      b := b + PByteArray(rgba)[2];
    end;

  PByteArray(@transpix)[0] := r div (128 * 128);
  PByteArray(@transpix)[1] := g div (128 * 128);
  PByteArray(@transpix)[2] := b div (128 * 128);
  PByteArray(@transpix)[3] := 0;


  if not boolval(solidskytexture) then
  begin
    solidskytexture := texture_extension_number;
    inc(texture_extension_number);
  end;
  GL_Bind(solidskytexture);
  glTexImage2D(GL_TEXTURE_2D, 0, gl_solid_format, 128, 128, 0, GL_RGBA, GL_UNSIGNED_BYTE, @trans);
  glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
  glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);


  for i := 0 to 127 do
    for j := 0 to 127 do
    begin
      p := src[i * 256 + j];
      if p = 0 then
        trans[(i * 128) + j] := transpix
      else
        trans[(i * 128) + j] := d_8to24table[p];
    end;

  if not boolval(alphaskytexture) then
  begin
    alphaskytexture := texture_extension_number;
    inc(texture_extension_number);
  end;
  GL_Bind(alphaskytexture);
  glTexImage2D(GL_TEXTURE_2D, 0, gl_alpha_format, 128, 128, 0, GL_RGBA, GL_UNSIGNED_BYTE, @trans);
  glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
  glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
end;


end.

