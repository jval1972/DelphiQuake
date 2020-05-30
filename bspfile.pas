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

unit bspfile;

interface

uses
  q_delphi,
  SysUtils,
  OpenGL12,
  bspconst,
  gl_model,
  gl_model_h,
  gl_planes,
  gl_warp,
  gl_vidnt,
  gl_rmain_h,
  gl_texture,
  zone,
  sys_win,
  mathlib,
  common;

var
  loadmodel: PBSPModelFile;
  loadname: array[0..31] of char; // for hunk tags
  mod_novis: array[0..MAX_MAP_LEAFS div 8 - 1] of byte;

const
  MAX_MOD_KNOWN = 512;

var
  mod_known: array[0..MAX_MOD_KNOWN - 1] of TBSPModelFile;
  mod_numknown: integer;

procedure BSP_LoadMap_QuakeI(mdl: PBSPModelFile; buffer: pointer);

procedure BSP_LoadMap_HalfLife(mdl: PBSPModelFile; buffer: pointer);

implementation

uses
  bsptypes;

var
  mod_base: PByteArray;

procedure BSP_Funny_Lump_Size;
begin
  Sys_Error('MOD_LoadBmodel: funny lump size in %s', [loadmodel.name]);
end;

procedure BSP_LoadClipnodes(l: PBSPLump);
var
  _in, _out: PBSPClipNode;
  i, count: integer;
  hull: Phull_t;
begin
  _in := PBSPClipNode(@mod_base[l.Offset]);
  if l.Length mod SizeOf(TBSPClipNode) <> 0 then
    BSP_Funny_Lump_Size;
  count := l.Length div SizeOf(TBSPClipNode);
  _out := Hunk_AllocName(count * SizeOf(TBSPClipNode), loadname);

  loadmodel.clipnodes := _out;
  loadmodel.numclipnodes := count;

  hull := @loadmodel.hulls[1]; // JVAL mayby hulls[1] & hulls[2] in one function?
  hull.clipnodes := _out;
  hull.firstclipnode := 0;
  hull.lastclipnode := count - 1;
  hull.planes := @loadmodel.planes[0];
  hull.clip_mins[0] := -16;
  hull.clip_mins[1] := -16;
  hull.clip_mins[2] := -24;
  hull.clip_maxs[0] := 16;
  hull.clip_maxs[1] := 16;
  hull.clip_maxs[2] := 32;

  hull := @loadmodel.hulls[2];
  hull.clipnodes := _out;
  hull.firstclipnode := 0;
  hull.lastclipnode := count - 1;
  hull.planes := @loadmodel.planes[0];
  hull.clip_mins[0] := -32;
  hull.clip_mins[1] := -32;
  hull.clip_mins[2] := -24;
  hull.clip_maxs[0] := 32;
  hull.clip_maxs[1] := 32;
  hull.clip_maxs[2] := 64;

  for i := 0 to count - 1 do
  begin
    _out.PlaneIndex := LittleLong(_in.PlaneIndex);
    _out.children[0] := LittleShort(_in.children[0]);
    _out.children[1] := LittleShort(_in.children[1]);
    inc(_in);
    inc(_out);
  end;
end;

procedure BSP_LoadEdges(l: PBSPLump);
var
  _in: PBSPEdge;
  _out: Pmedge_t;
  i, count: integer;
begin
  _in := PBSPEdge(@mod_base[l.Offset]);
  if l.Length mod SizeOf(TBSPEdge) <> 0 then
    BSP_Funny_Lump_Size;
  count := l.Length div SizeOf(TBSPEdge);
  _out := Hunk_AllocName((count + 1) * SizeOf(medge_t), loadname);

  loadmodel.edges := Pmedge_tArray(_out);
  loadmodel.numedges := count;

  for i := 0 to count - 1 do
  begin
    _out.v[0] := unsigned_short(LittleShort(_in.v[0]));
    _out.v[1] := unsigned_short(LittleShort(_in.v[1]));
    inc(_in);
    inc(_out);
  end;
end;

procedure BSP_LoadEntities(l: PBSPLump);
begin
  if l.Length = 0 then
  begin
    loadmodel.entities := nil;
    exit;
  end;
  loadmodel.entities := Hunk_AllocName(l.Length, loadname);
  memcpy(loadmodel.entities, @mod_base[l.Offset], l.Length);
end;

procedure BSP_LoadFaces(l: PBSPLump);
label
  continue1;
var
  _in: PBSPFace;
  _out: Pmsurface_t;
  i, count, surfnum: integer;
  planenum, side: integer;
begin
  _in := PBSPFace(@mod_base[l.Offset]);
  if l.Length mod SizeOf(TBSPFace) <> 0 then
    BSP_Funny_Lump_Size;
  count := l.Length div SizeOf(TBSPFace);
  _out := Hunk_AllocName(count * SizeOf(msurface_t), loadname);

  loadmodel.surfaces := Pmsurface_tArray(_out);
  loadmodel.numsurfaces := count;

  for surfnum := 0 to count - 1 do
  begin
    _out.firstedge := LittleLong(_in.firstedge);
    _out.numedges := LittleShort(_in.numedges);
    _out.flags := 0;

    planenum := LittleShort(_in.PlaneIndex);
    side := LittleShort(_in.side);
    if side <> 0 then
      _out.flags := _out.flags or SURF_PLANEBACK;

    _out.plane := @loadmodel.planes[planenum];

    _out.texinfo := @loadmodel.texinfo[LittleShort(_in.texinfo)]; // JVAL should check this

    CalcSurfaceExtents(_out);

  // lighting info

    for i := 0 to MAXLIGHTMAPS - 1 do
      _out.styles[i] := _in.styles[i];
    i := LittleLong(_in.light_offset);
    if i = -1 then
      _out.samples := nil
    else
      _out.samples := @loadmodel.lightdata[i]; // JVAL should check this

  // set the drawing flags flag

    if Q_strncmp(_out.texinfo.texture.name, 'sky', 3) = 0 then // sky
    begin
      _out.flags := _out.flags or (SURF_DRAWSKY or SURF_DRAWTILED);
      goto continue1;
    end;

    if Q_strncmp(_out.texinfo.texture.name, '*', 1) = 0 then // turbulent
    begin
      _out.flags := _out.flags or (SURF_DRAWTURB or SURF_DRAWTILED);
      for i := 0 to 1 do
      begin
        _out.extents[i] := 16384;
        _out.texturemins[i] := -8192;
      end;
      GL_SubdivideSurface(_out); // cut up polygon for warps
      goto continue1;
    end;
    continue1:
    inc(_in);
    inc(_out);
  end;
end;

procedure BSP_LoadLeafs(l: PBSPLump);
var
  _in: PBSPLeaf;
  _out: Pmleaf_t;
  i, j, count, p: integer;
begin
  _in := PBSPLeaf(@mod_base[l.Offset]);
  if l.Length mod SizeOf(TBSPLeaf) <> 0 then
    BSP_Funny_Lump_Size;
  count := l.Length div SizeOf(TBSPLeaf);
  _out := Hunk_AllocName(count * SizeOf(mleaf_t), loadname);

  loadmodel.leafs := Pmleaf_tArray(_out);
  loadmodel.numleafs := count;

  for i := 0 to count - 1 do
  begin
    for j := 0 to 2 do
    begin
      _out.minmaxs[j] := LittleShort(_in.mins[j]);
      _out.minmaxs[3 + j] := LittleShort(_in.maxs[j]);
    end;

    p := LittleLong(_in.contents);
    _out.contents := p;

    _out.firstmarksurface := @loadmodel.marksurfaces[LittleShort(_in.firstmarksurface)]; // JVAL SOS SOS SOS

    _out.nummarksurfaces := LittleShort(_in.nummarksurfaces);

    p := LittleLong(_in.visofs);
    if p = -1 then
      _out.compressed_vis := nil
    else
      _out.compressed_vis := @loadmodel.visdata[p]; // JVAL Should check this
    _out.efrags := nil;

    for j := 0 to 3 do
      _out.ambient_sound_level[j] := _in.ambient_level[j];

    // gl underwater warp
    if _out.contents <> CONTENTS_EMPTY then
    begin
      for j := 0 to _out.nummarksurfaces - 1 do
        _out.firstmarksurface[j].flags := _out.firstmarksurface[j].flags or SURF_UNDERWATER;
    end;
    inc(_in);
    inc(_out);
  end;
end;

procedure BSP_LoadLighting(l: PBSPLump);
begin
  if l.Length = 0 then
  begin
    loadmodel.lightdata := nil;
    exit;
  end;

  loadmodel.lightdata := Hunk_AllocName(l.Length, loadname);
  memcpy(loadmodel.lightdata, @mod_base[l.Offset], l.Length);
end;

procedure BSP_LoadMarksurfaces(l: PBSPLump);
var
  i, j, count: integer;
  _in: PShortArray;
  _out: Pmsurface_tPArray;
begin
  _in := PShortArray(@mod_base[l.Offset]);
  if l.Length mod SizeOf(short) <> 0 then
    BSP_Funny_Lump_Size;
  count := l.Length div SizeOf(short);
  _out := Hunk_AllocName(count * SizeOf(Pmsurface_t), loadname);

  loadmodel.marksurfaces := _out;
  loadmodel.nummarksurfaces := count;

  for i := 0 to count - 1 do
  begin
    j := LittleShort(_in[i]);
    if j >= loadmodel.numsurfaces then
      Sys_Error('Mod_ParseMarksurfaces: bad surface number');
    _out[i] := @loadmodel.surfaces[j];
  end;
end;

procedure BSP_LoadNodes(l: PBSPLump);
var
  i, j, count, p: integer;
  _in: PBSPNode;
  _out: Pmnode_t;
begin
  _in := PBSPNode(@mod_base[l.Offset]);
  if l.Length mod SizeOf(TBSPNode) <> 0 then
    BSP_Funny_Lump_Size;
  count := l.Length div SizeOf(TBSPNode);
  _out := Hunk_AllocName(count * SizeOf(mnode_t), loadname);

  loadmodel.nodes := _out;
  loadmodel.numnodes := count;

  for i := 0 to count - 1 do
  begin
    for j := 0 to 2 do
    begin
      _out.minmaxs[j] := LittleShort(_in.mins[j]);
      _out.minmaxs[3 + j] := LittleShort(_in.maxs[j]);
    end;

    p := LittleLong(_in.PlaneIndex);
    _out.plane := @loadmodel.planes[p];

    _out.firstsurface := LittleShort(_in.firstface);
    _out.numsurfaces := LittleShort(_in.numfaces);

    for j := 0 to 1 do
    begin
      p := LittleShort(_in.children[j]);
      if p >= 0 then
      begin
        _out.children[j] := loadmodel.nodes; //[p] // JVAL check this
        inc(_out.children[j], p);
      end
      else
        _out.children[j] := Pmnode_t(@loadmodel.leafs[-1 - p]); // JVAL check this
    end;
    inc(_in);
    inc(_out);
  end;

  Mod_SetParent(loadmodel.nodes, nil); // sets nodes and leafs
end;

procedure BSP_LoadPlanes(l: PBSPLump);
var
  i, j: integer;
  _out: Pmplane_t;
  _in: PBSPPlane;
  count: integer;
  bits: integer;
begin
  _in := PBSPPlane(@mod_base[l.Offset]);
  if l.Length mod SizeOf(TBSPPlane) <> 0 then
    BSP_Funny_Lump_Size;
  count := l.Length div SizeOf(TBSPPlane);
  _out := Hunk_AllocName(count * 2 * SizeOf(mplane_t), loadname);

  loadmodel.planes := Pmplane_tArray(_out);
  loadmodel.numplanes := count;

  for i := 0 to count - 1 do
  begin
    bits := 0;
    for j := 0 to 2 do
    begin
      _out.normal[j] := LittleFloat(_in.normal[j]);
      if _out.normal[j] < 0 then
        bits := bits or (1 shl j);
    end;

    _out.dist := LittleFloat(_in.dist);
    _out.PlaneType := LittleLong(_in.PlaneType);
    _out.signbits := bits;
    inc(_in);
    inc(_out);
  end;
end;

procedure BSP_LoadSubmodels(l: PBSPLump);
var
  _in: PBSPModel;
  _out: PBSPModel;
  i, j, count: integer;
begin
  _in := PBSPModel(@mod_base[l.Offset]);
  if l.Length mod SizeOf(TBSPModel) <> 0 then
    BSP_Funny_Lump_Size;
  count := l.Length div SizeOf(TBSPModel);
  _out := Hunk_AllocName(count * SizeOf(TBSPModel), loadname);

  loadmodel.submodels := PBSPModelArray(_out);
  loadmodel.numsubmodels := count;

  for i := 0 to count - 1 do
  begin
    for j := 0 to 2 do
    begin // spread the mins / maxs by a pixel
      _out.mins[j] := LittleFloat(_in.mins[j]) - 1;
      _out.maxs[j] := LittleFloat(_in.maxs[j]) + 1;
      _out.origin[j] := LittleFloat(_in.origin[j]);
    end;
    for j := 0 to MAX_MAP_HULLS - 1 do
      _out.headnode[j] := LittleLong(_in.headnode[j]);
    _out.visleafs := LittleLong(_in.visleafs);
    _out.firstface := LittleLong(_in.firstface);
    _out.numfaces := LittleLong(_in.numfaces);
    inc(_in);
    inc(_out);
  end;
end;

procedure BSP_LoadSurfedges(l: PBSPLump);
var
  i, count: integer;
  _in, _out: PIntegerArray;
begin
  _in := PIntegerArray(@mod_base[l.Offset]);
  if l.Length mod SizeOf(integer) <> 0 then
    BSP_Funny_Lump_Size;
  count := l.Length div SizeOf(integer);
  _out := Hunk_AllocName(count * SizeOf(integer), loadname);

  loadmodel.surfedges := _out;
  loadmodel.numsurfedges := count;

  for i := 0 to count - 1 do
    _out[i] := LittleLong(_in[i]);
end;

procedure BSP_LoadTexinfo(l: PBSPLump);
var
  _in: Ptexinfo_t;
  _out: Pmtexinfo_t;
  i, j, count: integer;
  miptex: integer;
  len1, len2: single;
begin
  _in := Ptexinfo_t(@mod_base[l.Offset]);
  if l.Length mod SizeOf(texinfo_t) <> 0 then
    BSP_Funny_Lump_Size;
  count := l.Length div SizeOf(texinfo_t);
  _out := Hunk_AllocName(count * SizeOf(mtexinfo_t), loadname);

  loadmodel.texinfo := Pmtexinfo_tArray(_out);
  loadmodel.numtexinfo := count;

  for i := 0 to count - 1 do
  begin
    for j := 0 to 7 do
      _out.vecs[0][j] := LittleFloat(_in.vecs[0][j]);
    len1 := VectorLength(@_out.vecs[0]); // JVAL was Length()
    len2 := VectorLength(@_out.vecs[1]);
    len1 := (len1 + len2) / 2;
    if len1 < 0.32 then
      _out.mipadjust := 4
    else if len1 < 0.49 then
      _out.mipadjust := 3
    else if len1 < 0.99 then
      _out.mipadjust := 2
    else
      _out.mipadjust := 1;
    miptex := LittleLong(_in.miptex);
    _out.flags := LittleLong(_in.flags);

    if loadmodel.textures = nil then
    begin
      _out.texture := r_notexture_mip; // checkerboard texture
      _out.flags := 0;
    end
    else
    begin
      if miptex >= loadmodel.numtextures then
        Sys_Error('miptex >= loadmodel.numtextures');
      _out.texture := loadmodel.textures[miptex];
      if _out.texture = nil then
      begin
        _out.texture := r_notexture_mip; // texture not found
        _out.flags := 0;
      end;
    end;
    inc(_in);
    inc(_out);
  end;
end;

procedure BSP_LoadTextures(l: PBSPLump);
const
  ANIM_CYCLE = 2;
var
  i, j, pixels, altmax: integer;
  num, max: char;
  mt: Pmiptex_t;
  tx, tx2: Ptexture_t;
  anims: array[0..9] of Ptexture_t;
  altanims: array[0..9] of Ptexture_t;
  m: Pdmiptexlump_t;
begin
  if l.Length = 0 then
  begin
    loadmodel.textures := nil;
    exit;
  end;
  m := Pdmiptexlump_t(@mod_base[l.Offset]);

  m.nummiptex := LittleLong(m.nummiptex);

  loadmodel.numtextures := m.nummiptex;
  loadmodel.textures := Hunk_AllocName(m.nummiptex * SizeOf(texture_t), loadname);
  for i := 0 to m.nummiptex - 1 do
  begin
    m.dataofs[i] := LittleLong(m.dataofs[i]);
    if m.dataofs[i] = -1 then
      continue;
    mt := Pmiptex_t(integer(m) + m.dataofs[i]);
    mt.width := LittleLong(mt.width);
    mt.height := LittleLong(mt.height);
    for j := 0 to MIPLEVELS - 1 do
      mt.offsets[j] := LittleLong(mt.offsets[j]);

    if (mt.width and 15 <> 0) or (mt.height and 15 <> 0) then
      Sys_Error('Texture %s is not 16 aligned', [mt.name]);
    pixels := mt.width * mt.height div 64 * 85; // JVAL should check operation priorities
    tx := Hunk_AllocName(SizeOf(texture_t) + pixels, loadname);
    loadmodel.textures[i] := tx;

    memcpy(@tx.name, @mt.name, SizeOf(tx.name));
    tx.width := mt.width;
    tx.height := mt.height;
    for j := 0 to MIPLEVELS - 1 do
      tx.offsets[j] := mt.offsets[j] + SizeOf(texture_t) - SizeOf(miptex_t);
    // the pixels immediately follow the structures
    memcpy(pointer(integer(tx) + SizeOf(texture_t)), pointer(integer(mt) + SizeOf(miptex_t)), pixels);

    if Q_strncmp(mt.name, 'sky', 3) = 0 then
      R_InitSky(tx)
    else
    begin
      texture_mode := GL_LINEAR_MIPMAP_LINEAR; //_LINEAR;

      textures_path := loadname;
      tx.gl_texturenum := GL_LoadTexture(mt.name, tx.width, tx.height, pointer(integer(tx) + SizeOf(texture_t)), true, false);
      textures_path := '';

      texture_mode := GL_LINEAR;
    end;
  end;

//
// sequence the animations
//
  for i := 0 to m.nummiptex - 1 do
  begin
    tx := loadmodel.textures[i];
    if (tx = nil) or (tx.name[0] <> '+') then
      continue;
    if tx.anim_next <> nil then
      continue; // allready sequenced

  // find the number of frames in the animation
    ZeroMemory(@anims, SizeOf(anims));
    ZeroMemory(@altanims, SizeOf(altanims));

    max := tx.name[1];
    altmax := 0;
    if (max >= 'a') and (max <= 'z') then
      max := Chr(Ord(max) - (Ord('a') - Ord('A')));
    if (max >= '0') and (max <= '9') then
    begin
      max := Chr(Ord(max) - Ord('0'));
      altmax := 0;
      anims[Ord(max)] := tx;
      inc(max);
    end
    else if (max >= 'A') and (max <= 'J') then
    begin
      altmax := Ord(max) - Ord('A');
      max := #0;
      altanims[altmax] := tx;
      inc(altmax);
    end
    else
      Sys_Error('Bad animating texture %s', [tx.name]);

    for j := i + 1 to m.nummiptex - 1 do
    begin
      tx2 := loadmodel.textures[j];
      if (tx2 = nil) or (tx2.name[0] <> '+') then
        continue;
      if strcmp(PChar(@tx2.name[2]), PChar(@(tx.name[2]))) <> 0 then // JVAL check!
        continue;

      num := tx2.name[1];
      if (num >= 'a') and (num <= 'z') then
        num := Chr(Ord(num) - (Ord('a') - Ord('A')));
      if (num >= '0') and (num <= '9') then
      begin
        num := Chr(Ord(num) - Ord('0'));
        anims[Ord(num)] := tx2;
        if Ord(num) + 1 > Ord(max) then
          max := Chr(Ord(num) + 1);
      end
      else if (num >= 'A') and (num <= 'J') then
      begin
        num := Chr(Ord(num) - Ord('A'));
        altanims[Ord(num)] := tx2;
        if Ord(num) + 1 > altmax then
          altmax := Ord(num) + 1;
      end
      else
        Sys_Error('Bad animating texture %s', [tx.name]);
    end;

  // link them all together
    for j := 0 to Ord(max) - 1 do
    begin
      tx2 := anims[j];
      if tx2 = nil then
        Sys_Error('Missing frame %d of %s', [j, tx.name]);
      tx2.anim_total := Ord(max) * ANIM_CYCLE;
      tx2.anim_min := j * ANIM_CYCLE;
      tx2.anim_max := (j + 1) * ANIM_CYCLE;
      tx2.anim_next := anims[(j + 1) mod Ord(max)];
      if altmax <> 0 then
        tx2.alternate_anims := altanims[0];
    end;
    for j := 0 to altmax - 1 do
    begin
      tx2 := altanims[j];
      if tx2 = nil then
        Sys_Error('Missing frame %d of %s', [j, tx.name]);
      tx2.anim_total := altmax * ANIM_CYCLE;
      tx2.anim_min := j * ANIM_CYCLE;
      tx2.anim_max := (j + 1) * ANIM_CYCLE;
      tx2.anim_next := altanims[(j + 1) mod altmax];
      if max <> #0 then
        tx2.alternate_anims := anims[0];
    end;
  end;
end;

procedure BSP_LoadTexturesHL(l: PBSPLump);
const
  ANIM_CYCLE = 2;
var
  i, j, pixels, altmax: integer;
  num, max: char;
  mt: Pmiptex_t;
  tx, tx2: Ptexture_t;
  anims: array[0..9] of Ptexture_t;
  altanims: array[0..9] of Ptexture_t;
  m: Pdmiptexlump_t;
begin
  if l.Length = 0 then
  begin
    loadmodel.textures := nil;
    exit;
  end;
  m := Pdmiptexlump_t(@mod_base[l.Offset]);

  m.nummiptex := LittleLong(m.nummiptex);

  loadmodel.numtextures := m.nummiptex;
  loadmodel.textures := Hunk_AllocName(m.nummiptex * SizeOf(texture_t), loadname);
  for i := 0 to m.nummiptex - 1 do
  begin
    m.dataofs[i] := LittleLong(m.dataofs[i]);
    if m.dataofs[i] = -1 then
      continue;
    mt := Pmiptex_t(integer(m) + m.dataofs[i]);
    mt.width := LittleLong(mt.width);
    mt.height := LittleLong(mt.height);

    for j := 0 to MIPLEVELS - 1 do
      mt.offsets[j] := LittleLong(mt.offsets[j]);

    if (mt.width and 15 <> 0) or (mt.height and 15 <> 0) then
      Sys_Error('Texture %s is not 16 aligned', [mt.name]);

    pixels := mt.width * mt.height div 64 * 85; // JVAL should check operation priorities

    tx := Hunk_AllocName(SizeOf(texture_t) + pixels, loadname);
    loadmodel.textures[i] := tx;

    memcpy(@tx.name, @mt.name, SizeOf(tx.name));
    tx.width := mt.width;
    tx.height := mt.height;
    for j := 0 to MIPLEVELS - 1 do
      tx.offsets[j] := mt.offsets[j] + SizeOf(texture_t) - SizeOf(miptex_t);

    if (mt.offsets[0] = 0) and
       (mt.offsets[1] = 0) and
       (mt.offsets[2] = 0) and
       (mt.offsets[3] = 0) then
    begin
      if Q_strncmp(mt.name, 'sky', 3) = 0 then
        R_InitSky(tx)
      else
      begin
        texture_mode := {GL_LINEAR_MIPMAP_NEAREST} GL_LINEAR; //_LINEAR;
        textures_path := 'cs'; //+loadname;
        tx.gl_texturenum := GL_LoadTexture24(mt.name, tx.width, tx.height, nil, true, false, nil);
        textures_path := '';
        texture_mode := GL_LINEAR_MIPMAP_LINEAR;
      end;
    end;
  end;
//
// sequence the animations
//
  for i := 0 to m.nummiptex - 1 do
  begin
    tx := loadmodel.textures[i];
    if (tx = nil) or (tx.name[0] <> '+') then
      continue;
    if tx.anim_next <> nil then
      continue; // allready sequenced

  // find the number of frames in the animation
    ZeroMemory(@anims, SizeOf(anims));
    ZeroMemory(@altanims, SizeOf(altanims));

    max := tx.name[1];
    altmax := 0;
    if (max >= 'a') and (max <= 'z') then
      max := Chr(Ord(max) - (Ord('a') - Ord('A')));
    if (max >= '0') and (max <= '9') then
    begin
      max := Chr(Ord(max) - Ord('0'));
      altmax := 0;
      anims[Ord(max)] := tx;
      inc(max);
    end
    else if (max >= 'A') and (max <= 'J') then
    begin
      altmax := Ord(max) - Ord('A');
      max := #0;
      altanims[altmax] := tx;
      inc(altmax);
    end
    else
      Sys_Error('Bad animating texture %s', [tx.name]);

    for j := i + 1 to m.nummiptex - 1 do
    begin
      tx2 := loadmodel.textures[j];
      if (tx2 = nil) or (tx2.name[0] <> '+') then
        continue;
      if strcmp(PChar(@tx2.name[2]), PChar(@(tx.name[2]))) <> 0 then // JVAL check!
        continue;

      num := tx2.name[1];
      if (num >= 'a') and (num <= 'z') then
        num := Chr(Ord(num) - (Ord('a') - Ord('A')));
      if (num >= '0') and (num <= '9') then
      begin
        num := Chr(Ord(num) - Ord('0'));
        anims[Ord(num)] := tx2;
        if Ord(num) + 1 > Ord(max) then
          max := Chr(Ord(num) + 1);
      end
      else if (num >= 'A') and (num <= 'J') then
      begin
        num := Chr(Ord(num) - Ord('A'));
        altanims[Ord(num)] := tx2;
        if Ord(num) + 1 > altmax then
          altmax := Ord(num) + 1;
      end
      else
        Sys_Error('Bad animating texture %s', [tx.name]);
    end;

  // link them all together
    for j := 0 to Ord(max) - 1 do
    begin
      tx2 := anims[j];
      if tx2 = nil then
        Sys_Error('Missing frame %d of %s', [j, tx.name]);
      tx2.anim_total := Ord(max) * ANIM_CYCLE;
      tx2.anim_min := j * ANIM_CYCLE;
      tx2.anim_max := (j + 1) * ANIM_CYCLE;
      tx2.anim_next := anims[(j + 1) mod Ord(max)];
      if altmax <> 0 then
        tx2.alternate_anims := altanims[0];
    end;
    for j := 0 to altmax - 1 do
    begin
      tx2 := altanims[j];
      if tx2 = nil then
        Sys_Error('Missing frame %d of %s', [j, tx.name]);
      tx2.anim_total := altmax * ANIM_CYCLE;
      tx2.anim_min := j * ANIM_CYCLE;
      tx2.anim_max := (j + 1) * ANIM_CYCLE;
      tx2.anim_next := altanims[(j + 1) mod altmax];
      if max <> #0 then
        tx2.alternate_anims := anims[0];
    end;
  end;
end;

procedure BSP_LoadVertexes(l: PBSPLump);
var
  _in: PBSPVertex;
  _out: Pmvertex_t;
  i, count: integer;
begin
  _in := PBSPVertex(@mod_base[l.Offset]);
  if l.Length mod SizeOf(TBSPVertex) <> 0 then
    BSP_Funny_Lump_Size;
  count := l.Length div SizeOf(TBSPVertex);
  _out := Hunk_AllocName(count * SizeOf(mvertex_t), loadname);

  loadmodel.vertexes := Pmvertex_tArray(_out);
  loadmodel.numvertexes := count;

  for i := 0 to count - 1 do
  begin
    _out.position := _in.Position;
    inc(_in); inc(_out);
  end;
end;

procedure BSP_LoadVisibility(l: PBSPLump);
begin
  if l.Length = 0 then
  begin
    loadmodel.visdata := nil;
    exit;
  end;

  loadmodel.visdata := Hunk_AllocName(l.Length, loadname);
  memcpy(loadmodel.visdata, @mod_base[l.Offset], l.Length);
end;

procedure BSP_MakeHull0;
var
  _in, child: Pmnode_t;
  _out: PBSPClipNode;
  i, j, count: integer;
  hull: Phull_t;
begin
  hull := @loadmodel.hulls[0];

  _in := loadmodel.nodes;
  count := loadmodel.numnodes;
  _out := Hunk_AllocName(count * SizeOf(TBSPClipNode), loadname);

  hull.clipnodes := _out;
  hull.firstclipnode := 0;
  hull.lastclipnode := count - 1;
  hull.planes := @loadmodel.planes[0];

  for i := 0 to count - 1 do
  begin
    _out.PlaneIndex := (integer(_in.plane) - integer(loadmodel.planes)) div SizeOf(mplane_t {mnode_t}); // TODO JVAL -> should check this
    for j := 0 to 1 do
    begin
      child := _in.children[j];
      if child.contents < 0 then
        _out.children[j] := child.contents
      else
        _out.children[j] := (integer(child) - integer(loadmodel.nodes)) div SizeOf(mnode_t); // JVAL CHECK CHECK CHECK!@!!!!!!
    end;
    inc(_in);
    inc(_out);
  end;
end;

procedure BSP_LoadMap_HalfLife(mdl: PBSPModelFile; buffer: pointer);
var
  i, j: integer;
  header: PBSPHeader;
  bm: PBSPModel;
  name: array[0..9] of char;
begin
  gl_lightmap_format := GL_RGB;
  loadmodel._type := mod_brush;

  header := PBSPHeader(buffer);
  //
  // check ID :)

// swap all the lumps
  mod_base := PByteArray(header);

  for i := 0 to SizeOf(TBSPHeader) div 4 - 1 do
    PIntegerArray(header)[i] := LittleLong(PIntegerArray(header)[i]);

// load into heap

  BSP_LoadVertexes(@header.lumps[LUMP_VERTEXES]);
  BSP_LoadEdges(@header.lumps[LUMP_EDGES]);
  BSP_LoadSurfedges(@header.lumps[LUMP_SURFEDGES]);
  BSP_LoadTexturesHL(@header.lumps[LUMP_TEXTURES]);
  BSP_LoadLighting(@header.lumps[LUMP_LIGHTING]);
  BSP_LoadPlanes(@header.lumps[LUMP_PLANES]);
  BSP_LoadTexinfo(@header.lumps[LUMP_TEXINFO]);
  BSP_LoadFaces(@header.lumps[LUMP_FACES]);
  BSP_LoadMarksurfaces(@header.lumps[LUMP_MARKSURFACES]);
  BSP_LoadVisibility(@header.lumps[LUMP_VISIBILITY]);
  BSP_LoadLeafs(@header.lumps[LUMP_LEAFS]);
  BSP_LoadNodes(@header.lumps[LUMP_NODES]);
  BSP_LoadClipnodes(@header.lumps[LUMP_CLIPNODES]);
  BSP_LoadEntities(@header.lumps[LUMP_ENTITIES]);
  BSP_LoadSubmodels(@header.lumps[LUMP_MODELS]);

  BSP_MakeHull0;

  mdl.numframes := 2; // regular and alternate animation

//
// set up the submodels (FIXME: this is confusing)
//
  for i := 0 to mdl.numsubmodels - 1 do
  begin
    bm := @mdl.submodels[i];

    mdl.hulls[0].firstclipnode := bm.headnode[0];
    for j := 1 to MAX_MAP_HULLS - 1 do
    begin
      mdl.hulls[j].firstclipnode := bm.headnode[j];
      mdl.hulls[j].lastclipnode := mdl.numclipnodes - 1;
    end;

    mdl.firstmodelsurface := bm.firstface;
    mdl.nummodelsurfaces := bm.numfaces;

    VectorCopy(@bm.maxs, @mdl.maxs);
    VectorCopy(@bm.mins, @mdl.mins);

    mdl.radius := RadiusFromBounds(@mdl.mins, @mdl.maxs);

    mdl.numleafs := bm.visleafs;

    if i < mdl.numsubmodels - 1 then
    begin // duplicate the basic information
      sprintf(name, '*' + IntToStr(i + 1));
      loadmodel := Mod_FindName(name);
      loadmodel^ := mdl^;
      strcpy(loadmodel.name, name);
      mdl := loadmodel;
    end;
  end;
end;

procedure BSP_LoadMap_QuakeI(mdl: PBSPModelFile; buffer: pointer);
var
  i, j: integer;
  header: PBSPHeader;
  bm: PBSPModel;
  name: array[0..9] of char;
begin
  gl_lightmap_format := GL_LUMINANCE;
  loadmodel._type := mod_brush;

  header := PBSPHeader(buffer);
  //
  // check ID :)

// swap all the lumps
  mod_base := PByteArray(header);

  for i := 0 to SizeOf(TBSPHeader) div 4 - 1 do
    PIntegerArray(header)[i] := LittleLong(PIntegerArray(header)[i]);

// load into heap

  BSP_LoadVertexes(@header.lumps[LUMP_VERTEXES]);
  BSP_LoadEdges(@header.lumps[LUMP_EDGES]);
  BSP_LoadSurfedges(@header.lumps[LUMP_SURFEDGES]);
  BSP_LoadTextures(@header.lumps[LUMP_TEXTURES]);
  BSP_LoadLighting(@header.lumps[LUMP_LIGHTING]);
  BSP_LoadPlanes(@header.lumps[LUMP_PLANES]);
  BSP_LoadTexinfo(@header.lumps[LUMP_TEXINFO]);
  BSP_LoadFaces(@header.lumps[LUMP_FACES]);
  BSP_LoadMarksurfaces(@header.lumps[LUMP_MARKSURFACES]);
  BSP_LoadVisibility(@header.lumps[LUMP_VISIBILITY]);
  BSP_LoadLeafs(@header.lumps[LUMP_LEAFS]);
  BSP_LoadNodes(@header.lumps[LUMP_NODES]);
  BSP_LoadClipnodes(@header.lumps[LUMP_CLIPNODES]);
  BSP_LoadEntities(@header.lumps[LUMP_ENTITIES]);
  BSP_LoadSubmodels(@header.lumps[LUMP_MODELS]);

  BSP_MakeHull0;

  mdl.numframes := 2; // regular and alternate animation

//
// set up the submodels (FIXME: this is confusing)
//
  for i := 0 to mdl.numsubmodels - 1 do
  begin
    bm := @mdl.submodels[i];

    mdl.hulls[0].firstclipnode := bm.headnode[0];
    for j := 1 to MAX_MAP_HULLS - 1 do
    begin
      mdl.hulls[j].firstclipnode := bm.headnode[j];
      mdl.hulls[j].lastclipnode := mdl.numclipnodes - 1;
    end;

    mdl.firstmodelsurface := bm.firstface;
    mdl.nummodelsurfaces := bm.numfaces;

    VectorCopy(@bm.maxs, @mdl.maxs);
    VectorCopy(@bm.mins, @mdl.mins);

    mdl.radius := RadiusFromBounds(@mdl.mins, @mdl.maxs);

    mdl.numleafs := bm.visleafs;

    if i < mdl.numsubmodels - 1 then
    begin // duplicate the basic information
      sprintf(name, '*%d', [i + 1]);
      loadmodel := Mod_FindName(name);
      loadmodel^ := mdl^;
      strcpy(loadmodel.name, name);
      mdl := loadmodel;
    end;
  end;
end;

end.

