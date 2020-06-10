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

{$WARN SYMBOL_DEPRECATED OFF}
{$WARN SYMBOL_PLATFORM OFF}	

unit sys_win;

// sys_win.c -- Win32 system interface code

interface

uses
  q_delphi,
  Windows;

procedure Sys_Error(error: PChar); overload;
procedure Sys_Error(error: PChar; const Args: array of const); overload;
procedure Sys_Error(error: string); overload;
procedure Sys_Error(error: string; const Args: array of const); overload;
function Sys_FloatTime: double;
procedure Sys_Quit;
procedure Sys_Printf(fmt: PChar); overload;
procedure Sys_Printf(fmt: PChar; const Args: array of const); overload;
procedure Sys_Printf(fmt: string); overload;
procedure Sys_Printf(fmt: string; const Args: array of const); overload;
function Sys_ConsoleInput: PChar;
procedure Sys_SendKeyEvents;
procedure Sys_InitFileHandles;

function Sys_FileOpenRead(path: PChar; hndl: PInteger): integer;
function Sys_FileRead(handle: integer; dest: pointer; count: integer): integer;
function Sys_FileOpenWrite(path: PChar): integer;
function Sys_FileWrite(handle: integer; data: pointer; count: integer): integer;
procedure Sys_FileClose(handle: integer);
procedure Sys_FileSeek(handle: integer; position: integer);
function Sys_FileTime(path: PChar): integer;

procedure Sys_mkdir(path: PChar);

procedure Sys_Sleep(const msecs: integer = 1);

var
  global_hInstance: THandle;

  hwnd_dialog: HWND;

var
  ActiveApp, Minimized: qboolean;
  isDedicated: qboolean;

function WinMain: integer;

implementation

uses
  gl_vidnt,
  common,
  host,
  conproc,
  quakedef,
  snd_win,
  host_h,
  cl_main_h,
  gl_screen,
  zone,
  SysUtils;

const
  MINIMUM_WIN_MEMORY = $0880000;
  MAXIMUM_WIN_MEMORY = $2000000;

  CONSOLE_ERROR_TIMEOUT = 60.0; // # of seconds to wait on Sys_Error running
                                //  dedicated before exiting
  PAUSE_SLEEP = 50; // sleep time on pause or minimization
  NOT_FOCUS_SLEEP = 20; // sleep time when not focus

var
  WinNT: qboolean;

var
  pfreq: double;
  curtime: double = 0.0;
  lastcurtime: double = 0.0;
  lowshift: unsigned;
  sc_return_on_enter: qboolean = false;
  hinput, houtput: THandle;

//static char      *tracking_tag := 'Clams & Mooses';

var
  tevent: THandle;
  hFile: THandle = 0;
  heventParent: THandle;
  heventChild: THandle;

var
  sys_checksum: integer; // JVAL was volatile


(*
================
Sys_PageIn
================
*)

procedure Sys_PageIn(ptr: pointer; size: integer);
var
  x: PByteArray;
  m, n: integer;
begin
// touch all the memory to make sure it's there. The 16-page skip is to
// keep Win 95 from thinking we're trying to page ourselves in (we are
// doing that, of course, but there's no reason we shouldn't)
  x := PByteArray(ptr);

  for n := 0 to 3 do
  begin
    m := 0;
    while m < (size - 16 * $1000) do
    begin
      sys_checksum := sys_checksum + PInteger(@x[m])^;
      sys_checksum := sys_checksum + PInteger(@x[m + 16 * $1000])^;
      inc(m, 4);
    end;
  end;
end;


(*
===============================================================================

FILE IO

===============================================================================
*)

const
  MAX_HANDLES = 10;

var
  sys_handles: array[0..MAX_HANDLES - 1] of integer;

procedure Sys_InitFileHandles;
var
  i: integer;
begin
  for i := 1 to MAX_HANDLES - 1 do
    sys_handles[i] := NULLFILE;
end;

function findhandle: integer;
var
  i: integer;
begin
  for i := 1 to MAX_HANDLES - 1 do
    if sys_handles[i] = -1 then
    begin
      result := i;
      exit;
    end;
  Sys_Error('out of handles');
  result := -1;
end;

(*
================
filelength
================
*)

function filelength(var f: file): integer;
var
  t: integer;
begin
  t := VID_ForceUnlockedAndReturnState;

  result := filesize(f);

  VID_ForceLockState(t);
end;

function Sys_FileOpenRead(path: PChar; hndl: PInteger): integer;
var
  f: integer;
  i: integer;
  t: integer;
begin
  t := VID_ForceUnlockedAndReturnState;

  i := findhandle;

  f := fopen(path, 'rb');

  if f = NULLFILE then
  begin
    hndl^ := -1;
    result := -1;
  end
  else
  begin
    sys_handles[i] := f;
    hndl^ := i;
    result := fseek(f, 0, 2);
    fseek(f, 0, 0);
  end;

  VID_ForceLockState(t);
end;

function Sys_FileOpenWrite(path: PChar): integer;
var
  f: integer;
  t: integer;
begin
  t := VID_ForceUnlockedAndReturnState;

  result := findhandle;

  f := fopen(path, 'wb');
  if f = NULLFILE then
    Sys_Error('Error opening %s', [path]);
  sys_handles[result] := f;

  VID_ForceLockState(t);
end;

procedure Sys_FileClose(handle: integer);
var
  t: integer;
begin
  t := VID_ForceUnlockedAndReturnState;
  fclose(sys_handles[handle]);
  VID_ForceLockState(t);
end;

procedure Sys_FileSeek(handle: integer; position: integer);
var
  t: integer;
begin
  t := VID_ForceUnlockedAndReturnState;
  fseek(sys_handles[handle], position, 0);
  VID_ForceLockState(t);
end;

function Sys_FileRead(handle: integer; dest: pointer; count: integer): integer;
var
  t: integer;
begin
  t := VID_ForceUnlockedAndReturnState;
  result := fread(dest, 1, count, sys_handles[handle]);
  VID_ForceLockState(t);
end;

function Sys_FileWrite(handle: integer; data: pointer; count: integer): integer;
var
  t: integer;
begin
  t := VID_ForceUnlockedAndReturnState;
  result := fwrite(data, 1, count, sys_handles[handle]);
  VID_ForceLockState(t);
end;

function Sys_FileTime(path: PChar): integer;
var
  f: integer;
  t: integer;
begin
  t := VID_ForceUnlockedAndReturnState;

  f := fopen(path, 'rb');

  if f <> NULLFILE then
  begin
    fclose(f);
    result := 1;
  end
  else
  begin
    result := -1;
  end;

  VID_ForceLockState(t);
end;

procedure Sys_mkdir(path: PChar);
var
  s: string;
begin
  FixFileName(path);
  s := Path;
  if s = '' then
    exit;
  if not (s[Length(s) - 1] in ['\', '/']) then
    s := s + '\';
  if not DirectoryExists(s) then
    mkdir(s);
end;


(*
===============================================================================

SYSTEM IO

===============================================================================
*)

(*
================
Sys_MakeCodeWriteable
================
*)

procedure Sys_MakeCodeWriteable(startaddr: unsigned; length: unsigned);
var
  flOldProtect: DWORD;
begin
  if not VirtualProtect(pointer(startaddr), length, PAGE_READWRITE, @flOldProtect) then
    Sys_Error('Protection change failed'#10);
end;


procedure Sys_SetFPCW;
begin
end;

(*
================
Sys_InitFloatTime
================
*)

procedure Sys_InitFloatTime;
var
  j: integer;
begin

  Sys_FloatTime;

  j := COM_CheckParm('-starttime');

  if j <> 0 then
  begin
    curtime := Q_atof(com_argv[j + 1]);
  end
  else
  begin
    curtime := 0.0;
  end;

  lastcurtime := curtime;
end;



(*
================
Sys_Init
================
*)

procedure Sys_Init;
var
  PerformanceFreq: TLargeInteger;
  lowpart, highpart: unsigned;
  vinfo: TOSVersionInfo;
begin

  Sys_SetFPCW;

  if not QueryPerformanceFrequency(PerformanceFreq) then
    Sys_Error('No hardware timer available');

// get 32 out of the 64 time bits such that we have around
// 1 microsecond resolution
  lowpart := unsigned(LARGE_INTEGER(PerformanceFreq).LowPart);
  highpart := unsigned(LARGE_INTEGER(PerformanceFreq).HighPart);
  lowshift := 0;

  while (highpart <> 0) or (lowpart > 2000000.0) do
  begin
    inc(lowshift);
    lowpart := lowpart div 2;
    lowpart := lowpart or ((highpart and 1) shl 31);
    highpart := highpart div 2;
  end;

  pfreq := 1.0 / lowpart;

  Sys_InitFloatTime;

  vinfo.dwOSVersionInfoSize := SizeOf(vinfo);

  if not GetVersionEx(vinfo) then
    Sys_Error('Couldn''t get OS info');

  if (vinfo.dwMajorVersion < 4) or (vinfo.dwPlatformId = VER_PLATFORM_WIN32s) then
  begin
    Sys_Error('WinQuake requires at least Win95 or NT 4.0');
  end;

  if vinfo.dwPlatformId = VER_PLATFORM_WIN32_NT then
    WinNT := true
  else
    WinNT := false;
end;

var
  in_sys_error0: integer = 0;
  in_sys_error1: integer = 0;
  in_sys_error2: integer = 0;
  in_sys_error3: integer = 0;

procedure Sys_Error(error: PChar);
begin
  Sys_Error(error, []);
end;

procedure Sys_Error(error: PChar; const Args: array of const);
const
  _text3 = 'Press Enter to exit'#10;
  _text4 = '***********************************'#10;
  _text5 = #10;
var
  text, text2: array[0..1023] of char;
  text3: array[0..19] of char;
  text4: array[0..35] of char;
  text5: array[0..0] of char;
  dummy: DWORD;
  starttime: double;
begin
  if in_sys_error3 = 0 then
  begin
    in_sys_error3 := 1;
    VID_ForceUnlockedAndReturnState;
  end;

  sprintf(text, error, Args);
  sprintf(text3, '%s', [_text3]);
  sprintf(text4, '%s', [_text4]);
  sprintf(text5, '%s', [_text5]);

  if isDedicated then
  begin
    sprintf(text2, 'ERROR: %s'#10, [text]);
    WriteFile(houtput, text5, strlen(text5), dummy, nil);
    WriteFile(houtput, text4, strlen(text4), dummy, nil);
    WriteFile(houtput, text2, strlen(text2), dummy, nil);
    WriteFile(houtput, text3, strlen(text3), dummy, nil);
    WriteFile(houtput, text4, strlen(text4), dummy, nil);


    starttime := Sys_FloatTime;
    sc_return_on_enter := true; // so Enter will get us out of here

    while (Sys_ConsoleInput = nil) and ((Sys_FloatTime - starttime) < CONSOLE_ERROR_TIMEOUT) do
    begin
    end;
  end
  else
  begin
  // switch to windowed so the message box is visible, unless we already
  // tried that and failed
    if in_sys_error0 = 0 then
    begin
      in_sys_error0 := 1;
      VID_SetDefaultMode;
      MessageBox(0, text, 'Quake Error',
        MB_OK or MB_SETFOREGROUND or MB_ICONSTOP);
    end
    else
    begin
      MessageBox(0, text, 'Double Quake Error',
        MB_OK or MB_SETFOREGROUND or MB_ICONSTOP);
    end;
  end;

  if in_sys_error1 = 0 then
  begin
    in_sys_error1 := 1;
    Host_Shutdown;
  end;

// shut down QHOST hooks if necessary
  if in_sys_error2 = 0 then
  begin
    in_sys_error2 := 1;
    DeinitConProc;
  end;


  Memory_Shutdown;

  halt(1);
end;

procedure Sys_Error(error: string);
begin
  Sys_Error(PChar(error));
end;

procedure Sys_Error(error: string; const Args: array of const);
begin
  Sys_Error(PChar(error), Args);
end;

procedure Sys_Printf(fmt: PChar);
begin
  Sys_Printf(fmt, []);
end;

procedure Sys_Printf(fmt: PChar; const Args: array of const);
var
  text: array[0..$FFFF] of char;
  dummy: DWORD;
begin
  if isDedicated then
  begin
    sprintf(text, fmt, Args);

    WriteFile(houtput, text, strlen(text), dummy, nil);
  end;
end;

procedure Sys_Printf(fmt: string);
begin
  Sys_Printf(PChar(fmt));
end;

procedure Sys_Printf(fmt: string; const Args: array of const); overload;
begin
  Sys_Printf(PChar(fmt), Args);
end;

procedure Sys_Quit;
begin
  VID_ForceUnlockedAndReturnState;

  Host_Shutdown;

  if tevent <> 0 then
    CloseHandle(tevent);

  if isDedicated then
    FreeConsole;

// shut down QHOST hooks if necessary
  DeinitConProc;

  Memory_Shutdown;

  halt(0);
end;


(*
================
Sys_FloatTime
================
*)
var
  sametimecount_Sys_FloatTime: integer;
  oldtime_Sys_FloatTime: unsigned;
  first_Sys_FloatTime: integer = 1;

function Sys_FloatTime: double;
var
  PerformanceCount: TLargeInteger;
  temp, t2: unsigned;
  time: double;
begin
  QueryPerformanceCounter(PerformanceCount);

  temp := (unsigned(LARGE_INTEGER(PerformanceCount).LowPart) shr lowshift) or
    (unsigned(LARGE_INTEGER(PerformanceCount).HighPart) shl (32 - lowshift));

  if first_Sys_FloatTime <> 0 then
  begin
    oldtime_Sys_FloatTime := temp;
    first_Sys_FloatTime := 0;
  end
  else
  begin
  // check for turnover or backward time
    if (temp <= oldtime_Sys_FloatTime) and ((oldtime_Sys_FloatTime - temp) < $10000000) then
    begin
      oldtime_Sys_FloatTime := temp; // so we can't get stuck
    end
    else
    begin
      t2 := temp - oldtime_Sys_FloatTime;

      time := t2 * pfreq;
      oldtime_Sys_FloatTime := temp;

      curtime := curtime + time;

      if curtime = lastcurtime then
      begin
        inc(sametimecount_Sys_FloatTime);

        if sametimecount_Sys_FloatTime > 100000 then
        begin
          curtime := curtime + 1.0;
          sametimecount_Sys_FloatTime := 0;
        end;
      end
      else
      begin
        sametimecount_Sys_FloatTime := 0;
      end;

      lastcurtime := curtime;
    end;
  end;

  result := curtime;
end;


var
  text_Sys_ConsoleInput: array[0..255] of char;
  len_Sys_ConsoleInput: integer;

function Sys_ConsoleInput: PChar;
var
  recs: array[0..1023] of TInputRecord;
  dummy: DWORD;
  ch: char;
  numread, numevents: DWORD;
begin

  if not isDedicated then
  begin
    result := nil;
    exit;
  end;


  while true do
  begin
    if not GetNumberOfConsoleInputEvents(hinput, numevents) then
      Sys_Error('Error getting # of console events');

    if numevents = 0 then
      break;

    if not ReadConsoleInput(hinput, recs[0], 1, numread) then
      Sys_Error('Error reading console input');

    if numread <> 1 then
      Sys_Error('Couldn''t read console input');

    if recs[0].EventType = KEY_EVENT then
    begin
      if not recs[0].Event.KeyEvent.bKeyDown then
      begin
        ch := recs[0].Event.KeyEvent.AsciiChar;

        case ch of
          #13:
            begin
              WriteFile(houtput, #13#10, 2, dummy, nil);

              if len_Sys_ConsoleInput <> 0 then
              begin
                text_Sys_ConsoleInput[len_Sys_ConsoleInput] := #0;
                len_Sys_ConsoleInput := 0;
                result := @text_Sys_ConsoleInput[0];
                exit;
              end
              else if sc_return_on_enter then
              begin
              // special case to allow exiting from the error handler on Enter
                text_Sys_ConsoleInput[0] := #13;
                len_Sys_ConsoleInput := 0;
                result := @text_Sys_ConsoleInput[0];
                exit;
              end;

            end;

          #8: // backspace
            begin
              WriteFile(houtput, #8' '#8, 3, dummy, nil);
              if len_Sys_ConsoleInput <> 0 then
              begin
                dec(len_Sys_ConsoleInput);
              end;
            end;

        else
          begin
            if ch >= ' ' then
            begin
              WriteFile(houtput, ch, 1, dummy, nil);
              text_Sys_ConsoleInput[len_Sys_ConsoleInput] := ch;
              len_Sys_ConsoleInput := (len_Sys_ConsoleInput + 1) and $FF;
            end;
          end;
        end;
      end;
    end;
  end;

  result := nil;
end;

procedure Sys_SendKeyEvents;
var
  msg: TMsg;
begin
  while PeekMessage(msg, 0, 0, 0, PM_NOREMOVE) do
  begin
  // we always update if there are any event, even if we're paused
    scr_skipupdate := false;

    if not GetMessage(msg, 0, 0, 0) then
      Sys_Quit;

    TranslateMessage(msg);
    DispatchMessage(msg);
  end;
end;


(*
==============================================================================

 WINDOWS CRAP

==============================================================================
*)


(*
==================
WinMain
==================
*)

procedure SleepUntilInput(time: integer);
begin
  MsgWaitForMultipleObjects(1, tevent, false, time, QS_ALLINPUT);
end;

type
  dpiproc_t = function: BOOL; stdcall;
  dpiproc2_t = function(value: integer): HRESULT; stdcall;

function I_SetDPIAwareness: boolean;
var
  dpifunc: dpiproc_t;
  dpifunc2: dpiproc2_t;
  dllinst: THandle;
begin
  result := false;

  dllinst := LoadLibrary('Shcore.dll');
  if dllinst <> 0 then
  begin
    dpifunc2 := GetProcAddress(dllinst, 'SetProcessDpiAwareness');
    if assigned(dpifunc2) then
    begin
      result := dpifunc2(2) = S_OK;
      if not result then
        result := dpifunc2(1) = S_OK;
    end;
    FreeLibrary(dllinst);
    exit;
  end;

  dllinst := LoadLibrary('user32');
  dpifunc := GetProcAddress(dllinst, 'SetProcessDPIAware');
  if assigned(dpifunc) then
    result := dpifunc;
  FreeLibrary(dllinst);
end;

(*
==================
WinMain
==================
*)
var
  global_nCmdShow: integer;
  argv: TArgvArray;
  s_argv: array[0..MAX_NUM_ARGVS - 1] of string;
  empty_string: PChar = ' ';

var
  cwd: array[0..1023] of char;

const
  IDD_DIALOG1 = 108;

function WinMain: integer;
var
  parms: quakeparms_t;
  time, oldtime, newtime: double;
  lpBuffer: TMemoryStatus;
  i, t: integer;
  rect: TRect;
  pos: integer;
begin
  (* previous instances do not exist in Win32 *)
  if HPrevInst <> 0 then
  begin
    result := 0;
    exit;
  end;

  I_SetDPIAwareness;
    
  global_hInstance := hInstance;
  global_nCmdShow := CmdShow;

  lpBuffer.dwLength := SizeOf(TMemoryStatus);
  GlobalMemoryStatus(lpBuffer);

  if GetCurrentDirectory(SizeOf(cwd), cwd) = 0 then
    Sys_Error('Couldn''t determine current directory');

  pos := Q_strlen(cwd) - 1;
  if cwd[pos] in ['\', '/'] then
    cwd[pos] := #0;

  parms.basedir := cwd;
  parms.cachedir := nil;

  parms.argc := ParamCount + 1;
  argv[0] := empty_string;

  for i := 1 to ParamCount do
  begin
    s_argv[i] := ParamStr(i);
    argv[i] := PChar(s_argv[i]);
  end;

  parms.argv := @argv;

  COM_InitArgv(parms.argc, parms.argv);

  parms.argc := com_argc;
  parms.argv := com_argv;

  isDedicated := COM_CheckParm('-dedicated') <> 0;

  if not isDedicated then
  begin
    hwnd_dialog := CreateDialog(hInstance, MAKEINTRESOURCE(IDD_DIALOG1), 0, nil);

    if hwnd_dialog <> 0 then
    begin
      if GetWindowRect(hwnd_dialog, rect) then
      begin
        if rect.left > (rect.top * 2) then
        begin
          SetWindowPos(hwnd_dialog, 0,
            (rect.left div 2) - ((rect.right - rect.left) div 2),
            rect.top, 0, 0,
            SWP_NOZORDER or SWP_NOSIZE);
        end;
      end;

      ShowWindow(hwnd_dialog, SW_SHOWDEFAULT);
      UpdateWindow(hwnd_dialog);
      SetForegroundWindow(hwnd_dialog);
    end;
  end;

// take the greater of all the available memory or half the total memory,
// but at least 8 Mb and no more than 16 Mb, unless they explicitly
// request otherwise
  parms.memsize := lpBuffer.dwAvailPhys;

  if parms.memsize < MINIMUM_WIN_MEMORY then
    parms.memsize := MINIMUM_WIN_MEMORY;

  if parms.memsize < (lpBuffer.dwTotalPhys div 2) then
    parms.memsize := lpBuffer.dwTotalPhys div 2;

  if parms.memsize > MAXIMUM_WIN_MEMORY then
    parms.memsize := MAXIMUM_WIN_MEMORY;

  t := COM_CheckParm('-heapsize');
  if t <> 0 then
  begin
    inc(t);

    if t < com_argc then
      parms.memsize := Q_atoi(com_argv[t]) * 1024;
  end;

  parms.membase := malloc(parms.memsize);

  if parms.membase = nil then
    Sys_Error('Not enough memory free; check disk space');

  Sys_PageIn(parms.membase, parms.memsize);

  tevent := CreateEvent(nil, false, false, nil);

  if tevent = 0 then
    Sys_Error('Couldn''t create event');

  if isDedicated then
  begin
    if not AllocConsole then
    begin
      Sys_Error('Couldn''t create dedicated server console');
    end;

    hinput := GetStdHandle(STD_INPUT_HANDLE);
    houtput := GetStdHandle(STD_OUTPUT_HANDLE);

  // give QHOST a chance to hook into the console
    t := COM_CheckParm('-HFILE');
    if t > 0 then
    begin
      if t < com_argc then
        hFile := Q_atoi(com_argv[t + 1]);
    end;

    t := COM_CheckParm('-HPARENT');
    if t > 0 then
    begin
      if t < com_argc then
        heventParent := Q_atoi(com_argv[t + 1]);
    end;

    t := COM_CheckParm('-HCHILD');
    if t > 0 then
    begin
      if t < com_argc then
        heventChild := Q_atoi(com_argv[t + 1]);
    end;

    InitConProc(hFile, heventParent, heventChild);
  end;

  Sys_Init;

// because sound is off until we become active
  S_BlockSound;

  Sys_Printf('Host_Init'#10);
  Host_Init(@parms);

  oldtime := Sys_FloatTime;

  if isDedicated then
  begin
    while true do
    begin
      newtime := Sys_FloatTime;
      time := newtime - oldtime;

      while time < sys_ticrate.value do
      begin
        Sys_Sleep;
        newtime := Sys_FloatTime;
        time := newtime - oldtime;
      end;
      Host_Frame(time);
      oldtime := newtime;
    end
  end
  else
  begin
    while true do
    begin
    // yield the CPU for a little while when paused, minimized, or not the focus
      if (cl.paused and (not ActiveApp and not DDActive)) or Minimized or block_drawing then
      begin
        SleepUntilInput(PAUSE_SLEEP);
        scr_skipupdate := true; // no point in bothering to draw
      end
      else if not ActiveApp and not DDActive then
      begin
        SleepUntilInput(NOT_FOCUS_SLEEP);
      end;

      newtime := Sys_FloatTime;
      time := newtime - oldtime;
      Host_Frame(time);
      oldtime := newtime;
    end;
  end;

  (* return success of application *)
  result := 1;
end;

procedure Sys_HighFPPrecision;
begin
end;

procedure Sys_LowFPPrecision;
begin
end;

procedure Sys_Sleep(const msecs: integer = 1);
begin
  sleep(msecs);
end;

end.

