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

unit net;

// net.h -- quake's interface to the networking layer

interface

uses
  q_delphi,
  WinSock,
  quakedef,
  common;

type
  Pqsockaddr_t = ^qsockaddr_t;
  qsockaddr_t = record
    sa_family: short;
    sa_data: array[0..13] of byte;
  end;

const
  NET_NAMELEN = 64;

  NET_MAXMESSAGE = 8192;
  NET_HEADERSIZE = (2 * SizeOf(unsigned));
  NET_DATAGRAMSIZE = (MAX_DATAGRAM + NET_HEADERSIZE);

// NetHeader flags
  NETFLAG_LENGTH_MASK = $0000FFFF;
  NETFLAG_DATA = $00010000;
  NETFLAG_ACK = $00020000;
  NETFLAG_NAK = $00040000;
  NETFLAG_EOM = $00080000;
  NETFLAG_UNRELIABLE = $00100000;
  NETFLAG_CTL = integer($80000000);


  NET_PROTOCOL_VERSION = 3;

// This is the network info/connection protocol.  It is used to find Quake
// servers, get info about them, and connect to them.  Once connected, the
// Quake game protocol (documented elsewhere) is used.
//
//
// General notes:
//  game_name is currently always "QUAKE", but is there so this same protocol
//    can be used for future games as well; can you say Quake2?
//
// CCREQ_CONNECT
//    string  game_name        "QUAKE"
//    byte  net_protocol_version  NET_PROTOCOL_VERSION
//
// CCREQ_SERVER_INFO
//    string  game_name        "QUAKE"
//    byte  net_protocol_version  NET_PROTOCOL_VERSION
//
// CCREQ_PLAYER_INFO
//    byte  player_number
//
// CCREQ_RULE_INFO
//    string  rule
//
//
//
// CCREP_ACCEPT
//    long  port
//
// CCREP_REJECT
//    string  reason
//
// CCREP_SERVER_INFO
//    string  server_address
//    string  host_name
//    string  level_name
//    byte  current_players
//    byte  max_players
//    byte  protocol_version  NET_PROTOCOL_VERSION
//
// CCREP_PLAYER_INFO
//    byte  player_number
//    string  name
//    long  colors
//    long  frags
//    long  connect_time
//    string  address
//
// CCREP_RULE_INFO
//    string  rule
//    string  value

//  note:
//    There are two address forms used above.  The short form is just a
//    port number.  The address that goes along with the port is defined as
//    "whatever address you receive this reponse from".  This lets us use
//    the host OS to solve the problem of multiple host addresses (possibly
//    with no routing between them); the host will use the right address
//    when we reply to the inbound connection request.  The long from is
//    a full address and port in a string.  It is used for returning the
//    address of a server that is not running locally.

const
  CCREQ_CONNECT = $01;
  CCREQ_SERVER_INFO = $02;
  CCREQ_PLAYER_INFO = $03;
  CCREQ_RULE_INFO = $04;

  CCREP_ACCEPT = $81;
  CCREP_REJECT = $82;
  CCREP_SERVER_INFO = $83;
  CCREP_PLAYER_INFO = $84;
  CCREP_RULE_INFO = $85;

type
  Pqsocket_t = ^qsocket_t;
  qsocket_t = record
    next: Pqsocket_t;
    connecttime: double;
    lastMessageTime: double;
    lastSendTime: double;

    disconnected: qboolean;
    canSend: qboolean;
    sendNext: qboolean;

    driver: integer;
    landriver: integer;
    socket: integer;
    driverdata: pointer;

    ackSequence: unsigned_int;
    sendSequence: unsigned_int;
    unreliableSendSequence: unsigned_int;
    sendMessageLength: integer;
    sendMessage: array[0..NET_MAXMESSAGE - 1] of byte;

    receiveSequence: unsigned_int;
    unreliableReceiveSequence: unsigned_int;
    receiveMessageLength: integer;
    receiveMessage: array[0..NET_MAXMESSAGE - 1] of byte;

    addr: qsockaddr_t;
    address: array[0..NET_NAMELEN - 1] of char;
  end;

type
  Pnet_landriver_t = ^net_landriver_t;
  net_landriver_t = record
    name: PChar;
    initialized: qboolean;
    controlSock: integer;
    Init: function: integer;
    Shutdown: procedure;
    Listen: procedure(b: qboolean);
    OpenSocket: function(i: integer): integer;
    CloseSocket: function(i: integer): integer;
    Connect: function(i: integer; ps: Pqsockaddr_t): integer;
    CheckNewConnections: function: integer;
    Read: function(i: integer; pb: PByteArray; i2: integer; ps: Pqsockaddr_t): integer;
    Write: function(i: integer; pb: PByteArray; i2: integer; ps: Pqsockaddr_t): integer;
    Broadcast: function(i: integer; pb: PByteArray; i2: integer): integer;
    AddrToString: function(ps: Pqsockaddr_t): PChar;
    StringToAddr: function(pc: PChar; ps: Pqsockaddr_t): integer;
    GetSocketAddr: function(i: integer; ps: Pqsockaddr_t): integer;
    GetNameFromAddr: function(ps: Pqsockaddr_t; pc: Pchar): integer;
    GetAddrFromName: function(pc: PChar; ps: Pqsockaddr_t): integer;
    AddrCompare: function(ps1: Pqsockaddr_t; ps2: Pqsockaddr_t): integer;
    GetSocketPort: function(ps: Pqsockaddr_t): integer;
    SetSocketPort: function(ps: Pqsockaddr_t; i: integer): integer;
  end;

const
  MAX_NET_DRIVERS = 8;

type
  Pnet_driver_t = ^net_driver_t;
  net_driver_t = record
    name: PChar;
    initialized: qboolean;
    Init: function: integer;
    Listen: procedure(b: qboolean);
    SearchForHosts: procedure(b: qboolean);
    Connect: function(pc: PChar): Pqsocket_t;
    CheckNewConnections: function: Pqsocket_t;
    QGetMessage: function(pq: Pqsocket_t): integer;
    QSendMessage: function(pq: Pqsocket_t; ps: Psizebuf_t): integer;
    SendUnreliableMessage: function(pq: Pqsocket_t; ps: Psizebuf_t): integer;
    CanSendMessage: function(pq: Pqsocket_t): qboolean;
    CanSendUnreliableMessage: function(pq: Pqsocket_t): qboolean;
    Close: procedure(pq: Pqsocket_t);
    Shutdown: procedure;
    controlSock: integer;
  end;

const
  HOSTCACHESIZE = 8;

type
  Phostcache_t = ^hostcache_t;
  hostcache_t = record
    name: array[0..15] of char;
    map: array[0..15] of char;
    cname: array[0..31] of char;
    users: integer;
    maxusers: integer;
    driver: integer;
    ldriver: integer;
    addr: qsockaddr_t;
  end;

type
  PollProcedureProc = procedure(p: pointer);
  PPollProcedure_t = ^PollProcedure_t;
  PollProcedure_t = record
    next: PPollProcedure_t;
    nextTime: double;
    proc: PollProcedureProc;
    arg: pointer;
  end;

function recvfrom_a(s: TSocket; var Buf; len, flags: Integer; from: PSockAddr; fromlen: PInteger): Integer; stdcall;

implementation

function recvfrom_a; external 'wsock32.dll' name 'recvfrom';

end.

