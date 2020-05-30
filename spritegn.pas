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

unit spritegn;

interface



// **********************************************************
// * This file must be identical in the spritegen directory *
// * and in the Quake directory, because it's used to       *
// * pass data from one to the other via .spr files.        *
// **********************************************************

//-------------------------------------------------------
// This program generates .spr sprite package files.
// The format of the files is as follows:
//
// dsprite_t file header structure
// <repeat dsprite_t.numframes times>
//   <if spritegroup, repeat dspritegroup_t.numframes times>
//     dspriteframe_t frame header structure
//     sprite bitmap
//   <else (single sprite frame)>
//     dspriteframe_t frame header structure
//     sprite bitmap
// <endrepeat>
//-------------------------------------------------------

const
  SPRITE_VERSION = 1;

// TODO: shorten these?
type
  Pdsprite_t = ^dsprite_t;
  dsprite_t = record
    ident: integer;
    version: integer;
    _type: integer;
    boundingradius: Single;
    width: integer;
    height: integer;
    numframes: integer;
    beamlength: Single;
    synctype: cardinal; //synctype_t;
  end;

const
  SPR_VP_PARALLEL_UPRIGHT = 0;
  SPR_FACING_UPRIGHT = 1;
  SPR_VP_PARALLEL = 2;
  SPR_ORIENTED = 3;
  SPR_VP_PARALLEL_ORIENTED = 4;

type
  Pdspriteframe_t = ^dspriteframe_t;
  dspriteframe_t = record
    origin: array[0..1] of integer;
    width: integer;
    height: integer;
  end;

type
  Pdspritegroup_t = ^dspritegroup_t;
  dspritegroup_t = record
    numframes: integer;
  end;

  Pdspriteinterval_t = ^dspriteinterval_t;
  dspriteinterval_t = record
    interval: Single;
  end;

  spriteframetype_t = (SPR_SINGLE, SPR_GROUP);

  Pdspriteframetype_t = ^dspriteframetype_t;
  dspriteframetype_t = record
    _type: cardinal; { spriteframetype_t }
  end;

const
  IDSPRITEHEADER = (Ord('P') shl 24) + (Ord('S') shl 16) + (Ord('D') shl 8) + Ord('I');

implementation

end.

