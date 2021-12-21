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

unit common;

// common.c -- misc functions used in client and server

interface

uses
  q_delphi,
  quakedef,
  cvar,
  zone;

type
  sizebuf_t = record
    allowoverflow: qboolean; // if false, do a Sys_Error
    overflowed: qboolean; // set to true if the buffer size failed
    data: PByteArray;
    maxsize: integer;
    cursize: integer;
  end;
  Psizebuf_t = ^sizebuf_t;

  Plink_t = ^link_t;
  link_t = record
    prev, next: Plink_t;
  end;

//
// in memory
//

type
  packfile_t = record
    name: array[0..MAX_QPATH - 1] of char;
    filepos, filelen: integer;
  end;
  Ppackfile_t = ^packfile_t;
  packfile_tArray = array[0..$FFFF] of packfile_t;
  Ppackfile_tArray = ^packfile_tArray;

  Ppack_t = ^pack_t;
  pack_t = record
    filename: array[0..MAX_OSPATH - 1] of char;
    handle: integer;
    numfiles: integer;
    files: Ppackfile_tArray;
  end;

//
// on disk
//
  dpackfile_t = record
    name: array[0..55] of char;
    filepos, filelen: integer;
  end;

  dpackheader_t = record
    id: array[0..3] of char;
    dirofs: integer;
    dirlen: integer;
  end;


procedure ClearLink(l: Plink_t);
procedure RemoveLink(l: Plink_t);
procedure InsertLinkBefore(l: Plink_t; before: Plink_t);
procedure InsertLinkAfter(l: Plink_t; after: Plink_t);
function Q_memcmp(m1: pointer; m2: pointer; count: integer): integer;
procedure Q_strcpy(dest: PChar; src: PChar);
procedure Q_strncpy(dest: PChar; src: PChar; count: integer);
function Q_strlen(str: PChar): integer;
function Q_strrchr(s: PChar; c: char): PChar;
procedure Q_strcat(dest: PChar; src: PChar);
function Q_strcmp(s1, s2: PChar): integer;
function Q_strncmp(s1, s2: PChar; count: integer): integer;
function Q_strncasecmp(s1, s2: PChar; n: integer): integer;
function Q_strcasecmp(s1, s2: PChar): integer;
function Q_atoi(str: PChar): integer;
function Q_atof(str: PChar): single;

function ShortSwap(l: short): short;
function ShortNoSwap(l: short): short;
function LongSwap(l: integer): integer;
function LongNoSwap(l: integer): integer;
function FloatSwap(f: single): single;
function FloatNoSwap(f: single): single;

procedure MSG_WriteChar(sb: Psizebuf_t; c: ShortInt);
procedure MSG_WriteByte(sb: Psizebuf_t; c: Integer);
procedure MSG_WriteShort(sb: Psizebuf_t; c: Integer);
procedure MSG_WriteLong(sb: Psizebuf_t; c: Integer);
procedure MSG_WriteFloat(sb: Psizebuf_t; f: Single);
procedure MSG_WriteString(sb: Psizebuf_t; s: PChar);
procedure MSG_WriteCoord(sb: Psizebuf_t; f: Single);
procedure MSG_WriteAngle(sb: Psizebuf_t; f: Single);
procedure MSG_BeginReading;
function MSG_ReadChar: integer;
function MSG_ReadByte: integer;
function MSG_ReadShort: integer;
function MSG_ReadLong: integer;
function MSG_ReadFloat: single;
function MSG_ReadString: PChar;
function MSG_ReadCoord: single;
function MSG_ReadAngle: single;
procedure SZ_Alloc(buf: Psizebuf_t; startsize: integer);
procedure SZ_Free(buf: Psizebuf_t);
procedure SZ_Clear(buf: Psizebuf_t);
function SZ_GetSpace(buf: Psizebuf_t; length: integer): pointer;
procedure SZ_Write(buf: Psizebuf_t; data: pointer; length: integer);
procedure SZ_Print(buf: Psizebuf_t; data: PChar);
function COM_SkipPath(pathname: PChar): PChar;
procedure COM_StripExtension(_in, _out: PChar);
function COM_FileExtension(_in: PChar): PChar;
procedure COM_FileBase(_in, _out: PChar);
procedure COM_DefaultExtension(path, extension: PChar);
function COM_Parse(data: PChar): PChar;
function COM_CheckParm(parm: PChar): integer;
procedure COM_CheckRegistered;
procedure COM_Path_f;
procedure COM_InitArgv(argc: integer; argv: PArgvArray);
procedure COM_Init(basedir: PChar);
function va(format: PChar; const Args: array of const): PChar;
procedure COM_WriteFile(filename: PChar; data: pointer; len: integer);
procedure COM_CreatePath(path: PChar);
procedure COM_CopyFile(netpath: PChar; cachepath: PChar);
function COM_FindFile(filename: PChar; handle: Pinteger; var f: integer): integer;
function COM_OpenFile(filename: PChar; handle: Pinteger): integer;
function COM_FOpenFile(filename: PChar; var f: integer): integer;
procedure COM_CloseFile(h: integer);
function COM_LoadFile(path: PChar; usehunk: integer): PByteArray;
function COM_LoadHunkFile(path: PChar): PByteArray;
function COM_LoadTempFile(path: PChar): PByteArray;
procedure COM_LoadCacheFile(path: PChar; cu: Pcache_user_t);
function COM_LoadStackFile(path: PChar; buffer: pointer; bufsize: integer): PByteArray;
function COM_LoadPackFile(packfile: PChar): Ppack_t;
procedure COM_AddGameDirectory(dir: PChar);
procedure COM_InitFilesystem;

const
  Q_MAXCHAR = Chr($7F);
  Q_MAXSHORT = short($7FFF);
  Q_MAXINT = integer($7FFFFFFF);
  Q_MAXLONG = integer($7FFFFFFF);
  Q_MAXFLOAT = integer($7FFFFFFF);

  Q_MINCHAR = Chr($80);
  Q_MINSHORT = short($8000);
  Q_MININT = integer($80000000);
  Q_MINLONG = integer($80000000);
  Q_MINFLOAT = integer($7FFFFFFF);


const
  NUM_SAFE_ARGVS = 7;

var
  largv: array[0..MAX_NUM_ARGVS + NUM_SAFE_ARGVS] of PChar;
  argvdummy: PChar = ' ';

var
  com_gamedir: array[0..MAX_OSPATH - 1] of char;

const
  safeargvs: array[0..NUM_SAFE_ARGVS - 1] of PChar = (
    '-stdvid',
    '-nolan',
    '-nosound',
    '-nocdaudio',
    '-nojoy',
    '-nomouse',
    '-dibonly'
    );

var
  registered: cvar_t =
  (name: 'registered'; text: '0');
  cmdline: cvar_t =
  (name: 'cmdline'; text: '0'; archive: false; server: true);

  com_modified: qboolean; // set true if using non-id files

  proghack: qboolean;

  static_registered: integer = 1; // only for startup check, then set

const
// if a packfile directory differs from this, it is assumed to be hacked
  PAK0_COUNT = 339;
  PAK0_CRC = 32981;
  MAX_TOKEN_CHARS = 1024;

var
  com_token: array[0..MAX_TOKEN_CHARS - 1] of char;

var
  com_argc: integer;
  com_argv: PArgvArray; //array[0..MAX_NUM_ARGVS + NUM_SAFE_ARGVS] of PChar; // JVAL ?? was char **

const
  CMDLINE_LENGTH = 256;

var
  com_cmdline: array[0..CMDLINE_LENGTH - 1] of char;

  standard_quake: qboolean = true;
  rogue: qboolean;
  hipnotic: qboolean;

var
  bigendien: qboolean;

  BigShort: function(L: SmallInt): SmallInt;
  LittleShort: function(L: SmallInt): SmallInt;
  BigLong: function(L: LongInt): LongInt;
  LittleLong: function(L: LongInt): LongInt;
  BigFloat: function(L: Single): Single;
  LittleFloat: function(L: Single): Single;

var
  com_filesize: integer;

var
  msg_badread: qboolean = false;
  msg_readcount: integer;

  msg_suppress_1: qboolean = false;


implementation

uses
  net_main,
  sys_win,
  console,
  cmd,
  gl_draw,
  crc,
  host_h;

var
// this graphic needs to be in the pak file to use registered features
  pop: packed array[0..8 * 16 - 1] of word = (
    $0000, $0000, $0000, $0000, $0000, $0000, $0000, $0000,
    $0000, $0000, $6600, $0000, $0000, $0000, $6600, $0000,
    $0000, $0066, $0000, $0000, $0000, $0000, $0067, $0000,
    $0000, $6665, $0000, $0000, $0000, $0000, $0065, $6600,
    $0063, $6561, $0000, $0000, $0000, $0000, $0061, $6563,
    $0064, $6561, $0000, $0000, $0000, $0000, $0061, $6564,
    $0064, $6564, $0000, $6469, $6969, $6400, $0064, $6564,
    $0063, $6568, $6200, $0064, $6864, $0000, $6268, $6563,
    $0000, $6567, $6963, $0064, $6764, $0063, $6967, $6500,
    $0000, $6266, $6769, $6A68, $6768, $6A69, $6766, $6200,
    $0000, $0062, $6566, $6666, $6666, $6666, $6562, $0000,
    $0000, $0000, $0062, $6364, $6664, $6362, $0000, $0000,
    $0000, $0000, $0000, $0062, $6662, $0000, $0000, $0000,
    $0000, $0000, $0000, $0061, $6661, $0000, $0000, $0000,
    $0000, $0000, $0000, $0000, $6500, $0000, $0000, $0000,
    $0000, $0000, $0000, $0000, $6400, $0000, $0000, $0000
    );

(*


All of Quake's data access is through a hierchal file system, but the contents of the file system can be
transparently merged from several sources.

The "base directory" is the path to the directory holding the quake.exe and all game directories.
The sys_* files pass this to host_init in quakeparms_t->basedir.  This can be overridden
with the "-basedir" command line parm to allow code debugging in a different directory.
The base directory is
only used during filesystem initialization.

The "game directory" is the first tree on the search path and directory that all generated files
(savegames, screenshots, demos, config files) will be saved to.  This can be overridden
with the "-game" command line parameter.  The game directory can never be changed while quake is executing.
This is a precacution against having a malicious server instruct clients to write files over areas they shouldn't.

The "cache directory" is only used during development to save network bandwidth, especially over ISDN / T1 lines.
If there is a cache directory
specified, when a file is found by the normal search path, it will be mirrored
into the cache directory, then opened there.



FIXME:
The file "parms.txt" will be read out of the game directory and appended to the current command line arguments
to allow different games to initialize startup parms differently.  This could be used to add a "-sspeed 22050"
for the high quality sound edition.  Because they are added at the end, they will not override an explicit setting
on the original command line.

*)

//============================================================================


// ClearLink is used for new headnodes

procedure ClearLink(l: Plink_t);
begin
  l.prev := l;
  l.next := l;
end;

procedure RemoveLink(l: Plink_t);
begin
  l.next.prev := l.prev;
  l.prev.next := l.next;
end;

procedure InsertLinkBefore(l: Plink_t; before: Plink_t);
begin
  l.next := before;
  l.prev := before.prev;
  l.prev.next := l;
  l.next.prev := l;
end;

procedure InsertLinkAfter(l: Plink_t; after: Plink_t);
begin
  l.next := after.next;
  l.prev := after;
  l.prev.next := l;
  l.next.prev := l;
end;

(*
============================================================================

          LIBRARY REPLACEMENT FUNCTIONS

============================================================================
*)

// JVAL: needs optimization ??? (pointers in loop, 4 byte alignment check)

function Q_memcmp(m1: pointer; m2: pointer; count: integer): integer;
begin
  while count > 0 do
  begin
    dec(count);
    if PByteArray(m1)[count] <> PByteArray(m2)[count] then
    begin
      result := -1;
      exit;
    end;
  end;
  result := 0;
end;

procedure Q_strcpy(dest: PChar; src: PChar);
begin
  while src^ <> #0 do
  begin
    dest^ := src^;
    inc(dest);
    inc(src);
  end;
  dest^ := #0;
end;

procedure Q_strncpy(dest: PChar; src: PChar; count: integer);
begin
  while (src^ <> #0) and (count > 0) do
  begin
    dest^ := src^;
    dec(count);
    inc(dest);
    inc(src);
  end;
  if count <> 0 then
    dest^ := #0;
end;

function Q_strlen(str: PChar): integer;
begin
  result := 0;
  while str[result] <> #0 do
    inc(result);
end;

function Q_strrchr(s: PChar; c: char): PChar;
var
  len: integer;
begin
  len := Q_strlen(s);
  inc(s, len);
  while len <> 0 do
  begin
    dec(s); // JVAL should check this
    dec(len);
    if s^ = c then
    begin
      result := s;
      exit;
    end;
  end;
  result := nil;
end;

procedure Q_strcat(dest: PChar; src: PChar);
begin
  inc(dest, Q_strlen(dest));
  Q_strcpy(dest, src);
end;

function Q_strcmp(s1, s2: PChar): integer;
begin
  while true do
  begin
    if s1^ <> s2^ then
    begin
      result := -1; // strings not equal
      exit;
    end;
    if s1^ = #0 then
    begin
      result := 0; // strings are equal
      exit;
    end;
    inc(s1);
    inc(s2);
  end;

  result := -1;
end;

function Q_strncmp(s1, s2: PChar; count: integer): integer;
begin
  while true do
  begin
    if count = 0 then
    begin
      result := 0;
      exit;
    end;
    dec(count);
    if s1^ <> s2^ then
    begin
      result := -1; // strings not equal
      exit;
    end;
    if s1^ = #0 then
    begin
      result := 0; // strings are equal
      exit;
    end;
    inc(s1);
    inc(s2);
  end;

  result := -1;
end;


function Q_strncasecmp(s1, s2: PChar; n: integer): integer;
var
  c1, c2: char;
begin
  while true do
  begin
    c1 := s1^;
    inc(s1);
    c2 := s2^;
    inc(s2);

    if n = 0 then
    begin
      result := 0; // strings are equal until end point
      exit;
    end;
    dec(n);

    if (c1 <> c2) then
    begin
      if (c1 >= 'a') and (c1 <= 'z') then
        c1 := Chr(Ord(c1) - (Ord('a') - Ord('A')));
      if (c2 >= 'a') and (c2 <= 'z') then
        c2 := Chr(Ord(c2) - (Ord('a') - Ord('A')));
      if (c1 <> c2) then
      begin
        result := -1; // strings not equal
        exit;
      end;
    end;
    if c1 = #0 then
    begin
      result := 0; // strings are equal
      exit;
    end;
//              s1++;
//              s2++;
  end;

  result := -1;
end;

// JVAL: should change this... 99999

function Q_strcasecmp(s1, s2: PChar): integer;
begin
  result := Q_strncasecmp(s1, s2, 99999);
end;

function Q_atoi(str: PChar): integer;
var
  val: integer;
  sign: integer;
  c: char;
begin
  if str^ = '-' then
  begin
    sign := -1;
    inc(str);
  end
  else
    sign := 1;

  val := 0;

//
// check for hex
//
  if (str[0] = '0') and (str[1] in ['x', 'X']) then
  begin
    inc(str, 2);
    while true do
    begin
      c := str^;
      inc(str);
      if (c >= '0') and (c <= '9') then
        val := (val shl 4) + Ord(c) - Ord('0')
      else if (c >= 'a') and (c <= 'f') then
        val := (val shl 4) + Ord(c) - Ord('a') + 10
      else if (c >= 'A') and (c <= 'F') then
        val := (val shl 4) + Ord(c) - Ord('A') + 10
      else
      begin
        result := val * sign;
        exit;
      end;
    end;
  end;

//
// check for character
//
  if str[0] = '''' then
  begin
    result := sign * PByteArray(str)[1];
    exit;
  end;

//
// assume decimal
//
  while true do
  begin
    c := str^;
    inc(str);
    if (c < '0') or (c > '9') then
    begin
      result := val * sign;
      exit;
    end;
    val := val * 10 + Ord(c) - Ord('0');
  end;

  result := 0;
end;


function Q_atof(str: PChar): single;
var
  val: double;
  sign: integer;
  c: char;
  decimal, total: integer;
begin
  if str^ = '-' then
  begin
    sign := -1;
    inc(str);
  end
  else
    sign := 1;

  val := 0;

//
// check for hex
//
  if (str[0] = '0') and ((str[1] = 'x') or (str[1] = 'X')) then
  begin
    inc(str, 2);
    while true do
    begin
      c := str^;
      inc(str);
      if (c >= '0') and (c <= '9') then
        val := val * 16 + Ord(c) - Ord('0')
      else if (c >= 'a') and (c <= 'f') then
        val := val * 16 + Ord(c) - Ord('a') + 10
      else if (c >= 'A') and (c <= 'F') then
        val := val * 16 + Ord(c) - Ord('A') + 10
      else
      begin
        result := val * sign;
        exit;
      end;
    end;
  end;

//
// check for character
//
  if str^ = '''' then
  begin
    result := sign * PByteArray(str)[1];
    exit;
  end;

//
// assume decimal
//
  decimal := -1;
  total := 0;
  while true do
  begin
    c := str^;
    inc(str);
    if (c = '.') then
    begin
      decimal := total;
      continue;
    end;
    if (c < '0') or (c > '9') then
      break;
    val := val * 10 + Ord(c) - Ord('0');
    inc(total);
  end;

  if decimal = -1 then
  begin
    result := val * sign;
    exit;
  end;

  while total > decimal do
  begin
    val := val / 10;
    dec(total);
  end;

  result := val * sign;
end;

(*
============================================================================

          BYTE ORDER FUNCTIONS

============================================================================
*)

function ShortSwap(l: short): short;
var
  b1, b2: byte;
begin
  b1 := l and 255;
  b2 := (l shr 8) and 255;

  result := (b1 shl 8) + b2;
end;

function ShortNoSwap(l: short): short;
begin
  result := l;
end;

function LongSwap(l: integer): integer;
var
  b1, b2, b3, b4: byte;
begin
  b1 := l and 255;
  b2 := (l shr 8) and 255;
  b3 := (l shr 16) and 255;
  b4 := (l shr 24) and 255;

  result := (b1 shl 24) + (b2 shl 16) + (b3 shl 8) + b4;
end;

function LongNoSwap(l: integer): integer;
begin
  result := l;
end;

function FloatSwap(f: single): single;
type
  union_f = record
    case integer of
      1: (f: single);
      2: (b: array[0..3] of byte);
  end;
var
  dat1, dat2: union_f;
begin
  dat1.f := f;
  dat2.b[0] := dat1.b[3];
  dat2.b[1] := dat1.b[2];
  dat2.b[2] := dat1.b[1];
  dat2.b[3] := dat1.b[0];
  result := dat2.f;
end;

function FloatNoSwap(f: single): single;
begin
  result := f;
end;

(*
==============================================================================

      MESSAGE IO FUNCTIONS

Handles byte ordering and avoids alignment errors
==============================================================================
*)

//
// writing functions
//

procedure MSG_WriteChar(sb: Psizebuf_t; c: ShortInt);
var
  buf: PByteArray;
begin
{$IFDEF PARANOID}
  if (c < -128) or (c > 127) then
    Com_Error(ERR_FATAL, 'MSG_WriteChar: range error', []);
{$ENDIF}

  buf := SZ_GetSpace(sb, 1);
  buf[0] := c;
end;

procedure MSG_WriteByte(sb: Psizebuf_t; c: Integer);
var
  buf: PByteArray;
begin
{$IFDEF PARANOID}
  if (c < 0) or (c > 255) then
    Com_Error(ERR_FATAL, 'MSG_WriteByte: range error', []);
{$ENDIF}

  buf := SZ_GetSpace(sb, 1);
  buf[0] := Byte(c);
end;

procedure MSG_WriteShort(sb: Psizebuf_t; c: Integer);
var
  buf: PByteArray;
begin
{$IFDEF PARANOID}
  if (c < SmallInt($8000)) or (c > SmallInt($7FFF)) then
    Com_Error(ERR_FATAL, 'MSG_WriteShort: range error', []);
{$ENDIF}

  buf := SZ_GetSpace(sb, 2);
  buf[0] := c and $FF;
  buf[1] := c shr 8;
end;

procedure MSG_WriteLong(sb: Psizebuf_t; c: Integer);
var
  buf: PByteArray;
begin
  buf := SZ_GetSpace(sb, 4);
  buf[0] := c and $FF;
  buf[1] := (c shr 8) and $FF;
  buf[2] := (c shr 16) and $FF;
  buf[3] := (c shr 24);
end;

procedure MSG_WriteFloat(sb: Psizebuf_t; f: Single);
type
  union_fl = packed record
    case boolean of
      True: (f: Single; );
      False: (l: Integer; )
  end;
var
  dat: union_fl;
begin
  dat.f := f;
  dat.l := LittleLong(dat.l);

  SZ_Write(sb, @dat.l, 4);
end;

procedure MSG_WriteString(sb: Psizebuf_t; s: PChar);
begin
  if (s = nil) then
    SZ_Write(sb, PChar(''), 1)
  else
    SZ_Write(sb, s, strlen(s) + 1);
end;

procedure MSG_WriteCoord(sb: Psizebuf_t; f: Single);
begin
  MSG_WriteShort(sb, Trunc(f * 8));
end;

procedure MSG_WriteAngle(sb: Psizebuf_t; f: Single);
begin
  MSG_WriteByte(sb, Trunc(f * 256 / 360) and 255);
end;

//
// reading functions
//

procedure MSG_BeginReading;
begin
  msg_readcount := 0;
  msg_badread := false;
end;

// returns -1 and sets msg_badread if no more characters are available

function MSG_ReadChar: integer;
begin
  if msg_readcount + 1 > net_message.cursize then
  begin
    msg_badread := true;
    result := -1;
  end
  else
  begin
    result := signed_char(net_message.data[msg_readcount]);
    inc(msg_readcount);
  end;
end;

function MSG_ReadByte: integer;
begin
  if msg_readcount + 1 > net_message.cursize then
  begin
    msg_badread := true;
    result := -1;
  end
  else
  begin
    result := integer(net_message.data[msg_readcount]);
    inc(msg_readcount);
  end;
end;

function MSG_ReadShort: integer;
begin
  if msg_readcount + 2 > net_message.cursize then
  begin
    msg_badread := true;
    result := -1;
    exit;
  end;

  result := short(net_message.data[msg_readcount] + (net_message.data[msg_readcount + 1] shl 8));

  inc(msg_readcount, 2);
end;

function MSG_ReadLong: integer;
begin
  if msg_readcount + 4 > net_message.cursize then
  begin
    msg_badread := true;
    result := -1;
    exit;
  end;

  result := net_message.data[msg_readcount] +
    (net_message.data[msg_readcount + 1] shl 8) +
    (net_message.data[msg_readcount + 2] shl 16) +
    (net_message.data[msg_readcount + 3] shl 24);

  inc(msg_readcount, 4);
end;

function MSG_ReadFloat: single;
type
  union_fbl = packed record
    case Integer of
      0: (f: Single);
      1: (b: array[0..3] of Byte);
      2: (l: Integer);
  end;
var
  dat: union_fbl;
  i: integer;
begin
  for i := 0 to 3 do
  begin
    dat.b[i] := net_message.data[msg_readcount];
    inc(msg_readcount);
  end;

  dat.l := LittleLong(dat.l);

  result := dat.f;
end;

var
  string_MSG_ReadString: array[0..2048 - 1] of Char = #0;

function MSG_ReadString: PChar;
var
  l, c: integer;
begin
  l := 0;
  repeat
    c := MSG_ReadChar;
    if (c = -1) or (c = 0) then
      Break;
    string_MSG_ReadString[l] := Char(c);
    Inc(l);
  until (l >= SizeOf(string_MSG_ReadString) - 1);

  string_MSG_ReadString[l] := #0;

  Result := string_MSG_ReadString;
end;

function MSG_ReadCoord: single;
begin
  result := MSG_ReadShort * (1.0 / 8);
end;

function MSG_ReadAngle: single;
begin
  result := MSG_ReadChar * (360.0 / 256);
end;



//===========================================================================

procedure SZ_Alloc(buf: Psizebuf_t; startsize: integer);
begin
  if startsize < 256 then
    startsize := 256;
  buf.data := Hunk_AllocName(startsize, 'sizebuf');
  buf.maxsize := startsize;
  buf.cursize := 0;
end;


procedure SZ_Free(buf: Psizebuf_t);
begin
//      Z_Free (buf->data);
//      buf->data = NULL;
//      buf->maxsize = 0;
  buf.cursize := 0;
end;

procedure SZ_Clear(buf: Psizebuf_t);
begin
  buf.cursize := 0;
end;

function SZ_GetSpace(buf: Psizebuf_t; length: integer): pointer;
var
  data: pointer;
begin

  if buf.cursize + length > buf.maxsize then
  begin
    if not buf.allowoverflow then
      Sys_Error('SZ_GetSpace: overflow without allowoverflow set');

    if length > buf.maxsize then
      Sys_Error('SZ_GetSpace: %d is > full buffer size', [length]);

    buf.overflowed := true;
    Con_Printf('SZ_GetSpace: overflow');
    SZ_Clear(buf);
  end;

  data := pointer(integer(buf.data) + buf.cursize);
  buf.cursize := buf.cursize + length;

  result := data;
end;

procedure SZ_Write(buf: Psizebuf_t; data: pointer; length: integer);
begin
  memcpy(SZ_GetSpace(buf, length), data, length);
end;

procedure SZ_Print(buf: Psizebuf_t; data: PChar);
var
  len: integer;
begin
  len := Q_strlen(data) + 1;

  if buf.data[buf.cursize - 1] <> 0 then
    memcpy(SZ_GetSpace(buf, len), data, len) // no trailing 0
  else
    memcpy(pointer(integer(SZ_GetSpace(buf, len - 1)) - 1), data, len); // write over trailing 0
end;


//============================================================================


(*
============
COM_SkipPath
============
*)

function COM_SkipPath(pathname: PChar): PChar;
var
  last: PChar;
begin
  last := pathname;
  while pathname^ <> #0 do
  begin
    if pathname^ = '/' then // JVAL mayby check and '\'
      last := @PCharArray(pathname)[1];
    inc(pathname);
  end;
  result := last;
end;

(*
============
COM_StripExtension
============
*)

procedure COM_StripExtension(_in, _out: PChar);
begin
  while (_in^ <> #0) and (_in^ <> '.') do
  begin
    _out^ := _in^;
    inc(_in);
    inc(_out);
  end;
  _out^ := #0;
end;

(*
============
COM_FileExtension
============
*)
var
  exten: array[0..7] of char;

function COM_FileExtension(_in: PChar): PChar;
var
  i: integer;
begin
  while (_in^ <> #0) and (_in^ <> '.') do
    inc(_in);
  if (_in^ = #0) then
  begin
    result := '';
    exit;
  end;
  inc(_in);
  i := 0;
  while (i < 7) and (_in^ <> #0) do
  begin
    exten[i] := _in^;
    inc(i);
    inc(_in);
  end;
  exten[i] := #0;
  result := @exten;
end;

(*
============
COM_FileBase
============
*)

procedure COM_FileBase(_in, _out: PChar);
var
  s, s2: PChar;
begin
  s := _in;
  inc(s, strlen(_in) - 1);

  while (s <> _in) and (s^ <> '.') do
    dec(s);

  s2 := s;
  while (s2 <> _in) and (s2^ <> '/') and (s2^ <> '\') do
    dec(s2);

  if integer(s) - integer(s2) < 2 then
    strcpy(_out, '?model?')
  else
  begin
    dec(s);
    strncpy(_out, PChar(LongInt(s2) + 1), LongInt(s) - LongInt(s2));
    _out[LongInt(s) - LongInt(s2)] := #0;
  end;
end;


(*
==================
COM_DefaultExtension
==================
*)

procedure COM_DefaultExtension(path, extension: PChar);
var
  src: PChar;
begin
//
// if path doesn't have a .EXT, append extension
// (extension should include the .)
//
  src := path;
  inc(src, strlen(path) - 1);

  while (src^ <> '/') and (src <> path) do
  begin
    if (src^ = '.') then
      exit; // it has an extension
    dec(src);
  end;

  strcat(path, extension);
end;


(*
==============
COM_Parse

Parse a token out of a string
==============
*)

function COM_Parse(data: PChar): PChar;
label
  skipwhite;
var
  c: char;
  len: integer;

  function get_c: char;
  begin
    c := data^;
    result := c;
  end;

begin
  len := 0;
  com_token[0] := #0;

  if data = nil then
  begin
    result := nil;
    exit;
  end;

// skip whitespace
  skipwhite:
  while get_c <= ' ' do
  begin
    if c = #0 then
    begin
      result := nil; // end of file;
      exit;
    end;
    inc(data);
  end;

// skip // comments
  if (c = '/') and (data[1] = '/') then
  begin
    while not (data[0] in [#0, #10, #13]) do
      inc(data);
    goto skipwhite;
  end;


// handle quoted strings specially
  if c = '"' then
  begin
    inc(data);
    while true do
    begin
      c := data^;
      inc(data);
      if c in [#0, '"'] then
      begin
        com_token[len] := #0;
        result := data;
        exit;
      end;
      com_token[len] := c;
      inc(len);
    end;
  end;

// parse single characters
  if c in ['{', '}', ')', '(', '''', ':'] then
  begin
    com_token[len] := c;
    inc(len);
    com_token[len] := #0;
    result := @data[1];
    exit;
  end;

// parse a regular word
  repeat
    com_token[len] := c;
    inc(len);
    inc(data);
    c := data^;
    if c in ['{', '}', ')', '(', '''', ':'] then
      break;
  until c <= #32;

  com_token[len] := #0;
  result := data;
end;


(*
================
COM_CheckParm

Returns the position (1 to argc-1) in the program's argument list
where the given parameter apears, or 0 if not present
================
*)

function COM_CheckParm(parm: PChar): integer;
var
  i: integer;
begin
  for i := 1 to com_argc - 1 do
  begin
    if not boolval(com_argv[i]) then
      continue; // NEXTSTEP sometimes clears appkit vars.
    if Q_strcmp(parm, com_argv[i]) = 0 then
    begin
      result := i;
      exit;
    end;
  end;

  result := 0;
end;

(*
================
COM_CheckRegistered

Looks for the pop.txt file and verifies it.
Sets the "registered" cvar.
Immediately exits out if an alternate game was attempted to be started without
being registered.
================
*)

procedure COM_CheckRegistered;
var
  h: integer;
  check: array[0..127] of unsigned_short;
  i: integer;
begin
  COM_OpenFile('gfx/pop.lmp', @h);
  static_registered := 0;

  if h = -1 then
  begin
    Con_Printf('Playing shareware version.'#10);
//    if com_modified then
//      Sys_Error('You must have the registered version to use modified games'); // JVAL !!!
    exit;
  end;

  Sys_FileRead(h, @check, SizeOf(check));
  COM_CloseFile(h);

  for i := 0 to 127 do
    if pop[i] <> unsigned_short(BigShort(check[i])) then
      Sys_Error('Corrupted data file.');

  Cvar_Set('cmdline', com_cmdline);
  Cvar_Set('registered', '1');
  static_registered := 1;
  Con_Printf('Playing registered version.'#10);
end;


(*
================
COM_InitArgv
================
*)

function _Min(const x, y: integer): integer;
begin
  if x < y then
    result := x
  else
    result := y;
end;

procedure COM_InitArgv(argc: integer; argv: PArgvArray);
var
  safe: qboolean;
  i, j, n: integer;
  mn: integer;
begin
// reconstitute the command line for the cmdline externally visible cvar
  n := 0;

  mn := _Min(MAX_NUM_ARGVS, argc);
  for j := 0 to mn - 1 do
  begin
    i := 0;

    while (n < CMDLINE_LENGTH - 1) and (argv[j][i] <> #0) do
    begin
      com_cmdline[n] := argv[j][i];
      inc(i);
      inc(n);
    end;

    if n < CMDLINE_LENGTH - 1 then
    begin
      com_cmdline[n] := ' ';
      inc(n);
    end
    else
      break;
  end;

  com_cmdline[n] := #0;

  safe := false;

  com_argc := 0;
  while com_argc < mn do
  begin
    largv[com_argc] := argv[com_argc];
    if Q_strcmp('-safe', argv[com_argc]) = 0 then
      safe := true;
    inc(com_argc);
  end;

  if safe then
  begin
  // force all the safe-mode switches. Note that we reserved extra space in
  // case we need to add these, so we don't need an overflow check
    for i := 0 to NUM_SAFE_ARGVS - 1 do
    begin
      largv[com_argc] := safeargvs[i];
      inc(com_argc);
    end;
  end;

  largv[com_argc] := argvdummy;
  com_argv := @largv;

  if COM_CheckParm('-rogue') > 0 then
  begin
    rogue := true;
    standard_quake := false;
  end;

  if COM_CheckParm('-hipnotic') > 0 then
  begin
    hipnotic := true;
    standard_quake := false;
  end;
end;


(*
================
COM_Init
================
*)

procedure COM_Init(basedir: PChar);
const
  swaptest: array[0..1] of byte = (1, 0);
begin
// set the byte swapping variables in a portable manner
  if Pshort(@swaptest)^ = 1 then
  begin
    bigendien := false;
    BigShort := ShortSwap;
    LittleShort := ShortNoSwap;
    BigLong := LongSwap;
    LittleLong := LongNoSwap;
    BigFloat := FloatSwap;
    LittleFloat := FloatNoSwap;
  end
  else
  begin
    bigendien := true;
    BigShort := ShortNoSwap;
    LittleShort := ShortSwap;
    BigLong := LongNoSwap;
    LittleLong := LongSwap;
    BigFloat := FloatNoSwap;
    LittleFloat := FloatSwap;
  end;

  Cvar_RegisterVariable(@registered);
  Cvar_RegisterVariable(@cmdline);
  Cmd_AddCommand('path', COM_Path_f);

  COM_InitFilesystem;
  COM_CheckRegistered;
end;


(*
============
va

does a varargs printf into a temp buffer, so I don't need to have
varargs versions of all text functions.
FIXME: make this buffer size safe someday
============
*)
var
  str: array[0..$FFFF] of char;

function va(format: PChar; const Args: array of const): PChar;
begin
  sprintf(str, format, Args);
  result := str;
end;


/// just for debugging

function memsearch(start: PByteArray; count, search: integer): integer;
var
  i: integer;
begin
  for i := 0 to count - 1 do
    if start[i] = search then
    begin
      result := i;
      exit;
    end;

  result := -1;
end;

(*
=============================================================================

QUAKE FILESYSTEM

=============================================================================
*)

const
  MAX_FILES_IN_PACK = $2000;

var
  com_cachedir: array[0..MAX_OSPATH - 1] of char;

type
  Psearchpath_t = ^searchpath_t;
  searchpath_t = record
    filename: array[0..MAX_OSPATH - 1] of char;
    pack: Ppack_t; // only one of filename / pack will be used
    next: Psearchpath_t;
  end;

var
  com_searchpaths: Psearchpath_t;

(*
============
COM_Path_f

============
*)

procedure COM_Path_f;
var
  s: Psearchpath_t;
begin
  Con_Printf('Current search path:'#10);
  s := com_searchpaths;
  while s <> nil do
  begin
    if s.pack <> nil then
      Con_Printf('%s (%d files)'#10, [s.pack.filename, s.pack.numfiles])
    else
      Con_Printf('%s'#10, [s.filename]);
    s := s.next;
  end;
end;

(*
============
COM_WriteFile

The filename will be prefixed by the current game directory
============
*)

procedure COM_WriteFile(filename: PChar; data: pointer; len: integer);
var
  handle: integer;
  name: array[0..MAX_OSPATH - 1] of char;
begin
  sprintf(name, '%s/%s', [com_gamedir, filename]);

  handle := Sys_FileOpenWrite(name);
  if handle = -1 then
  begin
    Sys_Printf('COM_WriteFile: failed on %s'#10, [name]);
    exit;
  end;

  Sys_Printf('COM_WriteFile: %s'#10, [name]);
  Sys_FileWrite(handle, data, len);
  Sys_FileClose(handle);
end;


(*
============
COM_CreatePath

Only used for CopyFile
============
*)

procedure COM_CreatePath(path: PChar);
var
  ofs: PChar;
begin
// JVAL mayby: ForceDirectories()
  ofs := @path[1];
  while ofs^ <> #0 do
  begin
    if ofs^ = '/' then
    begin // create the directory
      ofs^ := #0;
      Sys_mkdir(path);
      ofs^ := '/';
    end;
    inc(ofs);
  end;
end;


(*
===========
COM_CopyFile

Copies a file over from the net to the local cache, creating any directories
needed.  This is for the convenience of developers using ISDN from home.
===========
*)

procedure COM_CopyFile(netpath: PChar; cachepath: PChar);
var
  _in, _out: integer;
  remaining, count: integer;
  buf: array[0..4095] of char;
begin
  remaining := Sys_FileOpenRead(netpath, @_in);
  COM_CreatePath(cachepath); // create directories up to the cache file
  _out := Sys_FileOpenWrite(cachepath);

  while remaining <> 0 do
  begin
    if remaining < SizeOf(buf) then
      count := remaining
    else
      count := SizeOf(buf);
    Sys_FileRead(_in, @buf, count);
    Sys_FileWrite(_out, @buf, count);
    remaining := remaining - count;
  end;

  Sys_FileClose(_in);
  Sys_FileClose(_out);
end;

(*
===========
COM_FindFile

Finds the file in the search path.
Sets com_filesize and one of handle or file
===========
*)

function COM_FindFile(filename: PChar; handle: Pinteger; var f: integer): integer;
var
  search: Psearchpath_t;
  netpath: array[0..MAX_OSPATH - 1] of char;
  path: PChar;
  cachepath: array[0..MAX_OSPATH - 1] of char;
  pak: Ppack_t;
  i: integer;
  findtime, cachetime: integer;
begin
{  if boolval(f) and boolval(handle) then
    Sys_Error('COM_FindFile: both handle and file set');
  if not boolval(f) and not boolval(handle) then
    Sys_Error('COM_FindFile: neither handle or file set');}
{
  if (f <> -1) and (handle <> nil) then
    Sys_Error('COM_FindFile: both handle and file set '+filename);
  if (f = -1) and (handle = nil) then
    Sys_Error('COM_FindFile: neither handle or file set '+filename);
}
//
// search through the path, one element at a time
//
  search := com_searchpaths;
  if proghack then
  begin // gross hack to use quake 1 progs with quake 2 maps
    if strcmp(filename, 'progs.dat') = 0 then
      search := search.next;
  end;

  while search <> nil do
  begin
  // is the element a pak file?
    if search.pack <> nil then
    begin
    // look through all the pak file elements
      pak := search.pack;
      for i := 0 to pak.numfiles - 1 do
        if strcmp(pak.files[i].name, filename) = 0 then
        begin // found it!
          Sys_Printf('PackFile: %s : %s'#10, [pak.filename, filename]);
          if handle <> nil then
          begin
            handle^ := pak.handle;
            Sys_FileSeek(pak.handle, pak.files[i].filepos);
          end
          else
          begin // open a new file on the pakfile
            f := fopen(pak.filename, 'rb');
            if f <> NULLFILE then
              fseek(f, pak.files[i].filepos, 0);
          end;
          com_filesize := pak.files[i].filelen;
          result := com_filesize;
          exit;
        end;
    end
    else
    begin
  // check a file in the directory tree
      if static_registered = 0 then
      begin // if not a registered version, don't ever go beyond base
        if strchr(filename, '/') or strchr(filename, '\') then
        begin
          search := search.next;
          continue;
        end;
      end;

      sprintf(netpath, '%s/%s', [search.filename, filename]);

      findtime := Sys_FileTime(netpath);
      if findtime = -1 then
      begin
        search := search.next;
        continue;
      end;

    // see if the file needs to be updated in the cache
      if com_cachedir[0] = #0 then
        strcpy(cachepath, netpath)
      else
      begin
        if (strlen(netpath) < 2) or (netpath[1] <> ':') then
          path := @netpath[0]
        else
          path := @netpath[2];
        sprintf(cachepath, '%s%s', [com_cachedir, path]);
        cachetime := Sys_FileTime(cachepath);

        if cachetime < findtime then
          COM_CopyFile(netpath, cachepath);
        strcpy(netpath, cachepath);
      end;

      Sys_Printf('FindFile: %s'#10, [netpath]);
      com_filesize := Sys_FileOpenRead(netpath, @i);
      if handle <> nil then
        handle^ := i
      else
      begin
        Sys_FileClose(i);
        f := fopen(netpath, 'rb');
      end;
      result := com_filesize;
      exit;
    end;
    search := search.next;
  end;

  Sys_Printf('FindFile: can''t find %s'#10, [filename]);

  if handle <> nil then
    handle^ := -1
  else
  begin
    fclose(f);
  end;
  com_filesize := -1;
  result := -1;
end;


(*
===========
COM_OpenFile

filename never has a leading slash, but may contain directory walks
returns a handle and a length
it may actually be inside a pak file
===========
*)

function COM_OpenFile(filename: PChar; handle: Pinteger): integer;
var
  f: integer;
begin
  f := NULLFILE;
  result := COM_FindFile(filename, handle, f);
end;

(*
===========
COM_FOpenFile

If the requested file is inside a packfile, a new FILE * will be opened
into the file.
===========
*)

function COM_FOpenFile(filename: PChar; var f: integer): integer;
begin
  f := NULLFILE;
  result := COM_FindFile(filename, nil, f);
end;

(*
============
COM_CloseFile

If it is a pak file handle, don't really close it
============
*)

procedure COM_CloseFile(h: integer);
var
  s: Psearchpath_t;
begin
  s := com_searchpaths;
  while s <> nil do
  begin
    if (s.pack <> nil) and (s.pack.handle = h) then
      exit;
    s := s.next;
  end;

  Sys_FileClose(h);
end;


(*
============
COM_LoadFile

Filename are reletive to the quake directory.
Allways appends a 0 byte.
============
*)
var
  loadcache: Pcache_user_t;
  loadbuf: PByteArray;
  loadsize: integer;

function COM_LoadFile(path: PChar; usehunk: integer): PByteArray;
var
  h: integer;
  buf: PByteArray;
  base: array[0..31] of char;
  len: integer;
begin
  buf := nil; // quiet compiler warning

// look for it in the filesystem or pack files
  len := COM_OpenFile(path, @h);
  if h = -1 then
  begin
    result := nil;
    exit;
  end;

// extract the filename base name for hunk tag
  COM_FileBase(path, base);

  if usehunk = 1 then
    buf := Hunk_AllocName(len + 1, base)
  else if usehunk = 2 then
    buf := Hunk_TempAlloc(len + 1)
  else if usehunk = 0 then
    buf := Z_Malloc(len + 1)
  else if usehunk = 3 then
    buf := Cache_Alloc(loadcache, len + 1, base)
  else if usehunk = 4 then
  begin
    if len + 1 > loadsize then
      buf := Hunk_TempAlloc(len + 1)
    else
      buf := loadbuf;
  end
  else
    Sys_Error('COM_LoadFile: bad usehunk');

  if buf = nil then
    Sys_Error('COM_LoadFile: not enough space for %s', [path]);

  buf[len] := 0;

  Draw_BeginDisc;
  Sys_FileRead(h, buf, len);
  COM_CloseFile(h);
  Draw_EndDisc;

  result := buf;
end;

function COM_LoadHunkFile(path: PChar): PByteArray;
begin
  result := COM_LoadFile(path, 1);
end;

function COM_LoadTempFile(path: PChar): PByteArray;
begin
  result := COM_LoadFile(path, 2);
end;

procedure COM_LoadCacheFile(path: PChar; cu: Pcache_user_t);
begin
  loadcache := cu;
  COM_LoadFile(path, 3);
end;

// uses temp hunk if larger than bufsize

function COM_LoadStackFile(path: PChar; buffer: pointer; bufsize: integer): PByteArray;
var
  buf: PByteArray;
begin
  loadbuf := PByteArray(buffer);
  loadsize := bufsize;
  buf := COM_LoadFile(path, 4);

  result := buf;
end;

(*
=================
COM_LoadPackFile

Takes an explicit (not game tree related) path to a pak file.

Loads the header and directory, adding the files at the beginning
of the list so they override previous pack files.
=================
*)

function COM_LoadPackFile(packfile: PChar): Ppack_t;
var
  header: dpackheader_t;
  i: integer;
  newfiles: Ppackfile_tArray;
  numpackfiles: integer;
  pack: Ppack_t;
  packhandle: integer;
  info: array[0..MAX_FILES_IN_PACK - 1] of dpackfile_t;
  crc: unsigned_short;
begin
  if Sys_FileOpenRead(packfile, @packhandle) = -1 then
  begin
//              Con_Printf ("Couldn't open %s\n", packfile);
    result := nil;
    exit;
  end;

  Sys_FileRead(packhandle, @header, SizeOf(header));
  if (header.id[0] <> 'P') or (header.id[1] <> 'A') or
    (header.id[2] <> 'C') or (header.id[3] <> 'K') then
    Sys_Error('%s is not a packfile', [packfile]);
  header.dirofs := LittleLong(header.dirofs);
  header.dirlen := LittleLong(header.dirlen);

  numpackfiles := header.dirlen div SizeOf(dpackfile_t);

  if numpackfiles > MAX_FILES_IN_PACK then
    Sys_Error('%s has %d files', [packfile, numpackfiles]);

  if (numpackfiles <> PAK0_COUNT) then
    com_modified := true; // not the original file

  newfiles := Hunk_AllocName(numpackfiles * SizeOf(packfile_t), 'packfile');

  Sys_FileSeek(packhandle, header.dirofs);
  Sys_FileRead(packhandle, @info, header.dirlen);

// crc the directory to check for modifications
  CRC_Init(@crc);
  for i := 0 to header.dirlen - 1 do
    CRC_ProcessByte(@crc, PByteArray(@info)[i]);
  if crc <> PAK0_CRC then
    com_modified := true;

// parse the directory
  for i := 0 to numpackfiles - 1 do
  begin
    strcpy(newfiles[i].name, info[i].name);
    newfiles[i].filepos := LittleLong(info[i].filepos);
    newfiles[i].filelen := LittleLong(info[i].filelen);
  end;

  pack := Hunk_Alloc(SizeOf(pack_t));
  strcpy(pack.filename, packfile);
  pack.handle := packhandle;
  pack.numfiles := numpackfiles;
  pack.files := newfiles;

  Con_Printf('Added packfile %s (%d files)'#10, [packfile, numpackfiles]);
  result := pack;
end;


(*
================
COM_AddGameDirectory

Sets com_gamedir, adds the directory to the head of the path,
then loads and adds pak1.pak pak2.pak ...
================
*)

procedure COM_AddGameDirectory(dir: PChar);
var
  i: integer;
  search: Psearchpath_t;
  pak: Ppack_t;
  pakfile: array[0..MAX_OSPATH - 1] of char;
begin
  strcpy(com_gamedir, dir);

//
// add the directory to the search path
//
  search := Hunk_Alloc(SizeOf(searchpath_t));
  strcpy(search.filename, dir);
  search.next := com_searchpaths;
  com_searchpaths := search;

//
// add any pak files in the format pak0.pak pak1.pak, ...
//
  i := 0;
  while true do
  begin
    sprintf(pakfile, '%s/pak%d.pak', [dir, i]);
    pak := COM_LoadPackFile(pakfile);
    if pak = nil then
      break;
    search := Hunk_Alloc(SizeOf(searchpath_t));
    search.pack := pak;
    search.next := com_searchpaths;
    com_searchpaths := search;
    inc(i);
  end;

//
// add the contents of the parms.txt file to the end of the command line
//

end;


(*
================
COM_InitFilesystem
================
*)

procedure COM_InitFilesystem;
var
  i, j: integer;
  basedir: array[0..MAX_OSPATH - 1] of char;
  search: Psearchpath_t;
begin
//
// -basedir <path>
// Overrides the system supplied base directory (under GAMENAME)
//
  Sys_InitFileHandles;

  i := COM_CheckParm('-basedir');
  if (i > 0) and (i < com_argc - 1) then
    strcpy(basedir, com_argv[i + 1])
  else
    strcpy(basedir, host_parms.basedir);

  j := strlen(basedir);

  if j > 0 then
  begin
    if basedir[j - 1] in ['\', '/'] then
      basedir[j - 1] := #0;
  end;

//
// -cachedir <path>
// Overrides the system supplied cache directory (NULL or /qcache)
// -cachedir - will disable caching.
//
  i := COM_CheckParm('-cachedir');
  if (i > 0) and (i < com_argc - 1) then
  begin
    inc(i);
    if com_argv[i][0] = '-' then
      com_cachedir[0] := #0
    else
      strcpy(com_cachedir, com_argv[i]);
  end
  else if host_parms.cachedir <> nil then
    strcpy(com_cachedir, host_parms.cachedir)
  else
    com_cachedir[0] := #0;

//
// start up with GAMENAME by default (id1)
//
  COM_AddGameDirectory(va('%s/%s', [basedir, GAMENAME]));

  if COM_CheckParm('-rogue') <> 0 then
    COM_AddGameDirectory(va('%s/rogue', [basedir]));
  if COM_CheckParm('-hipnotic') <> 0 then
    COM_AddGameDirectory(va('%s/hipnotic', [basedir]));

//
// -game <gamedir>
// Adds basedir/gamedir as an override game
//
  i := COM_CheckParm('-game');
  if (i > 0) and (i < com_argc - 1) then
  begin
    com_modified := true;
    COM_AddGameDirectory(va('%s/%s', [basedir, com_argv[i + 1]]));
  end;

//
// -path <dir or packfile> [<dir or packfile>] ...
// Fully specifies the exact search path, overriding the generated one
//
  i := COM_CheckParm('-path');
  if i <> 0 then
  begin
    com_modified := true;
    com_searchpaths := nil;
    while i < com_argc - 1 do // JVAL, mayby while i < com_argc do
    begin
      inc(i);
      if not boolval(com_argv[i]) or (com_argv[i][0] = '+') or (com_argv[i][0] = '-') then
        break;

      search := Hunk_Alloc(SizeOf(searchpath_t));
      if strcmp(COM_FileExtension(com_argv[i]), 'pak') = 0 then
      begin
        search.pack := COM_LoadPackFile(com_argv[i]);
        if search.pack = nil then
          Sys_Error('Couldn''t load packfile: %s', [com_argv[i]]);
      end
      else
        strcpy(search.filename, com_argv[i]);
      search.next := com_searchpaths;
      com_searchpaths := search;
    end;
  end;

  if COM_CheckParm('-proghack') <> 0 then
    proghack := true;
end;


end.


