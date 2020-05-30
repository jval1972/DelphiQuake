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

unit net_win;

interface

uses
  net;

var
  net_drivers: array[0..MAX_NET_DRIVERS - 1] of net_driver_t;

  net_numdrivers: integer = 2;


var
  net_landrivers: array[0..MAX_NET_DRIVERS - 1] of net_landriver_t;

  net_numlandrivers: integer = 2;


implementation

uses
  net_loop,
  net_dgrm,
  net_wins,
  net_wipx;

procedure InitNetDrivers;
begin
  net_drivers[0].name := 'Loopback';
  net_drivers[0].initialized := false;
  net_drivers[0].Init := @Loop_Init;
  net_drivers[0].Listen := @Loop_Listen;
  net_drivers[0].SearchForHosts := @Loop_SearchForHosts;
  net_drivers[0].Connect := @Loop_Connect;
  net_drivers[0].CheckNewConnections := @Loop_CheckNewConnections;
  net_drivers[0].QGetMessage := @Loop_GetMessage;
  net_drivers[0].QSendMessage := @Loop_SendMessage;
  net_drivers[0].SendUnreliableMessage := @Loop_SendUnreliableMessage;
  net_drivers[0].CanSendMessage := @Loop_CanSendMessage;
  net_drivers[0].CanSendUnreliableMessage := @Loop_CanSendUnreliableMessage;
  net_drivers[0].Close := @Loop_Close;
  net_drivers[0].Shutdown := @Loop_Shutdown;

  net_drivers[1].name := 'Datagram';
  net_drivers[1].initialized := false;
  net_drivers[1].Init := @Datagram_Init;
  net_drivers[1].Listen := @Datagram_Listen;
  net_drivers[1].SearchForHosts := @Datagram_SearchForHosts;
  net_drivers[1].Connect := @Datagram_Connect;
  net_drivers[1].CheckNewConnections := @Datagram_CheckNewConnections;
  net_drivers[1].QGetMessage := @Datagram_GetMessage;
  net_drivers[1].QSendMessage := @Datagram_SendMessage;
  net_drivers[1].SendUnreliableMessage := @Datagram_SendUnreliableMessage;
  net_drivers[1].CanSendMessage := @Datagram_CanSendMessage;
  net_drivers[1].CanSendUnreliableMessage := @Datagram_CanSendUnreliableMessage;
  net_drivers[1].Close := @Datagram_Close;
  net_drivers[1].Shutdown := @Datagram_Shutdown;
end;

procedure InitLanDrivers;
begin
  net_landrivers[0].name := 'Winsock TCPIP';
  net_landrivers[0].initialized := false;
  net_landrivers[0].controlSock := 0;
  net_landrivers[0].Init := @WINS_Init;
  net_landrivers[0].Shutdown := @WINS_Shutdown;
  net_landrivers[0].Listen := @WINS_Listen;
  net_landrivers[0].OpenSocket := @WINS_OpenSocket;
  net_landrivers[0].CloseSocket := @WINS_CloseSocket;
  net_landrivers[0].Connect := @WINS_Connect;
  net_landrivers[0].CheckNewConnections := @WINS_CheckNewConnections;
  net_landrivers[0].Read := @WINS_Read;
  net_landrivers[0].Write := @WINS_Write;
  net_landrivers[0].Broadcast := @WINS_Broadcast;
  net_landrivers[0].AddrToString := @WINS_AddrToString;
  net_landrivers[0].StringToAddr := @WINS_StringToAddr;
  net_landrivers[0].GetSocketAddr := @WINS_GetSocketAddr;
  net_landrivers[0].GetNameFromAddr := @WINS_GetNameFromAddr;
  net_landrivers[0].GetAddrFromName := @WINS_GetAddrFromName;
  net_landrivers[0].AddrCompare := @WINS_AddrCompare;
  net_landrivers[0].GetSocketPort := @WINS_GetSocketPort;
  net_landrivers[0].SetSocketPort := @WINS_SetSocketPort;

  net_landrivers[1].name := 'Winsock IPX';
  net_landrivers[1].initialized := false;
  net_landrivers[1].controlSock := 0;
  net_landrivers[1].Init := @WIPX_Init;
  net_landrivers[1].Shutdown := @WIPX_Shutdown;
  net_landrivers[1].Listen := @WIPX_Listen;
  net_landrivers[1].OpenSocket := @WIPX_OpenSocket;
  net_landrivers[1].CloseSocket := @WIPX_CloseSocket;
  net_landrivers[1].Connect := @WIPX_Connect;
  net_landrivers[1].CheckNewConnections := @WIPX_CheckNewConnections;
  net_landrivers[1].Read := @WIPX_Read;
  net_landrivers[1].Write := @WIPX_Write;
  net_landrivers[1].Broadcast := @WIPX_Broadcast;
  net_landrivers[1].AddrToString := @WIPX_AddrToString;
  net_landrivers[1].StringToAddr := @WIPX_StringToAddr;
  net_landrivers[1].GetSocketAddr := @WIPX_GetSocketAddr;
  net_landrivers[1].GetNameFromAddr := @WIPX_GetNameFromAddr;
  net_landrivers[1].GetAddrFromName := @WIPX_GetAddrFromName;
  net_landrivers[1].AddrCompare := @WIPX_AddrCompare;
  net_landrivers[1].GetSocketPort := @WIPX_GetSocketPort;
  net_landrivers[1].SetSocketPort := @WIPX_SetSocketPort;
end;

initialization
  InitNetDrivers;
  InitLanDrivers;

end.

