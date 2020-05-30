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

(*
 *   wsipx.h
 *
 *   Microsoft Windows
 *   Copyright (C) Microsoft Corporation, 1992-1997.
 *
 *   Windows Sockets include file for IPX/SPX.  This file contains all
 *   standardized IPX/SPX information.  Include this header file after
 *   winsock.h.
 *
 *   To open an IPX socket, call socket() with an address family of
 *   AF_IPX, a socket type of SOCK_DGRAM, and protocol NSPROTO_IPX.
 *   Note that the protocol value must be specified, it cannot be 0.
 *   All IPX packets are sent with the packet type field of the IPX
 *   header set to 0.
 *
 *   To open an SPX or SPXII socket, call socket() with an address
 *   family of AF_IPX, socket type of SOCK_SEQPACKET or SOCK_STREAM,
 *   and protocol of NSPROTO_SPX or NSPROTO_SPXII.  If SOCK_SEQPACKET
 *   is specified, then the end of message bit is respected, and
 *   recv() calls are not completed until a packet is received with
 *   the end of message bit set.  If SOCK_STREAM is specified, then
 *   the end of message bit is not respected, and recv() completes
 *   as soon as any data is received, regardless of the setting of the
 *   end of message bit.  Send coalescing is never performed, and sends
 *   smaller than a single packet are always sent with the end of
 *   message bit set.  Sends larger than a single packet are packetized
 *   with the end of message bit set on only the last packet of the
 *   send.
 *
 *)

{$Z4}

unit wsipx_h;

interface

(*
 *   This is the structure of the SOCKADDR structure for IPX and SPX.
 *
 *)

type
  SOCKADDR_IPX = record
    sa_family: Smallint;
    sa_netnum: array[0..3] of char;
    sa_nodenum: array[0..5] of char;
    sa_socket: word;
  end;
  PSOCKADDR_IPX = ^SOCKADDR_IPX;
  LPSOCKADDR_IPX = ^SOCKADDR_IPX;
  TSockAddrIpx = SOCKADDR_IPX;
  PSockAddrIpx = ^TSockAddrIpx;

(*
 *   Protocol families used in the "protocol" parameter of the socket() API.
 *
 *)

const
  NSPROTO_IPX = 1000;
  NSPROTO_SPX = 1256;
  NSPROTO_SPXII = 1257;

implementation

end.

