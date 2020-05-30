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

unit gl_part;

interface

uses
  q_vector,
  gl_model_h;

procedure R_InitParticles;
procedure R_DrawParticles;
procedure R_ReadPointFile_f;
procedure R_ClearParticles;
procedure R_RunParticleEffect(org: PVector3f; dir: PVector3f; color: integer; count: integer);
procedure R_ParticleExplosion(org: PVector3f);
procedure R_BlobExplosion(org: PVector3f);
procedure R_LavaSplash(org: PVector3f);
procedure R_TeleportSplash(org: PVector3f);
procedure R_ParticleExplosion2(org: PVector3f; colorStart, colorLength: integer);
procedure R_EntityParticles(ent: Pentity_t);
procedure R_RocketTrail(start: PVector3f; _end: PVector3f; _type: integer);
procedure R_ParseParticleEffect;

implementation

uses
  q_delphi,
  mathlib,
  gl_rmain,
  gl_defs,
  OpenGL12,
  common,
  zone,
  cl_main_h,
  quakedef,
  sv_main,
  console,
  gl_texture,
  gl_rmain_h,
  sv_phys,
  gl_vidnt;

const
  MAX_PARTICLES = 2048; // default max # of particles at one
                                //  time

  ABSOLUTE_MIN_PARTICLES = 512; // no fewer than this no matter what's
                                //  on the command line

  ramp1: array[0..7] of integer = ($6F, $6D, $6B, $69, $67, $65, $63, $61);
  ramp2: array[0..7] of integer = ($6F, $6E, $6D, $6C, $6B, $6A, $68, $66);
  ramp3: array[0..7] of integer = ($6D, $6B, $06, $05, $04, $03, $00, $00);

var
  active_particles, free_particles: Pparticle_t;

  particles: Pparticle_tArray;
  r_numparticles: integer;


(*
===============
R_InitParticles
===============
*)

procedure R_InitParticles;
var
  i: integer;
begin
  i := COM_CheckParm('-particles');

  if i > 0 then
  begin
    r_numparticles := Q_atoi(com_argv[i + 1]);
    if r_numparticles < ABSOLUTE_MIN_PARTICLES then
      r_numparticles := ABSOLUTE_MIN_PARTICLES;
  end
  else
    r_numparticles := MAX_PARTICLES;

  particles := Pparticle_tArray(
    Hunk_AllocName(r_numparticles * SizeOf(particle_t), 'particles'));
end;

(*
===============
R_EntityParticles
===============
*)

var
  avelocities: array[0..NUMVERTEXNORMALS - 1] of TVector3f;
  beamlength: single = 16;

procedure R_EntityParticles(ent: Pentity_t);
var
  i: integer;
  p: Pparticle_t;
  sr, sp, sy, cr, cp, cy: single;
  fwd: TVector3f;
  dist: single;
begin
  dist := 64;

  if avelocities[0][0] = 0 then // JVAL check initialization!
  begin
    for i := 0 to NUMVERTEXNORMALS * 3 - 1 do
      avelocities[0][i] := (rand and 255) * 0.01;
  end;


  for i := 0 to NUMVERTEXNORMALS - 1 do
  begin
    SinCos(cl.time * avelocities[i][0], sy, cy);
    SinCos(cl.time * avelocities[i][1], sp, cp);
    SinCos(cl.time * avelocities[i][2], sr, cr);

    fwd[0] := cp * cy;
    fwd[1] := cp * sy;
    fwd[2] := -sp;

    if free_particles = nil then
      exit;
    p := free_particles;
    free_particles := p.next;
    p.next := active_particles;
    active_particles := p;

    p.die := cl.time + 0.01;
    p.color := $6F;
    p._type := pt_explode;

    p.org[0] := ent.origin[0] + r_avertexnormals[i][0] * dist + fwd[0] * beamlength;
    p.org[1] := ent.origin[1] + r_avertexnormals[i][1] * dist + fwd[1] * beamlength;
    p.org[2] := ent.origin[2] + r_avertexnormals[i][2] * dist + fwd[2] * beamlength;
  end;
end;


(*
===============
R_ClearParticles
===============
*)

procedure R_ClearParticles;
var
  i: integer;
begin
  free_particles := @particles[0];
  active_particles := nil;

  for i := 0 to r_numparticles - 1 do
    particles[i].next := @particles[i + 1];
  particles[r_numparticles - 1].next := nil;
end;


procedure R_ReadPointFile_f;
var
  f: integer;
  org: TVector3f;
  c: integer;
  p: Pparticle_t;
  name: array[0..MAX_OSPATH - 1] of char;
  i: integer;
begin
  sprintf(name, 'maps/%s.pts', [sv.name]);

  COM_FOpenFile(name, f);
  if not FileIsOpened(f) then
  begin
    Con_Printf('couldn''t open %s'#10, [name]);
    exit;
  end;

  Con_Printf('Reading %s...'#10, [name]);
  c := 0;
  while true do
  begin
{$I-}
    for i := 0 to 2 do
      org[i] := read_float(f); // JVAL decimal separators ???
{$I+}
    if IOResult <> 0 then
      break;
    inc(c);

    if free_particles = nil then
    begin
      Con_Printf('Not enough free particles'#10);
      break;
    end;
    p := free_particles;
    free_particles := p.next;
    p.next := active_particles;
    active_particles := p;

    p.die := 99999;
    p.color := (-c) and 15; // JVAL check!
    p._type := pt_static;
    VectorCopy(@vec3_origin, @p.vel);
    VectorCopy(@org, @p.org);
  end;

  fclose(f);
  Con_Printf('%d points read'#10, [c]);
end;

(*
===============
R_ParseParticleEffect

Parse an effect out of the server message
===============
*)

procedure R_ParseParticleEffect;
var
  org, dir: TVector3f;
  i, count, msgcount, color: integer;
begin
  for i := 0 to 2 do
    org[i] := MSG_ReadCoord;
  for i := 0 to 2 do
    dir[i] := MSG_ReadChar * (1.0 / 16);
  msgcount := MSG_ReadByte;
  color := MSG_ReadByte;

  if msgcount = 255 then
    count := 1024
  else
    count := msgcount;

  R_RunParticleEffect(@org, @dir, color, count);
end;

(*
===============
R_ParticleExplosion

===============
*)

procedure R_ParticleExplosion(org: PVector3f);
var
  i: integer;
  p: Pparticle_t;
begin
  for i := 0 to 1023 do
  begin
    if free_particles = nil then
      exit;
    p := free_particles;
    free_particles := p.next;
    p.next := active_particles;
    active_particles := p;

    p.die := cl.time + 5;
    p.color := ramp1[0];
    p.ramp := rand and 3;
    p.org[0] := org[0] + (rand mod 32) - 16;
    p.vel[0] := rand mod 512 - 256;
    p.org[1] := org[1] + (rand mod 32) - 16;
    p.vel[1] := rand mod 512 - 256;
    p.org[2] := org[2] + (rand mod 32) - 16;
    p.vel[2] := rand mod 512 - 256;
    if i and 1 <> 0 then
      p._type := pt_explode
    else
      p._type := pt_explode2;
  end;
end;

(*
===============
R_ParticleExplosion2

===============
*)

procedure R_ParticleExplosion2(org: PVector3f; colorStart, colorLength: integer);
var
  i: integer;
  p: pparticle_t;
  colorMod: integer;
begin
  colorMod := 0;

  for i := 0 to 511 do
  begin
    if free_particles = nil then
      exit;
    p := free_particles;
    free_particles := p.next;
    p.next := active_particles;
    active_particles := p;

    p.die := cl.time + 0.3;
    p.color := colorStart + (colorMod mod colorLength);
    inc(colorMod);

    p._type := pt_blob;
    p.org[0] := org[0] + rand mod 32 - 16;
    p.vel[0] := rand mod 512 - 256;
    p.org[1] := org[1] + rand mod 32 - 16;
    p.vel[1] := rand mod 512 - 256;
    p.org[2] := org[2] + rand mod 32 - 16;
    p.vel[2] := rand mod 512 - 256;
  end;
end;

(*
===============
R_BlobExplosion

===============
*)

procedure R_BlobExplosion(org: PVector3f);
var
  i, j: integer;
  p: Pparticle_t;
begin
  for i := 0 to 1023 do
  begin
    if free_particles = nil then
      exit;
    p := free_particles;
    free_particles := p.next;
    p.next := active_particles;
    active_particles := p;

    p.die := cl.time + 1 + (rand and 8) * 0.05;

    if i and 1 <> 0 then
    begin
      p._type := pt_blob;
      p.color := 66 + rand mod 6;
      for j := 0 to 2 do
      begin
        p.org[j] := org[j] + rand mod 32 - 16; // JVAL mayby special proc to handle this!
        p.vel[j] := rand mod 512 - 256;
      end;
    end
    else
    begin
      p._type := pt_blob2;
      p.color := 150 + rand mod 6;
      for j := 0 to 2 do
      begin
        p.org[j] := org[j] + rand mod 32 - 16;
        p.vel[j] := rand mod 512 - 256;
      end;
    end;
  end;
end;

(*
===============
R_RunParticleEffect

===============
*)

procedure R_RunParticleEffect(org: PVector3f; dir: PVector3f; color: integer;
  count: integer);
var
  i, j: integer;
  p: Pparticle_t;
begin
  for i := 0 to count - 1 do
  begin
    if free_particles = nil then
      exit;
    p := free_particles;
    free_particles := p.next;
    p.next := active_particles;
    active_particles := p;

    if count = 1024 then
    begin // rocket explosion
      p.die := cl.time + 5;
      p.color := ramp1[0];
      p.ramp := rand and 3;
      if i and 1 <> 0 then
      begin
        p._type := pt_explode;
        for j := 0 to 2 do
        begin
          p.org[j] := org[j] + rand mod 32 - 16;
          p.vel[j] := rand mod 512 - 256;
        end;
      end
      else
      begin
        p._type := pt_explode2;
        for j := 0 to 2 do
        begin
          p.org[j] := org[j] + rand mod 32 - 16;
          p.vel[j] := rand mod 512 - 256;
        end;
      end;
    end
    else
    begin
      p.die := cl.time + 0.1 * (rand mod 5);
      p.color := (color and (not 7)) + (rand and 7);
      p._type := pt_slowgrav;
      for j := 0 to 2 do
      begin
        p.org[j] := org[j] + rand mod 15 - 8;
        p.vel[j] := dir[j] * 15; // + (rand()%300)-150;
      end;
    end;
  end;
end;


(*
===============
R_LavaSplash

===============
*)

procedure R_LavaSplash(org: PVector3f);
var
  i, j, k: integer;
  p: Pparticle_t;
  vel: single;
  dir: TVector3f;
begin
  for i := -16 to 15 do
    for j := -16 to 15 do
      for k := 0 to 0 do
      begin
        if free_particles = nil then
          exit;
        p := free_particles;
        free_particles := p.next;
        p.next := active_particles;
        active_particles := p;

        p.die := cl.time + 2 + (rand and 31) * 0.02;
        p.color := 224 + (rand and 7);
        p._type := pt_slowgrav;

        dir[0] := j * 8 + (rand and 7);
        dir[1] := i * 8 + (rand and 7);
        dir[2] := 256;

        p.org[0] := org[0] + dir[0];
        p.org[1] := org[1] + dir[1];
        p.org[2] := org[2] + (rand and 63);

        VectorNormalize(@dir);
        vel := 50 + (rand and 63);
        VectorScale(@dir, vel, @p.vel);
      end;
end;

(*
===============
R_TeleportSplash

===============
*)

procedure R_TeleportSplash(org: PVector3f);
var
  i, j, k: integer;
  p: Pparticle_t;
  vel: single;
  dir: TVector3f;
begin
  i := -16;
  while i < 16 do
  begin
    j := -16;
    while j < 16 do
    begin
      k := -24;
      while k < 32 do
      begin
        if free_particles = nil then
          exit;
        p := free_particles;
        free_particles := p.next;
        p.next := active_particles;
        active_particles := p;

        p.die := cl.time + 0.2 + (rand and 7) * 0.02;
        p.color := 7 + (rand and 7);
        p._type := pt_slowgrav;

        dir[0] := j * 8;
        dir[1] := i * 8;
        dir[2] := k * 8;

        p.org[0] := org[0] + i + (rand and 3);
        p.org[1] := org[1] + j + (rand and 3);
        p.org[2] := org[2] + k + (rand and 3);

        VectorNormalize(@dir);
        vel := 50 + (rand and 63);
        VectorScale(@dir, vel, @p.vel);

        inc(k, 4);
      end;

      inc(j, 4);
    end;

    inc(i, 4);
  end;

end;

var
  tracercount: integer = 0;

procedure R_RocketTrail(start: PVector3f; _end: PVector3f; _type: integer);
var
  vec: TVector3f;
  len: single;
  j: integer;
  p: Pparticle_t;
  minus: integer;
begin
  VectorSubtract(_end, start, @vec);
  len := VectorNormalize(@vec);
  if _type < 128 then
    minus := 3
  else
  begin
    minus := 1;
    _type := _type - 128;
  end;

  while len > 0 do
  begin
    len := len - minus;

    if free_particles = nil then
      exit;
    p := free_particles;
    free_particles := p.next;
    p.next := active_particles;
    active_particles := p;

    VectorCopy(@vec3_origin, @p.vel);
    p.die := cl.time + 2;

    case _type of
      0: // rocket trail
        begin
          p.ramp := rand and 3;
          p.color := ramp3[intval(p.ramp)];
          p._type := pt_fire;
          for j := 0 to 2 do
            p.org[j] := start[j] + (rand mod 6) - 3;
        end;

      1: // smoke smoke
        begin
          p.ramp := rand and 3 + 2;
          p.color := ramp3[intval(p.ramp)];
          p._type := pt_fire;
          for j := 0 to 2 do
            p.org[j] := start[j] + (rand mod 6) - 3;
        end;

      2: // blood
        begin
          p._type := pt_grav;
          p.color := 67 + rand and 3;
          for j := 0 to 2 do
            p.org[j] := start[j] + (rand mod 6) - 3;
        end;

      3,
        5: // tracer
        begin
          p.die := cl.time + 0.5;
          p._type := pt_static;
          if _type = 3 then
            p.color := 52 + 2 * (tracercount and 4)
          else
            p.color := 230 + 2 * (tracercount and 4);

          inc(tracercount);

          VectorCopy(start, @p.org);
          if tracercount and 1 <> 0 then
          begin
            p.vel[0] := 30 * vec[1];
            p.vel[1] := -30 * vec[0];
          end
          else
          begin
            p.vel[0] := -30 * vec[1];
            p.vel[1] := 30 * vec[0];
          end;
        end;

      4: // slight blood
        begin
          p._type := pt_grav;
          p.color := 67 + (rand and 3);
          for j := 0 to 2 do
            p.org[j] := start[j] + (rand mod 6) - 3;
          len := len - 3;
        end;

      6: // voor trail
        begin
          p.color := 9 * 16 + 8 + (rand and 3);
          p._type := pt_static;
          p.die := cl.time + 0.3;
          for j := 0 to 2 do
            p.org[j] := start[j] + (rand and 15) - 8;
        end;
    end;


    VectorAdd(start, @vec, start);
  end;
end;


(*
===============
R_DrawParticles
===============
*)

procedure R_DrawParticles;
label
  continue1;
var
  p, kill: Pparticle_t;
  grav: single;
  i: integer;
  time2, time3: single;
  time1: single;
  dvel: single;
  frametime: single;
  up, right: TVector3f;
  scale: single;
begin
  GL_Bind(particletexture);
  glEnable(GL_BLEND);
  glTexEnvf(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_MODULATE);
  glBegin(GL_TRIANGLES);

  VectorScale(@vup, 1.5, @up);
  VectorScale(@vright, 1.5, @right);
  frametime := cl.time - cl.oldtime;
  time3 := frametime * 15;
  time2 := frametime * 10;
  time1 := frametime * 5;
  grav := frametime * sv_gravity.value * 0.05;
  dvel := 4 * frametime;

  while true do
  begin
    kill := active_particles;
    if (kill <> nil) and (kill.die < cl.time) then
    begin
      active_particles := kill.next;
      kill.next := free_particles;
      free_particles := kill;
      continue;
    end;
    break;
  end;

  p := active_particles;
  while p <> nil do
  begin
    while true do
    begin
      kill := p.next;
      if (kill <> nil) and (kill.die < cl.time) then
      begin
        p.next := kill.next;
        kill.next := free_particles;
        free_particles := kill;
        goto continue1;
      end;
      break;
    end;

    // hack a scale up to keep particles from disapearing
    scale := (p.org[0] - r_origin[0]) * vpn[0] +
      (p.org[1] - r_origin[1]) * vpn[1] +
      (p.org[2] - r_origin[2]) * vpn[2];
    if scale < 20 then
      scale := 1
    else
      scale := 1 + scale * 0.004;
    glColor3ubv(PGLubyte(@d_8to24table[intval(p.color)])); // JVAL check!, also check int()
    glTexCoord2f(0, 0);
    glVertex3fv(@p.org);
    glTexCoord2f(1, 0);
    glVertex3f(p.org[0] + up[0] * scale, p.org[1] + up[1] * scale, p.org[2] + up[2] * scale);
    glTexCoord2f(0, 1);
    glVertex3f(p.org[0] + right[0] * scale, p.org[1] + right[1] * scale, p.org[2] + right[2] * scale);
    p.org[0] := p.org[0] + p.vel[0] * frametime;
    p.org[1] := p.org[1] + p.vel[1] * frametime;
    p.org[2] := p.org[2] + p.vel[2] * frametime;

    case p._type of
      pt_static: ;

      pt_fire:
        begin
          p.ramp := p.ramp + time1;
          if p.ramp >= 6 then
            p.die := -1
          else
            p.color := ramp3[intval(p.ramp)];
          p.vel[2] := p.vel[2] + grav;
        end;

      pt_explode:
        begin
          p.ramp := p.ramp + time2;
          if p.ramp >= 8 then
            p.die := -1
          else
            p.color := ramp1[intval(p.ramp)];
          for i := 0 to 2 do
            p.vel[i] := p.vel[i] + p.vel[i] * dvel;
          p.vel[2] := p.vel[2] - grav;
        end;

      pt_explode2:
        begin
          p.ramp := p.ramp + time3;
          if p.ramp >= 8 then
            p.die := -1
          else
            p.color := ramp2[intval(p.ramp)];
          for i := 0 to 2 do
            p.vel[i] := p.vel[i] - p.vel[i] * frametime;
          p.vel[2] := p.vel[2] - grav;
        end;

      pt_blob:
        begin
          for i := 0 to 2 do
            p.vel[i] := p.vel[i] + p.vel[i] * dvel;
          p.vel[2] := p.vel[2] - grav;
        end;

      pt_blob2:
        begin
          for i := 0 to 1 do
            p.vel[i] := p.vel[i] - p.vel[i] * dvel;
          p.vel[2] := p.vel[2] - grav;
        end;

      pt_grav,
      pt_slowgrav:
        begin
          p.vel[2] := p.vel[2] - grav;
        end;

    end;

    continue1:
    p := p.next;
  end;

  glEnd;
  glDisable(GL_BLEND);
  glTexEnvf(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_REPLACE);
end;


end.
