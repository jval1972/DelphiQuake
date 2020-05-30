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

unit net_dgrm;

interface

uses
  q_delphi,
  net,
  common;

function Datagram_SendMessage(sock: Pqsocket_t; data: Psizebuf_t): integer;
function Datagram_CanSendMessage(sock: Pqsocket_t): qboolean;
function Datagram_CanSendUnreliableMessage(sock: Pqsocket_t): qboolean;
function Datagram_SendUnreliableMessage(sock: Pqsocket_t; data: Psizebuf_t): integer;
function Datagram_GetMessage(sock: Pqsocket_t): integer;
function Datagram_Init: integer;
procedure Datagram_Shutdown;
procedure Datagram_Close(sock: Pqsocket_t);
procedure Datagram_Listen(state: qboolean);
function Datagram_CheckNewConnections: Pqsocket_t;
procedure Datagram_SearchForHosts(xmit: qboolean);
function Datagram_Connect(host: PChar): Pqsocket_t;

procedure PrintStats(s: Pqsocket_t);

implementation

uses
  WinSock,
  quakedef,
  cmd,
  sv_main,
  console,
  pr_edict,
  host,
  host_h,
  net_win,
  net_main,
  sys_win,
  server_h,
  cvar,
  gl_screen,
  menu,
  keys;

var
  net_landriverlevel: integer;

var
(* statistic counters *)
  packetsSent: integer = 0;
  packetsReSent: integer = 0;
  packetsReceived: integer = 0;
  receivedDuplicateCount: integer = 0;
  shortPacketCount: integer = 0;
  droppedDatagrams: integer;

var
  myDriverLevel: integer;

type
  packetBuffer_t = record
    length: unsigned_int;
    sequence: unsigned_int;
    data: array[0..MAX_DATAGRAM - 1] of byte;
  end;

var
  packetBuffer: packetBuffer_t;

var
  banAddr: unsigned = $00000000;
  banMask: unsigned = $FFFFFFFF;

procedure NET_Ban_f;
var
  addrStr: array[0..31] of char;
  maskStr: array[0..31] of char;
  print: procedure(str: PChar; const A: array of const);
begin
  if cmd_source = src_command then
  begin
    if sv.active then
    begin
      Cmd_ForwardToServer;
      exit;
    end;
    print := Con_Printf;
  end
  else
  begin
    if boolval(pr_global_struct.deathmatch) and not host_client.privileged then
      exit;
    print := SV_ClientPrintf;
  end;

  case Cmd_Argc_f of
    1:
      begin
        if PInAddr(@banAddr).S_addr <> 0 then
        begin
          Q_strcpy(addrStr, inet_ntoa(PInAddr(@banAddr)^));
          Q_strcpy(maskStr, inet_ntoa(PInAddr(@banMask)^));
          print('Banning %s [%s]'#10, [addrStr, maskStr]);
        end
        else
          print('Banning not active'#10, []);
      end;

    2:
      begin
        if Q_strcasecmp(Cmd_Argv_f(1), 'off') = 0 then
          banAddr := $00000000
        else
          banAddr := inet_addr(Cmd_Argv_f(1));
        banMask := $FFFFFFFF;
      end;

    3:
      begin
        banAddr := inet_addr(Cmd_Argv_f(1));
        banMask := inet_addr(Cmd_Argv_f(2));
      end;

  else
    print('BAN ip_address [mask]'#10, []);
  end;

end;


function Datagram_SendMessage(sock: Pqsocket_t; data: Psizebuf_t): integer;
var
  packetLen: unsigned_int;
  dataLen: unsigned_int;
  eom: unsigned_int;
begin
{$IFDEF DEBUG}
  if data.cursize = 0 then
    Sys_Error('Datagram_SendMessage: zero length message'#10);

  if data.cursize > NET_MAXMESSAGE then
    Sys_Error('Datagram_SendMessage: message too big %u'#10, [data.cursize]);

  if not sock.canSend then
    Sys_Error('SendMessage: called with canSend = false'#10);
{$ENDIF}

  memcpy(@sock.sendMessage, data.data, data.cursize);
  sock.sendMessageLength := data.cursize;

  if data.cursize <= MAX_DATAGRAM then
  begin
    dataLen := data.cursize;
    eom := NETFLAG_EOM;
  end
  else
  begin
    dataLen := MAX_DATAGRAM;
    eom := 0;
  end;
  packetLen := NET_HEADERSIZE + dataLen;

  packetBuffer.length := BigLong(packetLen or (NETFLAG_DATA or eom));
  packetBuffer.sequence := BigLong(sock.sendSequence);
  sock.sendSequence := sock.sendSequence + 1;
  memcpy(@packetBuffer.data, @sock.sendMessage, dataLen);

  sock.canSend := false;

  if net_landrivers[sock.landriver].Write(sock.socket, PByteArray(@packetBuffer), packetLen, @sock.addr) = -1 then
  begin
    result := -1;
    exit;
  end;

  sock.lastSendTime := net_time;
  inc(packetsSent);
  result := 1;
end;


function SendMessageNext(sock: Pqsocket_t): integer;
var
  packetLen: unsigned_int;
  dataLen: unsigned_int;
  eom: unsigned_int;
begin
  if sock.sendMessageLength <= MAX_DATAGRAM then
  begin
    dataLen := sock.sendMessageLength;
    eom := NETFLAG_EOM;
  end
  else
  begin
    dataLen := MAX_DATAGRAM;
    eom := 0;
  end;
  packetLen := NET_HEADERSIZE + dataLen;

  packetBuffer.length := BigLong(packetLen or (NETFLAG_DATA or eom));
  packetBuffer.sequence := BigLong(sock.sendSequence);
  sock.sendSequence := sock.sendSequence + 1;
  memcpy(@packetBuffer.data, @sock.sendMessage, dataLen);

  sock.sendNext := false;

  if net_landrivers[sock.landriver].Write(sock.socket, PByteArray(@packetBuffer), packetLen, @sock.addr) = -1 then
  begin
    result := -1;
    exit;
  end;

  sock.lastSendTime := net_time;
  inc(packetsSent);
  result := 1;
end;


function ReSendMessage(sock: Pqsocket_t): integer;
var
  packetLen: unsigned_int;
  dataLen: unsigned_int;
  eom: unsigned_int;
begin
  if sock.sendMessageLength <= MAX_DATAGRAM then
  begin
    dataLen := sock.sendMessageLength;
    eom := NETFLAG_EOM;
  end
  else
  begin
    dataLen := MAX_DATAGRAM;
    eom := 0;
  end;
  packetLen := NET_HEADERSIZE + dataLen;

  packetBuffer.length := BigLong(packetLen or (NETFLAG_DATA or eom));
  packetBuffer.sequence := BigLong(sock.sendSequence - 1);
  memcpy(@packetBuffer.data, @sock.sendMessage, dataLen);

  sock.sendNext := false;

  if net_landrivers[sock.landriver].Write(sock.socket, PByteArray(@packetBuffer), packetLen, @sock.addr) = -1 then
  begin
    result := -1;
    exit;
  end;

  sock.lastSendTime := net_time;
  inc(packetsReSent);
  result := 1;
end;


function Datagram_CanSendMessage(sock: Pqsocket_t): qboolean;
begin
  if sock.sendNext then
    SendMessageNext(sock);

  result := sock.canSend;
end;


function Datagram_CanSendUnreliableMessage(sock: Pqsocket_t): qboolean;
begin
  result := true;
end;


function Datagram_SendUnreliableMessage(sock: Pqsocket_t; data: Psizebuf_t): integer;
var
  packetLen: integer;
begin
{$IFDEF DEBUG}
  if data.cursize = 0 then
    Sys_Error('Datagram_SendUnreliableMessage: zero length message'#10);

  if data.cursize > MAX_DATAGRAM then
    Sys_Error('Datagram_SendUnreliableMessage: message too big %u'#10, [data.cursize]);
{$ENDIF}

  packetLen := NET_HEADERSIZE + data.cursize;

  packetBuffer.length := BigLong(packetLen or NETFLAG_UNRELIABLE);
  packetBuffer.sequence := BigLong(sock.unreliableSendSequence);
  sock.unreliableSendSequence := sock.unreliableSendSequence + 1;
  memcpy(@packetBuffer.data, data.data, data.cursize);

  if net_landrivers[sock.landriver].Write(sock.socket, PByteArray(@packetBuffer), packetLen, @sock.addr) = -1 then
  begin
    result := -1;
    exit;
  end;

  inc(packetsSent);
  result := 1;
end;


{$IFDEF DEBUG}
var
  buf_StrAddr: array[0..31] of char;

function StrAddr(addr: Pqsockaddr_t): PChar;
var
  p: PByte;
  n: integer;
begin
  p := PByte(addr);

  for n := 0 to 15 do
  begin
    sprintf(@buf[n * 2], '%02x', p^);
    inc(p);
    result := @buf[0];
  end;
{$ENDIF}

function Datagram_GetMessage(sock: Pqsocket_t): integer;
var
  len: integer; // unsigned_int;
  flags: unsigned_int;
  readaddr: qsockaddr_t;
  sequence: unsigned_int;
  count: integer;
begin
  result := 0;
  if not sock.canSend then
    if (net_time - sock.lastSendTime) > 1.0 then
      ReSendMessage(sock);

  while true do
  begin
    len := net_landrivers[sock.landriver].Read(sock.socket, PByteArray(@packetBuffer), NET_DATAGRAMSIZE, @readaddr);

//  if ((rand() & 255) > 220)
//    continue;

    if len = 0 then
      break;

    if len = -1 then
    begin
      Con_Printf('Read error'#10);
      result := -1;
      exit;
    end;

    if net_landrivers[sock.landriver].AddrCompare(@readaddr, @sock.addr) <> 0 then
    begin
{$IFDEF DEBUG}
      Con_DPrintf('Forged packet received'#10);
      Con_DPrintf('Expected: %s'#10, [StrAddr(@sock.addr)]);
      Con_DPrintf('Received: %s'#10, [StrAddr(@readaddr)]);
{$ENDIF}
      continue;
    end;

    if len < NET_HEADERSIZE then
    begin
      inc(shortPacketCount);
      continue;
    end;

    len := BigLong(packetBuffer.length);
    flags := len and (not NETFLAG_LENGTH_MASK);
    len := len and NETFLAG_LENGTH_MASK;

    if flags and NETFLAG_CTL <> 0 then
      continue;

    sequence := BigLong(packetBuffer.sequence);
    inc(packetsReceived);

    if flags and NETFLAG_UNRELIABLE <> 0 then
    begin
      if sequence < sock.unreliableReceiveSequence then
      begin
        Con_DPrintf('Got a stale datagram'#10);
        result := 0;
        break;
      end;
      if sequence <> sock.unreliableReceiveSequence then
      begin
        count := sequence - sock.unreliableReceiveSequence;
        droppedDatagrams := droppedDatagrams + count;
        Con_DPrintf('Dropped %u datagram(s)'#10, [count]);
      end;
      sock.unreliableReceiveSequence := sequence + 1;

      len := len - NET_HEADERSIZE;

      SZ_Clear(@net_message);
      SZ_Write(@net_message, @packetBuffer.data, len);

      result := 2;
      break;
    end;

    if flags and NETFLAG_ACK <> 0 then
    begin
      if sequence <> (sock.sendSequence - 1) then
      begin
        Con_DPrintf('Stale ACK received'#10);
        continue;
      end;
      if sequence = sock.ackSequence then
      begin
        inc(sock.ackSequence);
        if sock.ackSequence <> sock.sendSequence then
          Con_DPrintf('ack sequencing error'#10);
      end
      else
      begin
        Con_DPrintf('Duplicate ACK received'#10);
        continue;
      end;
      sock.sendMessageLength := sock.sendMessageLength - MAX_DATAGRAM;
      if sock.sendMessageLength > 0 then
      begin
        memcpy(@sock.sendMessage, @sock.sendMessage[MAX_DATAGRAM], sock.sendMessageLength);
        sock.sendNext := true;
      end
      else
      begin
        sock.sendMessageLength := 0;
        sock.canSend := true;
      end;
      continue;
    end;

    if flags and NETFLAG_DATA <> 0 then
    begin
      packetBuffer.length := BigLong(NET_HEADERSIZE or NETFLAG_ACK);
      packetBuffer.sequence := BigLong(sequence);
      net_landrivers[sock.landriver].Write(sock.socket, PByteArray(@packetBuffer), NET_HEADERSIZE, @readaddr);

      if sequence <> sock.receiveSequence then
      begin
        inc(receivedDuplicateCount);
        continue;
      end;
      inc(sock.receiveSequence);

      len := len - NET_HEADERSIZE;

      if flags and NETFLAG_EOM <> 0 then
      begin
        SZ_Clear(@net_message);
        SZ_Write(@net_message, @sock.receiveMessage, sock.receiveMessageLength);
        SZ_Write(@net_message, @packetBuffer.data, len);
        sock.receiveMessageLength := 0;

        result := 1;
        break;
      end;

      memcpy(@sock.receiveMessage[sock.receiveMessageLength], @packetBuffer.data, len);
      sock.receiveMessageLength := sock.receiveMessageLength + len;
      continue;
    end;
  end;

  if sock.sendNext then
    SendMessageNext(sock);
end;


procedure PrintStats(s: Pqsocket_t);
begin
  Con_Printf('canSend = %4u   '#10, [s.canSend]);
  Con_Printf('sendSeq = %4u   ', [s.sendSequence]);
  Con_Printf('recvSeq = %4u   '#10, [s.receiveSequence]);
  Con_Printf(#10);
end;

procedure NET_Stats_f;
var
  s: Pqsocket_t;
begin
  if Cmd_Argc_f = 1 then
  begin
    Con_Printf('unreliable messages sent   = %d'#10, [unreliableMessagesSent]);
    Con_Printf('unreliable messages recv   = %d'#10, [unreliableMessagesReceived]);
    Con_Printf('reliable messages sent     = %d'#10, [messagesSent]);
    Con_Printf('reliable messages received = %d'#10, [messagesReceived]);
    Con_Printf('packetsSent                = %d'#10, [packetsSent]);
    Con_Printf('packetsReSent              = %d'#10, [packetsReSent]);
    Con_Printf('packetsReceived            = %d'#10, [packetsReceived]);
    Con_Printf('receivedDuplicateCount     = %d'#10, [receivedDuplicateCount]);
    Con_Printf('shortPacketCount           = %d'#10, [shortPacketCount]);
    Con_Printf('droppedDatagrams           = %d'#10, [droppedDatagrams]);
  end
  else if Q_strcmp(Cmd_Argv_f(1), '*') = 0 then
  begin
    s := net_activeSockets;
    while s <> nil do
    begin
      PrintStats(s);
      s := s.next;
    end;
    s := net_freeSockets;
    while s <> nil do
    begin
      PrintStats(s);
      s := s.next;
    end;
  end
  else
  begin
    s := net_activeSockets;
    while s <> nil do
    begin
      if Q_strcasecmp(Cmd_Argv_f(1), s.address) = 0 then
        break;
      s := s.next;
    end;
    if s = nil then
    begin
      s := net_freeSockets;
      while s <> nil do
      begin
        if Q_strcasecmp(Cmd_Argv_f(1), s.address) = 0 then
          break;
        s := s.next;
      end;
    end;
    if s = nil then
      exit;
    PrintStats(s);
  end;
end;


var
  testInProgress: qboolean = false;
  testPollCount: integer;
  testDriver: integer;
  testSocket: integer;

var
  testPollProcedure: PollProcedure_t;

procedure Test_Poll;
var
  clientaddr: qsockaddr_t;
  control: integer;
  len: integer;
  name: array[0..31] of char;
  address: array[0..63] of char;
  colors: integer;
  frags: integer;
  connectTime: integer;
  pnum: integer;
begin
  net_landriverlevel := testDriver;

  while true do
  begin
    len := net_landrivers[net_landriverlevel].Read(testSocket, net_message.data, net_message.maxsize, @clientaddr);
    if len < SizeOf(integer) then
      break;

    net_message.cursize := len;

    MSG_BeginReading;
    control := BigLong(PInteger(net_message.data)^);
    MSG_ReadLong;
    if control = -1 then
      break;
    if (control and (not NETFLAG_LENGTH_MASK)) <> NETFLAG_CTL then
      break;
    if (control and NETFLAG_LENGTH_MASK) <> len then
      break;

    if MSG_ReadByte <> CCREP_PLAYER_INFO then
      Sys_Error('Unexpected repsonse to Player Info request'#10);

    pnum := MSG_ReadByte; // Read player number
    Q_strcpy(name, MSG_ReadString);
    colors := MSG_ReadLong;
    frags := MSG_ReadLong;
    connectTime := MSG_ReadLong;
    Q_strcpy(address, MSG_ReadString);

    Con_Printf('%s (Player number = %d)'#10'  frags:%3d  colors:%u %u  time:%u'#10'  %s'#10,
      [name, pnum, frags, colors div 16, colors and $0F, connectTime div 60, address]);
  end;

  dec(testPollCount);
  if testPollCount <> 0 then
    SchedulePollProcedure(@testPollProcedure, 0.1)
  else
  begin
    net_landrivers[net_landriverlevel].CloseSocket(testSocket);
    testInProgress := false;
  end;
end;

procedure Test_f;
label
  JustDoIt;
var
  host: PChar;
  n: integer;
  max: integer;
  sendaddr: qsockaddr_t;
begin
  max := MAX_SCOREBOARD;

  if testInProgress then
    exit;

  host := Cmd_Argv_f(1);

  if boolval(host) and boolval(hostCacheCount) then
  begin
    n := 0;
    while n < hostCacheCount do
    begin
      if Q_strcasecmp(host, hostcache[n].name) = 0 then
      begin
        if hostcache[n].driver <> myDriverLevel then
        begin
          inc(n);
          continue;
        end;
        net_landriverlevel := hostcache[n].ldriver;
        max := hostcache[n].maxusers;
        memcpy(@sendaddr, @hostcache[n].addr, SizeOf(qsockaddr_t));
        break;
      end;
      inc(n);
    end;
    if n < hostCacheCount then
      goto JustDoIt;
  end;

  net_landriverlevel := 0;
  while net_landriverlevel < net_numlandrivers do
  begin
    if not net_landrivers[net_landriverlevel].initialized then
    begin
      inc(net_landriverlevel);
      continue;
    end;

    // see if we can resolve the host name
    if net_landrivers[net_landriverlevel].GetAddrFromName(host, @sendaddr) <> -1 then
      break;

    inc(net_landriverlevel);
  end;
  if net_landriverlevel = net_numlandrivers then
    exit;

  JustDoIt:

  testSocket := net_landrivers[net_landriverlevel].OpenSocket(0);
  if testSocket = -1 then
    exit;

  testInProgress := true;
  testPollCount := 20;
  testDriver := net_landriverlevel;

  for n := 0 to max - 1 do
  begin
    SZ_Clear(@net_message);
    // save space for the header, filled in later
    MSG_WriteLong(@net_message, 0);
    MSG_WriteByte(@net_message, CCREQ_PLAYER_INFO);
    MSG_WriteByte(@net_message, n);
    PInteger(net_message.data)^ := BigLong(NETFLAG_CTL or (net_message.cursize and NETFLAG_LENGTH_MASK));
    net_landrivers[net_landriverlevel].Write(testSocket, net_message.data, net_message.cursize, @sendaddr);
  end;
  SZ_Clear(@net_message);
  SchedulePollProcedure(@testPollProcedure, 0.1);
end;

var
  test2InProgress: qboolean = false;
  test2Driver: integer;
  test2Socket: integer;

var
  test2PollProcedure: PollProcedure_t;

procedure Test2_Poll;
label
  Reschedule,
    Error,
    Done;
var
  clientaddr: qsockaddr_t;
  control: integer;
  len: integer;
  name: array[0..255] of char;
  value: array[0..255] of char;
begin
  net_landriverlevel := test2Driver;
  name[0] := #0;

  len := net_landrivers[net_landriverlevel].Read(test2Socket, net_message.data, net_message.maxsize, @clientaddr);
  if len < SizeOf(integer) then
    goto Reschedule;

  net_message.cursize := len;

  MSG_BeginReading;
  control := BigLong(PInteger(net_message.data)^);
  MSG_ReadLong;
  if control = -1 then
    goto Error;
  if (control and (not NETFLAG_LENGTH_MASK)) <> NETFLAG_CTL then
    goto Error;
  if (control and NETFLAG_LENGTH_MASK) <> len then
    goto Error;

  if MSG_ReadByte <> CCREP_RULE_INFO then
    goto Error;

  Q_strcpy(name, MSG_ReadString);
  if name[0] = #0 then
    goto Done;
  Q_strcpy(value, MSG_ReadString);

  Con_Printf('%-16.16s  %-16.16s'#10, [name, value]);

  SZ_Clear(@net_message);
  // save space for the header, filled in later
  MSG_WriteLong(@net_message, 0);
  MSG_WriteByte(@net_message, CCREQ_RULE_INFO);
  MSG_WriteString(@net_message, name);
  PInteger(net_message.data)^ := BigLong(NETFLAG_CTL or (net_message.cursize and NETFLAG_LENGTH_MASK));
  net_landrivers[net_landriverlevel].Write(test2Socket, net_message.data, net_message.cursize, @clientaddr);
  SZ_Clear(@net_message);

  Reschedule:
  SchedulePollProcedure(@test2PollProcedure, 0.05);
  exit;

  Error:
  Con_Printf('Unexpected repsonse to Rule Info request'#10);
  Done:
  net_landrivers[net_landriverlevel].CloseSocket(test2Socket);
  test2InProgress := false;
  exit;
end;

procedure Test2_f;
label
  JustDoIt;
var
  host: PChar;
  n: integer;
  sendaddr: qsockaddr_t;
begin
  if test2InProgress then
    exit;

  host := Cmd_Argv_f(1);

  if (host <> nil) and boolval(hostCacheCount) then
  begin
    n := 0;
    while n < hostCacheCount do
    begin
      if Q_strcasecmp(host, hostcache[n].name) = 0 then
      begin
        if hostcache[n].driver <> myDriverLevel then
        begin
          inc(n);
          continue;
        end;
        net_landriverlevel := hostcache[n].ldriver;
        memcpy(@sendaddr, @hostcache[n].addr, SizeOf(qsockaddr_t));
        break;
      end;
      inc(n);
    end;
    if n < hostCacheCount then
      goto JustDoIt;
  end;

  net_landriverlevel := 0;
  while net_landriverlevel < net_numlandrivers do
  begin
    if not net_landrivers[net_landriverlevel].initialized then
    begin
      inc(net_landriverlevel);
      continue;
    end;

    // see if we can resolve the host name
    if net_landrivers[net_landriverlevel].GetAddrFromName(host, @sendaddr) <> -1 then
      break;

    inc(net_landriverlevel);
  end;
  if net_landriverlevel = net_numlandrivers then
    exit;

  JustDoIt:
  test2Socket := net_landrivers[net_landriverlevel].OpenSocket(0);
  if test2Socket = -1 then
    exit;

  test2InProgress := true;
  test2Driver := net_landriverlevel;

  SZ_Clear(@net_message);
  // save space for the header, filled in later
  MSG_WriteLong(@net_message, 0);
  MSG_WriteByte(@net_message, CCREQ_RULE_INFO);
  MSG_WriteString(@net_message, '');
  PInteger(net_message.data)^ := BigLong(NETFLAG_CTL or (net_message.cursize and NETFLAG_LENGTH_MASK));
  net_landrivers[net_landriverlevel].Write(test2Socket, net_message.data, net_message.cursize, @sendaddr);
  SZ_Clear(@net_message);
  SchedulePollProcedure(@test2PollProcedure, 0.05);
end;


function Datagram_Init: integer;
var
  i: integer;
  csock: integer;
begin
  myDriverLevel := net_driverlevel;
  Cmd_AddCommand('net_stats', NET_Stats_f);

  if COM_CheckParm('-nolan') <> 0 then
  begin
    result := -1;
    exit;
  end;

  for i := 0 to net_numlandrivers - 1 do
  begin
    csock := net_landrivers[i].Init;
    if csock <> -1 then
    begin
      net_landrivers[i].initialized := true;
      net_landrivers[i].controlSock := csock;
    end;
  end;

  Cmd_AddCommand('ban', NET_Ban_f);
  Cmd_AddCommand('test', Test_f);
  Cmd_AddCommand('test2', Test2_f);

  result := 0;
end;


procedure Datagram_Shutdown;
var
  i: integer;
begin
//
// shutdown the lan drivers
//
  for i := 0 to net_numlandrivers - 1 do
  begin
    if net_landrivers[i].initialized then
    begin
      net_landrivers[i].Shutdown;
      net_landrivers[i].initialized := false;
    end;
  end;
end;


procedure Datagram_Close(sock: Pqsocket_t);
begin
  net_landrivers[sock.landriver].CloseSocket(sock.socket);
end;


procedure Datagram_Listen(state: qboolean);
var
  i: integer;
begin
  for i := 0 to net_numlandrivers - 1 do
    if net_landrivers[i].initialized then
      net_landrivers[i].Listen(state);
end;


function _Datagram_CheckNewConnections: Pqsocket_t;
var
  clientaddr: qsockaddr_t;
  newaddr: qsockaddr_t;
  newsock: integer;
  acceptsock: integer;
  sock: Pqsocket_t;
  s: Pqsocket_t;
  len: integer;
  ret: integer;
  command: integer;
  control: integer;
  playerNumber: integer;
  activeNumber: integer;
  clientNumber: integer;
  client: Pclient_t;

  prevCvarName: PChar;
  pvar: Pcvar_t;

  testAddr: unsigned_int;
begin
  acceptsock := net_landrivers[net_landriverlevel].CheckNewConnections;
  if acceptsock = -1 then
  begin
    result := nil;
    exit;
  end;

  SZ_Clear(@net_message);

  len := net_landrivers[net_landriverlevel].Read(acceptsock, net_message.data, net_message.maxsize, @clientaddr);
  if len < SizeOf(integer) then
  begin
    result := nil;
    exit;
  end;
  net_message.cursize := len;

  MSG_BeginReading;
  control := BigLong(PInteger(net_message.data)^);
  MSG_ReadLong;
  if control = -1 then
  begin
    result := nil;
    exit;
  end;
  if (control and (not NETFLAG_LENGTH_MASK)) <> NETFLAG_CTL then
  begin
    result := nil;
    exit;
  end;
  if (control and NETFLAG_LENGTH_MASK) <> len then
  begin
    result := nil;
    exit;
  end;

  command := MSG_ReadByte;
  if command = CCREQ_SERVER_INFO then
  begin
    if Q_strcmp(MSG_ReadString, 'QUAKE') <> 0 then
    begin
      result := nil;
      exit;
    end;

    SZ_Clear(@net_message);
    // save space for the header, filled in later
    MSG_WriteLong(@net_message, 0);
    MSG_WriteByte(@net_message, CCREP_SERVER_INFO);
    net_landrivers[net_landriverlevel].GetSocketAddr(acceptsock, @newaddr);
    MSG_WriteString(@net_message, net_landrivers[net_landriverlevel].AddrToString(@newaddr));
    MSG_WriteString(@net_message, hostname.text);
    MSG_WriteString(@net_message, sv.name);
    MSG_WriteByte(@net_message, net_activeconnections);
    MSG_WriteByte(@net_message, svs.maxclients);
    MSG_WriteByte(@net_message, NET_PROTOCOL_VERSION);
    PInteger(net_message.data)^ := BigLong(NETFLAG_CTL or (net_message.cursize and NETFLAG_LENGTH_MASK));
    net_landrivers[net_landriverlevel].Write(acceptsock, net_message.data, net_message.cursize, @clientaddr);
    SZ_Clear(@net_message);
    result := nil;
    exit;
  end;

  if command = CCREQ_PLAYER_INFO then
  begin
    playerNumber := MSG_ReadByte;
    activeNumber := -1;
    clientNumber := 0;
    client := @svs.clients[0]; // JVAL check!
    while clientNumber < svs.maxclients do
    begin
      if client.active then
      begin
        inc(activeNumber);
        if activeNumber = playerNumber then
          break;
      end;
      inc(clientNumber);
      inc(client);
    end;
    if clientNumber = svs.maxclients then
    begin
      result := nil;
      exit;
    end;

    SZ_Clear(@net_message);
    // save space for the header, filled in later
    MSG_WriteLong(@net_message, 0);
    MSG_WriteByte(@net_message, CCREP_PLAYER_INFO);
    MSG_WriteByte(@net_message, playerNumber);
    MSG_WriteString(@net_message, client.name);
    MSG_WriteLong(@net_message, client.colors);
    MSG_WriteLong(@net_message, intval(client.edict.v.frags));
    MSG_WriteLong(@net_message, intval(net_time - client.netconnection.connecttime));
    MSG_WriteString(@net_message, client.netconnection.address);
    PInteger(net_message.data)^ := BigLong(NETFLAG_CTL or (net_message.cursize and NETFLAG_LENGTH_MASK));
    net_landrivers[net_landriverlevel].Write(acceptsock, net_message.data, net_message.cursize, @clientaddr);
    SZ_Clear(@net_message);

    result := nil;
    exit;
  end;

  if command = CCREQ_RULE_INFO then
  begin

    // find the search start location
    prevCvarName := MSG_ReadString;
    if prevCvarName^ <> #0 then
    begin
      pvar := Cvar_FindVar(prevCvarName);
      if pvar = nil then
      begin
        result := nil;
        exit;
      end;
      pvar := pvar.next;
    end
    else
      pvar := cvar_vars;

    // search for the next server cvar
    while pvar <> nil do
    begin
      if pvar.server then
        break;
      pvar := pvar.next;
    end;

    // send the response

    SZ_Clear(@net_message);
    // save space for the header, filled in later
    MSG_WriteLong(@net_message, 0);
    MSG_WriteByte(@net_message, CCREP_RULE_INFO);
    if pvar <> nil then
    begin
      MSG_WriteString(@net_message, pvar.name);
      MSG_WriteString(@net_message, pvar.text);
    end;
    PInteger(net_message.data)^ := BigLong(NETFLAG_CTL or (net_message.cursize and NETFLAG_LENGTH_MASK));
    net_landrivers[net_landriverlevel].Write(acceptsock, net_message.data, net_message.cursize, @clientaddr);
    SZ_Clear(@net_message);

    result := nil;
    exit;
  end;

  if command <> CCREQ_CONNECT then
  begin
    result := nil;
    exit;
  end;

  if Q_strcmp(MSG_ReadString, 'QUAKE') <> 0 then
  begin
    result := nil;
    exit;
  end;

  if MSG_ReadByte <> NET_PROTOCOL_VERSION then
  begin
    SZ_Clear(@net_message);
    // save space for the header, filled in later
    MSG_WriteLong(@net_message, 0);
    MSG_WriteByte(@net_message, CCREP_REJECT);
    MSG_WriteString(@net_message, 'Incompatible version.'#10);
    PInteger(net_message.data)^ := BigLong(NETFLAG_CTL or (net_message.cursize and NETFLAG_LENGTH_MASK));
    net_landrivers[net_landriverlevel].Write(acceptsock, net_message.data, net_message.cursize, @clientaddr);
    SZ_Clear(@net_message);

    result := nil;
    exit;
  end;

  // check for a ban
  if clientaddr.sa_family = AF_INET then
  begin
    testAddr := PSockAddrIn(@clientaddr).sin_addr.s_addr;
    if (testAddr and banMask) = banAddr then
    begin
      SZ_Clear(@net_message);
      // save space for the header, filled in later
      MSG_WriteLong(@net_message, 0);
      MSG_WriteByte(@net_message, CCREP_REJECT);
      MSG_WriteString(@net_message, 'You have been banned.'#10);
      PInteger(net_message.data)^ := BigLong(NETFLAG_CTL or (net_message.cursize and NETFLAG_LENGTH_MASK));
      net_landrivers[net_landriverlevel].Write(acceptsock, net_message.data, net_message.cursize, @clientaddr);
      SZ_Clear(@net_message);

      result := nil;
      exit;
    end;
  end;

  // see if this guy is already connected
  s := net_activeSockets; // JVAL check
  while s <> nil do
  begin
    if s.driver <> net_driverlevel then
    begin
      s := s.next;
      continue;
    end;
    ret := net_landrivers[net_landriverlevel].AddrCompare(@clientaddr, @s.addr);
    if ret >= 0 then
    begin
      // is this a duplicate connection reqeust?
      if (ret = 0) and (net_time - s.connecttime < 2.0) then
      begin
        // yes, so send a duplicate reply
        SZ_Clear(@net_message);
        // save space for the header, filled in later
        MSG_WriteLong(@net_message, 0);
        MSG_WriteByte(@net_message, CCREP_ACCEPT);
        net_landrivers[net_landriverlevel].GetSocketAddr(s.socket, @newaddr);
        MSG_WriteLong(@net_message, net_landrivers[net_landriverlevel].GetSocketPort(@newaddr));
        PInteger(net_message.data)^ := BigLong(NETFLAG_CTL or (net_message.cursize and NETFLAG_LENGTH_MASK));
        net_landrivers[net_landriverlevel].Write(acceptsock, net_message.data, net_message.cursize, @clientaddr);
        SZ_Clear(@net_message);

        result := nil;
        exit;
      end;
      // it's somebody coming back in from a crash/disconnect
      // so close the old qsocket and let their retry get them back in
      NET_Close(s);

      result := nil;
      exit;

    end;
    s := s.next;
  end;

  // allocate a QSocket
  sock := NET_NewQSocket;
  if sock = nil then
  begin
    // no room; try to let him know
    SZ_Clear(@net_message);
    // save space for the header, filled in later
    MSG_WriteLong(@net_message, 0);
    MSG_WriteByte(@net_message, CCREP_REJECT);
    MSG_WriteString(@net_message, 'Server is full.'#10);
    PInteger(net_message.data)^ := BigLong(NETFLAG_CTL or (net_message.cursize and NETFLAG_LENGTH_MASK));
    net_landrivers[net_landriverlevel].Write(acceptsock, net_message.data, net_message.cursize, @clientaddr);
    SZ_Clear(@net_message);

    result := nil;
    exit;
  end;

  // allocate a network socket
  newsock := net_landrivers[net_landriverlevel].OpenSocket(0);
  if newsock = -1 then
  begin
    NET_FreeQSocket(sock);

    result := nil;
    exit;
  end;

  // connect to the client
  if net_landrivers[net_landriverlevel].Connect(newsock, @clientaddr) = -1 then
  begin
    net_landrivers[net_landriverlevel].CloseSocket(newsock);
    NET_FreeQSocket(sock);

    result := nil;
    exit;
  end;

  // everything is allocated, just fill in the details
  sock.socket := newsock;
  sock.landriver := net_landriverlevel;
  sock.addr := clientaddr;
  Q_strcpy(sock.address, net_landrivers[net_landriverlevel].AddrToString(@clientaddr));

  // send him back the info about the server connection he has been allocated
  SZ_Clear(@net_message);
  // save space for the header, filled in later
  MSG_WriteLong(@net_message, 0);
  MSG_WriteByte(@net_message, CCREP_ACCEPT);
  net_landrivers[net_landriverlevel].GetSocketAddr(newsock, @newaddr);
  MSG_WriteLong(@net_message, net_landrivers[net_landriverlevel].GetSocketPort(@newaddr));
//  MSG_WriteString(&net_message, net_landrivers[net_landriverlevel].AddrToString(&newaddr));
  PInteger(net_message.data)^ := BigLong(NETFLAG_CTL or (net_message.cursize and NETFLAG_LENGTH_MASK));
  net_landrivers[net_landriverlevel].Write(acceptsock, net_message.data, net_message.cursize, @clientaddr);
  SZ_Clear(@net_message);

  result := sock;
end;

function Datagram_CheckNewConnections: Pqsocket_t;
begin
  result := nil;
  net_landriverlevel := 0;
  while net_landriverlevel < net_numlandrivers do
  begin
    if net_landrivers[net_landriverlevel].initialized then
    begin
      result := _Datagram_CheckNewConnections;
      if result <> nil then
        break;
    end;
    inc(net_landriverlevel);
  end;
end;

procedure _Datagram_SearchForHosts(xmit: qboolean);
var
  ret: integer;
  n: integer;
  i: integer;
  readaddr: qsockaddr_t;
  myaddr: qsockaddr_t;
  control: integer;

  function _get_ret: integer;
  begin
    ret := net_landrivers[net_landriverlevel].Read(net_landrivers[net_landriverlevel].controlSock,
      net_message.data, net_message.maxsize, @readaddr);
    result := ret;
  end;

begin
  net_landrivers[net_landriverlevel].GetSocketAddr(net_landrivers[net_landriverlevel].controlSock, @myaddr);
  if xmit then
  begin
    SZ_Clear(@net_message);
    // save space for the header, filled in later
    MSG_WriteLong(@net_message, 0);
    MSG_WriteByte(@net_message, CCREQ_SERVER_INFO);
    MSG_WriteString(@net_message, 'QUAKE');
    MSG_WriteByte(@net_message, NET_PROTOCOL_VERSION);
    PInteger(net_message.data)^ := BigLong(NETFLAG_CTL or (net_message.cursize and NETFLAG_LENGTH_MASK));
    net_landrivers[net_landriverlevel].Broadcast(net_landrivers[net_landriverlevel].controlSock, net_message.data, net_message.cursize);
    SZ_Clear(@net_message);
  end;

  while _get_ret > 0 do
  begin
    if ret < SizeOf(integer) then
      continue;
    net_message.cursize := ret;

    // don't answer our own query
    if net_landrivers[net_landriverlevel].AddrCompare(@readaddr, @myaddr) >= 0 then
      continue;

    // is the cache full?
    if hostCacheCount = HOSTCACHESIZE then
      continue;

    MSG_BeginReading;
    control := BigLong(PInteger(net_message.data)^);
    MSG_ReadLong;
    if control = -1 then
      continue;
    if (control and (not NETFLAG_LENGTH_MASK)) <> NETFLAG_CTL then
      continue;
    if (control and NETFLAG_LENGTH_MASK) <> ret then
      continue;

    if MSG_ReadByte <> CCREP_SERVER_INFO then
      continue;

    net_landrivers[net_landriverlevel].GetAddrFromName(MSG_ReadString, @readaddr);
    // search the cache for this server
    n := 0;
    while n < hostCacheCount do
    begin
      if net_landrivers[net_landriverlevel].AddrCompare(@readaddr, @hostcache[n].addr) = 0 then
        break;
      inc(n);
    end;

    // is it already there?
    if n < hostCacheCount then
      continue;

    // add it
    inc(hostCacheCount);
    Q_strcpy(hostcache[n].name, MSG_ReadString);
    Q_strcpy(hostcache[n].map, MSG_ReadString);
    hostcache[n].users := MSG_ReadByte;
    hostcache[n].maxusers := MSG_ReadByte;
    if MSG_ReadByte <> NET_PROTOCOL_VERSION then
    begin
      Q_strcpy(hostcache[n].cname, hostcache[n].name);
      hostcache[n].cname[14] := #0;
      Q_strcpy(hostcache[n].name, '*');
      Q_strcat(hostcache[n].name, hostcache[n].cname);
    end;
    memcpy(@hostcache[n].addr, @readaddr, SizeOf(qsockaddr_t));
    hostcache[n].driver := net_driverlevel;
    hostcache[n].ldriver := net_landriverlevel;
    Q_strcpy(hostcache[n].cname, net_landrivers[net_landriverlevel].AddrToString(@readaddr));

    // check for a name conflict
    i := 0;
    while i < hostCacheCount do
    begin
      if i = n then
      begin
        inc(i);
        continue;
      end;
      if Q_strcasecmp(hostcache[n].name, hostcache[i].name) = 0 then
      begin
        i := Q_strlen(hostcache[n].name);
        if (i < 15) and (hostcache[n].name[i - 1] > '8') then
        begin
          hostcache[n].name[i] := '0';
          hostcache[n].name[i + 1] := #0;
        end
        else
          hostcache[n].name[i - 1] := Chr(Ord(hostcache[n].name[i - 1]) + 1);
        i := -1;
      end;
      inc(i);
    end;
  end;
end;

procedure Datagram_SearchForHosts(xmit: qboolean);
begin
  net_landriverlevel := 0;
  while net_landriverlevel < net_numlandrivers do
  begin
    if hostCacheCount = HOSTCACHESIZE then
      break;
    if net_landrivers[net_landriverlevel].initialized then
      _Datagram_SearchForHosts(xmit);
    inc(net_landriverlevel);
  end;
end;


function _Datagram_Connect(host: PChar): Pqsocket_t;
label
  ErrorReturn,
    ErrorReturn2;
var
  sendaddr: qsockaddr_t;
  readaddr: qsockaddr_t;
  sock: Pqsocket_t;
  newsock: integer;
  ret: integer;
  reps: integer;
  start_time: double;
  control: integer;
  reason: PChar;
begin
  // see if we can resolve the host name
  if net_landrivers[net_landriverlevel].GetAddrFromName(host, @sendaddr) = -1 then
  begin
    result := nil;
    exit;
  end;

  newsock := net_landrivers[net_landriverlevel].OpenSocket(0);
  if newsock = -1 then
  begin
    result := nil;
    exit;
  end;

  sock := NET_NewQSocket;
  if sock = nil then
    goto ErrorReturn2;
  sock.socket := newsock;
  sock.landriver := net_landriverlevel;

  // connect to the host
  if net_landrivers[net_landriverlevel].Connect(newsock, @sendaddr) = -1 then
    goto ErrorReturn;

  // send the connection request
  Con_Printf('trying...'#10);
  SCR_UpdateScreen;
  start_time := net_time;

  for reps := 0 to 2 do
  begin
    SZ_Clear(@net_message);
    // save space for the header, filled in later
    MSG_WriteLong(@net_message, 0);
    MSG_WriteByte(@net_message, CCREQ_CONNECT);
    MSG_WriteString(@net_message, 'QUAKE');
    MSG_WriteByte(@net_message, NET_PROTOCOL_VERSION);
    PInteger(net_message.data)^ := BigLong(NETFLAG_CTL or (net_message.cursize and NETFLAG_LENGTH_MASK));
    net_landrivers[net_landriverlevel].Write(newsock, net_message.data, net_message.cursize, @sendaddr);
    SZ_Clear(@net_message);
    repeat
      ret := net_landrivers[net_landriverlevel].Read(newsock, net_message.data, net_message.maxsize, @readaddr);
      // if we got something, validate it
      if ret > 0 then
      begin
        // is it from the right place?
        if net_landrivers[sock.landriver].AddrCompare(@readaddr, @sendaddr) <> 0 then
        begin
{$IFDEF DEBUG}
          Con_Printf('wrong reply address'#10);
          Con_Printf('Expected: %s'#10, StrAddr(@sendaddr));
          Con_Printf('Received: %s'#10, StrAddr(@readaddr));
          SCR_UpdateScreen;
{$ENDIF}
          ret := 0;
          continue;
        end;

        if ret < SizeOf(integer) then
        begin
          ret := 0;
          continue;
        end;

        net_message.cursize := ret;
        MSG_BeginReading;

        control := BigLong(PInteger(net_message.data)^);
        MSG_ReadLong;
        if control = -1 then
        begin
          ret := 0;
          continue;
        end;
        if (control and (not NETFLAG_LENGTH_MASK)) <> NETFLAG_CTL then
        begin
          ret := 0;
          continue;
        end;
        if (control and NETFLAG_LENGTH_MASK) <> ret then
        begin
          ret := 0;
          continue;
        end;
      end;
    until not ((ret = 0) and (SetNetTime - start_time < 2.5));
    if ret <> 0 then
      break;
    Con_Printf('still trying...'#10);
    SCR_UpdateScreen;
    start_time := SetNetTime;
  end;

  if ret = 0 then
  begin
    reason := 'No Response';
    Con_Printf('%s'#10, [reason]);
    Q_strcpy(@m_return_reason, reason);
    goto ErrorReturn;
  end;

  if ret = -1 then
  begin
    reason := 'Network Error';
    Con_Printf('%s'#10, [reason]);
    Q_strcpy(m_return_reason, reason);
    goto ErrorReturn;
  end;

  ret := MSG_ReadByte;
  if ret = CCREP_REJECT then
  begin
    reason := MSG_ReadString;
    Con_Printf(reason);
    Q_strncpy(m_return_reason, reason, 31);
    goto ErrorReturn;
  end;

  if ret = CCREP_ACCEPT then
  begin
    memcpy(@sock.addr, @sendaddr, SizeOf(qsockaddr_t));
    net_landrivers[net_landriverlevel].SetSocketPort(@sock.addr, MSG_ReadLong);
  end
  else
  begin
    reason := 'Bad Response';
    Con_Printf('%s'#10, [reason]);
    Q_strcpy(m_return_reason, reason);
    goto ErrorReturn;
  end;

  net_landrivers[net_landriverlevel].GetNameFromAddr(@sendaddr, sock.address);

  Con_Printf('Connection accepted'#10);
  sock.lastMessageTime := SetNetTime;

  // switch the connection to the specified address
  if net_landrivers[net_landriverlevel].Connect(newsock, @sock.addr) = -1 then
  begin
    reason := 'Connect to Game failed';
    Con_Printf('%s'#10, [reason]);
    Q_strcpy(m_return_reason, reason);
    goto ErrorReturn;
  end;

  m_return_onerror := false;
  result := sock;
  exit;

  ErrorReturn:
  NET_FreeQSocket(sock);

  ErrorReturn2:

  net_landrivers[net_landriverlevel].CloseSocket(newsock);
  if m_return_onerror then
  begin
    key_dest := key_menu;
    m_state := m_return_state;
    m_return_onerror := false;
  end;
  result := nil;
end;

function Datagram_Connect(host: PChar): Pqsocket_t;
begin
  result := nil;
  net_landriverlevel := 0;
  while net_landriverlevel < net_numlandrivers do
  begin
    if net_landrivers[net_landriverlevel].initialized then
    begin
      result := _Datagram_Connect(host);
      if result <> nil then
        break;
    end;
    inc(net_landriverlevel);
  end;
end;


initialization

  testPollProcedure.next := nil;
  testPollProcedure.nextTime := 0.0;
  testPollProcedure.proc := @Test_Poll;

  test2PollProcedure.next := nil;
  test2PollProcedure.nextTime := 0.0;
  test2PollProcedure.proc := @Test2_Poll;


end.

