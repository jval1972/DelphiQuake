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

unit net_wipx;

interface

uses
  q_delphi,
  net;

function WIPX_Init: integer;
procedure WIPX_Shutdown;
procedure WIPX_Listen(state: qboolean);
function WIPX_OpenSocket(port: integer): integer;
function WIPX_CloseSocket(handle: integer): integer;
function WIPX_Connect(handle: integer; addr: Pqsockaddr_t): integer;
function WIPX_CheckNewConnections: integer;
function WIPX_Read(handle: integer; buf: PByteArray; len: integer; addr: Pqsockaddr_t): integer;
function WIPX_Broadcast(handle: integer; buf: PByteArray; len: integer): integer;
function WIPX_Write(handle: integer; buf: PByteArray; len: integer; addr: Pqsockaddr_t): integer;
function WIPX_AddrToString(addr: Pqsockaddr_t): PChar;
function WIPX_StringToAddr(str: PChar; addr: Pqsockaddr_t): integer;
function WIPX_GetSocketAddr(handle: integer; addr: Pqsockaddr_t): integer;
function WIPX_GetNameFromAddr(addr: Pqsockaddr_t; name: PChar): integer;
function WIPX_GetAddrFromName(name: PChar; addr: Pqsockaddr_t): integer;
function WIPX_AddrCompare(addr1: Pqsockaddr_t; addr2: Pqsockaddr_t): integer;
function WIPX_GetSocketPort(addr: Pqsockaddr_t): integer;
function WIPX_SetSocketPort(addr: Pqsockaddr_t; port: integer): integer;



implementation

uses
  Windows,
  winsock,
  wsipx_h,
  net_wins,
  common,
  console,
  net_main,
  cvar,
  sys_win;

const
  MAXHOSTNAMELEN = 256;

var
  net_acceptsocket: integer = -1; // socket for fielding new connections
  net_controlsocket: integer;
  broadcastaddr: qsockaddr_t;

const
  IPXSOCKETS = 18;

var
  ipxsocket: array[0..IPXSOCKETS - 1] of integer;
  sequence: array[0..IPXSOCKETS - 1] of integer;

//=============================================================================

function WIPX_Init: integer;
var
  i: integer;
  buff: array[0..MAXHOSTNAMELEN - 1] of char;
  addr: qsockaddr_t;
  p: PChar;
  r: integer;
  wVersionRequested: word;
begin
  if COM_CheckParm('-noipx') <> 0 then
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
      Con_Printf('Winsock initialization failed.'#10);
      result := -1;
      exit;
    end;
  end;
  inc(winsock_initialized);

  for i := 0 to IPXSOCKETS - 1 do
    ipxsocket[i] := 0;

  // determine my name & address
  if gethostname(buff, MAXHOSTNAMELEN) = 0 then
  begin
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
  end;

  net_controlsocket := WIPX_OpenSocket(0);
  if net_controlsocket = -1 then
  begin
    Con_Printf('WIPX_Init: Unable to open control socket'#10);
    dec(winsock_initialized);
    if winsock_initialized = 0 then
      WSACleanup;
    result := -1;
    exit;
  end;

  PSockAddrIpx(@broadcastaddr).sa_family := AF_IPX;
  memset(@PSockAddrIpx(@broadcastaddr).sa_netnum, 0, 4);
  memset(@PSockAddrIpx(@broadcastaddr).sa_nodenum, $FF, 6);
  PSockAddrIpx(@broadcastaddr).sa_socket := htons(u_short(net_hostport));

  WIPX_GetSocketAddr(net_controlsocket, @addr);
  Q_strcpy(my_ipx_address, WIPX_AddrToString(@addr));
  p := Q_strrchr(my_ipx_address, ':');
  if p <> nil then
    p^ := #0;

  Con_Printf('Winsock IPX Initialized'#10);
  ipxAvailable := true;

  result := net_controlsocket;
end;

//=============================================================================

procedure WIPX_Shutdown;
begin
  WIPX_Listen(false);
  WIPX_CloseSocket(net_controlsocket);
  dec(winsock_initialized);
  if winsock_initialized = 0 then
    WSACleanup;
end;

//=============================================================================

procedure WIPX_Listen(state: qboolean);
begin
  // enable listening
  if state then
  begin
    if net_acceptsocket <> -1 then
      exit;
    net_acceptsocket := WIPX_OpenSocket(net_hostport);
    if net_acceptsocket = -1 then
      Sys_Error('WIPX_Listen: Unable to open accept socket'#10);
    exit;
  end;

  // disable listening
  if net_acceptsocket = -1 then
    exit;
  WIPX_CloseSocket(net_acceptsocket);
  net_acceptsocket := -1;
end;

//=============================================================================

function WIPX_OpenSocket(port: integer): integer;
label
  ErrorReturn;
var
  handle: integer;
  newsocket: integer;
  address: TSockAddrIpx;
  _true: u_long;
begin
  _true := 1;

  handle := 0;
  while handle < IPXSOCKETS do
  begin
    if ipxsocket[handle] = 0 then
      break;
    inc(handle);
  end;
  if handle = IPXSOCKETS then
  begin
    result := -1;
    exit;
  end;

  newsocket := socket(AF_IPX, SOCK_DGRAM, NSPROTO_IPX);
  if newsocket = INVALID_SOCKET then
  begin
    result := -1;
    exit;
  end;

  if ioctlsocket(newsocket, FIONBIO, _true) = -1 then
    goto ErrorReturn;

  if setsockopt(newsocket, SOL_SOCKET, SO_BROADCAST, PChar(@_true), SizeOf(_true)) < 0 then
    goto ErrorReturn;

  address.sa_family := AF_IPX;
  ZeroMemory(@address.sa_netnum, 4);
  ZeroMemory(@address.sa_nodenum, 6); ;
  address.sa_socket := htons(u_short(port));
  if bind(newsocket, PSockAddr(@address)^, SizeOf(address)) = 0 then
  begin
    ipxsocket[handle] := newsocket;
    sequence[handle] := 0;
    result := handle;
    exit;
  end;

  Sys_Error('Winsock IPX bind failed'#10);
  ErrorReturn:
  closesocket(newsocket);
  result := -1;
end;

//=============================================================================

function WIPX_CloseSocket(handle: integer): integer;
var
  socket: integer;
begin
  socket := ipxsocket[handle];
  result := closesocket(socket);
  ipxsocket[handle] := 0;
end;

//=============================================================================

function WIPX_Connect(handle: integer; addr: Pqsockaddr_t): integer;
begin
  result := 0;
end;

//=============================================================================

function WIPX_CheckNewConnections: integer;
var
  available: u_long;
begin
  if net_acceptsocket = -1 then
  begin
    result := -1;
    exit;
  end;

  if ioctlsocket(ipxsocket[net_acceptsocket], FIONREAD, available) = -1 then
    Sys_Error('WIPX: ioctlsocket (FIONREAD) failed'#10);
  if available <> 0 then
    result := net_acceptsocket
  else
    result := -1;
end;

//=============================================================================

var
  packetBuffer: array[0..NET_DATAGRAMSIZE + 3] of byte;

function WIPX_Read(handle: integer; buf: PByteArray; len: integer; addr: Pqsockaddr_t): integer;
var
  addrlen: integer;
  socket: integer;
  errno: integer;
begin
  addrlen := SizeOf(qsockaddr_t);
  socket := ipxsocket[handle];
  result := recvfrom_a(socket, packetBuffer, len + 4, 0, PSockAddr(addr), @addrlen);
  if result = -1 then
  begin
    errno := WSAGetLastError;
    if (errno = WSAEWOULDBLOCK) or (errno = WSAECONNREFUSED) then
    begin
      result := 0;
      exit;
    end;
  end;

  if result < 4 then
  begin
    result := 0;
    exit;
  end;

  // remove sequence number, it's only needed for DOS IPX
  dec(result, 4);
  memcpy(buf, @packetBuffer[4], result);
end;

//=============================================================================

function WIPX_Broadcast(handle: integer; buf: PByteArray; len: integer): integer;
begin
  result := WIPX_Write(handle, buf, len, @broadcastaddr);
end;

//=============================================================================

function WIPX_Write(handle: integer; buf: PByteArray; len: integer; addr: Pqsockaddr_t): integer;
var
  socket: integer;
begin
  socket := ipxsocket[handle];

  // build packet with sequence number
  PInteger(@packetBuffer[0])^ := sequence[handle];
  inc(sequence[handle]);
  memcpy(@packetBuffer[4], buf, len);
  inc(len, 4);

  result := sendto(socket, packetBuffer, len, 0, PSockAddr(addr)^, SizeOf(qsockaddr_t));
  if result = -1 then
    if WSAGetLastError = WSAEWOULDBLOCK then
      result := 0;
end;

//=============================================================================

var
  buf_WIPX_AddrToString: array[0..27] of char;

function WIPX_AddrToString(addr: Pqsockaddr_t): PChar;
begin
  sprintf(buf_WIPX_AddrToString, '%02x%02x%02x%02x:%02x%02x%02x%02x%02x%02x:%u',
    [
    Ord(PSockAddrIpx(addr).sa_netnum[0]),
      Ord(PSockAddrIpx(addr).sa_netnum[1]),
      Ord(PSockAddrIpx(addr).sa_netnum[2]),
      Ord(PSockAddrIpx(addr).sa_netnum[3]),
      Ord(PSockAddrIpx(addr).sa_nodenum[0]),
      Ord(PSockAddrIpx(addr).sa_nodenum[1]),
      Ord(PSockAddrIpx(addr).sa_nodenum[2]),
      Ord(PSockAddrIpx(addr).sa_nodenum[3]),
      Ord(PSockAddrIpx(addr).sa_nodenum[4]),
      Ord(PSockAddrIpx(addr).sa_nodenum[5]),
      ntohs(PSockAddrIpx(addr).sa_socket)
      ]);
  result := @buf_WIPX_AddrToString[0];
end;

//=============================================================================

function WIPX_StringToAddr(str: PChar; addr: Pqsockaddr_t): integer;
var
  v: integer;
  buf: array[0..2] of char;
  code: integer;
  p: PChar;

  function DOIT(const offs: integer; p: PChar): boolean;
  begin
    buf[0] := str[offs];
    buf[1] := str[offs + 1];
    val(buf, v, code);
    result := code = 0;
    if result then
      p^ := Chr(v);
  end;

begin
  buf[2] := #0;
  ZeroMemory(addr, SizeOf(qsockaddr_t));
  addr.sa_family := AF_IPX;

  result := -1;
  if not DOIT(0, @PSockAddrIpx(addr).sa_netnum[0]) then exit;
  if not DOIT(2, @PSockAddrIpx(addr).sa_netnum[1]) then exit;
  if not DOIT(4, @PSockAddrIpx(addr).sa_netnum[2]) then exit;
  if not DOIT(6, @PSockAddrIpx(addr).sa_netnum[3]) then exit;
  if not DOIT(9, @PSockAddrIpx(addr).sa_nodenum[0]) then exit;
  if not DOIT(11, @PSockAddrIpx(addr).sa_nodenum[1]) then exit;
  if not DOIT(13, @PSockAddrIpx(addr).sa_nodenum[2]) then exit;
  if not DOIT(15, @PSockAddrIpx(addr).sa_nodenum[3]) then exit;
  if not DOIT(17, @PSockAddrIpx(addr).sa_nodenum[4]) then exit;
  if not DOIT(19, @PSockAddrIpx(addr).sa_nodenum[5]) then exit;

  p := @str[22];
  val(p, v, code);
  PSockAddrIpx(addr).sa_socket := htons(u_short(v));

  result := 0;
end;

//=============================================================================

function WIPX_GetSocketAddr(handle: integer; addr: Pqsockaddr_t): integer;
var
  socket: integer;
  addrlen: integer;
begin
  socket := ipxsocket[handle];
  addrlen := SizeOf(qsockaddr_t);

  ZeroMemory(addr, SizeOf(qsockaddr_t));
  if getsockname(socket, PSockAddr(addr)^, addrlen) <> 0 then // JVAL mayby always return 0 ???
    result := -1
  else
    result := 0;
(*
  {
    int errno = pWSAGetLastError();
  }

  return 0;
*)
end;

//=============================================================================

function WIPX_GetNameFromAddr(addr: Pqsockaddr_t; name: PChar): integer;
begin
  Q_strcpy(name, WIPX_AddrToString(addr));
  result := 0;
end;

//=============================================================================

function WIPX_GetAddrFromName(name: PChar; addr: Pqsockaddr_t): integer;
var
  n: integer;
  buf: array[0..31] of char;
begin
  n := Q_strlen(name);

  if n = 12 then
  begin
    sprintf(buf, '00000000:%s:%u', [name, net_hostport]);
    result := WIPX_StringToAddr(buf, addr);
    exit;
  end;

  if n = 21 then
  begin
    sprintf(buf, '%s:%u', [name, net_hostport]);
    result := WIPX_StringToAddr(buf, addr);
    exit;
  end;

  if (n > 21) and (n <= 27) then
  begin
    result := WIPX_StringToAddr(name, addr);
    exit;
  end;

  result := -1;
end;

//=============================================================================

function WIPX_AddrCompare(addr1: Pqsockaddr_t; addr2: Pqsockaddr_t): integer;
begin
  if addr1.sa_family <> addr2.sa_family then
  begin
    result := -1;
    exit;
  end;

  if (PSockAddrIpx(addr1).sa_netnum[0] <> #0) and (PSockAddrIpx(addr2).sa_netnum[0] <> #0) then
    if Q_memcmp(@PSockAddrIpx(addr1).sa_netnum, @PSockAddrIpx(addr2).sa_netnum, 4) <> 0 then
    begin
      result := -1;
      exit;
    end;
  if Q_memcmp(@PSockAddrIpx(addr1).sa_nodenum, @PSockAddrIpx(addr2).sa_nodenum, 6) <> 0 then
  begin
    result := -1;
    exit;
  end;

  if PSockAddrIpx(addr1).sa_socket <> PSockAddrIpx(addr2).sa_socket then
  begin
    result := 1;
    exit;
  end;

  result := 0;
end;

//=============================================================================

function WIPX_GetSocketPort(addr: Pqsockaddr_t): integer;
begin
  result := ntohs(PSockAddrIpx(addr).sa_socket);
end;


function WIPX_SetSocketPort(addr: Pqsockaddr_t; port: integer): integer;
begin
  PSockAddrIpx(addr).sa_socket := htons(u_short(port));
  result := 0;
end;


end.

 