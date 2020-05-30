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

unit pr_cmds;

interface

uses
  cvar,
  progs_h;

const
  pr_numbuiltins = 79;

var
  pr_builtin: array[0..pr_numbuiltins - 1] of builtin_t;
  pr_builtins: Pbuiltin_t;

procedure PF_changeyaw;

var
  sv_aim: cvar_t =
  (name: 'sv_aim'; text: '1.0');

procedure PR_InitBuiltIns;

implementation

uses
  q_delphi,
  q_vector,
  bspconst,
  mathlib,
  pr_comp,
  pr_edict,
  pr_exec,
  console,
  host,
  world,
  gl_model,
  gl_model_h,
  quakedef,
  sv_main,
  server_h,
  common,
  protocol,
  sys_win,
  host_h,
  cmd,
  sv_move;

procedure RETURN_EDICT(e: Pedict_t);
begin
  PIntegerArray(pr_globals)[OFS_RETURN] := EDICT_TO_PROG(e);
end;

(*
===============================================================================

            BUILT-IN FUNCTIONS

===============================================================================
*)

var
  out_PF_VarString: array[0..255] of char;

function PF_VarString(first: integer): PChar;
var
  i: integer;
begin
  out_PF_VarString[0] := #0;
  for i := first to pr_argc - 1 do
    strcat(out_PF_VarString, G_STRING((OFS_PARM0 + i * 3)));

  result := @out_PF_VarString[0];
end;


(*
=================
PF_errror

This is a TERMINAL error, which will kill off the entire server.
Dumps self.

error(value)
=================
*)

procedure PF_error;
var
  s: PChar;
  ed: Pedict_t;
begin
  s := PF_VarString(0);
  Con_Printf('======SERVER ERROR in %s:'#10'%s'#10, [pr_strings[pr_xfunction.s_name], s]);
  ed := PROG_TO_EDICT(pr_global_struct.self);
  ED_Print(ed);

  Host_Error('Program error');
end;

(*
=================
PF_objerror

Dumps out self, then an error message.  The program is aborted and self is
removed, but the level can continue.

objerror(value)
=================
*)

procedure PF_objerror;
var
  s: PChar;
  ed: Pedict_t;
begin
  s := PF_VarString(0);
  Con_Printf('======OBJECT ERROR in %s:'#10'%s'#10, [pr_strings[pr_xfunction.s_name], s]);
  ed := PROG_TO_EDICT(pr_global_struct.self);
  ED_Print(ed);
  ED_Free(ed);

  Host_Error('Program error');
end;



(*
==============
PF_makevectors

Writes new values for v_forward, v_up, and v_right based on angles
makevectors(vector)
==============
*)

procedure PF_makevectors;
begin
  AngleVectors(G_VECTOR(OFS_PARM0),
    @pr_global_struct.v_forward, @pr_global_struct.v_right, @pr_global_struct.v_up);
end;

(*
=================
PF_setorigin

This is the only valid way to move an object without using the physics of the world
(setting velocity and waiting).  Directly changing origin will not set internal links
correctly, so clipping would be messed up.  This should be called when an object
is spawned, and then only if it is teleported.

setorigin (entity, origin)
=================
*)

procedure PF_setorigin;
var
  e: Pedict_t;
  org: PVector3f;
begin
  e := G_EDICT(OFS_PARM0);
  org := G_VECTOR(OFS_PARM1);
  VectorCopy(org, @e.v.origin);
  SV_LinkEdict(e, false);
end;


procedure SetMinMaxSize(e: Pedict_t; min, max: PVector3f; rotate: qboolean);
var
  angles: PfloatArray;
  rmin, rmax: TVector3f;
  bounds: array[0..1] of TVector3f;
  xvector, yvector: TVector3f;
  a: single;
  base, transformed: TVector3f;
  i, j, k, l: integer;
begin
  for i := 0 to 2 do
    if min[i] > max[i] then
      PR_RunError('backwards mins/maxs');

  rotate := false; // FIXME: implement rotation properly again

  if not rotate then
  begin
    VectorCopy(min, @rmin);
    VectorCopy(max, @rmax);
  end
  else
  begin
  // find min / max for rotations
    angles := @e.v.angles[0];

    a := angles[1] / 180 * M_PI;

    xvector[0] := cos(a); // JVAL mayby SicCos ??
    xvector[1] := sin(a);
    yvector[0] := -sin(a);
    yvector[1] := cos(a);

    VectorCopy(min, @bounds[0]);
    VectorCopy(max, @bounds[1]);

    rmin[0] := 9999;
    rmin[1] := 9999;
    rmin[2] := 9999;
    rmax[0] := -9999;
    rmax[1] := -9999;
    rmax[2] := -9999;

    for i := 0 to 1 do
    begin
      base[0] := bounds[i, 0];
      for j := 0 to 1 do
      begin
        base[1] := bounds[j, 1];
        for k := 0 to 1 do
        begin
          base[2] := bounds[k, 2];

        // transform the point
          transformed[0] := xvector[0] * base[0] + yvector[0] * base[1];
          transformed[1] := xvector[1] * base[0] + yvector[1] * base[1];
          transformed[2] := base[2];

          for l := 0 to 2 do
          begin
            if transformed[l] < rmin[l] then
              rmin[l] := transformed[l];
            if transformed[l] > rmax[l] then
              rmax[l] := transformed[l];
          end;
        end;
      end;
    end;
  end;

// set derived values
  VectorCopy(@rmin, @e.v.mins);
  VectorCopy(@rmax, @e.v.maxs);
  VectorSubtract(max, min, @e.v.size);

  SV_LinkEdict(e, false);
end;

(*
=================
PF_setsize

the size box is rotated by the current angle

setsize (entity, minvector, maxvector)
=================
*)

procedure PF_setsize;
var
  e: Pedict_t;
  min, max: PVector3f;
begin
  e := G_EDICT(OFS_PARM0);
  min := G_VECTOR(OFS_PARM1);
  max := G_VECTOR(OFS_PARM2);
  SetMinMaxSize(e, min, max, false);
end;


(*
=================
PF_setmodel

setmodel(entity, model)
=================
*)

procedure PF_setmodel;
var
  e: Pedict_t;
  m: PChar;
  check: PChar;
  mdl: PBSPModelFile;
  i: integer;
begin
  e := G_EDICT(OFS_PARM0);
  m := G_STRING(OFS_PARM1);

// check to see if model was properly precached
  i := 0;
  while i < MAX_MODELS do
  begin
    check := sv.model_precache[i];
    if strcmp(check, m) = 0 then
      break;
    inc(i);
  end;

  if i = MAX_MODELS then
    PR_RunError('no precache: %s'#10, [m]);

{ var check: PPChar;
  .....
  check := @sv.model_precache[0];
  while boolval(check^) do
  begin
    if strcmp(check^, m) = 0 then
      break;
    inc(check);
  end;

  if not boolval(check^) then
    PR_RunError('no precache: %s'#10, [m]);
}

  e.v.model := m - pr_strings;
  e.v.modelindex := i; //SV_ModelIndex (m);

  mdl := sv.models[i]; // Mod_ForName (m, true);

  if mdl <> nil then
    SetMinMaxSize(e, @mdl.mins, @mdl.maxs, true)
  else
    SetMinMaxSize(e, @vec3_origin, @vec3_origin, true);
end;

(*
=================
PF_bprint

broadcast print to everyone on server

bprint(value)
=================
*)

procedure PF_bprint;
var
  s: PChar;
begin
  s := PF_VarString(0);
  SV_BroadcastPrintf('%s', [s]);
end;

(*
=================
PF_sprint

single print to a specific client

sprint(clientent, value)
=================
*)

procedure PF_sprint;
var
  s: PChar;
  client: Pclient_t;
  entnum: integer;
begin
  entnum := G_EDICTNUM(OFS_PARM0);
  s := PF_VarString(1);

  if (entnum < 1) or (entnum > svs.maxclients) then
  begin
    Con_Printf('tried to sprint to a non-client'#10);
    exit;
  end;

  client := @svs.clients[entnum - 1];

  MSG_WriteChar(@client._message, svc_print);
  MSG_WriteString(@client._message, s);
end;


(*
=================
PF_centerprint

single print to a specific client

centerprint(clientent, value)
=================
*)

procedure PF_centerprint;
var
  s: PChar;
  client: Pclient_t;
  entnum: integer;
begin
  entnum := G_EDICTNUM(OFS_PARM0); // JVAL mayby same proc as above...
  s := PF_VarString(1);

  if (entnum < 1) or (entnum > svs.maxclients) then
  begin
    Con_Printf('tried to sprint to a non-client'#10);
    exit;
  end;

  client := @svs.clients[entnum - 1];

  MSG_WriteChar(@client._message, svc_centerprint);
  MSG_WriteString(@client._message, s);
end;


(*
=================
PF_normalize

vector normalize(vector)
=================
*)

procedure PF_normalize;
var
  value1: PVector3f;
  newvalue: TVector3f;
  n: single;
begin
  value1 := G_VECTOR(OFS_PARM0);

  n := value1[0] * value1[0] + value1[1] * value1[1] + value1[2] * value1[2];

  if n = 0 then
  begin
    newvalue[0] := 0.0;
    newvalue[1] := 0.0;
    newvalue[2] := 0.0;
  end
  else
  begin
    n := sqrt(n);
    n := 1 / n;
    newvalue[0] := value1[0] * n;
    newvalue[1] := value1[1] * n;
    newvalue[2] := value1[2] * n;
  end;

  VectorCopy(@newvalue, G_VECTOR(OFS_RETURN));
end;

(*
=================
PF_vlen

scalar vlen(vector)
=================
*)

procedure PF_vlen;
var
  value1: PVector3f;
  n: single;
begin
  value1 := G_VECTOR(OFS_PARM0);

  n := value1[0] * value1[0] + value1[1] * value1[1] + value1[2] * value1[2];
  n := sqrt(n);

  G_FLOAT(OFS_RETURN)^ := n; // JVAL handle this!
end;

(*
=================
PF_vectoyaw

float vectoyaw(vector)
=================
*)

procedure PF_vectoyaw;
var
  value1: PVector3f;
  yaw: single;
begin
  value1 := G_VECTOR(OFS_PARM0);

  if (value1[1] = 0) and (value1[0] = 0) then
    yaw := 0
  else
  begin
    yaw := intval(fatan2(value1[1], value1[0]) * 180 / M_PI);
    if yaw < 0 then
      yaw := yaw + 360;
  end;

  G_FLOAT(OFS_RETURN)^ := yaw; // JVAL handle this!
end;


(*
=================
PF_vectoangles

vector vectoangles(vector)
=================
*)

procedure PF_vectoangles;
var
  value1: PVector3f;
  fwd: single;
  yaw, pitch: single;
begin
  value1 := G_VECTOR(OFS_PARM0);

  if (value1[1] = 0) and (value1[0] = 0) then
  begin
    yaw := 0;
    if value1[2] > 0 then
      pitch := 90
    else
      pitch := 270;
  end
  else
  begin
    yaw := intval(fatan2(value1[1], value1[0]) * 180 / M_PI);
    if yaw < 0 then
      yaw := yaw + 360;

    fwd := sqrt(value1[0] * value1[0] + value1[1] * value1[1]);
    pitch := intval(fatan2(value1[2], fwd) * 180 / M_PI);
    if pitch < 0 then
      pitch := pitch + 360;
  end;

  G_FLOAT(OFS_RETURN + 0)^ := pitch;
  G_FLOAT(OFS_RETURN + 1)^ := yaw;
  G_FLOAT(OFS_RETURN + 2)^ := 0;
end;

(*
=================
PF_Random

Returns a number from 0<= num < 1

random()
=================
*)

procedure PF_random;
var
  num: single;
begin
  num := (rand and $7FFF) / $7FFF;

  G_FLOAT(OFS_RETURN)^ := num;
end;

(*
=================
PF_particle

particle(origin, color, count)
=================
*)

procedure PF_particle;
var
  org, dir: PVector3f;
  color: single;
  count: single;
begin
  org := G_VECTOR(OFS_PARM0);
  dir := G_VECTOR(OFS_PARM1);
  color := G_FLOAT(OFS_PARM2)^;
  count := G_FLOAT(OFS_PARM3)^;
  SV_StartParticle(org, dir, intval(color), intval(count));
end;


(*
=================
PF_ambientsound

=================
*)

procedure PF_ambientsound;
var
  check: PPChar;
  samp: PChar;
  pos: PVector3f;
  vol, attenuation: single;
  i, soundnum: integer;
begin
  pos := G_VECTOR(OFS_PARM0);
  samp := G_STRING(OFS_PARM1);
  vol := G_FLOAT(OFS_PARM2)^;
  attenuation := G_FLOAT(OFS_PARM3)^;

// check to see if samp was properly precached
  check := @sv.sound_precache[0];
  soundnum := 0;
  while boolval(check^) do
  begin
    if strcmp(check^, samp) = 0 then
      break;
    inc(check);
    inc(soundnum);
  end;

  if not boolval(check^) then
  begin
    Con_Printf('no precache: %s'#10, [samp]);
    exit;
  end;

// add an svc_spawnambient command to the level signon packet

  MSG_WriteByte(@sv.signon, svc_spawnstaticsound);
  for i := 0 to 2 do
    MSG_WriteCoord(@sv.signon, pos[i]);

  MSG_WriteByte(@sv.signon, soundnum);

  MSG_WriteByte(@sv.signon, intval(vol * 255));
  MSG_WriteByte(@sv.signon, intval(attenuation * 64));

end;

(*
=================
PF_sound

Each entity can have eight independant sound sources, like voice,
weapon, feet, etc.

Channel 0 is an auto-allocate channel, the others override anything
allready running on that entity/channel pair.

An attenuation of 0 will play full volume everywhere in the level.
Larger attenuations will drop off.

=================
*)

procedure PF_sound;
var
  sample: PChar;
  channel: integer;
  entity: Pedict_t;
  volume: integer;
  attenuation: single;
begin
  entity := G_EDICT(OFS_PARM0);
  channel := intval(G_FLOAT(OFS_PARM1)^);
  sample := G_STRING(OFS_PARM2);
  volume := intval(G_FLOAT(OFS_PARM3)^ * 255);
  attenuation := G_FLOAT(OFS_PARM4)^;

  if (volume < 0) or (volume > 255) then
    Sys_Error('SV_StartSound: volume = %d', [volume]);

  if (attenuation < 0) or (attenuation > 4) then
    Sys_Error('SV_StartSound: attenuation = %f', [attenuation]);

  if (channel < 0) or (channel > 7) then
    Sys_Error('SV_StartSound: channel = %d', [channel]);

  SV_StartSound(entity, channel, sample, volume, attenuation);
end;

(*
=================
PF_break

break()
=================
*)

procedure PF_break;
begin
  Con_Printf('break statement'#10);
// *(int *)-4 = 0;  // dump to debugger // JVAL removed
//  PR_RunError ("break statement");
end;

(*
=================
PF_traceline

Used for use tracing and shot targeting
Traces are blocked by bbox and exact bsp entityes, and also slide box entities
if the tryents flag is set.

traceline (vector1, vector2, tryents)
=================
*)

procedure PF_traceline;
var
  v1, v2: PVector3f;
  trace: trace_t;
  nomonsters: integer;
  ent: Pedict_t;
begin
  v1 := G_VECTOR(OFS_PARM0);
  v2 := G_VECTOR(OFS_PARM1);
  nomonsters := intval(G_FLOAT(OFS_PARM2)^);
  ent := G_EDICT(OFS_PARM3);

  trace := SV_MoveEdict(v1, @vec3_origin, @vec3_origin, v2, nomonsters, ent);

  pr_global_struct.trace_allsolid := floatval(trace.allsolid);
  pr_global_struct.trace_startsolid := floatval(trace.startsolid);
  pr_global_struct.trace_fraction := trace.fraction;
  pr_global_struct.trace_inwater := floatval(trace.inwater);
  pr_global_struct.trace_inopen := floatval(trace.inopen);
  VectorCopy(@trace.endpos[0], @pr_global_struct.trace_endpos[0]);
  VectorCopy(@trace.plane.normal[0], @pr_global_struct.trace_plane_normal[0]);
  pr_global_struct.trace_plane_dist := trace.plane.dist;
  if boolval(trace.ent) then
    pr_global_struct.trace_ent := EDICT_TO_PROG(trace.ent)
  else
    pr_global_struct.trace_ent := EDICT_TO_PROG(sv.edicts);
end;

(*
=================
PF_checkpos

Returns true if the given entity can move to the given position from it's
current position by walking or rolling.
FIXME: make work...
scalar checkpos (entity, vector)
=================
*)

procedure PF_checkpos;
begin
end;

//============================================================================

var
  checkpvs: array[0..MAX_MAP_LEAFS div 8 - 1] of byte;

function PF_newcheckclient(check: integer): integer;
var
  i: integer;
  pvs: PByteArray;
  ent: Pedict_t;
  leaf: Pmleaf_t;
  org: TVector3f;
begin
// cycle to the next one

  if check < 1 then
    check := 1;
  if check > svs.maxclients then
    check := svs.maxclients;

  if check = svs.maxclients then
    i := 0
  else
    i := check;

  ent := nil; // JVAL avoid compiler warning
  while true do // JVAL check!
  begin
    inc(i);

    if i = svs.maxclients + 1 then
      i := 1;

    ent := EDICT_NUM(i);

    if i = check then
      break; // didn't find anything else

    if ent.free then
      continue;
    if ent.v.health <= 0 then
      continue;

    if (intval(ent.v.flags) and FL_NOTARGET) <> 0 then
      continue;

  // anything that is a client, or has a client as an enemy
    break;
  end;

// get the PVS for the entity
  VectorAdd(@ent.v.origin, @ent.v.view_ofs, @org);
  leaf := Mod_PointInLeaf(@org, sv.worldmodel);
  pvs := Mod_LeafPVS(leaf, sv.worldmodel);
  memcpy(@checkpvs, pvs, (sv.worldmodel.numleafs + 7) div 8);

  result := i;
end;

(*
=================
PF_checkclient

Returns a client (or object that has a client enemy) that would be a
valid target.

If there are more than one valid options, they are cycled each frame

If (self.origin + self.viewofs) is not in the PVS of the current target,
it is not returned at all.

name checkclient ()
=================
*)
const
  MAX_CHECK = 16;

var
  c_invis, c_notvis: integer;

procedure PF_checkclient;
var
  ent, self: Pedict_t;
  leaf: Pmleaf_t;
  l: integer;
  view: TVector3f;
begin
// find a new check if on a new frame
  if sv.time - sv.lastchecktime >= 0.1 then
  begin
    sv.lastcheck := PF_newcheckclient(sv.lastcheck);
    sv.lastchecktime := sv.time;
  end;

// return check if it might be visible
  ent := EDICT_NUM(sv.lastcheck);
  if ent.free or (ent.v.health <= 0) then
  begin
    RETURN_EDICT(sv.edicts);
    exit;
  end;

// if current entity can't possibly see the check entity, return 0
  self := PROG_TO_EDICT(pr_global_struct.self);
  VectorAdd(@self.v.origin, @self.v.view_ofs, @view);
  leaf := Mod_PointInLeaf(@view, sv.worldmodel);
  l := (integer(leaf) - integer(sv.worldmodel.leafs)) div SizeOf(mleaf_t) - 1;
  if (l < 0) or not boolval(checkpvs[l div 8] and (1 shl (l and 7))) then
  begin
    inc(c_notvis);
    RETURN_EDICT(sv.edicts);
    exit;
  end;

// might be able to see it
  inc(c_invis);
  RETURN_EDICT(ent);
end;

//============================================================================


(*
=================
PF_stuffcmd

Sends text over to the client's execution buffer

stuffcmd (clientent, value)
=================
*)

procedure PF_stuffcmd;
var
  entnum: integer;
  str: PChar;
  old: Pclient_t;
begin
  entnum := G_EDICTNUM(OFS_PARM0);
  if (entnum < 1) or (entnum > svs.maxclients) then
    PR_RunError('Parm 0 not a client');
  str := G_STRING(OFS_PARM1);

  old := host_client;
  host_client := @svs.clients[entnum - 1];
  Host_ClientCommands('%s', [str]);
  host_client := old;
end;

(*
=================
PF_localcmd

Sends text over to the client's execution buffer

localcmd (string)
=================
*)

procedure PF_localcmd;
var
  str: PChar;
begin
  str := G_STRING(OFS_PARM0);
  Cbuf_AddText(str);
end;

(*
=================
PF_cvar

float cvar (string)
=================
*)

procedure PF_cvar;
var
  str: PChar;
begin
  str := G_STRING(OFS_PARM0);

  G_FLOAT(OFS_RETURN)^ := Cvar_VariableValue(str);
end;

(*
=================
PF_cvar_set

float cvar (string)
=================
*)

procedure PF_cvar_set;
var
  v, val: PChar;
begin
  v := G_STRING(OFS_PARM0);
  val := G_STRING(OFS_PARM1);

  Cvar_Set(v, val);
end;

(*
=================
PF_findradius

Returns a chain of entities that have origins within a spherical area

findradius (origin, radius)
=================
*)

procedure PF_findradius;
var
  ent, chain: Pedict_t;
  rad: single;
  org: PVector3f;
  eorg: TVector3f;
  i, j: integer;
begin
  chain := Pedict_t(sv.edicts);

  org := G_VECTOR(OFS_PARM0);
  rad := G_FLOAT(OFS_PARM1)^;

  ent := sv.edicts; // JVAL check!
  for i := 1 to sv.num_edicts - 1 do
  begin
    ent := NEXT_EDICT(ent);
    if ent.free then
      continue;
    if ent.v.solid = SOLID_NOT then
      continue;
    for j := 0 to 2 do
      eorg[j] := org[j] - (ent.v.origin[j] + (ent.v.mins[j] + ent.v.maxs[j]) * 0.5);
    if VectorLength(@eorg) > rad then
      continue;

    ent.v.chain := EDICT_TO_PROG(chain);
    chain := ent;
  end;

  RETURN_EDICT(chain);
end;


(*
=========
PF_dprint
=========
*)

procedure PF_dprint;
begin
  Con_DPrintf('%s', [PF_VarString(0)]);
end;

var
  pr_string_temp: array[0..127] of char;

procedure PF_ftos;
var
  v: single;
begin
  v := G_FLOAT(OFS_PARM0)^;

  if v = intval(v) then
    sprintf(pr_string_temp, '%d', [intval(v)])
  else
    sprintf(pr_string_temp, '%5.1f', [v]);
  G_INT(OFS_RETURN)^ := integer(@pr_string_temp) - integer(pr_strings); // ?????
end;

procedure PF_fabs;
var
  v: single;
begin
  v := G_FLOAT(OFS_PARM0)^;
  G_FLOAT(OFS_RETURN)^ := abs(v);
end;

procedure PF_vtos;
begin
  sprintf(pr_string_temp, '''%5.1f %5.1f %5.1f''', [G_VECTOR(OFS_PARM0)[0], G_VECTOR(OFS_PARM0)[1], G_VECTOR(OFS_PARM0)[2]]);
  G_INT(OFS_RETURN)^ := integer(@pr_string_temp) - integer(@pr_strings); // JVAL check!
end;

procedure PF_Spawn;
var
  ed: Pedict_t;
begin
  ed := ED_Alloc;
  RETURN_EDICT(ed);
end;

procedure PF_Remove;
var
  ed: Pedict_t;
begin
  ed := G_EDICT(OFS_PARM0);
  ED_Free(ed);
end;


// entity (entity start, .string field, string match) find = #5;
procedure PF_Find;
var
  e: integer;
  f: integer;
  s, t: PChar;
  ed: Pedict_t;
begin
  e := G_EDICTNUM(OFS_PARM0);
  f := G_INT(OFS_PARM1)^;
  s := G_STRING(OFS_PARM2);
  if s = nil then
    PR_RunError('PF_Find: bad search string');

  inc(e); // JVAL check!
  while e < sv.num_edicts do
  begin
    ed := EDICT_NUM(e);
    if ed.free then
    begin
      inc(e);
      continue;
    end;
    t := E_STRING(ed, f);
    if t = nil then
    begin
      inc(e);
      continue;
    end;
    if strcmp(t, s) = 0 then
    begin
      RETURN_EDICT(ed);
      exit;
    end;
    inc(e);
  end;

  RETURN_EDICT(sv.edicts);
end;

procedure PR_CheckEmptyString(s: PChar);
begin
  if s[0] <= ' ' then
    PR_RunError('Bad string');
end;

procedure PF_precache_file;
begin // precache_file is only used to copy files with qcc, it does nothing
  G_INT(OFS_RETURN)^ := G_INT(OFS_PARM0)^;
end;

procedure PF_precache_sound;
var
  s: PChar;
  i: integer;
begin
  if sv.state <> ss_loading then
    PR_RunError('PF_Precache_*: Precache can only be done in spawn functions');

  s := G_STRING(OFS_PARM0);
  G_INT(OFS_RETURN)^ := G_INT(OFS_PARM0)^;
  PR_CheckEmptyString(s);

  for i := 0 to MAX_SOUNDS - 1 do
  begin
    if sv.sound_precache[i] = nil then
    begin
      sv.sound_precache[i] := s;
      exit;
    end;
    if strcmp(sv.sound_precache[i], s) = 0 then
      exit;
  end;
  PR_RunError('PF_precache_sound: overflow');
end;

procedure PF_precache_model;
var
  s: PChar;
  i: integer;
begin
  if sv.state <> ss_loading then
    PR_RunError('PF_Precache_*: Precache can only be done in spawn functions');

  s := G_STRING(OFS_PARM0);
  G_INT(OFS_RETURN)^ := G_INT(OFS_PARM0)^;
  PR_CheckEmptyString(s);

  for i := 0 to MAX_MODELS - 1 do
  begin
    if sv.model_precache[i] = nil then
    begin
      sv.model_precache[i] := s;
      sv.models[i] := Mod_ForName(s, true);
      exit;
    end;
    if strcmp(sv.model_precache[i], s) = 0 then
      exit;
  end;
  PR_RunError('PF_precache_model: overflow');
end;


procedure PF_coredump;
begin
  ED_PrintEdicts;
end;

procedure PF_traceon;
begin
  pr_trace := true;
end;

procedure PF_traceoff;
begin
  pr_trace := false;
end;

procedure PF_eprint;
begin
  ED_PrintNum(G_EDICTNUM(OFS_PARM0));
end;

(*
===============
PF_walkmove

float(float yaw, float dist) walkmove
===============
*)

procedure PF_walkmove;
var
  ent: Pedict_t;
  yaw, dist: single;
  move: TVector3f;
  oldf: Pdfunction_t;
  oldself: integer;
begin
  ent := PROG_TO_EDICT(pr_global_struct.self);
  yaw := G_FLOAT(OFS_PARM0)^;
  dist := G_FLOAT(OFS_PARM1)^;

  if intval(ent.v.flags) and (FL_ONGROUND or FL_FLY or FL_SWIM) = 0 then // JVAL check!
  begin
    G_FLOAT(OFS_RETURN)^ := 0;
    exit;
  end;

  yaw := yaw * M_PI * 2 / 360;

  move[0] := cos(yaw) * dist; // JVAL SinCos ??
  move[1] := sin(yaw) * dist;
  move[2] := 0;

// save program state, because SV_movestep may call other progs
  oldf := pr_xfunction;
  oldself := pr_global_struct.self;

  G_FLOAT(OFS_RETURN)^ := floatval(SV_movestep(ent, @move, true));


// restore program state
  pr_xfunction := oldf;
  pr_global_struct.self := oldself;
end;

(*
===============
PF_droptofloor

void() droptofloor
===============
*)

procedure PF_droptofloor;
var
  ent: Pedict_t;
  _end: TVector3f;
  trace: trace_t;
begin
  ent := PROG_TO_EDICT(pr_global_struct.self);

  VectorCopy(@ent.v.origin, @_end);
  _end[2] := _end[2] - 256;

  trace := SV_MoveEdict(@ent.v.origin, @ent.v.mins, @ent.v.maxs, @_end, 0, ent);

  if (trace.fraction = 1) or trace.allsolid then
    G_FLOAT(OFS_RETURN)^ := 0
  else
  begin
    VectorCopy(@trace.endpos, @ent.v.origin);
    SV_LinkEdict(ent, false);
    ent.v.flags := intval(ent.v.flags) or FL_ONGROUND;
    ent.v.groundentity := EDICT_TO_PROG(trace.ent);
    G_FLOAT(OFS_RETURN)^ := 1;
  end;
end;

(*
===============
PF_lightstyle

void(float style, string value) lightstyle
===============
*)

procedure PF_lightstyle;
var
  style: integer;
  val: PChar;
  client: Pclient_t;
  j: integer;
begin
  style := intval(G_FLOAT(OFS_PARM0)^);
  val := G_STRING(OFS_PARM1);

// change the string in sv
  sv.lightstyles[style] := val;

// send message to all clients on this server
  if sv.state <> ss_active then
    exit;

  client := @svs.clients[0];
  for j := 0 to svs.maxclients - 1 do
  begin
    if client.active or client.spawned then
    begin
      MSG_WriteChar(@client._message, svc_lightstyle);
      MSG_WriteChar(@client._message, style);
      MSG_WriteString(@client._message, val);
    end;
    inc(client);
  end;
end;

procedure PF_rint;
var
  f: single;
begin
  f := G_FLOAT(OFS_PARM0)^;
  if f > 0 then
    G_FLOAT(OFS_RETURN)^ := intval(f + 0.5)
  else
    G_FLOAT(OFS_RETURN)^ := intval(f - 0.5);
end;

procedure PF_floor;
begin
  G_FLOAT(OFS_RETURN)^ := floor(G_FLOAT(OFS_PARM0)^);
end;

procedure PF_ceil;
begin
  G_FLOAT(OFS_RETURN)^ := ceil(G_FLOAT(OFS_PARM0)^);
end;


(*
=============
PF_checkbottom
=============
*)

procedure PF_checkbottom;
var
  ent: Pedict_t;
begin
  ent := G_EDICT(OFS_PARM0);

  G_FLOAT(OFS_RETURN)^ := floatval(SV_CheckBottom(ent));
end;

(*
=============
PF_pointcontents
=============
*)

procedure PF_pointcontents;
var
  v: PVector3f;
begin
  v := G_VECTOR(OFS_PARM0);

  G_FLOAT(OFS_RETURN)^ := SV_PointContents(v);
end;

(*
=============
PF_nextent

entity nextent(entity)
=============
*)

procedure PF_nextent;
var
  i: integer;
  ent: Pedict_t;
begin
  i := G_EDICTNUM(OFS_PARM0);
  while true do
  begin
    inc(i);
    if i = sv.num_edicts then
    begin
      RETURN_EDICT(sv.edicts);
      exit;
    end;
    ent := EDICT_NUM(i);
    if not ent.free then
    begin
      RETURN_EDICT(ent);
      exit;
    end;
  end;
end;

(*
=============
PF_aim

Pick a vector for the player to shoot along
vector aim(entity, missilespeed)
=============
*)

procedure PF_aim;
label
  continue1;
var
  ent, check, bestent: Pedict_t;
  start, dir, _end, bestdir: TVector3f;
  i, j: integer;
  tr: trace_t;
  dist, bestdist: single;
begin
  ent := G_EDICT(OFS_PARM0);

  VectorCopy(@ent.v.origin, @start);
  start[2] := start[2] + 20;

// try sending a trace straight
  VectorCopy(@pr_global_struct.v_forward, @dir);
  VectorMA(@start, 2048, @dir, @_end);
  tr := SV_MoveEdict(@start, @vec3_origin, @vec3_origin, @_end, 0, ent);
  if (tr.ent <> nil) and (tr.ent.v.takedamage = DAMAGE_AIM) and
    ((teamplay.value = 0) or (ent.v.team <= 0) or (ent.v.team <> tr.ent.v.team)) then
  begin
    VectorCopy(@pr_global_struct.v_forward, G_VECTOR(OFS_RETURN));
    exit;
  end;


// try all possible entities
  VectorCopy(@dir, @bestdir);
  bestdist := sv_aim.value;
  bestent := nil;

  check := NEXT_EDICT(sv.edicts);
  for i := 1 to sv.num_edicts - 1 do
  begin
    if check.v.takedamage <> DAMAGE_AIM then
      goto continue1;
    if check = ent then
      goto continue1;
    if (teamplay.value <> 0) and (ent.v.team > 0) and (ent.v.team = check.v.team) then
      goto continue1; // don't aim at teammate
    for j := 0 to 2 do
      _end[j] := check.v.origin[j] + 0.5 * (check.v.mins[j] + check.v.maxs[j]);
    VectorSubtract(@_end, @start, @dir);
    VectorNormalize(@dir);
    dist := VectorDotProduct(@dir, @pr_global_struct.v_forward);
    if dist < bestdist then
      goto continue1; // to far to turn
    tr := SV_MoveEdict(@start, @vec3_origin, @vec3_origin, @_end, 0, ent);
    if tr.ent = check then
    begin // can shoot at this one
      bestdist := dist;
      bestent := check;
    end;
    continue1:
    check := NEXT_EDICT(check);
  end;

  if bestent <> nil then
  begin
    VectorSubtract(@bestent.v.origin, @ent.v.origin, @dir);
    dist := VectorDotProduct(@dir, @pr_global_struct.v_forward);
    VectorScale(@pr_global_struct.v_forward, dist, @_end);
    _end[2] := dir[2];
    VectorNormalize(@_end);
    VectorCopy(@_end, G_VECTOR(OFS_RETURN));
  end
  else
    VectorCopy(@bestdir, G_VECTOR(OFS_RETURN));
end;

(*
==============
PF_changeyaw

This was a major timewaster in progs, so it was converted to C
==============
*)

procedure PF_changeyaw;
var
  ent: Pedict_t;
  ideal, current, move, speed: single;
begin
  ent := PROG_TO_EDICT(pr_global_struct.self);
  current := anglemod(ent.v.angles[1]);
  ideal := ent.v.ideal_yaw;
  speed := ent.v.yaw_speed;

  if current = ideal then
    exit;
  move := ideal - current;
  if ideal > current then
  begin
    if move >= 180 then
      move := move - 360;
  end
  else
  begin
    if move <= -180 then
      move := move + 360;
  end;
  if move > 0 then
  begin
    if move > speed then
      move := speed;
  end
  else
  begin
    if move < -speed then
      move := -speed;
  end;

  ent.v.angles[1] := anglemod(current + move);
end;


(*
===============================================================================

MESSAGE WRITING

===============================================================================
*)

const
  MSG_BROADCAST = 0; // unreliable to all
  MSG_ONE = 1; // reliable to one (msg_entity)
  MSG_ALL = 2; // reliable to all
  MSG_INIT = 3; // write to the init string

function WriteDest: Psizebuf_t;
var
  entnum: integer;
  dest: integer;
  ent: Pedict_t;
begin
  dest := intval(G_FLOAT(OFS_PARM0)^);
  case dest of
    MSG_BROADCAST:
      begin
        result := @sv.datagram;
      end;

    MSG_ONE:
      begin
        ent := PROG_TO_EDICT(pr_global_struct.msg_entity);
        entnum := NUM_FOR_EDICT(ent);
        if (entnum < 1) or (entnum > svs.maxclients) then
          PR_RunError('WriteDest: not a client');
        result := @svs.clients[entnum - 1]._message;
      end;

    MSG_ALL:
      begin
        result := @sv.reliable_datagram;
      end;

    MSG_INIT:
      begin
        result := @sv.signon;
      end;

  else
    begin
      PR_RunError('WriteDest: bad destination');
      result := nil;
    end;
  end;
end;

procedure PF_WriteByte;
begin
  MSG_WriteByte(WriteDest, intval(G_FLOAT(OFS_PARM1)^));
end;

procedure PF_WriteChar;
begin
  MSG_WriteChar(WriteDest, intval(G_FLOAT(OFS_PARM1)^));
end;

procedure PF_WriteShort;
begin
  MSG_WriteShort(WriteDest, intval(G_FLOAT(OFS_PARM1)^));
end;

procedure PF_WriteLong;
begin
  MSG_WriteLong(WriteDest, intval(G_FLOAT(OFS_PARM1)^));
end;

procedure PF_WriteAngle;
begin
  MSG_WriteAngle(WriteDest, G_FLOAT(OFS_PARM1)^);
end;

procedure PF_WriteCoord;
begin
  MSG_WriteCoord(WriteDest, G_FLOAT(OFS_PARM1)^);
end;

procedure PF_WriteString;
begin
  MSG_WriteString(WriteDest, G_STRING(OFS_PARM1));
end;


procedure PF_WriteEntity;
begin
  MSG_WriteShort(WriteDest, G_EDICTNUM(OFS_PARM1));
end;

//=============================================================================

procedure PF_makestatic;
var
  ent: Pedict_t;
  i: integer;
begin
  ent := G_EDICT(OFS_PARM0);

  MSG_WriteByte(@sv.signon, svc_spawnstatic);

  MSG_WriteByte(@sv.signon, SV_ModelIndex(pr_strings + ent.v.model)); // JVAL check!

  MSG_WriteByte(@sv.signon, intval(ent.v.frame));
  MSG_WriteByte(@sv.signon, intval(ent.v.colormap));
  MSG_WriteByte(@sv.signon, intval(ent.v.skin));
  for i := 0 to 2 do
  begin
    MSG_WriteCoord(@sv.signon, ent.v.origin[i]);
    MSG_WriteAngle(@sv.signon, ent.v.angles[i]);
  end;

// throw the entity away now
  ED_Free(ent);
end;

//=============================================================================

(*
==============
PF_setspawnparms
==============
*)

procedure PF_setspawnparms;
var
  ent: Pedict_t;
  i: integer;
  client: Pclient_t;
begin
  ent := G_EDICT(OFS_PARM0);
  i := NUM_FOR_EDICT(ent);
  if (i < 1) or (i > svs.maxclients) then
    PR_RunError('Entity is not a client');

  // copy spawn parms out of the client_t
  client := @svs.clients[i - 1]; // JVAL check!

  for i := 0 to NUM_SPAWN_PARMS - 1 do
    PFloatArray(@pr_global_struct.parm1)[i] := client.spawn_parms[i];
end;

(*
==============
PF_changelevel
==============
*)

procedure PF_changelevel;
var
  s: PChar;
begin
// make sure we don't issue two changelevels
  if svs.changelevel_issued then
    exit;
  svs.changelevel_issued := true;

  s := G_STRING(OFS_PARM0);
  Cbuf_AddText(va('changelevel %s'#10, [s]));
end;

procedure PF_Fixme;
begin
  PR_RunError('unimplemented bulitin');
end;


procedure PR_InitBuiltIns;
begin
  pr_builtins := @pr_builtin[0];

  pr_builtin[0] := @PF_Fixme;
  pr_builtin[1] := @PF_makevectors; // void(entity e)  makevectors     = #1;
  pr_builtin[2] := @PF_setorigin; // void(entity e, vector o) setorigin  = #2;
  pr_builtin[3] := @PF_setmodel; // void(entity e, string m) setmodel  = #3;
  pr_builtin[4] := @PF_setsize; // void(entity e, vector min, vector max) setsize = #4;
  pr_builtin[5] := @PF_Fixme; // void(entity e, vector min, vector max) setabssize = #5;
  pr_builtin[6] := @PF_break; // void() break            = #6;
  pr_builtin[7] := @PF_random; // float() random            = #7;
  pr_builtin[8] := @PF_sound; // void(entity e, float chan, string samp) sound = #8;
  pr_builtin[9] := @PF_normalize; // vector(vector v) normalize      = #9;
  pr_builtin[10] := @PF_error; // void(string e) error        = #10;
  pr_builtin[11] := @PF_objerror; // void(string e) objerror        = #11;
  pr_builtin[12] := @PF_vlen; // float(vector v) vlen        = #12;
  pr_builtin[13] := @PF_vectoyaw; // float(vector v) vectoyaw    = #13;
  pr_builtin[14] := @PF_Spawn; // entity() spawn            = #14;
  pr_builtin[15] := @PF_Remove; // void(entity e) remove        = #15;
  pr_builtin[16] := @PF_traceline; // float(vector v1, vector v2, float tryents) traceline = #16;
  pr_builtin[17] := @PF_checkclient; // entity() clientlist          = #17;
  pr_builtin[18] := @PF_Find; // entity(entity start, .string fld, string match) find = #18;
  pr_builtin[19] := @PF_precache_sound; // void(string s) precache_sound    = #19;
  pr_builtin[20] := @PF_precache_model; // void(string s) precache_model    = #20;
  pr_builtin[21] := @PF_stuffcmd; // void(entity client, string s)stuffcmd = #21;
  pr_builtin[22] := @PF_findradius; // entity(vector org, float rad) findradius = #22;
  pr_builtin[23] := @PF_bprint; // void(string s) bprint        = #23;
  pr_builtin[24] := @PF_sprint; // void(entity client, string s) sprint = #24;
  pr_builtin[25] := @PF_dprint; // void(string s) dprint        = #25;
  pr_builtin[26] := @PF_ftos; // void(string s) ftos        = #26;
  pr_builtin[27] := @PF_vtos; // void(string s) vtos        = #27;
  pr_builtin[28] := @PF_coredump;
  pr_builtin[29] := @PF_traceon;
  pr_builtin[30] := @PF_traceoff;
  pr_builtin[31] := @PF_eprint; // void(entity e) debug print an entire entity
  pr_builtin[32] := @PF_walkmove; // float(float yaw, float dist) walkmove
  pr_builtin[33] := @PF_Fixme; // float(float yaw, float dist) walkmove
  pr_builtin[34] := @PF_droptofloor;
  pr_builtin[35] := @PF_lightstyle;
  pr_builtin[36] := @PF_rint;
  pr_builtin[37] := @PF_floor;
  pr_builtin[38] := @PF_ceil;
  pr_builtin[39] := @PF_Fixme;
  pr_builtin[40] := @PF_checkbottom;
  pr_builtin[41] := @PF_pointcontents;
  pr_builtin[42] := @PF_Fixme;
  pr_builtin[43] := @PF_fabs;
  pr_builtin[44] := @PF_aim;
  pr_builtin[45] := @PF_cvar;
  pr_builtin[46] := @PF_localcmd;
  pr_builtin[47] := @PF_nextent;
  pr_builtin[48] := @PF_particle;
  pr_builtin[49] := @PF_changeyaw;
  pr_builtin[50] := @PF_Fixme;
  pr_builtin[51] := @PF_vectoangles;

  pr_builtin[52] := @PF_WriteByte;
  pr_builtin[53] := @PF_WriteChar;
  pr_builtin[54] := @PF_WriteShort;
  pr_builtin[55] := @PF_WriteLong;
  pr_builtin[56] := @PF_WriteCoord;
  pr_builtin[57] := @PF_WriteAngle;
  pr_builtin[58] := @PF_WriteString;
  pr_builtin[59] := @PF_WriteEntity;

  pr_builtin[60] := @PF_Fixme;
  pr_builtin[61] := @PF_Fixme;
  pr_builtin[62] := @PF_Fixme;
  pr_builtin[63] := @PF_Fixme;
  pr_builtin[64] := @PF_Fixme;
  pr_builtin[65] := @PF_Fixme;
  pr_builtin[66] := @PF_Fixme;

  pr_builtin[67] := @SV_MoveToGoal;
  pr_builtin[68] := @PF_precache_file;
  pr_builtin[69] := @PF_makestatic;

  pr_builtin[70] := @PF_changelevel;
  pr_builtin[71] := @PF_Fixme;

  pr_builtin[72] := @PF_cvar_set;
  pr_builtin[73] := @PF_centerprint;

  pr_builtin[74] := @PF_ambientsound;

  pr_builtin[75] := @PF_precache_model;
  pr_builtin[76] := @PF_precache_sound; // precache_sound2 is different only for qcc
  pr_builtin[77] := @PF_precache_file;

  pr_builtin[78] := @PF_setspawnparms;
end;

end.

