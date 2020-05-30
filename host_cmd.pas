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

unit host_cmd;

interface

uses
  q_delphi;

procedure Host_InitCommands;
procedure Host_Quit_f;

var
  noclip_anglehack: qboolean;
  current_skill: integer;


implementation

uses
  keys,
  cl_main,
  client,
  menu,
  cl_main_h,
  host,
  sys_win,
  server_h,
  cmd,
  sv_main,
  console,
  cvar,
  quakedef,
  net_main,
  pr_edict,
  host_h,
  sv_user,
  gl_screen,
  cl_demo,
  common,
  progs_h,
  zone,
  world,
  protocol,
  pr_exec,
  gl_model_h,
  gl_model;

(*
==================
Host_Quit_f
==================
*)

procedure Host_Quit_f;
begin
  if (key_dest <> key_console) and (cls.state <> ca_dedicated) then
  begin
    M_Menu_Quit_f;
    exit;
  end;
  CL_Disconnect;
  Host_ShutdownServer(false);

  Sys_Quit;
end;


(*
==================
Host_Status_f
==================
*)
type
  print_t = procedure(p: PChar; const A: array of const);

procedure Host_Status_f;
var
  client: Pclient_t;
  seconds: integer;
  minutes: integer;
  hours: integer;
  j: integer;
  print: print_t;
begin
  if cmd_source = src_command then
  begin
    if not sv.active then
    begin
      Cmd_ForwardToServer;
      exit;
    end;
    print := Con_Printf;
  end
  else
    print := SV_ClientPrintf;

  print('host:    %s'#10, [Cvar_VariableString('hostname')]);
  print('version: %4.2f'#10, [VERSION]);
  if tcpipAvailable then
    print('tcp/ip:  %s'#10, [my_tcpip_address]);
  if ipxAvailable then
    print('ipx:     %s'#10, [my_ipx_address]);
  print('map:     %s'#10, [sv.name]);
  print('players: %d active (%d max)'#10#10, [net_activeconnections, svs.maxclients]);
  client := @svs.clients[0]; // JVAL check this
  for j := 0 to svs.maxclients - 1 do
  begin
    if client.active then
    begin
      seconds := intval(net_time - client.netconnection.connecttime);
      minutes := seconds div 60;
      if minutes <> 0 then
      begin
        seconds := seconds - (minutes * 60);
        hours := minutes div 60;
        if hours <> 0 then
          minutes := minutes - (hours * 60);
      end
      else
        hours := 0;
      print('#%-2u %-16.16s  %3d  %2d:%02d:%02d'#10, // JVAL SOS
        [j + 1, client.name, intval(client.edict.v.frags), hours, minutes, seconds]);
      print('   %s'#10, [client.netconnection.address]);
    end;
    inc(client);
  end;
end;


(*
==================
Host_God_f

Sets client to godmode
==================
*)

procedure Host_God_f;
begin
  if cmd_source = src_command then
  begin
    Cmd_ForwardToServer;
    exit;
  end;

  if (pr_global_struct.deathmatch <> 0) and not host_client.privileged then
    exit;

  sv_player.v.flags := intval(sv_player.v.flags) xor FL_GODMODE; // JVAL check xor
  if intval(sv_player.v.flags) and FL_GODMODE = 0 then
    SV_ClientPrintf('godmode OFF'#10)
  else
    SV_ClientPrintf('godmode ON'#10);
end;

procedure Host_Notarget_f;
begin
  if cmd_source = src_command then
  begin
    Cmd_ForwardToServer;
    exit;
  end;

  if (pr_global_struct.deathmatch <> 0) and not host_client.privileged then
    exit;

  sv_player.v.flags := intval(sv_player.v.flags) xor FL_NOTARGET; // JVAL check xor
  if (intval(sv_player.v.flags) and FL_NOTARGET) = 0 then
    SV_ClientPrintf('notarget OFF'#10)
  else
    SV_ClientPrintf('notarget ON'#10);
end;

procedure Host_Noclip_f;
begin
  if cmd_source = src_command then
  begin
    Cmd_ForwardToServer;
    exit;
  end;

  if (pr_global_struct.deathmatch <> 0) and not host_client.privileged then
    exit;

  if sv_player.v.movetype <> MOVETYPE_NOCLIP then
  begin
    noclip_anglehack := true;
    sv_player.v.movetype := MOVETYPE_NOCLIP;
    SV_ClientPrintf('noclip ON'#10);
  end
  else
  begin
    noclip_anglehack := false;
    sv_player.v.movetype := MOVETYPE_WALK;
    SV_ClientPrintf('noclip OFF'#10);
  end;
end;

(*
==================
Host_Fly_f

Sets client to flymode
==================
*)

procedure Host_Fly_f;
begin
  if cmd_source = src_command then
  begin
    Cmd_ForwardToServer;
    exit;
  end;

  if (pr_global_struct.deathmatch <> 0) and not (host_client.privileged) then
    exit;

  if sv_player.v.movetype <> MOVETYPE_FLY then
  begin
    sv_player.v.movetype := MOVETYPE_FLY;
    SV_ClientPrintf('flymode ON'#10);
  end
  else
  begin
    sv_player.v.movetype := MOVETYPE_WALK;
    SV_ClientPrintf('flymode OFF'#10);
  end;
end;


(*
==================
Host_Ping_f

==================
*)

procedure Host_Ping_f;
var
  i, j: integer;
  total: single;
  client: Pclient_t;
begin
  if cmd_source = src_command then
  begin
    Cmd_ForwardToServer;
    exit;
  end;

  SV_ClientPrintf('Client ping times:'#10);
  client := @svs.clients[0]; // JVAL check this
  for i := 0 to svs.maxclients - 1 do
  begin
    if client.active then
    begin
      total := 0.0;
      for j := 0 to NUM_PING_TIMES - 1 do
        total := total + client.ping_times[j];
      total := total / NUM_PING_TIMES;
      SV_ClientPrintf('%4d %s'#10, [int(total * 1000), client.name]);
    end;
    inc(client);
  end;
end;

(*
===============================================================================

SERVER TRANSITIONS

===============================================================================
*)


(*
======================
Host_Map_f

handle a
map <servername>
command from the console.  Active clients are kicked off.
======================
*)

procedure Host_Map_f;
var
  i: integer;
  name: array[0..MAX_QPATH - 1] of char;
begin
  if cmd_source <> src_command then
    exit;

  cls.demonum := -1; // stop demo loop in case this fails

  CL_Disconnect;
  Host_ShutdownServer(false);

  key_dest := key_game; // remove console or menu
  SCR_BeginLoadingPlaque;

  cls.mapstring[0] := #0;
  for i := 0 to Cmd_Argc_f - 1 do
  begin
    strcat(cls.mapstring, Cmd_Argv_f(i));
    strcat(cls.mapstring, ' ');
  end;
  strcat(cls.mapstring, #10);

  svs.serverflags := 0; // haven't completed an episode yet
  strcpy(name, Cmd_Argv_f(1));
  SV_SpawnServer(name);
  if not sv.active then
    exit;

  if cls.state <> ca_dedicated then
  begin
    strcpy(cls.spawnparms, '');

    for i := 2 to Cmd_Argc_f - 1 do
    begin
      strcat(cls.spawnparms, Cmd_Argv_f(i));
      strcat(cls.spawnparms, ' ');
    end;

    Cmd_ExecuteString('connect local', src_command);
  end;
end;

(*
==================
Host_Changelevel_f

Goes to a new map, taking all clients along
==================
*)

procedure Host_Changelevel_f;
var
  level: array[0..MAX_QPATH - 1] of char;
begin
  if Cmd_Argc_f <> 2 then
  begin
    Con_Printf('changelevel <levelname> : continue game on a new level'#10);
    exit;
  end;
  if not sv.active or cls.demoplayback then
  begin
    Con_Printf('Only the server may changelevel'#10);
    exit;
  end;
  SV_SaveSpawnparms;
  strcpy(level, Cmd_Argv_f(1));
  SV_SpawnServer(level);
end;

(*
==================
Host_Restart_f

Restarts the current server for a dead player
==================
*)

procedure Host_Restart_f;
var
  mapname: array[0..MAX_QPATH - 1] of char;
begin
  if cls.demoplayback or not sv.active then
    exit;

  if cmd_source <> src_command then
    exit;
  strcpy(mapname, sv.name); // must copy out, because it gets cleared
                            // in sv_spawnserver
  SV_SpawnServer(mapname);
end;

(*
==================
Host_Reconnect_f

This command causes the client to wait for the signon messages again.
This is sent just before a server changes levels
==================
*)

procedure Host_Reconnect_f;
begin
  SCR_BeginLoadingPlaque;
  cls.signon := 0; // need new connection messages
end;

(*
=====================
Host_Connect_f

User command to connect to server
=====================
*)

procedure Host_Connect_f;
var
  name: array[0..MAX_QPATH - 1] of char;
begin
  cls.demonum := -1; // stop demo loop in case this fails
  if cls.demoplayback then
  begin
    CL_StopPlayback;
    CL_Disconnect;
  end;
  strcpy(name, Cmd_Argv_f(1));
  CL_EstablishConnection(name);
  Host_Reconnect_f;
end;


(*
===============================================================================

LOAD / SAVE GAME

===============================================================================
*)

const
  SAVEGAME_VERSION = 5;

(*
===============
Host_SavegameComment

Writes a SAVEGAME_COMMENT_LENGTH character comment describing the current
===============
*)

procedure Host_SavegameComment(text: PChar);
var
  i: integer;
  kills: array[0..19] of char;
begin
  for i := 0 to SAVEGAME_COMMENT_LENGTH - 1 do
    text[i] := ' ';
  memcpy(text, @cl.levelname, strlen(cl.levelname));
  sprintf(kills, 'kills:%3d/%3d', [cl.stats[STAT_MONSTERS], cl.stats[STAT_TOTALMONSTERS]]);
  memcpy(@text[22], @kills, strlen(kills));
// convert space to _ to make stdio happy
  for i := 0 to SAVEGAME_COMMENT_LENGTH - 1 do
    if text[i] = ' ' then
      text[i] := '_';
  text[SAVEGAME_COMMENT_LENGTH] := #0;
end;


(*
===============
Host_Savegame_f
===============
*)

procedure Host_Savegame_f;
var
  name: array[0..255] of char;
  f: text;
  i: integer;
  comment: array[0..SAVEGAME_COMMENT_LENGTH] of char;
begin
  if cmd_source <> src_command then
    exit;

  if not sv.active then
  begin
    Con_Printf('Not playing a local game.'#10);
    exit;
  end;

  if cl.intermission <> 0 then
  begin
    Con_Printf('Can''t save in intermission.'#10);
    exit;
  end;

  if svs.maxclients <> 1 then
  begin
    Con_Printf('Can''t save multiplayer games.'#10);
    exit;
  end;

  if Cmd_Argc_f <> 2 then
  begin
    Con_Printf('save <savename> : save a game'#10);
    exit;
  end;

  if strstr(Cmd_Argv_f(1), '..') <> nil then
  begin
    Con_Printf('Relative pathnames are not allowed.'#10);
    exit;
  end;

  for i := 0 to svs.maxclients - 1 do
  begin
    if svs.clients[i].active and (svs.clients[i].edict.v.health <= 0) then
    begin
      Con_Printf('Can''t savegame with a dead player'#10);
      exit;
    end;
  end;

  sprintf(name, '%s/%s', [com_gamedir, Cmd_Argv_f(1)]);
  COM_DefaultExtension(name, '.sav');

  Con_Printf('Saving game to %s...'#10, [name]);

  if not fopen(name, 'w', f) then
  begin
    Con_Printf('ERROR: couldn''t open.'#10);
    exit;
  end;

  fprintf(f, '%d'#10, [SAVEGAME_VERSION]);
  Host_SavegameComment(comment);
  fprintf(f, '%s'#10, [comment]);
  for i := 0 to NUM_SPAWN_PARMS - 1 do
    fprintf(f, '%f'#10, [svs.clients[0].spawn_parms[i]]);
  fprintf(f, '%d'#10, [current_skill]);
  fprintf(f, '%s'#10, [sv.name]);
  fprintf(f, '%f'#10, [sv.time]);

// write the light styles

  for i := 0 to MAX_LIGHTSTYLES - 1 do
  begin
    if sv.lightstyles[i] <> nil then
      fprintf(f, '%s'#10, [sv.lightstyles[i]])
    else
      fprintf(f, 'm'#10);
  end;

  ED_WriteGlobals(f);
  for i := 0 to sv.num_edicts - 1 do
  begin
    ED_Write(f, EDICT_NUM(i));
    flush(f);
  end;
  fclose(f);
  Con_Printf('done.'#10);
end;


(*
===============
Host_Loadgame_f
===============
*)

procedure Host_Loadgame_f;
var
  name: array[0..MAX_OSPATH - 1] of char;
  f: text;
  mapname: array[0..MAX_QPATH - 1] of char;
  time, tfloat: single;
  str: array[0..32767] of char;
  start: PChar;
  i: integer;
  r: char;
  ent: Pedict_t;
  entnum: integer;
  version: integer;
  spawn_parms: array[0..NUM_SPAWN_PARMS - 1] of single;
begin
  if cmd_source <> src_command then
    exit;

  if Cmd_Argc_f <> 2 then
  begin
    Con_Printf('load <savename> : load a game'#10);
    exit;
  end;

  cls.demonum := -1; // stop demo loop in case this fails

  sprintf(name, '%s/%s', [com_gamedir, Cmd_Argv_f(1)]);
  COM_DefaultExtension(name, '.sav');

// we can't call SCR_BeginLoadingPlaque, because too much stack space has
// been used.  The menu calls it before stuffing loadgame command
//  SCR_BeginLoadingPlaque ();

  Con_Printf('Loading game from %s...'#10, [name]);

  if not fopen(name, 'r', f) then
  begin
    Con_Printf('ERROR: couldn''t open.'#10);
    exit;
  end;

  fscanf(f, version);
  if version <> SAVEGAME_VERSION then
  begin
    fclose(f);
    Con_Printf('Savegame is version %d, not %d'#10, [version, SAVEGAME_VERSION]);
    exit;
  end;
  fscanf(f, str);
  for i := 0 to NUM_SPAWN_PARMS - 1 do
    fscanf(f, spawn_parms[i]);
// this silliness is so we can load 1.06 save files, which have float skill values
  fscanf(f, tfloat);
  current_skill := intval(tfloat + 0.1);
  Cvar_SetValue('skill', current_skill);

  fscanf(f, mapname);
  fscanf(f, time);

  CL_Disconnect_f;

  SV_SpawnServer(mapname);
  if not sv.active then
  begin
    Con_Printf('Couldn''t load map'#10);
    exit;
  end;
  sv.paused := true; // pause until all clients connect
  sv.loadgame := true;

// load the light styles

  for i := 0 to MAX_LIGHTSTYLES - 1 do
  begin
    fscanf(f, str);
    sv.lightstyles[i] := Hunk_Alloc(strlen(str) + 1);
    strcpy(sv.lightstyles[i], str);
  end;

// load the edicts out of the savegame file
  entnum := -1; // -1 is the globals
  while not eof(f) do
  begin
    i := 0;
    while i < SizeOf(str) - 1 do
    begin
      getc(f, r);
      if eof(f) or (r = #0) then
        break;
      str[i] := r;
      if r = '}' then
      begin
        inc(i);
        break;
      end;
      inc(i);
    end;
    if i = SizeOf(str) - 1 then
      Sys_Error('Loadgame buffer overflow');
    str[i] := #0;
    start := COM_Parse(str);
    if com_token[0] = #0 then
      break; // end of file
    if strcmp(com_token, '{') <> 0 then
      Sys_Error('First token isn''t a brace');

    if entnum = -1 then
    begin // parse the global vars
      ED_ParseGlobals(start);
    end
    else
    begin // parse an edict

      ent := EDICT_NUM(entnum);
      ZeroMemory(@ent.v, progs.entityfields * 4);
      ent.free := false;
      ED_ParseEdict(start, ent);

    // link it into the bsp tree
      if not ent.free then
        SV_LinkEdict(ent, false);
    end;

    inc(entnum);
  end;

  sv.num_edicts := entnum;
  sv.time := time;

  fclose(f);

  for i := 0 to NUM_SPAWN_PARMS - 1 do
    svs.clients[0].spawn_parms[i] := spawn_parms[i];

  if cls.state <> ca_dedicated then
  begin
    CL_EstablishConnection('local');
    Host_Reconnect_f;
  end;
end;

//============================================================================

(*
======================
Host_Name_f
======================
*)

procedure Host_Name_f;
var
  newName: PChar;
begin
  if Cmd_Argc_f = 1 then
  begin
    Con_Printf('"name" is "%s"'#10, [cl_name.text]);
    exit;
  end;
  if Cmd_Argc_f = 2 then
    newName := Cmd_Argv_f(1)
  else
    newName := Cmd_Args_f;
  newName[15] := #0;

  if cmd_source = src_command then
  begin
    if Q_strcmp(cl_name.text, newName) = 0 then
      exit;
    Cvar_Set('_cl_name', newName);
    if cls.state = ca_connected then
      Cmd_ForwardToServer;
    exit;
  end;

  if boolval(host_client.name[0]) and boolval(strcmp(host_client.name, 'unconnected')) then
    if Q_strcmp(host_client.name, newName) <> 0 then
      Con_Printf('%s renamed to %s'#10, [host_client.name, newName]);
  Q_strcpy(host_client.name, newName);
  host_client.edict.v.netname := integer(@host_client.name) - integer(pr_strings); // JVAL SOS

// send notification to all clients

  MSG_WriteByte(@sv.reliable_datagram, svc_updatename);
  MSG_WriteByte(@sv.reliable_datagram, (integer(host_client) - integer(svs.clients)) div SizeOf(client_t));
  MSG_WriteString(@sv.reliable_datagram, host_client.name);
end;


procedure Host_Version_f;
begin
  Con_Printf('Version %4.2f'#10, [VERSION]);
  Con_Printf('Exe: %s %s'#10, [__TIME__, __DATE__]); // JVAL change this, how???
end;


procedure Host_Say(teamonly: qboolean);
var
  client: Pclient_t;
  save: Pclient_t;
  j: integer;
  p: PChar;
  text: array[0..64] of char;
  fromServer: qboolean;
begin
  fromServer := false;

  if cmd_source = src_command then
  begin
    if cls.state = ca_dedicated then
    begin
      fromServer := true;
      teamonly := false;
    end
    else
    begin
      Cmd_ForwardToServer;
      exit;
    end;
  end;

  if Cmd_Argc_f < 2 then
    exit;

  save := host_client;

  p := Cmd_Args_f;
// remove quotes if present
  if p^ = '"' then
  begin
    inc(p);
    p[Q_strlen(p) - 1] := #0;
  end;

// turn on color set 1
  if not fromServer then
    sprintf(text, '%s%s: ', [Chr(1), save.name]) // JVAL check formating string!
  else
    sprintf(text, '%s<%s> ', [Chr(1), hostname.text]); // JVAL check formating string!

  j := SizeOf(text) - 2 - Q_strlen(text); // -2 for /n and null terminator
  if Q_strlen(p) > j then
    p[j] := #0;

  strcat(text, p);
  strcat(text, #10);

  client := @svs.clients[0]; // JVAL check this
  for j := 0 to svs.maxclients - 1 do
  begin
    if (client = nil) or not client.active or not client.spawned then
    begin
      inc(client);
      continue;
    end;
    if (teamplay.value <> 0) and teamonly and (client.edict.v.team <> save.edict.v.team) then
    begin
      inc(client);
      continue;
    end;
    host_client := client;
    SV_ClientPrintf('%s', [text]);
    inc(client);
  end;
  host_client := save;

  Sys_Printf('%s', [@text[1]]);
end;


procedure Host_Say_f;
begin
  Host_Say(false);
end;


procedure Host_Say_Team_f;
begin
  Host_Say(true);
end;


procedure Host_Tell_f;
var
  client: Pclient_t;
  save: Pclient_t;
  j: integer;
  p: PChar;
  text: array[0..63] of char;
begin
  if cmd_source = src_command then
  begin
    Cmd_ForwardToServer;
    exit;
  end;

  if Cmd_Argc_f < 3 then
    exit;

  Q_strcpy(text, host_client.name);
  Q_strcat(text, ': ');

  p := Cmd_Args_f;

// remove quotes if present
  if p^ = '"' then
  begin
    inc(p);
    p[Q_strlen(p) - 1] := #0;
  end;

// check length & truncate if necessary
  j := SizeOf(text) - 2 - Q_strlen(text); // -2 for /n and null terminator
  if Q_strlen(p) > j then
    p[j] := #0;

  strcat(text, p);
  strcat(text, #10);

  save := host_client;
  client := @svs.clients[0]; // JVAL check this
  for j := 0 to svs.maxclients - 1 do
  begin
    if not client.active or not client.spawned then
    begin
      inc(client);
      continue;
    end;
    if Q_strcasecmp(client.name, Cmd_Argv_f(1)) <> 0 then
    begin
      inc(client);
      continue;
    end;
    host_client := client;
    SV_ClientPrintf('%s', [text]);
    break;
  end;
  host_client := save;
end;


(*
==================
Host_Color_f
==================
*)

procedure Host_Color_f;
var
  top, bottom: integer;
  playercolor: integer;
begin
  if Cmd_Argc_f = 1 then
  begin
    Con_Printf('"color" is "%d %d"'#10, [(intval(cl_color.value) shr 4), intval(cl_color.value) and $0F]);
    Con_Printf('color <0-13> [0-13]'#10);
    exit;
  end;

  if Cmd_Argc_f = 2 then
  begin
    top := atoi(Cmd_Argv_f(1));
    bottom := top;
  end
  else
  begin
    top := atoi(Cmd_Argv_f(1));
    bottom := atoi(Cmd_Argv_f(2));
  end;

  top := top and 15; // JVAL mayby same proc inside func to adjust top & bottom
  if top > 13 then
    top := 13;
  bottom := bottom and 15;
  if bottom > 13 then
    bottom := 13;

  playercolor := top * 16 + bottom;

  if cmd_source = src_command then
  begin
    Cvar_SetValue('_cl_color', playercolor);
    if cls.state = ca_connected then
      Cmd_ForwardToServer;
    exit;
  end;

  host_client.colors := playercolor;
  host_client.edict.v.team := bottom + 1;

// send notification to all clients
  MSG_WriteByte(@sv.reliable_datagram, svc_updatecolors);
  MSG_WriteByte(@sv.reliable_datagram, (integer(host_client) - integer(svs.clients)) div SizeOf(client_t));
  MSG_WriteByte(@sv.reliable_datagram, host_client.colors);
end;

(*
==================
Host_Kill_f
==================
*)

procedure Host_Kill_f;
begin
  if cmd_source = src_command then
  begin
    Cmd_ForwardToServer;
    exit;
  end;

  if sv_player.v.health <= 0 then
  begin
    SV_ClientPrintf('Can''t suicide -- allready dead!'#10);
    exit;
  end;

  pr_global_struct.time := sv.time;
  pr_global_struct.self := EDICT_TO_PROG(sv_player);
  PR_ExecuteProgram(pr_global_struct.ClientKill);
end;


(*
==================
Host_Pause_f
==================
*)

procedure Host_Pause_f;
var
  nname: PChar;
begin
  if cmd_source = src_command then
  begin
    Cmd_ForwardToServer;
    exit;
  end;
  if pausable.value = 0 then
    SV_ClientPrintf('Pause not allowed.'#10)
  else
  begin
    sv.paused := sv.paused xor true;

    nname := PChar(@pr_strings[sv_player.v.netname]); // JVAL check!
    if sv.paused then
      SV_BroadcastPrintf('%s paused the game'#10, [nname])
    else
      SV_BroadcastPrintf('%s unpaused the game'#10, [nname]);

  // send notification to all clients
    MSG_WriteByte(@sv.reliable_datagram, svc_setpause);
    MSG_WriteByte(@sv.reliable_datagram, Ord(sv.paused));
  end;
end;

//===========================================================================


(*
==================
Host_PreSpawn_f
==================
*)

procedure Host_PreSpawn_f;
begin
  if cmd_source = src_command then
  begin
    Con_Printf('prespawn is not valid from the console'#10);
    exit;
  end;

  if host_client.spawned then
  begin
    Con_Printf('prespawn not valid -- allready spawned'#10);
    exit;
  end;

  SZ_Write(@host_client._message, sv.signon.data, sv.signon.cursize);
  MSG_WriteByte(@host_client._message, svc_signonnum);
  MSG_WriteByte(@host_client._message, 2);
  host_client.sendsignon := true;
end;

(*
==================
Host_Spawn_f
==================
*)

procedure Host_Spawn_f;
var
  i: integer;
  client: Pclient_t;
  ent: Pedict_t;
begin
  if cmd_source = src_command then
  begin
    Con_Printf('spawn is not valid from the console'#10);
    exit;
  end;

  if host_client.spawned then
  begin
    Con_Printf('Spawn not valid -- allready spawned'#10);
    exit;
  end;

// run the entrance script
  if sv.loadgame then
  begin // loaded games are fully inited allready
        // if this is the last client to be connected, unpause
    sv.paused := false;
  end
  else
  begin
    // set up the edict
    ent := host_client.edict;

    ZeroMemory(@ent.v, progs.entityfields * 4);
    ent.v.colormap := NUM_FOR_EDICT(ent);
    ent.v.team := (host_client.colors and 15) + 1;
    ent.v.netname := integer(@host_client.name) - integer(pr_strings); // JVAL check

    // copy spawn parms out of the client_t

    for i := 0 to NUM_SPAWN_PARMS - 1 do
      PFloatArray(@pr_global_struct.parm1)[i] := host_client.spawn_parms[i];

    // call the spawn function

    pr_global_struct.time := sv.time;
    pr_global_struct.self := EDICT_TO_PROG(sv_player);
    PR_ExecuteProgram(pr_global_struct.ClientConnect);

    if (Sys_FloatTime - host_client.netconnection.connecttime) <= sv.time then
      Sys_Printf('%s entered the game'#10, [host_client.name]);

    PR_ExecuteProgram(pr_global_struct.PutClientInServer);
  end;


// send all current names, colors, and frag counts
  SZ_Clear(@host_client._message);

// send time of update
  MSG_WriteByte(@host_client._message, svc_time);
  MSG_WriteFloat(@host_client._message, sv.time);

  client := @svs.clients[0]; // JVAL check
  for i := 0 to svs.maxclients - 1 do
  begin
    MSG_WriteByte(@host_client._message, svc_updatename);
    MSG_WriteByte(@host_client._message, i);
    MSG_WriteString(@host_client._message, client.name);
    MSG_WriteByte(@host_client._message, svc_updatefrags);
    MSG_WriteByte(@host_client._message, i);
    MSG_WriteShort(@host_client._message, client.old_frags);
    MSG_WriteByte(@host_client._message, svc_updatecolors);
    MSG_WriteByte(@host_client._message, i);
    MSG_WriteByte(@host_client._message, client.colors);
    inc(client);
  end;

// send all current light styles
  for i := 0 to MAX_LIGHTSTYLES - 1 do
  begin
    MSG_WriteByte(@host_client._message, svc_lightstyle);
    MSG_WriteByte(@host_client._message, i);
    MSG_WriteString(@host_client._message, sv.lightstyles[i]);
  end;

//
// send some stats
//
  MSG_WriteByte(@host_client._message, svc_updatestat);
  MSG_WriteByte(@host_client._message, STAT_TOTALSECRETS);
  MSG_WriteLong(@host_client._message, intval(pr_global_struct.total_secrets));

  MSG_WriteByte(@host_client._message, svc_updatestat);
  MSG_WriteByte(@host_client._message, STAT_TOTALMONSTERS);
  MSG_WriteLong(@host_client._message, intval(pr_global_struct.total_monsters));

  MSG_WriteByte(@host_client._message, svc_updatestat);
  MSG_WriteByte(@host_client._message, STAT_SECRETS);
  MSG_WriteLong(@host_client._message, intval(pr_global_struct.found_secrets));

  MSG_WriteByte(@host_client._message, svc_updatestat);
  MSG_WriteByte(@host_client._message, STAT_MONSTERS);
  MSG_WriteLong(@host_client._message, intval(pr_global_struct.killed_monsters));


//
// send a fixangle
// Never send a roll angle, because savegames can catch the server
// in a state where it is expecting the client to correct the angle
// and it won't happen if the game was just loaded, so you wind up
// with a permanent head tilt
  ent := EDICT_NUM(1 + (integer(host_client) - integer(svs.clients)) div SizeOf(client_t));
  MSG_WriteByte(@host_client._message, svc_setangle);
  for i := 0 to 1 do
    MSG_WriteAngle(@host_client._message, ent.v.angles[i]);
  MSG_WriteAngle(@host_client._message, 0);

  SV_WriteClientdataToMessage(sv_player, @host_client._message);

  MSG_WriteByte(@host_client._message, svc_signonnum);
  MSG_WriteByte(@host_client._message, 3);
  host_client.sendsignon := true;
end;

(*
==================
Host_Begin_f
==================
*)

procedure Host_Begin_f;
begin
  if cmd_source = src_command then
  begin
    Con_Printf('begin is not valid from the console'#10);
    exit;
  end;

  host_client.spawned := true;
end;

//===========================================================================


(*
==================
Host_Kick_f

Kicks a user off of the server
==================
*)

procedure Host_Kick_f;
var
  who: PChar;
  _message: PChar;
  save: Pclient_t;
  i: integer;
  byNumber: qboolean;
begin
  _message := nil;
  byNumber := false;

  if cmd_source = src_command then
  begin
    if not sv.active then
    begin
      Cmd_ForwardToServer;
      exit;
    end;
  end
  else if (pr_global_struct.deathmatch <> 0) and not host_client.privileged then
    exit;

  save := host_client;

  if (Cmd_Argc_f > 2) and (Q_strcmp(Cmd_Argv_f(1), '#') = 0) then
  begin
    i := intval(Q_atof(Cmd_Argv_f(2))) - 1;
    if (i < 0) or (i >= svs.maxclients) then
      exit;
    if not svs.clients[i].active then
      exit;
    host_client := @svs.clients[i];
    byNumber := true;
  end
  else
  begin
    host_client := @svs.clients[0]; // JVAL check
    i := 0;
    while i < svs.maxclients do
    begin
      if not host_client.active then
      begin
        inc(host_client);
        inc(i);
        continue;
      end;
      if Q_strcasecmp(host_client.name, Cmd_Argv_f(1)) = 0 then
        break;
      inc(host_client);
      inc(i);
    end;
  end;

  if i < svs.maxclients then
  begin
    if cmd_source = src_command then
    begin
      if cls.state = ca_dedicated then
        who := 'Console'
      else
        who := cl_name.text;
    end
    else
      who := save.name;

    // can't kick yourself!
    if host_client = save then
      exit;

    if Cmd_Argc_f > 2 then
    begin
      _message := COM_Parse(Cmd_Args_f);
      if byNumber then
      begin
        inc(_message); // skip the #
        while _message^ = ' ' do // skip white space
          inc(_message);
        _message := @_message[Q_strlen(Cmd_Argv_f(2))]; // skip the number
      end;
      while boolval(_message^) and (_message^ = ' ') do
        inc(_message);
    end;
    if _message <> nil then
      SV_ClientPrintf('Kicked by %s: %s'#10, [who, _message])
    else
      SV_ClientPrintf('Kicked by %s'#10, [who]);
    SV_DropClient(false);
  end;

  host_client := save;
end;

(*
===============================================================================

DEBUGGING TOOLS

===============================================================================
*)

(*
==================
Host_Give_f
==================
*)

procedure Host_Give_f;
var
  t: PChar;
  v: integer;
  val: Peval_t;
begin
  if cmd_source = src_command then
  begin
    Cmd_ForwardToServer;
    exit;
  end;

  if (pr_global_struct.deathmatch <> 0) and not host_client.privileged then
    exit;

  t := Cmd_Argv_f(1);
  v := atoi(Cmd_Argv_f(2));

  case t[0] of
    '0',
      '1',
      '2',
      '3',
      '4',
      '5',
      '6',
      '7',
      '8',
      '9':
      begin
        // MED 01/04/97 added hipnotic give stuff
        if hipnotic then
        begin
          if t[0] = '6' then
          begin
            if t[1] = 'a' then
              sv_player.v.items := intval(sv_player.v.items) or HIT_PROXIMITY_GUN
            else
              sv_player.v.items := intval(sv_player.v.items) or IT_GRENADE_LAUNCHER;
          end
          else if t[0] = '9' then
            sv_player.v.items := intval(sv_player.v.items) or HIT_LASER_CANNON
          else if t[0] = '0' then
            sv_player.v.items := intval(sv_player.v.items) or HIT_MJOLNIR
          else if t[0] >= '2' then
            sv_player.v.items := intval(sv_player.v.items) or ((IT_SHOTGUN shl (Ord(t[0]) - Ord('2'))));
        end
        else
        begin
          if t[0] >= '2' then
            sv_player.v.items := intval(sv_player.v.items) or ((IT_SHOTGUN shl (Ord(t[0]) - Ord('2'))));
        end;
      end;

    's':
      begin
        if rogue then
        begin
          val := GetEdictFieldValue(sv_player, 'ammo_shells1');
          if val <> nil then
            val._float := v;
        end;

        sv_player.v.ammo_shells := v;
      end;
    'n':
      begin
        if rogue then
        begin
          val := GetEdictFieldValue(sv_player, 'ammo_nails1');
          if val <> nil then
          begin
            val._float := v;
            if sv_player.v.weapon <= IT_LIGHTNING then
              sv_player.v.ammo_nails := v;
          end;
        end
        else
          sv_player.v.ammo_nails := v;
      end;
    'l':
      begin
        if rogue then
        begin
          val := GetEdictFieldValue(sv_player, 'ammo_lava_nails');
          if val <> nil then
          begin
            val._float := v;
            if sv_player.v.weapon > IT_LIGHTNING then
              sv_player.v.ammo_nails := v;
          end;
        end;
      end;
    'r':
      begin
        if rogue then
        begin
          val := GetEdictFieldValue(sv_player, 'ammo_rockets1');
          if val <> nil then
          begin
            val._float := v;
            if sv_player.v.weapon <= IT_LIGHTNING then
              sv_player.v.ammo_rockets := v;
          end;
        end
        else
          sv_player.v.ammo_rockets := v;
      end;
    'm':
      begin
        if rogue then
        begin
          val := GetEdictFieldValue(sv_player, 'ammo_multi_rockets');
          if val <> nil then
          begin
            val._float := v;
            if sv_player.v.weapon > IT_LIGHTNING then
              sv_player.v.ammo_rockets := v;
          end;
        end;
      end;
    'h':
      begin
        sv_player.v.health := v;
      end;
    'c':
      begin
        if rogue then
        begin
          val := GetEdictFieldValue(sv_player, 'ammo_cells1');
          if val <> nil then
          begin
            val._float := v;
            if sv_player.v.weapon <= IT_LIGHTNING then
              sv_player.v.ammo_cells := v;
          end
        end
        else
          sv_player.v.ammo_cells := v;
      end;
    'p':
      begin
        if rogue then
        begin
          val := GetEdictFieldValue(sv_player, 'ammo_plasma');
          if val <> nil then
          begin
            val._float := v;
            if sv_player.v.weapon > IT_LIGHTNING then
              sv_player.v.ammo_cells := v;
          end;
        end;
      end;
  end;
end;

function FindViewthing: Pedict_t;
var
  i: integer;
  e: Pedict_t;
begin
  for i := 0 to sv.num_edicts - 1 do
  begin
    e := EDICT_NUM(i);
    if strcmp(@pr_strings[e.v.classname], 'viewthing') = 0 then // JVAL SOS
    begin
      result := e;
      exit;
    end;
  end;
  Con_Printf('No viewthing on map'#10);
  result := nil;
end;

(*
==================
Host_Viewmodel_f
==================
*)

procedure Host_Viewmodel_f;
var
  e: Pedict_t;
  m: PBSPModelFile;
begin
  e := FindViewthing;
  if e = nil then
    exit;

  m := Mod_ForName(Cmd_Argv_f(1), false);
  if m = nil then
  begin
    Con_Printf('Can''t load %s'#10, [Cmd_Argv_f(1)]);
    exit;
  end;

  e.v.frame := 0;
  cl.model_precache[intval(e.v.modelindex)] := m;
end;

(*
==================
Host_Viewframe_f
==================
*)

procedure Host_Viewframe_f;
var
  e: Pedict_t;
  f: integer;
  m: PBSPModelFile;
begin
  e := FindViewthing;
  if e = nil then
    exit;

  m := cl.model_precache[intval(e.v.modelindex)];

  f := atoi(Cmd_Argv_f(1));
  if f >= m.numframes then
    f := m.numframes - 1;

  e.v.frame := f;
end;


procedure PrintFrameName(m: PBSPModelFile; frame: integer);
var
  hdr: Paliashdr_t;
  pframedesc: Pmaliasframedesc_t;
begin
  hdr := Paliashdr_t(Mod_Extradata(m));
  if hdr = nil then
    exit;

  pframedesc := @hdr.frames[frame];

  Con_Printf('frame %d: %s'#10, [frame, pframedesc.name]);
end;

procedure Host_ViewDelta(delta: integer); // Added by JVAL
var
  e: Pedict_t;
  m: PBSPModelFile;
begin
  e := FindViewthing;
  if e = nil then
    exit;

  m := cl.model_precache[intval(e.v.modelindex)];

  e.v.frame := e.v.frame + delta;
  if e.v.frame >= m.numframes then
    e.v.frame := m.numframes - 1;
  if e.v.frame < 0 then
    e.v.frame := 0;

  PrintFrameName(m, intval(e.v.frame));
end;

(*
==================
Host_Viewnext_f
==================
*)

procedure Host_Viewnext_f;
begin
  Host_ViewDelta(1);
end;

(*
==================
Host_Viewprev_f
==================
*)

procedure Host_Viewprev_f;
begin
  Host_ViewDelta(-1);
end;

(*
===============================================================================

DEMO LOOP CONTROL

===============================================================================
*)


(*
==================
Host_Startdemos_f
==================
*)

procedure Host_Startdemos_f;
var
  i, c: integer;
begin
  if cls.state = ca_dedicated then
  begin
    if not sv.active then
      Cbuf_AddText('map start'#10);
    exit;
  end;

  c := Cmd_Argc_f - 1;
  if c > MAX_DEMOS then
  begin
    Con_Printf('Max %d demos in demoloop'#10, [MAX_DEMOS]);
    c := MAX_DEMOS;
  end;
  Con_Printf('%d demo(s) in loop'#10, [c]);

  for i := 1 to c do
    strncpy(cls.demos[i - 1], Cmd_Argv_f(i), SizeOf(cls.demos[0]) - 1);

  if not sv.active and (cls.demonum <> -1) and not cls.demoplayback then
  begin
    cls.demonum := 0;
    CL_NextDemo;
  end
  else
    cls.demonum := -1;
end;


(*
==================
Host_Demos_f

Return to looping demos
==================
*)

procedure Host_Demos_f;
begin
  if cls.state = ca_dedicated then
    exit;

  if cls.demonum = -1 then
    cls.demonum := 1;
  CL_Disconnect_f;
  CL_NextDemo;
end;

(*
==================
Host_Stopdemo_f

Return to looping demos
==================
*)

procedure Host_Stopdemo_f;
begin
  if cls.state = ca_dedicated then
    exit;

  if not cls.demoplayback then
    exit;

  CL_StopPlayback;
  CL_Disconnect;
end;

//=============================================================================

(*
==================
Host_InitCommands
==================
*)

procedure Host_InitCommands;
begin
  Cmd_AddCommand('status', Host_Status_f);
  Cmd_AddCommand('quit', Host_Quit_f);
  Cmd_AddCommand('god', Host_God_f);
  Cmd_AddCommand('notarget', Host_Notarget_f);
  Cmd_AddCommand('fly', Host_Fly_f);
  Cmd_AddCommand('map', Host_Map_f);
  Cmd_AddCommand('restart', Host_Restart_f);
  Cmd_AddCommand('changelevel', Host_Changelevel_f);
  Cmd_AddCommand('connect', Host_Connect_f);
  Cmd_AddCommand('reconnect', Host_Reconnect_f);
  Cmd_AddCommand('name', Host_Name_f);
  Cmd_AddCommand('noclip', Host_Noclip_f);
  Cmd_AddCommand('version', Host_Version_f);
  Cmd_AddCommand('say', Host_Say_f);
  Cmd_AddCommand('say_team', Host_Say_Team_f);
  Cmd_AddCommand('tell', Host_Tell_f);
  Cmd_AddCommand('color', Host_Color_f);
  Cmd_AddCommand('kill', Host_Kill_f);
  Cmd_AddCommand('pause', Host_Pause_f);
  Cmd_AddCommand('spawn', Host_Spawn_f);
  Cmd_AddCommand('begin', Host_Begin_f);
  Cmd_AddCommand('prespawn', Host_PreSpawn_f);
  Cmd_AddCommand('kick', Host_Kick_f);
  Cmd_AddCommand('ping', Host_Ping_f);
  Cmd_AddCommand('load', Host_Loadgame_f);
  Cmd_AddCommand('save', Host_Savegame_f);
  Cmd_AddCommand('give', Host_Give_f);

  Cmd_AddCommand('startdemos', Host_Startdemos_f);
  Cmd_AddCommand('demos', Host_Demos_f);
  Cmd_AddCommand('stopdemo', Host_Stopdemo_f);

  Cmd_AddCommand('viewmodel', Host_Viewmodel_f);
  Cmd_AddCommand('viewframe', Host_Viewframe_f);
  Cmd_AddCommand('viewnext', Host_Viewnext_f);
  Cmd_AddCommand('viewprev', Host_Viewprev_f);

  Cmd_AddCommand('mcache', Mod_Print);
end;

end.

