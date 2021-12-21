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

unit net_wins;

interface

// net_wins.c

uses
  q_delphi,
  net,
  WinSock;


var
  winsock_initialized: integer = 0;
  winsockdata: WSADATA;


procedure WINS_GetLocalAddress;
function WINS_Init: integer;
procedure WINS_Shutdown;
procedure WINS_Listen(state: qboolean);
function WINS_OpenSocket(port: integer): integer;
function WINS_CloseSocket(socket: integer): integer;
function PartialIPAddress(_in: PChar; hostaddr: Pqsockaddr_t): integer;
function WINS_Connect(socket: integer; addr: Pqsockaddr_t): integer;
function WINS_CheckNewConnections: integer;
function WINS_Read(socket: integer; buf: PByteArray; len: integer; addr: Pqsockaddr_t): integer;
function WINS_MakeSocketBroadcastCapable(socket: integer): integer;
function WINS_Broadcast(socket: integer; buf: PByteArray; len: integer): integer;
function WINS_Write(socket: integer; buf: PByteArray; len: integer; addr: Pqsockaddr_t): integer;
function WINS_AddrToString(addr: Pqsockaddr_t): PChar;
function WINS_StringToAddr(str: PChar; addr: Pqsockaddr_t): integer;
function WINS_GetSocketAddr(socket: integer; addr: Pqsockaddr_t): integer;
function WINS_GetNameFromAddr(addr: Pqsockaddr_t; name: PChar): integer;
function WINS_GetAddrFromName(name: PChar; addr: Pqsockaddr_t): integer;
function WINS_AddrCompare(addr1: Pqsockaddr_t; addr2: Pqsockaddr_t): integer;
function WINS_GetSocketPort(addr: Pqsockaddr_t): integer;
function WINS_SetSocketPort(addr: Pqsockaddr_t; port: integer): integer;


implementation

uses
  Windows,
  sys_win,
  net_main,
  common,
  console,
  cvar;

const
  MAXHOSTNAMELEN = 256;

var
  net_acceptsocket: integer = -1; // socket for fielding new connections
  net_controlsocket: integer;
  net_broadcastsocket: integer = 0;
  broadcastaddr: qsockaddr_t;

  myAddr: integer;

//=============================================================================

var
  blocktime: double;

function BlockingHook: BOOL; stdcall;
var
  msg: TMsg;
begin
  if (Sys_FloatTime - blocktime) > 2.0 then
  begin
    WSACancelBlockingCall;
    result := false;
    exit;
  end;

  (* get the next message, if any *)
  result := PeekMessage(msg, 0, 0, 0, PM_REMOVE);

  (* if we got one, process it *)
  if result then
  begin
    TranslateMessage(msg);
    DispatchMessage(msg);
  end;
end;


procedure WINS_GetLocalAddress;
var
  local: PHostEnt;
  buff: array[0..MAXHOSTNAMELEN - 1] of char;
  addr: unsigned;
begin
  if myAddr <> INADDR_ANY then
    exit;

  if gethostname(buff, MAXHOSTNAMELEN) = SOCKET_ERROR then
    exit;

  blocktime := Sys_FloatTime;
  WSASetBlockingHook(@BlockingHook);
  local := gethostbyname(buff);
  WSAUnhookBlockingHook;
  if local = nil then
    exit;

  myAddr := PInteger(local.h_addr_list^)^; // JVAL check!

  addr := ntohl(myAddr);
  sprintf(my_tcpip_address, '%d.%d.%d.%d', [(addr shr 24) and $FF, (addr shr 16) and $FF, (addr shr 8) and $FF, addr and $FF]);
end;


function WINS_Init: integer;
var
  i: integer;
  buff: array[0..MAXHOSTNAMELEN - 1] of char;
  p: PChar;
  r: integer;
  wVersionRequested: WORD;
begin
  if COM_CheckParm('-noudp') <> 0 then
  begin
    result := -1;
    exit;
  end;

  if winsock_initialized = 0 then
  begin
    wVersionRequested := MAKEWORD(1, 1);

    r := WSAStartup(wVersionRequested, winsockdata);

    if r <> 0 then
    begin
      Con_SafePrintf('Winsock initialization failed.'#10);
      result := -1;
      exit;
    end;
  end;
  inc(winsock_initialized);

  // determine my name
  if gethostname(buff, MAXHOSTNAMELEN) = SOCKET_ERROR then
  begin
    Con_DPrintf('Winsock TCP/IP Initialization failed.'#10);
    dec(winsock_initialized);
    if winsock_initialized = 0 then
      WSACleanup;
    result := -1;
    exit;
  end;

  // if the quake hostname isn't set, set it to the machine name
  if Q_strcmp(hostname.text, 'UNNAMED') = 0 then
  begin
    // see if it's a text IP address (well, close enough)
    p := @buff[0];
    while p^ <> #0 do
    begin
      if ((p^ < '0') or (p^ > '9')) and (p^ <> '.') then
        break;
      inc(p);
    end;

    // if it is a real name, strip off the domain; we only want the host
    if p^ <> #0 then
    begin
      i := 0;
      while i < 15 do
      begin
        if buff[i] = '.' then
          break;
        inc(i);
      end;
      buff[i] := #0;
    end;
    Cvar_Set('hostname', buff);
  end;

  i := COM_CheckParm('-ip');
  if i <> 0 then
  begin
    if i < com_argc - 1 then
    begin
      myAddr := inet_addr(com_argv[i + 1]);
      if myAddr = INADDR_NONE then
        Sys_Error('%s is not a valid IP address', [com_argv[i + 1]]);
      strcpy(my_tcpip_address, com_argv[i + 1]);
    end
    else
    begin
      Sys_Error('NET_Init: you must specify an IP address after -ip');
    end;
  end
  else
  begin
    myAddr := INADDR_ANY;
    strcpy(my_tcpip_address, 'INADDR_ANY');
  end;

  net_controlsocket := WINS_OpenSocket(0);
  if net_controlsocket = -1 then
  begin
    Con_Printf('WINS_Init: Unable to open control socket'#10);
    dec(winsock_initialized);
    if winsock_initialized = 0 then
      WSACleanup;
    result := -1;
    exit;
  end;

  PSockAddrIn(@broadcastaddr).sin_family := AF_INET;
  PSockAddrIn(@broadcastaddr).sin_addr.s_addr := INADDR_BROADCAST;
  PSockAddrIn(@broadcastaddr).sin_port := htons(u_short(net_hostport));

  Con_Printf('Winsock TCP/IP Initialized'#10);
  tcpipAvailable := true;

  result := net_controlsocket;
end;

//=============================================================================

procedure WINS_Shutdown;
begin
  WINS_Listen(false);
  WINS_CloseSocket(net_controlsocket);
  dec(winsock_initialized); // JVAL mayby external proc the 3 lines below ??
  if winsock_initialized = 0 then
    WSACleanup;
end;

//=============================================================================

procedure WINS_Listen(state: qboolean);
begin
  // enable listening
  if state then
  begin
    if net_acceptsocket <> -1 then
      exit;
    WINS_GetLocalAddress;
    net_acceptsocket := WINS_OpenSocket(net_hostport);
    if net_acceptsocket = -1 then
      Sys_Error('WINS_Listen: Unable to open accept socket'#10);
    exit;
  end;

  // disable listening
  if net_acceptsocket = -1 then
    exit;
  WINS_CloseSocket(net_acceptsocket);
  net_acceptsocket := -1;
end;

//=============================================================================

function WINS_OpenSocket(port: integer): integer;
var
  newsocket: integer;
  address: sockaddr_in;
  _true: u_long;
begin
  _true := 1;

  result := -1;

  newsocket := socket(PF_INET, SOCK_DGRAM, IPPROTO_UDP);
  if newsocket = -1 then
    exit;

  if ioctlsocket(newsocket, FIONBIO, _true) = -1 then
  begin
    closesocket(newsocket);
    exit;
  end;
  address.sin_family := AF_INET;
  address.sin_addr.s_addr := myAddr;
  address.sin_port := htons(u_short(port));
  if bind(newsocket, address, SizeOf(address)) = 0 then
    result := newsocket
  else
    Sys_Error('Unable to bind to %s', [WINS_AddrToString(Pqsockaddr_t(@address))]);
end;

//=============================================================================

function WINS_CloseSocket(socket: integer): integer;
begin
  if socket = net_broadcastsocket then
    net_broadcastsocket := 0;
  result := closesocket(socket);
end;


//=============================================================================
(*
============
PartialIPAddress

this lets you type only as much of the net address as required, using
the local network components to fill in the rest
============
*)

function PartialIPAddress(_in: PChar; hostaddr: Pqsockaddr_t): integer;
var
  buff: array[0..255] of char;
  b: PChar;
  addr: integer;
  num: integer;
  mask: integer;
  run: integer;
  port: integer;
begin
  buff[0] := '.';
  b := @buff[0];
  strcpy(@buff[1], _in);
  if buff[1] = '.' then
    inc(b);

  addr := 0;
  mask := -1;
  while b^ = '.' do
  begin
    inc(b);
    num := 0;
    run := 0;
    while not ((b^ < '0') or (b^ > '9')) do
    begin
      num := num * 10 + Ord(b^) - Ord('0');
      inc(b);
      inc(run);
      if run > 3 then // JVAL check!
      begin
        result := -1;
        exit;
      end;
    end;
    if ((b^ < '0') or (b^ > '9')) and (b^ <> '.') and (b^ <> ':') and (b^ <> #0) then
    begin
      result := -1;
      exit;
    end;
    if (num < 0) or (num > 255) then
    begin
      result := -1;
      exit;
    end;
    mask := mask * 256;
    addr := (addr * 256) + num;
  end;

  if b^ = ':' then
  begin
    inc(b);
    port := Q_atoi(b);
  end
  else
  begin
    port := net_hostport;
  end;

  hostaddr.sa_family := AF_INET;
  PSockAddrIn(hostaddr).sin_port := htons(u_short(port));
  PSockAddrIn(hostaddr).sin_addr.s_addr := (myAddr and htonl(mask)) or htonl(addr);

  result := 0;
end;

//=============================================================================

function WINS_Connect(socket: integer; addr: Pqsockaddr_t): integer;
begin
  result := 0;
end;

//=============================================================================

function WINS_CheckNewConnections: integer;
var
  buf: array[0..4095] of char;
begin
  if net_acceptsocket = -1 then
  begin
    result := -1;
    exit;
  end;

  if recvfrom_a(net_acceptsocket, buf, SizeOf(buf), MSG_PEEK, nil, nil) > 0 then
    result := net_acceptsocket
  else
    result := -1;
end;

//=============================================================================

function WINS_Read(socket: integer; buf: PByteArray; len: integer; addr: Pqsockaddr_t): integer;
var
  addrlen: integer;
  errno: integer;
begin
  addrlen := SizeOf(qsockaddr_t);
  result := recvfrom_a(socket, buf^, len, 0, PSockAddr(addr), @addrlen);
  if result = -1 then
  begin
    errno := WSAGetLastError;
    if (errno = WSAEWOULDBLOCK) or (errno = WSAECONNREFUSED) then
      result := 0;
  end;
end;

//=============================================================================

function WINS_MakeSocketBroadcastCapable(socket: integer): integer;
var
  i: integer;
begin
  i := 1;

  // make this socket broadcast capable
  if setsockopt(socket, SOL_SOCKET, SO_BROADCAST, PChar(@i), SizeOf(i)) < 0 then
    result := -1
  else
  begin
    net_broadcastsocket := socket;
    result := 0;
  end;
end;

//=============================================================================

function WINS_Broadcast(socket: integer; buf: PByteArray; len: integer): integer;
begin
  if socket <> net_broadcastsocket then
  begin
    if net_broadcastsocket <> 0 then
      Sys_Error('Attempted to use multiple broadcasts sockets'#10);
    WINS_GetLocalAddress;
    result := WINS_MakeSocketBroadcastCapable(socket);
    if result = -1 then
    begin
      Con_Printf('Unable to make socket broadcast capable'#10);
      exit;
    end;
  end;

  result := WINS_Write(socket, buf, len, @broadcastaddr);
end;

//=============================================================================

function WINS_Write(socket: integer; buf: PByteArray; len: integer; addr: Pqsockaddr_t): integer;
begin
  result := sendto(socket, buf^, len, 0, PSockAddr(addr)^, SizeOf(qsockaddr_t));
  if result = -1 then
    if WSAGetLastError = WSAEWOULDBLOCK then
      result := 0;
end;

//=============================================================================

var
  buffer_WINS_AddrToString: array[0..21] of char;

function WINS_AddrToString(addr: Pqsockaddr_t): PChar;
var
  haddr: integer;
begin
  haddr := ntohl(PSockAddrIn(addr).sin_addr.s_addr);
  sprintf(buffer_WINS_AddrToString, '%d.%d.%d.%d:%d',
    [(haddr shr 24) and $FF, (haddr shr 16) and $FF, (haddr shr 8) and $FF, haddr and $FF, ntohs(PSockAddrIn(addr).sin_port)]);
  result := @buffer_WINS_AddrToString[0];
end;

//=============================================================================

function WINS_StringToAddr(str: PChar; addr: Pqsockaddr_t): integer;
var
  ha1, ha2, ha3, ha4, hp: integer;
  ipaddr: integer;

  function get_one_int(var p: PChar; const _until: char): integer; // JVAL check!
  var
    buf: array[0..31] of char;
    i: integer;
  begin
    i := 0;
    while not (p^ in [_until, #0]) do
    begin
      buf[i] := p^;
      inc(p);
      inc(i);
    end;
    if p^ <> #0 then
      inc(p);
    buf[i] := #0;
    result := atoi(@buf[0]);
  end;

var
  p: PChar;
begin
  p := str;
  ha1 := get_one_int(p, '.');
  ha2 := get_one_int(p, '.');
  ha3 := get_one_int(p, '.');
  ha4 := get_one_int(p, ':');
  hp := get_one_int(p, ' ');
//  sscanf(string, "%d.%d.%d.%d:%d", &ha1, &ha2, &ha3, &ha4, &hp);
  ipaddr := (ha1 shl 24) or (ha2 shl 16) or (ha3 shl 8) or ha4;

  addr.sa_family := AF_INET;
  PSockAddrIn(addr).sin_addr.s_addr := htonl(ipaddr);
  PSockAddrIn(addr).sin_port := htons(u_short(hp));
  result := 0;
end;

//=============================================================================

function WINS_GetSocketAddr(socket: integer; addr: Pqsockaddr_t): integer;
var
  addrlen: integer;
  a: integer;
begin
  addrlen := SizeOf(qsockaddr_t);
  memset(addr, 0, SizeOf(qsockaddr_t));
  getsockname(socket, PSockAddrIn(addr)^, addrlen);
  a := PSockAddrIn(addr).sin_addr.s_addr;
  if (a = 0) or (a = inet_addr('127.0.0.1')) then
    PSockAddrIn(addr).sin_addr.s_addr := myAddr;

  result := 0;
end;

//=============================================================================

function WINS_GetNameFromAddr(addr: Pqsockaddr_t; name: PChar): integer;
var
  hostentry: PHostEnt;
begin
  hostentry := gethostbyaddr(PChar(@PSockAddrIn(addr).sin_addr), SizeOf(in_addr), AF_INET);
  if hostentry <> nil then
    Q_strncpy(name, hostentry.h_name, NET_NAMELEN - 1)
  else
    Q_strcpy(name, WINS_AddrToString(addr));

  result := 0;
end;

//=============================================================================

function WINS_GetAddrFromName(name: PChar; addr: Pqsockaddr_t): integer;
var
  hostentry: PHostEnt;
begin
  if (name[0] >= '0') and (name[0] <= '9') then
  begin
    result := PartialIPAddress(name, addr);
    exit;
  end;

  hostentry := gethostbyname(name);
  if hostentry = nil then
    result := -1
  else
  begin
    addr.sa_family := AF_INET;
    PSockAddrIn(addr).sin_port := htons(u_short(net_hostport));
    PSockAddrIn(addr).sin_addr.s_addr := PInteger(hostentry.h_addr_list^)^; // JVAL check!

    result := 0;
  end;
end;

//=============================================================================

function WINS_AddrCompare(addr1: Pqsockaddr_t; addr2: Pqsockaddr_t): integer;
begin
  if addr1.sa_family <> addr2.sa_family then
  begin
    result := -1;
    exit;
  end;

  if PSockAddrIn(addr1).sin_addr.s_addr <> PSockAddrIn(addr2).sin_addr.s_addr then
  begin
    result := -1;
    exit;
  end;

  if PSockAddrIn(addr1).sin_port <> PSockAddrIn(addr2).sin_port then
  begin
    result := -1;
    exit;
  end;

  result := 0;
end;

//=============================================================================

function WINS_GetSocketPort(addr: Pqsockaddr_t): integer;
begin
  result := ntohs(PSockAddrIn(addr).sin_port);
end;


function WINS_SetSocketPort(addr: Pqsockaddr_t; port: integer): integer;
begin
  PSockAddrIn(addr).sin_port := htons(u_short(port));
  result := 0;
end;

//=============================================================================

end.

