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

unit gl_mesh; // triangle model functions

interface

uses
  gl_model_h;

procedure GL_MakeAliasModelDisplayLists(m: PBSPModelFile; hdr: Paliashdr_t);

implementation

uses
  q_delphi,
  modelgen,
  console,
  quakedef,
  common,
  gl_model,
  zone;

(*
=================================================================

ALIAS MODEL DISPLAY LIST GENERATION

=================================================================
*)

var
  aliasmodel: PBSPModelFile;
  paliashdr: Paliashdr_t;

  used: array[0..8191] of integer;

// the command list holds counts and s/t values that are valid for
// every frame
  commands: array[0..8191] of integer;
  numcommands: integer;

// all frames will have their vertexes rearranged and expanded
// so they are in the order expected by the command list
  vertexorder: array[0..8191] of integer;
  numorder: integer;

  allverts: integer = 0;
  alltris: integer = 0;

  stripverts: array[0..127] of integer;
  striptris: array[0..127] of integer;
  stripcount: integer;

(*
================
StripLength
================
*)

function StripLength(starttri: integer; startv: integer): integer;
label
  nexttri,
    done,
    continue1;
var
  m1, m2: integer;
  j: integer;
  last, check: Pmtriangle_t;
  k: integer;
begin
  used[starttri] := 2;

  last := @triangles[starttri];

  stripverts[0] := last.vertindex[(startv) mod 3];
  stripverts[1] := last.vertindex[(startv + 1) mod 3];
  stripverts[2] := last.vertindex[(startv + 2) mod 3];

  striptris[0] := starttri;
  stripcount := 1;

  m1 := last.vertindex[(startv + 2) mod 3];
  m2 := last.vertindex[(startv + 1) mod 3];

  // look for a matching triangle
  nexttri:
  check := @triangles[starttri + 1];
  for j := starttri + 1 to pheader.numtris - 1 do
  begin
    if check.facesfront <> last.facesfront then
      goto continue1;
    for k := 0 to 2 do
    begin
      if check.vertindex[k] <> m1 then
        goto continue1;
      if check.vertindex[(k + 1) mod 3] <> m2 then
        goto continue1;

      // this is the next part of the fan

      // if we can't use this triangle, this tristrip is done
      if used[j] <> 0 then
        goto done;

      // the new edge
      if stripcount and 1 <> 0 then
        m2 := check.vertindex[(k + 2) mod 3]
      else
        m1 := check.vertindex[(k + 2) mod 3];

      stripverts[stripcount + 2] := check.vertindex[(k + 2) mod 3];
      striptris[stripcount] := j;
      inc(stripcount);

      used[j] := 2;
      goto nexttri;
    end;
    continue1:
    inc(check);
  end;

  done:

  // clear the temp used flags
  for j := starttri + 1 to pheader.numtris - 1 do
    if used[j] = 2 then
      used[j] := 0;

  result := stripcount;
end;

(*
===========
FanLength
===========
*)

function FanLength(starttri: integer; startv: integer): integer;
label
  nexttri,
    done,
    continue1;
var
  m1, m2: integer;
  j: integer;
  last, check: Pmtriangle_t;
  k: integer;
begin
  used[starttri] := 2;

  last := @triangles[starttri];

  stripverts[0] := last.vertindex[(startv) mod 3];
  stripverts[1] := last.vertindex[(startv + 1) mod 3];
  stripverts[2] := last.vertindex[(startv + 2) mod 3];

  striptris[0] := starttri;
  stripcount := 1;

  m1 := last.vertindex[(startv) mod 3];
  m2 := last.vertindex[(startv + 2) mod 3];


  // look for a matching triangle
  nexttri:
  check := @triangles[starttri + 1];
  for j := starttri + 1 to pheader.numtris - 1 do
  begin
    if check.facesfront <> last.facesfront then
      goto continue1;
    for k := 0 to 2 do
    begin
      if check.vertindex[k] <> m1 then
        goto continue1;
      if check.vertindex[(k + 1) mod 3] <> m2 then
        goto continue1;

      // this is the next part of the fan

      // if we can't use this triangle, this tristrip is done
      if used[j] <> 0 then
        goto done;

      // the new edge
      m2 := check.vertindex[(k + 2) mod 3];

      stripverts[stripcount + 2] := m2;
      striptris[stripcount] := j;
      inc(stripcount);

      used[j] := 2;
      goto nexttri;
    end;
    continue1:
    inc(check);
  end;

  done:

  // clear the temp used flags
  for j := starttri + 1 to pheader.numtris - 1 do
    if used[j] = 2 then
      used[j] := 0;

  result := stripcount;
end;


(*
================
BuildTris

Generate a list of trifans or strips
for the model, which holds for all frames
================
*)

procedure BuildTris;
var
  i, j, k: integer;
  startv: integer;
  s, t: single;
  len, bestlen, besttype: integer;
  bestverts: array[0..1023] of integer;
  besttris: array[0..1023] of integer;
  _type: integer;
begin
  //
  // build tristrips
  //
  numorder := 0;
  numcommands := 0;
  ZeroMemory(@used, SizeOf(used));
  for i := 0 to pheader.numtris - 1 do
  begin
    // pick an unused triangle and start the trifan
    if used[i] <> 0 then
      continue;

    bestlen := 0;
    besttype := 0;
    for _type := 0 to 1 do
//  type = 1;
    begin
      for startv := 0 to 2 do
      begin
        if _type = 1 then
          len := StripLength(i, startv)
        else
          len := FanLength(i, startv);
        if len > bestlen then
        begin
          besttype := _type;
          bestlen := len;
          for j := 0 to bestlen + 1 do
            bestverts[j] := stripverts[j];
          for j := 0 to bestlen - 1 do
            besttris[j] := striptris[j];
        end;
      end;
    end;

    // mark the tris on the best strip as used
    for j := 0 to bestlen - 1 do
      used[besttris[j]] := 1;

    if besttype = 1 then
      commands[numcommands] := bestlen + 2
    else
      commands[numcommands] := -(bestlen + 2);
    inc(numcommands);

    for j := 0 to bestlen + 1 do
    begin
      // emit a vertex into the reorder buffer
      k := bestverts[j];
      vertexorder[numorder] := k;
      inc(numorder);

      // emit s/t coords into the commands stream
      s := stverts[k].s;
      t := stverts[k].t;
      if (triangles[besttris[0]].facesfront = 0) and (stverts[k].onseam <> 0) then
        s := s + pheader.skinwidth / 2; // on back side
      s := (s + 0.5) / pheader.skinwidth;
      t := (t + 0.5) / pheader.skinheight;

      Psingle(@commands[numcommands])^ := s;
      inc(numcommands);
      Psingle(@commands[numcommands])^ := t;
      inc(numcommands);
    end;
  end;

  commands[numcommands] := 0; // end of list marker
  inc(numcommands);

  Con_DPrintf('%3d tri %3d vert %3d cmd'#10, [pheader.numtris, numorder, numcommands]);

  allverts := allverts + numorder;
  alltris := alltris + pheader.numtris;
end;


(*
================
GL_MakeAliasModelDisplayLists
================
*)

procedure GL_MakeAliasModelDisplayLists(m: PBSPModelFile; hdr: Paliashdr_t);
var
  i, j: integer;
  cmds: PIntegerArray;
  verts: Ptrivertx_t;
  cache: array[0..MAX_QPATH - 1] of char;
  fullpath: array[0..MAX_OSPATH - 1] of char;
  f: integer;
begin
  aliasmodel := m;
  paliashdr := hdr; // (aliashdr_t *)Mod_Extradata (m);

  //
  // look for a cached version
  //
  strcpy(cache, 'glquake/');
  COM_StripExtension(m.name + strlen('progs/'), cache + strlen('glquake/'));
  strcat(cache, '.ms2');

  COM_FOpenFile(cache, f);
  if f <> NULLFILE then
  begin
    fread(@numcommands, 4, 1, f);
    fread(@numorder, 4, 1, f);
    fread(@commands, numcommands * SizeOf(commands[0]), 1, f);
    fread(@vertexorder, numorder * SizeOf(vertexorder[0]), 1, f);
    fclose(f);
  end
  else
  begin
    //
    // build it from scratch
    //
    Con_Printf('meshing %s...'#10, [m.name]);

    BuildTris; // trifans or lists

    //
    // save out the cached version
    //
    sprintf(fullpath, '%s/%s', [com_gamedir, cache]);
    f := fopen(fullpath, 'wb');
    if f <> NULLFILE then
    begin
      fwrite(@numcommands, 4, 1, f);
      fwrite(@numorder, 4, 1, f);
      fwrite(@commands, numcommands * SizeOf(commands[0]), 1, f);
      fwrite(@vertexorder, numorder * SizeOf(vertexorder[0]), 1, f);
      fclose(f);
    end;
  end;


  // save the data out

  paliashdr.poseverts := numorder;

  cmds := Hunk_Alloc(numcommands * 4);
  paliashdr.commands := integer(cmds) - integer(paliashdr);
  memcpy(cmds, @commands, numcommands * 4);

  verts := Hunk_Alloc(paliashdr.numposes * paliashdr.poseverts * SizeOf(trivertx_t));
  paliashdr.posedata := integer(verts) - integer(paliashdr);
  for i := 0 to paliashdr.numposes - 1 do
    for j := 0 to numorder - 1 do
    begin
      verts^ := Ptrivertx_tArray(poseverts[i])[vertexorder[j]];
      inc(verts);
    end;
end;


end.

 