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

unit q_extra;

interface

procedure QEX_Init;

procedure QEX_Shutdown;

implementation

uses
  q_delphi,
  common,
  gl_sky,
  t_main,
  w_pak;

procedure Ex_DetectCPU;
begin

  try
  // detect MMX and 3DNow! capable CPU (adapted from AMD's "3DNow! Porting Guide")
    asm
      pusha
      mov  eax, $80000000
      cpuid
      cmp  eax, $80000000
      jbe @@NoMMX3DNow
      mov mmxMachine, 1
      mov  eax, $80000001
      cpuid
      test edx, $80000000
      jz @@NoMMX3DNow
      mov AMD3DNowMachine, 1
  @@NoMMX3DNow:
      popa
    end;
  except
  // trap for old/exotics CPUs
    mmxMachine := 0;
    AMD3DNowMachine := 0;
  end;

  if mmxMachine <> 0 then
    printf(' MMX extentions detected'#13#10);
  if AMD3DNowMachine <> 0 then
    printf(' AMD 3D Now! extentions detected'#13#10);
end;


procedure Ex_AddPAKFiles(parm: PChar);
var
  p: integer;
begin
  p := Com_CheckParm(parm);
  if p <> 0 then
  begin
    inc(p);
    while (p < com_argc) and boolval(com_argv[p]) and (com_argv[p]^ <> '-') do
    begin
      PAK_AddFile(com_argv[p]);
      inc(p);
    end;
  end;
end;


procedure QEX_Init;
begin
  Ex_DetectCPU;
  T_Init;
  PAK_InitFileSystem;
  Ex_AddPAKFiles('-pakfile');
end;

procedure QEX_Shutdown;
begin
  T_ShutDown;
  PAK_ShutDown;
  GL_ShutdownSky;
end;


end.
