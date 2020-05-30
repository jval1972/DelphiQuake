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

unit gl_model_h;

interface

uses
  q_delphi,
  q_vector,
  bspconst,
  bsptypes,
  spritegn,
  modelgen,
  gl_planes,
  quakedef,
  zone;

// entity effects

const
  EF_BRIGHTFIELD = 1;
  EF_MUZZLEFLASH = 2;
  EF_BRIGHTLIGHT = 4;
  EF_DIMLIGHT = 8;


(*
==============================================================================

BRUSH MODELS

==============================================================================
*)


//
// in memory representation
//
// !!! if this is changed, it must be changed in asm_draw.h too !!!
type
  mvertex_t = record
    position: TVector3f;
  end;
  Pmvertex_t = ^mvertex_t;
  mvertex_tArray = array[0..$FFFF] of mvertex_t;
  Pmvertex_tArray = ^mvertex_tArray;

const
  SIDE_FRONT = 0;
  SIDE_BACK = 1;
  SIDE_ON = 2;

const
  SURF_PLANEBACK = 2;
  SURF_DRAWSKY = 4;
  SURF_DRAWSPRITE = 8;
  SURF_DRAWTURB = $10;
  SURF_DRAWTILED = $20;
  SURF_DRAWBACKGROUND = $40;
  SURF_UNDERWATER = $80;

type
// !!! if this is changed, it must be changed in asm_i386.h too !!!
  hull_t = record
    clipnodes: PBSPClipNode;
    planes: Pmplane_t;
    firstclipnode: integer;
    lastclipnode: integer;
    clip_mins: TVector3f;
    clip_maxs: TVector3f;
  end;
  Phull_t = ^hull_t;

(*
==============================================================================

SPRITE MODELS

==============================================================================
*)


// FIXME: shorten these?
  mspriteframe_t = record
    width: integer;
    height: integer;
    up, down, left, right: single;
    gl_texturenum: integer;
  end;
  Pmspriteframe_t = ^mspriteframe_t;

  mspritegroup_t = record
    numframes: integer;
    intervals: Psingle;
    frames: array[0..0] of Pmspriteframe_t;
  end;
  Pmspritegroup_t = ^mspritegroup_t;

  mspriteframedesc_t = record
    _type: spriteframetype_t;
    frameptr: Pmspriteframe_t;
  end;
  Pmspriteframedesc_t = ^mspriteframedesc_t;

  msprite_t = record
    _type: integer;
    maxwidth: integer;
    maxheight: integer;
    numframes: integer;
    beamlength: single; // remove?
    cachespot: pointer; // remove?
    frames: array[0..0] of mspriteframedesc_t;
  end;
  Pmsprite_t = ^msprite_t;


(*
==============================================================================

ALIAS MODELS

Alias models are position independent, so the cache manager can move them.
==============================================================================
*)

type
  maliasframedesc_t = record
    firstpose: integer;
    numposes: integer;
    interval: single;
    bboxmin: trivertx_t;
    bboxmax: trivertx_t;
    frame: integer;
    name: array[0..15] of char;
  end;
  Pmaliasframedesc_t = ^maliasframedesc_t;

  maliasgroupframedesc_t = record
    bboxmin: trivertx_t;
    bboxmax: trivertx_t;
    frame: integer;
  end;
  Pmaliasgroupframedesc_t = ^maliasgroupframedesc_t;

  maliasgroup_t = record
    numframes: integer;
    intervals: integer;
    frames: array[0..0] of maliasgroupframedesc_t;
  end;
  Pmaliasgroup_t = ^maliasgroup_t;

// !!! if this is changed, it must be changed in asm_draw.h too !!!
  Pmtriangle_t = ^mtriangle_t;
  mtriangle_t = record
    facesfront: integer;
    vertindex: array[0..2] of integer;
  end;

const
  MAX_SKINS = 32;

type
  aliashdr_t = record
    ident: integer;
    version: integer;
    scale: TVector3f;
    scale_origin: TVector3f;
    boundingradius: single;
    eyeposition: TVector3f;
    numskins: integer;
    skinwidth: integer;
    skinheight: integer;
    numverts: integer;
    numtris: integer;
    numframes: integer;
    synctype: synctype_t;
    flags: integer;
    size: single;

    numposes: integer;
    poseverts: integer;
    posedata: integer; // numposes*poseverts trivert_t
    commands: integer; // gl command list with embedded s/t
    gl_texturenum: array[0..MAX_SKINS - 1, 0..3] of integer;
    texels: array[0..MAX_SKINS - 1] of integer; // only for player skins
    frames: array[0..0] of maliasframedesc_t; // variable sized
  end;
  Paliashdr_t = ^aliashdr_t;

const
  MAXALIASVERTS = 1024;
  MAXALIASFRAMES = 256;
  MAXALIASTRIS = 2048;

//===================================================================

//
// Whole model
//

type
  modtype_t = (mod_brush, mod_sprite, mod_alias);

const
  EF_ROCKET = 1; // leave a trail
  EF_GRENADE = 2; // leave a trail
  EF_GIB = 4; // leave a trail
  EF_ROTATE = 8; // rotate (bonus items)
  EF_TRACER = 16; // green split trail
  EF_ZOMGIB = 32; // small blood trail
  EF_TRACER2 = 64; // orange split trail + rotate
  EF_TRACER3 = 128; // purple trail

// !!! if this is changed, it must be changed in asm_draw.h too !!!
type
  Pmleaf_t = ^mleaf_t;
  PPefrag_t = ^Pefrag_t;
  Pefrag_t = ^efrag_t;
  Pentity_t = ^entity_t;
  PBSPModelFile = ^TBSPModelFile;


  mleaf_t = record
// common with node
    contents: integer; // wil be a negative contents number
    visframe: integer; // node needs to be traversed if current

    minmaxs: array[0..5] of single; // for bounding box culling

    parent: Pmnode_t;

// leaf specific
    compressed_vis: PByteArray;
    efrags: Pefrag_t;

    firstmarksurface: Pmsurface_tPArray;
    nummarksurfaces: integer;

    key: integer; // BSP sequence number for leaf's contents
    ambient_sound_level: array[0..NUM_AMBIENTS - 1] of byte;
  end;
  mleaf_tArray = array[0..$FFFF] of mleaf_t;
  Pmleaf_tArray = ^mleaf_tArray;

  efrag_t = record
    leaf: Pmleaf_t;
    leafnext: Pefrag_t;
    entity: Pentity_t;
    entnext: Pefrag_t;
  end;
  efrag_tArray = array[0..$FFFF] of efrag_t;
  Pefrag_tArray = ^efrag_tArray;


  entity_t = record
    forcelink: qboolean; // model changed
    update_type: integer;
    baseline: entity_state_t; // to fill in defaults in updates
    msgtime: double; // time of last update
    msg_origins: array[0..1] of TVector3f; // last two updates (0 is newest)
    origin: TVector3f;
    msg_angles: array[0..1] of TVector3f; // last two updates (0 is newest)
    angles: TVector3f;
    model: PBSPModelFile; // NULL = no model
    efrag: Pefrag_t; // linked list of efrags
    frame: integer;
    syncbase: single; // for client-side animations
    colormap: PByteArray;
    effects: integer; // light, particals, etc
    skinnum: integer; // for Alias models
    visframe: integer; // last frame this entity was
                                                  //  found in an active leaf
    dlightframe: integer; // dynamic lighting
    dlightbits: integer;

// FIXME: could turn these into a union
    trivial_accept: integer;
    topnode: Pmnode_t; // for bmodels, first world node
                                                  //  that splits bmodel, or NULL if
                                                  //  not split
  end;


  TBSPModelFile = record
    name: array[0..MAX_QPATH - 1] of char;
    needload: qboolean; // bmodels and sprites don't cache normally
    _type: modtype_t;
    numframes: integer;
    synctype: synctype_t;
    flags: integer;

//
// volume occupied by the model graphics
//
    mins, maxs: TVector3f;
    radius: single;

//
// solid volume for clipping
//
    clipbox: qboolean;
    clipmins, clipmaxs: TVector3f;

//
// brush model
//
    firstmodelsurface, nummodelsurfaces: integer;

    numsubmodels: integer;
    submodels: PBSPModelArray;

    numplanes: integer;
    planes: Pmplane_tArray;

    numleafs: integer; // number of visible leafs, not counting 0
    leafs: Pmleaf_tArray;

    numvertexes: integer;
    vertexes: Pmvertex_tArray;

    numedges: integer;
    edges: Pmedge_tArray;

    numnodes: integer;
    nodes: Pmnode_t;

    numtexinfo: integer;
    texinfo: Pmtexinfo_tArray;

    numsurfaces: integer;
    surfaces: Pmsurface_tArray;

    numsurfedges: integer;
    surfedges: PIntegerArray;

    numclipnodes: integer;
    clipnodes: PBSPClipNode;

    nummarksurfaces: integer;
    marksurfaces: Pmsurface_tPArray;

    hulls: array[0..MAX_MAP_HULLS - 1] of hull_t;

    numtextures: integer;
    textures: Ptexture_tPArray;

    visdata: PByteArray;
    lightdata: PByteArray;
    entities: PChar;

//
// additional model data
//
    cache: cache_user_t; // only access through Mod_Extradata
  end;

//============================================================================

implementation

end.

