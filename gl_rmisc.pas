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

unit gl_rmisc;

// r_misc.c

interface

procedure R_InitTextures;
procedure R_InitParticleTexture;
procedure R_Envmap_f;
procedure R_Init;
procedure R_TranslatePlayerSkin(playernum: integer);
procedure R_NewMap;
procedure R_TimeRefresh_f;
procedure D_FlushCaches;

implementation

uses
  q_delphi,
  OpenGL12,
  gl_rmain_h,
  zone,
  gl_planes,
  gl_defs,
  gl_vidnt,
  gl_texture,
  gl_rmain,
  gl_screen,
  common,
  cmd,
  gl_part,
  cvar,
  gl_model_h,
  gl_model,
  gl_rsurf,
  cl_main_h,
  render_h,
  console,
  sys_win,
  vid_h;

(*
==================
R_InitTextures
==================
*)

procedure R_InitTextures;
var
  x, y, m: integer;
  dest: PByte;
begin
// create a simple checkerboard texture for the default
  r_notexture_mip := Hunk_AllocName(SizeOf(texture_t) + 16 * 16 + 8 * 8 + 4 * 4 + 2 * 2, 'notexture');

  r_notexture_mip.height := 16;
  r_notexture_mip.width := 16;
  r_notexture_mip.offsets[0] := SizeOf(texture_t);
  r_notexture_mip.offsets[1] := r_notexture_mip.offsets[0] + 16 * 16;
  r_notexture_mip.offsets[2] := r_notexture_mip.offsets[1] + 8 * 8;
  r_notexture_mip.offsets[3] := r_notexture_mip.offsets[2] + 4 * 4;

  for m := 0 to 3 do
  begin
    dest := PByte(unsigned(r_notexture_mip) + r_notexture_mip.offsets[m]);
    for y := 0 to (16 shr m) - 1 do
      for x := 0 to (16 shr m) - 1 do
      begin
        if (y < (8 shr m)) xor (x < (8 shr m)) then
          dest^ := 0
        else
          dest^ := $FF;
        inc(dest);
      end;
  end;
end;

const
  dottexture: array[0..7, 0..7] of byte = (
    (0, 1, 1, 0, 0, 0, 0, 0),
    (1, 1, 1, 1, 0, 0, 0, 0),
    (1, 1, 1, 1, 0, 0, 0, 0),
    (0, 1, 1, 0, 0, 0, 0, 0),
    (0, 0, 0, 0, 0, 0, 0, 0),
    (0, 0, 0, 0, 0, 0, 0, 0),
    (0, 0, 0, 0, 0, 0, 0, 0),
    (0, 0, 0, 0, 0, 0, 0, 0)
    );

procedure R_InitParticleTexture;
var
  x, y: integer;
  data: array[0..7, 0..7, 0..3] of byte;
begin
  //
  // particle texture
  //
  particletexture := texture_extension_number;
  inc(texture_extension_number);
  GL_Bind(particletexture);

  for x := 0 to 7 do
    for y := 0 to 7 do
    begin
      data[y][x][0] := 255;
      data[y][x][1] := 255;
      data[y][x][2] := 255;
      data[y][x][3] := dottexture[x][y] * 255; // JVAL check (??? mayby * 256 ????)
    end;

  glTexImage2D(GL_TEXTURE_2D, 0, gl_alpha_format, 8, 8, 0, GL_RGBA, GL_UNSIGNED_BYTE, @data);

  glTexEnvf(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_MODULATE);

  glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
  glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
end;

(*
===============
R_Envmap_f

Grab six views for environment mapping tests
===============
*)

procedure R_Envmap_f;
var
  buffer: array[0..256 * 256 * 4 - 1] of byte;
begin
  glDrawBuffer(GL_FRONT);
  glReadBuffer(GL_FRONT);
  envmap := true;

  r_refdef.vrect.x := 0;
  r_refdef.vrect.y := 0;
  r_refdef.vrect.width := 256;
  r_refdef.vrect.height := 256;

  r_refdef.viewangles[0] := 0;
  r_refdef.viewangles[1] := 0;
  r_refdef.viewangles[2] := 0;
  GL_BeginRendering(@glx, @gly, @glwidth, @glheight);
  R_RenderView;
  glReadPixels(0, 0, 256, 256, GL_RGBA, GL_UNSIGNED_BYTE, @buffer);
  COM_WriteFile('env0.rgb', @buffer, SizeOf(buffer));

  r_refdef.viewangles[1] := 90;
  GL_BeginRendering(@glx, @gly, @glwidth, @glheight);
  R_RenderView;
  glReadPixels(0, 0, 256, 256, GL_RGBA, GL_UNSIGNED_BYTE, @buffer);
  COM_WriteFile('env1.rgb', @buffer, SizeOf(buffer));

  r_refdef.viewangles[1] := 180;
  GL_BeginRendering(@glx, @gly, @glwidth, @glheight);
  R_RenderView;
  glReadPixels(0, 0, 256, 256, GL_RGBA, GL_UNSIGNED_BYTE, @buffer);
  COM_WriteFile('env2.rgb', @buffer, SizeOf(buffer));

  r_refdef.viewangles[1] := 270;
  GL_BeginRendering(@glx, @gly, @glwidth, @glheight);
  R_RenderView;
  glReadPixels(0, 0, 256, 256, GL_RGBA, GL_UNSIGNED_BYTE, @buffer);
  COM_WriteFile('env3.rgb', @buffer, SizeOf(buffer));

  r_refdef.viewangles[0] := -90;
  r_refdef.viewangles[1] := 0;
  GL_BeginRendering(@glx, @gly, @glwidth, @glheight);
  R_RenderView;
  glReadPixels(0, 0, 256, 256, GL_RGBA, GL_UNSIGNED_BYTE, @buffer);
  COM_WriteFile('env4.rgb', @buffer, SizeOf(buffer));

  r_refdef.viewangles[0] := 90;
  r_refdef.viewangles[1] := 0;
  GL_BeginRendering(@glx, @gly, @glwidth, @glheight);
  R_RenderView;
  glReadPixels(0, 0, 256, 256, GL_RGBA, GL_UNSIGNED_BYTE, @buffer);
  COM_WriteFile('env5.rgb', @buffer, SizeOf(buffer));

  envmap := false;
  glDrawBuffer(GL_BACK);
  glReadBuffer(GL_BACK);
  GL_EndRendering;
end;

(*
===============
R_Init
===============
*)

procedure R_Init;
begin
  Cmd_AddCommand('timerefresh', R_TimeRefresh_f);
  Cmd_AddCommand('envmap', R_Envmap_f);
  Cmd_AddCommand('pointfile', R_ReadPointFile_f);

  Cvar_RegisterVariable(@r_norefresh);
  Cvar_RegisterVariable(@r_fog);
  Cvar_RegisterVariable(@r_lightmap);
  Cvar_RegisterVariable(@r_fullbright);
  Cvar_RegisterVariable(@r_drawentities);
  Cvar_RegisterVariable(@r_drawviewmodel);
  Cvar_RegisterVariable(@r_shadows);
  Cvar_RegisterVariable(@r_mirroralpha);
  Cvar_RegisterVariable(@r_wateralpha);
  Cvar_RegisterVariable(@r_dynamic);
  Cvar_RegisterVariable(@r_novis);
  Cvar_RegisterVariable(@r_speeds);

  Cvar_RegisterVariable(@gl_finish);
  Cvar_RegisterVariable(@gl_clear);
  Cvar_RegisterVariable(@gl_texsort);
  Cvar_RegisterVariable(@gl_interpolatemodels);
  
  if gl_mtexable then
    Cvar_SetValue('gl_texsort', 0.0);

  Cvar_RegisterVariable(@gl_cull);
  Cvar_RegisterVariable(@gl_smoothmodels);
  Cvar_RegisterVariable(@gl_affinemodels);
  Cvar_RegisterVariable(@gl_polyblend);
  Cvar_RegisterVariable(@gl_flashblend);
  Cvar_RegisterVariable(@gl_playermip);
  Cvar_RegisterVariable(@gl_nocolors);

  Cvar_RegisterVariable(@gl_keeptjunctions);
  Cvar_RegisterVariable(@gl_reporttjunctions);

  Cvar_RegisterVariable(@gl_doubleeyes);

  R_InitParticles;
  R_InitParticleTexture;

  playertextures := texture_extension_number;
  inc(texture_extension_number, 16);
end;

(*
===============
R_TranslatePlayerSkin

Translates a skin texture by the per-player color lookup
===============
*)

procedure R_TranslatePlayerSkin(playernum: integer);
var
  top, bottom: integer;
  translate: array[0..255] of byte;
  translate32: array[0..255] of unsigned;
  i, j, s: integer;
  model: PBSPModelFile;
  paliashdr: Paliashdr_t;
  original: PByte;
  _out: Punsigned;
  out2: PByte;
  pixels: array[0..512 * 256 - 1] of unsigned;
  scaled_width, scaled_height: integer; // JVAL was unsigned;
  inwidth, inheight: integer;
  inrow: PByteArray;
  frac, fracstep: unsigned;
//  extern  byte    **player_8bit_texels_tbl;
begin
  GL_DisableMultitexture;

  top := cl.scores[playernum].colors and $F0;
  bottom := ((cl.scores[playernum].colors and 15) shl 4);

  for i := 0 to 255 do
    translate[i] := i;

  for i := 0 to 15 do
  begin
    if top < 128 then // the artists made some backwards ranges.  sigh.
      translate[TOP_RANGE + i] := top + i
    else
      translate[TOP_RANGE + i] := top + 15 - i;

    if bottom < 128 then
      translate[BOTTOM_RANGE + i] := bottom + i
    else
      translate[BOTTOM_RANGE + i] := bottom + 15 - i;
  end;

  //
  // locate the original skin pixels
  //
  currententity := @cl_entities[1 + playernum];
  model := currententity.model;
  if model = nil then
    exit; // player doesn't have a model yet
  if model._type <> mod_alias then
    exit; // only translate skins on alias models

  paliashdr := Paliashdr_t(Mod_Extradata(model));
  s := paliashdr.skinwidth * paliashdr.skinheight;
  if (currententity.skinnum < 0) or (currententity.skinnum >= paliashdr.numskins) then
  begin
    Con_Printf('(%d): Invalid player skin #%d'#10, [playernum, currententity.skinnum]);
    original := PByte(integer(paliashdr) + paliashdr.texels[0])
  end
  else
    original := PByte(integer(paliashdr) + paliashdr.texels[currententity.skinnum]);
  if s and 3 <> 0 then
    Sys_Error('R_TranslateSkin: s&3');

  inwidth := paliashdr.skinwidth;
  inheight := paliashdr.skinheight;

  // because this happens during gameplay, do it fast
  // instead of sending it through gl_upload 8
  GL_Bind(playertextures + playernum);

  scaled_width := decide(gl_max_size.value < 512, intval(gl_max_size.value), 512);
  scaled_height := decide(gl_max_size.value < 256, intval(gl_max_size.value), 256);

  // allow users to crunch sizes down even more if they want
  scaled_width := (scaled_width shr intval(gl_playermip.value));
  scaled_height := (scaled_height shr intval(gl_playermip.value));

  if VID_Is8bit then // 8bit texture upload
  begin
    out2 := PByte(@pixels);
    ZeroMemory(@pixels, SizeOf(pixels));
    fracstep := inwidth * $10000 div scaled_width;
    for i := 0 to scaled_height - 1 do // JVAL mayby change this loop ??
    begin
      inrow := PByteArray(integer(original) + inwidth * (i * inheight div scaled_height));
      frac := fracstep div 2;
      for j := 0 to scaled_width - 1 do
      begin
        out2^ := translate[inrow[(frac shr 16)]];
        inc(out2);
        inc(frac, fracstep);
      end;
    end;

    GL_Upload8_EXT(PByteArray(@pixels), scaled_width, scaled_height, false, false);
    exit;
  end;

  for i := 0 to 255 do
    translate32[i] := d_8to24table[translate[i]];

  _out := @pixels[0];
  fracstep := inwidth * $10000 div scaled_width;
  for i := 0 to scaled_height - 1 do
  begin
    inrow := PByteArray(integer(original) + inwidth * (i * inheight div scaled_height));
    frac := fracstep div 2;
    for j := 0 to scaled_width - 1 do
    begin
      _out^ := translate32[inrow[(frac shr 16)]];
      inc(_out);
      inc(frac, fracstep);
    end;
  end;
  glTexImage2D(GL_TEXTURE_2D, 0, gl_solid_format, scaled_width, scaled_height, 0, GL_RGBA, GL_UNSIGNED_BYTE, @pixels);

  glTexEnvf(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_MODULATE);
  glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
  glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);

end;


(*
===============
R_NewMap
===============
*)

procedure R_NewMap;
var
  i: integer;
begin
  for i := 0 to 255 do
    d_lightstylevalue[i] := 264; // normal light value

  ZeroMemory(@r_worldentity, SizeOf(r_worldentity));
  r_worldentity.model := cl.worldmodel;

// clear out efrags in case the level hasn't been reloaded
// FIXME: is this one short?
  for i := 0 to cl.worldmodel.numleafs - 1 do
    cl.worldmodel.leafs[i].efrags := nil;

  r_viewleaf := nil;
  R_ClearParticles;

  GL_BuildLightmaps;

  // identify sky texture
  skytexturenum := -1;
  mirrortexturenum := -1;
  for i := 0 to cl.worldmodel.numtextures - 1 do
  begin
    if cl.worldmodel.textures[i] = nil then
      continue; // JVAL : maybe dont call q_strncmp after skytexturenum is set
    if Q_strncmp(cl.worldmodel.textures[i].name, 'sky', 3) = 0 then
      skytexturenum := i; // JVAL same as above to mirrortexnum
    if Q_strncmp(cl.worldmodel.textures[i].name, 'window02_1', 10) = 0 then
      mirrortexturenum := i;
    cl.worldmodel.textures[i].texturechain := nil;
  end;
end;


(*
====================
R_TimeRefresh_f

For program optimization
====================
*)

procedure R_TimeRefresh_f;
const
  NUMTESTFRAMES = 128;
var
  i: integer;
  start, stop, time: single;
begin
  glDrawBuffer(GL_FRONT);
  glFinish;

  start := Sys_FloatTime;
  for i := 0 to NUMTESTFRAMES - 1 do
  begin
    r_refdef.viewangles[1] := i / NUMTESTFRAMES * 360.0;
    R_RenderView;
  end;

  glFinish;
  stop := Sys_FloatTime;
  time := stop - start;
  Con_Printf('%d frames in %2.3f seconds (%2.3f fps)'#10, [NUMTESTFRAMES, time, NUMTESTFRAMES / time]);

  glDrawBuffer(GL_BACK);
  GL_EndRendering;
end;

procedure D_FlushCaches;
begin
// JVAL ???
end;


end.

 