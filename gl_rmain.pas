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

unit gl_rmain;

// r_main.c

interface

uses
  q_delphi,
  q_vector,
  cvar,
  gl_model_h,
  gl_planes,
  render_h;

procedure R_RenderView;
procedure R_RotateForEntity(e: Pentity_t);
function R_CullBox(mins: PVector3f; maxs: PVector3f): qboolean;

const
  NUMVERTEXNORMALS = 162;

  r_avertexnormals: array[0..NUMVERTEXNORMALS - 1, 0..2] of single = (
{$I anorms.inc}
    );

var
  r_norefresh: cvar_t = (name: 'r_norefresh'; text: '0');
  r_fog: cvar_t = (name: 'r_fog'; text: '0');
  r_drawentities: cvar_t = (name: 'r_drawentities'; text: '1');
  r_drawviewmodel: cvar_t = (name: 'r_drawviewmodel'; text: '1');
  r_speeds: cvar_t = (name: 'r_speeds'; text: '0');
  r_lightmap: cvar_t = (name: 'r_lightmap'; text: '0');
  r_shadows: cvar_t = (name: 'r_shadows'; text: '1');
  r_mirroralpha: cvar_t = (name: 'r_mirroralpha'; text: '1');
  r_wateralpha: cvar_t = (name: 'r_wateralpha'; text: '0.5');
  r_dynamic: cvar_t = (name: 'r_dynamic'; text: '1');
  r_novis: cvar_t = (name: 'r_novis'; text: '0');
  r_fullbright: cvar_t = (name: 'r_fullbright'; text: '0');

  gl_finish: cvar_t = (name: 'gl_finish'; text: '0');
  gl_clear: cvar_t = (name: 'gl_clear'; text: '0');
  gl_cull: cvar_t = (name: 'gl_cull'; text: '1');
  gl_smoothmodels: cvar_t = (name: 'gl_smoothmodels'; text: '1');
  gl_affinemodels: cvar_t = (name: 'gl_affinemodels'; text: '0');
  gl_polyblend: cvar_t = (name: 'gl_polyblend'; text: '1');
  gl_flashblend: cvar_t = (name: 'gl_flashblend'; text: '1');
  gl_playermip: cvar_t = (name: 'gl_playermip'; text: '0');
  gl_nocolors: cvar_t = (name: 'gl_nocolors'; text: '0');
  gl_keeptjunctions: cvar_t = (name: 'gl_keeptjunctions'; text: '0');
  gl_reporttjunctions: cvar_t = (name: 'gl_reporttjunctions'; text: '0');
  gl_doubleeyes: cvar_t = (name: 'gl_doubleeys'; text: '1');
  gl_texsort: cvar_t = (name: 'gl_texsort'; text: '1');
  gl_interpolatemodels: cvar_t = (name: 'gl_interpolatemodels'; text: '1');

var
  c_brush_polys: integer;
  c_alias_polys: integer;

var
  mirror: qboolean;
  mirrortexturenum: integer; // quake texturenum, not gltexturenum
  mirror_plane: Pmplane_t;

var
  r_world_matrix: array[0..15] of single;
  r_base_world_matrix: array[0..15] of single;

//
// screen size info
//
  r_refdef: refdef_t;

var
  modelorg: TVector3f;
  r_entorigin: TVector3f;

var
  r_viewleaf, r_oldviewleaf: Pmleaf_t;

var
  r_cache_thrash: qboolean; // compatability
  cnttextures: array[0..1] of integer = (-1, -1); // cached
  envmap: qboolean; // true during envmap command capture
  playertextures: integer; // up to 16 color translated skins

var
  r_worldentity: entity_t;


implementation

uses
  quakedef,
  OpenGL12,
  bspconst,
  mathlib,
  console,
  spritegn,
  cl_main_h,
  gl_rsurf,
  gl_rmain_h,
  gl_texture,
  gl_sky,
  modelgen,
  gl_rlight,
  client,
  gl_model,
  gl_vidnt,
  chase,
  view,
  vid_h,
  gl_screen,
  snd_dma,
  gl_part,
  sys_win;

var
  frustum: array[0..3] of mplane_t;

(*
=================
R_CullBox

Returns true if the box is completely outside the frustom
=================
*)

function R_CullBox(mins: PVector3f; maxs: PVector3f): qboolean;
var
  i: integer;
  p: Pmplane_t;
begin
  p := @frustum[0];
  for i := 0 to 3 do
  begin
    if BoxOnPlaneSide(mins, maxs, p) = 2 then
    begin
      result := true;
      exit;
    end;
    inc(p);
  end;

  result := false;
end;


procedure R_RotateForEntity(e: Pentity_t);
begin
  glTranslatef(e.origin[0], e.origin[1], e.origin[2]);

  glRotatef(e.angles[1], 0, 0, 1);
  glRotatef(-e.angles[0], 0, 1, 0);
  glRotatef(e.angles[2], 1, 0, 0);
end;

(*
=============================================================

  SPRITE MODELS

=============================================================
*)

(*
================
R_GetSpriteFrame
================
*)

function R_GetSpriteFrame(currententity: Pentity_t): Pmspriteframe_t;
var
  psprite: Pmsprite_t;
  pspritegroup: Pmspritegroup_t;
  pspriteframe: Pmspriteframe_t;
  i, numframes, frame: integer;
  pintervals: PFloatArray;
  fullinterval, targettime, time: single;
begin
  psprite := currententity.model.cache.data;
  frame := currententity.frame;

  if (frame >= psprite.numframes) or (frame < 0) then
  begin
    Con_Printf('R_DrawSprite: no such frame %d'#10, [frame]);
    frame := 0;
  end;

  if psprite.frames[frame]._type = SPR_SINGLE then
    pspriteframe := psprite.frames[frame].frameptr
  else
  begin
    pspritegroup := Pmspritegroup_t(psprite.frames[frame].frameptr);
    pintervals := PFloatArray(pspritegroup.intervals);
    numframes := pspritegroup.numframes;
    fullinterval := pintervals[numframes - 1];

    time := cl.time + currententity.syncbase;

  // when loading in Mod_LoadSpriteGroup, we guaranteed all interval values
  // are positive, so we don't have to worry about division by 0
    targettime := time - intval(time / fullinterval) * fullinterval;

    i := 0;
    while i < numframes - 1 do
    begin
      if pintervals[i] > targettime then
        break;
      inc(i);
    end;

    pspriteframe := pspritegroup.frames[i];
  end;

  result := pspriteframe;
end;


(*
=================
R_DrawSpriteModel

=================
*)

procedure R_DrawSpriteModel(e: Pentity_t);
var
  point: TVector3f;
  frame: Pmspriteframe_t;
  up, right: PVector3f;
  v_forward, v_right, v_up: TVector3f;
  psprite: Pmsprite_t;
begin
  // don't even bother culling, because it's just a single
  // polygon without a surface cache
  frame := R_GetSpriteFrame(e);
  psprite := currententity.model.cache.data;

  if psprite._type = SPR_ORIENTED then
  begin // bullet marks on walls
    AngleVectors(@currententity.angles, @v_forward, @v_right, @v_up);
    up := @v_up[0];
    right := @v_right[0];
  end
  else
  begin // normal sprite
    up := @vup[0];
    right := @vright[0];
  end;

  glColor3f(1, 1, 1);

  GL_DisableMultitexture;

  GL_Bind(frame.gl_texturenum);

  glEnable(GL_ALPHA_TEST);
  glBegin(GL_QUADS);

  glTexCoord2f(0, 1);
  VectorMA(@e.origin, frame.down, up, @point);
  VectorMA(@point, frame.left, right, @point);
  glVertex3fv(@point);

  glTexCoord2f(0, 0);
  VectorMA(@e.origin, frame.up, up, @point);
  VectorMA(@point, frame.left, right, @point);
  glVertex3fv(@point);

  glTexCoord2f(1, 0);
  VectorMA(@e.origin, frame.up, up, @point);
  VectorMA(@point, frame.right, right, @point);
  glVertex3fv(@point);

  glTexCoord2f(1, 1);
  VectorMA(@e.origin, frame.down, up, @point);
  VectorMA(@point, frame.right, right, @point);
  glVertex3fv(@point);

  glEnd;

  glDisable(GL_ALPHA_TEST);
end;

(*
=============================================================

  ALIAS MODELS

=============================================================
*)


var
  shadevector: TVector3f;
  shadelight, ambientlight: single;

const
// precalculated dot products for quantized angles
  SHADEDOT_QUANT = 16;

  r_avertexnormal_dots: array[0..SHADEDOT_QUANT - 1, 0..255] of single =
{$I anorm_dots.inc}

var
  shadedots: PfloatArray = @r_avertexnormal_dots[0];

  lastposenum: integer;

(*
=============
GL_DrawAliasFrame
=============
*)

procedure GL_DrawAliasFrame(paliashdr: Paliashdr_t; posenum: integer);
var
  l: single;
  verts: Ptrivertx_t;
  order: Pinteger;
  count: integer;
begin
  lastposenum := posenum;

  verts := Ptrivertx_t(integer(paliashdr) + paliashdr.posedata);
//  verts := verts += posenum * paliashdr->poseverts;
  inc(verts, posenum * paliashdr.poseverts); // JVAL SOS
  order := PInteger(integer(paliashdr) + paliashdr.commands);

  while true do
  begin
    // get the vertex count and primitive type
    count := order^;
    inc(order);
    if count = 0 then
      break; // done
    if count < 0 then
    begin
      count := -count;
      glBegin(GL_TRIANGLE_FAN);
    end
    else
      glBegin(GL_TRIANGLE_STRIP);

    repeat
      // texture coordinates come from the draw list
      glTexCoord2f(PfloatArray(order)[0], PfloatArray(order)[1]);
      inc(order, 2);

      // normals and vertexes come from the frame list
      l := shadedots[verts.lightnormalindex] * shadelight;
      glColor3f(l, l, l);
      glVertex3f(verts.v[0], verts.v[1], verts.v[2]);
      inc(verts);
      dec(count);
    until count = 0;

    glEnd;
  end;
end;


(*
=============
GL_DrawAliasFrameEx
=============
*)

procedure GL_DrawAliasFrameEx(paliashdr: Paliashdr_t; posenum1, posenum2: integer; w: single);
var
  l: single;
  verts1: Ptrivertx_t;
  verts2: Ptrivertx_t;
  order: Pinteger;
  count: integer;
  w2: single;
  x, y, z: single;
begin
  lastposenum := posenum1;

  verts1 := Ptrivertx_t(integer(paliashdr) + paliashdr.posedata);
  inc(verts1, posenum1 * paliashdr.poseverts);
  verts2 := Ptrivertx_t(integer(paliashdr) + paliashdr.posedata);
  inc(verts2, posenum2 * paliashdr.poseverts);
  order := PInteger(integer(paliashdr) + paliashdr.commands);

  w2 := 1.0 - w;

  while true do
  begin
    // get the vertex count and primitive type
    count := order^;
    inc(order);
    if count = 0 then
      break; // done
    if count < 0 then
    begin
      count := -count;
      glBegin(GL_TRIANGLE_FAN);
    end
    else
      glBegin(GL_TRIANGLE_STRIP);

    repeat
      // texture coordinates come from the draw list
      glTexCoord2f(PfloatArray(order)[0], PfloatArray(order)[1]);
      inc(order, 2);

      // normals and vertexes come from the frame list
      l := (shadedots[verts1.lightnormalindex] * w2 + shadedots[verts2.lightnormalindex] * w) * shadelight;
      glColor3f(l, l, l);

      x := verts1.v[0] * w2 + verts2.v[0] * w;
      y := verts1.v[1] * w2 + verts2.v[1] * w;
      z := verts1.v[2] * w2 + verts2.v[2] * w;

      glVertex3f(x, y, z);
      inc(verts1);
      inc(verts2);
      dec(count);
    until count = 0;

    glEnd;
  end;
end;


(*
=============
GL_DrawAliasShadow
=============
*)

procedure GL_DrawAliasShadow(paliashdr: Paliashdr_t; posenum: integer);
var
  verts: Ptrivertx_t;
  order: Pinteger;
  point: TVector3f;
  height, lheight: single;
  count: integer;
begin
  lheight := currententity.origin[2] - lightspot[2];

  verts := Ptrivertx_t(integer(paliashdr) + paliashdr.posedata);
  inc(verts, posenum * paliashdr.poseverts); // JVAL SOS
  order := Pinteger(integer(paliashdr) + paliashdr.commands);

  height := -lheight + 1.0;

  while true do
  begin
    // get the vertex count and primitive type
    count := order^;
    inc(order);
    if count = 0 then
      break; // done
    if count < 0 then
    begin
      count := -count;
      glBegin(GL_TRIANGLE_FAN);
    end
    else
      glBegin(GL_TRIANGLE_STRIP);

    repeat
      // texture coordinates come from the draw list
      // (skipped for shadows) glTexCoord2fv ((float *)order);
      inc(order, 2);

      // normals and vertexes come from the frame list
      point[0] := verts.v[0] * paliashdr.scale[0] + paliashdr.scale_origin[0];
      point[1] := verts.v[1] * paliashdr.scale[1] + paliashdr.scale_origin[1];
      point[2] := verts.v[2] * paliashdr.scale[2] + paliashdr.scale_origin[2];

      point[0] := point[0] - shadevector[0] * (point[2] + lheight);
      point[1] := point[1] - shadevector[1] * (point[2] + lheight);
      point[2] := height;
//      height -= 0.001;
      glVertex3fv(@point);

      inc(verts);
      dec(count);
    until count = 0;

    glEnd;
  end;
end;



(*
=================
R_SetupAliasFrame

=================
*)

procedure R_SetupAliasFrame(frame: integer; paliashdr: Paliashdr_t);
var
  pose, pose2, numposes: integer;
  interval: single;
  w: single;
  iofs: integer;
  fofs: float;
begin
  if (frame >= paliashdr.numframes) or (frame < 0) then
  begin
    Con_DPrintf('R_AliasSetupFrame: no such frame %d'#10, [frame]);
    frame := 0;
  end;

  pose := paliashdr.frames[frame].firstpose;
  numposes := paliashdr.frames[frame].numposes;

  if numposes <= 1 then
  begin
    GL_DrawAliasFrame(paliashdr, pose);
    exit;
  end;

  interval := paliashdr.frames[frame].interval;
  iofs := intval(cl.time / interval) mod numposes;
  pose := pose + iofs;
  //Con_Printf('%f'#10, [(round(100 * cl.time / interval) mod (100 * numposes)) / 100]);
//  if gl_interpolatemodels.value = 0 then
  begin
    GL_DrawAliasFrame(paliashdr, pose);
    exit;
  end;

  fofs := (round(1000 * cl.time / interval) mod (1000 * numposes)) / 1000;

  w := fofs - iofs;

  pose2 := (pose + 1) mod numposes;

  GL_DrawAliasFrameEx(paliashdr, pose, pose2, w);


end;



(*
=================
R_DrawAliasModel

=================
*)

procedure R_DrawAliasModel(e: Pentity_t);
var
  i: integer;
  lnum: integer;
  dist: TVector3f;
  add: single;
  clmodel: PBSPModelFile;
  mins, maxs: TVector3f;
  paliashdr: Paliashdr_t;
  an: single;
  anim: integer;
begin
  clmodel := currententity.model;

  VectorAdd(@currententity.origin, @clmodel.mins, @mins);
  VectorAdd(@currententity.origin, @clmodel.maxs, @maxs);

  if R_CullBox(@mins, @maxs) then
    exit;

  VectorCopy(@currententity.origin, @r_entorigin);
  VectorSubtract(@r_origin, @r_entorigin, @modelorg);

  //
  // get lighting information
  //

  shadelight := R_LightPoint(@currententity.origin);
  ambientlight := shadelight;

  // allways give the gun some light
  if (e = @cl.viewent) and (ambientlight < 24) then
  begin
    shadelight := 24;
    ambientlight := 24;
  end;

  for lnum := 0 to MAX_DLIGHTS - 1 do
  begin
    if cl_dlights[lnum].die >= cl.time then
    begin
      VectorSubtract(@currententity.origin,
        @cl_dlights[lnum].origin,
        @dist);
      add := cl_dlights[lnum].radius - VectorLength(@dist);

      if add > 0 then
      begin
        ambientlight := ambientlight + add;
        //ZOID models should be affected by dlights as well
        shadelight := shadelight + add;
      end;
    end;
  end;

  // clamp lighting so it doesn't overbright as much
  if ambientlight > 128 then
    ambientlight := 128;
  if ambientlight + shadelight > 192 then
    shadelight := 192 - ambientlight;

  // ZOID: never allow players to go totally black
  i := (integer(currententity) - integer(@cl_entities)) div SizeOf(entity_t);
  if (i >= 1) and (i <= cl.maxclients) then // /* && !strcmp (currententity->model->name, "progs/player.mdl") */)
    if ambientlight < 8 then
    begin
      shadelight := 8;
      ambientlight := 8;
    end;

  // HACK HACK HACK -- no fullbright colors, so make torches full light
  if (strcmp(clmodel.name, 'progs/flame2.mdl') = 0) or
    (strcmp(clmodel.name, 'progs/flame.mdl') = 0) then
  begin
    shadelight := 256;
    ambientlight := 256;
  end;

//  shadedots := r_avertexnormal_dots[((int)(e->angles[1] * (SHADEDOT_QUANT / 360.0))) & (SHADEDOT_QUANT - 1)];
// JVAL SOS
  shadedots := @r_avertexnormal_dots[intval(e.angles[1] * (SHADEDOT_QUANT / 360.0)) and (SHADEDOT_QUANT - 1)];
  shadelight := shadelight / 200.0;

  an := e.angles[1] / 180 * M_PI;
  shadevector[0] := cos(-an);
  shadevector[1] := sin(-an);
  shadevector[2] := 1;
  VectorNormalize(@shadevector);

  //
  // locate the proper data
  //
  paliashdr := Paliashdr_t(Mod_Extradata(currententity.model));

  c_alias_polys := c_alias_polys + paliashdr.numtris;

  //
  // draw all the triangles
  //

  GL_DisableMultitexture;

  glPushMatrix;
  R_RotateForEntity(e);

  if (strcmp(clmodel.name, 'progs/eyes.mdl') = 0) and (gl_doubleeyes.value <> 0) then
  begin
    glTranslatef(paliashdr.scale_origin[0], paliashdr.scale_origin[1], paliashdr.scale_origin[2] - (22 + 8));
// double size of eyes, since they are really hard to see in gl
    glScalef(paliashdr.scale[0] * 2, paliashdr.scale[1] * 2, paliashdr.scale[2] * 2);
  end
  else
  begin
    glTranslatef(paliashdr.scale_origin[0], paliashdr.scale_origin[1], paliashdr.scale_origin[2]);
    glScalef(paliashdr.scale[0], paliashdr.scale[1], paliashdr.scale[2]);
  end;

  anim := intval(cl.time * 10) and 3;
  GL_Bind(paliashdr.gl_texturenum[currententity.skinnum][anim]);

  // we can't dynamically colormap textures, so they are cached
  // seperately for the players.  Heads are just uncolored.
  if (integer(currententity.colormap) <> integer(vid.colormap)) and (gl_nocolors.value = 0) then
  begin
    i := (integer(currententity) - integer(@cl_entities)) div SizeOf(entity_t);
    if (i >= 1) and (i <= cl.maxclients) then // /* && !strcmp (currententity->model->name, "progs/player.mdl") */)
      GL_Bind(playertextures - 1 + i);
  end;

  if gl_smoothmodels.value <> 0 then
    glShadeModel(GL_SMOOTH);

  glTexEnvf(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_MODULATE);

  if gl_affinemodels.value <> 0 then
    glHint(GL_PERSPECTIVE_CORRECTION_HINT, GL_FASTEST);

  R_SetupAliasFrame(currententity.frame, paliashdr);

  glTexEnvf(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_REPLACE);

  if gl_affinemodels.value <> 0 then
    glHint(GL_PERSPECTIVE_CORRECTION_HINT, GL_NICEST);

  glPopMatrix;

  if r_shadows.value <> 0 then
  begin
    glPushMatrix;
    R_RotateForEntity(e);
    glDisable(GL_TEXTURE_2D);
    glEnable(GL_BLEND);
    glColor4f(0, 0, 0, 0.5);
    GL_DrawAliasShadow(paliashdr, lastposenum);
    glEnable(GL_TEXTURE_2D);
    glDisable(GL_BLEND);
    glColor4f(1, 1, 1, 1);
    glPopMatrix;
  end;    

end;

//==================================================================================

(*
=============
R_DrawEntitiesOnList
=============
*)

procedure R_DrawEntitiesOnList;
var
  i: integer;
begin
  if r_drawentities.value = 0 then
    exit;

  // draw sprites seperately, because of alpha blending
  for i := 0 to cl_numvisedicts - 1 do
  begin
    currententity := cl_visedicts[i];

    case currententity.model._type of
      mod_alias:
        R_DrawAliasModel(currententity);

      mod_brush:
        R_DrawBrushModel(currententity);
    end;
  end;

  for i := 0 to cl_numvisedicts - 1 do
  begin
    currententity := cl_visedicts[i];

    if currententity.model._type = mod_sprite then
      R_DrawSpriteModel(currententity);
  end;
end;

(*
=============
R_DoDrawViewModel
=============
*)

procedure R_DoDrawViewModel;
var
  ambient, diffuse: array[0..3] of single;
  j: integer;
  lnum: integer;
  dist: TVector3f;
  add: single;
  dl: Pdlight_t;
  _ambientlight, _shadelight: integer;
begin
  if r_drawviewmodel.value = 0 then
    exit;

  if chase_active.value <> 0 then
    exit;

  if envmap then
    exit;

  if r_drawentities.value = 0 then
    exit;

  if cl.items and IT_INVISIBILITY <> 0 then
    exit;

  if cl.stats[STAT_HEALTH] <= 0 then
    exit;

  currententity := @cl.viewent;
  if currententity.model = nil then
    exit;

  j := R_LightPoint(@currententity.origin);

  if j < 24 then
    j := 24; // allways give some light on gun
  _ambientlight := j;
  _shadelight := j;

// add dynamic lights
  for lnum := 0 to MAX_DLIGHTS - 1 do // JVAL maybe pointer loop??
  begin
    dl := @cl_dlights[lnum];
    if dl.radius = 0 then
      continue;
    if dl.die < cl.time then
      continue;

    VectorSubtract(@currententity.origin, @dl.origin, @dist);
    add := dl.radius - VectorLength(@dist);
    if add > 0 then
      _ambientlight := _ambientlight + intval(add);
  end;

  ambient[0] := _ambientlight / 128;
  ambient[1] := ambient[0];
  ambient[2] := ambient[0];
  ambient[3] := ambient[0];
  diffuse[0] := _shadelight / 128;
  diffuse[1] := diffuse[0];
  diffuse[2] := diffuse[0];
  diffuse[3] := diffuse[0];

  // hack the depth range to prevent view model from poking into walls
  glDepthRange(gldepthmin, gldepthmin + 0.3 * (gldepthmax - gldepthmin));
  R_DrawAliasModel(currententity);
  glDepthRange(gldepthmin, gldepthmax);
end;


(*
============
R_PolyBlend
============
*)

procedure R_PolyBlend;
begin
  if gl_polyblend.value = 0 then
    exit;

  if v_blend[3] = 0 then
    exit;

  GL_DisableMultitexture;

  glDisable(GL_ALPHA_TEST);
  glEnable(GL_BLEND);
  glDisable(GL_DEPTH_TEST);
  glDisable(GL_TEXTURE_2D);

  glLoadIdentity;

  glRotatef(-90, 1, 0, 0); // put Z going up
  glRotatef(90, 0, 0, 1); // put Z going up

  glColor4fv(@v_blend);

  glBegin(GL_QUADS);

  glVertex3f(10, 100, 100);
  glVertex3f(10, -100, 100);
  glVertex3f(10, -100, -100);
  glVertex3f(10, 100, -100);
  glEnd;

  glDisable(GL_BLEND);
  glEnable(GL_TEXTURE_2D);
  glEnable(GL_ALPHA_TEST);
end;


function SignbitsForPlane(_out: Pmplane_t): integer;
var
  i: integer;
begin
  // for fast box on planeside test

  result := 0;
  for i := 0 to 2 do
    if _out.normal[i] < 0 then
      result := result or (1 shl i);
end;

procedure R_SetFrustum;
var
  i: integer;
begin
  if r_refdef.fov_x = 90 then
  begin
    // front side is visible

    VectorAdd(@vpn, @vright, @frustum[0].normal);
    VectorSubtract(@vpn, @vright, @frustum[1].normal);

    VectorAdd(@vpn, @vup, @frustum[2].normal);
    VectorSubtract(@vpn, @vup, @frustum[3].normal);
  end
  else
  begin
    // rotate VPN right by FOV_X/2 degrees
    RotatePointAroundVector(@frustum[0].normal, @vup, @vpn, -(90 - r_refdef.fov_x / 2));
    // rotate VPN left by FOV_X/2 degrees
    RotatePointAroundVector(@frustum[1].normal, @vup, @vpn, 90 - r_refdef.fov_x / 2);
    // rotate VPN up by FOV_X/2 degrees
    RotatePointAroundVector(@frustum[2].normal, @vright, @vpn, 90 - r_refdef.fov_y / 2);
    // rotate VPN down by FOV_X/2 degrees
    RotatePointAroundVector(@frustum[3].normal, @vright, @vpn, -(90 - r_refdef.fov_y / 2));
  end;

  for i := 0 to 3 do
  begin
    frustum[i].PlaneType := PLANE_ANYZ;
    frustum[i].dist := VectorDotProduct(@r_origin, @frustum[i].normal);
    frustum[i].signbits := SignbitsForPlane(@frustum[i]);
  end;
end;



(*
===============
R_SetupFrame
===============
*)

procedure R_SetupFrame;
begin
// don't allow cheats in multiplayer
  if cl.maxclients > 1 then
    Cvar_SetValue('r_fullbright', 0);

  R_AnimateLight;

  inc(r_framecount);

// build the transformation matrix for the given view angles
  VectorCopy(@r_refdef.vieworg, @r_origin);

  AngleVectors(@r_refdef.viewangles, @vpn, @vright, @vup);

// current viewleaf
  r_oldviewleaf := r_viewleaf;
  r_viewleaf := Mod_PointInLeaf(@r_origin, cl.worldmodel);

  V_SetContentsColor(r_viewleaf.contents);
  V_CalcBlend;

  r_cache_thrash := false;

  c_brush_polys := 0;
  c_alias_polys := 0;

end;


procedure MYgluPerspective(fovy: TGLdouble; aspect: TGLdouble;
  zNear: TGLdouble; zFar: TGLdouble);
var
  xmin, xmax, ymin, ymax: TGLdouble;
begin

  ymax := zNear * ftan(fovy * M_PI / 360.0);
  ymin := -ymax;

  xmin := ymin * aspect;
  xmax := ymax * aspect;

  glFrustum(xmin, xmax, ymin, ymax, zNear, zFar);
end;


(*
=============
R_SetupGL
=============
*)

procedure R_SetupGL;
var
  screenaspect: single;
  x, x2, y2, y, w, h: integer;
begin
  //
  // set up viewpoint
  //
  glMatrixMode(GL_PROJECTION);
  glLoadIdentity;
  x := r_refdef.vrect.x * glwidth div vid.width; // JVAL -> maybe trunc / intval() ??
  x2 := (r_refdef.vrect.x + r_refdef.vrect.width) * glwidth div vid.width; // JVAL same as above ??
  y := (vid.height - r_refdef.vrect.y) * glheight div vid.height;
  y2 := (vid.height - (r_refdef.vrect.y + r_refdef.vrect.height)) * glheight div vid.height;

  // fudge around because of frac screen scale
  if x > 0 then
    dec(x);
  if x2 < glwidth then
    inc(x2);
  if y2 < 0 then
    dec(y2);
  if y < glheight then
    inc(y);

  w := x2 - x;
  h := y - y2;

  if envmap then // JVAL -> avoid previous calculation of w, h ??
  begin
    x := 0;
    y2 := 0;
    w := 256;
    h := 256;
  end;

  glViewport(glx + x, gly + y2, w, h);
  screenaspect := r_refdef.vrect.width / r_refdef.vrect.height;
//  yfov = 2*atan((float)r_refdef.vrect.height/r_refdef.vrect.width)*180/M_PI;
  MYgluPerspective(r_refdef.fov_y, screenaspect, 4, 4096);

  if mirror then
  begin
    if mirror_plane.normal[2] <> 0 then
      glScalef(1, -1, 1)
    else
      glScalef(-1, 1, 1);
    glCullFace(GL_BACK);
  end
  else
    glCullFace(GL_FRONT);

  glMatrixMode(GL_MODELVIEW);
  glLoadIdentity;

  glRotatef(-90, 1, 0, 0); // put Z going up
  glRotatef(90, 0, 0, 1); // put Z going up
  glRotatef(-r_refdef.viewangles[2], 1, 0, 0);
  glRotatef(-r_refdef.viewangles[0], 0, 1, 0);
  glRotatef(-r_refdef.viewangles[1], 0, 0, 1);
  glTranslatef(-r_refdef.vieworg[0], -r_refdef.vieworg[1], -r_refdef.vieworg[2]);

  glGetFloatv(GL_MODELVIEW_MATRIX, @r_world_matrix);

  //
  // set drawing parms
  //
  if gl_cull.value <> 0 then
    glEnable(GL_CULL_FACE)
  else
    glDisable(GL_CULL_FACE);

  glDisable(GL_BLEND);
  glDisable(GL_ALPHA_TEST);
  glEnable(GL_DEPTH_TEST);
end;

(*
================
R_RenderScene

r_refdef must be set before the first call
================
*)

procedure R_RenderScene;
begin
  R_SetupFrame;

  R_SetFrustum;

  R_SetupGL;

  R_MarkLeaves; // done here so we know if we're in water

  R_DrawWorld; // adds static entities to the list

  S_ExtraUpdate; // don't let sound get messed up if going slow

  R_DrawEntitiesOnList;

  GL_DisableMultitexture;


  R_RenderDlights;

  R_DrawParticles;

end;


(*
=============
R_Clear
=============
*)
var
  trickframe: integer = 0;

procedure R_Clear;
begin
  if r_mirroralpha.value <> 1.0 then
  begin
    if gl_clear.value <> 0 then
      glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT)
    else
      glClear(GL_DEPTH_BUFFER_BIT);
    gldepthmin := 0;
    gldepthmax := 0.5;
    glDepthFunc(GL_LEQUAL);
  end
  else if gl_ztrick.value <> 0 then
  begin
    if gl_clear.value <> 0 then
      glClear(GL_COLOR_BUFFER_BIT);

    inc(trickframe);
    if trickframe and 1 <> 0 then
    begin
      gldepthmin := 0;
      gldepthmax := 0.49999;
      glDepthFunc(GL_LEQUAL);
    end
    else
    begin
      gldepthmin := 1;
      gldepthmax := 0.5;
      glDepthFunc(GL_GEQUAL);
    end
  end
  else
  begin
    if gl_clear.value <> 0 then
      glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT)
    else
      glClear(GL_DEPTH_BUFFER_BIT);
    gldepthmin := 0;
    gldepthmax := 1;
    glDepthFunc(GL_LEQUAL);
  end;

  glDepthRange(gldepthmin, gldepthmax);
end;

(*
=============
R_Mirror
=============
*)

procedure R_Mirror;
var
  d: single;
  s: Pmsurface_t;
  ent: Pentity_t;
begin
  if not mirror then
    exit;

  memcpy(@r_base_world_matrix, @r_world_matrix, SizeOf(r_base_world_matrix));

  d := VectorDotProduct(@r_refdef.vieworg, @mirror_plane.normal) - mirror_plane.dist;
  VectorMA(@r_refdef.vieworg, -2 * d, @mirror_plane.normal, @r_refdef.vieworg);

  d := VectorDotProduct(@vpn, @mirror_plane.normal);
  VectorMA(@vpn, -2 * d, @mirror_plane.normal, @vpn);

  r_refdef.viewangles[0] := -fasin(vpn[2]) / M_PI * 180;
  r_refdef.viewangles[1] := fatan2(vpn[1], vpn[0]) / M_PI * 180;
  r_refdef.viewangles[2] := -r_refdef.viewangles[2];

  ent := @cl_entities[cl.viewentity];
  if cl_numvisedicts < MAX_VISEDICTS then
  begin
    cl_visedicts[cl_numvisedicts] := ent;
    inc(cl_numvisedicts);
  end;

  gldepthmin := 0.5;
  gldepthmax := 1;
  glDepthRange(gldepthmin, gldepthmax);
  glDepthFunc(GL_LEQUAL);

  R_RenderScene;
  R_DrawWaterSurfaces;

  gldepthmin := 0;
  gldepthmax := 0.5;
  glDepthRange(gldepthmin, gldepthmax);
  glDepthFunc(GL_LEQUAL);

  // blend on top
  glEnable(GL_BLEND);
  glMatrixMode(GL_PROJECTION);
  if mirror_plane.normal[2] <> 0 then
    glScalef(1, -1, 1)
  else
    glScalef(-1, 1, 1);
  glCullFace(GL_FRONT);
  glMatrixMode(GL_MODELVIEW);

  glLoadMatrixf(@r_base_world_matrix);

  glColor4f(1, 1, 1, r_mirroralpha.value);
  s := cl.worldmodel.textures[mirrortexturenum].texturechain;
  while s <> nil do
  begin
    R_RenderBrushPoly(s);
    s := s.texturechain;
  end;

  cl.worldmodel.textures[mirrortexturenum].texturechain := nil;
  glDisable(GL_BLEND);
  glColor4f(1, 1, 1, 1);
end;

(*
================
R_RenderView

r_refdef must be set before the first call
================
*)

procedure R_RenderView;
var
  time1, time2: double;
  colors: array[0..3] of single;
begin

  if r_norefresh.value <> 0 then
    exit;

  if (r_worldentity.model = nil) or (cl.worldmodel = nil) then
    Sys_Error('R_RenderView: NULL worldmodel');

  if r_speeds.value <> 0 then
  begin
    glFinish;
    time1 := Sys_FloatTime;
    c_brush_polys := 0;
    c_alias_polys := 0;
  end
  else
    time1 := 0.0; // JVAL avoid compiler warning

  mirror := false;

  if gl_finish.value <> 0 then
    glFinish;

  R_Clear;

  // render normal view

//(***** Experimental silly looking fog ******
//*/***** Use r_fullbright if you enable ******

  if r_fog.value <> 0 then
  begin
    colors[0] := 0.0;
    colors[1] := 0.0;
    colors[2] := 0.0;
    colors[3] := 0.0;

    glFogi(GL_FOG_MODE, GL_LINEAR);
    glFogfv(GL_FOG_COLOR, @colors);
    glFogf(GL_FOG_END, 512.0);
    glEnable(GL_FOG);
  end;
//********************************************)

  R_RenderScene;
  R_DoDrawViewModel;
  R_DrawWaterSurfaces;

//  More fog right here :)
  if r_fog.value <> 0 then
    glDisable(GL_FOG);

//  End of all fog code...

  // render mirror view
  R_Mirror;

  R_PolyBlend;

  if r_speeds.value <> 0 then
  begin
//    glFinish ();
    time2 := Sys_FloatTime;
    Con_Printf('%3d ms  %4d wpoly %4d epoly'#10,
      [int((time2 - time1) * 1000), c_brush_polys, c_alias_polys]);
  end;


end;

end.

