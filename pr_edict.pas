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

unit pr_edict;

// sv_edict.c -- entity dictionary

interface

uses
  q_delphi,
  progdefs,
  progs_h,
  pr_comp;

procedure ED_WriteGlobals(var f: text);
procedure ED_Write(var f: text; ed: Pedict_t); //JVAL SOS file or text???
procedure ED_ParseGlobals(data: PChar);
function ED_ParseEdict(data: PChar; ent: Pedict_t): PChar;
procedure ED_Print(ed: Pedict_t);
procedure ED_Free(ed: Pedict_t);
function ED_Alloc: Pedict_t;
procedure ED_PrintEdicts;
procedure ED_PrintNum(ent: integer);
procedure ED_LoadFromFile(data: PChar);
function ED_ParseEpair(base: pointer; key: Pddef_t; s: PChar): qboolean;

function GetEdictFieldValue(ed: Pedict_t; field: PChar): Peval_t;

procedure PR_Init;
function PR_GlobalString(ofs: integer): PChar;
function PR_GlobalStringNoContents(ofs: integer): PChar;
procedure PR_LoadProgs;

var
  pr_global_struct: Pglobalvars_t;
  progs: Pdprograms_t;
  pr_functions: Pdfunction_tArray;
  pr_strings: PChar;
  pr_statements: Pdstatement_tArray;
  pr_globals: PFloatArray; // same as pr_global_struct
  pr_edict_size: integer; // in bytes
  pr_crc: unsigned_short;


implementation

uses
  q_vector,
  cvar,
  sv_main,
  quakedef,
  sys_win,
  world,
  mathlib,
  console,
  common,
  cmd,
  server_h,
  host,
  host_h,
  host_cmd,
  zone,
  pr_exec,
  crc;

var
  pr_fielddefs: Pddef_tArray;
  pr_globaldefs: Pddef_tArray;

const
  type_size: array[0..7] of integer = (
    1, SizeOf(string_t) div 4, 1, 3, 1, 1, SizeOf(func_t) div 4, SizeOf(pointer) div 4);

var
  nomonsters: cvar_t = (name: 'nomonsters'; text: '0');
  gamecfg: cvar_t = (name: 'gamecfg'; text: '0');
  scratch1: cvar_t = (name: 'scratch1'; text: '0');
  scratch2: cvar_t = (name: 'scratch2'; text: '0');
  scratch3: cvar_t = (name: 'scratch3'; text: '0');
  scratch4: cvar_t = (name: 'scratch4'; text: '0');
  savedgamecfg: cvar_t = (name: 'savedgamecfg'; text: '0'; archive: true);
  saved1: cvar_t = (name: 'saved1'; text: '0'; archive: true);
  saved2: cvar_t = (name: 'saved2'; text: '0'; archive: true);
  saved3: cvar_t = (name: 'saved3'; text: '0'; archive: true);
  saved4: cvar_t = (name: 'saved4'; text: '0'; archive: true);

const
  MAX_FIELD_LEN = 64;
  GEFV_CACHESIZE = 2;

type
  gefv_cache = record
    pcache: Pddef_t;
    field: array[0..MAX_FIELD_LEN - 1] of char;
  end;

var
  gefvCache: array[0..GEFV_CACHESIZE - 1] of gefv_cache;

(*
=================
ED_ClearEdict

Sets everything to NULL
=================
*)

procedure ED_ClearEdict(e: Pedict_t);
begin
  memset(@e.v, 0, progs.entityfields * 4);
  e.free := false;
end;

(*
=================
ED_Alloc

Either finds a free edict, or allocates a new one.
Try to avoid reusing an entity that was recently freed, because it
can cause the client to think the entity morphed into something else
instead of being removed and recreated, which can cause interpolated
angles and bad trails.
=================
*)

function ED_Alloc: Pedict_t;
var
  i: integer;
begin
  i := svs.maxclients + 1;
  while i < sv.num_edicts do
  begin
    result := EDICT_NUM(i);
    // the first couple seconds of server time can involve a lot of
    // freeing and allocating, so relax the replacement policy
    if result.free and ((result.freetime < 2) or (sv.time - result.freetime > 0.5)) then
    begin
      ED_ClearEdict(result);
      exit;
    end;
    inc(i);
  end;

  if i = MAX_EDICTS then
    Sys_Error('ED_Alloc: no free edicts');

  inc(sv.num_edicts);
  result := EDICT_NUM(i);
  ED_ClearEdict(result);
end;

(*
=================
ED_Free

Marks the edict as free
FIXME: walk all entities and NULL out references to this entity
=================
*)

procedure ED_Free(ed: Pedict_t);
begin
  SV_UnlinkEdict(ed); // unlink from world bsp

  ed.free := true;
  ed.v.model := 0;
  ed.v.takedamage := 0;
  ed.v.modelindex := 0;
  ed.v.colormap := 0;
  ed.v.skin := 0;
  ed.v.frame := 0;
  VectorCopy(@vec3_origin, @ed.v.origin);
  VectorCopy(@vec3_origin, @ed.v.angles);
  ed.v.nextthink := -1;
  ed.v.solid := 0;

  ed.freetime := sv.time;
end;

//===========================================================================

(*
============
ED_GlobalAtOfs
============
*)

function ED_GlobalAtOfs(ofs: integer): Pddef_t;
var
  i: integer;
begin
  for i := 0 to progs.numglobaldefs - 1 do
  begin
    result := @pr_globaldefs[i];
    if result.ofs = ofs then
      exit;
  end;
  result := nil;
end;

(*
============
ED_FieldAtOfs
============
*)

function ED_FieldAtOfs(ofs: integer): Pddef_t;
var
  i: integer;
begin
  for i := 0 to progs.numfielddefs - 1 do
  begin
    result := @pr_fielddefs[i];
    if result.ofs = ofs then
      exit;
  end;
  result := nil;
end;

(*
============
ED_FindField
============
*)

function ED_FindField(name: PChar): Pddef_t;
var
  i: integer;
begin
  for i := 0 to progs.numfielddefs - 1 do
  begin
    result := @pr_fielddefs[i];
    if strcmp(@pr_strings[result.s_name], name) = 0 then // JVAL SOS
      exit;
  end;
  result := nil;
end;


(*
============
ED_FindGlobal
============
*)

function ED_FindGlobal(name: PChar): Pddef_t;
var
  i: integer;
begin
  for i := 0 to progs.numglobaldefs - 1 do
  begin
    result := @pr_globaldefs[i];
    if strcmp(@pr_strings[result.s_name], name) = 0 then // JVAL SOS
      exit;
  end;
  result := nil;
end;


(*
============
ED_FindFunction
============
*)

function ED_FindFunction(name: PChar): Pdfunction_t;
var
  i: integer;
begin
  for i := 0 to progs.numfunctions - 1 do
  begin
    result := @pr_functions[i];
    if strcmp(@pr_strings[result.s_name], name) = 0 then
      exit;
  end;
  result := nil;
end;


var
  rep_GetEdictFieldValue: integer = 0;

function GetEdictFieldValue(ed: Pedict_t; field: PChar): Peval_t;
label
  done;
var
  def: Pddef_t;
  i: integer;
begin
  for i := 0 to GEFV_CACHESIZE - 1 do
  begin
    if strcmp(field, gefvCache[i].field) = 0 then
    begin
      def := gefvCache[i].pcache;
      goto done;
    end;
  end;

  def := ED_FindField(field);

  if strlen(field) < MAX_FIELD_LEN then
  begin
    gefvCache[rep_GetEdictFieldValue].pcache := def;
    strcpy(gefvCache[rep_GetEdictFieldValue].field, field);
    rep_GetEdictFieldValue := rep_GetEdictFieldValue xor 1;
  end;

  done:
  if def = nil then
    result := nil
  else
    result := Peval_t(integer(@ed.v) + def.ofs * 4); // JVAL SOS
end;


(*
============
PR_ValueString

Returns a string describing *data in a type specific manner
=============
*)
var
  line_PR_ValueString: array[0..255] of char;

function PR_ValueString(_type: etype_t; val: Peval_t): PChar;
var
  def: Pddef_t;
  f: Pdfunction_t;
begin
  _type := etype_t(ord(_type) and (not DEF_SAVEGLOBAL));

  case _type of
    ev_string:
      begin
        sprintf(line_PR_ValueString, '%s', [PChar(@pr_strings[val._string])]); // JVAL SOS
      end;

    ev_entity:
      begin
        sprintf(line_PR_ValueString, 'entity %d', [NUM_FOR_EDICT(PROG_TO_EDICT(val.edict))]);
      end;

    ev_function:
      begin
        f := @pr_functions[val.func];
        sprintf(line_PR_ValueString, '%s()', [PChar(@pr_strings[f.s_name])]);
      end;

    ev_field:
      begin
        def := ED_FieldAtOfs(val._int);
        sprintf(line_PR_ValueString, '.%s', [PChar(@pr_strings[def.s_name])]);
      end;

    ev_void:
      begin
        sprintf(line_PR_ValueString, 'void');
      end;

    ev_float:
      begin
        sprintf(line_PR_ValueString, '%5.1f', [val._float]);
      end;

    ev_vector:
      begin
        sprintf(line_PR_ValueString, '''%5.1f %5.1f %5.1f''', [val.vector[0], val.vector[1], val.vector[2]]);
      end;

    ev_pointer:
      begin
        sprintf(line_PR_ValueString, 'pointer');
      end;

  else
    begin
      sprintf(line_PR_ValueString, 'bad type %d', [Ord(_type)]);
    end;
  end;

  result := @line_PR_ValueString[0];
end;

(*
============
PR_UglyValueString

Returns a string describing *data in a type specific manner
Easier to parse than PR_ValueString
=============
*)
var
  line_PR_UglyValueString: array[0..255] of char; // JVAL mayby same buffer with above proc() ??

function PR_UglyValueString(_type: etype_t; val: Peval_t): PChar;
var
  def: Pddef_t;
  f: Pdfunction_t;
begin
  _type := etype_t(ord(_type) and (not DEF_SAVEGLOBAL));

  case _type of
    ev_string:
      begin
        sprintf(line_PR_UglyValueString, '%s', [PChar(@pr_strings[val._string])]);
      end;

    ev_entity:
      begin
        sprintf(line_PR_UglyValueString, '%d', [NUM_FOR_EDICT(PROG_TO_EDICT(val.edict))]);
      end;

    ev_function:
      begin
        f := @pr_functions[val.func];
        sprintf(line_PR_UglyValueString, '%s', [PChar(@pr_strings[f.s_name])]);
      end;

    ev_field:
      begin
        def := ED_FieldAtOfs(val._int);
        sprintf(line_PR_UglyValueString, '%s', [PChar(@pr_strings[def.s_name])]);
      end;

    ev_void:
      begin
        sprintf(line_PR_UglyValueString, 'void');
      end;

    ev_float:
      begin
        sprintf(line_PR_UglyValueString, '%f', [val._float]);
      end;

    ev_vector:
      begin
        sprintf(line_PR_UglyValueString, '%f %f %f', [val.vector[0], val.vector[1], val.vector[2]]);
      end;

  else
    begin
      sprintf(line_PR_UglyValueString, 'bad type %d', [Ord(_type)]);
    end;
  end;

  result := @line_PR_UglyValueString[0];
end;

(*
============
PR_GlobalString

Returns a string with a description and the contents of a global,
padded to 20 field width
============
*)
var
  line_PR_GlobalString: array[0..255] of char;

function PR_GlobalString(ofs: integer): PChar;
var
  s: PChar;
  i: integer;
  def: Pddef_t;
  val: pointer;
begin
  val := @pr_globals[ofs];
  def := ED_GlobalAtOfs(ofs);
  if def = nil then
    sprintf(line_PR_GlobalString, '%d(???)', [ofs])
  else
  begin
    s := PR_ValueString(etype_t(def._type), val);
    sprintf(line_PR_GlobalString, '%d(%s)%s', [ofs, PChar(@pr_strings[def.s_name]), s]);
  end;

  i := strlen(@line_PR_GlobalString[0]);
  while i < 20 do
  begin
    strcat(line_PR_GlobalString, ' ');
    inc(i);
  end;
  strcat(line_PR_GlobalString, ' ');

  result := @line_PR_GlobalString[0];
end;

var
  line_PR_GlobalStringNoContents: array[0..127] of char; // JVAL check static line_xxxx sizes!

function PR_GlobalStringNoContents(ofs: integer): PChar;
var
  i: integer;
  def: Pddef_t;
begin
  def := ED_GlobalAtOfs(ofs);
  if def = nil then
    sprintf(line_PR_GlobalStringNoContents, '%d(???)', [ofs])
  else
    sprintf(line_PR_GlobalStringNoContents, '%d(%s)', [ofs, PChar(@pr_strings[def.s_name])]); // JVAL SOS

  i := strlen(line_PR_GlobalStringNoContents); // JVAL mayby external proc() ?? for adding spaces???
  while i < 20 do
  begin
    strcat(line_PR_GlobalStringNoContents, ' ');
    inc(i);
  end;
  strcat(line_PR_GlobalStringNoContents, ' ');

  result := @line_PR_GlobalStringNoContents[0];
end;


(*
=============
ED_Print

For debugging
=============
*)

procedure ED_Print(ed: Pedict_t);
var
  l: integer;
  d: Pddef_t;
  v: PIntegerArray;
  i, j: integer;
  name: PChar;
  _type: integer;
begin
  if ed.free then
  begin
    Con_Printf('FREE'#10);
    exit;
  end;

  Con_Printf(#10'EDICT %d:'#10, [NUM_FOR_EDICT(ed)]);
  for i := 1 to progs.numfielddefs - 1 do
  begin
    d := @pr_fielddefs[i];
    name := @pr_strings[d.s_name]; // JVAL SOS, mayby @pr_strings[d.s_name] ??
    if name[strlen(name) - 2] = '_' then // JVAL mayby l = strlen(name) and check l >= 2
      continue; // skip _x, _y, _z vars

    v := PIntegerArray(integer(@ed.v) + d.ofs * 4);

  // if the value is still all 0, skip the field
    _type := d._type and (not DEF_SAVEGLOBAL);

    j := 0;
    while j < type_size[_type] do
    begin
      if v[j] <> 0 then
        break;
      inc(j);
    end;

    if j = type_size[_type] then
      continue;

    Con_Printf('%s', [name]);
    l := strlen(name);
    while l < 15 do
    begin
      Con_Printf(' ');
      inc(l);
    end;

    Con_Printf('%s'#10, [PR_ValueString(etype_t(d._type), Peval_t(v))]);
  end;
end;

(*
=============
ED_Write

For savegames
=============
*)

procedure ED_Write(var f: text; ed: Pedict_t); //JVAL SOS file or text???
var
  d: Pddef_t;
  v: PIntegerArray;
  i, j: integer;
  name: PChar;
  _type: integer;
begin
  fprintf(f, '{'#10);

  if ed.free then
  begin
    fprintf(f, '}'#10);
    exit;
  end;

  for i := 1 to progs.numfielddefs - 1 do
  begin
    d := @pr_fielddefs[i];
    name := @pr_strings[d.s_name]; // JVAL SOS
    if name[strlen(name) - 2] = '_' then // JVAL SOS l := strlen(name); if l > 2 then !
      continue; // skip _x, _y, _z vars

    v := PIntegerArray(integer(@ed.v) + d.ofs * 4);

  // if the value is still all 0, skip the field
    _type := d._type and (not DEF_SAVEGLOBAL);
    j := 0;
    while j < type_size[_type] do
    begin
      if v[j] <> 0 then
        break;
      inc(j);
    end;
    if j = type_size[_type] then
      continue;

    fprintf(f, '"%s" ', [name]);
    fprintf(f, '"%s"'#10, [PR_UglyValueString(etype_t(d._type), Peval_t(v))]);
  end;

  fprintf(f, '}'#10);
end;

procedure ED_PrintNum(ent: integer);
begin
  ED_Print(EDICT_NUM(ent));
end;

(*
=============
ED_PrintEdicts

For debugging, prints all the entities in the current server
=============
*)

procedure ED_PrintEdicts;
var
  i: integer;
begin
  Con_Printf('%d entities'#10, [sv.num_edicts]);
  for i := 0 to sv.num_edicts - 1 do
    ED_PrintNum(i);
end;

(*
=============
ED_PrintEdict_f

For debugging, prints a single edicy
=============
*)

procedure ED_PrintEdict_f;
var
  i: integer;
begin
  i := Q_atoi(Cmd_Argv_f(1));
  if i >= sv.num_edicts then
  begin
    Con_Printf('Bad edict number'#10);
    exit;
  end;
  ED_PrintNum(i);
end;

(*
=============
ED_Count

For debugging
=============
*)

procedure ED_Count;
var
  i: integer;
  ent: Pedict_t;
  active, models, solid, step: integer;
begin
  active := 0;
  models := 0;
  solid := 0;
  step := 0;

  for i := 0 to sv.num_edicts - 1 do
  begin
    ent := EDICT_NUM(i);
    if ent.free then
      continue;
    inc(active);
    if boolval(ent.v.solid) then
      inc(solid);
    if boolval(ent.v.model) then
      inc(models);
    if ent.v.movetype = MOVETYPE_STEP then
      inc(step);
  end;

  Con_Printf('num_edicts:%3d'#10, [sv.num_edicts]);
  Con_Printf('active    :%3d'#10, [active]);
  Con_Printf('view      :%3d'#10, [models]);
  Con_Printf('touch     :%3d'#10, [solid]);
  Con_Printf('step      :%3d'#10, [step]);

end;

(*
==============================================================================

          ARCHIVING GLOBALS

FIXME: need to tag constants, doesn't really work
==============================================================================
*)

(*
=============
ED_WriteGlobals
=============
*)

procedure ED_WriteGlobals(var f: text);
var
  def: Pddef_t;
  i: integer;
  name: PChar;
  _type: integer;
begin
  fprintf(f, '{'#10);

  for i := 0 to progs.numglobaldefs - 1 do
  begin
    def := @pr_globaldefs[i];
    _type := def._type;
    if not boolval(_type and DEF_SAVEGLOBAL) then
      continue;
    _type := _type and (not DEF_SAVEGLOBAL);

{    if (_type <> ev_string) and (_type <> ev_float) and (_type <> ev_entity) then
      continue;}
    if etype_t(_type) in [ev_string, ev_float, ev_entity] then
    begin
      name := @pr_strings[def.s_name];
      fprintf(f, '"%s" ', [name]);
      fprintf(f, '"%s"'#10, [PR_UglyValueString(etype_t(_type), Peval_t(@pr_globals[def.ofs]))]);
    end;
  end;
  fprintf(f, '}'#10);
end;

(*
=============
ED_ParseGlobals
=============
*)

procedure ParseError(err: PChar);
begin
  Sys_Error('ED_ParseEntity: %s', [err]);
end;

const
  rsEOFError = 'EOF without closing brace';
  rsBraceError = 'closing brace without data';

procedure ED_ParseGlobals(data: PChar);
var
  keyname: array[0..63] of char;
  key: Pddef_t;
begin
  while true do
  begin
  // parse key
    data := COM_Parse(data);
    if com_token[0] = '}' then
      break;
    if data = nil then
      ParseError(rsEOFError);

    strcpy(keyname, com_token);

  // parse value
    data := COM_Parse(data);
    if data = nil then
      ParseError(rsEOFError);

    if com_token[0] = '}' then
      ParseError(rsBraceError);

    key := ED_FindGlobal(keyname);
    if key = nil then
    begin
      Con_Printf('''%s'' is not a global'#10, [keyname]);
      continue;
    end;

    if not ED_ParseEpair(pr_globals, key, com_token) then
      Host_Error('ED_ParseGlobals: parse error');
  end;
end;

//============================================================================


(*
=============
ED_NewString
=============
*)

function ED_NewString(_string: PChar): PChar; // JVAL SOS!!!!! (\n) and (\\) convertion!
var
  _new, new_p: PChar;
  i, l: integer;
begin
  l := strlen(_string) + 1;
  _new := Hunk_Alloc(l);
  new_p := _new;

  i := 0;
  while i < l do
  begin
    if (_string[i] = '\') and (i < l - 1) then
    begin
      inc(i);
      if _string[i] = 'n' then
        new_p^ := #10
      else
        new_p^ := '\';
    end
    else
      new_p^ := _string[i];
    inc(new_p);
    inc(i);
  end;
  // JVAL mayby new_p^ := #0; ??
  result := _new;
end;


(*
=============
ED_ParseEval

Can parse either fields or globals
returns false if error
=============
*)

function ED_ParseEpair(base: pointer; key: Pddef_t; s: PChar): qboolean;
var
  i: integer;
  _string: array[0..127] of char;
  def: Pddef_t;
  v, w: PChar;
  d: pointer;
  func: Pdfunction_t;
  _type: integer;
begin
  d := pointer(integer(base) + key.ofs * SizeOf(integer)); // JVAL SOS

  _type := key._type and (not DEF_SAVEGLOBAL);
  case etype_t(_type) of
    ev_string:
      begin
        Pstring_t(d)^ := ED_NewString(s) - pr_strings; // JVAL SOS
      end;

    ev_float:
      begin
        Psingle(d)^ := atof(s);
      end;

    ev_vector:
      begin
        strcpy(_string, s);
        v := @_string[0];
        w := @_string[0];
        for i := 0 to 2 do
        begin
          while boolval(v^) and (v^ <> ' ') do
            inc(v);
          v^ := #0;
          PFloatArray(d)[i] := atof(w);
          v := @v[1];
          w := v;
        end;
      end;

    ev_entity:
      begin
        PInteger(d)^ := EDICT_TO_PROG(EDICT_NUM(atoi(s)));
      end;

    ev_field:
      begin
        def := ED_FindField(s);
        if def = nil then
        begin
          Con_Printf('Can''t find field %s'#10, [s]);
          result := false;
          exit;
        end;
        PInteger(d)^ := G_INT(def.ofs)^;
      end;

    ev_function:
      begin
        func := ED_FindFunction(s);
        if func = nil then
        begin
          Con_Printf('Can''t find function %s'#10, [s]);
          result := false;
          exit;
        end;
        Pfunc_t(d)^ := (integer(func) - integer(pr_functions)) div SizeOf(dfunction_t); //Pfunc_t(integer(func) - integer(pr_functions))^; // JVAL SOS
      end;

  end;

  result := true;
end;

(*
====================
ED_ParseEdict

Parses an edict out of the given string, returning the new position
ed should be a properly initialized empty edict.
Used for initial level load and for savegames.
====================
*)

function ED_ParseEdict(data: PChar; ent: Pedict_t): PChar;
var
  key: Pddef_t;
  anglehack: qboolean;
  init: qboolean;
  keyname: array[0..255] of char;
  n: integer;
  temp: array[0..31] of char;
begin
  init := false;

// clear it
  if ent <> sv.edicts then // hack
    memset(@ent.v, 0, progs.entityfields * 4);

// go through all the dictionary pairs
  while true do
  begin
    // parse key
    data := COM_Parse(data);
    if com_token[0] = '}' then
      break;
    if data = nil then
      ParseError(rsEOFError);

    // anglehack is to allow QuakeEd to write single scalar angles
    // and allow them to be turned into vectors. (FIXME...)
    if strcmp(com_token, 'angle') = 0 then // JVAL check
    begin
      strcpy(com_token, 'angles');
      anglehack := true;
    end
    else
      anglehack := false;

    // FIXME: change light to _light to get rid of this hack
    if strcmp(com_token, 'light') = 0 then
      strcpy(com_token, 'light_lev'); // hack for single light def

    strcpy(keyname, com_token);

    // another hack to fix heynames with trailing spaces
    n := strlen(keyname);
    while (n <> 0) and (keyname[n - 1] = ' ') do
    begin
      keyname[n - 1] := #0;
      dec(n);
    end;

    // parse value
    data := COM_Parse(data);
    if data = nil then
      ParseError(rsEOFError);

    if com_token[0] = '}' then
      ParseError(rsBraceError);

    init := true;

// keynames with a leading underscore are used for utility comments,
// and are immediately discarded by quake
    if keyname[0] = '_' then
      continue;

    key := ED_FindField(keyname);
    if key = nil then
    begin
      Con_Printf('''%s'' is not a field'#10, [keyname]);
      continue;
    end;

    if anglehack then
    begin
      strcpy(temp, com_token);
      sprintf(com_token, '0 %s 0', [temp]);
    end;

    if not ED_ParseEpair(pointer(@ent.v), key, com_token) then
      Host_Error('ED_ParseEdict: parse error');
  end;

  if not init then
    ent.free := true;

  result := data;
end;


(*
================
ED_LoadFromFile

The entities are directly placed in the array, rather than allocated with
ED_Alloc, because otherwise an error loading the map would have entity
number references out of order.

Creates a server's entity / program execution context by
parsing textual entity definitions out of an ent file.

Used for both fresh maps and savegame loads.  A fresh map would also need
to call ED_CallSpawnFunctions () to let the objects initialize themselves.
================
*)

procedure ED_LoadFromFile(data: PChar);
var
  ent: Pedict_t;
  inhibit: integer;
  func: Pdfunction_t;
begin
  ent := nil;
  inhibit := 0;
  pr_global_struct.time := sv.time;

// parse ents
  while true do
  begin
// parse the opening brace
    data := COM_Parse(data);
    if data = nil then
      break;
    if com_token[0] <> '{' then
      Sys_Error('ED_LoadFromFile: found %s when expecting {', [com_token]);

    if ent = nil then
      ent := EDICT_NUM(0)
    else
      ent := ED_Alloc;
    data := ED_ParseEdict(data, ent);

// remove things from different skill levels or deathmatch
    if deathmatch.value <> 0 then
    begin
      if (intval(ent.v.spawnflags) and SPAWNFLAG_NOT_DEATHMATCH) <> 0 then // JVAL check type casting!
      begin
        ED_Free(ent);
        inc(inhibit);
        continue;
      end;
    end
    else if ((current_skill = 0) and ((intval(ent.v.spawnflags) and SPAWNFLAG_NOT_EASY) <> 0)) or // JVAL check!
      ((current_skill = 1) and ((intval(ent.v.spawnflags) and SPAWNFLAG_NOT_MEDIUM) <> 0)) or
      ((current_skill = 2) and ((intval(ent.v.spawnflags) and SPAWNFLAG_NOT_HARD) <> 0)) then
    begin
      ED_Free(ent);
      inc(inhibit);
      continue;
    end;

//
// immediately call spawn function
//
    if ent.v.classname = 0 then
    begin
      Con_Printf('No classname for:'#10);
      ED_Print(ent);
      ED_Free(ent);
      continue;
    end;

  // look for the spawn function
    func := ED_FindFunction(@pr_strings[ent.v.classname]);

    if func = nil then
    begin
      Con_Printf('No spawn function for:'#10);
      ED_Print(ent);
      ED_Free(ent);
      continue;
    end;

    pr_global_struct.self := EDICT_TO_PROG(ent);
    PR_ExecuteProgram((integer(func) - integer(pr_functions)) div SizeOf(dfunction_t));
  end;

  Con_DPrintf('%d entities inhibited'#10, [inhibit]);
end;


(*
===============
PR_LoadProgs
===============
*)

procedure PR_LoadProgs;
var
  i: integer;
begin
// flush the non-C variable lookup cache
  for i := 0 to GEFV_CACHESIZE - 1 do
    gefvCache[i].field[0] := #0;

  CRC_Init(@pr_crc);

  progs := Pdprograms_t(COM_LoadHunkFile('progs.dat'));
  if progs = nil then
    Sys_Error('PR_LoadProgs: couldn''t load progs.dat');
  Con_DPrintf('Programs occupy %dK.'#10, [com_filesize div 1024]);

  for i := 0 to com_filesize - 1 do
    CRC_ProcessByte(@pr_crc, PByteArray(progs)[i]);

// byte swap the header
  for i := 0 to SizeOf(progs^) div 4 - 1 do // JVAL SOS (SizeOf)
    PIntegerArray(progs)[i] := LittleLong(PIntegerArray(progs)[i]);

  if progs.version <> PROG_VERSION then
    Sys_Error('progs.dat has wrong version number (%d should be %d)', [progs.version, PROG_VERSION]);
  if progs.crc <> PROGHEADER_CRC then
    Sys_Error('progs.dat system vars have been modified, progdefs.h is out of date');

  pr_functions := Pdfunction_tArray(integer(progs) + progs.ofs_functions);
  pr_strings := C_PChar(progs, progs.ofs_strings);
  pr_globaldefs := Pddef_tArray(integer(progs) + progs.ofs_globaldefs);
  pr_fielddefs := Pddef_tArray(integer(progs) + progs.ofs_fielddefs);
  pr_statements := Pdstatement_tArray(integer(progs) + progs.ofs_statements);

  pr_global_struct := Pglobalvars_t(integer(progs) + progs.ofs_globals);
  pr_globals := PFloatArray(pr_global_struct);

  pr_edict_size := progs.entityfields * 4 + SizeOf(edict_t) - SizeOf(entvars_t);

// byte swap the lumps
  for i := 0 to progs.numstatements - 1 do
  begin
    pr_statements[i].op := LittleShort(pr_statements[i].op);
    pr_statements[i].a := LittleShort(pr_statements[i].a);
    pr_statements[i].b := LittleShort(pr_statements[i].b);
    pr_statements[i].c := LittleShort(pr_statements[i].c);
  end;

  for i := 0 to progs.numfunctions - 1 do
  begin
    pr_functions[i].first_statement := LittleLong(pr_functions[i].first_statement);
    pr_functions[i].parm_start := LittleLong(pr_functions[i].parm_start);
    pr_functions[i].s_name := LittleLong(pr_functions[i].s_name);
    pr_functions[i].s_file := LittleLong(pr_functions[i].s_file);
    pr_functions[i].numparms := LittleLong(pr_functions[i].numparms);
    pr_functions[i].locals := LittleLong(pr_functions[i].locals);
  end;

  for i := 0 to progs.numglobaldefs - 1 do
  begin
    pr_globaldefs[i]._type := LittleShort(pr_globaldefs[i]._type);
    pr_globaldefs[i].ofs := LittleShort(pr_globaldefs[i].ofs);
    pr_globaldefs[i].s_name := LittleLong(pr_globaldefs[i].s_name);
  end;

  for i := 0 to progs.numfielddefs - 1 do
  begin
    pr_fielddefs[i]._type := LittleShort(pr_fielddefs[i]._type);
    if (pr_fielddefs[i]._type and DEF_SAVEGLOBAL) <> 0 then
      Sys_Error('PR_LoadProgs: pr_fielddefs[i].type & DEF_SAVEGLOBAL');
    pr_fielddefs[i].ofs := LittleShort(pr_fielddefs[i].ofs);
    pr_fielddefs[i].s_name := LittleLong(pr_fielddefs[i].s_name);
  end;

  for i := 0 to progs.numglobals - 1 do
    PIntegerArray(pr_globals)[i] := LittleLong(PIntegerArray(pr_globals)[i]);
end;


(*
===============
PR_Init
===============
*)

procedure PR_Init;
begin
  Cmd_AddCommand('edict', ED_PrintEdict_f);
  Cmd_AddCommand('edicts', ED_PrintEdicts);
  Cmd_AddCommand('edictcount', ED_Count);
  Cmd_AddCommand('profile', PR_Profile_f);
  Cvar_RegisterVariable(@nomonsters);
  Cvar_RegisterVariable(@gamecfg);
  Cvar_RegisterVariable(@scratch1);
  Cvar_RegisterVariable(@scratch2);
  Cvar_RegisterVariable(@scratch3);
  Cvar_RegisterVariable(@scratch4);
  Cvar_RegisterVariable(@savedgamecfg);
  Cvar_RegisterVariable(@saved1);
  Cvar_RegisterVariable(@saved2);
  Cvar_RegisterVariable(@saved3);
  Cvar_RegisterVariable(@saved4);
end;

initialization
  ZeroMemory(@gefvCache, SizeOf(gefvCache));

end.

