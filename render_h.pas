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

unit render_h;

// refresh.h -- public interface to refresh functions

interface

uses
  q_vector,
  vid_h;

const
  MAXCLIPPLANES = 11;

  TOP_RANGE = 16; // soldier uniform colors
  BOTTOM_RANGE = 96;

const
  WATERDELTA = 8; // JVAL added


// !!! if this is changed, it must be changed in asm_draw.h too !!!
type
  Prefdef_t = ^refdef_t;
  refdef_t = record
    vrect: vrect_t; // subwindow in video for refresh
                                        // FIXME: not need vrect next field here?
    aliasvrect: vrect_t; // scaled Alias version
    vrectright,
      vrectbottom: integer; // right & bottom screen coords
    aliasvrectright,
      aliasvrectbottom: integer; // scaled Alias versions
    vrectrightedge: single; // rightmost right edge we care about,
                                        //  for use in edge list
    fvrectx, fvrecty: single; // for floating-point compares
    fvrectx_adj, fvrecty_adj: single; // left and top edges, for clamping
    vrect_x_adj_shift20: integer; // (vrect.x + 0.5 - epsilon) << 20
    vrectright_adj_shift20: integer; // (vrectright + 0.5 - epsilon) << 20
    fvrectright_adj,
      fvrectbottom_adj: single;
                                        // right and bottom edges, for clamping
    fvrectright: single; // rightmost edge, for Alias clamping
    fvrectbottom: single; // bottommost edge, for Alias clamping
    horizontalFieldOfView: single; // at Z = 1.0, this many X is visible
                                        // 2.0 = 90 degrees
    xOrigin: single; // should probably allways be 0.5
    yOrigin: single; // between be around 0.3 to 0.5

    vieworg: TVector3f;
    viewangles: TVector3f;

    fov_x, fov_y: single;

    ambientlight: integer;
  end;

implementation

end.
