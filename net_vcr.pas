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

unit net_vcr;

interface

uses
  q_delphi,
  net,
  common;

const
  VCR_OP_CONNECT = 1;
  VCR_OP_GETMESSAGE = 2;
  VCR_OP_SENDMESSAGE = 3;
  VCR_OP_CANSENDMESSAGE = 4;
  VCR_MAX_MESSAGE = 4;

function VCR_Init: integer;
procedure VCR_ReadNext;
procedure VCR_Listen(state: qboolean);
procedure VCR_Shutdown;
function VCR_GetMessage(sock: Pqsocket_t): integer;
function VCR_SendMessage(sock: Pqsocket_t; data: Psizebuf_t): integer;
function VCR_CanSendMessage(sock: Pqsocket_t): qboolean;
procedure VCR_Close(sock: Pqsocket_t);
procedure VCR_SearchForHosts(xmit: qboolean);
function VCR_Connect(host: PChar): Pqsocket_t;
function VCR_CheckNewConnections: Pqsocket_t;

implementation

uses
  net_win,
  sys_win,
  net_main,
  host_h;

// This is the playback portion of the VCR.  It reads the file produced
// by the recorder and plays it back to the host.  The recording contains
// everything necessary (events, timestamps, and data) to duplicate the game
// from the viewpoint of everything above the network layer.

type
  next_t = record
    time: double;
    op: integer;
    session: integer;
  end;

var
  next: next_t;

function VCR_Init: integer;
begin
  net_drivers[0].Init := @VCR_Init;

  net_drivers[0].SearchForHosts := @VCR_SearchForHosts;
  net_drivers[0].Connect := @VCR_Connect;
  net_drivers[0].CheckNewConnections := @VCR_CheckNewConnections;
  net_drivers[0].QGetMessage := @VCR_GetMessage;
  net_drivers[0].QSendMessage := @VCR_SendMessage;
  net_drivers[0].CanSendMessage := @VCR_CanSendMessage;
  net_drivers[0].Close := @VCR_Close;
  net_drivers[0].Shutdown := @VCR_Shutdown;

  Sys_FileRead(vcrFile, @next, SizeOf(next));

  result := 0;
end;

procedure VCR_ReadNext;
begin
  if Sys_FileRead(vcrFile, @next, SizeOf(next)) = 0 then
  begin
    next.op := 255;
    Sys_Error('=== END OF PLAYBACK==='#10);
  end;
  if (next.op < 1) or (next.op > VCR_MAX_MESSAGE) then
    Sys_Error('VCR_ReadNext: bad op');
end;


procedure VCR_Listen(state: qboolean);
begin
end;

procedure VCR_Shutdown;
begin
end;


function VCR_GetMessage(sock: Pqsocket_t): integer;
begin
  if (host_time <> next.time) or (next.op <> VCR_OP_GETMESSAGE) or (next.session <> PInteger(@sock.driverdata)^) then
    Sys_Error('VCR missmatch');

  Sys_FileRead(vcrFile, @result, SizeOf(integer));
  if result <> 1 then
  begin
    VCR_ReadNext;
    exit;
  end;

  Sys_FileRead(vcrFile, @net_message.cursize, SizeOf(integer));
  Sys_FileRead(vcrFile, net_message.data, net_message.cursize);

  VCR_ReadNext;

  result := 1;
end;


function VCR_SendMessage(sock: Pqsocket_t; data: Psizebuf_t): integer;
begin
  if (host_time <> next.time) or (next.op <> VCR_OP_SENDMESSAGE) or (next.session <> PInteger(@sock.driverdata)^) then
    Sys_Error('VCR missmatch');

  Sys_FileRead(vcrFile, @result, SizeOf(integer));

  VCR_ReadNext;
end;

function VCR_CanSendMessage(sock: Pqsocket_t): qboolean;
begin
  if (host_time <> next.time) or (next.op <> VCR_OP_CANSENDMESSAGE) or (next.session <> PInteger(@sock.driverdata)^) then
    Sys_Error('VCR missmatch');

  Sys_FileRead(vcrFile, @result, SizeOf(integer));

  VCR_ReadNext;
end;

procedure VCR_Close(sock: Pqsocket_t);
begin
end;

procedure VCR_SearchForHosts(xmit: qboolean);
begin
end;


function VCR_Connect(host: PChar): Pqsocket_t;
begin
  result := nil;
end;


function VCR_CheckNewConnections: Pqsocket_t;
begin
  if (host_time <> next.time) or (next.op <> VCR_OP_CONNECT) then
    Sys_Error('VCR missmatch');

  if next.session = 0 then
  begin
    VCR_ReadNext;
    result := nil;
    exit;
  end;

  result := NET_NewQSocket;
  PInteger(@result.driverdata)^ := next.session;

  Sys_FileRead(vcrFile, @result.address, NET_NAMELEN);
  VCR_ReadNext;
end;


end.

