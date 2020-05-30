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

unit modelgen;

interface

uses
  q_vector;

const

  ALIAS_VERSION = 6;

  ALIAS_ONSEAM = $0020;

type
  aliasframetype_t = (ALIAS_SINGLE, ALIAS_GROUP);
  aliasskintype_t = (ALIAS_SKIN_SINGLE, ALIAS_SKIN_GROUP);

type
  mdl_t = record
    ident: integer;
    version: integer;
    scale: TVector3f;
    scale_origin: TVector3f;
    boundingradius: Single;
    eyeposition: TVector3f;
    numskins: integer;
    skinwidth: integer;
    skinheight: integer;
    numverts: integer;
    numtris: integer;
    numframes: integer;
    synctype: cardinal; //synctype_t;
    flags: integer;
    size: Single;
  end;
  Pmdl_t = ^mdl_t;
  mdl_tArray = array[0..$FFFF] of mdl_t;
  Pmdl_tArray = ^mdl_tArray;


// TODO: could be shorts

type
  stvert_t = record
    onseam: integer;
    s: integer;
    t: integer;
  end;
  Pstvert_t = ^stvert_t;

type
  dtriangle_t = record
    facesfront: integer;
    vertindex: array[0..2] of integer;
  end;
  Pdtriangle_t = ^dtriangle_t;
  dtriangle_tArray = array[0..$FFFF] of dtriangle_t;
  Pdtriangle_tArray = ^dtriangle_tArray;

// This mirrors trivert_t in trilib.h, is present so Quake knows how to
// load this data

type
  trivertx_t = packed record
    v: array[0..2] of byte;
    lightnormalindex: byte;
  end;
  Ptrivertx_t = ^trivertx_t;
  trivertx_tArray = array[0..$FFFF] of trivertx_t;
  Ptrivertx_tArray = ^trivertx_tArray;

type
  daliasframe_t = record
    bboxmin: trivertx_t; // lightnormal isn't used
    bboxmax: trivertx_t; // lightnormal isn't used
    name: array[0..15] of char; // frame name from grabbing
  end;
  Pdaliasframe_t = ^daliasframe_t;

type
  daliasgroup_t = record
    numframes: integer;
    bboxmin: trivertx_t; // lightnormal isn't used
    bboxmax: trivertx_t; // lightnormal isn't used
  end;
  Pdaliasgroup_t = ^daliasgroup_t;

type
  daliasskingroup_t = record
    numskins: integer;
  end;
  Pdaliasskingroup_t = ^daliasskingroup_t;

type
  daliasinterval_t = record
    interval: Single;
  end;
  Pdaliasinterval_t = ^daliasinterval_t;

type
  daliasskininterval_t = record
    interval: Single;
  end;
  Pdaliasskininterval_t = ^daliasskininterval_t;

type
  daliasframetype_t = record
    _type: cardinal; //aliasframetype_t;
  end;
  Pdaliasframetype_t = ^daliasframetype_t;

type
  daliasskintype_t = record
    _type: cardinal; //aliasskintype_t;
  end;
  Pdaliasskintype_t = ^daliasskintype_t;

const
  IDPOLYHEADER = (Ord('O') shl 24) + (Ord('P') shl 16) + (Ord('D') shl 8) + Ord('I');
  // little-endian "IDPO"

implementation

end.

