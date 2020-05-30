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

unit host;

// host.c -- coordinates spawning and killing of local servers

interface

uses
  q_delphi,
  quakedef;

(*

A server can allways be started, even if the system started out as a client
to a remote system.

A client can NOT be started if the system started as a dedicated server.

Memory is cleared / released when a server or client begins, not when they end.

*)
procedure Host_EndGame(_message: PChar; const Args: array of const);
procedure Host_Error(error: PChar); overload;
procedure Host_Error(error: PChar; const Args: array of const); overload;
procedure Host_FindMaxClients;
procedure Host_InitLocal;
procedure Host_WriteConfiguration;
procedure SV_ClientPrintf(fmt: PChar); overload;
procedure SV_ClientPrintf(fmt: PChar; const Args: array of const); overload;
procedure SV_ClientPrintf(fmt: string); overload;
procedure SV_ClientPrintf(fmt: string; const Args: array of const); overload;
procedure SV_BroadcastPrintf(fmt: PChar; const Args: array of const);
procedure Host_ClientCommands(fmt: PChar; const Args: array of const);
procedure SV_DropClient(crash: qboolean);
procedure Host_ShutdownServer(crash: qboolean);
procedure Host_ClearMemory;
procedure Host_GetConsoleCommands;
procedure Host_ServerFrame;
procedure Host_Frame(time: single);
procedure Host_InitVCR(parms: Pquakeparms_t);
procedure Host_Init(parms: Pquakeparms_t);
procedure Host_Shutdown;


implementation

uses
  q_vector,
  server_h,
  cvar,
  console,
  sv_main,
  cl_main,
  client,
  sys_win,
  gl_screen,
  common,
  zone,
  host_cmd,
  cl_main_h,
  host_h,
  keys,
  protocol,
  net_main,
  pr_edict,
  progs_h,
  pr_exec,
  gl_rmisc,
  gl_model,
  cmd,
  sv_user,
  sv_phys,
  in_win,
  snd_dma,
  gl_rmain_h,
  cd_win,
  view,
  chase,
  wad,
  menu,
  gl_vidnt,
  gl_draw,
  sbar,
  q_extra,
  SysUtils,
  pr_cmds;


(*
================
Host_EndGame
================
*)

procedure Host_EndGame(_message: PChar; const Args: array of const);
var
  _string: array[0..1023] of char;
begin
  sprintf(_string, _message, Args);
  Con_DPrintf('Host_EndGame: %s'#10, [_string]);

  if sv.active then
    Host_ShutdownServer(false);

  if cls.state = ca_dedicated then
    Sys_Error('Host_EndGame: %s', [_string]); // dedicated servers exit

  if cls.demonum <> -1 then
    CL_NextDemo
  else
    CL_Disconnect;
end;

(*
================
Host_Error

This shuts down both the client and server
================
*)
var
  inerror: qboolean = false;

procedure Host_Error(error: PChar);
begin
  Host_Error(error, []);
end;

procedure Host_Error(error: PChar; const Args: array of const);
var
  _string: array[0..1023] of char;
begin
  if inerror then
    Sys_Error('Host_Error: recursively entered');
  inerror := true;

  SCR_EndLoadingPlaque; // reenable screen updates

  sprintf(_string, error, Args);
  Con_Printf('Host_Error: %s'#10, [_string]);

  if sv.active then
    Host_ShutdownServer(false);

  if cls.state = ca_dedicated then
    Sys_Error('Host_Error: %s'#10, [_string]); // dedicated servers exit

  CL_Disconnect;
  cls.demonum := -1;

  inerror := false;

  raise Exception.CreateFmt('Host_Error: %s'#10, [_string]);
end;

(*
================
Host_FindMaxClients
================
*)

procedure Host_FindMaxClients;
var
  i: integer;
begin
  svs.maxclients := 1;

  i := COM_CheckParm('-dedicated');
  if i <> 0 then
  begin
    cls.state := ca_dedicated;
    if i <> (com_argc - 1) then
      svs.maxclients := Q_atoi(com_argv[i + 1])
    else
      svs.maxclients := 32;
  end
  else
    cls.state := ca_disconnected;

  i := COM_CheckParm('-listen');
  if i <> 0 then
  begin
    if cls.state = ca_dedicated then
      Sys_Error('Only one of -dedicated or -listen can be specified');
    if i <> com_argc - 1 then
      svs.maxclients := Q_atoi(com_argv[i + 1])
    else
      svs.maxclients := 32;
  end;
  if svs.maxclients < 1 then
    svs.maxclients := 32
  else if svs.maxclients > MAX_SCOREBOARD then
    svs.maxclients := MAX_SCOREBOARD;

  svs.maxclientslimit := svs.maxclients;
  if svs.maxclientslimit < 4 then
    svs.maxclientslimit := 4;
  svs.clients := Hunk_AllocName(svs.maxclientslimit * SizeOf(client_t), 'clients');

  if svs.maxclients > 1 then Cvar_SetValue('deathmatch', 1.0)
  else Cvar_SetValue('deathmatch', 0.0);
end;


(*
=======================
Host_InitLocal
======================
*)

procedure Host_InitLocal;
begin
  Host_InitCommands;

  Cvar_RegisterVariable(@host_framerate);
  Cvar_RegisterVariable(@host_speeds);

  Cvar_RegisterVariable(@sys_ticrate);
  Cvar_RegisterVariable(@serverprofile);

  Cvar_RegisterVariable(@fraglimit);
  Cvar_RegisterVariable(@timelimit);
  Cvar_RegisterVariable(@teamplay);
  Cvar_RegisterVariable(@samelevel);
  Cvar_RegisterVariable(@noexit);
  Cvar_RegisterVariable(@skill);
  Cvar_RegisterVariable(@developer);
  Cvar_RegisterVariable(@deathmatch);
  Cvar_RegisterVariable(@coop);

  Cvar_RegisterVariable(@pausable);

  Cvar_RegisterVariable(@temp1);

  Host_FindMaxClients;

  host_time := 1.0; // so a think at time 0 won't get called
end;


(*
===============
Host_WriteConfiguration

Writes key bindings and archived cvars to config.cfg
===============
*)

procedure Host_WriteConfiguration;
var
  f: text;
begin
// dedicated servers initialize the host but don't parse and set the
// config.cfg cvars
  if host_initialized and not isDedicated then // JVAL check this!
  begin
    if not fopen(va('%s/config.cfg', [com_gamedir]), 'w', f) then
    begin
      Con_Printf('Couldn''t write config.cfg.'#10);
      exit;
    end;

    Key_WriteBindings(f);
    Cvar_WriteVariables(f);

    fclose(f);
  end;
end;


(*
=================
SV_ClientPrintf

Sends text across to be displayed
FIXME: make this just a stuffed echo?
=================
*)

procedure SV_ClientPrintf(fmt: PChar);
begin
  SV_ClientPrintf(fmt, []);
end;

procedure SV_ClientPrintf(fmt: PChar; const Args: array of const);
var
  _string: array[0..1023] of char;
begin
  sprintf(_string, fmt, Args);

  MSG_WriteByte(@host_client._message, svc_print);
  MSG_WriteString(@host_client._message, _string);
end;

procedure SV_ClientPrintf(fmt: string);
begin
  SV_ClientPrintf(PChar(fmt));
end;

procedure SV_ClientPrintf(fmt: string; const Args: array of const); overload;
begin
  SV_ClientPrintf(PChar(fmt), Args);
end;

(*
=================
SV_BroadcastPrintf

Sends text to all active clients
=================
*)

procedure SV_BroadcastPrintf(fmt: PChar; const Args: array of const);
var
  _string: array[0..1023] of char;
  i: integer;
begin
  sprintf(_string, fmt, Args);

  for i := 0 to svs.maxclients - 1 do
    if svs.clients[i].active and svs.clients[i].spawned then
    begin
      MSG_WriteByte(@svs.clients[i]._message, svc_print);
      MSG_WriteString(@svs.clients[i]._message, _string);
    end;
end;

(*
=================
Host_ClientCommands

Send text over to the client to be executed
=================
*)

procedure Host_ClientCommands(fmt: PChar; const Args: array of const);
var
  _string: array[0..1023] of char;
begin
  sprintf(_string, fmt, Args);

  MSG_WriteByte(@host_client._message, svc_stufftext);
  MSG_WriteString(@host_client._message, _string);
end;

(*
=====================
SV_DropClient

Called when the player is getting totally kicked off the host
if (crash = true), don't bother sending signofs
=====================
*)

procedure SV_DropClient(crash: qboolean);
var
  saveSelf: integer;
  i: integer;
  client: Pclient_t;
begin
  if not crash then
  begin
    // send any final messages (don't check for errors)
    if NET_CanSendMessage(host_client.netconnection) then
    begin
      MSG_WriteByte(@host_client._message, svc_disconnect);
      NET_SendMessage(host_client.netconnection, @host_client._message);
    end;

    if (host_client.edict <> nil) and host_client.spawned then
    begin
    // call the prog function for removing a client
    // this will set the body to a dead frame, among other things
      saveSelf := pr_global_struct.self;
      pr_global_struct.self := EDICT_TO_PROG(host_client.edict);
      PR_ExecuteProgram(pr_global_struct.ClientDisconnect);
      pr_global_struct.self := saveSelf;
    end;

    Sys_Printf('Client %s removed'#10, [host_client.name]);
  end;

// break the net connection
  NET_Close(host_client.netconnection);
  host_client.netconnection := nil;

// free the client (the body stays around)
  host_client.active := false;
  host_client.name[0] := #0;
  host_client.old_frags := -999999;
  dec(net_activeconnections);

// send notification to all clients
  client := @svs.clients[0]; // JVAL check this
  for i := 0 to svs.maxclients - 1 do
  begin
    if client.active then
    begin
      MSG_WriteByte(@client._message, svc_updatename);
      MSG_WriteByte(@client._message, (integer(host_client) - integer(svs.clients)) div SizeOf(client_t));
      MSG_WriteString(@client._message, '');
      MSG_WriteByte(@client._message, svc_updatefrags);
      MSG_WriteByte(@client._message, (integer(host_client) - integer(svs.clients)) div SizeOf(client_t));
      MSG_WriteShort(@client._message, 0);
      MSG_WriteByte(@client._message, svc_updatecolors);
      MSG_WriteByte(@client._message, (integer(host_client) - integer(svs.clients)) div SizeOf(client_t));
      MSG_WriteByte(@client._message, 0);
    end;
    inc(client);
  end;
end;

(*
==================
Host_ShutdownServer

This only happens at the end of a game, not between levels
==================
*)

procedure Host_ShutdownServer(crash: qboolean);
var
  i: integer;
  count: integer;
  buf: sizebuf_t;
  msg: array[0..3] of char;
  start: double;
begin
  if not sv.active then
    exit;

  sv.active := false;

// stop all client sounds immediately
  if cls.state = ca_connected then
    CL_Disconnect;

// flush any pending messages - like the score!!!
  start := Sys_FloatTime;
  repeat
    count := 0;
    host_client := @svs.clients[0]; // JVAL check
    for i := 0 to svs.maxclients - 1 do
    begin
      if host_client.active and (host_client._message.cursize <> 0) then
      begin
        if NET_CanSendMessage(host_client.netconnection) then
        begin
          NET_SendMessage(host_client.netconnection, @host_client._message);
          SZ_Clear(@host_client._message);
        end
        else
        begin
          NET_GetMessage(host_client.netconnection);
          inc(count);
        end;
      end;
      inc(host_client);
    end;
    if ((Sys_FloatTime - start) > 3.0) then
      break;
  until count = 0;

// make sure all the clients know we're disconnecting
  buf.data := @msg;
  buf.maxsize := 4;
  buf.cursize := 0;
  MSG_WriteByte(@buf, svc_disconnect);
  count := NET_SendToAll(@buf, 5);
  if count <> 0 then
    Con_Printf('Host_ShutdownServer: NET_SendToAll failed for %u clients'#10, [count]);

  host_client := @svs.clients[0];
  for i := 0 to svs.maxclients - 1 do
  begin
    if host_client.active then
      SV_DropClient(crash);
    inc(host_client);
  end;
//
// clear structures
//
  ZeroMemory(@sv, SizeOf(sv));
  memset(svs.clients, 0, svs.maxclientslimit * SizeOf(client_t));
end;


(*
================
Host_ClearMemory

This clears all the memory used by both the client and server, but does
not reinitialize anything.
================
*)

procedure Host_ClearMemory;
begin
  Con_DPrintf('Clearing memory'#10);
  D_FlushCaches;
  Mod_ClearAll;
  if host_hunklevel <> 0 then
    Hunk_FreeToLowMark(host_hunklevel);

  cls.signon := 0;
  ZeroMemory(@sv, SizeOf(sv));
  ZeroMemory(@cl, SizeOf(cl));
end;


//============================================================================


(*
===================
Host_FilterTime

Returns false if the time is too short to run a frame
===================
*)

function Host_FilterTime(time: single): qboolean;
begin
  realtime := realtime + time;

  if not cls.timedemo and (realtime - oldrealtime < 1.0 / 72.0) then
  begin
    result := false; // framerate is too high
    exit;
  end;

  host_frametime := realtime - oldrealtime;
  oldrealtime := realtime;

  if host_framerate.value > 0 then
    host_frametime := host_framerate.value
  else
  begin // don't allow really long or short frames
    if host_frametime > 0.1 then
      host_frametime := 0.1;
    if host_frametime < 0.001 then
      host_frametime := 0.001;
  end;

  result := true;
end;


(*
===================
Host_GetConsoleCommands

Add them exactly as if they had been typed at the console
===================
*)

procedure Host_GetConsoleCommands;
var
  cmd: PChar;
begin
  while true do
  begin
    cmd := Sys_ConsoleInput;
    if cmd = nil then
      break;
    Cbuf_AddText(cmd);
  end;
end;


procedure Host_ServerFrame;
begin
// run the world state
  pr_global_struct.frametime := host_frametime;

// set the time and clear the general datagram
  SV_ClearDatagram;

// check for new clients
  SV_CheckForNewClients;

// read client messages
  SV_RunClients;

// move things around and think
// always pause in single player if in console or menus
  if not sv.paused and ((svs.maxclients > 1) or (key_dest = key_game)) then
    SV_Physics;

// send all messages to the clients
  SV_SendClientMessages;
end;

(*
==================
Host_Frame

Runs all active servers
==================
*)
var
  time1_Host_Frame: double = 0.0;
  time2_Host_Frame: double = 0.0;
  time3_Host_Frame: double = 0.0;

procedure _Host_Frame(time: single);
var
  pass1, pass2, pass3: integer;
begin
//  if boolval(setjmp(host_abortserver)) then // JVAL removed!
//    exit;      // something bad happened, or the server disconnected

// keep the random time dependent
  rand;

// decide the simulation time
  if not Host_FilterTime(time) then
    exit; // don't run too fast, or packets will flood out

// get new key events
  Sys_SendKeyEvents;

// allow mice or other external controllers to add commands
  IN_Commands;

// process console commands
  Cbuf_Execute;

  NET_Poll;

// if running the server locally, make intentions now
  if sv.active then
    CL_SendCmd;

//-------------------
//
// server operations
//
//-------------------

// check for commands typed to the host
  Host_GetConsoleCommands;

  if sv.active then
    Host_ServerFrame;

//-------------------
//
// client operations
//
//-------------------

// if running the server remotely, send intentions now after
// the incoming messages have been read
  if not sv.active then
    CL_SendCmd;

  host_time := host_time + host_frametime;

// fetch results from server
  if cls.state = ca_connected then
    CL_ReadFromServer;

// update video
  if host_speeds.value <> 0 then
    time1_Host_Frame := Sys_FloatTime;

  SCR_UpdateScreen;

  if host_speeds.value <> 0 then
    time2_Host_Frame := Sys_FloatTime;

// update audio
  if cls.signon = SIGNONS then
  begin
    S_Update(@r_origin, @vpn, @vright, @vup);
    CL_DecayLights;
  end
  else
    S_Update(@vec3_origin, @vec3_origin, @vec3_origin, @vec3_origin);

  CDAudio_Update;

  if host_speeds.value <> 0 then
  begin
    pass1 := intval((time1_Host_Frame - time3_Host_Frame) * 1000);
    time3_Host_Frame := Sys_FloatTime;
    pass2 := intval((time2_Host_Frame - time1_Host_Frame) * 1000);
    pass3 := intval((time3_Host_Frame - time2_Host_Frame) * 1000);
    Con_Printf('%3d tot %3d server %3d gfx %3d snd'#10,
      [pass1 + pass2 + pass3, pass1, pass2, pass3]);
  end;

  inc(host_framecount);

end;

var
  timetotal_Host_Frame: double = 0.0;
  timecount_Host_Frame: integer = 0;

procedure Host_Frame(time: single);
var
  time1, time2: double;
  i, c, m: integer;
begin
  if serverprofile.value = 0 then
  begin
    try
      _Host_Frame(time);
    except
      on E: Exception do
        Sys_Error('%s', [E.Message]);
    end;
    exit;
  end;

  time1 := Sys_FloatTime;
  _Host_Frame(time);
  time2 := Sys_FloatTime;

  timetotal_Host_Frame := timetotal_Host_Frame + time2 - time1;
  inc(timecount_Host_Frame);

  if timecount_Host_Frame < 1000 then
    exit;

  m := intval((timetotal_Host_Frame * 1000) / timecount_Host_Frame);
  timecount_Host_Frame := 0;
  timetotal_Host_Frame := 0.0;
  c := 0;
  for i := 0 to svs.maxclients - 1 do
  begin
    if svs.clients[i].active then
      inc(c);
  end;

  Con_Printf('serverprofile: %2d clients %2d msec'#10, [c, m]);
end;

//============================================================================


//extern int vcrFile;
const
  VCR_SIGNATURE = $56435231;

// "VCR1"

procedure Host_InitVCR(parms: Pquakeparms_t);
var
  i, len, n: integer;
  p: PChar;
  buf: array[0..9] of char;
begin
  if COM_CheckParm('-playback') <> 0 then
  begin
    if com_argc <> 2 then
      Sys_Error('No other parameters allowed with -playback'#10);

    Sys_FileOpenRead('quake.vcr', @vcrFile);
    if vcrFile = -1 then
      Sys_Error('playback file not found'#10);

    Sys_FileRead(vcrFile, @i, SizeOf(integer));
    if i <> VCR_SIGNATURE then
      Sys_Error('Invalid signature in vcr file'#10);

    Sys_FileRead(vcrFile, @com_argc, SizeOf(integer));
    com_argv := malloc(com_argc * SizeOf(PChar));
    com_argv[0] := parms.argv[0];
    for i := 0 to com_argc - 1 do
    begin
      Sys_FileRead(vcrFile, @len, SizeOf(integer));
      p := malloc(len);
      Sys_FileRead(vcrFile, p, len);
      com_argv[i + 1] := p;
    end;
    inc(com_argc); (* add one for arg[0] *)
    parms.argc := com_argc;
    parms.argv := com_argv;
  end;

  n := COM_CheckParm('-record');
  if n <> 0 then
  begin
    vcrFile := Sys_FileOpenWrite('quake.vcr');

    i := VCR_SIGNATURE;
    Sys_FileWrite(vcrFile, @i, SizeOf(integer));
    i := com_argc - 1;
    Sys_FileWrite(vcrFile, @i, sizeof(integer));
    for i := 1 to com_argc - 1 do
    begin
      if i = n then
      begin
        len := 10;
        strcat(buf, '-playback');
        Sys_FileWrite(vcrFile, @len, SizeOf(integer));
        Sys_FileWrite(vcrFile, @buf, len);
        continue;
      end;
      len := Q_strlen(com_argv[i]) + 1;
      Sys_FileWrite(vcrFile, @len, SizeOf(integer));
      Sys_FileWrite(vcrFile, com_argv[i], len);
    end;
  end;

end;

(*
====================
Host_Init
====================
*)

procedure Host_Init(parms: Pquakeparms_t);
begin
  if standard_quake then
    minimum_memory := MINIMUM_MEMORY
  else
    minimum_memory := MINIMUM_MEMORY_LEVELPAK;

  if COM_CheckParm('-minmemory') <> 0 then
    parms.memsize := minimum_memory;

  host_parms := parms^;

  if parms.memsize < minimum_memory then
    Sys_Error('Only %4.1f megs of memory available, can''t execute game',
      [parms.memsize / $100000]);

  com_argc := parms.argc;
  com_argv := parms.argv;

  Memory_Init(parms.membase, parms.memsize);
  QEX_Init;
  PR_InitBuiltIns;
  Cbuf_Init;
  Cmd_Init;
  V_Init;
  Chase_Init;
  Host_InitVCR(parms);
  COM_Init(parms.basedir);
  Host_InitLocal;
  W_LoadWadFile('gfx.wad');
  Key_Init;
  Con_Init;
  M_Init;
  PR_Init;
  Mod_Init;
  NET_Init;
  SV_Init;

  Con_Printf('Exe: %s %s'#10, [__TIME__, __DATE__]); // JVAL change this, how???
  Con_Printf('%4.1f megabyte heap'#10, [parms.memsize / $100000]);

  R_InitTextures; // needed even for dedicated servers

  if cls.state <> ca_dedicated then
  begin
    host_basepal := COM_LoadHunkFile('gfx/palette.lmp');
    if host_basepal = nil then
      Sys_Error('Couldn''t load gfx/palette.lmp');
    host_colormap := COM_LoadHunkFile('gfx/colormap.lmp');
    if host_colormap = nil then
      Sys_Error('Couldn''t load gfx/colormap.lmp');

    VID_Init(host_basepal);

    Draw_Init;
    SCR_Init;
    R_Init;
    S_Init;
    CDAudio_Init;
    Sbar_Init;
    CL_Init;
    IN_Init;
  end;

  Cbuf_InsertText('exec quake.rc'#10);

  Hunk_AllocName(0, '-HOST_HUNKLEVEL-');
  host_hunklevel := Hunk_LowMark;

  host_initialized := true;

  Sys_Printf('========Quake Initialized========='#10);
end;


(*
===============
Host_Shutdown

FIXME: this is a callback from Sys_Quit and Sys_Error.  It would be better
to run quit through here before the final handoff to the sys code.
===============
*)
var
  isdown_Host_Shutdown: qboolean = false;

procedure Host_Shutdown;
begin
  if isdown_Host_Shutdown then
  begin
//    printf('recursive shutdown'#10); JVAL check!!
    exit;
  end;
  isdown_Host_Shutdown := true;

// keep Con_Printf from trying to update the screen
  scr_disabled_for_loading := true;

  Host_WriteConfiguration;

  CDAudio_Shutdown;
  NET_Shutdown;
  S_Shutdown;
  IN_Shutdown;

  if cls.state <> ca_dedicated then
    VID_Shutdown;

  QEX_Shutdown;  
end;


end.

