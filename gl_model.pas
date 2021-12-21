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

unit gl_model;

// models.c -- model loading and caching

// models are the only shared resource between a client and server running
// on the same machine.

interface

uses
  q_delphi,
  q_vector,
  gl_planes,
  gl_texture,
  modelgen,
  spritegn,
  gl_model_h,
  cvar;

(*

d*_t structures are on-disk representations
m*_t structures are in-memory

*)

procedure Mod_Init;
procedure Mod_ClearAll;
function Mod_FindName(name: PChar): PBSPModelFile;
function Mod_ForName(name: PChar; crash: qboolean): PBSPModelFile;
function Mod_Extradata(mdl: PBSPModelFile): pointer; // handles caching
procedure Mod_TouchModel(name: PChar);

function Mod_PointInLeaf(p: PVector3f; model: PBSPModelFile): Pmleaf_t;
function Mod_LeafPVS(leaf: Pmleaf_t; model: PBSPModelFile): PByteArray;

function Mod_LoadModel(mdl: PBSPModelFile; crash: qboolean): PBSPModelFile;
procedure Mod_LoadAliasModel(mdl: PBSPModelFile; buffer: pointer);
procedure Mod_LoadSpriteModel(mdl: PBSPModelFile; buffer: pointer);

procedure Mod_Print;
procedure CalcSurfaceExtents(s: Pmsurface_t);
procedure Mod_SetParent(node: Pmnode_t; parent: Pmnode_t);

var
  pheader: Paliashdr_t;
  stverts: array[0..MAXALIASVERTS - 1] of stvert_t;
  triangles: array[0..MAXALIASTRIS - 1] of mtriangle_t;

var
// a pose is a single set of vertexes.  a frame may be
// an animating sequence of poses
  poseverts: array[0..MAXALIASFRAMES - 1] of Ptrivertx_t;
  posenum: integer = 0;

var
  gl_subdivide_size: cvar_t = (name: 'gl_subdivide_size'; text: '128'; archive: true);

implementation

uses
  bspfile,
  bspconst,
  bsptypes,
  zone,
  sys_win,
  mathlib,
  common,
  gl_vidnt,
  OpenGL12,
  gl_mesh,
  gl_defs,
  quakedef,
  console;

(*
===============
Mod_Init
===============
*)

procedure Mod_Init;
begin
  Cvar_RegisterVariable(@gl_subdivide_size);
  memset(@mod_novis, $FF, SizeOf(mod_novis));
end;

(*
===============
Mod_Init

Caches the data if needed
===============
*)

function Mod_Extradata(mdl: PBSPModelFile): pointer;
var
  r: pointer;
begin
  r := Cache_Check(@mdl.cache);
  if r <> nil then
  begin
    result := r;
    exit;
  end;

  Mod_LoadModel(mdl, true);

  if mdl.cache.data = nil then
    Sys_Error('Mod_Extradata: caching failed');
  result := mdl.cache.data;
end;

(*
===============
Mod_PointInLeaf
===============
*)

function Mod_PointInLeaf(p: PVector3f; model: PBSPModelFile): Pmleaf_t;
var
  node: Pmnode_t;
  d: single;
  plane: Pmplane_t;
begin
  if (model = nil) or (model.nodes = nil) then
    Sys_Error('Mod_PointInLeaf: bad model');

  node := model.nodes;
  while true do
  begin
    if node.contents < 0 then
    begin
      result := Pmleaf_t(node);
      exit;
    end;
    plane := node.plane;
    d := VectorDotProduct(p, @plane.normal) - plane.dist;
    if d > 0 then
      node := node.children[0]
    else
      node := node.children[1];
  end;

  result := nil; // never reached
end;


(*
===================
Mod_DecompressVis
===================
*)
var
  decompressed_Vis: array[0..MAX_MAP_LEAFS div 8 - 1] of byte;

function Mod_DecompressVis(_in: PByteArray; model: PBSPModelFile): PByteArray;
var
  c: integer;
  _out: PByte;
  row: integer;
begin
  row := ((model.numleafs + 7) shr 3);
  _out := @decompressed_Vis[0];

  if _in = nil then
  begin // no vis info, so make all visible
    while row <> 0 do
    begin
      _out^ := $FF;
      inc(_out);
      dec(row);
    end;
    result := @decompressed_Vis;
    exit;
  end;

  repeat
    if _in[0] <> 0 then
    begin
      _out^ := _in[0];
      inc(_out);
      _in := @_in[1];
      continue;
    end;

    c := _in[1]; // JVAL -> should check this
    _in := @_in[2];
    while c <> 0 do
    begin
      _out^ := 0;
      inc(_out);
      dec(c);
    end;
  until integer(_out) - integer(@decompressed_Vis[0]) >= row;

  result := @decompressed_Vis[0];
end;

function Mod_LeafPVS(leaf: Pmleaf_t; model: PBSPModelFile): PByteArray;
begin
  if leaf = @model.leafs[0] then
    result := @mod_novis
  else
    result := Mod_DecompressVis(leaf.compressed_vis, model);
end;

(*
===================
Mod_ClearAll
===================
*)

procedure Mod_ClearAll;
var
  i: integer;
  mdl: PBSPModelFile;
begin
  mdl := @mod_known[0];
  for i := 0 to mod_numknown - 1 do
  begin
    if mdl._type <> mod_alias then
      mdl.needload := true;
    inc(mdl);
  end;
end;

(*
==================
Mod_FindName

==================
*)

function Mod_FindName(name: PChar): PBSPModelFile;
var
  i: integer;
begin
  if name[0] = #0 then
    Sys_Error('Mod_ForName: NULL name');

//
// search the currently loaded models
//
  result := @mod_known[0];
  i := 0;
  while i < mod_numknown do
  begin
    if strcmp(result.name, name) = 0 then
      break;
    inc(result);
    inc(i);
  end;

  if i = mod_numknown then
  begin
    if mod_numknown = MAX_MOD_KNOWN then
      Sys_Error('mod_numknown = MAX_MOD_KNOWN');
    strcpy(result.name, name);
    result.needload := true;
    inc(mod_numknown);
  end;
end;

(*
==================
Mod_TouchModel

==================
*)

procedure Mod_TouchModel(name: PChar);
var
  mdl: PBSPModelFile;
begin
  mdl := Mod_FindName(name);

  if not mdl.needload then
  begin
    if mdl._type = mod_alias then
      Cache_Check(@mdl.cache);
  end;
end;

procedure Mod_LoadBrushModel(mdl: PBSPModelFile; buffer: pointer);
var
  i: integer;
  header: PBSPHeader;
begin
  loadmodel._type := mod_brush;

  header := PBSPHeader(buffer);

  i := LittleLong(header.version);
  case i of
    BSPVERSION_QuakeI: BSP_LoadMap_QuakeI(mdl, buffer);
    BSPVERSION_HalfLife: BSP_LoadMap_HalfLife(mdl, buffer);
  else
    Sys_Error('Mod_LoadBrushModel: %s has wrong version number (%d should be %d)', [mdl.name, i, BSPVERSION_QuakeI]);
  end;
end;

(*
==================
Mod_LoadModel

Loads a model into the cache
==================
*)

function Mod_LoadModel(mdl: PBSPModelFile; crash: qboolean): PBSPModelFile;
var
  d: pointer;
  buf: PunsignedArray;
  stackbuf: array[0..1023] of byte; // avoid dirtying the cache heap
begin
  if not mdl.needload then
  begin
    if mdl._type = mod_alias then
    begin
      d := Cache_Check(@mdl.cache);
      if d <> nil then
      begin
        result := mdl;
        exit;
      end;
    end
    else
    begin
      result := mdl; // not cached at all
      exit;
    end;
  end;

//
// because the world is so huge, load it one piece at a time
//
//
// load the file
//
  buf := PunsignedArray(COM_LoadStackFile(mdl.name, @stackbuf, SizeOf(stackbuf)));
  if buf = nil then
  begin
    if crash then
      Sys_Error('Mod_NumForName: %s not found', [mdl.name]);
    result := nil;
    exit;
  end;

//
// allocate a new model
//
  COM_FileBase(mdl.name, loadname);

  loadmodel := mdl;

//
// fill it in
//

// call the apropriate loader
  mdl.needload := false;

  case LittleLong(buf[0]) of
    IDPOLYHEADER: Mod_LoadAliasModel(mdl, buf);
    IDSPRITEHEADER: Mod_LoadSpriteModel(mdl, buf);
  else
    Mod_LoadBrushModel(mdl, buf);
  end;

  result := mdl;
end;

(*
==================
Mod_ForName

Loads in a model for the given name
==================
*)

function Mod_ForName(name: PChar; crash: qboolean): PBSPModelFile;
var
  mdl: PBSPModelFile;
begin
  mdl := Mod_FindName(name);

  result := Mod_LoadModel(mdl, crash);
end;


(*
===============================================================================

          BRUSHMODEL LOADING

===============================================================================
*)

(*
================
CalcSurfaceExtents

Fills in s->texturemins[] and s->extents[]
================
*)

procedure CalcSurfaceExtents(s: Pmsurface_t);
var
  mins, maxs: array[0..1] of single;
  val: single;
  i, j, e: integer;
  v: Pmvertex_t;
  tex: Pmtexinfo_t;
  bmins, bmaxs: array[0..1] of integer;
begin
  mins[0] := 999999;
  mins[1] := 999999;
  maxs[0] := -999999;
  maxs[1] := -999999;

  tex := s.texinfo;

  for i := 0 to s.numedges - 1 do
  begin
    e := loadmodel.surfedges[s.firstedge + i];
    if e >= 0 then
      v := @loadmodel.vertexes[loadmodel.edges[e].v[0]]
    else
      v := @loadmodel.vertexes[loadmodel.edges[-e].v[1]];

    for j := 0 to 1 do
    begin
      val := v.position[0] * tex.vecs[j][0] +
        v.position[1] * tex.vecs[j][1] +
        v.position[2] * tex.vecs[j][2] +
        tex.vecs[j][3];
      if val < mins[j] then
        mins[j] := val;
      if val > maxs[j] then
        maxs[j] := val;
    end;
  end;

  for i := 0 to 1 do
  begin
    bmins[i] := floor(mins[i] / 16);
    bmaxs[i] := ceil(maxs[i] / 16);

    s.texturemins[i] := bmins[i] * 16;
    s.extents[i] := (bmaxs[i] - bmins[i]) * 16;
    if (tex.flags and TEX_SPECIAL = 0) and (s.extents[i] > 512) then //  /* 256 */ )
      Sys_Error('Bad surface extents');
  end;
end;


(*
=================
Mod_SetParent
=================
*)

procedure Mod_SetParent(node: Pmnode_t; parent: Pmnode_t);
begin
  node.parent := parent;
  if node.contents < 0 then
    exit;

  Mod_SetParent(node.children[0], node);
  Mod_SetParent(node.children[1], node);
end;

(*
==============================================================================

ALIAS MODELS

==============================================================================
*)


//byte    **player_8bit_texels_tbl;
//byte    *player_8bit_texels;

(*
=================
Mod_LoadAliasFrame
=================
*)

function Mod_LoadAliasFrame(pin: pointer; frame: Pmaliasframedesc_t): pointer;
var
  pinframe: Ptrivertx_t;
  i: integer;
  pdaliasframe: Pdaliasframe_t;
begin
  pdaliasframe := Pdaliasframe_t(pin);

  strcpy(frame.name, pdaliasframe.name);
  frame.firstpose := posenum;
  frame.numposes := 1;

  for i := 0 to 2 do
  begin
  // these are byte values, so we don't have to worry about
  // endianness
    frame.bboxmin.v[i] := pdaliasframe.bboxmin.v[i];
    frame.bboxmin.v[i] := pdaliasframe.bboxmax.v[i];
  end;

  inc(pdaliasframe);
  pinframe := Ptrivertx_t(pdaliasframe);

  poseverts[posenum] := pinframe;
  inc(posenum);

  inc(pinframe, pheader.numverts);

  result := pointer(pinframe);
end;


(*
=================
Mod_LoadAliasGroup
=================
*)

function Mod_LoadAliasGroup(pin: pointer; frame: Pmaliasframedesc_t): pointer;
var
  pingroup: Pdaliasgroup_t;
  i, numframes: integer;
  pin_intervals: Pdaliasinterval_t;
  ptemp: pointer;
begin
  pingroup := Pdaliasgroup_t(pin);

  numframes := LittleLong(pingroup.numframes);

  frame.firstpose := posenum;
  frame.numposes := numframes;

  for i := 0 to 2 do
  begin
  // these are byte values, so we don't have to worry about endianness
    frame.bboxmin.v[i] := pingroup.bboxmin.v[i];
    frame.bboxmin.v[i] := pingroup.bboxmax.v[i];
  end;

  pin_intervals := Pdaliasinterval_t(integer(pingroup) + SizeOf(daliasgroup_t));

  frame.interval := LittleFloat(pin_intervals.interval);

  inc(pin_intervals, numframes); // JVAL this should work!

  ptemp := pointer(pin_intervals);

  for i := 0 to numframes - 1 do
  begin
    poseverts[posenum] := Ptrivertx_t(integer(ptemp) + SizeOf(daliasframe_t));
    inc(posenum);

    ptemp := Ptrivertx_t((integer(ptemp) + SizeOf(daliasframe_t)) + SizeOf(trivertx_t) * pheader.numverts);
  end;

  result := ptemp;
end;

//=========================================================

(*
=================
Mod_FloodFillSkin

Fill background pixels so mipmapping doesn't have haloes - Ed
=================
*)

type
  floodfill_t = record
    x, y: short;
  end;

// must be a power of 2
const
  FLOODFILL_FIFO_SIZE = $1000;

  FLOODFILL_FIFO_MASK = (FLOODFILL_FIFO_SIZE - 1);

procedure Mod_FloodFillSkin(skin: PByteArray; skinwidth, skinheight: integer);
var
  fillcolor: byte; // assume this is the pixel to fill
  fifo: array[0..FLOODFILL_FIFO_SIZE - 1] of floodfill_t;
  inpt, outpt: integer;
  filledcolor: integer;
  i: integer;
  x, y: integer;
  fdc: integer;
  pos: PByteArray;

  procedure FLOODFILL_STEP(off, dx, dy: integer);
  begin
    if pos[off] = fillcolor then
    begin
      pos[off] := 255;
      fifo[inpt].x := x + dx;
      fifo[inpt].y := y + dy;
      inpt := (inpt + 1) and FLOODFILL_FIFO_MASK;
    end
    else if pos[off] <> 255 then
      fdc := pos[off];
  end;

begin
  fillcolor := skin[0];
  inpt := 0;
  outpt := 0;
  filledcolor := -1;

  if filledcolor = -1 then
  begin
    filledcolor := 0;
    // attempt to find opaque black
    for i := 0 to 255 do
      if d_8to24table[i] = 255 then // alpha 1.0
      begin
        filledcolor := i;
        break;
      end;
  end;

  // can't fill to filled color or to transparent color (used as visited marker)
  if (fillcolor = filledcolor) or (fillcolor = 255) then
  begin
    //printf( "not filling skin from %d to %d\n", fillcolor, filledcolor );
    exit;
  end;

  fifo[inpt].x := 0;
  fifo[inpt].y := 0;
  inpt := (inpt + 1) and FLOODFILL_FIFO_MASK;

  while outpt <> inpt do
  begin
    x := fifo[outpt].x;
    y := fifo[outpt].y;
    fdc := filledcolor;
    pos := @skin[x + skinwidth * y];

    outpt := (outpt + 1) and FLOODFILL_FIFO_MASK;

    if x > 0 then
      FLOODFILL_STEP(-1, -1, 0);
    if x < skinwidth - 1 then
      FLOODFILL_STEP(1, 1, 0);
    if y > 0 then
      FLOODFILL_STEP(-skinwidth, 0, -1);
    if y < skinheight - 1 then
      FLOODFILL_STEP(skinwidth, 0, 1);
    skin[x + skinwidth * y] := fdc;
  end;
end;

(*
===============
Mod_LoadAllSkins
===============
*)

function Mod_LoadAllSkins(numskins: integer; pskintype: Pdaliasskintype_t): pointer;
var
  i, j, k: integer;
  name: array[0..31] of char;
  s: integer;
  skin: PByteArray;
  texels: PByte;
  pinskingroup: Pdaliasskingroup_t;
  groupskins: integer;
  pinskinintervals: Pdaliasskininterval_t;
  texnum: integer;
begin
  skin := PByteArray(integer(pskintype) + SizeOf(daliasskintype_t));

  if (numskins < 1) or (numskins > MAX_SKINS) then
    Sys_Error('Mod_LoadAliasModel: Invalid # of skins: %d'#10, [numskins]);

  s := pheader.skinwidth * pheader.skinheight;

  for i := 0 to numskins - 1 do
  begin
    if aliasskintype_t(pskintype._type) = ALIAS_SKIN_SINGLE then // TODO Check
    begin
      Mod_FloodFillSkin(skin, pheader.skinwidth, pheader.skinheight);

      // save 8 bit texels for the player model to remap
      texels := Hunk_AllocName(s, loadname);
      pheader.texels[i] := integer(texels) - integer(pheader); // JVAL -> check this!
      memcpy(texels, pointer(integer(pskintype) + SizeOf(daliasskintype_t)), s);
      sprintf(name, '%s_%d', [loadmodel.name, i]);
      texnum := GL_LoadTexture(name, pheader.skinwidth, pheader.skinheight,
        pointer(integer(pskintype) + SizeOf(daliasskintype_t)), true, false);
      pheader.gl_texturenum[i][0] := texnum;
      pheader.gl_texturenum[i][1] := texnum;
      pheader.gl_texturenum[i][2] := texnum;
      pheader.gl_texturenum[i][3] := texnum;

      pskintype := Pdaliasskintype_t(integer(pskintype) + SizeOf(daliasskintype_t) + s);
    end
    else
    begin
      // animating skin group.  yuck.
      inc(pskintype);
      pinskingroup := Pdaliasskingroup_t(pskintype);
      groupskins := LittleLong(pinskingroup.numskins);
      pinskinintervals := Pdaliasskininterval_t(integer(pinskingroup) + SizeOf(daliasskingroup_t));

      pskintype := Pdaliasskintype_t(integer(pinskinintervals) + groupskins * SizeOf(daliasskininterval_t));

      for j := 0 to groupskins - 1 do
      begin
        Mod_FloodFillSkin(skin, pheader.skinwidth, pheader.skinheight);
        if j = 0 then
        begin
          texels := Hunk_AllocName(s, loadname);
          pheader.texels[i] := integer(texels) - integer(pheader); // JVAL -> check this
          memcpy(texels, pskintype, s);
        end;
        sprintf(name, '%s_%d_%d', [loadmodel.name, i, j]);
        pheader.gl_texturenum[i][j and 3] :=
          GL_LoadTexture(name, pheader.skinwidth, pheader.skinheight,
          pointer(pskintype), true, false);
        pskintype := Pdaliasskintype_t(integer(pskintype) + s);
      end;
      j := groupskins;
      k := j;
      while j < 4 do
        pheader.gl_texturenum[i][j and 3] := pheader.gl_texturenum[i][j - k];
    end;
  end;

  result := pointer(pskintype);
end;

//=========================================================================

(*
=================
Mod_LoadAliasModel
=================
*)

procedure Mod_LoadAliasModel(mdl: PBSPModelFile; buffer: pointer);
var
  i, j: integer;
  pinmodel: Pmdl_t;
  pinstverts: Pstvert_t;
  pverttmp: Pstvert_t;
  pintriangles, pintr: Pdtriangle_t;
  version, numframes: integer;
  size: integer;
  pframetype: Pdaliasframetype_t;
  pskintype: Pdaliasskintype_t;
  start, _end, total: integer;
  frametype: aliasframetype_t;
begin
  start := Hunk_LowMark;

  pinmodel := Pmdl_t(buffer);

  version := LittleLong(pinmodel.version);
  if version <> ALIAS_VERSION then
    Sys_Error('%s has wrong version number (%d should be %d)', [mdl.name, version, ALIAS_VERSION]);

//
// allocate space for a working header, plus all the data except the frames,
// skin and group info
//
  size := SizeOf(aliashdr_t) + (LittleLong(pinmodel.numframes) - 1) * SizeOf(pheader.frames[0]);
  pheader := Hunk_AllocName(size, loadname);

  mdl.flags := LittleLong(pinmodel.flags);

//
// endian-adjust and copy the data, starting with the alias model header
//
  pheader.boundingradius := LittleFloat(pinmodel.boundingradius);
  pheader.numskins := LittleLong(pinmodel.numskins);
  pheader.skinwidth := LittleLong(pinmodel.skinwidth);
  pheader.skinheight := LittleLong(pinmodel.skinheight);

  if pheader.skinheight > MAX_LBM_HEIGHT then
    Sys_Error('model %s has a skin taller than %d', [mdl.name, MAX_LBM_HEIGHT]);

  pheader.numverts := LittleLong(pinmodel.numverts);

  if pheader.numverts <= 0 then
    Sys_Error('model %s has no vertices', [mdl.name]);

  if pheader.numverts > MAXALIASVERTS then
    Sys_Error('model %s has too many vertices', [mdl.name]);

  pheader.numtris := LittleLong(pinmodel.numtris);

  if pheader.numtris <= 0 then
    Sys_Error('model %s has no triangles', [mdl.name]);

  pheader.numframes := LittleLong(pinmodel.numframes);
  numframes := pheader.numframes;
  if numframes < 1 then
    Sys_Error('Mod_LoadAliasModel: Invalid # of frames: %d'#10, [numframes]);

  pheader.size := LittleFloat(pinmodel.size) * ALIAS_BASE_SIZE_RATIO;
  mdl.synctype := synctype_t(LittleLong(Ord(pinmodel.synctype)));
  mdl.numframes := pheader.numframes;

  for i := 0 to 2 do
  begin
    pheader.scale[i] := LittleFloat(pinmodel.scale[i]);
    pheader.scale_origin[i] := LittleFloat(pinmodel.scale_origin[i]);
    pheader.eyeposition[i] := LittleFloat(pinmodel.eyeposition[i]);
  end;

//
// load the skins
//
  pskintype := Pdaliasskintype_t(@Pmdl_tArray(pinmodel)[1]);
  pskintype := Mod_LoadAllSkins(pheader.numskins, pskintype);

//
// load base s and t vertices
//
  pinstverts := Pstvert_t(pskintype);

  pverttmp := pinstverts;
  for i := 0 to pheader.numverts - 1 do
  begin
    stverts[i].onseam := LittleLong(pverttmp.onseam);
    stverts[i].s := LittleLong(pverttmp.s);
    stverts[i].t := LittleLong(pverttmp.t);
    inc(pverttmp);
  end;

//
// load triangle lists
//
  pintriangles := Pdtriangle_t(pverttmp);

  pintr := pintriangles;
  for i := 0 to pheader.numtris - 1 do
  begin
    triangles[i].facesfront := LittleLong(pintr.facesfront);

    for j := 0 to 2 do
    begin
      triangles[i].vertindex[j] :=
        LittleLong(pintr.vertindex[j]);
    end;
    inc(pintr);
  end;

//
// load the frames
//
  posenum := 0;
  pintr := pintriangles;
  inc(pintr, pheader.numtris);
  pframetype := Pdaliasframetype_t(pintr);

  for i := 0 to numframes - 1 do
  begin
    frametype := aliasframetype_t(LittleLong(Ord(pframetype._type)));

    inc(pframetype);
    if frametype = ALIAS_SINGLE then
    begin
      pframetype := Pdaliasframetype_t(Mod_LoadAliasFrame(pframetype, @pheader.frames[i]));
    end
    else
    begin
      pframetype := Pdaliasframetype_t(Mod_LoadAliasGroup(pframetype, @pheader.frames[i]));
    end;
  end;

  pheader.numposes := posenum;

  mdl._type := mod_alias;

// FIXME: do this right
  mdl.mins[0] := -16;
  mdl.mins[1] := -16;
  mdl.mins[2] := -16;
  mdl.maxs[0] := 16;
  mdl.maxs[1] := 16;
  mdl.maxs[2] := 16;

  //
  // build the draw lists
  //
  GL_MakeAliasModelDisplayLists(mdl, pheader);

//
// move the complete, relocatable alias model to the cache
//
  _end := Hunk_LowMark;
  total := _end - start;

  Cache_Alloc(@mdl.cache, total, loadname);
  if mdl.cache.data = nil then
    exit;
  memcpy(mdl.cache.data, pheader, total);

  Hunk_FreeToLowMark(start);
end;

//=============================================================================

(*
=================
Mod_LoadSpriteFrame
=================
*)

function Mod_LoadSpriteFrame(pin: pointer; var ppframe: Pmspriteframe_t;
  framenum: integer): pointer;
var
  pinframe: Pdspriteframe_t;
  pspriteframe: Pmspriteframe_t;
  width, height, size: integer;
  origin: array[0..1] of integer;
  name: array[0..63] of char;
begin
  pinframe := Pdspriteframe_t(pin);

  width := LittleLong(pinframe.width);
  height := LittleLong(pinframe.height);
  size := width * height;

  pspriteframe := Hunk_AllocName(SizeOf(mspriteframe_t), loadname);

  ZeroMemory(pspriteframe, SizeOf(mspriteframe_t));

  ppframe := pspriteframe;

  pspriteframe.width := width;
  pspriteframe.height := height;
  origin[0] := LittleLong(pinframe.origin[0]);
  origin[1] := LittleLong(pinframe.origin[1]);

  pspriteframe.up := origin[1];
  pspriteframe.down := origin[1] - height;
  pspriteframe.left := origin[0];
  pspriteframe.right := width + origin[0];

  sprintf(name, '%s_%d', [loadmodel.name, framenum]);
  pspriteframe.gl_texturenum :=
    GL_LoadTexture(name, width, height, pointer(integer(pinframe) + SizeOf(dspriteframe_t)), true, true);

  result := pointer(integer(pinframe) + SizeOf(dspriteframe_t) + size);
end;


(*
=================
Mod_LoadSpriteGroup
=================
*)

function Mod_LoadSpriteGroup(pin: pointer; var ppframe: Pmspriteframe_t;
  framenum: integer): pointer;
var
  pingroup: Pdspritegroup_t;
  tmp: Pdspritegroup_t;
  pspritegroup: Pmspritegroup_t;
  i, numframes: integer;
  pin_intervals: Pdspriteinterval_t;
  poutintervals: Psingle;
  ptemp: pointer;
begin
  pingroup := Pdspritegroup_t(pin);

  numframes := LittleLong(pingroup.numframes);

  pspritegroup := Hunk_AllocName(SizeOf(mspritegroup_t) +
    (numframes - 1) * SizeOf(pspritegroup.frames[0]), loadname);

  pspritegroup.numframes := numframes;

  ppframe := Pmspriteframe_t(pspritegroup);

  tmp := pingroup;
  inc(tmp);
  pin_intervals := Pdspriteinterval_t(tmp);

  poutintervals := Hunk_AllocName(numframes * SizeOf(single), loadname);

  pspritegroup.intervals := poutintervals;

  for i := 0 to numframes - 1 do
  begin
    poutintervals^ := LittleFloat(pin_intervals.interval);
    if poutintervals^ <= 0.0 then
      Sys_Error('Mod_LoadSpriteGroup: interval<=0');

    inc(poutintervals);
    inc(pin_intervals);
  end;

  ptemp := pointer(pin_intervals);

  for i := 0 to numframes - 1 do
  begin
    ptemp := Mod_LoadSpriteFrame(ptemp, pspritegroup.frames[i], framenum * 100 + i);
  end;

  result := ptemp;
end;


(*
=================
Mod_LoadSpriteModel
=================
*)

procedure Mod_LoadSpriteModel(mdl: PBSPModelFile; buffer: pointer);
var
  i: integer;
  version: integer;
  pin: Pdsprite_t;
  psprite: Pmsprite_t;
  numframes: integer;
  size: integer;
  pframetype: Pdspriteframetype_t;
  frametype: spriteframetype_t;
begin
  pin := Pdsprite_t(buffer);

  version := LittleLong(pin.version);
  if version <> SPRITE_VERSION then
    Sys_Error('%s has wrong version number (%d should be %d)',
      [mdl.name, version, SPRITE_VERSION]);

  numframes := LittleLong(pin.numframes);

  size := SizeOf(msprite_t) + (numframes - 1) * SizeOf(mspriteframedesc_t);

  psprite := Hunk_AllocName(size, loadname);

  mdl.cache.data := psprite;

  psprite._type := LittleLong(pin._type);
  psprite.maxwidth := LittleLong(pin.width);
  psprite.maxheight := LittleLong(pin.height);
  psprite.beamlength := LittleFloat(pin.beamlength);
  mdl.synctype := synctype_t(LittleLong(Ord(pin.synctype)));
  psprite.numframes := numframes;

  mdl.mins[0] := -psprite.maxwidth / 2;
  mdl.mins[1] := -psprite.maxwidth / 2;
  mdl.maxs[0] := psprite.maxwidth / 2;
  mdl.maxs[1] := psprite.maxwidth / 2; ;
  mdl.mins[2] := -psprite.maxheight / 2;
  mdl.maxs[2] := psprite.maxheight / 2;

//
// load the frames
//
  if numframes < 1 then
    Sys_Error('Mod_LoadSpriteModel: Invalid # of frames: %d'#10, [numframes]);

  mdl.numframes := numframes;

  pframetype := Pdspriteframetype_t(integer(pin) + SizeOf(dsprite_t)); // JVAL -> check this

  for i := 0 to numframes - 1 do
  begin
    frametype := spriteframetype_t(LittleLong(Ord(pframetype._type)));
    psprite.frames[i]._type := frametype;

    inc(pframetype);
    if frametype = SPR_SINGLE then
    begin
      pframetype := Pdspriteframetype_t(
        Mod_LoadSpriteFrame(pframetype, psprite.frames[i].frameptr, i));
    end
    else
    begin
      pframetype := Pdspriteframetype_t(
        Mod_LoadSpriteGroup(pframetype, psprite.frames[i].frameptr, i));
    end;
  end;

  mdl._type := mod_sprite;
end;

//=============================================================================

(*
================
Mod_Print
================
*)

procedure Mod_Print;
var
  i: integer;
  mdl: PBSPModelFile;
begin
  Con_Printf('Cached models:'#10);
  mdl := @mod_known[0];
  for i := 0 to mod_numknown - 1 do
  begin
    Con_Printf('%8p : %s'#10, [mdl.cache.data, mdl.name]);
    inc(mdl);
  end;
end;


end.

