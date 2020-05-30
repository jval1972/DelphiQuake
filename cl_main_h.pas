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

unit cl_main_h;

interface

uses
  client,
  gl_model_h,
  quakedef,
  cvar;

var
// FIXME: put these on hunk?
  cl_efrags: array[0..MAX_EFRAGS - 1] of efrag_t;
  cl_entities: array[0..MAX_EDICTS - 1] of entity_t;
  cl_static_entities: array[0..MAX_STATIC_ENTITIES - 1] of entity_t;
  cl_lightstyle: array[0..MAX_LIGHTSTYLES - 1] of lightstyle_t;


var
  cls: client_static_t;
  cl: client_state_t;
  cl_dlights: array[0..MAX_DLIGHTS - 1] of dlight_t;

// we need to declare some mouse variables here, because the menu system
// references them even when on a unix system.

// these two are not intended to be set directly

var
  cl_name: cvar_t = (name: '_cl_name'; text: 'player'; archive: true);
  cl_color: cvar_t = (name: '_cl_color'; text: '0'; archive: true);

  cl_shownet: cvar_t = (name: 'cl_shownet'; text: '0'); // can be 0, 1, or 2
  cl_nolerp: cvar_t = (name: 'cl_nolerp'; text: '0');

  lookspring: cvar_t = (name: 'lookspring'; text: '0'; archive: true);
  lookstrafe: cvar_t = (name: 'lookstrafe'; text: '0'; archive: true);
  sensitivity: cvar_t = (name: 'sensitivity'; text: '3'; archive: true);

  m_pitch: cvar_t = (name: 'm_pitch'; text: '0.022'; archive: true);
  m_yaw: cvar_t = (name: 'm_yaw'; text: '0.022'; archive: true);
  m_forward: cvar_t = (name: 'm_forward'; text: '1'; archive: true);
  m_side: cvar_t = (name: 'm_side'; text: '0.8'; archive: true);


  cl_numvisedicts: integer;
  cl_visedicts: array[0..MAX_VISEDICTS - 1] of Pentity_t;


implementation

end.

 