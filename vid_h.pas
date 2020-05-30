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

unit vid_h;

// vid.h -- video driver defs

interface

uses
  q_delphi;
  
const
  VID_CBITS = 6;
  VID_GRADES = 1 shl VID_CBITS;

{
// a pixel can be one, two, or four bytes
type
  pixel_t = byte;
  Ppixel_t = ^pixel_t;
  pixel_tArray = array[0..$FFFF] of pixel_t;
  Ppixel_tArray = ^pixel_tArray;
}
type
  Pvrect_t = ^vrect_t;
  vrect_t = record
    x, y, width, height: integer;
    pnext: Pvrect_t;
  end;

type
  Pviddef_t = ^viddef_t;
  viddef_t = record
    buffer: PByteArray; // invisible buffer
    colormap: PByteArray; // 256 * VID_GRADES size
    colormap16: Punsigned_shortArray; // 256 * VID_GRADES size
    fullbright: integer; // index of first fullbright color
    rowbytes: unsigned; // may be > width if displayed in a window
    width: integer; //unsigned;          // JVAL mayby integer ?
    height: integer; //unsigned;
    aspect: single; // width / height -- < 0 is taller than wide
    numpages: integer;
    recalc_refdef: qboolean; // if true, recalc vid-based stuff
    conbuffer: PByteArray;
    conrowbytes: integer;
    conwidth: integer; //unsigned;
    conheight: integer; // unsigned;
    maxwarpwidth: integer;
    maxwarpheight: integer;
    direct: PByteArray; // direct drawing to framebuffer, if not
                              //  NULL
  end;
{
  Pviddef_t = ^viddef_t;
  viddef_t = record
    buffer: Ppixel_tArray;    // invisible buffer
    colormap: Ppixel_tArray;  // 256 * VID_GRADES size
    colormap16: Punsigned_shortArray;   // 256 * VID_GRADES size
    fullbright: integer;      // index of first fullbright color
    rowbytes: unsigned;       // may be > width if displayed in a window
    width: unsigned;          // JVAL mayby integer ?
    height: unsigned;
    aspect: float;            // width / height -- < 0 is taller than wide
    numpages: integer;
    recalc_refdef: integer;   // if true, recalc vid-based stuff
    conbuffer: Ppixel_tArray;
    conrowbytes: integer;
    conwidth: unsigned;
    conheight: unsigned;
    maxwarpwidth: integer;
    maxwarpheight: integer;
    direct: Ppixel_tArray;    // direct drawing to framebuffer, if not
                              //  NULL
  end;
}

implementation

end.

