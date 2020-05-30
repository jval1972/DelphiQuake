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

unit cl_demo;

(*
==============================================================================

DEMO CODE

When a demo is playing back, all NET_SendMessages are skipped, and
NET_GetMessages are read from the demo file.

Whenever cl.time gets past the last received message, another message is
read from the demo file.
==============================================================================
*)


interface

procedure CL_FinishTimeDemo;

procedure CL_StopPlayback;

function CL_GetMessage: integer;

procedure CL_Stop_f;

procedure CL_Record_f;

procedure CL_PlayDemo_f;

procedure CL_TimeDemo_f;

implementation

uses
  q_delphi,
  cl_main_h,
  client,
  common,
  net_main,
  host_h,
  mathlib,
  quakedef,
  sys_win,
  protocol,
  console,
  cmd,
  cl_main;

(*
==============
CL_StopPlayback

Called when a demo file runs out, or the user starts a game
==============
*)
procedure CL_StopPlayback;
begin
  if not cls.demoplayback then
    exit;

  fclose(cls.demofile);
  cls.demoplayback := false;
//  cls.demofile = NULL;
	cls.state := ca_disconnected;

  if cls.timedemo then
    CL_FinishTimeDemo;
end;

(*
====================
CL_WriteDemoMessage

Dumps the current net message, prefixed by the length and view angles
====================
*)
procedure CL_WriteDemoMessage;
var
  len: integer;
  i: integer;
  f: single;
begin
  len := LittleLong(net_message.cursize);
  fwrite(@len, 4, 1, cls.demofile);
  for  i := 0 to 2 do
  begin
    f := LittleFloat(cl.viewangles[i]);
    fwrite(@f, 4, 1, cls.demofile);
//    BlockWrite(cls.demofile, f, 4);
  end;
  fwrite(net_message.data, net_message.cursize, 1, cls.demofile);
//  BlockWrite(cls.demofile, net_message.data^, net_message.cursize);
//  fflush (cls.demofile);
end;

(*
====================
CL_GetMessage

Handles recording and playback of demos, on top of NET_ code
====================
*)
function CL_GetMessage: integer;
var
  i: integer;
  f: single;
begin
  result := 0;
  if cls.demoplayback then
  begin
  // decide if it is time to grab the next message
    if cls.signon = SIGNONS then // allways grab until fully connected
    begin
      if cls.timedemo then
      begin
        if host_framecount = cls.td_lastframe then
        begin
          result := 0; // allready read this frame's message
          exit;
        end;
        cls.td_lastframe := host_framecount;
      // if this is the second frame, grab the real td_starttime
      // so the bogus time on the first frame doesn't count
        if host_framecount = cls.td_startframe + 1 then
          cls.td_starttime := realtime;
      end
      else if cl.time <= cl.mtime[0] then
      begin
        result := 0; // don't need another message yet
        exit;
      end;
    end;

  // get the next message
    fread(@net_message.cursize, 4, 1, cls.demofile);
    VectorCopy(@cl.mviewangles[0], @cl.mviewangles[1]);
    for i := 0 to 2 do
    begin
      fread(@f, 4, 1, cls.demofile);
      cl.mviewangles[0][i] := LittleFloat(f);
    end;

    net_message.cursize := LittleLong(net_message.cursize);
    if net_message.cursize > MAX_MSGLEN then
    begin
      // Sys_Error('Demo message > MAX_MSGLEN');
      Con_Printf('Warning(): Demo message > MAX_MSGLEN'#10);
      result := 0;
      exit;
    end;

    result := fread(net_message.data, net_message.cursize, 1, cls.demofile);
    if result <> 1 then
    begin
      CL_StopPlayback;
			result := 0;
      exit;
    end;

    exit;
  end;

  while true do
  begin
    result := NET_GetMessage(cls.netcon);

    if (result <> 1) and (result <> 2) then
    begin
      exit;
    end;

  // discard nop keepalive message
    if (net_message.cursize = 1) and (net_message.data[0] = svc_nop) then
      Con_Printf('<-- server to client keepalive'#10)
    else
			break;
  end;

  if cls.demorecording then
    CL_WriteDemoMessage;
end;


(*
====================
CL_Stop_f

stop recording a demo
====================
*)
procedure CL_Stop_f;
begin
  if cmd_source <> src_command then
    exit;

  if not cls.demorecording then
  begin
    Con_Printf('Not recording a demo.'#10);
    exit;
  end;

// write a disconnect message to the demo file
  SZ_Clear(@net_message);
  MSG_WriteByte(@net_message, svc_disconnect);
  CL_WriteDemoMessage;

// finish up
  fclose(cls.demofile);
  cls.demorecording := false;
  Con_Printf('Completed demo'#10);
end;

(*
====================
CL_Record_f

record <demoname> <map> [cd track]
====================
*)
procedure CL_Record_f;
var
  c: integer;
  name: array[0..MAX_OSPATH - 1] of char;
  track: integer;
begin
  if cmd_source <> src_command then
    exit;

  c := Cmd_Argc_f;
  if (c <> 2) and (c <> 3) and (c <> 4) then
  begin
    Con_Printf('record <demoname> [<map> [cd track]]'#10);
    exit;
  end;

	if strstr(Cmd_Argv_f(1), '..') <> nil then
  begin
    Con_Printf('Relative pathnames are not allowed.'#10);
    exit;
  end;

  if (c = 2) and (cls.state = ca_connected) then
  begin
    Con_Printf('Can not record - already connected to server'#10'Client demo recording must be started before connecting'#10);
    exit;
  end;

// write the forced cd track number, or -1
  if c = 4 then
  begin
    track := atoi(Cmd_Argv_f(3));
    Con_Printf('Forcing CD track to %d'#10, [cls.forcetrack]);
  end
  else
    track := -1;

  sprintf(name, '%s/%s', [com_gamedir, Cmd_Argv_f(1)]);

//
// start the map up
//
  if c > 2 then
    Cmd_ExecuteString(va('map %s', [Cmd_Argv_f(2)]), src_command);

//
// open the demo file
//
  COM_DefaultExtension(name, '.dem');

  Con_Printf('recording to %s'#10, [name]);
//  cls.demofile = fopen (name, "wb");
  cls.demofile := fopen(name, 'wb');
	if cls.demofile = -1 then
  begin
    Con_Printf('ERROR: couldn''t open.'#10);
    exit;
  end;

  cls.forcetrack := track;
  fprintf(cls.demofile, '%d'#10, [cls.forcetrack]);

  cls.demorecording := true;
end;


(*
====================
CL_PlayDemo_f

play [demoname]
====================
*)
procedure CL_PlayDemo_f;
var
  name: PChar;
  c: char;
  neg: qboolean;
  oret: integer;
begin
  neg := false;

  if cmd_source <> src_command then
    exit;

  if Cmd_Argc_f <> 2 then
  begin
    Con_Printf('play <demoname> : plays a demo'#10);
    exit;
  end;

//
// disconnect from server
//
  CL_Disconnect;

//
// open the demo file
//
	name := Cmd_Argv_f(1);
  COM_DefaultExtension(name, '.dem');

  Con_Printf('Playing demo from %s.'#10, [name]);
  oret := COM_FOpenFile(name, cls.demofile);
  if oret < 0 then
  begin
    Con_Printf('ERROR: couldn''t open.'#10);
    cls.demonum := -1;		// stop demo loop
    exit;
  end;

  cls.demoplayback := true;
  cls.state := ca_connected;
  cls.forcetrack := 0;

  while not (getc(cls.demofile, c) in [#13, #10]) do
  begin
    if c = '-' then
      neg := true
    else
      cls.forcetrack := cls.forcetrack * 10 + (Ord(c) - Ord('0'));
  end;

  if neg then
    cls.forcetrack := -cls.forcetrack;
// ZOID, fscanf is evil
//	fscanf (cls.demofile, "%d\n", &cls.forcetrack);
end;

(*
====================
CL_FinishTimeDemo

====================
*)
procedure CL_FinishTimeDemo;
var
  frames: integer;
  time: single;
begin
  cls.timedemo := false;

// the first frame didn't count
  frames := (host_framecount - cls.td_startframe) - 1;
  time := realtime - cls.td_starttime;
  if time = 0 then
    time := 1;
  Con_Printf('%d frames %5.3f seconds %5.3f fps'#10, [frames, time, frames / time]);
end;

(*
====================
CL_TimeDemo_f

timedemo [demoname]
====================
*)
procedure CL_TimeDemo_f;
begin
  if cmd_source <> src_command then
    exit;

  if Cmd_Argc_f <> 2 then
  begin
    Con_Printf('timedemo <demoname> : gets demo speeds'#10);
    exit;
  end;

  CL_PlayDemo_f;

// cls.td_starttime will be grabbed at the second frame of the demo, so
// all the loading time doesn't get counted

  cls.timedemo := true;
  cls.td_startframe := host_framecount;
  cls.td_lastframe := -1;		// get a new message this frame
end;

end.
