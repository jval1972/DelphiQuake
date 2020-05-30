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

unit t_material;

interface

uses
  q_delphi,
  t_main;

type
  TMaterialTextureManager = object(TTextureManager)
    tex1: PTexture;
  public
    constructor Create;
    function LoadHeader(stream: TStream): boolean; virtual;
    function LoadImage(stream: TStream): boolean; virtual;
    destructor Destroy; virtual;
  end;

implementation

constructor TMaterialTextureManager.Create;
begin
  inherited Create;
  SetFileExt('.MATERIAL');
end;

function TMaterialTextureManager.LoadHeader(stream: TStream): boolean;
var
  s: TDStringList;
  texname, alphaname: string;
  alpha1: PTexture;
begin
  stream.seek(0, sFromBeginning);
  s := TDSTringList.Create;
  s.LoadFromStream(stream);
  texname := s.Values['texture'];
  alphaname := s.Values['alpha'];
  s.Free;
  result := texname <> '';
  if not result then
    exit;
  tex1 := T_LoadHiResTexture(texname);
  if tex1 = nil then
  begin
    result := false;
    exit;
  end;
  if alphaname <> '' then
  begin
    alpha1 := T_LoadHiResTexture(alphaname);
    if alpha1 = nil then
      exit;
    tex1.ConvertTo32bit;
    tex1.SetAlphaChannelFromImage(alpha1);
    dispose(alpha1, destroy);
  end;
  FBitmap^.SetBytesPerPixel(4);
  FBitmap^.SetWidth(tex1.GetWidth);
  FBitmap^.SetHeight(tex1.GetHeight);
end;

function TMaterialTextureManager.LoadImage(stream: TStream): boolean;
begin
  memcpy(FBitmap.GetImage, tex1.GetImage, tex1.GetWidth * tex1.GetHeight * 4);
  FBitmap.SetExternalAlphaPresent(tex1.ExternalAlphaPresent);
  dispose(tex1, destroy);
  result := true;
end;

destructor TMaterialTextureManager.Destroy;
begin
  Inherited destroy;
end;

end.

