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

unit net_loop;

// net_loop.c

interface

uses
  q_delphi,
  net,
  common,
  net_main;

function Loop_Init: integer;
procedure Loop_Shutdown;
procedure Loop_Listen(state: qboolean);
procedure Loop_SearchForHosts(xmit: qboolean);
function Loop_Connect(host: PChar): Pqsocket_t;
function Loop_CheckNewConnections: Pqsocket_t;
function Loop_GetMessage(sock: Pqsocket_t): integer;
function Loop_SendMessage(sock: Pqsocket_t; data: Psizebuf_t): integer;
function Loop_SendUnreliableMessage(sock: Pqsocket_t; data: Psizebuf_t): integer;
function Loop_CanSendMessage(sock: Pqsocket_t): qboolean;
procedure Loop_Close(sock: Pqsocket_t);
function Loop_CanSendUnreliableMessage(sock: Pqsocket_t): qboolean;

implementation

uses
  cl_main_h,
  client,
  sv_main,
  console,
  sys_win;

var
  localconnectpending: qboolean = false;
  loop_client: Pqsocket_t = nil;
  loop_server: Pqsocket_t = nil;

function Loop_Init: integer;
begin
  if cls.state = ca_dedicated then
    result := -1
  else
    result := 0;
end;


procedure Loop_Shutdown;
begin
end;


procedure Loop_Listen(state: qboolean);
begin
end;


procedure Loop_SearchForHosts(xmit: qboolean);
begin
  if not sv.active then
    exit;

  hostCacheCount := 1;
  if Q_strcmp(hostname.text, 'UNNAMED') = 0 then
    Q_strcpy(hostcache[0].name, 'local')
  else
    Q_strcpy(hostcache[0].name, hostname.text);
  Q_strcpy(hostcache[0].map, sv.name);
  hostcache[0].users := net_activeconnections;
  hostcache[0].maxusers := svs.maxclients;
  hostcache[0].driver := net_driverlevel;
  Q_strcpy(hostcache[0].cname, 'local');
end;


function Loop_Connect(host: PChar): Pqsocket_t;
begin
  if Q_strcmp(host, 'local') <> 0 then
  begin
    result := nil;
    exit;
  end;

  localconnectpending := true;

  if loop_client = nil then
  begin
    loop_client := NET_NewQSocket;
    if loop_client = nil then
    begin
      Con_Printf('Loop_Connect: no qsocket available'#10);
      result := nil;
      exit;
    end;
    Q_strcpy(loop_client.address, 'localhost');
  end;
  loop_client.receiveMessageLength := 0;
  loop_client.sendMessageLength := 0;
  loop_client.canSend := true;

  if loop_server = nil then
  begin
    loop_server := NET_NewQSocket;
    if loop_server = nil then
    begin
      Con_Printf('Loop_Connect: no qsocket available'#10);
      result := nil;
      exit;
    end;
    Q_strcpy(loop_server.address, 'LOCAL');
  end;
  loop_server.receiveMessageLength := 0;
  loop_server.sendMessageLength := 0;
  loop_server.canSend := true;

  loop_client.driverdata := loop_server;
  loop_server.driverdata := loop_client;

  result := loop_client;
end;


function Loop_CheckNewConnections: Pqsocket_t;
begin
  if not localconnectpending then
  begin
    result := nil;
    exit;
  end;

  localconnectpending := false;
  loop_server.sendMessageLength := 0;
  loop_server.receiveMessageLength := 0;
  loop_server.canSend := true;
  loop_client.sendMessageLength := 0;
  loop_client.receiveMessageLength := 0;
  loop_client.canSend := true;
  result := loop_server;
end;


function IntAlign(value: integer): integer;
begin
  result := (value + (SizeOf(integer) - 1)) and (not (SizeOf(integer) - 1));
end;


function Loop_GetMessage(sock: Pqsocket_t): integer;
var
  len: integer;
begin
  if sock.receiveMessageLength = 0 then
  begin
    result := 0;
    exit;
  end;

  result := sock.receiveMessage[0];
  len := sock.receiveMessage[1] + (sock.receiveMessage[2] * 256);
  // alignment byte skipped here
  SZ_Clear(@net_message);
  SZ_Write(@net_message, @sock.receiveMessage[4], len);

  len := IntAlign(len + 4);
  sock.receiveMessageLength := sock.receiveMessageLength - len;

  if boolval(sock.receiveMessageLength) then
    memcpy(@sock.receiveMessage, @sock.receiveMessage[len], sock.receiveMessageLength);

  if boolval(sock.driverdata) and (result = 1) then
    Pqsocket_t(sock.driverdata).canSend := true;

end;


function Loop_SendMessage(sock: Pqsocket_t; data: Psizebuf_t): integer;
var
  buffer: PByte;
  bufferLength: PInteger;
begin
  if not boolval(sock.driverdata) then
  begin
    result := -1;
    exit;
  end;

  bufferLength := @(Pqsocket_t(sock.driverdata).receiveMessageLength);

  if bufferLength^ + data.cursize + 4 > NET_MAXMESSAGE then
    Sys_Error('Loop_SendMessage: overflow'#10);

  buffer := PByte(@Pqsocket_t(sock.driverdata).receiveMessage[bufferLength^]);

  // message type
  buffer^ := 1;
  inc(buffer);

  // length
  buffer^ := data.cursize and $FF;
  inc(buffer);
  buffer^ := data.cursize div 256;
  inc(buffer);

  // align
  inc(buffer);

  // message
  memcpy(buffer, data.data, data.cursize);
  bufferLength^ := IntAlign(bufferLength^ + data.cursize + 4);

  sock.canSend := false;
  result := 1;
end;


function Loop_SendUnreliableMessage(sock: Pqsocket_t; data: Psizebuf_t): integer;
var
  buffer: PByte;
  bufferLength: PInteger;
begin
  if not boolval(sock.driverdata) then
  begin
    result := -1;
    exit;
  end;

  bufferLength := @(Pqsocket_t(sock.driverdata).receiveMessageLength);

  if bufferLength^ + data.cursize + SizeOf(byte) + SizeOf(short) > NET_MAXMESSAGE then
  begin
    result := 0;
    exit;
  end;

  buffer := PByte(@Pqsocket_t(sock.driverdata).receiveMessage[bufferLength^]);

  // message type
  buffer^ := 2;
  inc(buffer);

  // length
  buffer^ := data.cursize and $FF;
  inc(buffer);
  buffer^ := data.cursize div 256;
  inc(buffer);

  // align
  inc(buffer);

  // message
  memcpy(buffer, data.data, data.cursize);
  bufferLength^ := IntAlign(bufferLength^ + data.cursize + 4);
  result := 1;
end;


function Loop_CanSendMessage(sock: Pqsocket_t): qboolean;
begin
  if not boolval(sock.driverdata) then
    result := false
  else
    result := sock.canSend;
end;


function Loop_CanSendUnreliableMessage(sock: Pqsocket_t): qboolean;
begin
  result := true;
end;


procedure Loop_Close(sock: Pqsocket_t);
begin
  if boolval(sock.driverdata) then
    Pqsocket_t(sock.driverdata).driverdata := nil;
  sock.receiveMessageLength := 0;
  sock.sendMessageLength := 0;
  sock.canSend := true;
  if sock = loop_client then
    loop_client := nil
  else
    loop_server := nil;
end;

end.

 