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

unit host_h;

interface

uses
  q_delphi,
  quakedef,
  cvar,
  server_h;

var
  realtime: double; // without any filtering or bounding

var
  host_parms: quakeparms_t;

  host_initialized: qboolean; // true if into command execution

  host_frametime: double;
  host_time: double;
  oldrealtime: double; // last frame run
  host_framecount: integer;

  host_hunklevel: integer;

  minimum_memory: unsigned; // JVAL was integer;

  host_client: Pclient_t; // current client

  host_basepal: PByteArray;
  host_colormap: PByteArray;

var
  host_framerate: cvar_t = (name: 'host_framerate'; text: '0'); // set for slow motion
  host_speeds: cvar_t = (name: 'host_speeds'; text: '0'); // set for running times

  sys_ticrate: cvar_t = (name: 'sys_ticrate'; text: '0.05');
  serverprofile: cvar_t = (name: 'serverprofile'; text: '0');

  fraglimit: cvar_t = (name: 'fraglimit'; text: '0'; archive: false; server: true);
  timelimit: cvar_t = (name: 'timelimit'; text: '0'; archive: false; server: true);
  teamplay: cvar_t = (name: 'teamplay'; text: '0'; archive: false; server: true);

  samelevel: cvar_t = (name: 'samelevel'; text: '0');
  noexit: cvar_t = (name: 'noexit'; text: '0'; archive: false; server: true);

  developer: cvar_t = (name: 'developer'; text: '0');
  
  skill: cvar_t = (name: 'skill'; text: '1'); // 0 - 3
  deathmatch: cvar_t = (name: 'deathmatch'; text: '0'); // 0, 1, or 2
  coop: cvar_t = (name: 'coop'; text: '0'); // 0 or 1

  pausable: cvar_t = (name: 'pausable'; text: '1');

  temp1: cvar_t = (name: 'temp1'; text: '0');

implementation

end.

