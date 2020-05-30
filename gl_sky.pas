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

unit gl_sky;

interface

uses
  cvar;

procedure GL_InitSky;

procedure GL_DrawSky;

procedure GL_ShutdownSky;

var
  dodrawsky: Boolean = false;
  gl_drawskydome: cvar_t = (name: 'gl_drawskydome'; text: '0'; archive: true);

implementation

uses
  q_delphi,
  q_vector,
  opengl12,
  gl_warp,
  gl_texture;

const
  COMPLEXITY = 16;

var
  fSkyListUpper: TGLuint;
  fSkyListLower: TGLuint;
  skyinitialized: Boolean = false;

const
  SKYSIZE: single = 100000.0;

procedure GL_InitSky;
var
  iRotationStep: double;
  iRotationZ, iRotationY: double;
  iStartPoint, iTemp: TVector3f;
  iI, iJ, iX, iY: Integer;
  iMatrix: TMatrix4f;
  iVertices: array[0..(COMPLEXITY div 4 + 1) * (COMPLEXITY + 1) - 1] of TVector3f;
  iUVCoords: array[0..(COMPLEXITY div 4 + 1) * (COMPLEXITY + 1) - 1] of TVector3f;
  ipos: integer;
begin
  Cvar_RegisterVariable(@gl_drawskydome);

  iRotationStep := 2 * pi / COMPLEXITY;
  iStartPoint[0] := SKYSIZE;
  iStartPoint[1] := 0.0;
  iStartPoint[2] := 0.0;

  iRotationZ := 0;
  ipos := 0;
  for iI := (COMPLEXITY div 4) downto 0 do
  begin
    iRotationY := 0;
    for iJ := 0 to COMPLEXITY do
    begin
      ZeroMemory(@iMatrix, SizeOf(iMatrix));
      iMatrix[0, 0] := cos(iRotationY);
      iMatrix[0, 2] := sin(iRotationY);
      iMatrix[1, 1] := 1.0;
      iMatrix[2, 0] := -sin(iRotationY);
      iMatrix[2, 2] := cos(iRotationY);
      iMatrix[3, 3] := 1.0;

      iTemp[0] := iStartPoint[0] * iMatrix[0, 0] + iStartPoint[1] * iMatrix[1, 0] + iStartPoint[2] * iMatrix[2, 0] + iMatrix[3, 0];
      iTemp[1] := iStartPoint[0] * iMatrix[0, 1] + iStartPoint[1] * iMatrix[1, 1] + iStartPoint[2] * iMatrix[2, 1] + iMatrix[3, 1];
      iTemp[2] := iStartPoint[0] * iMatrix[0, 2] + iStartPoint[1] * iMatrix[1, 2] + iStartPoint[2] * iMatrix[2, 2] + iMatrix[3, 2];

      iVertices[ipos] := iTemp;

      iUVCoords[ipos][0] :=  iTemp[0] / SKYSIZE;
      iUVCoords[ipos][1] :=  iTemp[2] / SKYSIZE;
      inc(ipos);
      iRotationY := iRotationY + iRotationStep;
    end;
    iStartPoint[0] := SKYSIZE;
    iStartPoint[1] := 0.0;
    iStartPoint[2] := 0.0;
    iRotationZ := iRotationZ - iRotationStep;
    ZeroMemory(@iMatrix, SizeOf(iMatrix));
    iMatrix[0, 0] := cos(iRotationZ);
    iMatrix[1, 0] := sin(iRotationZ);
    iMatrix[0, 1] := -sin(iRotationZ);
    iMatrix[1, 1] := cos(iRotationZ);
    iTemp[0] := iStartPoint[0] * iMatrix[0, 0] + iStartPoint[1] * iMatrix[1, 0] + iStartPoint[2] * iMatrix[2, 0] + iMatrix[3, 0];
    iTemp[1] := iStartPoint[0] * iMatrix[0, 1] + iStartPoint[1] * iMatrix[1, 1] + iStartPoint[2] * iMatrix[2, 1] + iMatrix[3, 1];
    iTemp[2] := iStartPoint[0] * iMatrix[0, 2] + iStartPoint[1] * iMatrix[1, 2] + iStartPoint[2] * iMatrix[2, 2] + iMatrix[3, 2];
    iStartPoint := iTemp;
  end;

  fSkyListUpper := glGenLists(1);

  glNewList(fSkyListUpper, GL_COMPILE);

  glColor4f(1.0, 1.0, 1.0, 1.0);
  for iI := 0 to (COMPLEXITY div 4) - 1 do
  begin
    glBegin(GL_TRIANGLE_STRIP);
    for iJ := 0 to COMPLEXITY do
    begin
      iX := iJ + (iI * (COMPLEXITY + 1));
      iY := iJ + ((iI + 1) * (COMPLEXITY + 1));

      glTexCoord2fv(@iUVCoords[iY]);
      glVertex3fv(@iVertices[iY]);

      glTexCoord2fv(@iUVCoords[iX]);
      glVertex3fv(@iVertices[iX]);
    end;
    glEnd;
  end;

  glEndList;

  for iI := 0 to (COMPLEXITY div 4 + 1) * (COMPLEXITY + 1) - 1 do
    iVertices[iI][1] := 1.0 - iVertices[iI][1];

  fSkyListLower := glGenLists(1);

  glNewList(fSkyListLower, GL_COMPILE);

  glColor4f(1.0, 1.0, 1.0, 1.0);
  for iI := 0 to (COMPLEXITY div 4) - 1 do
  begin
    glBegin(GL_TRIANGLE_STRIP);
    for iJ := 0 to COMPLEXITY do
    begin
      iX := iJ + (iI * (COMPLEXITY + 1));
      iY := iJ + ((iI + 1) * (COMPLEXITY + 1));

      glTexCoord2fv(@iUVCoords[iY]);
      glVertex3fv(@iVertices[iY]);

      glTexCoord2fv(@iUVCoords[iX]);
      glVertex3fv(@iVertices[iX]);
    end;
    glEnd;
  end;

  glEndList;

  skyinitialized := true;

end;

procedure GL_DrawSky;
begin
  if not dodrawsky then
    exit;

  GL_Bind(solidskytexture);
  glCallList(fSkyListUpper);
  glCallList(fSkyListLower);

  dodrawsky := false;
end;

procedure GL_ShutdownSky;
begin
  if not skyinitialized then
    exit;

  glDeleteLists(fSkyListLower, 1);
  glDeleteLists(fSkyListUpper, 1);
end;

end.
