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

unit conproc;

interface

uses
  Windows;

const
  CCOM_WRITE_TEXT = $2;
// Param1 : Text

  CCOM_GET_TEXT = $3;
// Param1 : Begin line
// Param2 : End line

  CCOM_GET_SCR_LINES = $4;
// No params

  CCOM_SET_SCR_LINES = $5;
// Param1 : Number of lines

procedure InitConProc(hFile: THandle; heventParent: THandle; heventChild: THandle);
procedure DeinitConProc;

implementation

uses
  q_delphi,
  console;

var
  heventDone: THandle;
  hfileBuffer: THandle;
  heventChildSend: THandle;
  heventParentSend: THandle;
  hStdout: THandle;
  hStdin: THandle;

function RequestProc(dwNichts: DWORD): DWORD; stdcall; forward;
function GetMappedBuffer(hfileBuffer: THandle): pointer; forward;
procedure ReleaseMappedBuffer(pBuffer: pointer); forward;
function GetScreenBufferLines(piLines: Pinteger): integer; forward;
function SetScreenBufferLines(iLines: integer): integer; forward;
function ReadText(pszText: LPTSTR; iBeginLine: integer; iEndLine: integer): integer; forward;
function WriteText(szText: LPCTSTR): integer; forward;
function CharToCode(c: char): integer; forward;
function SetConsoleCXCY(hStdout: THandle; cx, cy: integer): BOOL; forward;


procedure InitConProc(hFile: THandle; heventParent: THandle; heventChild: THandle);
var
  dwID: DWORD;
begin
// ignore if we don't have all the events.
  if (hFile = 0) or (heventParent = 0) or (heventChild = 0) then
    exit;

  hfileBuffer := hFile;
  heventParentSend := heventParent;
  heventChildSend := heventChild;

// so we'll know when to go away.
  heventDone := CreateEvent(nil, false, false, nil);

  if heventDone = 0 then
  begin
    Con_SafePrintf('Couldn''t create heventDone'#10);
    exit;
  end;

  if CreateThread(nil, 0, @RequestProc, nil, 0, dwID) = 0 then
  begin
    CloseHandle(heventDone);
    Con_SafePrintf('Couldn''t create QHOST thread'#10);
    exit;
  end;

// save off the input/output handles.
  hStdout := GetStdHandle(STD_OUTPUT_HANDLE);
  hStdin := GetStdHandle(STD_INPUT_HANDLE);

// force 80 character width, at least 25 character height
  SetConsoleCXCY(hStdout, 80, 25);
end;


procedure DeinitConProc;
begin
  if heventDone <> 0 then
    SetEvent(heventDone);
end;


function RequestProc(dwNichts: DWORD): DWORD; stdcall;
var
  pBuffer: PintegerArray;
  dwRet: DWORD;
  heventWait: array[0..1] of THandle;
  iBeginLine, iEndLine: integer;
begin
  heventWait[0] := heventParentSend;
  heventWait[1] := heventDone;

  while true do
  begin
    dwRet := WaitForMultipleObjects(2, @heventWait, FALSE, INFINITE);

  // heventDone fired, so we're exiting.
    if dwRet = WAIT_OBJECT_0 + 1 then
      break;

    pBuffer := GetMappedBuffer(hfileBuffer);

  // hfileBuffer is invalid.  Just leave.
    if pBuffer = nil then
    begin
      Con_SafePrintf('Invalid hfileBuffer'#10);
      break;
    end;

    case pBuffer[0] of
      CCOM_WRITE_TEXT:
        begin
        // Param1 : Text
          pBuffer[0] := WriteText(LPCTSTR(@pBuffer[1]));
        end;

      CCOM_GET_TEXT:
        begin
        // Param1 : Begin line
        // Param2 : End line
          iBeginLine := pBuffer[1];
          iEndLine := pBuffer[2];
          pBuffer[0] := ReadText(LPTSTR(@pBuffer[1]), iBeginLine, iEndLine);
        end;

      CCOM_GET_SCR_LINES:
        begin
        // No params
          pBuffer[0] := GetScreenBufferLines(@pBuffer[1]);
        end;

      CCOM_SET_SCR_LINES:
        begin
        // Param1 : Number of lines
          pBuffer[0] := SetScreenBufferLines(pBuffer[1]);
        end;
    end;

    ReleaseMappedBuffer(pBuffer);
    SetEvent(heventChildSend);
  end;

  result := 0;
end;


function GetMappedBuffer(hfileBuffer: THandle): pointer;
begin
  result := MapViewOfFile(hfileBuffer, FILE_MAP_READ or FILE_MAP_WRITE, 0, 0, 0);
end;


procedure ReleaseMappedBuffer(pBuffer: pointer);
begin
  UnmapViewOfFile(pBuffer);
end;


function GetScreenBufferLines(piLines: Pinteger): integer;
var
  info: CONSOLE_SCREEN_BUFFER_INFO;
  ret: BOOL;
begin
  ret := GetConsoleScreenBufferInfo(hStdout, info);

  if ret then
  begin
    piLines^ := info.dwSize.Y;
    result := 1;
  end
  else
    result := 0;
end;

function SetScreenBufferLines(iLines: integer): integer;
begin
  result := intval(SetConsoleCXCY(hStdout, 80, iLines));
end;


function ReadText(pszText: LPTSTR; iBeginLine: integer; iEndLine: integer): integer;
var
  _coord: COORD;
  dwRead: DWORD;
  ret: BOOL;
begin
  _coord.X := 0;
  _coord.Y := iBeginLine;

  ret := ReadConsoleOutputCharacter(
    hStdout,
    pszText,
    80 * (iEndLine - iBeginLine + 1),
    _coord,
    dwRead);

  // Make sure it's null terminated.
  if ret then
  begin
    pszText[dwRead] := #0;
    result := 1;
  end
  else
    result := 0;
end;

function WriteText(szText: LPCTSTR): integer;
var
  dwWritten: DWORD;
  rec: TInputRecord;
  upper: char;
  sz: PChar;
  wc: array[0..1] of WideChar;
begin
  sz := LPTSTR(szText);

  while sz^ <> #0 do
  begin
  // 13 is the code for a carriage return (\n) instead of 10.
    if sz^ = #10 then
      sz^ := #13;

    upper := toupper(sz^);

    rec.EventType := KEY_EVENT;
    rec.Event.KeyEvent.bKeyDown := true;
    rec.Event.KeyEvent.wRepeatCount := 1;
    rec.Event.KeyEvent.wVirtualKeyCode := Ord(upper);
    rec.Event.KeyEvent.wVirtualScanCode := CharToCode(sz^);
    rec.Event.KeyEvent.AsciiChar := sz^;
    Utf8ToUnicode(@wc, sz, 1);
    rec.Event.KeyEvent.UnicodeChar := wc[0];
    rec.Event.KeyEvent.dwControlKeyState := decide(isupper(sz^), $80, $0);

    WriteConsoleInput(hStdin, rec, 1, dwWritten);

    rec.Event.KeyEvent.bKeyDown := FALSE;

    WriteConsoleInput(hStdin, rec, 1, dwWritten);

    inc(sz);
  end;

  result := 1;
end;


function CharToCode(c: char): integer;
var
  upper: char;
begin
  if c = #13 then
  begin
    result := 28;
    exit;
  end;

  upper := toupper(c);

  if isalpha(c) then
  begin
    result := 30 + Ord(upper) - 65;
    exit;
  end;

  if isdigit(c) then
  begin
    result := 1 + Ord(upper) - 47;
    exit;
  end;

  result := Ord(c);
end;


function SetConsoleCXCY(hStdout: THandle; cx, cy: integer): BOOL;
var
  info: CONSOLE_SCREEN_BUFFER_INFO;
  coordMax: COORD;
begin
  coordMax := GetLargestConsoleWindowSize(hStdout);

  if cy > coordMax.Y then
    cy := coordMax.Y;

  if cx > coordMax.X then
    cx := coordMax.X;

  if not GetConsoleScreenBufferInfo(hStdout, info) then
  begin
    result := false;
    exit;
  end;

// height
  info.srWindow.Left := 0;
  info.srWindow.Right := info.dwSize.X - 1;
  info.srWindow.Top := 0;
  info.srWindow.Bottom := cy - 1;

  if cy < info.dwSize.Y then
  begin
    if not SetConsoleWindowInfo(hStdout, TRUE, info.srWindow) then
    begin
      result := false;
      exit;
    end;

    info.dwSize.Y := cy;

    if not SetConsoleScreenBufferSize(hStdout, info.dwSize) then
    begin
      result := false;
      exit;
    end
  end
  else if cy > info.dwSize.Y then
  begin
    info.dwSize.Y := cy;

    if not SetConsoleScreenBufferSize(hStdout, info.dwSize) then
    begin
      result := false;
      exit;
    end;

    if not SetConsoleWindowInfo(hStdout, true, info.srWindow) then
    begin
      result := false;
      exit;
    end;
  end;

  if not GetConsoleScreenBufferInfo(hStdout, info) then
  begin
    result := false;
    exit;
  end;

// width
  info.srWindow.Left := 0;
  info.srWindow.Right := cx - 1;
  info.srWindow.Top := 0;
  info.srWindow.Bottom := info.dwSize.Y - 1;

  if cx < info.dwSize.X then
  begin
    if not SetConsoleWindowInfo(hStdout, true, info.srWindow) then
    begin
      result := false;
      exit;
    end;

    info.dwSize.X := cx;

    if not SetConsoleScreenBufferSize(hStdout, info.dwSize) then
    begin
      result := false;
      exit;
    end;
  end
  else if cx > info.dwSize.X then
  begin
    info.dwSize.X := cx;

    if not SetConsoleScreenBufferSize(hStdout, info.dwSize) then
    begin
      result := false;
      exit;
    end;

    if not SetConsoleWindowInfo(hStdout, true, info.srWindow) then
    begin
      result := false;
      exit;
    end;
  end;

  result := true;
end;


end.

