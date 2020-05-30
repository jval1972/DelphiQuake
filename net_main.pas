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

unit net_main;

// net_main.c

interface

uses
  q_delphi,
  common,
  cvar,
  net;

var
  serialAvailable: qboolean = false;
  ipxAvailable: qboolean = false;
  tcpipAvailable: qboolean = false;

var
  net_message: sizebuf_t;

function NET_SendUnreliableMessage(sock: Pqsocket_t; data: Psizebuf_t): integer;
procedure NET_Slist_f;
procedure NET_Poll;
function NET_GetMessage(sock: Pqsocket_t): integer;
function NET_CanSendMessage(sock: Pqsocket_t): qboolean;
function NET_SendMessage(sock: Pqsocket_t; data: Psizebuf_t): integer;
procedure NET_Close(sock: Pqsocket_t);
function NET_SendToAll(data: Psizebuf_t; blocktime: integer): integer;
procedure NET_Init;
procedure NET_Shutdown;
function NET_CheckNewConnections: Pqsocket_t;
function NET_Connect(host: PChar): Pqsocket_t;
function NET_NewQSocket: Pqsocket_t;
procedure NET_FreeQSocket(sock: Pqsocket_t);

function SetNetTime: double;

procedure SchedulePollProcedure(proc: PPollProcedure_t; timeOffset: double);

var
  hostname: cvar_t = (name: 'hostname'; text: 'UNNAMED');

var
  my_ipx_address: array[0..NET_NAMELEN - 1] of char;
  my_tcpip_address: array[0..NET_NAMELEN - 1] of char;

var
  net_hostport: integer;
  DEFAULTnet_hostport: integer = 26000;

var
  slistInProgress: qboolean = false;
  slistSilent: qboolean = false;
  slistLocal: qboolean = true;

var
  hostcache: array[0..HOSTCACHESIZE - 1] of hostcache_t;
  hostCacheCount: integer = 0;

var
  net_activeconnections: integer = 0;

  messagesSent: integer = 0;
  messagesReceived: integer = 0;
  unreliableMessagesSent: integer = 0;
  unreliableMessagesReceived: integer = 0;

var
  net_time: double;

var
  vcrFile: integer = -1;

var
  net_driverlevel: integer;

var
  net_activeSockets: Pqsocket_t = nil;
  net_freeSockets: Pqsocket_t = nil;

implementation

uses
  net_vcr,
  net_dgrm,
  sys_win,
  sv_main,
  cmd,
  console,
  net_win,
  host_h,
  quakedef,
  cl_main_h,
  client,
  zone;

var
  net_numsockets: integer = 0;

(*
void (*GetComPortConfig) (int portNumber, int *port, int *irq, int *baud, qboolean *useModem);
void (*SetComPortConfig) (int portNumber, int port, int irq, int baud, qboolean useModem);
void (*GetModemConfig) (int portNumber, char *dialType, char *clear, char *init, char *hangup);
void (*SetModemConfig) (int portNumber, char *dialType, char *clear, char *init, char *hangup);
*)

var
  listening: qboolean = false;

var
  slistStartTime: double;
  slistLastShown: integer;

var
  slistSendProcedure: PollProcedure_t;
  slistPollProcedure: PollProcedure_t;

var
  net_messagetimeout: cvar_t = (name: 'net_messagetimeout'; text: '300');

  configRestored: qboolean = false;

  config_com_port: cvar_t = (name: '_config_com_port'; text: '1016' {'0x3f8'}; archive: true);
  config_com_irq: cvar_t = (name: '_config_com_irq'; text: '4'; archive: true);
  config_com_baud: cvar_t = (name: '_config_com_baud'; text: '57600'; archive: true);
  config_com_modem: cvar_t = (name: '_config_com_modem'; text: '1'; archive: true);
  config_modem_dialtype: cvar_t = (name: '_config_modem_dialtype'; text: 'T'; archive: true);
  config_modem_clear: cvar_t = (name: '_config_modem_clear'; text: 'ATZ'; archive: true);
  config_modem_init: cvar_t = (name: '_config_modem_init'; text: ''; archive: true);
  config_modem_hangup: cvar_t = (name: '_config_modem_hangup'; text: 'AT H'; archive: true);

var
  recording: qboolean = false;

function SetNetTime: double;
begin
  net_time := Sys_FloatTime;
  result := net_time;
end;


(*
===================
NET_NewQSocket

Called by drivers when a new communications endpoint is required
The sequence and buffer fields will be filled in properly
===================
*)

function NET_NewQSocket: Pqsocket_t;
var
  sock: Pqsocket_t;
begin
  if net_freeSockets = nil then
  begin
    result := nil;
    exit;
  end;

  if net_activeconnections >= svs.maxclients then
  begin
    result := nil;
    exit;
  end;

  // get one from free list
  sock := net_freeSockets;
  net_freeSockets := sock.next;

  // add it to active list
  sock.next := net_activeSockets;
  net_activeSockets := sock;

  sock.disconnected := false;
  sock.connecttime := net_time;
  Q_strcpy(sock.address, 'UNSET ADDRESS');
  sock.driver := net_driverlevel;
  sock.socket := 0;
  sock.driverdata := nil;
  sock.canSend := true;
  sock.sendNext := false;
  sock.lastMessageTime := net_time;
  sock.ackSequence := 0;
  sock.sendSequence := 0;
  sock.unreliableSendSequence := 0;
  sock.sendMessageLength := 0;
  sock.receiveSequence := 0;
  sock.unreliableReceiveSequence := 0;
  sock.receiveMessageLength := 0;

  result := sock;
end;


procedure NET_FreeQSocket(sock: Pqsocket_t);
var
  s: Pqsocket_t;
begin
  // remove it from active list
  if sock = net_activeSockets then
    net_activeSockets := net_activeSockets.next
  else
  begin
    s := net_activeSockets;
    while s <> nil do
    begin
      if s.next = sock then
      begin
        s.next := sock.next;
        break;
      end;
      s := s.next;
    end;
    if s = nil then
      Sys_Error('NET_FreeQSocket: not active'#10);
  end;

  // add it to free list
  sock.next := net_freeSockets;
  net_freeSockets := sock;
  sock.disconnected := true;
end;


procedure NET_Listen_f;
var
  i: integer;
begin
  if Cmd_Argc_f <> 2 then
  begin
    Con_Printf('"listen" is "%u"'#10, [decide(listening, 1, 0)]);
    exit;
  end;

  listening := decide(Q_atoi(Cmd_Argv_f(1)), true, false);

  for i := 0 to net_numdrivers - 1 do
  begin
    net_driverlevel := i; // JVAL must do this ???
    if not net_drivers[net_driverlevel].initialized then
      continue;
    net_drivers[net_driverlevel].Listen(listening);
  end;
end;


procedure MaxPlayers_f;
var
  n: integer;
begin
  if Cmd_Argc_f <> 2 then
  begin
    Con_Printf('"maxplayers" is "%u"'#10, [svs.maxclients]);
    exit;
  end;

  if sv.active then
  begin
    Con_Printf('maxplayers can not be changed while a server is running.'#10);
    exit;
  end;

  n := Q_atoi(Cmd_Argv_f(1));
  if n < 1 then
    n := 1;
  if n > svs.maxclientslimit then
  begin
    n := svs.maxclientslimit;
    Con_Printf('"maxplayers" set to "%u"'#10, [n]);
  end;

  if (n = 1) and listening then
    Cbuf_AddText('listen 0'#10);

  if (n > 1) and not listening then
    Cbuf_AddText('listen 1'#10);

  svs.maxclients := n;
  if n = 1 then
    Cvar_Set('deathmatch', '0')
  else
    Cvar_Set('deathmatch', '1');
end;


procedure NET_Port_f;
var
  n: integer;
begin
  if Cmd_Argc_f <> 2 then
  begin
    Con_Printf('"port" is "%u"'#10, [net_hostport]);
    exit;
  end;

  n := Q_atoi(Cmd_Argv_f(1));
  if (n < 1) or (n > 65534) then
  begin
    Con_Printf('Bad value, must be between 1 and 65534'#10);
    exit;
  end;

  DEFAULTnet_hostport := n;
  net_hostport := n;

  if listening then
  begin
    // force a change to the new port
    Cbuf_AddText('listen 0'#10);
    Cbuf_AddText('listen 1'#10);
  end;
end;


procedure PrintSlistHeader;
begin
  Con_Printf('Server          Map             Users'#10);
  Con_Printf('--------------- --------------- -----'#10);
  slistLastShown := 0;
end;


procedure PrintSlist;
var
  n: integer;
begin
  n := slistLastShown;
  while n < hostCacheCount do
  begin
    if boolval(hostcache[n].maxusers) then
      Con_Printf('%-15.15s %-15.15s %2u/%2u'#10, [hostcache[n].name, hostcache[n].map, hostcache[n].users, hostcache[n].maxusers])
    else
      Con_Printf('%-15.15s %-15.15s'#10, [hostcache[n].name, hostcache[n].map]);
    inc(n);
  end;
  slistLastShown := n;
end;


procedure PrintSlistTrailer;
begin
  if boolval(hostCacheCount) then
    Con_Printf('== end list =='#10#10)
  else
    Con_Printf('No Quake servers found.'#10#10);
end;


procedure NET_Slist_f;
begin
  if slistInProgress then
    exit;

  if not slistSilent then
  begin
    Con_Printf('Looking for Quake servers...'#10);
    PrintSlistHeader;
  end;

  slistInProgress := true;
  slistStartTime := Sys_FloatTime;

  SchedulePollProcedure(@slistSendProcedure, 0.0);
  SchedulePollProcedure(@slistPollProcedure, 0.1);

  hostCacheCount := 0;
end;


procedure Slist_Send;
label
  continue1;
begin
  net_driverlevel := 0;
  while net_driverlevel < net_numdrivers do
  begin
    if not slistLocal and (net_driverlevel = 0) then
      goto continue1;
    if not net_drivers[net_driverlevel].initialized then
      goto continue1;
    net_drivers[net_driverlevel].SearchForHosts(true);

    continue1:
    inc(net_driverlevel);

  end;

  if (Sys_FloatTime - slistStartTime) < 0.5 then
    SchedulePollProcedure(@slistSendProcedure, 0.75);
end;


procedure Slist_Poll;
label
  continue1;
begin
  net_driverlevel := 0;
  while net_driverlevel < net_numdrivers do
  begin
    if not slistLocal and (net_driverlevel = 0) then
      goto continue1;
    if not net_drivers[net_driverlevel].initialized then
      goto continue1;
    net_drivers[net_driverlevel].SearchForHosts(false);

    continue1:

    inc(net_driverlevel);

  end;

  if not slistSilent then
    PrintSlist;

  if (Sys_FloatTime - slistStartTime) < 1.5 then
  begin
    SchedulePollProcedure(@slistPollProcedure, 0.1);
    exit;
  end;

  if not slistSilent then
    PrintSlistTrailer;
  slistInProgress := false;
  slistSilent := false;
  slistLocal := true;
end;


(*
===================
NET_Connect
===================
*)

function NET_Connect(host: PChar): Pqsocket_t;
label
  JustDoIt;
var
  n: integer;
  numdrivers: integer;
begin
  numdrivers := net_numdrivers;

  SetNetTime;

  if (host <> nil) and (host^ = #0) then
    host := nil;

  if host <> nil then
  begin
    if Q_strcasecmp(host, 'local') = 0 then
    begin
      numdrivers := 1;
      goto JustDoIt;
    end;

    if hostCacheCount <> 0 then
    begin
      n := 0;
      while n < hostCacheCount do
      begin
        if Q_strcasecmp(host, hostcache[n].name) = 0 then
        begin
          host := hostcache[n].cname;
          break;
        end;
        inc(n);
      end;
      if n < hostCacheCount then
        goto JustDoIt;
    end;
  end;

  slistSilent := boolval(host); // JVAL check
  NET_Slist_f;

  while slistInProgress do
    NET_Poll;

  if host = nil then
  begin
    if hostCacheCount <> 1 then
    begin
      result := nil;
      exit;
    end;
    host := hostcache[0].cname;
    Con_Printf('Connecting to...'#10'%s @ %s'#10#10, [hostcache[0].name, host]);
  end;

  if hostCacheCount <> 0 then
    for n := 0 to hostCacheCount - 1 do
      if Q_strcasecmp(host, hostcache[n].name) = 0 then
      begin
        host := hostcache[n].cname;
        break;
      end;

  JustDoIt:
  net_driverlevel := 0;
  while net_driverlevel < numdrivers do
  begin
    if net_drivers[net_driverlevel].initialized then
    begin
      result := net_drivers[net_driverlevel].Connect(host);
      if result <> nil then
        exit;
    end;
    inc(net_driverlevel);
  end;

  if host <> nil then
  begin
    Con_Printf(#10);
    PrintSlistHeader;
    PrintSlist;
    PrintSlistTrailer;
  end;

  result := nil;
end;


(*
===================
NET_CheckNewConnections
===================
*)

type
  vcrConnect_t = record
    time: double;
    op: integer;
    session: integer;
  end;

var
  vcrConnect: vcrConnect_t;

function NET_CheckNewConnections: Pqsocket_t;
label
  continue1;
begin
  SetNetTime;

  net_driverlevel := 0;
  while net_driverlevel < net_numdrivers do
  begin
    if not net_drivers[net_driverlevel].initialized then
      goto continue1;
    if (net_driverlevel <> 0) and not listening then
      goto continue1;
    result := net_drivers[net_driverlevel].CheckNewConnections;
    if result <> nil then
    begin
      if recording then
      begin
        vcrConnect.time := host_time;
        vcrConnect.op := VCR_OP_CONNECT;
        vcrConnect.session := integer(result);
        Sys_FileWrite(vcrFile, @vcrConnect, SizeOf(vcrConnect));
        Sys_FileWrite(vcrFile, @result.address, NET_NAMELEN);
      end;
      exit;
    end;

    continue1:

    inc(net_driverlevel);

  end;

  if recording then
  begin
    vcrConnect.time := host_time;
    vcrConnect.op := VCR_OP_CONNECT;
    vcrConnect.session := 0;
    Sys_FileWrite(vcrFile, @vcrConnect, SizeOf(vcrConnect));
  end;

  result := nil;
end;

(*
===================
NET_Close
===================
*)

procedure NET_Close(sock: Pqsocket_t);
begin
  if sock = nil then
    exit;

  if sock.disconnected then
    exit;

  SetNetTime;

  // call the driver_Close function
  net_drivers[sock.driver].Close(sock);

  NET_FreeQSocket(sock);
end;


(*
=================
NET_GetMessage

If there is a complete message, return it in net_message

returns 0 if no data is waiting
returns 1 if a message was received
returns -1 if connection is invalid
=================
*)

type
  vcrGetMessage_t = record
    time: double;
    op: integer;
    session: integer;
    ret: integer;
    len: integer;
  end;

var
  vcrGetMessage: vcrGetMessage_t;

function NET_GetMessage(sock: Pqsocket_t): integer;
begin
  if sock = nil then
  begin
    result := -1;
    exit;
  end;

  if sock.disconnected then
  begin
    Con_Printf('NET_GetMessage: disconnected socket'#10);
    result := -1;
    exit;
  end;

  SetNetTime;

  result := net_drivers[sock.driver].QGetMessage(sock);

  // see if this connection has timed out
  if (result = 0) and boolval(sock.driver) then
  begin
    if (net_time - sock.lastMessageTime) > net_messagetimeout.value then
    begin
      NET_Close(sock);
      result := -1;
      exit;
    end;
  end;


  if result > 0 then
  begin
    if boolval(sock.driver) then
    begin
      sock.lastMessageTime := net_time;
      if result = 1 then
        inc(messagesReceived)
      else if result = 2 then
        inc(unreliableMessagesReceived);
    end;

    if recording then
    begin
      vcrGetMessage.time := host_time;
      vcrGetMessage.op := VCR_OP_GETMESSAGE;
      vcrGetMessage.session := integer(sock);
      vcrGetMessage.ret := result;
      vcrGetMessage.len := net_message.cursize;
      Sys_FileWrite(vcrFile, @vcrGetMessage, 24);
      Sys_FileWrite(vcrFile, net_message.data, net_message.cursize);
    end;
  end
  else
  begin
    if recording then
    begin
      vcrGetMessage.time := host_time;
      vcrGetMessage.op := VCR_OP_GETMESSAGE;
      vcrGetMessage.session := integer(sock);
      vcrGetMessage.ret := result;
      Sys_FileWrite(vcrFile, @vcrGetMessage, 20);
    end;
  end;

end;


(*
==================
NET_SendMessage

Try to send a complete length+message unit over the reliable stream.
returns 0 if the message cannot be delivered reliably, but the connection
    is still considered valid
returns 1 if the message was sent properly
returns -1 if the connection died
==================
*)

type
  vcrSendMessage_t = record
    time: double;
    op: integer;
    session: integer;
    r: integer;
  end;

var
  vcrSendMessage: vcrSendMessage_t;

function NET_SendMessage(sock: Pqsocket_t; data: Psizebuf_t): integer;
begin
  if sock = nil then
  begin
    result := -1;
    exit;
  end;

  if sock.disconnected then
  begin
    Con_Printf('NET_SendMessage: disconnected socket'#10);
    result := -1;
    exit;
  end;

  SetNetTime;
  result := net_drivers[sock.driver].QSendMessage(sock, data);
  if (result = 1) and boolval(sock.driver) then
    inc(messagesSent);

  if recording then
  begin
    vcrSendMessage.time := host_time;
    vcrSendMessage.op := VCR_OP_SENDMESSAGE;
    vcrSendMessage.session := integer(sock);
    vcrSendMessage.r := result;
    Sys_FileWrite(vcrFile, @vcrSendMessage, 20);
  end;

end;


function NET_SendUnreliableMessage(sock: Pqsocket_t; data: Psizebuf_t): integer;
begin
  if sock = nil then
  begin
    result := -1;
    exit;
  end;

  if sock.disconnected then
  begin
    Con_Printf('NET_SendMessage: disconnected socket'#10);
    result := -1;
    exit;
  end;

  SetNetTime;
  result := net_drivers[sock.driver].SendUnreliableMessage(sock, data);
  if (result = 1) and boolval(sock.driver) then
    inc(unreliableMessagesSent);

  if recording then
  begin
    vcrSendMessage.time := host_time;
    vcrSendMessage.op := VCR_OP_SENDMESSAGE;
    vcrSendMessage.session := integer(sock);
    vcrSendMessage.r := result;
    Sys_FileWrite(vcrFile, @vcrSendMessage, 20);
  end;

end;


(*
==================
NET_CanSendMessage

Returns true or false if the given qsocket can currently accept a
message to be transmitted.
==================
*)

function NET_CanSendMessage(sock: Pqsocket_t): qboolean;
begin
  if sock = nil then // JVAL mayby procvalidsock(sock): qboolean ?
  begin
    result := false;
    exit;
  end;

  if sock.disconnected then
  begin
    result := false;
    exit;
  end;

  SetNetTime;

  result := net_drivers[sock.driver].CanSendMessage(sock);

  if recording then
  begin
    vcrSendMessage.time := host_time;
    vcrSendMessage.op := VCR_OP_CANSENDMESSAGE;
    vcrSendMessage.session := integer(sock);
    vcrSendMessage.r := intval(result);
    Sys_FileWrite(vcrFile, @vcrSendMessage, 20);
  end;

end;


function NET_SendToAll(data: Psizebuf_t; blocktime: integer): integer;
label
  continue1;
var
  start: double;
  i: integer;
  count: integer;
  state1: array[0..MAX_SCOREBOARD - 1] of qboolean;
  state2: array[0..MAX_SCOREBOARD - 1] of qboolean;
begin
  count := 0;

  host_client := @svs.clients[0]; // JVAL check!
  for i := 0 to svs.maxclients - 1 do
  begin
    if not boolval(host_client.netconnection) then
      goto continue1;
    if host_client.active then
    begin
      if host_client.netconnection.driver = 0 then
      begin
        NET_SendMessage(host_client.netconnection, data);
        state1[i] := true;
        state2[i] := true;
        goto continue1;
      end;
      inc(count);
      state1[i] := false;
      state2[i] := false;
    end
    else
    begin
      state1[i] := true;
      state2[i] := true;
    end;
    continue1:
    inc(host_client);
  end;

  start := Sys_FloatTime;
  while count <> 0 do
  begin
    count := 0;
    host_client := @svs.clients[0];
    for i := 0 to svs.maxclients - 1 do
    begin
      if not state1[i] then
      begin
        if NET_CanSendMessage(host_client.netconnection) then
        begin
          state1[i] := true;
          NET_SendMessage(host_client.netconnection, data);
        end
        else
        begin
          NET_GetMessage(host_client.netconnection);
        end;
        inc(count);
      end
      else if not state2[i] then
      begin
        if NET_CanSendMessage(host_client.netconnection) then
        begin
          state2[i] := true;
        end
        else
        begin
          NET_GetMessage(host_client.netconnection);
        end;
        inc(count);
      end;
      inc(host_client);
    end;
    if (Sys_FloatTime - start) > blocktime then
      break;
  end;
  result := count;
end;


//=============================================================================

(*
====================
NET_Init
====================
*)

procedure NET_Init;
var
  i: integer;
  controlSocket: integer;
  s: Pqsocket_t;
begin
  if COM_CheckParm('-playback') <> 0 then
  begin
    net_numdrivers := 1;
    net_drivers[0].Init := VCR_Init;
  end;

  if COM_CheckParm('-record') <> 0 then
    recording := true;

  i := COM_CheckParm('-port');
  if i = 0 then
    i := COM_CheckParm('-udpport');
  if i = 0 then
    i := COM_CheckParm('-ipxport');

  if i <> 0 then
  begin
    if i < com_argc - 1 then
      DEFAULTnet_hostport := Q_atoi(com_argv[i + 1])
    else
      Sys_Error('NET_Init: you must specify a number after -port');
  end;
  net_hostport := DEFAULTnet_hostport;

  if (COM_CheckParm('-listen') <> 0) or (cls.state = ca_dedicated) then
    listening := true;
  net_numsockets := svs.maxclientslimit;
  if cls.state <> ca_dedicated then
    inc(net_numsockets);

  SetNetTime;

  for i := 0 to net_numsockets - 1 do
  begin
    s := Pqsocket_t(Hunk_AllocName(SizeOf(qsocket_t), 'qsocket'));
    s.next := net_freeSockets;
    net_freeSockets := s;
    s.disconnected := true;
  end;

  // allocate space for network message buffer
  SZ_Alloc(@net_message, NET_MAXMESSAGE);

  Cvar_RegisterVariable(@net_messagetimeout);
  Cvar_RegisterVariable(@hostname);
  Cvar_RegisterVariable(@config_com_port);
  Cvar_RegisterVariable(@config_com_irq);
  Cvar_RegisterVariable(@config_com_baud);
  Cvar_RegisterVariable(@config_com_modem);
  Cvar_RegisterVariable(@config_modem_dialtype);
  Cvar_RegisterVariable(@config_modem_clear);
  Cvar_RegisterVariable(@config_modem_init);
  Cvar_RegisterVariable(@config_modem_hangup);
  Cmd_AddCommand('slist', NET_Slist_f);
  Cmd_AddCommand('listen', NET_Listen_f);
  Cmd_AddCommand('maxplayers', MaxPlayers_f);
  Cmd_AddCommand('port', NET_Port_f);

  // initialize all the drivers
  net_driverlevel := 0;
  while net_driverlevel < net_numdrivers do
  begin
    controlSocket := net_drivers[net_driverlevel].Init;
    if controlSocket <> -1 then
    begin
      net_drivers[net_driverlevel].initialized := true;
      net_drivers[net_driverlevel].controlSock := controlSocket;
      if listening then
        net_drivers[net_driverlevel].Listen(true);
    end;
    inc(net_driverlevel);
  end;

  if my_ipx_address[0] <> #0 then
    Con_DPrintf('IPX address %s'#10, [my_ipx_address]);
  if my_tcpip_address[0] <> #0 then
    Con_DPrintf('TCP/IP address %s'#10, [my_tcpip_address]);
end;

(*
====================
NET_Shutdown
====================
*)

procedure NET_Shutdown;
var
  sock: Pqsocket_t;
begin
  SetNetTime;

  sock := net_activeSockets;
  while sock <> nil do
  begin
    NET_Close(sock);
    sock := sock.next;
  end;

//
// shutdown the drivers
//
  net_driverlevel := 0;
  while net_driverlevel < net_numdrivers do
  begin
    if net_drivers[net_driverlevel].initialized then
    begin
      net_drivers[net_driverlevel].Shutdown;
      net_drivers[net_driverlevel].initialized := false;
    end;
    inc(net_driverlevel);
  end;

  if vcrFile <> -1 then
  begin
    Con_Printf('Closing vcrfile.'#10);
    Sys_FileClose(vcrFile);
  end;
end;


var
  pollProcedureList: PPollProcedure_t = nil;

procedure NET_Poll;
var
  pp: PPollProcedure_t;
begin
  if not configRestored then
  begin
    if serialAvailable then
    begin
    // JVAL not serial support!!
      Con_Printf('Serial modem support unavailable'#10);
      serialAvailable := false;
    end;
    configRestored := true;
  end;

  SetNetTime;

  pp := pollProcedureList;
  while pp <> nil do
  begin
    if pp.nextTime > net_time then
      break;
    pollProcedureList := pp.next;
    pp.proc(pp.arg);
    pp := pp.next
  end;
end;


procedure SchedulePollProcedure(proc: PPollProcedure_t; timeOffset: double);
var
  pp, prev: PPollProcedure_t;
begin
  proc.nextTime := Sys_FloatTime + timeOffset;
  prev := nil;
  pp := pollProcedureList;
  while pp <> nil do
  begin
    if pp.nextTime >= proc.nextTime then
      break;
    prev := pp;
    pp := pp.next;
  end;

  if prev = nil then
  begin
    proc.next := pollProcedureList;
    pollProcedureList := proc;
  end
  else
  begin
    proc.next := pp;
    prev.next := proc;
  end;
end;


initialization
  slistSendProcedure.next := nil;
  slistSendProcedure.nextTime := 0.0;
  slistSendProcedure.proc := @Slist_Send;

  slistPollProcedure.next := nil;
  slistPollProcedure.nextTime := 0.0;
  slistPollProcedure.proc := @Slist_Poll;

  pollProcedureList := nil;
end.

