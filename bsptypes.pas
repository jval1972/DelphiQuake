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

unit bsptypes;

interface

uses
  q_vector,
  bspconst;

type
  TBSPLump = record
    Offset: Integer;
    Length: Integer;
  end;
  PBSPLump = ^TBSPLump;

  TBSPHeader = record
    Version: integer;
    Lumps: array[0..HEADER_LUMPS - 1] of TBSPLump;
  end;
  PBSPHeader = ^TBSPHeader;

  TBSPModel = record
    mins: TVector3f;
    maxs: TVector3f;
    origin: TVector3f;
    headnode: array[0..MAX_MAP_HULLS - 1] of integer;
    visleafs: Integer; // not including the solid leaf 0
    firstface: Integer;
    numfaces: Integer;
  end;
  PBSPModel = ^TBSPModel;
  TBSPModelArray = array[0..$FFFF] of TBSPModel;
  PBSPModelArray = ^TBSPModelArray;

  dmiptexlump_t = packed record
    nummiptex: integer;
    dataofs: array[0..MIPLEVELS - 1] of integer; // [nummiptex]
  end;
  Pdmiptexlump_t = ^dmiptexlump_t;

  miptex_t = packed record
    name: array[0..15] of char;
    width, height: longword;
    offsets: array[0..MIPLEVELS - 1] of longword; // four mip maps stored
  end;
  Pmiptex_t = ^miptex_t;

  TBSPVertex = record
    Position: TVector3f;
  end;
  PBSPVertex = ^TBSPVertex;

  TBSPPlane = record
    normal: TVector3f;
    dist: Single;
    PlaneType: Integer; // PLANE_X - PLANE_ANYZ ?remove? trivial to regenerate
  end;
  PBSPPlane = ^TBSPPlane;

// !!! if this is changed, it must be changed in asm_i386.h too !!!
  TBSPNode = record
    PlaneIndex: integer;
    children: array[0..1] of smallint; // negative numbers are -(leafs+1), not nodes
    mins: array[0..2] of smallint; // for sphere culling
    maxs: array[0..2] of smallint;
    firstface: word;
    numfaces: word; // counting both sides
  end;
  PBSPNode = ^TBSPNode;

  TBSPClipNode = record
    PlaneIndex: integer;
    children: array[0..1] of smallint; // negative numbers are contents
  end;
  PBSPClipNode = ^TBSPClipNode;
  TBSPClipNodeArray = array[0..$FFFF] of TBSPClipNode;
  PBSPClipNodeArray = ^TBSPClipNodeArray;

  Ptexinfo_t = ^texinfo_t;
  texinfo_t = record
    vecs: array[0..1] of TVector4f; // [s/t][xyz offset]
    miptex: integer;
    flags: integer;
  end;

// note that edge 0 is never used, because negative edge nums are used for
// counterclockwise use of the edge in a face
  TBSPEdge = record
    v: array[0..1] of word; // vertex numbers
  end;
  PBSPEdge = ^TBSPEdge;

  TBSPFace = record
    PlaneIndex: smallint;
    side: smallint;

    firstedge: integer; // we must support > 64k edges
    numedges: smallint;
    texinfo: smallint;

// lighting info
    styles: array[0..MAXLIGHTMAPS - 1] of byte;
    light_offset: integer; // start of [numstyles*surfsize] samples
  end;
  PBSPFace = ^TBSPFace;
  TBSPFaceArray = array[0..$FFFF] of TBSPFace;
  PBSPFaceArray = ^TBSPFaceArray;

// leaf 0 is the generic CONTENTS_SOLID leaf, used for all solid areas
// all other leafs need visibility info
  TBSPLeaf = record
    contents: integer;
    visofs: integer; // -1 = no visibility info

    mins: array[0..2] of smallint; // for frustum culling
    maxs: array[0..2] of smallint;

    firstmarksurface: word;
    nummarksurfaces: word;

    ambient_level: array[0..NUM_AMBIENTS - 1] of byte;
  end;
  PBSPLeaf = ^TBSPLeaf;
  TBSPLeafArray = array[0..$FFFF] of TBSPLeaf;
  PBSPLeafArray = ^TBSPLeafArray;

//============================================================================


implementation

end.

