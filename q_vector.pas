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

unit q_vector;

interface

type
  TVector2f = array[0..1] of single;
  TVector3f = array[0..2] of single;
  TVector3i = array[0..2] of longint;
  TVector4f = array[0..3] of single;
  PVector4f = ^TVector4f;
  PVector3f = ^TVector3f;

  Pvec_t = ^Single;

  mat3_t = array[0..2, 0..2] of single;
  Pmat3_t = ^mat3_t;

  vec5_t = array[0..4] of single;
  Pvec5_t = ^vec5_t;

var
  vec3_origin: TVector3f = (0.0, 0.0, 0.0);

implementation

end.

