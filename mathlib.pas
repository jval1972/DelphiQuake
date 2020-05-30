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

unit mathlib;

interface
//
uses
  q_delphi,
  q_vector;

const
  M_PI = 3.14159265358979323846; // matches value in gcc v2 math.h
  DEG2RAD = M_PI / 180.0;

function IS_NAN(x: single): qboolean;
procedure ProjectPointOnPlane(dst: PVector3f; p: PVector3f; normal: PVector3f);
procedure PerpendicularVector(dst: PVector3f; src: PVector3f);
procedure RotatePointAroundVector(dst: PVector3f; dir: PVector3f; point: PVector3f; degrees: single);
function anglemod(a: single): single;
procedure AngleVectors(angles: PVector3f; _forward, right, up: PVector3f);

procedure VectorMA(veca: PVector3f; scale: single; vecb: PVector3f; vecc: PVector3f);
function VectorLength(const v: PVector3f): Single;
function VectorNormalize(v: PVector3f): single;
procedure VectorScale(_in: PVector3f; const scale: Single; _out: PVector3f);
procedure VectorSubtract(veca, vecb: PVector3f; _out: PVector3f);
procedure VectorAdd(veca, vecb: PVector3f; _out: PVector3f);
procedure VectorCopy(_in: PVector3f; _out: PVector3f);

function VectorDotProduct(const v1, v2: PVector3f): Single;
procedure CrossProduct(v1, v2: PVector3f; cross: PVector3f);
procedure R_ConcatRotations(in1, in2: Pmat3_t; _out: Pmat3_t);
function RadiusFromBounds(mins: PVector3f; maxs: PVector3f): single;
procedure SinCos(const Theta: Single; var Sin, Cos: Single);overload;
procedure SinCos(const theta, radius : Single; var Sin, Cos: Single);overload;

implementation

uses
  quakedef;

const
  nanmask = 255 shl 23;

procedure SinCos(const Theta: Single; var Sin, Cos: Single);
asm
   FLD  Theta
   FSINCOS
   FSTP DWORD PTR [EDX]
   FSTP DWORD PTR [EAX]
end;

procedure SinCos(const theta, radius : Single; var Sin, Cos: Single);
asm
   FLD  theta
   FSINCOS
   FMUL radius
   FSTP DWORD PTR [EDX]    // cosine
   FMUL radius
   FSTP DWORD PTR [EAX]    // sine
end;

function IS_NAN(x: single): qboolean;
begin
  result := (Pinteger(@x)^ and nanmask) = nanmask;
end;

procedure ProjectPointOnPlane(dst: PVector3f; p: PVector3f; normal: PVector3f);
var
  d: single;
  n: TVector3f;
  inv_denom: single;
begin
  inv_denom := 1.0 / VectorDotProduct(normal, normal);

  d := VectorDotProduct(normal, p) * inv_denom;

  n[0] := normal[0] * inv_denom;
  n[1] := normal[1] * inv_denom;
  n[2] := normal[2] * inv_denom;

  dst[0] := p[0] - d * n[0];
  dst[1] := p[1] - d * n[1];
  dst[2] := p[2] - d * n[2];
end;

(*
** assumes "src" is normalized
*)

procedure PerpendicularVector(dst: PVector3f; src: PVector3f);
var
  pos: integer;
  i: integer;
  minelem: single;
  tempvec: TVector3f;
begin
  minelem := 1.0;

  (*
  ** find the smallest magnitude axially aligned vector
  *)
  pos := 0;
  for i := 0 to 2 do
  begin
    if abs(src[i]) < minelem then
    begin
      pos := i;
      minelem := abs(src[i]);
    end;
  end;
  tempvec[0] := 0.0;
  tempvec[1] := 0.0;
  tempvec[2] := 0.0;
  tempvec[pos] := 1.0;

  (*
  ** project the point onto the plane defined by src
  *)
  ProjectPointOnPlane(dst, @tempvec[0], src);

  (*
  ** normalize the result
  *)
  VectorNormalize(dst);
end;

procedure RotatePointAroundVector(dst: PVector3f; dir: PVector3f; point: PVector3f; degrees: single);
var
  m: mat3_t;
  im: mat3_t;
  zrot: mat3_t;
  tmpmat: mat3_t;
  rot: mat3_t;
  i: integer;
  vr, vup, vf: TVector3f;
begin
  vf[0] := dir[0];
  vf[1] := dir[1];
  vf[2] := dir[2];

  PerpendicularVector(@vr[0], dir);
  CrossProduct(@vr[0], @vf[0], @vup[0]);

  m[0][0] := vr[0];
  m[1][0] := vr[1];
  m[2][0] := vr[2];

  m[0][1] := vup[0];
  m[1][1] := vup[1];
  m[2][1] := vup[2];

  m[0][2] := vf[0];
  m[1][2] := vf[1];
  m[2][2] := vf[2];

  memcpy(@im[0], @m[0], SizeOf(im));

  im[0][1] := m[1][0];
  im[0][2] := m[2][0];
  im[1][0] := m[0][1];
  im[1][2] := m[2][1];
  im[2][0] := m[0][2];
  im[2][1] := m[1][2];

  ZeroMemory(@zrot[0], SizeOf(zrot));
  zrot[0, 0] := 1.0;
  zrot[1, 1] := 1.0;
  zrot[2, 2] := 1.0;

  zrot[0][0] := cos(DEG2RAD * degrees);
  zrot[0][1] := sin(DEG2RAD * degrees);
  zrot[1][0] := -sin(DEG2RAD * degrees);
  zrot[1][1] := cos(DEG2RAD * degrees);

  R_ConcatRotations(@m[0], @zrot[0], @tmpmat[0]);
  R_ConcatRotations(@tmpmat[0], @im[0], @rot[0]);

  for i := 0 to 2 do
  begin
    dst[i] := rot[i, 0] * point[0] + rot[i, 1] * point[1] + rot[i, 2] * point[2];
  end;
end;

(*-----------------------------------------------------------------*)


function anglemod(a: single): single;
const
  a1 = (360.0 / 65536);
  a2 = (65536 / 360.0);
begin
  result := a1 * (intval(a * a2) and 65535);
end;

procedure AngleVectors(angles: PVector3f; _forward, right, up: PVector3f);
const
  a1 = (M_PI * 2 / 360);
var
  angle: single;
  sr, sp, sy, cr, cp, cy: single;
begin
  angle := angles[YAW] * a1;
  SinCos(angle, sy, cy);
  angle := angles[PITCH] * a1;
  SinCos(angle, sp, cp);
  angle := angles[ROLL] * a1;
  SinCos(angle, sr, cr);

  _forward[0] := cp * cy;
  _forward[1] := cp * sy;
  _forward[2] := -sp;
  right[0] := (-1 * sr * sp * cy + -1 * cr * -sy);
  right[1] := (-1 * sr * sp * sy + -1 * cr * cy);
  right[2] := -1 * sr * cp;
  up[0] := (cr * sp * cy + -sr * -sy);
  up[1] := (cr * sp * sy + -sr * cy);
  up[2] := cr * cp;
end;

procedure VectorMA(veca: PVector3f; scale: single; vecb: PVector3f; vecc: PVector3f);
begin
  vecc[0] := veca[0] + scale * vecb[0];
  vecc[1] := veca[1] + scale * vecb[1];
  vecc[2] := veca[2] + scale * vecb[2];
end;


function VectorDotProduct(const v1, v2: PVector3f): Single;
{begin
  result := v1[0] * v2[0] + v1[1] * v2[1] + v1[2] * v2[2];
end;}
asm
       FLD  DWORD PTR [eax]
       FMUL DWORD PTR [edx]
       FLD  DWORD PTR [eax+4]
       FMUL DWORD PTR [edx+4]
       faddp
       FLD  DWORD PTR [eax+8]
       FMUL DWORD PTR [edx+8]
       faddp
end;


procedure VectorSubtract(veca, vecb: PVector3f; _out: PVector3f);
{begin
  _out[0] := veca[0] - vecb[0];
  _out[1] := veca[1] - vecb[1];
  _out[2] := veca[2] - vecb[2];
end;}
asm
 FLD  DWORD PTR [EAX]
 FSUB DWORD PTR [EDX]
 FSTP DWORD PTR [ECX]
 FLD  DWORD PTR [EAX+4]
 FSUB DWORD PTR [EDX+4]
 FSTP DWORD PTR [ECX+4]
 FLD  DWORD PTR [EAX+8]
 FSUB DWORD PTR [EDX+8]
 FSTP DWORD PTR [ECX+8]
end;


procedure VectorAdd(veca, vecb: PVector3f; _out: PVector3f);
{begin
  _out[0] := veca[0] + vecb[0];
  _out[1] := veca[1] + vecb[1];
  _out[2] := veca[2] + vecb[2];
end;}
asm
 FLD  DWORD PTR [EAX]
 FADD DWORD PTR [EDX]
 FSTP DWORD PTR [ECX]
 FLD  DWORD PTR [EAX+4]
 FADD DWORD PTR [EDX+4]
 FSTP DWORD PTR [ECX+4]
 FLD  DWORD PTR [EAX+8]
 FADD DWORD PTR [EDX+8]
 FSTP DWORD PTR [ECX+8]
end;


procedure VectorCopy(_in: PVector3f; _out: PVector3f);
begin
  _out[0] := _in[0];
  _out[1] := _in[1];
  _out[2] := _in[2];
end;

procedure CrossProduct(v1, v2: PVector3f; cross: PVector3f);
begin
  cross[0] := v1[1] * v2[2] - v1[2] * v2[1];
  cross[1] := v1[2] * v2[0] - v1[0] * v2[2];
  cross[2] := v1[0] * v2[1] - v1[1] * v2[0];
end;

function VectorLength(const v: PVector3f): Single; // JVAL mayby add VectorSquareLength ?
{begin
  result := v[0] * v[0] + v[1] * v[1] + v[2] * v[2];
  result := sqrt(result);    // FIXME
end;}
asm
 FLD  DWORD PTR [EAX]
 FMUL ST, ST
 FLD  DWORD PTR [EAX+4]
 FMUL ST, ST
 FADDP
 FLD  DWORD PTR [EAX+8]
 FMUL ST, ST
 FADDP
 FSQRT
end;


function VectorNormalize(v: PVector3f): single;
var
  ilength: single;
begin
  result := VectorLength(v);

  if result > 0.0 then
  begin
    ilength := 1 / result;
    v[0] := v[0] * ilength;
    v[1] := v[1] * ilength;
    v[2] := v[2] * ilength;
  end;
end;

procedure VectorScale(_in: PVector3f; const scale: Single; _out: PVector3f);
{begin
  _out[0] := _in[0] * scale;
  _out[1] := _in[1] * scale;
  _out[2] := _in[2] * scale;
end;}
asm
 FLD  DWORD PTR [EAX]
 FMUL DWORD PTR [EBP+8]
 FSTP DWORD PTR [EDX]
 FLD  DWORD PTR [EAX+4]
 FMUL DWORD PTR [EBP+8]
 FSTP DWORD PTR [EDX+4]
 FLD  DWORD PTR [EAX+8]
 FMUL DWORD PTR [EBP+8]
 FSTP DWORD PTR [EDX+8]
end;

(*
================
R_ConcatRotations
================
*)

procedure R_ConcatRotations(in1, in2: Pmat3_t; _out: Pmat3_t);
begin
  _out[0][0] := in1[0][0] * in2[0][0] + in1[0][1] * in2[1][0] + in1[0][2] * in2[2][0];
  _out[0][1] := in1[0][0] * in2[0][1] + in1[0][1] * in2[1][1] + in1[0][2] * in2[2][1];
  _out[0][2] := in1[0][0] * in2[0][2] + in1[0][1] * in2[1][2] + in1[0][2] * in2[2][2];
  _out[1][0] := in1[1][0] * in2[0][0] + in1[1][1] * in2[1][0] + in1[1][2] * in2[2][0];
  _out[1][1] := in1[1][0] * in2[0][1] + in1[1][1] * in2[1][1] + in1[1][2] * in2[2][1];
  _out[1][2] := in1[1][0] * in2[0][2] + in1[1][1] * in2[1][2] + in1[1][2] * in2[2][2];
  _out[2][0] := in1[2][0] * in2[0][0] + in1[2][1] * in2[1][0] + in1[2][2] * in2[2][0];
  _out[2][1] := in1[2][0] * in2[0][1] + in1[2][1] * in2[1][1] + in1[2][2] * in2[2][1];
  _out[2][2] := in1[2][0] * in2[0][2] + in1[2][1] * in2[1][2] + in1[2][2] * in2[2][2];
end;

function RadiusFromBounds(mins: PVector3f; maxs: PVector3f): single;
var
  i: integer;
  corner: TVector3f;
begin
  for i := 0 to 2 do
    if abs(mins[i]) > abs(maxs[i]) then corner[i] := abs(mins[i])
    else corner[i] := abs(maxs[i]);

  result := VectorLength(@corner);
end;

end.

