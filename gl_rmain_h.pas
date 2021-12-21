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

unit gl_rmain_h;

interface

uses
  q_vector,
  gl_model_h,
  gl_planes;

var
//
// view origin
//
  vup: TVector3f;
  vpn: TVector3f;
  vright: TVector3f;
  r_origin: TVector3f;

var
  r_framecount: integer; // used for dlight push checking
  d_lightstylevalue: array[0..255] of integer; // 8.8 fraction of base light value
  currententity: Pentity_t;
  r_notexture_mip: Ptexture_t;

  r_visframecount: integer; // bumped when going to a new PVS


implementation

end.


