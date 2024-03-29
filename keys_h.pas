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

unit keys_h;

interface

const
//
// these are the key numbers that should be passed to Key_ProcessEvent
//
  K_TAB = 9;
  K_ENTER = 13;
  K_ESCAPE = 27;
  K_SPACE = 32;

// normal keys should be passed as lowercased ascii

  K_BACKSPACE = 127;
  K_UPARROW = 128;
  K_DOWNARROW = 129;
  K_LEFTARROW = 130;
  K_RIGHTARROW = 131;

  K_ALT = 132;
  K_CTRL = 133;
  K_SHIFT = 134;
  K_F1 = 135;
  K_F2 = 136;
  K_F3 = 137;
  K_F4 = 138;
  K_F5 = 139;
  K_F6 = 140;
  K_F7 = 141;
  K_F8 = 142;
  K_F9 = 143;
  K_F10 = 144;
  K_F11 = 145;
  K_F12 = 146;
  K_INS = 147;
  K_DEL = 148;
  K_PGDN = 149;
  K_PGUP = 150;
  K_HOME = 151;
  K_END = 152;

  K_PAUSE = 255;

//
// mouse buttons generate virtual keys
//
  K_MOUSE1 = 200;
  K_MOUSE2 = 201;
  K_MOUSE3 = 202;

//
// joystick buttons
//
  K_JOY1 = 203;
  K_JOY2 = 204;
  K_JOY3 = 205;
  K_JOY4 = 206;

//
// aux keys are for multi-buttoned joysticks to generate so they can use
// the normal binding process
//
  K_AUX1 = 207;
  K_AUX2 = 208;
  K_AUX3 = 209;
  K_AUX4 = 210;
  K_AUX5 = 211;
  K_AUX6 = 212;
  K_AUX7 = 213;
  K_AUX8 = 214;
  K_AUX9 = 215;
  K_AUX10 = 216;
  K_AUX11 = 217;
  K_AUX12 = 218;
  K_AUX13 = 219;
  K_AUX14 = 220;
  K_AUX15 = 221;
  K_AUX16 = 222;
  K_AUX17 = 223;
  K_AUX18 = 224;
  K_AUX19 = 225;
  K_AUX20 = 226;
  K_AUX21 = 227;
  K_AUX22 = 228;
  K_AUX23 = 229;
  K_AUX24 = 230;
  K_AUX25 = 231;
  K_AUX26 = 232;
  K_AUX27 = 233;
  K_AUX28 = 234;
  K_AUX29 = 235;
  K_AUX30 = 236;
  K_AUX31 = 237;
  K_AUX32 = 238;

// JACK: Intellimouse(c) Mouse Wheel Support

  K_MWHEELUP = 239;
  K_MWHEELDOWN = 240;


implementation

end.


