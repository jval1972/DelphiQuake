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

unit q_delphi;

interface

const
  MAXINT = $7fffffff;
  MININT = integer($80000000);
  MAXSHORT = $7fff;

type
  qboolean  = LongBool;
  Pqboolean = ^qboolean;

  PByte = ^Byte;
  PInteger = ^integer;

  Psingle = ^single;

  unsigned = longword;
  Punsigned = ^unsigned;

  unsigned_int = longword;
  Punsigned_int = ^unsigned_int;

  signed_char = shortint;
  unsigned_char = byte;

  short = smallint;
  Pshort = ^short;

  u_short = word;
  Pu_short = ^u_short;

  unsigned_short = word;
  Punsigned_short = ^unsigned_short;

  LONG = longint;
  PLONG = ^LONG;

  Punsigned_shortArray = ^Tunsigned_shortArray;
  Tunsigned_shortArray = array[0..$FFFF] of unsigned_short;

  PunsignedArray = ^TunsignedArray;
  TunsignedArray = array[0..$FFFF] of unsigned;

  PFloatArray = ^TFloatArray;
  TFloatArray = array[0..$FFFF] of single;

  PShortArray = ^TShortArray;
  TShortArray = array[0..$FFFF] of short;

  PCharArray = ^TCharArray;
  TCharArray = array[0..$FFFF] of char;

  PPChar = ^PChar;

type
  PPointer = ^Pointer;

  PString = ^string;

  PBoolean = ^Boolean;

  PLongWord = ^LongWord;

  PShortInt = ^ShortInt;

  TWordArray = packed array[0..$FFFF] of word;
  PWordArray = ^TWordArray;

  TIntegerArray = packed array[0..$FFFF] of integer;
  PIntegerArray = ^TIntegerArray;

  TLongWordArray = packed array[0..$FFFF] of LongWord;
  PLongWordArray = ^TLongWordArray;

  TSmallintArray = packed array[0..$FFFF] of Smallint;
  PSmallintArray = ^TSmallintArray;

  TByteArray = packed array[0..$FFFF] of Byte;
  PByteArray = ^TByteArray;

  TBooleanArray = packed array[0..$FFFF] of boolean;
  PBooleanArray = ^TBooleanArray;

  PProcedure = procedure;
  PIntFunction = function: integer;

  TStringArray = array[0..$FFFF] of string;
  PStringArray = ^TStringArray;

  TPointerArray = packed array[0..$FFFF] of pointer;
  PPointerArray = ^TPointerArray;

  PSmallInt = ^SmallInt;
  TSmallIntPArray = packed array[0..$FFFF] of PSmallIntArray;
  PSmallIntPArray = ^TSmallIntPArray;

  PWord = ^Word;
  TWordPArray = packed array[0..$FFFF] of PWordArray;
  PWordPArray = ^TWordPArray;

  TLongWordPArray = packed array[0..$FFFF] of PLongWordArray;
  PLongWordPArray = ^TLongWordPArray;

  TIntegerPArray = packed array[0..$FFFF] of PIntegerArray;
  PIntegerPArray = ^TIntegerPArray;

  TBytePArray = packed array[0..$FFFF] of PByteArray;
  PBytePArray = ^TBytePArray;

  float = single;

type
  charset_t = set of char;

  twobytes = packed record
    byte1, byte2: byte;
  end;

  TOutProc = procedure (const s: string);

var
  outproc: TOutProc = nil;

procedure printf(const str: string); overload;

procedure printf(const Fmt: string; const Args: array of const); overload;

function ftoa(f: integer): string;

function atoui(const s: string): longword; overload;

function atoui(const s: string; const default: longword): longword; overload;

//
// Memory functions
//
function memmove(const destination, source: pointer; count: integer): pointer;

function memcpy(const dest0: pointer; const src0: pointer; count0: integer): pointer;

function memset(const dest0: pointer; const val: integer; const count0: integer): pointer;

function malloc(const size: integer): Pointer;

function mallocA(var Size: integer; const Align: integer; var original: pointer): pointer;

function mallocz(const size: integer): Pointer;

procedure realloc(var p: pointer; const oldsize, newsize: integer);

procedure memfree(var p: pointer; const size: integer);

var
  memoryusage: integer = 0;

function IntToStrZfill(const z: integer; const x: integer): string;

function pDiff(const p1, p2: pointer; const size: integer): integer;

function getenv(const env: string): string;

function fexists(const filename: string): boolean;

function fexpand(const filename: string): string;

procedure fdelete(const filename: string);

function fext(const filename: string): string;

function fname(const filename: string): string;

const
  fCreate = 0;
  fOpenReadOnly = 1;
  fOpenReadWrite = 2;

  sFromBeginning = 0;
  sFromCurrent = 1;
  sFromEnd = 2;

type
  TStream = class
  protected
    FIOResult: integer;
  public
    OnBeginBusy: PProcedure;
    OnEndBusy: PProcedure;
    constructor Create;
    function Read(var Buffer; Count: Longint): Longint; virtual; abstract;
    function Write(const Buffer; Count: Longint): Longint; virtual; abstract;
    function Seek(Offset: Longint; Origin: Word): Longint; virtual; abstract;
    function Size: Longint; virtual; abstract;
    function Position: integer; virtual; abstract;
    function IOResult: integer;
  end;

  TMemoryStream = class(TStream)
  protected
    FSize: integer;
    FPosition: integer;
    FMemory: pointer;
    procedure Resize(newsize: integer);
  public
    OnBeginBusy: PProcedure;
    OnEndBusy: PProcedure;
    constructor Create;
    destructor Destroy; override;
    function Read(var Buffer; Count: Longint): Longint; override;
    function Write(const Buffer; Count: Longint): Longint; override;
    function Seek(Offset: Longint; Origin: Word): Longint; override;
    function Size: Longint; override;
    function Position: integer; override;
  end;

  TFile = class(TStream)
  private
    f: file;
  public
    constructor Create(const FileName: string; const mode: integer);
    destructor Destroy; override;
    function Read(var Buffer; Count: Longint): Longint; override;
    function Write(const Buffer; Count: Longint): Longint; override;
    function Seek(Offset: Longint; Origin: Word): Longint; override;
    function Size: Longint; override;
    function Position: integer; override;
  end;

  TCachedFile = class(TFile)
  private
    fBufSize: integer;
    fBuffer: pointer;
    fPosition: integer;
    fBufferStart: integer;
    fBufferEnd: integer;
    fSize: integer;
    fInitialized: boolean;
  protected
    procedure SetSize(NewSize: Longint); virtual;
    procedure ResetBuffer; virtual;
  public
    constructor Create(const FileName: string; mode: word; ABufSize: integer = $FFFF); virtual;
    destructor Destroy; override;
    function Read(var Buffer; Count: Longint): Longint; override;
    function Write(const Buffer; Count: Longint): Longint; override;
    function Seek(Offset: Longint; Origin: Word): Longint; override;
    function Position: integer; override;
  end;


type
  TDNumberList = class
  private
    fList: PIntegerArray;
    fNumItems: integer;
  protected
    function Get(Index: Integer): integer; virtual;
    procedure Put(Index: Integer; const value: integer); virtual;
  public
    constructor Create; virtual;
    destructor Destroy; override;
    function Add(const value: integer): integer; overload; virtual;
    procedure Add(const nlist: TDNumberList); overload; virtual;
    function Delete(const Index: integer): boolean;
    function IndexOf(const value: integer): integer;
    procedure Clear;
    property Count: integer read fNumItems;
    property Numbers[Index: Integer]: integer read Get write Put; default;
  end;

type
  TTextArray = array[0..$FFFF] of string[255];
  PTextArray = ^TTextArray;

type
  TDTextList = class
  private
    fList: PTextArray;
    fNumItems: integer;
  protected
    function Get(Index: Integer): string; virtual;
    procedure Put(Index: Integer; const value: string); virtual;
  public
    constructor Create; virtual;
    destructor Destroy; override;
    procedure Add(const value: string); overload; virtual;
    procedure Add(const nlist: TDTextList); overload; virtual;
    function Delete(const Index: integer): boolean;
    function IndexOf(const value: string): integer;
    procedure Clear;
    property Count: integer read fNumItems;
    property Numbers[Index: Integer]: string read Get write Put; default;
  end;


const
  MaxListSize = MAXINT div 16;

type
{ TDStrings class }

  TDStrings = class
  private
    function GetCommaText: string;
    function GetName(Index: Integer): string;
    function GetValue(const Name: string): string;
    function GetValueIdx(const idx: integer): string;
    procedure SetCommaText(const Value: string);
    procedure SetValue(const Name, Value: string);
  protected
    function Get(Index: Integer): string; virtual; abstract;
    function GetCapacity: Integer; virtual;
    function GetCount: Integer; virtual; abstract;
    function GetObject(Index: Integer): TObject; virtual;
    function GetTextStr: string; virtual;
    procedure Put(Index: Integer; const S: string); virtual;
    procedure PutObject(Index: Integer; AObject: TObject); virtual;
    procedure SetCapacity(NewCapacity: Integer); virtual;
    procedure SetTextStr(const Value: string); virtual;
    procedure SetByteStr(const A: PByteArray; const Size: integer); virtual;
  public
    function Add(const S: string): Integer; overload; virtual;
    function Add(const Fmt: string; const Args: array of const): Integer; overload; virtual;
    function AddObject(const S: string; AObject: TObject): Integer; virtual;
    procedure Append(const S: string);
    procedure AddStrings(Strings: TDStrings); virtual;
    procedure Clear; virtual; abstract;
    procedure Delete(Index: Integer); virtual; abstract;
    function Equals(Strings: TDStrings): Boolean;
    procedure Exchange(Index1, Index2: Integer); virtual;
    function GetText: PChar; virtual;
    function IndexOf(const S: string): Integer; virtual;
    function IndexOfName(const Name: string): Integer;
    function IndexOfObject(AObject: TObject): Integer;
    procedure Insert(Index: Integer; const S: string); virtual; abstract;
    procedure InsertObject(Index: Integer; const S: string;
      AObject: TObject);
    function  LoadFromFile(const FileName: string): boolean; virtual;
    function  LoadFromStream(const strm: TStream): boolean; virtual;
    procedure Move(CurIndex, NewIndex: Integer); virtual;
    function SaveToFile(const FileName: string): boolean; virtual;
    procedure SetText(Text: PChar); virtual;
    property Capacity: Integer read GetCapacity write SetCapacity;
    property CommaText: string read GetCommaText write SetCommaText;
    property Count: Integer read GetCount;
    property Names[Index: Integer]: string read GetName;
    property Objects[Index: Integer]: TObject read GetObject write PutObject;
    property Values[const Name: string]: string read GetValue write SetValue;
    property ValuesIdx[const idx: integer]: string read GetValueIdx;
    property Strings[Index: Integer]: string read Get write Put; default;
    property Text: string read GetTextStr write SetTextStr;
  end;

{ TDStringList class }

  TDStringList = class;

  PStringItem = ^TStringItem;
  TStringItem = record
    FString: string;
    FObject: TObject;
  end;

  PStringItemList = ^TStringItemList;
  TStringItemList = array[0..MaxListSize] of TStringItem;

  TDStringList = class(TDStrings)
  private
    FList: PStringItemList;
    FCount: Integer;
    FCapacity: Integer;
    procedure ExchangeItems(Index1, Index2: Integer);
    procedure Grow;
    procedure InsertItem(Index: Integer; const S: string);
  protected
    function Get(Index: Integer): string; override;
    function GetCapacity: Integer; override;
    function GetCount: Integer; override;
    function GetObject(Index: Integer): TObject; override;
    procedure Put(Index: Integer; const S: string); override;
    procedure PutObject(Index: Integer; AObject: TObject); override;
    procedure SetCapacity(NewCapacity: Integer); override;
  public
    destructor Destroy; override;
    function Add(const S: string): Integer; override;
    procedure Clear; override;
    procedure Delete(Index: Integer); override;
    procedure Exchange(Index1, Index2: Integer); override;
    procedure Insert(Index: Integer; const S: string); override;
  end;

function findfile(const mask: string): string;

function findfiles(const mask: string): TDStringList;

procedure fprintf(var f: file; const Fmt: string; const Args: array of const); overload;
procedure fprintf(const f: TFile; const str: string); overload;
procedure fprintf(const f: TFile; const Fmt: string; const Args: array of const); overload;
procedure fprintf(var f: text; const Fmt: PChar); overload;
procedure fprintf(var f: file; const Fmt: PChar); overload;
procedure fprintf(f: integer; const Fmt: PChar); overload;
procedure fprintf(var f: text; const Fmt: PChar; const Args: array of const); overload;
procedure fprintf(var f: file; const Fmt: PChar; const Args: array of const); overload;
procedure fprintf(f: integer; const Fmt: PChar; const Args: array of const); overload;
procedure fprintf(var f: text; const Fmt: string); overload;
procedure fprintf(var f: file; const Fmt: string); overload;
procedure fprintf(f: integer; const Fmt: string); overload;
procedure fprintf(var f: text; const Fmt: string; const Args: array of const); overload;
//procedure fprintf(var f: file; const Fmt: string; const Args: array of const); overload;
//procedure fprintf(f: integer; const Fmt: string; const Args: array of const); overload;


function tan(const x: extended): extended;

function strupper(const S: string): string;

function strlower(const S: string): string;

function strremovespaces(const s: string): string;

function _SHL(const x: integer; const bits: integer): integer;

function _SHLW(const x: LongWord; const bits: LongWord): LongWord;

function _SHR(const x: integer; const bits: integer): integer;
function _SHR1(const x: integer): integer;
function _SHR2(const x: integer): integer;
function _SHR3(const x: integer): integer;
function _SHR4(const x: integer): integer;
function _SHR7(const x: integer): integer;
function _SHR8(const x: integer): integer;
function _SHR14(const x: integer): integer;

function _SHRW(const x: LongWord; const bits: LongWord): LongWord;

function StringVal(const Str: PChar): string;

procedure ZeroMemory(const dest0: pointer; const count0: integer);

function fsize(const FileName: string): integer;

function fshortname(const FileName: string): string;

function strtrim(const S: string): string;

function capitalizedstring(const S: string; const splitter: char = ' '): string;

procedure splitstring(const inp: string; var out1, out2: string; const splitter: string = ' '); overload;

procedure splitstring(const inp: string; var out1, out2: string; const splitters: charset_t); overload;

function firstword(const inp: string; const splitter: string = ' '): string; overload;

function firstword(const inp: string; const splitters: charset_t): string; overload;

function secondword(const inp: string; const splitter: string = ' '): string; overload;

function secondword(const inp: string; const splitters: charset_t): string; overload;

function lastword(const inp: string; const splitter: string = ' '): string; overload;

function lastword(const inp: string; const splitters: charset_t): string; overload;

procedure FreeAndNil(var Obj);

function StrLCopy(Dest: PChar; const Source: PChar; MaxLen: Cardinal): PChar;

function fabs(const f: float): float;

procedure MakeDir(const dir: string);

function PascalText(src: PChar): string;

procedure CopyFile(const sname, dname: string);

function IsIntegerInRange(const test, f1, f2: integer): boolean;

function IsFloatInRange(const test, f1, f2: float): boolean;

procedure sprintf(s: PChar; const Fmt: PChar); overload;
procedure sprintf(s: PChar; const Fmt: PChar; const Args: array of const); overload;
procedure sprintf(var s: string; const Fmt: PChar); overload;
procedure sprintf(var s: string; const Fmt: PChar; const Args: array of const); overload;
procedure sprintf(s: PChar; const Fmt: string); overload;
procedure sprintf(s: PChar; const Fmt: string; const Args: array of const); overload;
procedure sprintf(var s: string; const Fmt: string); overload;
procedure sprintf(var s: string; const Fmt: string; const Args: array of const); overload;

function itoa(i: integer): string;

function atoi(const s: string): integer; overload;
function atoi(const s: PChar): integer; overload;
function atoi(const s: string; const default: integer): integer; overload;

function atof(const s: string): single; overload;
function atof(const s: PChar): single; overload;
function atof(const s: string; const default: single): single; overload;

function boolval(const x: integer): boolean; overload;
function boolval(const c: char): boolean; overload;
function boolval(const p: pointer): boolean; overload;
function boolval(const f: single): boolean; overload;
function boolval(var f: file): boolean; overload;

function intval(const b: boolean): integer; overload;
function intval(const f: single): integer; overload;

function floatval(const b: boolean): single;

function decidef(const condition: boolean;
  const iftrue: single; const iffalse: single): single;

function decide(const contition: boolean; const iftrue: integer; const iffalse: integer): integer; overload;
function decide(const contition: boolean; const iftrue: boolean; const iffalse: boolean): boolean; overload;
function decide(const contition: boolean; const iftrue: string; const iffalse: string): string; overload;
function decide(const contition: boolean; const iftrue: pointer; const iffalse: pointer): pointer; overload;
function decide(const contition: integer; const iftrue: integer; const iffalse: integer): integer; overload;
function decide(const contition: integer; const iftrue: boolean; const iffalse: boolean): boolean; overload;
function decide(const contition: integer; const iftrue: string; const iffalse: string): string; overload;
function decide(const contition: integer; const iftrue: pointer; const iffalse: pointer): pointer; overload;

function fread(buf: pointer; size: integer; count: integer; f: integer): integer; overload;
function fread(buf: pointer; size: integer; count: integer; var f: file): integer; overload;
function fwrite(buf: pointer; size: integer; count: integer; f: integer): integer; overload;
function fwrite(buf: pointer; size: integer; count: integer; var f: file): integer; overload;
procedure fclose(var f: integer); overload;
procedure fclose(var f: file); overload;
procedure fclose(var f: text); overload;

procedure fscanf(var f: text; buf: PChar); overload;
procedure fscanf(var f: text; var num: single); overload;
procedure fscanf(var f: text; var num: integer); overload;

function strstr(const _string: PChar; const strCharSet: PChar): PChar;
function strchr(const _string: PChar; const strChar: char): boolean;
function getc(f: integer; var c: char): char; overload;
function getc(var f: file; var c: char): char; overload;
function getc(var f: text; var c: char): char; overload;
function rand: integer;
function strncmp(s1, s2: PChar; count: Integer): Integer;
function strnicmp(s1, s2: PChar; count: Integer): Integer;
function strncpy(dest, source: PChar; count: Integer): PChar;
function FileIsOpened(f: integer): boolean; overload;
function FileIsOpened(var f: file): boolean; overload;
function FileIsOpened(var f: text): boolean; overload;
function isupper(ch: Char): boolean;
function islower(ch: Char): boolean;
function isalpha(ch: Char): boolean;
function isdigit(ch: Char): boolean;
function toupper(ch: Char): Char;
function tolower(ch: Char): Char;
function strcpy(Dest: PChar; const Source: PChar): PChar; assembler;
function strlen(const Str: PChar): integer; assembler;
function strcmp(const Str1, Str2: PChar): Integer; assembler;
function strend(const Str: PChar): PChar; assembler;
function strcat(Dest: PChar; const Source: PChar): PChar;
function uintval(const f: single): unsigned_int;
function fatan(const f: single): single;
function ftan(const f: single): single;
function fasin(const f: single): single;
function fatan2(const y, x: single): Extended;
function fpow(const Base, Exponent: single): single;
function floor(x: single): integer;
function ceil(x: single): integer;
function read_string(var f: file): PChar; overload;
function read_string(f: integer): PChar; overload;
function read_int(var f: file): integer;
function read_float(var f: file): single; overload;
function read_float(f: integer): single; overload;
procedure unlink(name: PChar);
function fopen(var f: file; const FileName: string; const mode: integer): boolean; overload;
function fopen(name: PChar; mode: string): integer; overload;
function fopen(name: PChar; mode: string; var f: file): boolean; overload;
function fopen(name: PChar; mode: string; var t: text): boolean; overload;
function fseek(Handle, Offset, Origin: Integer): Integer;
function C_PChar(const p: pointer; offs: integer): PChar;
procedure FixFileName(name: PChar);

function ReplaceStrAll(Const S, FromStr, ToStr: string): string;


var
  mmxMachine: byte = 0;
  AMD3DNowMachine: byte = 0;

const
  NULLFILE = -1;


implementation

uses
  Windows,
  SysUtils
{$IFDEF FPC}
  ,d_fpc
{$ENDIF},
  Math;

procedure printf(const str: string);
begin
  if Assigned(outproc) then
    outproc(str)
  else if IsConsole then
    write(str);
end;

procedure printf(const Fmt: string; const Args: array of const);
var
  s: string;
begin
  sprintf(s, Fmt, Args);
  printf(s);
end;

procedure fprintf(var f: file; const Fmt: string; const Args: array of const);
var
  s: string;
begin
  sprintf(s, Fmt, Args);
  fprintf(f, s);
end;

procedure fprintf(const f: TFile; const str: string);
begin
  fprintf(f.f, str);
end;

procedure fprintf(const f: TFile; const Fmt: string; const Args: array of const);
begin
  fprintf(f.f, Fmt, Args);
end;

function itoa(i: integer): string;
begin
  sprintf(result, '%d', [i]);
end;

function ftoa(f: integer): string;
begin
  result := FloatToStr(f);
end;


function atoi(const s: string): integer;
var
  code: integer;
  ret2: integer;
begin
  val(s, result, code);
  if code <> 0 then
  begin
    if Pos('0x', s) = 1 then
      val('$' + Copy(s, 3, Length(s) - 2), ret2, code)
    else
      val('$' + s, ret2, code);
    if code = 0 then
      result := ret2
    else
      result := 0;
  end;
end;

function atoi(const s: string; const default: integer): integer; overload;
var
  code: integer;
  ret2: integer;
begin
  val(s, result, code);
  if code <> 0 then
  begin
    if Pos('0x', s) = 1 then
      val('$' + Copy(s, 3, Length(s) - 2), ret2, code)
    else
      val('$' + s, ret2, code);
    if code = 0 then
      result := ret2
    else
      result := default;
  end;
end;

function atoui(const s: string): longword; overload;
var
  code: integer;
  ret2: longword;
begin
  val(s, result, code);
  if code <> 0 then
  begin
    if Pos('0x', s) = 1 then
      val('$' + Copy(s, 3, Length(s) - 2), ret2, code)
    else
      val('$' + s, ret2, code);
    if code = 0 then
      result := ret2
    else
      result := 0;
  end;
end;

function atoui(const s: string; const default: longword): longword; overload;
var
  code: integer;
  ret2: longword;
begin
  val(s, result, code);
  if code <> 0 then
  begin
    if Pos('0x', s) = 1 then
      val('$' + Copy(s, 3, Length(s) - 2), ret2, code)
    else
      val('$' + s, ret2, code);
    if code = 0 then
      result := ret2
    else
      result := default;
  end;
end;

function atof(const s: string): single;
var
  code: integer;
  i: integer;
  str: string;
begin
  val(s, result, code);
  if code <> 0 then
  begin
    str := s;
    for i := 1 to Length(str) do
      if str[i] in ['.', ','] then
        str[i] := DecimalSeparator;
    val(str, result, code);
    if code <> 0 then
      result := 0.0;
  end;
end;

function atof(const s: string; const default: single): single;
var
  code: integer;
  i: integer;
  str: string;
begin
  val(s, result, code);
  if code <> 0 then
  begin
    str := s;
    for i := 1 to Length(str) do
      if str[i] in ['.', ','] then
        str[i] := DecimalSeparator;
    val(str, result, code);
    if code <> 0 then
      result := default;
  end;
end;

procedure memcpy_MMX8(const dst: pointer; const src: pointer; const len: integer); assembler;
asm
  push esi
  push edi

  mov esi, src
  mov edi, dst
  mov ecx, len
  shr ecx, 3  // 8 bytes per iteration

@@loop1:
// Read in source data
  movq  mm1, [esi]
// Non-temporal stores
  movntq [edi], mm1

  add esi, 8
  add edi, 8
  dec ecx
  jnz @@loop1

  emms

  pop edi
  pop esi
end;

procedure memcpy_MMX64(const dst: pointer; const src: pointer; const len: integer); assembler;
asm
  push esi
  push edi

  mov esi, src
  mov edi, dst
  mov ecx, len
  shr ecx, 6    // 64 bytes per iteration

@@loop1:

// Read in source data
  movq mm1, [esi]
  movq mm2, [esi + 8]
  movq mm3, [esi + 16]
  movq mm4, [esi + 24]
  movq mm5, [esi + 32]
  movq mm6, [esi + 40]
  movq mm7, [esi + 48]
  movq mm0, [esi + 56]

// Non-temporal stores
  movntq [edi], mm1
  movntq [edi + 8], mm2
  movntq [edi + 16], mm3
  movntq [edi + 24], mm4
  movntq [edi + 32], mm5
  movntq [edi + 40], mm6
  movntq [edi + 48], mm7
  movntq [edi + 56], mm0

  add esi, 64
  add edi, 64
  dec ecx
  jnz @@loop1

  emms

  pop edi
  pop esi
end;

procedure memcpy_3DNow64(const dst: pointer; const src: pointer; const len: integer); assembler;
asm
  push esi
  push edi

  mov esi, src
  mov edi, dst
  mov ecx, len
  shr ecx, 6    // 64 bytes per iteration

@@loop1:
// Prefetch next loop, non-temporal
  prefetch [esi + 64]
  prefetch [esi + 96]

// Read in source data
  movq mm1, [esi]
  movq mm2, [esi + 8]
  movq mm3, [esi + 16]
  movq mm4, [esi + 24]
  movq mm5, [esi + 32]
  movq mm6, [esi + 40]
  movq mm7, [esi + 48]
  movq mm0, [esi + 56]

// Non-temporal stores
  movntq [edi], mm1
  movntq [edi + 8], mm2
  movntq [edi + 16], mm3
  movntq [edi + 24], mm4
  movntq [edi + 32], mm5
  movntq [edi + 40], mm6
  movntq [edi + 48], mm7
  movntq [edi + 56], mm0

  add esi, 64
  add edi, 64
  dec ecx
  jnz @@loop1

  emms

  pop edi
  pop esi
end;

function memmove(const destination, source: pointer; count: integer): pointer;
begin
  Move(source^, destination^, count);
  result := destination;
end;

function memcpy(const dest0: pointer; const src0: pointer; count0: integer): pointer;
var
  dest: PByte;
  src: PByte;
  count: integer;
begin
  if mmxMachine = 0 then
  begin
    Move(src0^, dest0^, count0);
    result := dest0;
    exit;
  end;

{  if abs(integer(dest0) - integer(src0)) < 8 then
  begin
    printf('memcpy(): FUCK!!');
    exit;
  end;}

  // if copying more than 16 bytes and we can copy 8 byte aligned
  if (count0 > 16) and (((integer(dest0) xor integer(src0)) and 7) = 0) then
  begin
    dest := PByte(dest0);
    src := PByte(src0);

    // copy up to the first 8 byte aligned boundary
    count := integer(dest) and 7;
    Move(src^, dest^, count);
    inc(dest, count);
    inc(src, count);
    count := count0 - count;

   // if there are blocks of 64 bytes
    if count and (not 63) <> 0 then
    begin
      if AMD3DNowMachine <> 0 then
        memcpy_3DNow64(dest, src, count and (not 63))
      else
        memcpy_MMX64(dest, src, count and (not 63));
      inc(src, count and (not 63));
      inc(dest, count and (not 63));
      count := count and 63;
    end;

    // if there are blocks of 8 bytes
    if count and (not 7) <> 0 then
    begin
      memcpy_MMX8(dest, src, count);
      inc(src, count and (not 7));
      inc(dest, count and (not 7));
      count := count and 7;
    end;

    // copy any remaining bytes
    Move(src^, dest^, count);
  end
  else
  begin
    // use the regular one if we cannot copy 8 byte aligned
    Move(src0^, dest0^, count0);
  end;
  result := dest0;
end;

type
  union_8b = record
    case integer of
      1: (bytes: array[0..7] of byte);
      2: (words: array[0..3] of word);
      3: (dwords: array[0..1] of LongWord);
  end;

function memset(const dest0: pointer; const val: integer; const count0: integer): pointer;
var
  data: union_8b;
  pdat: pointer;
  dest: PByte;
  count: integer;
begin
  if mmxMachine = 0 then
  begin
    FillChar(dest0^, count0, val);
    result := dest0;
    exit;
  end;

  dest := PByte(dest0);
  count := count0;

  while (count > 0) and (integer(dest) and 7 <> 0) do
  begin
    dest^ := val;
    inc(dest);
    dec(count);
  end;

  if count = 0 then
  begin
    result := dest0;
    exit;
  end;

  data.bytes[0] := val;
  data.bytes[1] := val;
  data.words[1] := data.words[0];
  data.dwords[1] := data.dwords[0];
  pdat := @data;

  if count >= 64 then
  begin
    asm
      push esi
      push edi

      mov edi, dest
      mov esi, pdat

      mov ecx, count
      // 64 bytes per iteration
      shr ecx, 6
      // Read in source data
      movq mm1, [esi]
      movq mm2, mm1
      movq mm3, mm1
      movq mm4, mm1
      movq mm5, mm1
      movq mm6, mm1
      movq mm7, mm1
      movq mm0, mm1
@@loop1:
      movntq [edi], mm1
      movntq [edi + 8], mm2
      movntq [edi + 16], mm3
      movntq [edi + 24], mm4
      movntq [edi + 32], mm5
      movntq [edi + 40], mm6
      movntq [edi + 48], mm7
      movntq [edi + 56], mm0

      add edi, 64
      dec ecx
      jnz @@loop1

      pop edi
      pop esi
    end;

    inc(dest, count and (not 63));
    count := count and 63;
  end;

  if count >= 8 then
  begin
    asm
      push esi
      push edi

      mov edi, dest
      mov esi, pdat

      mov ecx, count
      // 8 bytes per iteration
      shr ecx, 3
      // Read in source data
      movq mm1, [esi]
@@loop2:
      movntq  [edi], mm1

      add edi, 8
      dec ecx
      jnz @@loop2

      pop edi
      pop esi
    end;
    inc(dest, count and (not 7));
    count := count and 7;
  end;

  while count > 0 do
  begin
    dest^ := val;
    inc(dest);
    dec(count);
  end;

  asm
    emms
  end;

  result := dest0;
end;

function malloc(const size: integer): Pointer;
begin
  if size = 0 then
    result := nil
  else
  begin
    GetMem(result, size);
    memoryusage := memoryusage + size;
  end;
end;

function mallocA(var Size: integer; const Align: integer; var original: pointer): pointer;
begin
  Size := Size + Align;
  result := malloc(Size);
  original := result;
  if result <> nil then
    result := pointer(integer(result) and (1 - Align) + Align);
end;

function mallocz(const size: integer): Pointer;
begin
  result := malloc(size);
  if result <> nil then
    ZeroMemory(result, size);
end;

procedure realloc(var p: pointer; const oldsize, newsize: integer);
begin
  if newsize = 0 then
    memfree(p, oldsize)
  else if newsize <> oldsize then
  begin
    reallocmem(p, newsize);
    memoryusage := memoryusage - oldsize + newsize;
  end;
end;

procedure memfree(var p: pointer; const size: integer);
begin
  if p <> nil then
  begin
    FreeMem(p, size);
    p := nil;
    memoryusage := memoryusage - size;
  end;
end;

function IntToStrZfill(const z: integer; const x: integer): string;
var
  i: integer;
  len: integer;
begin
  result := itoa(x);
  len := Length(result);
  for i := len + 1 to z do
    result := '0' + result;
end;

function intval(const b: boolean): integer;
begin
  if b then
    result := 1
  else
    result := 0;
end;

function decidef(const condition: boolean;
  const iftrue: single; const iffalse: single): single;
begin
  if condition then
    result := iftrue
  else
    result := iffalse;
end;

function pDiff(const p1, p2: pointer; const size: integer): integer;
begin
  result := (Integer(p1) - Integer(p2)) div size;
end;

////////////////////////////////////////////////////////////////////////////////
// TStream
constructor TStream.Create;
begin
  FIOResult := 0;
end;

function TStream.IOResult: integer;
begin
  result := FIOResult;
  FIOResult := 0;
end;

////////////////////////////////////////////////////////////////////////////////
// TMemoryStream
constructor TMemoryStream.Create;
begin
  Inherited Create;
  FSize := 0;
  FPosition := 0;
  FMemory := nil;
end;

destructor TMemoryStream.Destroy;
begin
  Resize(0);
  Inherited Destroy;
end;

procedure TMemoryStream.Resize(newsize: integer);
begin
  if FSize <> newsize then
  begin
    realloc(FMemory, FSize, newsize);
    FSize := newsize;
    if FPosition > FSize then
      FPosition := FSize;
  end;
end;

function TMemoryStream.Read(var Buffer; Count: Longint): Longint;
begin
  if Count + FPosition > FSize then
    result := FSize - FPosition
  else
    result := Count;

  memcpy(@Buffer, pointer(integer(FMemory) + FPosition), result);
  FPosition := FPosition + result;
end;

function TMemoryStream.Write(const Buffer; Count: Longint): Longint;
begin
  if Count + FPosition > FSize then
    resize(Count + FPosition);
  memcpy(pointer(integer(FMemory) + FPosition), @Buffer, Count);
  FPosition := FPosition + Count;
  result := Count;
end;

function TMemoryStream.Seek(Offset: Longint; Origin: Word): Longint;
begin
  case Origin of
    sFromBeginning:
      result := Offset;
    sFromCurrent:
      result := FPosition + Offset;
    sFromEnd:
      result := FPosition - Offset;
  else
    result := 0;
  end;
  FPosition := result;
end;

function TMemoryStream.Size: Longint;
begin
  result := FSize;
end;

function TMemoryStream.Position: integer;
begin
  result := FPosition;
end;

////////////////////////////////////////////////////////////////////////////////
// TFile
// File class
constructor TFile.Create(const FileName: string; const mode: integer);
begin
  Inherited Create;
  OnBeginBusy := nil;
  OnEndBusy := nil;

  fopen(f, FileName, mode);
end;

destructor TFile.Destroy;
begin
  close(f);
  Inherited;
end;

function TFile.Read(var Buffer; Count: Longint): Longint;
begin
  if Assigned(OnBeginBusy) then OnBeginBusy;

  {$I-}
  BlockRead(f, Buffer, Count, result);
  {$I+}
  FIOResult := IOResult;

  if Assigned(OnEndBusy) then OnEndBusy;
end;

function TFile.Write(const Buffer; Count: Longint): Longint;
begin
  if Assigned(OnBeginBusy) then OnBeginBusy;

  {$I-}
  BlockWrite(f, Buffer, Count, result);
  {$I+}
  FIOResult := IOResult;

  if Assigned(OnEndBusy) then OnEndBusy;
end;

function TFile.Seek(Offset: Longint; Origin: Word): Longint;
begin
  case Origin of
    sFromBeginning:
      result := Offset;
    sFromCurrent:
      result := FilePos(f) + Offset;
    sFromEnd:
      result := FileSize(f) - Offset;
  else
    result := 0;
  end;
  {$I-}
  system.Seek(f, result);
  {$I+}
  FIOResult := IOResult;
end;

function TFile.Size: Longint;
begin
  {$I-}
  result := FileSize(f);
  {$I+}
  FIOResult := IOResult;
end;

function TFile.Position: integer;
begin
  {$I-}
  result := FilePos(f);
  {$I+}
  FIOResult := IOResult;
end;

////////////////////////////////////////////////////////////////////////////////
// TCachedFile
// Cache read file class
constructor TCachedFile.Create(const FileName: string; mode: word; ABufSize: integer = $FFFF);
begin
  fInitialized := false;
  Inherited Create(FileName, mode);
  if ABufSize > Size then
    fBufSize := Size
  else
    fBufSize := ABufSize;
  fBuffer := malloc(fBufSize);
  fPosition := 0;
  ResetBuffer;
  fSize := Inherited Size;
  fInitialized := true;
end;

procedure TCachedFile.ResetBuffer;
begin
  fBufferStart := -1;
  fBufferEnd := -1;
end;

destructor TCachedFile.Destroy;
begin
  memfree(fBuffer, fBufSize);
  Inherited;
end;

function TCachedFile.Read(var Buffer; Count: Longint): Longint;
var
  x: Longint;
begin
// Buffer hit
  if (fPosition >= fBufferStart) and (fPosition + Count <= fBufferEnd) then
  begin
    x := LongInt(fBuffer) + fPosition - fBufferStart;
    Move(Pointer(x)^, Buffer, Count);
    fPosition := fPosition + Count;
    result := Count;
  end
// Non Buffer hit, cache buffer
  else if Count <= fBufSize then
  begin
    fPosition := Inherited Seek(fPosition, sFromBeginning);
    x := Inherited Read(fBuffer^, fBufSize);
    if x < Count then
      result := x
    else
      result := Count;
    Move(fBuffer^, Buffer, Count);
    fBufferStart := fPosition;
    fBufferEnd := fPosition + x;
    fPosition := fPosition + result;
  end
// Keep old buffer
  else
  begin
    fPosition := Inherited Seek(fPosition, sFromBeginning);
    result := Inherited Read(Buffer, Count);
    fPosition := fPosition + result;
  end;
end;

function TCachedFile.Write(const Buffer; Count: Longint): Longint;
begin
  fPosition := Inherited Seek(fPosition, sFromBeginning);
  result := Inherited Write(Buffer, Count);
  fPosition := fPosition + result;
  if fSize < fPosition then
    fSize := fPosition;
end;

function TCachedFile.Seek(Offset: Longint; Origin: Word): Longint;
begin
  if fInitialized then
  begin
    case Origin of
      sFromBeginning: fPosition := Offset;
      sFromCurrent: Inc(fPosition, Offset);
      sFromEnd: fPosition := fSize + Offset;
    end;
    result := fPosition;
  end
  else
    result := Inherited Seek(Offset, Origin);
end;

procedure TCachedFile.SetSize(NewSize: Longint);
begin
  Inherited;
  fSize := NewSize;
end;

function TCachedFile.Position: integer;
begin
  result := FPosition;
end;

////////////////////////////////////////////////////////////////////////////////
// TDNumberList
constructor TDNumberList.Create;
begin
  fList := nil;
  fNumItems := 0;
end;

destructor TDNumberList.Destroy;
begin
  Clear;
end;

function TDNumberList.Get(Index: Integer): integer;
begin
  if (Index < 0) or (Index >= fNumItems) then
    result := 0
  else
    result := fList[Index];
end;

procedure TDNumberList.Put(Index: Integer; const value: integer);
begin
  fList[Index] := value;
end;

function TDNumberList.Add(const value: integer): integer;
begin
  realloc(pointer(fList), fNumItems * SizeOf(integer), (fNumItems + 1) * SizeOf(integer));
  Put(fNumItems, value);
  result := fNumItems;
  inc(fNumItems);
end;

procedure TDNumberList.Add(const nlist: TDNumberList);
var
  i: integer;
begin
  for i := 0 to nlist.Count - 1 do
    Add(nlist[i]);
end;

function TDNumberList.Delete(const Index: integer): boolean;
var
  i: integer;
begin
  if (Index < 0) or (Index >= fNumItems) then
  begin
    result := false;
    exit;
  end;

  for i := Index + 1 to fNumItems - 1 do
    fList[i - 1] := fList[i];

  realloc(pointer(fList), fNumItems * SizeOf(integer), (fNumItems - 1) * SizeOf(integer));
  dec(fNumItems);

  result := true;
end;

function TDNumberList.IndexOf(const value: integer): integer;
var
  i: integer;
begin
  for i := 0 to fNumItems - 1 do
    if fList[i] = value then
    begin
      result := i;
      exit;
    end;
  result := -1;
end;

procedure TDNumberList.Clear;
begin
  realloc(pointer(fList), fNumItems * SizeOf(integer), 0);
  fList := nil;
  fNumItems := 0;
end;


////////////////////////////////////////////////////////////////////////////////
// TDTextList
constructor TDTextList.Create;
begin
  fList := nil;
  fNumItems := 0;
end;

destructor TDTextList.Destroy;
begin
  Clear;
end;

function TDTextList.Get(Index: Integer): string;
begin
  if (Index < 0) or (Index >= fNumItems) then
    result := ''
  else
    result := fList[Index];
end;

procedure TDTextList.Put(Index: Integer; const value: string);
begin
  fList[Index] := value;
end;

procedure TDTextList.Add(const value: string);
begin
  realloc(pointer(fList), fNumItems * 256, (fNumItems + 1) * 256);
  Put(fNumItems, value);
  inc(fNumItems);
end;

procedure TDTextList.Add(const nlist: TDTextList);
var
  i: integer;
begin
  for i := 0 to nlist.Count - 1 do
    Add(nlist[i]);
end;

function TDTextList.Delete(const Index: integer): boolean;
var
  i: integer;
begin
  if (Index < 0) or (Index >= fNumItems) then
  begin
    result := false;
    exit;
  end;

  for i := Index + 1 to fNumItems - 1 do
    fList[i - 1] := fList[i];

  realloc(pointer(fList), fNumItems * 256, (fNumItems - 1) * 256);
  dec(fNumItems);

  result := true;
end;

function TDTextList.IndexOf(const value: string): integer;
var
  i: integer;
begin
  for i := 0 to fNumItems - 1 do
    if fList[i] = value then
    begin
      result := i;
      exit;
    end;
  result := -1;
end;

procedure TDTextList.Clear;
begin
  realloc(pointer(fList), fNumItems * 256, 0);
  fList := nil;
  fNumItems := 0;
end;

////////////////////////////////////////////////////////////////////////////////
// TDStrings
function TDStrings.Add(const S: string): Integer;
begin
  result := GetCount;
  Insert(result, S);
end;

function TDStrings.Add(const Fmt: string; const Args: array of const): integer;
var
  str: string;
begin
  sprintf(str, Fmt, Args);
  result := Add(str);
end;

function TDStrings.AddObject(const S: string; AObject: TObject): Integer;
begin
  result := Add(S);
  PutObject(result, AObject);
end;

procedure TDStrings.Append(const S: string);
begin
  Add(S);
end;

procedure TDStrings.AddStrings(Strings: TDStrings);
var
  I: Integer;
begin
  for I := 0 to Strings.Count - 1 do
    AddObject(Strings[I], Strings.Objects[I]);
end;

function TDStrings.Equals(Strings: TDStrings): Boolean;
var
  I, iCount: Integer;
begin
  result := false;
  iCount := GetCount;
  if iCount <> Strings.GetCount then Exit;
  for I := 0 to iCount - 1 do if Get(I) <> Strings.Get(I) then Exit;
  result := true;
end;

procedure TDStrings.Exchange(Index1, Index2: Integer);
var
  TempObject: TObject;
  TempString: string;
begin
  TempString := Strings[Index1];
  TempObject := Objects[Index1];
  Strings[Index1] := Strings[Index2];
  Objects[Index1] := Objects[Index2];
  Strings[Index2] := TempString;
  Objects[Index2] := TempObject;
end;

function TDStrings.GetCapacity: Integer;
begin  // descendants may optionally override/replace this default implementation
  result := Count;
end;

function TDStrings.GetCommaText: string;
var
  S: string;
  P: PChar;
  I, iCount: Integer;
begin
  iCount := GetCount;
  if (iCount = 1) and (Get(0) = '') then
    result := '""'
  else
  begin
    result := '';
    for I := 0 to iCount - 1 do
    begin
      S := Get(I);
      P := PChar(S);
      while not (P^ in [#0..' ','"',',']) do P := CharNext(P);
      if (P^ <> #0) then S := AnsiQuotedStr(S, '"');
      result := result + S + ',';
    end;
    System.Delete(result, Length(result), 1);
  end;
end;

function TDStrings.GetName(Index: Integer): string;
var
  P: Integer;
begin
  result := Get(Index);
  P := AnsiPos('=', result);
  if P <> 0 then
    SetLength(result, P-1)
  else
    SetLength(result, 0);
end;

function TDStrings.GetObject(Index: Integer): TObject;
begin
  result := nil;
end;

function TDStrings.GetText: PChar;
begin
  result := StrNew(PChar(GetTextStr));
end;

function TDStrings.GetTextStr: string;
var
  I, L, Size, iCount: Integer;
  P: PChar;
  S: string;
begin
  iCount := GetCount;
  Size := 0;
  for I := 0 to iCount - 1 do Inc(Size, Length(Get(I)) + 2);
  SetString(result, nil, Size);
  P := Pointer(result);
  for I := 0 to iCount - 1 do
  begin
    S := Get(I);
    L := Length(S);
    if L <> 0 then
    begin
      System.Move(Pointer(S)^, P^, L);
      Inc(P, L);
    end;
    P^ := #13;
    Inc(P);
    P^ := #10;
    Inc(P);
  end;
end;

function TDStrings.GetValue(const Name: string): string;
var
  I: Integer;
begin
  I := IndexOfName(Name);
  if I >= 0 then
    result := Copy(Get(I), Length(Name) + 2, MaxInt) else
    result := '';
end;

function TDStrings.GetValueIdx(const idx: integer): string;
var
  tmp: string;
begin
  splitstring(Get(idx), tmp, result);
end;

function TDStrings.IndexOf(const S: string): Integer;
begin
  for result := 0 to GetCount - 1 do
    if AnsiCompareText(Get(result), S) = 0 then Exit;
  result := -1;
end;

function TDStrings.IndexOfName(const Name: string): Integer;
var
  P: Integer;
  S: string;
begin
  for result := 0 to GetCount - 1 do
  begin
    S := Get(result);
    P := AnsiPos('=', S);
    if (P <> 0) and (AnsiCompareText(Copy(S, 1, P - 1), Name) = 0) then Exit;
  end;
  result := -1;
end;

function TDStrings.IndexOfObject(AObject: TObject): Integer;
begin
  for result := 0 to GetCount - 1 do
    if GetObject(result) = AObject then Exit;
  result := -1;
end;

procedure TDStrings.InsertObject(Index: Integer; const S: string;
  AObject: TObject);
begin
  Insert(Index, S);
  PutObject(Index, AObject);
end;

function TDStrings.LoadFromFile(const FileName: string): boolean;
var
  f: file;
  Size: Integer;
  S: string;
begin
  if fopen(f, FileName, fOpenReadOnly) then
  begin
    {$I-}
    Size := FileSize(f);
    SetString(S, nil, Size);
    BlockRead(f, Pointer(S)^, Size);
    SetTextStr(S);
    close(f);
    {$I+}
    result := IOresult = 0;
  end
  else
    result := false;
end;

function TDStrings.LoadFromStream(const strm: TStream): boolean;
var
  Size: Integer;
  A: PByteArray;
begin
  {$I-}
  strm.Seek(0, sFromBeginning);
  Size := strm.Size;
  A := malloc(Size);
  strm.Read(A^, Size);
  SetByteStr(A, Size);
  memfree(pointer(A), Size);
  {$I+}
  result := IOresult = 0;
end;

procedure TDStrings.Move(CurIndex, NewIndex: Integer);
var
  TempObject: TObject;
  TempString: string;
begin
  if CurIndex <> NewIndex then
  begin
    TempString := Get(CurIndex);
    TempObject := GetObject(CurIndex);
    Delete(CurIndex);
    InsertObject(NewIndex, TempString, TempObject);
  end;
end;

procedure TDStrings.Put(Index: Integer; const S: string);
var
  TempObject: TObject;
begin
  TempObject := GetObject(Index);
  Delete(Index);
  InsertObject(Index, S, TempObject);
end;

procedure TDStrings.PutObject(Index: Integer; AObject: TObject);
begin
end;

function TDStrings.SaveToFile(const FileName: string): boolean;
var
  f: file;
  S: string;
begin
  if fopen(f, FileName, fCreate) then
  begin
    {$I-}
    S := GetTextStr;
    BlockWrite(f, Pointer(S)^, Length(S));
    close(f);
    {$I+}
    result := IOresult = 0;
  end
  else
    result := false;
end;

procedure TDStrings.SetCapacity(NewCapacity: Integer);
begin
  // do nothing - descendants may optionally implement this method
end;

procedure TDStrings.SetCommaText(const Value: string);
var
  P, P1: PChar;
  S: string;
begin
  Clear;
  P := PChar(Value);
  while P^ in [#1..' '] do P := CharNext(P);
  while P^ <> #0 do
  begin
    if P^ = '"' then
      S := AnsiExtractQuotedStr(P, '"')
    else
    begin
      P1 := P;
      while (P^ > ' ') and (P^ <> ',') do P := CharNext(P);
      SetString(S, P1, P - P1);
    end;
    Add(S);
    while P^ in [#1..' '] do P := CharNext(P);
    if P^ = ',' then
      repeat
        P := CharNext(P);
      until not (P^ in [#1..' ']);
  end;
end;

procedure TDStrings.SetText(Text: PChar);
begin
  SetTextStr(Text);
end;

procedure TDStrings.SetTextStr(const Value: string);
var
  P, Start: PChar;
  S: string;
begin
  Clear;
  P := Pointer(Value);
  if P <> nil then
    while P^ <> #0 do
    begin
      Start := P;
      while not (P^ in [#0, #10, #13]) do Inc(P);
      SetString(S, Start, P - Start);
      Add(S);
      if P^ = #13 then Inc(P);
      if P^ = #10 then Inc(P);
    end;
end;

procedure TDStrings.SetByteStr(const A: PByteArray; const Size: integer);
var
  P, Start: PChar;
  S: string;
begin
  Clear;
  P := PChar(@A[0]);
  if P <> nil then
    while (P^ <> #0) and (integer(P) <> integer(@A[Size])) do
    begin
      Start := P;
      while (not (P^ in [#0, #10, #13])) and (integer(P) <> integer(@A[Size])) do Inc(P);
      SetString(S, Start, P - Start);
      Add(S);
      if P^ = #13 then Inc(P);
      if P^ = #10 then Inc(P);
    end;
end;


procedure TDStrings.SetValue(const Name, Value: string);
var
  I: Integer;
begin
  I := IndexOfName(Name);
  if Value <> '' then
  begin
    if I < 0 then I := Add('');
    Put(I, Name + '=' + Value);
  end else
  begin
    if I >= 0 then Delete(I);
  end;
end;

////////////////////////////////////////////////////////////////////////////////
// TStringList
destructor TDStringList.Destroy;
begin
  inherited Destroy;
  if FCount <> 0 then Finalize(FList[0], FCount);
  FCount := 0;
  SetCapacity(0);
end;

function TDStringList.Add(const S: string): Integer;
begin
  result := FCount;
  InsertItem(result, S);
end;

procedure TDStringList.Clear;
begin
  if FCount <> 0 then
  begin
    Finalize(FList[0], FCount);
    FCount := 0;
    SetCapacity(0);
  end;
end;

procedure TDStringList.Delete(Index: Integer);
begin
  if (Index >= 0) and (Index < FCount) then
  begin
    Finalize(FList[Index]);
    Dec(FCount);
    if Index < FCount then
      System.Move(FList[Index + 1], FList[Index],
        (FCount - Index) * SizeOf(TStringItem));
  end;
end;

procedure TDStringList.Exchange(Index1, Index2: Integer);
begin
  if (Index1 < 0) or (Index1 >= FCount) then exit;
  if (Index2 < 0) or (Index2 >= FCount) then exit;
  ExchangeItems(Index1, Index2);
end;

procedure TDStringList.ExchangeItems(Index1, Index2: Integer);
var
  Temp: Integer;
  Item1, Item2: PStringItem;
begin
  Item1 := @FList[Index1];
  Item2 := @FList[Index2];
  Temp := Integer(Item1.FString);
  Integer(Item1.FString) := Integer(Item2.FString);
  Integer(Item2.FString) := Temp;
  Temp := Integer(Item1.FObject);
  Integer(Item1.FObject) := Integer(Item2.FObject);
  Integer(Item2.FObject) := Temp;
end;

function TDStringList.Get(Index: Integer): string;
begin
  if (Index >= 0) and (Index < FCount) then
    result := FList[Index].FString
  else
    result := '';
end;

function TDStringList.GetCapacity: Integer;
begin
  result := FCapacity;
end;

function TDStringList.GetCount: Integer;
begin
  result := FCount;
end;

function TDStringList.GetObject(Index: Integer): TObject;
begin
  if (Index >= 0) and (Index < FCount) then
    result := FList[Index].FObject
  else
    result := nil;
end;

procedure TDStringList.Grow;
var
  Delta: Integer;
begin
  if FCapacity > 64 then Delta := FCapacity div 4 else
    if FCapacity > 8 then Delta := 16 else
      Delta := 4;
  SetCapacity(FCapacity + Delta);
end;

procedure TDStringList.Insert(Index: Integer; const S: string);
begin
  if (Index >= 0) and (Index <= FCount) then
    InsertItem(Index, S);
end;

procedure TDStringList.InsertItem(Index: Integer; const S: string);
begin
  if FCount = FCapacity then Grow;
  if Index < FCount then
    System.Move(FList[Index], FList[Index + 1],
      (FCount - Index) * SizeOf(TStringItem));
  with FList[Index] do
  begin
    Pointer(FString) := nil;
    FObject := nil;
    FString := S;
  end;
  Inc(FCount);
end;

procedure TDStringList.Put(Index: Integer; const S: string);
begin
  if (Index > 0) and (Index < FCount) then
    FList[Index].FString := S;
end;

procedure TDStringList.PutObject(Index: Integer; AObject: TObject);
begin
  if (Index >= 0) and (Index < FCount) then
    FList[Index].FObject := AObject;
end;

procedure TDStringList.SetCapacity(NewCapacity: Integer);
begin
  realloc(pointer(FList), FCapacity * SizeOf(TStringItem), NewCapacity * SizeOf(TStringItem));
  FCapacity := NewCapacity;
end;

////////////////////////////////////////////////////////////////////////////////

function getenv(const env: string): string;
var
  buf: array[0..255] of char;
begin
  ZeroMemory(@buf, SizeOf(buf));
  GetEnvironmentVariable(PChar(env), buf, 255);
  result := Trim(StringVal(buf));
end;

function fexists(const filename: string): boolean;
begin
  result := FileExists(filename);
end;

function fexpand(const filename: string): string;
begin
  result := ExpandFileName(filename);
end;

procedure fdelete(const filename: string);
begin
  if fexists(filename) then
    DeleteFile(filename);
end;

function fext(const filename: string): string;
begin
  result := ExtractFileExt(filename);
end;

function fname(const filename: string): string;
begin
  result := ExtractFileName(filename);
end;

function fmask(const mask: string): string;
begin
  result := mask;
  if result = '' then
    result := '*.*';
end;

function findfile(const mask: string): string;
var
  sr: TSearchRec;
  mask1: string;
begin
  mask1 := fmask(mask);
  if FindFirst(mask1, faAnyFile, sr) = 0 then
  begin
    result := sr.Name;
    FindClose(sr);
  end
  else
    result := '';
end;

function findfiles(const mask: string): TDStringList;
var
  sr: TSearchRec;
  mask1: string;
begin
  result := TDStringList.Create;
  mask1 := fmask(mask);
  if FindFirst(mask1, faAnyFile, sr) = 0 then
  begin
    result.Add(sr.Name);
    while FindNext(sr) = 0 do
      result.Add(sr.Name);
    FindClose(sr);
  end;
end;


function tan(const x: extended): extended;
var
  a: single;
  b: single;
begin
  b := cos(x);
  if b <> 0 then
  begin
    a := sin(x);
    result := a / b;
  end
  else
    result := 0.0;
end;

function strupper(const S: string): string;
var
  Ch: Char;
  L: Integer;
  Source, Dest: PChar;
begin
  L := Length(S);
  SetLength(result, L);
  Source := Pointer(S);
  Dest := Pointer(result);
  while L <> 0 do
  begin
    Ch := Source^;
    if (Ch >= 'a') and (Ch <= 'z') then Dec(Ch, 32);
    Dest^ := Ch;
    Inc(Source);
    Inc(Dest);
    Dec(L);
  end;
end;

function strlower(const S: string): string;
var
  Ch: Char;
  L: Integer;
  Source, Dest: PChar;
begin
  L := Length(S);
  SetLength(result, L);
  Source := Pointer(S);
  Dest := Pointer(result);
  while L <> 0 do
  begin
    Ch := Source^;
    if (Ch >= 'A') and (Ch <= 'Z') then Inc(Ch, 32);
    Dest^ := Ch;
    Inc(Source);
    Inc(Dest);
    Dec(L);
  end;
end;

function toupper(ch: Char): Char;
asm
{ ->    AL      Character       }
{ <-    AL      result          }

  cmp al, 'a'
  jb  @@exit
  cmp al, 'z'
  ja  @@exit
  sub al, 'a' - 'A'
@@exit:
end;

function tolower(ch: Char): Char;
asm
{ ->    AL      Character       }
{ <-    AL      result          }

  cmp al, 'A'
  jb  @@exit
  cmp al, 'Z'
  ja  @@exit
  sub al, 'A' - 'a'
@@exit:
end;

function strremovespaces(const s: string): string;
var
  i: integer;
begin
  result := '';
  for i := 1 to Length(s) do
    if s[i] <> ' ' then
      result := result + s[i];
end;

function _SHL(const x: integer; const bits: integer): integer; assembler;
asm
  mov ecx, edx
  sal eax, cl
end;

function _SHLW(const x: LongWord; const bits: LongWord): LongWord;
begin
  result := x shl bits;
end;

function _SHR(const x: integer; const bits: integer): integer; assembler;
asm
  mov ecx, edx
  sar eax, cl
end;

function _SHR1(const x: integer): integer; assembler;
asm
  sar eax, 1
end;

function _SHR2(const x: integer): integer; assembler;
asm
  sar eax, 2
end;

function _SHR3(const x: integer): integer; assembler;
asm
  sar eax, 3
end;

function _SHR4(const x: integer): integer; assembler;
asm
  sar eax, 4
end;

function _SHR7(const x: integer): integer; assembler;
asm
  sar eax, 7
end;

function _SHR8(const x: integer): integer; assembler;
asm
  sar eax, 8
end;

function _SHR14(const x: integer): integer; assembler;
asm
  sar eax, 14
end;

function _SHRW(const x: LongWord; const bits: LongWord): LongWord;
begin
  result := x shr bits;
end;

function StringVal(const Str: PChar): string;
begin
  sprintf(result, '%s', [Str]);
end;

procedure ZeroMemory(const dest0: pointer; const count0: integer);
var
  data: union_8b;
  pdat: pointer;
  dest: PByte;
  count: integer;
begin
  if mmxMachine = 0 then
  begin
    FillChar(dest0^, count0, 0);
    exit;
  end;

  dest := PByte(dest0);
  count := count0;

  while (count > 0) and (integer(dest) and 7 <> 0) do
  begin
    dest^ := 0;
    inc(dest);
    dec(count);
  end;

  if count = 0 then
  begin
    exit;
  end;

  data.dwords[0] := 0;
  data.dwords[1] := 0;
  pdat := @data;

  if count >= 64 then
  begin
    asm
      push esi
      push edi

      mov edi, dest
      mov esi, pdat

      mov ecx, count
      // 64 bytes per iteration
      shr ecx, 6
      // Read in source data
      movq mm1, [esi]
      movq mm2, mm1
      movq mm3, mm1
      movq mm4, mm1
      movq mm5, mm1
      movq mm6, mm1
      movq mm7, mm1
      movq mm0, mm1
@@loop1:
      // Non-temporal stores
      movntq [edi], mm1
      movntq [edi + 8], mm2
      movntq [edi + 16], mm3
      movntq [edi + 24], mm4
      movntq [edi + 32], mm5
      movntq [edi + 40], mm6
      movntq [edi + 48], mm7
      movntq [edi + 56], mm0

      add edi, 64
      dec ecx
      jnz @@loop1

      pop edi
      pop esi
    end;

    inc(dest, count and (not 63));
    count := count and 63;
  end;

  if count >= 8 then
  begin
    asm
      push esi
      push edi

      mov edi, dest
      mov esi, pdat

      mov ecx, count
      // 8 bytes per iteration
      shr ecx, 3
      // Read in source data
      movq mm1, [esi]
@@loop2:
      // Non-temporal stores
      movntq  [edi], mm1

      add edi, 8
      dec ecx
      jnz @@loop2

      pop edi
      pop esi
    end;
    inc(dest, count and (not 7));
    count := count and 7;
  end;

  while count > 0 do
  begin
    dest^ := 0;
    inc(dest);
    dec(count);
  end;

  asm
    emms
  end;

end;

function fopen(var f: file; const FileName: string; const mode: integer): boolean;
begin
  assign(f, FileName);
  {$I-}
  if mode = fCreate then
  begin
    FileMode := 2;
    rewrite(f, 1);
  end
  else if mode = fOpenReadOnly then
  begin
    FileMode := 0;
    reset(f, 1);
  end
  else if mode = fOpenReadWrite then
  begin
    FileMode := 2;
    reset(f, 1);
  end
  else
  begin
    result := false;
    exit;
  end;
  {$I+}
  result := IOresult = 0;
end;

function fsize(const FileName: string): integer;
var
  f: file;
begin
  if fopen(f, FileName, fOpenReadOnly) then
  begin
  {$I-}
    result := FileSize(f);
    close(f);
  {$I+}
  end
  else
    result := 0;
end;

function fshortname(const FileName: string): string;
var
  i: integer;
begin
  result := '';
  for i := Length(FileName) downto 1 do
  begin
    if FileName[i] in ['\', '/'] then
      break;
    result := FileName[i] + result;
  end;
end;

function strtrim(const S: string): string;
var
  I, L: Integer;
begin
  L := Length(S);
  I := 1;
  while (I <= L) and (S[I] <= ' ') do Inc(I);
  if I > L then result := '' else
  begin
    while S[L] <= ' ' do Dec(L);
    result := Copy(S, I, L - I + 1);
  end;
end;

function capitalizedstring(const S: string; const splitter: char = ' '): string;
var
  i: integer;
  c: string;
begin
  if S = '' then
  begin
    result := '';
    exit;
  end;

  result := strlower(S);
  result[1] := toupper(result[1]);
  c := tolower(splitter);
  for i := 2 to Length(result) do
  begin
    if result[i - 1] = c then
      result[i] := toupper(result[i])
  end;
end;

procedure splitstring(const inp: string; var out1, out2: string; const splitter: string = ' ');
var
  p: integer;
begin
  p := Pos(splitter, inp);
  if p = 0 then
  begin
    out1 := inp;
    out2 := '';
  end
  else
  begin
    out1 := strtrim(Copy(inp, 1, p - 1));
    out2 := strtrim(Copy(inp, p + 1, Length(inp) - p));
  end;
end;

procedure splitstring(const inp: string; var out1, out2: string; const splitters: charset_t);
var
  i: integer;
  p: integer;
  inp1: string;
begin
  inp1 := inp;
  for i := 1 to Length(inp1) do
    if inp1[i] in splitters then
      inp1[i] := ' ';
  p := Pos(' ', inp1);
  if p = 0 then
  begin
    out1 := inp1;
    out2 := '';
  end
  else
  begin
    out1 := strtrim(Copy(inp1, 1, p - 1));
    out2 := strtrim(Copy(inp1, p + 1, Length(inp) - p));
  end;
end;

function firstword(const inp: string; const splitter: string = ' '): string;
var
  tmp: string;
begin
  splitstring(inp, result, tmp, splitter);
end;

function firstword(const inp: string; const splitters: charset_t): string; overload;
var
  tmp: string;
begin
  splitstring(inp, result, tmp, splitters);
end;

function secondword(const inp: string; const splitter: string = ' '): string;
var
  tmp: string;
begin
  splitstring(inp, tmp, result, splitter);
end;

function secondword(const inp: string; const splitters: charset_t): string; overload;
var
  tmp: string;
begin
  splitstring(inp, tmp, result, splitters);
end;

function lastword(const inp: string; const splitter: string = ' '): string;
var
  i: integer;
begin
  result := '';
  i := length(inp);
  while i > 0 do
  begin
    if inp[i] = splitter then
      exit
    else
    begin
      result := inp[i] + result;
      dec(i);
    end;
  end;
end;

function lastword(const inp: string; const splitters: charset_t): string; overload;
var
  i: integer;
begin
  result := '';
  i := length(inp);
  while i > 0 do
  begin
    if inp[i] in splitters then
      exit
    else
    begin
      result := inp[i] + result;
      dec(i);
    end;
  end;
end;

procedure FreeAndNil(var Obj);
var
  Temp: TObject;
begin
  Temp := TObject(Obj);
  Pointer(Obj) := nil;
  Temp.Free;
end;

function StrLCopy(Dest: PChar; const Source: PChar; MaxLen: Cardinal): PChar; assembler;
asm
        PUSH    EDI
        PUSH    ESI
        PUSH    EBX
        MOV     ESI,EAX
        MOV     EDI,EDX
        MOV     EBX,ECX
        XOR     AL,AL
        TEST    ECX,ECX
        JZ      @@1
        REPNE   SCASB
        JNE     @@1
        INC     ECX
@@1:    SUB     EBX,ECX
        MOV     EDI,ESI
        MOV     ESI,EDX
        MOV     EDX,EDI
        MOV     ECX,EBX
        SHR     ECX,2
        REP     MOVSD
        MOV     ECX,EBX
        AND     ECX,3
        REP     MOVSB
        STOSB
        MOV     EAX,EDX
        POP     EBX
        POP     ESI
        POP     EDI
end;

function fabs(const f: float): float;
{var
  tmp: integer;
begin
  tmp := PInteger(@f)^;
  tmp := tmp and $7FFFFFFF;
  result := Pfloat(@tmp)^;
end;}
begin
  if f >= 0 then
    result := f
  else
    result := -f;
end;

procedure MakeDir(const dir: string);
begin
  CreateDir(dir);
end;

function PascalText(src: PChar): string;
var
  prev: char;
begin
  result := '';
  if src^ = #0 then
    exit;
  repeat
    prev := src^;
    inc(src);
    if (src^ = #10) and (prev <> #13) then
      result := result + prev + #13#10
    else if not (prev in [#10, #13]) then
      result := result + prev;
  until src^ = #0;
end;

procedure CopyFile(const sname, dname: string);
var
  FromF, ToF: file;
  NumRead, NumWritten: Integer;
  Buf: array[1..8192] of Char;
begin
  if fexists(sname) then
  begin
    AssignFile(FromF, sname);
    Reset(FromF, 1);
    AssignFile(ToF, dname);
    Rewrite(ToF, 1);
    repeat
      BlockRead(FromF, Buf, SizeOf(Buf), NumRead);
      BlockWrite(ToF, Buf, NumRead, NumWritten);
    until (NumRead = 0) or (NumWritten <> NumRead);
    CloseFile(FromF);
    CloseFile(ToF);
  end
  else
  begin
    AssignFile(ToF, dname);
    Rewrite(ToF, 1);
    CloseFile(ToF);
  end;
end;

function IsIntegerInRange(const test, f1, f2: integer): boolean;
begin
  result := (test >= f1) and (test <= f2);
end;

function IsFloatInRange(const test, f1, f2: float): boolean;
begin
  result := (test >= f1) and (test <= f2);
end;

procedure sprintf(s: PChar; const Fmt: PChar);
begin
  strcpy(s, Fmt);
end;

procedure sprintf(s: PChar; const Fmt: PChar; const Args: array of const);
var
  i: Integer;
begin
  if high(Args) - low(Args) = -1 then
    sprintf(s, Fmt)
  else
    StrFmt(s, Fmt, Args);
  for i := 0 to Length(s) do
    if s[i] = ',' then
      s[i] := '.';
end;

procedure sprintf(var s: string; const Fmt: PChar); overload;
begin
  s := Format(Fmt, []);
end;

procedure sprintf(var s: string; const Fmt: PChar; const Args: array of const);
begin
  s := Format(Fmt, Args);
end;

procedure sprintf(s: PChar; const Fmt: string);
begin
  sprintf(s, PChar(Fmt));
end;

procedure sprintf(s: PChar; const Fmt: string; const Args: array of const); overload;
begin
  sprintf(s, PChar(Fmt), Args);
end;

procedure sprintf(var s: string; const Fmt: string); overload;
begin
  s := Format(Fmt, []);
end;

procedure sprintf(var s: string; const Fmt: string; const Args: array of const); overload;
begin
  s := Format(Fmt, Args);
end;

procedure fprintf(var f: text; const Fmt: PChar);
begin
  fprintf(f, Fmt, []);
end;

procedure fprintf(var f: file; const Fmt: PChar);
begin
  fprintf(f, Fmt, []);
end;

procedure fprintf(f: integer; const Fmt: PChar);
begin
  fprintf(f, Fmt, []);
end;

procedure fprintf(var f: text; const Fmt: PChar; const Args: array of const);
var
  s: string;
begin
  s := Format(Fmt, Args);
  write(f, s);
end;

procedure fprintf(var f: file; const Fmt: PChar; const Args: array of const); overload;
var
  s: string;
  i: integer;
begin
  s := Format(Fmt, Args);
  for i := 1 to Length(s) do
    BlockWrite(f, s[i], 1);
end;

procedure fprintf(f: integer; const Fmt: PChar; const Args: array of const);
var
  s: string;
  i: integer;
begin
  s := Format(Fmt, Args);
  for i := 1 to Length(s) do
    FileWrite(f, s[i], 1);
end;

procedure fprintf(var f: text; const Fmt: string);
begin
  fprintf(f, PChar(fmt));
end;

procedure fprintf(var f: file; const Fmt: string); overload;
begin
  fprintf(f, PChar(fmt));
end;

procedure fprintf(f: integer; const Fmt: string);
begin
  fprintf(f, PChar(fmt));
end;

procedure fprintf(var f: text; const Fmt: string; const Args: array of const); overload;
begin
  fprintf(f, PChar(fmt), Args);
end;

procedure fprintf(f: integer; const Fmt: string; const Args: array of const); overload;
begin
  fprintf(f, PChar(fmt), Args);
end;

function atoi(const s: PChar): integer;
begin
  result := StrToIntDef(StrPas(s), 0);
end;

function StrToFloatDef(const s: string; def: single): single;
var
  code: integer;
begin
  val(s, result, code);
  if code <> 0 then
    result := def;
end;

function atof2(const s: string): single;
var
  s2: string;
  i: Integer;
begin
  s2 := s;
  for i := 1 to length(s2) do
  begin
    if s2[i] in ['.', ','] then
      s2[i] := DecimalSeparator;
  end;
  result := StrToFloatDef(s2, 0.0);
end;

function atof(const s: PChar): single; overload;
begin
  result := StrToFloatDef(StrPas(s), 0.0);
end;

function boolval(const x: integer): boolean;
begin
  result := x <> 0;
end;

function boolval(const c: char): boolean;
begin
  result := c <> #0;
end;

function boolval(const p: pointer): boolean;
begin
  result := p <> nil;
end;

function boolval(const f: single): boolean; overload;
begin
  result := f <> 0.0;
end;

function boolval(var f: file): boolean;
begin
{$I-}
  FilePos(f);
{$I+}
  result := IOResult = 0;
end;

function floatval(const b: boolean): single;
begin
  if b then
    result := 1.0
  else
    result := 0.0;
end;

function decide(const contition: boolean;
  const iftrue: integer; const iffalse: integer): integer;
begin
  if contition then
    result := iftrue
  else
    result := iffalse;
end;

function decide(const contition: boolean;
  const iftrue: boolean; const iffalse: boolean): boolean;
begin
  if contition then
    result := iftrue
  else
    result := iffalse;
end;

function decide(const contition: boolean;
  const iftrue: string; const iffalse: string): string;
begin
  if contition then
    result := iftrue
  else
    result := iffalse;
end;

function decide(const contition: boolean;
  const iftrue: pointer; const iffalse: pointer): pointer;
begin
  if contition then
    result := iftrue
  else
    result := iffalse;
end;

function decide(const contition: integer;
  const iftrue: integer; const iffalse: integer): integer;
begin
  if contition <> 0 then
    result := iftrue
  else
    result := iffalse;
end;

function decide(const contition: integer;
  const iftrue: boolean; const iffalse: boolean): boolean;
begin
  if contition <> 0 then
    result := iftrue
  else
    result := iffalse;
end;

function decide(const contition: integer;
  const iftrue: string; const iffalse: string): string;
begin
  if contition <> 0 then
    result := iftrue
  else
    result := iffalse;
end;

function decide(const contition: integer;
  const iftrue: pointer; const iffalse: pointer): pointer;
begin
  if contition <> 0 then
    result := iftrue
  else
    result := iffalse;
end;

function fread(buf: pointer; size: integer; count: integer; f: integer): integer;
begin
  result := FileRead(f, buf^, size * count);
  result := result div size;
end;

function fread(buf: pointer; size: integer; count: integer; var f: file): integer;
begin
  BlockRead(f, buf^, size * count, result);
  result := result div size;
end;

function fwrite(buf: pointer; size: integer; count: integer; f: integer): integer;
begin
  result := FileWrite(f, buf^, size * count);
  result := result div size;
end;

function fwrite(buf: pointer; size: integer; count: integer; var f: file): integer;
begin
  BlockWrite(f, buf^, size * count, result);
  result := result div size;
end;

procedure fclose(var f: integer);
begin
  if f <> NULLFILE then
  begin
    FileClose(f);
    f := NULLFILE;
  end;
end;

procedure fclose(var f: file);
begin
  close(f);
end;

procedure fclose(var f: text); overload;
begin
  close(f);
end;

procedure fscanf(var f: text; buf: PChar);
var
  s: string;
begin
  readln(f, s);
  strcpy(buf, PChar(s));
end;

procedure fscanf(var f: text; var num: single);
var
  s: string;
begin
  readln(f, s);
  num := atof(s);
end;

procedure fscanf(var f: text; var num: integer); overload;
var
  s: string;
begin
  readln(f, s);
  num := atoi(s);
end;

function strstr(const _string: PChar; const strCharSet: PChar): PChar;
var
  p: integer;
begin
  if strCharSet = nil then
  begin
    result := _string;
    exit;
  end;

  if strCharSet[0] = #0 then
  begin
    result := _string;
    exit;
  end;

  result := nil;
  p := Pos(StrPas(strCharSet), StrPas(_string));
  if p > 0 then
    result := @_string[p];
end;

function strchr(const _string: PChar; const strChar: char): boolean;
begin
  result := Pos(strChar, StrPas(_string)) > 0;
end;

function getc(f: integer; var c: char): char;
begin
  FileRead(f, c, SizeOf(c));
  result := c;
end;

function getc(var f: file; var c: char): char;
begin
  BlockRead(f, c, SizeOf(c));
  result := c;
end;

function getc(var f: text; var c: char): char;
begin
  read(f, c);
  result := c;
end;

const
  RAND_MAX = $7FFF;

var
  holdrand: integer = 0;

function rand: integer;
begin
  holdrand := holdrand * 214013 + 2531011;
  result := holdrand div $FFFF and RAND_MAX;
end;

function strncmp(s1, s2: PChar; count: Integer): Integer;
var
  z1, z2: string;
begin
  z1 := s1;
  z2 := s2;
  z1 := Copy(z1, 1, count);
  z2 := Copy(z2, 1, count);
  if z1 > z2 then
    result := -1
  else if z1 < z2 then
    result := 1
  else
    result := 0;
end;

function strnicmp(s1, s2: PChar; count: Integer): Integer;
var
  z1, z2: string;
begin
  z1 := s1;
  z2 := s2;
  z1 := UpperCase(Copy(z1, 1, count));
  z2 := UpperCase(Copy(z2, 1, count));
  if z1 > z2 then
    result := -1
  else if z1 < z2 then
    result := 1
  else
    result := 0;
end;

function strncpy(dest, source: PChar; count: Integer): PChar;
var
  len, i: Integer;
begin
  result := dest;
  len := strlen(source);
  if count <= len then
  begin
    move(source^, dest^, count);
  end
  else
  begin
    for i := 1 to len do
    begin
      dest^ := source^;
      inc(dest);
      inc(source);
      dec(count);
    end;
    for i := 1 to count do
    begin
      dest^ := #0;
      inc(dest);
    end;
  end;
end;

function FileIsOpened(f: integer): boolean; overload;
begin
  result := f >= 0;
end;

function FileIsOpened(var f: file): boolean;
begin
{$I-}
  FilePos(f);
{$I+}
  result := IOResult = 0;
end;

function FileIsOpened(var f: text): boolean; overload;
begin
{$I-}
  FilePos(f);
{$I+}
  result := IOResult = 0;
end;

function isupper(ch: Char): boolean;
begin
  result := (ch >= 'A') and (ch <= 'Z');
end;

function islower(ch: Char): boolean;
begin
  result := (ch >= 'a') and (ch <= 'z');
end;

function isalpha(ch: Char): boolean;
begin
  result := ((ch >= 'A') and (ch <= 'Z')) or
    ((ch >= 'a') and (ch <= 'z'));
end;

function isdigit(ch: Char): boolean;
begin
  result := ch in ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];
end;

function strcpy(Dest: PChar; const Source: PChar): PChar; assembler;
asm
        PUSH    EDI
        PUSH    ESI
        MOV     ESI,EAX
        MOV     EDI,EDX
        MOV     ECX,0FFFFFFFFH
        XOR     AL,AL
        REPNE   SCASB
        NOT     ECX
        MOV     EDI,ESI
        MOV     ESI,EDX
        MOV     EDX,ECX
        MOV     EAX,EDI
        SHR     ECX,2
        REP     MOVSD
        MOV     ECX,EDX
        AND     ECX,3
        REP     MOVSB
        POP     ESI
        POP     EDI
end;

function strlen(const Str: PChar): integer; assembler;
asm
        MOV     EDX,EDI
        MOV     EDI,EAX
        MOV     ECX,0FFFFFFFFH
        XOR     AL,AL
        REPNE   SCASB
        MOV     EAX,0FFFFFFFEH
        SUB     EAX,ECX
        MOV     EDI,EDX
end;

function strcmp(const Str1, Str2: PChar): Integer; assembler;
asm
        PUSH    EDI
        PUSH    ESI
        MOV     EDI,EDX
        MOV     ESI,EAX
        MOV     ECX,0FFFFFFFFH
        XOR     EAX,EAX
        REPNE   SCASB
        NOT     ECX
        MOV     EDI,EDX
        XOR     EDX,EDX
        REPE    CMPSB
        MOV     AL,[ESI-1]
        MOV     DL,[EDI-1]
        SUB     EAX,EDX
        POP     ESI
        POP     EDI
end;

function strend(const Str: PChar): PChar; assembler;
asm
        MOV     EDX,EDI
        MOV     EDI,EAX
        MOV     ECX,0FFFFFFFFH
        XOR     AL,AL
        REPNE   SCASB
        LEA     EAX,[EDI-1]
        MOV     EDI,EDX
end;

function strcat(Dest: PChar; const Source: PChar): PChar;
begin
  strcpy(strend(Dest), Source);
  Result := Dest;
end;

function intval(const f: single): integer;
begin
  result := round(f);
end;

function uintval(const f: single): unsigned_int;
begin
  result := trunc(f);
end;

function fatan(const f: single): single;
begin
  result := arctan(f); // JVAL check and optimize this!
end;

function ftan(const f: single): single;
begin
  result := tan(f); // JVAL check and optimize this!
end;

function fasin(const f: single): single;
begin
  result := arcsin(f); // JVAL check and optimize this!
end;

function fatan2(const y, x: single): Extended; //ArcTan2
asm
  FLD  Y
  FLD  X
  FPATAN
  FWAIT
end;

function fpow(const Base, Exponent: single): single;
begin
  result := power(Base, Exponent); // JVAL optimize this!
end;

function floor(x: single): integer;
begin
  Result := Integer(Trunc(X));
  if Frac(X) < 0 then
    Dec(Result);
end;

function ceil(x: single): integer;
begin
  Result := Integer(Trunc(X));
  if Frac(X) > 0 then
    Inc(Result);
end;

const
  WORDBUFSIZE = 1024;

var
  wordbuf: array[0..WORDBUFSIZE - 1] of char;

function read_string(var f: file): PChar;
const
  DELIMETERS: set of char = [#13, #10, ' '];
var
  i: integer;
  c: char;
begin
  c := #0;
  while (c in DELIMETERS) and not eof(f) do
  begin
    BlockRead(f, c, SizeOf(c));
  end;

  if eof(f) then
  begin
    result := nil;
    exit;
  end;

  i := 0;
  while (i < WORDBUFSIZE - 1) and not eof(f) do
  begin
    if not (c in DELIMETERS) then
    begin
      wordbuf[i] := c;
      BlockRead(f, c, SizeOf(c));
    end
    else
    begin
      wordbuf[i] := #0;
      break;
    end;
    inc(i);
  end;
  result := @wordbuf[0];
end;

function read_string(f: integer): PChar;
const
  DELIMETERS: set of char = [#13, #10, ' '];
var
  i: integer;
  c: char;
  numread: integer;
begin
  c := #0;
  numread := SizeOf(c);
  while (c in DELIMETERS) do
  begin
    numread := FileRead(f, c, SizeOf(c));
    if numread <> SizeOf(c) then
      break;
  end;

  if numread <> SizeOf(c) then
  begin
    result := nil;
    exit;
  end;

  i := 0;
  while (i < WORDBUFSIZE - 1) and (numread = SizeOf(c)) do
  begin
    if not (c in DELIMETERS) then
    begin
      wordbuf[i] := c;
      numread := FileRead(f, c, SizeOf(c));
    end
    else
    begin
      wordbuf[i] := #0;
      break;
    end;
    inc(i);
  end;
  result := @wordbuf[0];
end;

function read_int(var f: file): integer;
begin
  result := atoi(read_string(f));
end;

function read_float(var f: file): single;
begin
  result := atof(read_string(f));
end;

function read_float(f: integer): single;
begin
  result := atof(read_string(f));
end;

procedure unlink(name: PChar);
begin
  deletefile(name);
end;

procedure FixFileName(name: PChar);
var
  p: PChar;
begin
  p := name;
  while p^ <> #0 do
  begin
    if p^ = '/' then
      p^ := '\';
    inc(p);
  end;
end;

function fopen(name: PChar; mode: string): integer;
begin
  FixFileName(name);
  if (mode = 'r') or (mode = 'rb') then
    result := FileOpen(name, fmOpenRead or fmShareDenyNone)
  else if (mode = 'w') or (mode = 'wb') then
    result := FileCreate(name)
  else
    result := NULLFILE;
end;

function fopen(name: PChar; mode: string; var f: file): boolean;
begin
  FixFileName(name);
{$I-}
  assign(f, StrPas(name));
  if mode = 'rb' then
    reset(f, 1)
  else if mode = 'wb' then
    rewrite(f, 1)
  else
  begin
    result := false;
    exit;
  end;
{$I+}
  result := IOresult = 0;
end;

function fopen(name: PChar; mode: string; var t: text): boolean;
begin
  FixFileName(name);
{$I-}
  assign(t, StrPas(name));
  if mode = 'r' then
    reset(t)
  else if mode = 'w' then
    rewrite(t)
  else
  begin
    result := false;
    exit;
  end;
{$I+}
  result := IOresult = 0;
end;

function fseek(Handle, Offset, Origin: Integer): Integer;
begin
  result := FileSeek(Handle, Offset, Origin);
end;

function C_PChar(const p: pointer; offs: integer): PChar;
begin
  result := PChar(integer(p) + offs);
end;

function  ReplaceStrAll(Const S, FromStr, ToStr: string): string;
var
  I: integer;
begin
  Result := s;
  while true do
  begin
    I := Pos(FromStr, Result);
    if I > 0 then
    begin
      Delete(Result, I, Length(FromStr));
      Insert(ToStr, Result, I);
    end
    else
      exit;
  end;
end;

end.

