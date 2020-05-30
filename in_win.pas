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

unit in_win;

// in_win.c -- windows 95 mouse and joystick code
// 02/21/97 JCB Added extended DirectInput code to support external controllers.

interface

uses
  q_delphi,
  client;

procedure IN_Init;
procedure IN_Shutdown;
procedure IN_Commands;
procedure IN_Move(cmd: Pusercmd_t);
procedure IN_ClearStates;
procedure IN_Accumulate;
procedure IN_ActivateMouse;
procedure IN_HideMouse;
procedure IN_DeactivateMouse;
procedure IN_ShowMouse;
procedure IN_UpdateClipCursor;
procedure IN_MouseEvent(mstate: integer);

procedure Force_CenterView_f;
procedure Joy_AdvancedUpdate_f;

var
  mouseactive: qboolean;
  uiWheelMessage: unsigned_int;

implementation

uses
  Windows,
  MMsystem,
  cl_main_h,
  quakedef,
  gl_vidnt,
  common,
  cmd,
  keys,
  keys_h,
  cl_main,
  cl_input,
  view,
  host_cmd,
  sys_win,
  console,
  host_h,
  cvar;

var
  m_filter: cvar_t = (name: 'm_filter'; text: '1');
// none of these cvars are saved over a session
// this means that advanced controller configuration needs to be executed
// each time.  this avoids any problems with getting back to a default usage
// or when changing from one controller to another.  this way at least something
// works.
  in_joystick: cvar_t = (name: 'joystick'; text: '0'; archive: true);
  joy_name: cvar_t = (name: 'joyname'; text: 'joystick');
  joy_advanced: cvar_t = (name: 'joyadvanced'; text: '0');
  joy_advaxisx: cvar_t = (name: 'joyadvaxisx'; text: '0');
  joy_advaxisy: cvar_t = (name: 'joyadvaxisy'; text: '0');
  joy_advaxisz: cvar_t = (name: 'joyadvaxisz'; text: '0');
  joy_advaxisr: cvar_t = (name: 'joyadvaxisr'; text: '0');
  joy_advaxisu: cvar_t = (name: 'joyadvaxisu'; text: '0');
  joy_advaxisv: cvar_t = (name: 'joyadvaxisv'; text: '0');
  joy_forwardthreshold: cvar_t = (name: 'joyforwardthreshold'; text: '0.15');
  joy_sidethreshold: cvar_t = (name: 'joysidethreshold'; text: '0.15');
  joy_pitchthreshold: cvar_t = (name: 'joypitchthreshold'; text: '0.15');
  joy_yawthreshold: cvar_t = (name: 'joyyawthreshold'; text: '0.15');
  joy_forwardsensitivity: cvar_t = (name: 'joyforwardsensitivity'; text: '-1.0');
  joy_sidesensitivity: cvar_t = (name: 'joysidesensitivity'; text: '-1.0');
  joy_pitchsensitivity: cvar_t = (name: 'joypitchsensitivity'; text: '1.0');
  joy_yawsensitivity: cvar_t = (name: 'joyyawsensitivity'; text: '-1.0');
  joy_wwhack1: cvar_t = (name: 'joywwhack1'; text: '0.0');
  joy_wwhack2: cvar_t = (name: 'joywwhack2'; text: '0.0');

const
// joystick defines and variables
// where should defines be moved?
  JOY_ABSOLUTE_AXIS = $00000000; // control like a joystick
  JOY_RELATIVE_AXIS = $00000010; // control like a mouse, spinner, trackball
  JOY_MAX_AXES = 6; // X, Y, Z, R, U, V
  JOY_AXIS_X = 0;
  JOY_AXIS_Y = 1;
  JOY_AXIS_Z = 2;
  JOY_AXIS_R = 3;
  JOY_AXIS_U = 4;
  JOY_AXIS_V = 5;

const
  AxisNada = 0;
  AxisForward = 1;
  AxisLook = 2;
  AxisSide = 3;
  AxisTurn = 4;

var
  dwAxisFlags: array[0..JOY_MAX_AXES - 1] of DWORD = (
    JOY_RETURNX,
    JOY_RETURNY,
    JOY_RETURNZ,
    JOY_RETURNR,
    JOY_RETURNU,
    JOY_RETURNV
  );

var
  mouseinitialized: qboolean;
  mouseparmsvalid: qboolean;
  mouseactivatetoggle: qboolean;
  mouseshowtoggle: qboolean = qboolean(1);
  newmouseparms: array[0..2] of integer = (0, 0, 1);

  dwAxisMap: array[0..JOY_MAX_AXES - 1] of DWORD;
  dwControlMap: array[0..JOY_MAX_AXES - 1] of DWORD;
  pdwRawValue: array[0..JOY_MAX_AXES - 1] of PDWORD;
  joy_avail: qboolean;
  joy_advancedinit: qboolean;
  joy_haspov: qboolean;
  joy_oldbuttonstate: DWORD;
  joy_oldpovstate: DWORD;
  joy_id: integer;
  joy_flags: DWORD;
  joy_numbuttons: DWORD;
  ji: JOYINFOEX;
  originalmouseparms: array[0..2] of integer;
  restore_spi: qboolean;
  mouse_buttons: integer;
  mouse_oldbuttonstate: integer;
  current_pos: TPoint;
  mouse_x: integer;
  mouse_y: integer;
  old_mouse_x: integer;
  old_mouse_y: integer;
  mx_accum: integer;
  my_accum: integer;

procedure IN_Accumulate;
begin
  if mouseactive then
  begin
    GetCursorPos(current_pos);

    inc(mx_accum, current_pos.x - window_center_x);
    inc(my_accum, current_pos.y - window_center_y);

    // force the mouse to the center, so there's room to move
    SetCursorPos(window_center_x, window_center_y);
  end;
end;

procedure IN_ActivateMouse;
begin
  mouseactivatetoggle := true;

  if mouseinitialized then
  begin
    if mouseparmsvalid then
      restore_spi := SystemParametersInfo(SPI_SETMOUSE, 0, @newmouseparms, 0);

    SetCursorPos(window_center_x, window_center_y);
    SetCapture(mainwindow);
    ClipCursor(@window_rect);

    mouseactive := true;
  end;
end;

procedure IN_ClearStates;
begin
  if mouseactive then
  begin
    mx_accum := 0;
    my_accum := 0;
    mouse_oldbuttonstate := 0;
  end;
end;

procedure IN_Commands;
var
  i, key_index: integer;
  buttonstate, povstate: DWORD;
begin
  if not joy_avail then
    exit;

  // loop through the joystick buttons
  // key a joystick event or auxillary event for higher number buttons for each state change
  buttonstate := ji.wButtons;
  for i := 0 to joy_numbuttons - 1 do
  begin
    if boolval(buttonstate and (1 shl i)) and not boolval(joy_oldbuttonstate and (1 shl i)) then
    begin
      key_index := decide(i < 4, K_JOY1, K_AUX1);
      Key_ProcessEvent(key_index + i, true);
    end;

    if not boolval(buttonstate and (1 shl i)) and boolval(joy_oldbuttonstate and (1 shl i)) then
    begin
      key_index := decide(i < 4, K_JOY1, K_AUX1);
      Key_ProcessEvent(key_index + i, false);
    end;
  end;
  joy_oldbuttonstate := buttonstate;

  if joy_haspov then
  begin
    // convert POV information into 4 bits of state information
    // this avoids any potential problems related to moving from one
    // direction to another without going through the center position
    povstate := 0;
    if ji.dwPOV <> DWORD(JOY_POVCENTERED) then
    begin
      if ji.dwPOV = JOY_POVFORWARD then
        povstate := povstate or $01;
      if ji.dwPOV = JOY_POVRIGHT then
        povstate := povstate or $02;
      if ji.dwPOV = JOY_POVBACKWARD then
        povstate := povstate or $04;
      if ji.dwPOV = JOY_POVLEFT then
        povstate := povstate or $08;
    end;
    // determine which bits have changed and key an auxillary event for each change
    for i := 0 to 3 do
    begin
      if boolval(povstate and (1 shl i)) and not boolval(joy_oldpovstate and (1 shl i)) then
        Key_ProcessEvent(K_AUX29 + i, true);

      if not boolval(povstate and (1 shl i)) and boolval(joy_oldpovstate and (1 shl i)) then
        Key_ProcessEvent(K_AUX29 + i, false);
    end;
    joy_oldpovstate := povstate;
  end;
end;

procedure IN_DeactivateMouse;
begin
  mouseactivatetoggle := false;

  if mouseinitialized then
  begin
    if restore_spi then
      SystemParametersInfo(SPI_SETMOUSE, 0, @originalmouseparms, 0);

    ClipCursor(nil);
    ReleaseCapture;

    mouseactive := false;
  end;
end;

procedure IN_HideMouse;
begin
  if mouseshowtoggle then
  begin
    ShowCursor(false);
    mouseshowtoggle := false;
  end;
end;

procedure IN_StartupMouse;
begin
  if COM_CheckParm('-nomouse') <> 0 then
    exit;

  mouseinitialized := true;

  mouseparmsvalid := SystemParametersInfo(SPI_GETMOUSE, 0, @originalmouseparms, 0);

  if mouseparmsvalid then
  begin
    if COM_CheckParm('-noforcemspd') <> 0 then
      newmouseparms[2] := originalmouseparms[2];

    if COM_CheckParm('-noforcemaccel') <> 0 then
    begin
      newmouseparms[0] := originalmouseparms[0];
      newmouseparms[1] := originalmouseparms[1];
    end;

    if COM_CheckParm('-noforcemparms') <> 0 then
    begin
      newmouseparms[0] := originalmouseparms[0];
      newmouseparms[1] := originalmouseparms[1];
      newmouseparms[2] := originalmouseparms[2];
    end;
  end;

  mouse_buttons := 3;

// if a fullscreen video mode was set before the mouse was initialized,
// set the mouse state appropriately
  if mouseactivatetoggle then
    IN_ActivateMouse;
end;

procedure IN_StartupJoystick;
var
  numdevs: integer;
  jc: JOYCAPS;
  mmr: MMRESULT;
begin
   // assume no joystick
  joy_avail := false;

  // abort startup if user requests no joystick
  if COM_CheckParm('-nojoy') <> 0 then
    exit;

  // verify joystick driver is present
  numdevs := joyGetNumDevs;
  if numdevs = 0 then
  begin
    Con_Printf(#10'joystick not found -- driver not present'#10#10);
    exit;
  end;
  mmr := 0; // JVAL avoid compiler warning;

  // cycle through the joystick ids for the first valid one
  joy_id := 0;
  while joy_id < numdevs do
  begin
    ZeroMemory(@ji, SizeOf(ji));
    ji.dwSize := SizeOf(ji);
    ji.dwFlags := JOY_RETURNCENTERED;

    mmr := joyGetPosEx(joy_id, @ji);
    if mmr = JOYERR_NOERROR then
      break;
    inc(joy_id);
  end;

  // abort startup if we didn't find a valid joystick
  if mmr <> JOYERR_NOERROR then
  begin
    Con_Printf(#10'joystick not found -- no valid joysticks (%x)'#10#10, [mmr]);
    exit;
  end;

  // get the capabilities of the selected joystick
  // abort startup if command fails
  ZeroMemory(@jc, SizeOf(jc));
  mmr := joyGetDevCaps(joy_id, @jc, SizeOf(jc));
  if mmr <> JOYERR_NOERROR then
  begin
    Con_Printf(#10'joystick not found -- invalid joystick capabilities (%x)'#10#10, [mmr]);
    exit;
  end;

  // save the joystick's number of buttons and POV status
  joy_numbuttons := jc.wNumButtons;
  joy_haspov := jc.wCaps and JOYCAPS_HASPOV <> 0;

  // old button and POV states default to no buttons pressed
  joy_oldbuttonstate := 0;
  joy_oldpovstate := 0;

  // mark the joystick as available and advanced initialization not completed
  // this is needed as cvars are not available during initialization

  joy_avail := true;
  joy_advancedinit := false;

  Con_Printf(#10'joystick detected'#10#10);
end;

procedure IN_Init;
begin
  // mouse variables
  Cvar_RegisterVariable(@m_filter);

  // joystick variables
  Cvar_RegisterVariable(@in_joystick);
  Cvar_RegisterVariable(@joy_name);
  Cvar_RegisterVariable(@joy_advanced);
  Cvar_RegisterVariable(@joy_advaxisx);
  Cvar_RegisterVariable(@joy_advaxisy);
  Cvar_RegisterVariable(@joy_advaxisz);
  Cvar_RegisterVariable(@joy_advaxisr);
  Cvar_RegisterVariable(@joy_advaxisu);
  Cvar_RegisterVariable(@joy_advaxisv);
  Cvar_RegisterVariable(@joy_forwardthreshold);
  Cvar_RegisterVariable(@joy_sidethreshold);
  Cvar_RegisterVariable(@joy_pitchthreshold);
  Cvar_RegisterVariable(@joy_yawthreshold);
  Cvar_RegisterVariable(@joy_forwardsensitivity);
  Cvar_RegisterVariable(@joy_sidesensitivity);
  Cvar_RegisterVariable(@joy_pitchsensitivity);
  Cvar_RegisterVariable(@joy_yawsensitivity);
  Cvar_RegisterVariable(@joy_wwhack1);
  Cvar_RegisterVariable(@joy_wwhack2);

  Cmd_AddCommand('force_centerview', Force_CenterView_f);
  Cmd_AddCommand('joyadvancedupdate', Joy_AdvancedUpdate_f);

  uiWheelMessage := RegisterWindowMessage('MSWHEEL_ROLLMSG');

  IN_StartupMouse;
  IN_StartupJoystick;
end;

function IN_ReadJoystick: qboolean;
begin
  ZeroMemory(@ji, SizeOf(ji));
  ji.dwSize := SizeOf(ji);
  ji.dwFlags := joy_flags;

  if joyGetPosEx(joy_id, @ji) = JOYERR_NOERROR then
  begin
    // this is a hack -- there is a bug in the Logitech WingMan Warrior DirectInput Driver
    // rather than having 32768 be the zero point, they have the zero point at 32668
    // go figure -- anyway, now we get the full resolution out of the device
    if joy_wwhack1.value <> 0.0 then
      ji.dwUpos := ji.dwUpos + 100;

    result := true;
    exit;
  end
  else
  begin
    // read error occurred
    // turning off the joystick seems too harsh for 1 read error,\
    // but what should be done?
    // Con_Printf ("IN_ReadJoystick: no response\n");
    // joy_avail = false;
    result := false;
  end;
end;

procedure IN_JoyMove(cmd: Pusercmd_t);
var
  speed, aspeed: single;
  fAxisValue, fTemp: single;
  i: integer;
begin
  // complete initialization if first time in
  // this is needed as cvars are not available at initialization time
  if not joy_advancedinit then
  begin
    Joy_AdvancedUpdate_f;
    joy_advancedinit := true;
  end;

  // verify joystick is available and that the user wants to use it
  if not joy_avail or not boolval(in_joystick.value) then
    exit;

  // collect the joystick data, if possible
  if not IN_ReadJoystick then
    exit;

  if (in_speed.state and 1) <> 0 then
    speed := cl_movespeedkey.value
  else
    speed := 1.0;
  aspeed := speed * host_frametime;

  // loop through the axes
  for i := 0 to JOY_MAX_AXES - 1 do
  begin
    // get the floating point zero-centered, potentially-inverted data for the current axis
    fAxisValue := pdwRawValue[i]^; // JVAL mayby add - 32768.0; here
    // move centerpoint to zero
    fAxisValue := fAxisValue - 32768.0;

    if joy_wwhack2.value <> 0.0 then
    begin
      if dwAxisMap[i] = AxisTurn then
      begin
        // this is a special formula for the Logitech WingMan Warrior
        // y=ax^b; where a = 300 and b = 1.3
        // also x values are in increments of 800 (so this is factored out)
        // then bounds check result to level out excessively high spin rates
        fTemp := 300.0 * fpow(abs(fAxisValue) / 800.0, 1.3);
        if fTemp > 14000.0 then
          fTemp := 14000.0;
        // restore direction information
        if fAxisValue > 0.0 then
          fAxisValue := fTemp
        else
          fAxisValue := -fTemp;
      end;
    end;

    // convert range from -32768..32767 to -1..1
    fAxisValue := fAxisValue / 32768.0;

    case dwAxisMap[i] of
      AxisForward:
        begin
          if (joy_advanced.value = 0.0) and boolval(in_mlook.state and 1) then
          begin
            // user wants forward control to become look control
            if abs(fAxisValue) > joy_pitchthreshold.value then
            begin
              // if mouse invert is on, invert the joystick pitch value
              // only absolute control support here (joy_advanced is false)
              if m_pitch.value < 0.0 then
              begin
                cl.viewangles[PITCH] := cl.viewangles[PITCH] -
                  (fAxisValue * joy_pitchsensitivity.value) * aspeed * cl_pitchspeed.value;
              end
              else
              begin
                cl.viewangles[PITCH] := cl.viewangles[PITCH] +
                  (fAxisValue * joy_pitchsensitivity.value) * aspeed * cl_pitchspeed.value;
              end;
              V_StopPitchDrift;
            end
            else
            begin
              // no pitch movement
              // disable pitch return-to-center unless requested by user
              // *** this code can be removed when the lookspring bug is fixed
              // *** the bug always has the lookspring feature on
              if lookspring.value = 0.0 then
                V_StopPitchDrift;
            end;
          end
          else
          begin
            // user wants forward control to be forward control
            if abs(fAxisValue) > joy_forwardthreshold.value then
            begin
              cmd.forwardmove := cmd.forwardmove +
                (fAxisValue * joy_forwardsensitivity.value) * speed * cl_forwardspeed.value;
            end;
          end;
        end;

      AxisSide:
        begin
          if abs(fAxisValue) > joy_sidethreshold.value then
            cmd.sidemove := cmd.sidemove +
              (fAxisValue * joy_sidesensitivity.value) * speed * cl_sidespeed.value;
        end;

      AxisTurn:
        begin
          if boolval(in_strafe.state and 1) or (boolval(lookstrafe.value) and boolval(in_mlook.state and 1)) then
          begin
            // user wants turn control to become side control
            if abs(fAxisValue) > joy_sidethreshold.value then
            begin
              cmd.sidemove := cmd.sidemove -
                (fAxisValue * joy_sidesensitivity.value) * speed * cl_sidespeed.value;
            end;
          end
          else
          begin
            // user wants turn control to be turn control
            if abs(fAxisValue) > joy_yawthreshold.value then
            begin
              if dwControlMap[i] = JOY_ABSOLUTE_AXIS then
              begin
                cl.viewangles[YAW] := cl.viewangles[YAW] +
                  (fAxisValue * joy_yawsensitivity.value) * aspeed * cl_yawspeed.value;
              end
              else
              begin
                cl.viewangles[YAW] := cl.viewangles[YAW] +
                  (fAxisValue * joy_yawsensitivity.value) * speed * 180.0;
              end;

            end;
          end;
        end;

      AxisLook:
        begin
          if (in_mlook.state and 1) <> 0 then
          begin
            if abs(fAxisValue) > joy_pitchthreshold.value then
            begin
              // pitch movement detected and pitch movement desired by user
              if dwControlMap[i] = JOY_ABSOLUTE_AXIS then
              begin
                cl.viewangles[PITCH] := cl.viewangles[PITCH] +
                  (fAxisValue * joy_pitchsensitivity.value) * aspeed * cl_pitchspeed.value;
              end
              else
              begin
                cl.viewangles[PITCH] := cl.viewangles[PITCH] +
                  (fAxisValue * joy_pitchsensitivity.value) * speed * 180.0;
              end;
              V_StopPitchDrift;
            end
            else
            begin
              // no pitch movement
              // disable pitch return-to-center unless requested by user
              // *** this code can be removed when the lookspring bug is fixed
              // *** the bug always has the lookspring feature on
              if lookspring.value = 0.0 then
                V_StopPitchDrift;
            end;
          end;
        end;

    end;
  end;

  // bounds check pitch
  CL_AdjustPitch;
end;

function IN_RawValuePointer(axis: integer): PDWORD;
begin
  case axis of
    JOY_AXIS_X: result := @ji.wXpos;
    JOY_AXIS_Y: result := @ji.wYpos;
    JOY_AXIS_Z: result := @ji.wZpos;
    JOY_AXIS_R: result := @ji.dwRpos;
    JOY_AXIS_U: result := @ji.dwUpos;
    JOY_AXIS_V: result := @ji.dwVpos;
  else
    result := nil;
  end;
end;

procedure IN_Joy_AdvancedUpdate;
  // called once by IN_ReadJoystick and by user whenever an update is needed
  // cvars are now available
var
  i: integer;
  dwTemp: DWORD;
begin
  // initialize all the maps
  for i := 0 to JOY_MAX_AXES - 1 do
  begin
    dwAxisMap[i] := AxisNada;
    dwControlMap[i] := JOY_ABSOLUTE_AXIS;
    pdwRawValue[i] := IN_RawValuePointer(i);
  end;

  if joy_advanced.value = 0.0 then
  begin
    // default joystick initialization
    // 2 axes only with joystick control
    dwAxisMap[JOY_AXIS_X] := AxisTurn;
    // dwControlMap[JOY_AXIS_X] = JOY_ABSOLUTE_AXIS;
    dwAxisMap[JOY_AXIS_Y] := AxisForward;
    // dwControlMap[JOY_AXIS_Y] = JOY_ABSOLUTE_AXIS;
  end
  else
  begin
    if Q_strcmp(joy_name.text, 'joystick') <> 0 then
    begin
      // notify user of advanced controller
      Con_Printf(#10'%s configured'#10#10, [joy_name.text]);
    end;

    // advanced initialization here
    // data supplied by user via joy_axisn cvars
    dwTemp := DWORD(intval(joy_advaxisx.value));
    dwAxisMap[JOY_AXIS_X] := dwTemp and $0000000F;
    dwControlMap[JOY_AXIS_X] := dwTemp and JOY_RELATIVE_AXIS;

    dwTemp := DWORD(intval(joy_advaxisy.value));
    dwAxisMap[JOY_AXIS_Y] := dwTemp and $0000000F;
    dwControlMap[JOY_AXIS_Y] := dwTemp and JOY_RELATIVE_AXIS;

    dwTemp := DWORD(intval(joy_advaxisz.value));
    dwAxisMap[JOY_AXIS_Z] := dwTemp and $0000000F;
    dwControlMap[JOY_AXIS_Z] := dwTemp and JOY_RELATIVE_AXIS;

    dwTemp := DWORD(intval(joy_advaxisr.value));
    dwAxisMap[JOY_AXIS_R] := dwTemp and $0000000F;
    dwControlMap[JOY_AXIS_R] := dwTemp and JOY_RELATIVE_AXIS;

    dwTemp := DWORD(intval(joy_advaxisu.value));
    dwAxisMap[JOY_AXIS_U] := dwTemp and $0000000F;
    dwControlMap[JOY_AXIS_U] := dwTemp and JOY_RELATIVE_AXIS;

    dwTemp := DWORD(intval(joy_advaxisv.value));
    dwAxisMap[JOY_AXIS_V] := dwTemp and $0000000F;
    dwControlMap[JOY_AXIS_V] := dwTemp and JOY_RELATIVE_AXIS;
  end;

  // compute the axes to collect from DirectInput
  joy_flags := JOY_RETURNCENTERED or JOY_RETURNBUTTONS or JOY_RETURNPOV;
  for i := 0 to JOY_MAX_AXES - 1 do
  begin
    if dwAxisMap[i] <> AxisNada then
      joy_flags := joy_flags or dwAxisFlags[i];
  end;
end;

procedure IN_MouseEvent(mstate: integer);
var
  i: integer;
begin
  if mouseactive then
  begin
  // perform button actions
    for i := 0 to mouse_buttons - 1 do
    begin
      if boolval(mstate and (1 shl i)) and not boolval(mouse_oldbuttonstate and (1 shl i)) then
        Key_ProcessEvent(K_MOUSE1 + i, true);

      if not boolval(mstate and (1 shl i)) and boolval(mouse_oldbuttonstate and (1 shl i)) then
        Key_ProcessEvent(K_MOUSE1 + i, false);
    end;

    mouse_oldbuttonstate := mstate;
  end;
end;

procedure IN_MouseMove(cmd: Pusercmd_t);
var
  mx, my: integer;
begin
  if not mouseactive then
    exit;

  GetCursorPos(current_pos);
  mx := current_pos.x - window_center_x + mx_accum;
  my := current_pos.y - window_center_y + my_accum;
  mx_accum := 0;
  my_accum := 0;

//if (mx ||  my)
//  Con_DPrintf("mx=%d, my=%d\n", mx, my);

  if m_filter.value <> 0 then
  begin
    mouse_x := (mx + old_mouse_x) div 2;
    mouse_y := (my + old_mouse_y) div 2;
  end
  else
  begin
    mouse_x := mx;
    mouse_y := my;
  end;

  old_mouse_x := mx;
  old_mouse_y := my;

  mouse_x := intval(mouse_x * sensitivity.value);
  mouse_y := intval(mouse_y * sensitivity.value);

// add mouse X/Y movement to cmd
  if boolval(in_strafe.state and 1) or (boolval(lookstrafe.value) and boolval(in_mlook.state and 1)) then
    cmd.sidemove := cmd.sidemove + m_side.value * mouse_x
  else
    cl.viewangles[YAW] := cl.viewangles[YAW] - m_yaw.value * mouse_x;

  if (in_mlook.state and 1) <> 0 then
    V_StopPitchDrift;

  if boolval(in_mlook.state and 1) and (not boolval(in_strafe.state and 1)) then
  begin
    cl.viewangles[PITCH] := cl.viewangles[PITCH] + m_pitch.value * mouse_y;

    if cl.viewangles[PITCH] > 80 then
      cl.viewangles[PITCH] := 80;

    if cl.viewangles[PITCH] < -70 then
      cl.viewangles[PITCH] := -70;
  end
  else
  begin
    if boolval(in_strafe.state and 1) and noclip_anglehack then
      cmd.upmove := cmd.upmove - m_forward.value * mouse_y
    else
      cmd.forwardmove := cmd.forwardmove - m_forward.value * mouse_y;
  end;

// if the mouse has moved, force it to the center, so there's room to move
  if (mx <> 0) or (my <> 0) then
    SetCursorPos(window_center_x, window_center_y);
end;

procedure IN_Move(cmd: Pusercmd_t);
begin
  if ActiveApp and not Minimized then
  begin
    IN_MouseMove(cmd);
    IN_JoyMove(cmd);
  end;
end;

procedure IN_RestoreOriginalMouseState;
begin
  if mouseactivatetoggle then
  begin
    IN_DeactivateMouse;
    mouseactivatetoggle := true;
  end;

// try to redraw the cursor so it gets reinitialized, because sometimes it
// has garbage after the mode switch
  ShowCursor(true);
  ShowCursor(false);
end;

procedure IN_SetQuakeMouseState;
begin
  if mouseactivatetoggle then
    IN_ActivateMouse;
end;

procedure IN_ShowMouse;
begin
  if not mouseshowtoggle then
  begin
    ShowCursor(true);
    mouseshowtoggle := true;
  end;
end;

procedure IN_Shutdown;
begin
  IN_DeactivateMouse;
  IN_ShowMouse;
end;

procedure IN_UpdateClipCursor;
begin
  if mouseinitialized and mouseactive then
    ClipCursor(@window_rect);
end;

procedure Force_CenterView_f;
begin
  cl.viewangles[PITCH] := 0;
end;

procedure Joy_AdvancedUpdate_f;
begin
  IN_Joy_AdvancedUpdate;
end;

end.

