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

unit gl_rsurf;

// r_surf.c: surface-related refresh code

interface

uses
  q_delphi,
  gl_planes,
  gl_model_h;

var
  skytexturenum: integer;

procedure R_AddDynamicLights(surf: Pmsurface_t);
procedure R_BuildLightMap(surf: Pmsurface_t; dest: PByteArray; stride: integer);
function  R_TextureAnimation(base: Ptexture_t): Ptexture_t;
procedure GL_DisableMultitexture;
procedure GL_EnableMultitexture;
procedure R_DrawSequentialPoly(s: Pmsurface_t);
procedure DrawGLWaterPoly(p: Pglpoly_t);
procedure DrawGLWaterPolyLightmap(p: Pglpoly_t);
procedure DrawGLPoly(p: Pglpoly_t);
procedure R_BlendLightmaps;
procedure R_RenderBrushPoly(fa: Pmsurface_t);
procedure R_RenderDynamicLightmaps(fa: Pmsurface_t);
procedure R_MirrorChain(s: Pmsurface_t);
procedure R_DrawWaterSurfaces;
procedure DrawTextureChains;
procedure R_DrawBrushModel(e: Pentity_t);
procedure R_RecursiveWorldNode(node: Pmnode_t);
procedure R_DrawWorld;
procedure R_MarkLeaves;
function AllocBlock(w, h: integer; var x, y: integer): integer;
procedure BuildSurfaceDisplayList(fa: Pmsurface_t);
procedure GL_CreateSurfaceLightmap(surf: Pmsurface_t);
procedure GL_BuildLightmaps;

implementation

uses
  q_vector,
  quakedef,
  OpenGL12,
  mathlib,
  client,
  gl_rmain,
  bspconst,
  gl_texture,
  sys_win,
  gl_defs,
  gl_vidnt,
  gl_warp,
  gl_rlight,
  cl_main_h,
  gl_rmain_h,
  host_h,
  gl_refrag,
  gl_model,
  gl_sky,
  zone,
  common;

const
  GL_RGBA4 = 0;

var
  lightmap_bytes: integer; // 1, 2, or 4

  lightmap_textures: integer;

  blocklights: array[0..256 * 256 - 1] of unsigned;

const
  BLOCK_WIDTH = 128;
  BLOCK_HEIGHT = 128;

const
  MAX_LIGHTMAPS = 256;

type
  glRect_t = record
    l, t, w, h: byte; // JVAL was unsigned char
  end;
  PglRect_t = ^glRect_t;

var
  lightmap_polys: array[0..MAX_LIGHTMAPS - 1] of Pglpoly_t;
  lightmap_modified: array[0..MAX_LIGHTMAPS - 1] of qboolean;
  lightmap_rectchange: array[0..MAX_LIGHTMAPS - 1] of glRect_t;

  allocated: array[0..MAX_LIGHTMAPS - 1, 0..BLOCK_WIDTH - 1] of integer;

// the lightmap texture data needs to be kept in
// main memory so texsubimage can update properly
  lightmaps: array[0..4 * MAX_LIGHTMAPS * BLOCK_WIDTH * BLOCK_HEIGHT - 1] of byte;

// For gl_texsort 0
  skychain: Pmsurface_t = nil;
  waterchain: Pmsurface_t = nil;

(*
===============
R_AddDynamicLights
===============
*)

procedure R_AddDynamicLights(surf: Pmsurface_t);
var
  lnum: integer;
  sd, td: integer;
  dist, rad, minlight: single;
  impact, local: TVector3f;
  s, t: integer;
  i: integer;
  smax, tmax: integer;
  tex: Pmtexinfo_t;
begin
  smax := (surf.extents[0] div 16) + 1;
  tmax := (surf.extents[1] div 16) + 1;
  tex := surf.texinfo;

  for lnum := 0 to MAX_DLIGHTS - 1 do
  begin
    if (surf.dlightbits and (1 shl lnum)) = 0 then
      continue; // not lit by this light

    rad := cl_dlights[lnum].radius;
    dist := VectorDotProduct(@cl_dlights[lnum].origin, @surf.plane.normal) - surf.plane.dist;
    rad := rad - abs(dist);
    minlight := cl_dlights[lnum].minlight;
    if rad < minlight then
      continue;
    minlight := rad - minlight;

    for i := 0 to 2 do
    begin
      impact[i] := cl_dlights[lnum].origin[i] - surf.plane.normal[i] * dist;
    end;

    // JVAL mayby loop for code below?
    local[0] := VectorDotProduct(@impact, @tex.vecs[0]) + tex.vecs[0][3];
    local[1] := VectorDotProduct(@impact, @tex.vecs[1]) + tex.vecs[1][3];

    local[0] := local[0] - surf.texturemins[0];
    local[1] := local[1] - surf.texturemins[1];

    for t := 0 to tmax - 1 do
    begin
      td := intval(local[1] - t * 16);
      if td < 0 then
        td := -td;
      for s := 0 to smax - 1 do
      begin
        sd := intval(local[0] - s * 16);
        if sd < 0 then
          sd := -sd;
        if sd > td then
          dist := sd + (td / 2) // JVAL mayby not div, just /
        else
          dist := td + (sd / 2);
        if dist < minlight then
          blocklights[t * smax + s] := blocklights[t * smax + s] + uintval((rad - dist) * 256);
      end;
    end;
  end;
end;


(*
===============
R_BuildLightMap

Combine and scale multiple lightmaps into the 8.8 format in blocklights
===============
*)

procedure R_BuildLightMap(surf: Pmsurface_t; dest: PByteArray; stride: integer);
label
  store;
var
  smax, tmax: integer;
  t: integer;
  i, j, size: integer;
  lightmap: PByteArray;
  scale: unsigned;
  maps: integer;
  bl: Punsigned;
  r, g, b: Integer;
begin
  surf.cached_dlight := (surf.dlightframe = r_framecount);

  smax := (surf.extents[0] div 16) + 1;
  tmax := (surf.extents[1] div 16) + 1;
  size := smax * tmax;
  lightmap := surf.samples;
  if gl_lightmap_format = GL_RGB then size := size * 3;

// set to full bright if no light data
  if (r_fullbright.value <> 0) or (cl.worldmodel.lightdata = nil) then
  begin
    for i := 0 to size - 1 do
      blocklights[i] := 255 * 256;
    goto store;
  end;

// clear to no light
  for i := 0 to size - 1 do
    blocklights[i] := 0;

// add all the lightmaps
  if lightmap <> nil then
  begin
    maps := 0;
    while (maps < MAXLIGHTMAPS) and (surf.styles[maps] <> 255) do
    begin
      scale := d_lightstylevalue[surf.styles[maps]];
      surf.cached_light[maps] := scale; // 8.8 fraction
      for i := 0 to size - 1 do
        blocklights[i] := blocklights[i] + lightmap[i] * scale;
      lightmap := PByteArray(@lightmap[size]); // skip to next lightmap
      inc(maps);
    end;
  end;

// add all the dynamic lights
  if surf.dlightframe = r_framecount then
    R_AddDynamicLights(surf);

// bound, invert, and shift
  store:
  case gl_lightmap_format of
    GL_RGBA:
      begin
        stride := stride - (smax shl 2);
        bl := @blocklights[0];
        for i := 0 to tmax - 1 do
        begin
          for j := 0 to smax - 1 do
          begin
            t := bl^;
            inc(bl);
            t := (t shr 7);
            if t > 255 then
              t := 255;
            dest[3] := 255 - t;
            dest := PByteArray(@dest[4]);
          end;
          dest := PByteArray(@dest[stride]);
        end;
      end;
    GL_RGB:
      begin
        begin
          stride := stride - (smax * 3);
          bl := @blocklights[0];
          for i := 0 to tmax - 1 do
          begin
            for j := 0 to smax - 1 do
            begin
              r := bl^ shr 7; inc(bl);
              g := bl^ shr 7; inc(bl);
              b := bl^ shr 7; inc(bl);
              if r > 255 then r := 255;
              if g > 255 then g := 255;
              if b > 255 then b := 255;
              dest[0] := 255 - r;
              dest[1] := 255 - g;
              dest[2] := 255 - b;
              dest := PByteArray(@dest[3]);
            end;
            dest := PByteArray(@dest[stride]);
          end;
        end;
      end;
    GL_ALPHA,
      GL_LUMINANCE,
      GL_INTENSITY:
      begin
        bl := @blocklights[0];
        for i := 0 to tmax - 1 do
        begin
          for j := 0 to smax - 1 do
          begin
            t := bl^ shr 7; inc(bl);
            if t > 255 then t := 255;
            dest[j] := 255 - t;
          end;
          dest := PByteArray(@dest[stride]);
        end;
      end;
  else
    Sys_Error('Bad lightmap format');
  end;
end;


(*
===============
R_TextureAnimation

Returns the proper texture for a given time and base texture
===============
*)

function R_TextureAnimation(base: Ptexture_t): Ptexture_t;
var
  reletive: integer;
  count: integer;
begin
  if currententity.frame <> 0 then
  begin
    if base.alternate_anims <> nil then
      base := base.alternate_anims;
  end;

  if base.anim_total = 0 then
  begin
    result := base;
    exit;
  end;

  reletive := intval(cl.time * 10) mod base.anim_total;

  count := 0;
  while (base.anim_min > reletive) or (base.anim_max <= reletive) do
  begin
    base := base.anim_next;
    if base = nil then Sys_Error('R_TextureAnimation: broken cycle');
    if count > 100 then Sys_Error('R_TextureAnimation: infinite cycle');
    inc(count);
  end;

  result := base;
end;


(*
=============================================================

  BRUSH MODELS

=============================================================
*)

procedure GL_DisableMultitexture;
begin
  if mtexenabled then
  begin
    glDisable(GL_TEXTURE_2D);
    GL_SelectTexture(TEXTURE0_SGIS);
    mtexenabled := false;
  end;
end;

procedure GL_EnableMultitexture;
begin
  if gl_mtexable then
  begin
    GL_SelectTexture(TEXTURE1_SGIS);
    glEnable(GL_TEXTURE_2D);
    mtexenabled := true;
  end;
end;

(*
================
R_DrawSequentialPoly

Systems that have fast state and texture changes can
just do everything as it passes with no need to sort
================
*)

procedure R_DrawSequentialPoly(s: Pmsurface_t);
var
  p: Pglpoly_t;
  v: PfloatArray;
  i: integer;
  t: Ptexture_t;
  nv: TVector3f;
  theRect: PglRect_t;
begin
  //
  // normal lightmaped poly
  //

  if s.flags and (SURF_DRAWSKY or SURF_DRAWTURB or SURF_UNDERWATER) = 0 then
  begin
    R_RenderDynamicLightmaps(s);
    if gl_mtexable then
    begin
      p := s.polys;

      t := R_TextureAnimation(s.texinfo.texture);
      // Binds world to texture env 0
      GL_SelectTexture(TEXTURE0_SGIS);
      GL_Bind(t.gl_texturenum);
      glTexEnvf(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_REPLACE);
      // Binds lightmap to texenv 1
      GL_EnableMultitexture; // Same as SelectTexture (TEXTURE1)
      GL_Bind(lightmap_textures + s.lightmaptexturenum);
      i := s.lightmaptexturenum;
      if lightmap_modified[i] then
      begin
        lightmap_modified[i] := false;
        theRect := @lightmap_rectchange[i];
        glTexSubImage2D(GL_TEXTURE_2D, 0, 0, theRect.t,
          BLOCK_WIDTH, theRect.h, gl_lightmap_format, GL_UNSIGNED_BYTE,
          @lightmaps[(i * BLOCK_HEIGHT + theRect.t) * BLOCK_WIDTH * lightmap_bytes]);
        theRect.l := BLOCK_WIDTH;
        theRect.t := BLOCK_HEIGHT;
        theRect.h := 0;
        theRect.w := 0;
      end;
      glTexEnvf(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_BLEND);
      glBegin(GL_POLYGON);
      v := @p.verts[0]; // JVAL Check this
      for i := 0 to p.numverts - 1 do
      begin
        qglMTexCoord2fSGIS(TEXTURE0_SGIS, v[3], v[4]);
        qglMTexCoord2fSGIS(TEXTURE1_SGIS, v[5], v[6]);
        glVertex3fv(@v[0]);
        v := @v[VERTEXSIZE]; // JVAL check this
      end;
      glEnd;
      exit;
    end
    else
    begin
      p := s.polys;

      t := R_TextureAnimation(s.texinfo.texture);
      GL_Bind(t.gl_texturenum);
      glBegin(GL_POLYGON);
      v := @p.verts[0];
      for i := 0 to p.numverts - 1 do
      begin
        glTexCoord2f(v[3], v[4]);
        glVertex3fv(@v[0]);
        v := @v[VERTEXSIZE]; // JVAL check this
      end;
      glEnd;

      GL_Bind(lightmap_textures + s.lightmaptexturenum);
      glEnable(GL_BLEND);
      glBegin(GL_POLYGON);
      v := @p.verts[0]; // JVAL Check this
      for i := 0 to p.numverts - 1 do
      begin
        glTexCoord2f(v[5], v[6]);
        glVertex3fv(@v[0]);
        v := @v[VERTEXSIZE]; // JVAL check this
      end;
      glEnd;

      glDisable(GL_BLEND);
    end;

    exit;
  end;

  //
  // subdivided water surface warp
  //

  if s.flags and SURF_DRAWTURB <> 0 then
  begin
    GL_DisableMultitexture;
    GL_Bind(s.texinfo.texture.gl_texturenum);
    EmitWaterPolys(s);
    exit;
  end;

  //
  // subdivided sky warp
  //
  if s.flags and SURF_DRAWSKY <> 0 then
  begin
    if gl_drawskydome.value = 0 then
    begin
      GL_DisableMultitexture;
      GL_Bind(solidskytexture);
      speedscale := realtime * 8;
      speedscale := speedscale - (intval(speedscale) and (not 127));

      EmitSkyPolys(s);

      glEnable(GL_BLEND);
      GL_Bind(alphaskytexture);
      speedscale := realtime * 16;
      speedscale := speedscale - (intval(speedscale) and (not 127));
      EmitSkyPolys(s);

      glDisable(GL_BLEND);
    end
    else
      dodrawsky := true;
    exit;
  end;

  //
  // underwater warped with lightmap
  //
  R_RenderDynamicLightmaps(s);
  if gl_mtexable then
  begin
    p := s.polys; // JVAL check this

    t := R_TextureAnimation(s.texinfo.texture);
    GL_SelectTexture(TEXTURE0_SGIS);
    GL_Bind(t.gl_texturenum);
    glTexEnvf(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_REPLACE);
    GL_EnableMultitexture;
    GL_Bind(lightmap_textures + s.lightmaptexturenum);
    i := s.lightmaptexturenum;
    if lightmap_modified[i] then
    begin
      lightmap_modified[i] := false;
      theRect := @lightmap_rectchange[i];
      glTexSubImage2D(GL_TEXTURE_2D, 0, 0, theRect.t,
        BLOCK_WIDTH, theRect.h, gl_lightmap_format, GL_UNSIGNED_BYTE,
        @lightmaps[(i * BLOCK_HEIGHT + theRect.t) * BLOCK_WIDTH * lightmap_bytes]);
      theRect.l := BLOCK_WIDTH;
      theRect.t := BLOCK_HEIGHT;
      theRect.h := 0;
      theRect.w := 0;
    end;
    glTexEnvf(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_BLEND);
    glBegin(GL_TRIANGLE_FAN);
    v := @p.verts[0]; // JVAL Check this
    for i := 0 to p.numverts - 1 do
    begin
      qglMTexCoord2fSGIS(TEXTURE0_SGIS, v[3], v[4]);
      qglMTexCoord2fSGIS(TEXTURE1_SGIS, v[5], v[6]);
      // JVAL mayby optimize sin() ??
      nv[0] := v[0] + 8 * sin(v[1] * 0.05 + realtime) * sin(v[2] * 0.05 + realtime);
      nv[1] := v[1] + 8 * sin(v[0] * 0.05 + realtime) * sin(v[2] * 0.05 + realtime);
      nv[2] := v[2];

      glVertex3fv(@nv);
      v := @v[VERTEXSIZE]; // JVAL check this
    end;
    glEnd;
  end
  else
  begin
    p := s.polys; // JVAL check this

    t := R_TextureAnimation(s.texinfo.texture);
    GL_Bind(t.gl_texturenum);
    DrawGLWaterPoly(p);

    GL_Bind(lightmap_textures + s.lightmaptexturenum);
    glEnable(GL_BLEND);
    DrawGLWaterPolyLightmap(p);
    glDisable(GL_BLEND);
  end;
end;


(*
================
DrawGLWaterPoly

Warp the vertex coordinates
================
*)

procedure DrawGLWaterPoly(p: Pglpoly_t);
var
  i: integer;
  v: PFloatArray;
//  nv: TVector3f;
begin
  GL_DisableMultitexture;

  glBegin(GL_TRIANGLE_FAN);
  v := @p.verts[0];
  for i := 0 to p.numverts - 1 do
  begin
    glTexCoord2f(v[3], v[4]);

    // JVAL mayby optimize this -> eg tmp := 8 * sin(v[2] * 0.05 + realtime)
{    nv[0] := v[0] + 8 * sin(v[1] * 0.05 + realtime) * sin(v[2] * 0.05 + realtime);
    nv[1] := v[1] + 8 * sin(v[0] * 0.05 + realtime) * sin(v[2] * 0.05 + realtime);
    nv[2] := v[2];}

//    glVertex3fv(@nv);
    glVertex3fv(@v[0]);
    v := @v[VERTEXSIZE];
  end;
  glEnd;
end;

procedure DrawGLWaterPolyLightmap(p: Pglpoly_t);
var
  i: integer;
  v: PFloatArray;
//  nv: TVector3f;
begin
  GL_DisableMultitexture;

  glBegin(GL_TRIANGLE_FAN);
  v := @p.verts[0];
  for i := 0 to p.numverts - 1 do
  begin
    glTexCoord2f(v[5], v[6]);

    // JVAL mayby optimize this -> tmp := 8 * sin(v[2]*0.05+realtime) ??
{    nv[0] := v[0] + 8 * sin(v[1] * 0.05 + realtime) * sin(v[2] * 0.05 + realtime);
    nv[1] := v[1] + 8 * sin(v[0] * 0.05 + realtime) * sin(v[2] * 0.05 + realtime);
    nv[2] := v[2];}

//    glVertex3fv(@nv);
    glVertex3fv(@v[0]);
    v := @v[VERTEXSIZE];
  end;
  glEnd;
end;

(*
================
DrawGLPoly
================
*)

procedure DrawGLPoly(p: Pglpoly_t);
var
  i: integer;
  v: PFloatArray;
begin
  glBegin(GL_POLYGON);
  v := @p.verts[0];
  for i := 0 to p.numverts - 1 do
  begin
    glTexCoord2f(v[3], v[4]);
    glVertex3fv(@v[0]);
    v := @v[VERTEXSIZE];
  end;
  glEnd;
end;


(*
================
R_BlendLightmaps
================
*)

procedure R_BlendLightmaps;
var
  i, j: integer;
  p: Pglpoly_t;
  v: PFloatArray;
  theRect: PglRect_t;
begin
  if r_fullbright.value <> 0 then
    exit;
  if gl_texsort.value = 0 then
    exit;

  glDepthMask(false); // don't bother writing Z

  if gl_lightmap_format = GL_RGBA then
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)
  else if gl_lightmap_format = GL_RGB then
    glBlendFunc(GL_ZERO, GL_ONE_MINUS_SRC_COLOR)
  else if gl_lightmap_format = GL_LUMINANCE then
    glBlendFunc(GL_ZERO, GL_ONE_MINUS_SRC_COLOR)
  else if gl_lightmap_format = GL_INTENSITY then
  begin
    glTexEnvf(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_MODULATE);
    glColor4f(0, 0, 0, 1);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
  end;

  if r_lightmap.value = 0 then
    glEnable(GL_BLEND);

  for i := 0 to MAX_LIGHTMAPS - 1 do
  begin
    p := lightmap_polys[i];
    if p = nil then
      continue;
    GL_Bind(lightmap_textures + i);
    if lightmap_modified[i] then
    begin
      lightmap_modified[i] := false;
      theRect := @lightmap_rectchange[i];
//      glTexImage2D (GL_TEXTURE_2D, 0, lightmap_bytes
//      , BLOCK_WIDTH, BLOCK_HEIGHT, 0,
//      gl_lightmap_format, GL_UNSIGNED_BYTE, lightmaps+i*BLOCK_WIDTH*BLOCK_HEIGHT*lightmap_bytes);
//      glTexImage2D (GL_TEXTURE_2D, 0, lightmap_bytes
//        , BLOCK_WIDTH, theRect->h, 0,
//        gl_lightmap_format, GL_UNSIGNED_BYTE, lightmaps+(i*BLOCK_HEIGHT+theRect->t)*BLOCK_WIDTH*lightmap_bytes);
      glTexSubImage2D(GL_TEXTURE_2D, 0, 0, theRect.t,
        BLOCK_WIDTH, theRect.h, gl_lightmap_format, GL_UNSIGNED_BYTE,
        @lightmaps[(i * BLOCK_HEIGHT + theRect.t) * BLOCK_WIDTH * lightmap_bytes]);
      theRect.l := BLOCK_WIDTH;
      theRect.t := BLOCK_HEIGHT;
      theRect.h := 0;
      theRect.w := 0;
    end;
    while p <> nil do
    begin
      if p.flags and SURF_UNDERWATER <> 0 then
        DrawGLWaterPolyLightmap(p)
      else
      begin
        glBegin(GL_POLYGON);
        v := @p.verts[0];
        for j := 0 to p.numverts - 1 do
        begin
          glTexCoord2f(v[5], v[6]);
          glVertex3fv(@v[0]);
          v := @v[VERTEXSIZE];
        end;
        glEnd;
      end;
      p := p.chain;
    end;
  end;

  glDisable(GL_BLEND);
  if gl_lightmap_format = GL_LUMINANCE then glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)
  else if gl_lightmap_format = GL_INTENSITY then
  begin
    glTexEnvf(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_REPLACE);
    glColor4f(1, 1, 1, 1);
  end;

  glDepthMask(true); // back to normal Z buffering
end;

(*
================
R_RenderBrushPoly
================
*)

procedure R_RenderBrushPoly(fa: Pmsurface_t);
label
  dynamic1;
var
  t: Ptexture_t;
  base: PByte;
  maps: integer;
  theRect: PglRect_t;
  smax, tmax: integer;
begin
  inc(c_brush_polys);

  if fa.flags and SURF_DRAWSKY <> 0 then
  begin // warp texture, no lightmaps
    EmitBothSkyLayers(fa);
    exit;
  end;

  t := R_TextureAnimation(fa.texinfo.texture);
  GL_Bind(t.gl_texturenum);

  if fa.flags and SURF_DRAWTURB <> 0 then
  begin // warp texture, no lightmaps
    EmitWaterPolys(fa);
    exit;
  end;

  if fa.flags and SURF_UNDERWATER <> 0 then
    DrawGLWaterPoly(fa.polys)
  else
    DrawGLPoly(fa.polys);

  // add the poly to the proper lightmap chain

  fa.polys.chain := lightmap_polys[fa.lightmaptexturenum];
  lightmap_polys[fa.lightmaptexturenum] := fa.polys;

  // check for lightmap modification
  maps := 0;
  while (maps < MAXLIGHTMAPS) and (fa.styles[maps] <> 255) do
  begin
    if d_lightstylevalue[fa.styles[maps]] <> fa.cached_light[maps] then
      goto dynamic1;
    inc(maps);
  end;

  if (fa.dlightframe = r_framecount) or // dynamic this frame
    fa.cached_dlight then // dynamic previously
  begin
    dynamic1:
    if r_dynamic.value <> 0 then
    begin
      lightmap_modified[fa.lightmaptexturenum] := true;
      theRect := @lightmap_rectchange[fa.lightmaptexturenum];
      if fa.light_t < theRect.t then
      begin
        if theRect.h <> 0 then
          theRect.h := theRect.h + theRect.t - fa.light_t;
        theRect.t := fa.light_t;
      end;
      if fa.light_s < theRect.l then
      begin
        if theRect.w <> 0 then
          theRect.w := theRect.w + theRect.l - fa.light_s;
        theRect.l := fa.light_s;
      end;
      smax := (fa.extents[0] div 16) + 1;
      tmax := (fa.extents[1] div 16) + 1;
      if (theRect.w + theRect.l) < (fa.light_s + smax) then
        theRect.w := (fa.light_s - theRect.l) + smax;
      if (theRect.h + theRect.t) < (fa.light_t + tmax) then
        theRect.h := (fa.light_t - theRect.t) + tmax;
      base := @lightmaps[fa.lightmaptexturenum * lightmap_bytes * BLOCK_WIDTH * BLOCK_HEIGHT];
      inc(base, fa.light_t * BLOCK_WIDTH * lightmap_bytes + fa.light_s * lightmap_bytes);
      R_BuildLightMap(fa, PByteArray(base), BLOCK_WIDTH * lightmap_bytes);
    end;
  end;
end;

(*
================
R_RenderDynamicLightmaps
Multitexture
================
*)

procedure R_RenderDynamicLightmaps(fa: Pmsurface_t);
label
  dynamic1;
var
  base: PByte;
  maps: integer;
  theRect: PglRect_t;
  smax, tmax: integer;
begin
  inc(c_brush_polys);

  if fa.flags and (SURF_DRAWSKY or SURF_DRAWTURB) <> 0 then
    exit;

  fa.polys.chain := lightmap_polys[fa.lightmaptexturenum];
  lightmap_polys[fa.lightmaptexturenum] := fa.polys;

  // check for lightmap modification
  maps := 0;
  while (maps < MAXLIGHTMAPS) and (fa.styles[maps] <> 255) do
  begin
    if d_lightstylevalue[fa.styles[maps]] <> fa.cached_light[maps] then
      goto dynamic1;
    inc(maps);
  end;

  if (fa.dlightframe = r_framecount) or // dynamic this frame
    fa.cached_dlight then // dynamic previously
  begin
    dynamic1:
    if boolval(r_dynamic.value) then
    begin
      lightmap_modified[fa.lightmaptexturenum] := true;
      theRect := @lightmap_rectchange[fa.lightmaptexturenum];
      if fa.light_t < theRect.t then
      begin
        if boolval(theRect.h) then
          theRect.h := theRect.h + theRect.t - fa.light_t;
        theRect.t := fa.light_t;
      end;
      if fa.light_s < theRect.l then
      begin
        if boolval(theRect.w) then
          theRect.w := theRect.w + theRect.l - fa.light_s;
        theRect.l := fa.light_s;
      end;
      smax := (fa.extents[0] div 16) + 1;
      tmax := (fa.extents[1] div 16) + 1;
      if (theRect.w + theRect.l) < (fa.light_s + smax) then
        theRect.w := (fa.light_s - theRect.l) + smax;
      if (theRect.h + theRect.t) < (fa.light_t + tmax) then
        theRect.h := (fa.light_t - theRect.t) + tmax;
      base := @lightmaps[fa.lightmaptexturenum * lightmap_bytes * BLOCK_WIDTH * BLOCK_HEIGHT];
      inc(base, fa.light_t * BLOCK_WIDTH * lightmap_bytes + fa.light_s * lightmap_bytes);
      R_BuildLightMap(fa, PByteArray(base), BLOCK_WIDTH * lightmap_bytes);
    end;
  end;
end;

(*
================
R_MirrorChain
================
*)

procedure R_MirrorChain(s: Pmsurface_t);
begin
  if mirror then
    exit;
  mirror := true;
  mirror_plane := s.plane;
end;

(*
================
R_DrawWaterSurfaces
================
*)

procedure R_DrawWaterSurfaces;
var
  i: integer;
  s: Pmsurface_t;
  t: Ptexture_t;
begin
  if (r_wateralpha.value = 1.0) and (gl_texsort.value <> 0) then
    exit;

  //
  // go back to the world matrix
  //

  glLoadMatrixf(@r_world_matrix);

  if r_wateralpha.value < 1.0 then
  begin
    glEnable(GL_BLEND);
    glColor4f(1, 1, 1, r_wateralpha.value);
    glTexEnvf(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_MODULATE);
  end;

  if gl_texsort.value = 0 then
  begin
    if waterchain = nil then
      exit;

    s := waterchain;
    while s <> nil do
    begin
      GL_Bind(s.texinfo.texture.gl_texturenum);
      EmitWaterPolys(s);

      s := s.texturechain;
    end;

    waterchain := nil;
  end
  else
  begin
    for i := 0 to cl.worldmodel.numtextures - 1 do
    begin
      t := cl.worldmodel.textures[i];
      if t = nil then
        continue;
      s := t.texturechain;
      if s = nil then
        continue;
      if s.flags and SURF_DRAWTURB = 0 then
        continue;

      // set modulate mode explicitly

      GL_Bind(t.gl_texturenum);


      while s <> nil do
      begin
        EmitWaterPolys(s);
        s := s.texturechain;
      end;

      t.texturechain := nil;
    end;

  end;

  if r_wateralpha.value < 1.0 then
  begin
    glTexEnvf(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_REPLACE);

    glColor4f(1, 1, 1, 1);
    glDisable(GL_BLEND);
  end;

end;

(*
================
DrawTextureChains
================
*)

procedure DrawTextureChains;
var
  i: integer;
  s: Pmsurface_t;
  t: Ptexture_t;
begin
  if gl_texsort.value = 0 then
  begin
    GL_DisableMultitexture;

    if skychain <> nil then
    begin
      R_DrawSkyChain(skychain);
      skychain := nil;
    end;

    exit;
  end;

  for i := 0 to cl.worldmodel.numtextures - 1 do
  begin
    t := cl.worldmodel.textures[i];
    if t = nil then
      continue;
    s := t.texturechain;
    if s = nil then
      continue;
    if i = skytexturenum then
      R_DrawSkyChain(s)
    else if (i = mirrortexturenum) and (r_mirroralpha.value <> 1.0) then
    begin
      R_MirrorChain(s);
      continue;
    end
    else
    begin
      if ((s.flags and SURF_DRAWTURB) <> 0) and (r_wateralpha.value <> 1.0) then
        continue; // draw translucent water later
      while s <> nil do
      begin
        R_RenderBrushPoly(s);
        s := s.texturechain
      end;
    end;

    t.texturechain := nil;
  end;
end;

(*
=================
R_DrawBrushModel
=================
*)

procedure R_DrawBrushModel(e: Pentity_t);
var
  k: integer;
  mins, maxs: TVector3f;
  i: integer;
  psurf: Pmsurface_t;
  dot: single;
  pplane: Pmplane_t;
  clmodel: PBSPModelFile;
  rotated: qboolean;
  temp: TVector3f;
  _forward, right, up: TVector3f;
  nd: Pmnode_t;
begin
  currententity := e;
  currenttexture := -1;

  clmodel := e.model;

  if (e.angles[0] <> 0) or (e.angles[1] <> 0) or (e.angles[2] <> 0) then
  begin
    rotated := true;
    for i := 0 to 2 do
    begin
      mins[i] := e.origin[i] - clmodel.radius;
      maxs[i] := e.origin[i] + clmodel.radius;
    end
  end
  else
  begin
    rotated := false;
    VectorAdd(@e.origin, @clmodel.mins, @mins);
    VectorAdd(@e.origin, @clmodel.maxs, @maxs);
  end;

  if R_CullBox(@mins, @maxs) then
    exit;

  glColor3f(1, 1, 1);
  ZeroMemory(@lightmap_polys, SizeOf(lightmap_polys));

  VectorSubtract(@r_refdef.vieworg, @e.origin, @modelorg);
  if rotated then
  begin
    VectorCopy(@modelorg, @temp);
    AngleVectors(@e.angles, @_forward, @right, @up);
    modelorg[0] := VectorDotProduct(@temp, @_forward);
    modelorg[1] := -VectorDotProduct(@temp, @right);
    modelorg[2] := VectorDotProduct(@temp, @up);
  end;

  psurf := @clmodel.surfaces[clmodel.firstmodelsurface];

// calculate dynamic lighting for bmodel if it's not an
// instanced model
  if (clmodel.firstmodelsurface <> 0) and (not boolval(gl_flashblend.value)) then
  begin
    for k := 0 to MAX_DLIGHTS - 1 do
    begin
      if (cl_dlights[k].die < cl.time) or
        (not boolval(cl_dlights[k].radius)) then
        continue;

      nd := clmodel.nodes;
      inc(nd, clmodel.hulls[0].firstclipnode);

      R_MarkLights(@cl_dlights[k], (1 shl k), nd);
    end;
  end;

  glPushMatrix;
  e.angles[0] := -e.angles[0]; // stupid quake bug
  R_RotateForEntity(e);
  e.angles[0] := -e.angles[0]; // stupid quake bug

  //
  // draw texture
  //
  for i := 0 to clmodel.nummodelsurfaces - 1 do
  begin
  // find which side of the node we are on
    pplane := psurf.plane;

    dot := VectorDotProduct(@modelorg, @pplane.normal) - pplane.dist;

  // draw the polygon
    if (boolval(psurf.flags and SURF_PLANEBACK) and (dot < -BACKFACE_EPSILON)) or
      (not boolval(psurf.flags and SURF_PLANEBACK) and (dot > BACKFACE_EPSILON)) then
    begin
      if boolval(gl_texsort.value) then
        R_RenderBrushPoly(psurf)
      else
        R_DrawSequentialPoly(psurf);
    end;
    inc(psurf);
  end;

  R_BlendLightmaps;

  glPopMatrix;
end;

(*
=============================================================

  WORLD MODEL

=============================================================
*)

(*
================
R_RecursiveWorldNode
================
*)

procedure R_RecursiveWorldNode(node: Pmnode_t);
label
  continue1;
var
  c, side: integer;
  plane: Pmplane_t;
  surf: Pmsurface_t;
  pleaf: Pmleaf_t;
  dot: double;
begin
  if node.contents = CONTENTS_SOLID then
    exit; // solid

  if node.visframe <> r_visframecount then
    exit;
  if R_CullBox(@node.minmaxs, @node.minmaxs[3]) then
    exit;

// if a leaf node, draw stuff
  if node.contents < 0 then
  begin
    pleaf := Pmleaf_t(node);

    for c := 0 to pleaf.nummarksurfaces - 1 do
      pleaf.firstmarksurface[c].visframe := r_framecount;


  // deal with model fragments in this leaf
    if pleaf.efrags <> nil then
      R_StoreEfrags(@pleaf.efrags);

    exit;
  end;

// node is just a decision point, so go down the apropriate sides

// find which side of the node we are on
  plane := node.plane;

  case plane.PlaneType of
    PLANE_X: dot := modelorg[0] - plane.dist;
    PLANE_Y: dot := modelorg[1] - plane.dist;
    PLANE_Z: dot := modelorg[2] - plane.dist;
  else
    dot := VectorDotProduct(@modelorg, @plane.normal) - plane.dist;
  end;

  if dot >= 0 then
    side := 0
  else
    side := 1;

// recurse down the children, front side first
  R_RecursiveWorldNode(node.children[side]);

// draw stuff
  c := node.numsurfaces;

  if c > 0 then
  begin
    surf := @cl.worldmodel.surfaces[node.firstsurface];

    if dot < -BACKFACE_EPSILON then
      side := SURF_PLANEBACK
    else if dot > BACKFACE_EPSILON then
      side := 0;

    while c > 0 do
    begin
      if surf.visframe <> r_framecount then
        goto continue1;

      // don't backface underwater surfaces, because they warp
      if (surf.flags and SURF_UNDERWATER = 0) and ((dot < 0) xor boolval(surf.flags and SURF_PLANEBACK)) then // JVAL check this!! SOS
        goto continue1; // wrong side

      // if sorting by texture, just store it out
      if gl_texsort.value <> 0 then
      begin
        if not mirror or (surf.texinfo.texture <> cl.worldmodel.textures[mirrortexturenum]) then
        begin
          surf.texturechain := surf.texinfo.texture.texturechain;
          surf.texinfo.texture.texturechain := surf;
        end
      end
      else if surf.flags and SURF_DRAWSKY <> 0 then
      begin
        surf.texturechain := skychain;
        skychain := surf;
      end
      else if surf.flags and SURF_DRAWTURB <> 0 then
      begin
        surf.texturechain := waterchain;
        waterchain := surf;
      end
      else
        R_DrawSequentialPoly(surf);
      continue1:
      inc(surf);
      dec(c);
    end;

  end;

// recurse down the back side
  if side = 0 then
    node := node.children[1]
  else
    node := node.children[0];

  R_RecursiveWorldNode(node);
end;



(*
=============
R_DrawWorld
=============
*)

procedure R_DrawWorld;
var
  ent: entity_t;
begin
  ZeroMemory(@ent, SizeOf(ent));
  ent.model := cl.worldmodel;

  VectorCopy(@r_refdef.vieworg, @modelorg);

  currententity := @ent;
  currenttexture := -1;

  glColor3f(1, 1, 1);
  ZeroMemory(@lightmap_polys, SizeOf(lightmap_polys));
  R_RecursiveWorldNode(cl.worldmodel.nodes);

  DrawTextureChains;

  GL_DrawSky;

  R_BlendLightmaps;
end;


(*
===============
R_MarkLeaves
===============
*)

procedure R_MarkLeaves;
var
  vis: PByteArray;
  node: Pmnode_t;
  i: integer;
  solid: array[0..4095] of byte; // JVAL mayby static?
begin
  if (r_oldviewleaf = r_viewleaf) and (r_novis.value = 0) then
    exit;

  if mirror then
    exit;

  inc(r_visframecount);
  r_oldviewleaf := r_viewleaf;

  if r_novis.value <> 0 then
  begin
    vis := @solid[0];
    memset(@solid, $FF, (cl.worldmodel.numleafs + 7) div 8);
  end
  else
    vis := Mod_LeafPVS(r_viewleaf, cl.worldmodel);

  for i := 0 to cl.worldmodel.numleafs - 1 do
  begin
    if vis[i div 8] and (1 shl (i and 7)) <> 0 then
    begin
      node := Pmnode_t(@cl.worldmodel.leafs[i + 1]);
      repeat
        if node.visframe = r_visframecount then
          break;
        node.visframe := r_visframecount;
        node := node.parent;
      until node = nil;
    end;
  end;
end;



(*
=============================================================================

  LIGHTMAP ALLOCATION

=============================================================================
*)

// returns a texture number and the position inside it

function AllocBlock(w, h: integer; var x, y: integer): integer;
var
  i, j: integer;
  best, best2: integer;
  texnum: integer;
begin
  for texnum := 0 to MAX_LIGHTMAPS - 1 do
  begin
    best := BLOCK_HEIGHT;

    for i := 0 to BLOCK_WIDTH - w - 1 do
    begin
      best2 := 0;

      for j := 0 to w - 1 do
      begin
        if allocated[texnum][i + j] >= best then
          break;
        if allocated[texnum][i + j] > best2 then
          best2 := allocated[texnum][i + j];
      end;
      if j = w then
      begin // this is a valid spot
        x := i;
        y := best2;
        best := best2;
      end;
    end;

    if best + h > BLOCK_HEIGHT then
      continue;

    for i := 0 to w - 1 do
      allocated[texnum][x + i] := best + h;

    result := texnum;
    exit;
  end;
  result := -1; //Shut up compiler

  Sys_Error('AllocBlock: full');
end;


var
  r_pcurrentvertbase: Pmvertex_tArray;
  currentmodel: PBSPModelFile;
  nColinElim: integer = 0;

(*
================
BuildSurfaceDisplayList
================
*)

procedure BuildSurfaceDisplayList(fa: Pmsurface_t);
const
  COLINEAR_EPSILON = 0.001;
var
  i, j, k, lindex, lnumverts: integer;
  pedges, r_pedge: Pmedge_t;
  vec: PVector3f;
  s, t: single;
  poly: Pglpoly_t;
  v1, v2: TVector3f;
  prev, this, next: PVector3f;
begin
// reconstruct the polygon
  pedges := @currentmodel.edges[0];
  lnumverts := fa.numedges;

  //
  // draw texture
  //
  poly := Hunk_Alloc(SizeOf(glpoly_t) + (lnumverts - 4) * VERTEXSIZE * SizeOf(single));
  poly.next := fa.polys;
  poly.flags := fa.flags;
  fa.polys := poly;
  poly.numverts := lnumverts;

  for i := 0 to lnumverts - 1 do
  begin
    lindex := currentmodel.surfedges[fa.firstedge + i];

    if lindex > 0 then
    begin
      r_pedge := pedges;
      inc(r_pedge, lindex);
      vec := @r_pcurrentvertbase[r_pedge.v[0]].position[0];
    end
    else
    begin
      r_pedge := pedges;
      inc(r_pedge, -lindex);
      vec := @r_pcurrentvertbase[r_pedge.v[1]].position[0];
    end;
    s := VectorDotProduct(vec, @fa.texinfo.vecs[0]) + fa.texinfo.vecs[0][3];
    s := s / fa.texinfo.texture.width;

    t := VectorDotProduct(vec, @fa.texinfo.vecs[1]) + fa.texinfo.vecs[1][3];
    t := t / fa.texinfo.texture.height;

    VectorCopy(vec, @poly.verts[i]);
    poly.verts[i][3] := s;
    poly.verts[i][4] := t;

    //
    // lightmap texture coordinates
    //
    s := VectorDotProduct(vec, @fa.texinfo.vecs[0]) + fa.texinfo.vecs[0][3];
    s := s - fa.texturemins[0];
    s := s + fa.light_s * 16;
    s := s + 8;
    s := s / (BLOCK_WIDTH * 16); //fa->texinfo->texture->width;

    t := VectorDotProduct(vec, @fa.texinfo.vecs[1]) + fa.texinfo.vecs[1][3];
    t := t - fa.texturemins[1];
    t := t + fa.light_t * 16;
    t := t + 8;
    t := t / (BLOCK_HEIGHT * 16); //fa->texinfo->texture->height;

    poly.verts[i][5] := s;
    poly.verts[i][6] := t;
  end;

  //
  // remove co-linear points - Ed
  //
  if not boolval(gl_keeptjunctions.value) and not boolval(fa.flags and SURF_UNDERWATER) then
  begin
    i := 0;
    while i < lnumverts do
    begin

      prev := @poly.verts[(i + lnumverts - 1) mod lnumverts];
      this := @poly.verts[i];
      next := @poly.verts[(i + 1) mod lnumverts];

      VectorSubtract(this, prev, @v1);
      VectorNormalize(@v1);
      VectorSubtract(next, prev, @v2);
      VectorNormalize(@v2);

      // skip co-linear points
      if (abs(v1[0] - v2[0]) <= COLINEAR_EPSILON) and
        (abs(v1[1] - v2[1]) <= COLINEAR_EPSILON) and
        (abs(v1[2] - v2[2]) <= COLINEAR_EPSILON) then
      begin
        for j := i + 1 to lnumverts - 1 do
        begin
          for k := 0 to VERTEXSIZE - 1 do
            poly.verts[j - 1][k] := poly.verts[j][k];
        end;
        dec(lnumverts);
        inc(nColinElim);
        // retry next vertex next time, which is now current vertex
        dec(i);
      end;
      inc(i);
    end;
  end;
  poly.numverts := lnumverts;

end;

(*
========================
GL_CreateSurfaceLightmap
========================
*)

procedure GL_CreateSurfaceLightmap(surf: Pmsurface_t);
var
  smax, tmax: integer;
  base: PByte;
begin
  if surf.flags and (SURF_DRAWSKY or SURF_DRAWTURB) <> 0 then
    exit;

  smax := (surf.extents[0] div 16) + 1;
  tmax := (surf.extents[1] div 16) + 1;

  surf.lightmaptexturenum := AllocBlock(smax, tmax, surf.light_s, surf.light_t);
  base := @lightmaps[surf.lightmaptexturenum * lightmap_bytes * BLOCK_WIDTH * BLOCK_HEIGHT];
  inc(base, (surf.light_t * BLOCK_WIDTH + surf.light_s) * lightmap_bytes);
  R_BuildLightMap(surf, PByteArray(base), BLOCK_WIDTH * lightmap_bytes);
end;


(*
==================
GL_BuildLightmaps

Builds the lightmap texture
with all the surfaces from all brush models
==================
*)

procedure GL_BuildLightmaps;
var
  i, j: integer;
  m: PBSPModelFile;
//  extern qboolean isPermedia; // JVAL check where is declared
begin
  ZeroMemory(@allocated, SizeOf(allocated));

  r_framecount := 1; // no dlightcache

  if lightmap_textures = 0 then
  begin
    lightmap_textures := texture_extension_number;
    inc(texture_extension_number, MAX_LIGHTMAPS);
  end;

//  gl_lightmap_format := DEFAULT_LIGHTMAP_FORMAT;// GL_LUMINANCE;
  // default differently on the Permedia
  if isPermedia then gl_lightmap_format := GL_RGBA;

  if COM_CheckParm('-lm_1') <> 0 then gl_lightmap_format := GL_LUMINANCE;
  if COM_CheckParm('-lm_a') <> 0 then gl_lightmap_format := GL_ALPHA;
  if COM_CheckParm('-lm_i') <> 0 then gl_lightmap_format := GL_INTENSITY;
  if COM_CheckParm('-lm_2') <> 0 then gl_lightmap_format := GL_RGBA4;
  if COM_CheckParm('-lm_3') <> 0 then gl_lightmap_format := GL_RGB;
  if COM_CheckParm('-lm_4') <> 0 then gl_lightmap_format := GL_RGBA;

  case gl_lightmap_format of
    GL_RGBA: lightmap_bytes := 4;
    GL_RGB: lightmap_bytes := 3;
    GL_RGBA4: lightmap_bytes := 2;

    GL_LUMINANCE,
      GL_INTENSITY,
      GL_ALPHA:
      lightmap_bytes := 1;
  end;

  for j := 1 to MAX_MODELS - 1 do
  begin
    m := cl.model_precache[j];
    if m = nil then
      break;
    if m.name[0] = '*' then
      continue;
    r_pcurrentvertbase := m.vertexes;
    currentmodel := m;
    for i := 0 to m.numsurfaces - 1 do
    begin
      GL_CreateSurfaceLightmap(@m.surfaces[i]); // JVAL SOS
      if m.surfaces[i].flags and SURF_DRAWTURB <> 0 then
        continue;
      BuildSurfaceDisplayList(@m.surfaces[i]);
    end;
  end;

  if gl_texsort.value = 0 then
    GL_SelectTexture(TEXTURE1_SGIS);

  //
  // upload all lightmaps that were filled
  //
  for i := 0 to MAX_LIGHTMAPS - 1 do
  begin
    if allocated[i][0] = 0 then
      break; // no more used
    lightmap_modified[i] := false;
    lightmap_rectchange[i].l := BLOCK_WIDTH;
    lightmap_rectchange[i].t := BLOCK_HEIGHT;
    lightmap_rectchange[i].w := 0;
    lightmap_rectchange[i].h := 0;
    GL_Bind(lightmap_textures + i);
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexImage2D(GL_TEXTURE_2D, 0, lightmap_bytes,
      BLOCK_WIDTH, BLOCK_HEIGHT, 0,
      gl_lightmap_format, GL_UNSIGNED_BYTE,
      @lightmaps[i * BLOCK_WIDTH * BLOCK_HEIGHT * lightmap_bytes]);
  end;

  if gl_texsort.value = 0 then
    GL_SelectTexture(TEXTURE0_SGIS);

end;

end.

