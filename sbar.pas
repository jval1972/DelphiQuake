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

unit sbar;

// the status bar is only redrawn if something has changed, but if anything
// does, the entire thing will be redrawn for the next vid.numpages frames.

// sbar.c -- status bar code

interface

const
  SBAR_HEIGHT = 24;

procedure Sbar_Init;

procedure Sbar_Changed;
// call whenever any of the client stats represented on the sbar changes

procedure Sbar_Draw;
// called every frame by screen

procedure Sbar_IntermissionOverlay;
// called each frame after the level has been completed

procedure Sbar_FinaleOverlay;
procedure Sbar_DrawString(const x, y: integer; str: PChar);

var
  sb_lines: integer; // scan lines to draw

implementation

uses
  q_delphi,
  wad,
  quakedef,
  gl_draw,
  common,
  cmd,
  cl_main_h,
  protocol,
  gl_vidnt,
  client,
  host_h,
  gl_screen,
  menu;

var
  sb_updates: integer; // if >= vid.numpages, no update needed

const
  STAT_MINUS = 10; // num frame for '-' stats digit

var
  sb_nums: array[0..1, 0..10] of Pqpic_t;
  sb_colon, sb_slash: Pqpic_t;
  sb_ibar: Pqpic_t;
  sb_sbar: Pqpic_t;
  sb_scorebar: Pqpic_t;

  sb_weapons: array[0..6, 0..7] of Pqpic_t; // 0 is active, 1 is owned, 2-5 are flashes
  sb_ammo: array[0..3] of Pqpic_t;
  sb_sigil: array[0..3] of Pqpic_t;
  sb_armor: array[0..2] of Pqpic_t;
  sb_items: array[0..31] of Pqpic_t;

  sb_faces: array[0..6, 0..1] of Pqpic_t; // 0 is gibbed, 1 is dead, 2-6 are alive
                                            // 0 is static, 1 is temporary animation
  sb_face_invis: Pqpic_t;
  sb_face_quad: Pqpic_t;
  sb_face_invuln: Pqpic_t;
  sb_face_invis_invuln: Pqpic_t;

  sb_showscores: qboolean;

  rsb_invbar: array[0..1] of Pqpic_t;
  rsb_weapons: array[0..4] of Pqpic_t;
  rsb_items: array[0..1] of Pqpic_t;
  rsb_ammo: array[0..2] of Pqpic_t;
  rsb_teambord: Pqpic_t; // PGM 01/19/97 - team color border

//MED 01/04/97 added two more weapons + 3 alternates for grenade launcher
  hsb_weapons: array[0..6, 0..4] of Pqpic_t; // 0 is active, 1 is owned, 2-5 are flashes
//MED 01/04/97 added hipnotic items array
  hsb_items: array[0..1] of Pqpic_t;

const
//MED 01/04/97 added array to simplify weapon parsing
  hipweapons: array[0..3] of integer = (
    HIT_LASER_CANNON_BIT,
    HIT_MJOLNIR_BIT,
    4,
    HIT_PROXIMITY_GUN_BIT
    );

procedure Sbar_MiniDeathmatchOverlay; forward;
procedure Sbar_DeathmatchOverlay; forward;

(*
===============
Sbar_ShowScores

Tab key down
===============
*)

procedure Sbar_ShowScores;
begin
  if not sb_showscores then
  begin
    sb_showscores := true;
    sb_updates := 0;
  end;
end;

(*
===============
Sbar_DontShowScores

Tab key up
===============
*)

procedure Sbar_DontShowScores;
begin
  sb_showscores := false;
  sb_updates := 0;
end;

(*
===============
Sbar_Changed
===============
*)

procedure Sbar_Changed;
begin
  sb_updates := 0; // update next frame
end;

(*
===============
Sbar_Init
===============
*)

procedure Sbar_Init;
var
  i: integer;
begin
  for i := 0 to 9 do
  begin
    sb_nums[0][i] := Draw_PicFromWad(va('num_%d', [i]));
    sb_nums[1][i] := Draw_PicFromWad(va('anum_%d', [i]));
  end;

  sb_nums[0][10] := Draw_PicFromWad('num_minus');
  sb_nums[1][10] := Draw_PicFromWad('anum_minus');

  sb_colon := Draw_PicFromWad('num_colon');
  sb_slash := Draw_PicFromWad('num_slash');

  sb_weapons[0][0] := Draw_PicFromWad('inv_shotgun');
  sb_weapons[0][1] := Draw_PicFromWad('inv_sshotgun');
  sb_weapons[0][2] := Draw_PicFromWad('inv_nailgun');
  sb_weapons[0][3] := Draw_PicFromWad('inv_snailgun');
  sb_weapons[0][4] := Draw_PicFromWad('inv_rlaunch');
  sb_weapons[0][5] := Draw_PicFromWad('inv_srlaunch');
  sb_weapons[0][6] := Draw_PicFromWad('inv_lightng');

  sb_weapons[1][0] := Draw_PicFromWad('inv2_shotgun');
  sb_weapons[1][1] := Draw_PicFromWad('inv2_sshotgun');
  sb_weapons[1][2] := Draw_PicFromWad('inv2_nailgun');
  sb_weapons[1][3] := Draw_PicFromWad('inv2_snailgun');
  sb_weapons[1][4] := Draw_PicFromWad('inv2_rlaunch');
  sb_weapons[1][5] := Draw_PicFromWad('inv2_srlaunch');
  sb_weapons[1][6] := Draw_PicFromWad('inv2_lightng');

  for i := 0 to 4 do
  begin
    sb_weapons[2 + i][0] := Draw_PicFromWad(va('inva%d_shotgun', [i + 1]));
    sb_weapons[2 + i][1] := Draw_PicFromWad(va('inva%d_sshotgun', [i + 1]));
    sb_weapons[2 + i][2] := Draw_PicFromWad(va('inva%d_nailgun', [i + 1]));
    sb_weapons[2 + i][3] := Draw_PicFromWad(va('inva%d_snailgun', [i + 1]));
    sb_weapons[2 + i][4] := Draw_PicFromWad(va('inva%d_rlaunch', [i + 1]));
    sb_weapons[2 + i][5] := Draw_PicFromWad(va('inva%d_srlaunch', [i + 1]));
    sb_weapons[2 + i][6] := Draw_PicFromWad(va('inva%d_lightng', [i + 1]));
  end;

  sb_ammo[0] := Draw_PicFromWad('sb_shells');
  sb_ammo[1] := Draw_PicFromWad('sb_nails');
  sb_ammo[2] := Draw_PicFromWad('sb_rocket');
  sb_ammo[3] := Draw_PicFromWad('sb_cells');

  sb_armor[0] := Draw_PicFromWad('sb_armor1');
  sb_armor[1] := Draw_PicFromWad('sb_armor2');
  sb_armor[2] := Draw_PicFromWad('sb_armor3');

  sb_items[0] := Draw_PicFromWad('sb_key1');
  sb_items[1] := Draw_PicFromWad('sb_key2');
  sb_items[2] := Draw_PicFromWad('sb_invis');
  sb_items[3] := Draw_PicFromWad('sb_invuln');
  sb_items[4] := Draw_PicFromWad('sb_suit');
  sb_items[5] := Draw_PicFromWad('sb_quad');

  sb_sigil[0] := Draw_PicFromWad('sb_sigil1');
  sb_sigil[1] := Draw_PicFromWad('sb_sigil2');
  sb_sigil[2] := Draw_PicFromWad('sb_sigil3');
  sb_sigil[3] := Draw_PicFromWad('sb_sigil4');

  sb_faces[4][0] := Draw_PicFromWad('face1');
  sb_faces[4][1] := Draw_PicFromWad('face_p1');
  sb_faces[3][0] := Draw_PicFromWad('face2');
  sb_faces[3][1] := Draw_PicFromWad('face_p2');
  sb_faces[2][0] := Draw_PicFromWad('face3');
  sb_faces[2][1] := Draw_PicFromWad('face_p3');
  sb_faces[1][0] := Draw_PicFromWad('face4');
  sb_faces[1][1] := Draw_PicFromWad('face_p4');
  sb_faces[0][0] := Draw_PicFromWad('face5');
  sb_faces[0][1] := Draw_PicFromWad('face_p5');

  sb_face_invis := Draw_PicFromWad('face_invis');
  sb_face_invuln := Draw_PicFromWad('face_invul2');
  sb_face_invis_invuln := Draw_PicFromWad('face_inv2');
  sb_face_quad := Draw_PicFromWad('face_quad');

  Cmd_AddCommand('+showscores', Sbar_ShowScores);
  Cmd_AddCommand('-showscores', Sbar_DontShowScores);

  sb_sbar := Draw_PicFromWad('sbar');
  sb_ibar := Draw_PicFromWad('ibar');
  sb_scorebar := Draw_PicFromWad('scorebar');

//MED 01/04/97 added new hipnotic weapons
  if hipnotic then
  begin
    hsb_weapons[0][0] := Draw_PicFromWad('inv_laser');
    hsb_weapons[0][1] := Draw_PicFromWad('inv_mjolnir');
    hsb_weapons[0][2] := Draw_PicFromWad('inv_gren_prox');
    hsb_weapons[0][3] := Draw_PicFromWad('inv_prox_gren');
    hsb_weapons[0][4] := Draw_PicFromWad('inv_prox');

    hsb_weapons[1][0] := Draw_PicFromWad('inv2_laser');
    hsb_weapons[1][1] := Draw_PicFromWad('inv2_mjolnir');
    hsb_weapons[1][2] := Draw_PicFromWad('inv2_gren_prox');
    hsb_weapons[1][3] := Draw_PicFromWad('inv2_prox_gren');
    hsb_weapons[1][4] := Draw_PicFromWad('inv2_prox');

    for i := 0 to 4 do
    begin
      hsb_weapons[2 + i][0] := Draw_PicFromWad(va('inva%d_laser', [i + 1]));
      hsb_weapons[2 + i][1] := Draw_PicFromWad(va('inva%d_mjolnir', [i + 1]));
      hsb_weapons[2 + i][2] := Draw_PicFromWad(va('inva%d_gren_prox', [i + 1]));
      hsb_weapons[2 + i][3] := Draw_PicFromWad(va('inva%d_prox_gren', [i + 1]));
      hsb_weapons[2 + i][4] := Draw_PicFromWad(va('inva%d_prox', [i + 1]));
    end;

    hsb_items[0] := Draw_PicFromWad('sb_wsuit');
    hsb_items[1] := Draw_PicFromWad('sb_eshld');
  end;

  if rogue then
  begin
    rsb_invbar[0] := Draw_PicFromWad('r_invbar1');
    rsb_invbar[1] := Draw_PicFromWad('r_invbar2');

    rsb_weapons[0] := Draw_PicFromWad('r_lava');
    rsb_weapons[1] := Draw_PicFromWad('r_superlava');
    rsb_weapons[2] := Draw_PicFromWad('r_gren');
    rsb_weapons[3] := Draw_PicFromWad('r_multirock');
    rsb_weapons[4] := Draw_PicFromWad('r_plasma');

    rsb_items[0] := Draw_PicFromWad('r_shield1');
    rsb_items[1] := Draw_PicFromWad('r_agrav1');

// PGM 01/19/97 - team color border
    rsb_teambord := Draw_PicFromWad('r_teambord');
// PGM 01/19/97 - team color border

    rsb_ammo[0] := Draw_PicFromWad('r_ammolava');
    rsb_ammo[1] := Draw_PicFromWad('r_ammomulti');
    rsb_ammo[2] := Draw_PicFromWad('r_ammoplasma');
  end;
end;


//=============================================================================

// drawing routines are relative to the status bar location

(*
=============
Sbar_DrawPic
=============
*)

procedure Sbar_DrawPic(const x, y: integer; pic: Pqpic_t);
begin
  if cl.gametype = GAME_DEATHMATCH then
    Draw_Pic(x (* + ((vid.width - 320)>>1)*), y + (vid.height - SBAR_HEIGHT), pic)
  else
    Draw_Pic(x + ((vid.width - 320) div 2), y + (vid.height - SBAR_HEIGHT), pic);
end;

(*
=============
Sbar_DrawTransPic
=============
*)

procedure Sbar_DrawTransPic(const x, y: integer; pic: Pqpic_t);
begin
  if cl.gametype = GAME_DEATHMATCH then
    Draw_TransPic(x (*+ ((vid.width - 320)>>1)*), y + (vid.height - SBAR_HEIGHT), pic)
  else
    Draw_TransPic(x + ((vid.width - 320) div 2), y + (vid.height - SBAR_HEIGHT), pic);
end;

(*
================
Sbar_DrawCharacter

Draws one solid graphics character
================
*)

procedure Sbar_DrawCharacter(const x, y: integer; const num: integer);
begin
  if cl.gametype = GAME_DEATHMATCH then
    Draw_Character(x (*+ ((vid.width - 320)>>1) *) + 4, y + vid.height - SBAR_HEIGHT, num)
  else
    Draw_Character(x + ((vid.width - 320) div 2) + 4, y + vid.height - SBAR_HEIGHT, num);
end;

(*
================
Sbar_DrawString
================
*)

procedure Sbar_DrawString(const x, y: integer; str: PChar);
begin
  if cl.gametype = GAME_DEATHMATCH then
    Draw_String(x (*+ ((vid.width - 320)>>1)*), y + vid.height - SBAR_HEIGHT, str)
  else
    Draw_String(x + ((vid.width - 320) div 2), y + vid.height - SBAR_HEIGHT, str);
end;

(*
=============
Sbar_itoa
=============
*)

function Sbar_itoa(num: integer; buf: PChar): integer;
var
  str: PChar;
  pow10: integer;
  dig: integer;
begin
  str := buf;

  if num < 0 then
  begin
    str^ := '-';
    inc(str);
    num := -num;
  end;

  pow10 := 10;
  while num >= pow10 do
    pow10 := pow10 * 10;

  repeat
    pow10 := pow10 div 10;
    dig := num div pow10;
    str^ := Chr(Ord('0') + dig);
    inc(str);
    num := num - dig * pow10;
  until pow10 = 1;

  str^ := #0;

  result := integer(str) - integer(buf);
end;


(*
=============
Sbar_DrawNum
=============
*)

procedure Sbar_DrawNum(x, y: integer; const num: integer; const digits: integer;
  const color: integer);
var
  str: array[0..11] of char;
  ptr: PChar;
  l, frame: integer;
begin
  l := Sbar_itoa(num, str);
  ptr := @str[0];
  if l > digits then
    inc(ptr, (l - digits));
  if l < digits then
    inc(x, (digits - l) * 24);

  while ptr^ <> #0 do
  begin
    if ptr^ = '-' then
      frame := STAT_MINUS
    else
      frame := Ord(ptr^) - Ord('0');

    Sbar_DrawTransPic(x, y, sb_nums[color][frame]);
    inc(x, 24);
    inc(ptr);
  end;
end;

//=============================================================================

var
  fragsort: array[0..MAX_SCOREBOARD - 1] of integer;
  scoreboardtext: array[0..MAX_SCOREBOARD - 1] of array[0..19] of char;
  scoreboardtop: array[0..MAX_SCOREBOARD - 1] of integer;
  scoreboardbottom: array[0..MAX_SCOREBOARD - 1] of integer;
  scoreboardcount: array[0..MAX_SCOREBOARD - 1] of integer;
  scoreboardlines: integer;

(*
===============
Sbar_SortFrags
===============
*)

procedure Sbar_SortFrags;
var
  i, j, k: integer;
begin
// sort by frags
  scoreboardlines := 0;
  for i := 0 to cl.maxclients - 1 do
  begin
    if cl.scores[i].name[0] <> #0 then
    begin
      fragsort[scoreboardlines] := i;
      inc(scoreboardlines);
    end;
  end;

  for i := 0 to scoreboardlines - 1 do
    for j := 0 to scoreboardlines - i - 2 do
      if cl.scores[fragsort[j]].frags < cl.scores[fragsort[j + 1]].frags then
      begin
        k := fragsort[j];
        fragsort[j] := fragsort[j + 1];
        fragsort[j + 1] := k;
      end;
end;

function Sbar_ColorForMap(m: integer): integer; // JVAL ???
begin
  result := m + 8;
end;

(*
===============
Sbar_UpdateScoreboard
===============
*)

procedure Sbar_UpdateScoreboard;
var
  i, k: integer;
  top, bottom: integer;
  s: Pscoreboard_t;
begin
  Sbar_SortFrags;

// draw the text
  ZeroMemory(@scoreboardtext, SizeOf(scoreboardtext));

  for i := 0 to scoreboardlines - 1 do
  begin
    k := fragsort[i];
    s := @cl.scores[k];
    sprintf(@scoreboardtext[i][1], '%3d %s', [s.frags, s.name]);

    top := s.colors and $F0;
    bottom := (s.colors and 15) * 16;
    scoreboardtop[i] := Sbar_ColorForMap(top);
    scoreboardbottom[i] := Sbar_ColorForMap(bottom);
  end;
end;



(*
===============
Sbar_SoloScoreboard
===============
*)

procedure Sbar_SoloScoreboard;
var
  str: array[0..79] of char;
  minutes, seconds, tens, units: integer;
  l: integer;
begin
  sprintf(str, 'Monsters:%3d /%3d', [cl.stats[STAT_MONSTERS], cl.stats[STAT_TOTALMONSTERS]]);
  Sbar_DrawString(8, 4, str);

  sprintf(str, 'Secrets :%3d /%3d', [cl.stats[STAT_SECRETS], cl.stats[STAT_TOTALSECRETS]]);
  Sbar_DrawString(8, 12, str);

// time
  minutes := intval(cl.time / 60);
  seconds := intval(cl.time - 60 * minutes);
  tens := seconds div 10;
  units := seconds - 10 * tens;
  sprintf(str, 'Time :%3d:%d%d', [minutes, tens, units]);
  Sbar_DrawString(184, 4, str);

// draw level name
  l := strlen(cl.levelname);
  Sbar_DrawString(232 - l * 4, 12, cl.levelname);
end;

(*
===============
Sbar_DrawScoreboard
===============
*)

procedure Sbar_DrawScoreboard;
begin
  Sbar_SoloScoreboard;
  if cl.gametype = GAME_DEATHMATCH then
    Sbar_DeathmatchOverlay;
end;

//=============================================================================

(*
===============
Sbar_DrawInventory
===============
*)

procedure Sbar_DrawInventory;
var
  i: integer;
  num: array[0..5] of char;
  time: single;
  flashon: integer;
  grenadeflashing: integer;
begin
  if rogue then
  begin
    if cl.stats[STAT_ACTIVEWEAPON] >= RIT_LAVA_NAILGUN then
      Sbar_DrawPic(0, -24, rsb_invbar[0])
    else
      Sbar_DrawPic(0, -24, rsb_invbar[1]);
  end
  else
  begin
    Sbar_DrawPic(0, -24, sb_ibar);
  end;

// weapons
  for i := 0 to 6 do
  begin
    if cl.items and (IT_SHOTGUN shl i) <> 0 then
    begin
      time := cl.item_gettime[i];
      flashon := intval((cl.time - time) * 10);
      if flashon >= 10 then
      begin
        if cl.stats[STAT_ACTIVEWEAPON] = (IT_SHOTGUN shl i) then
          flashon := 1
        else
          flashon := 0;
      end
      else
        flashon := (flashon mod 5) + 2;

      Sbar_DrawPic(i * 24, -16, sb_weapons[flashon][i]);

      if flashon > 1 then
        sb_updates := 0; // force update to remove flash
    end;
  end;

// MED 01/04/97
// hipnotic weapons
  if hipnotic then
  begin
    grenadeflashing := 0;
    for i := 0 to 3 do
    begin
      if cl.items and (1 shl hipweapons[i]) <> 0 then
      begin
        time := cl.item_gettime[hipweapons[i]];
        flashon := intval((cl.time - time) * 10);
        if flashon >= 10 then
        begin
          if cl.stats[STAT_ACTIVEWEAPON] = (1 shl hipweapons[i]) then
            flashon := 1
          else
            flashon := 0;
        end
        else
          flashon := (flashon mod 5) + 2;

        // check grenade launcher
        if i = 2 then
        begin
          if cl.items and HIT_PROXIMITY_GUN <> 0 then
          begin
            if flashon <> 0 then
            begin
              grenadeflashing := 1;
              Sbar_DrawPic(96, -16, hsb_weapons[flashon][2]);
            end;
          end;
        end
        else if i = 3 then
        begin
          if cl.items and (IT_SHOTGUN shl 4) <> 0 then
          begin
            if (flashon <> 0) and (grenadeflashing = 0) then
            begin
              Sbar_DrawPic(96, -16, hsb_weapons[flashon][3]);
            end
            else if grenadeflashing = 0 then
            begin
              Sbar_DrawPic(96, -16, hsb_weapons[0][3]);
            end
          end
          else
            Sbar_DrawPic(96, -16, hsb_weapons[flashon][4]);
        end
        else
          Sbar_DrawPic(176 + (i * 24), -16, hsb_weapons[flashon][i]);
        if flashon > 1 then
          sb_updates := 0; // force update to remove flash
      end;
    end;
  end;

  if rogue then
  begin
    // check for powered up weapon.
    if cl.stats[STAT_ACTIVEWEAPON] >= RIT_LAVA_NAILGUN then
    begin
      for i := 0 to 4 do
      begin
        if cl.stats[STAT_ACTIVEWEAPON] = (RIT_LAVA_NAILGUN shl i) then
          Sbar_DrawPic((i + 2) * 24, -16, rsb_weapons[i]);
      end;
    end;
  end;

// ammo counts
  for i := 0 to 3 do
  begin
    sprintf(num, '%3d', [cl.stats[STAT_SHELLS + i]]);
    if num[0] <> ' ' then
      Sbar_DrawCharacter((6 * i + 1) * 8 - 2, -24, 18 + Ord(num[0]) - Ord('0'));
    if num[1] <> ' ' then
      Sbar_DrawCharacter((6 * i + 2) * 8 - 2, -24, 18 + Ord(num[1]) - Ord('0'));
    if num[2] <> ' ' then
      Sbar_DrawCharacter((6 * i + 3) * 8 - 2, -24, 18 + Ord(num[2]) - Ord('0'));
  end;

  flashon := 0;
  // items
  for i := 0 to 5 do
    if cl.items and (1 shl (17 + i)) <> 0 then
    begin
      time := cl.item_gettime[17 + i];
      if (time <> 0) and (time > cl.time - 2) and (flashon <> 0) then
      begin // flash frame
        sb_updates := 0;
      end
      else
      begin
      //MED 01/04/97 changed keys
        if not hipnotic or (i > 1) then
        begin
          Sbar_DrawPic(192 + i * 16, -16, sb_items[i]);
        end;
      end;
      if (time <> 0) and (time > cl.time - 2) then
        sb_updates := 0;
    end;

  //MED 01/04/97 added hipnotic items
  // hipnotic items
  if hipnotic then
    for i := 0 to 1 do
      if cl.items and (1 shl (24 + i)) <> 0 then
      begin
        time := cl.item_gettime[24 + i];
        if (time <> 0) and (time > cl.time - 2) and (flashon <> 0) then
        begin // flash frame
          sb_updates := 0;
        end
        else
        begin
          Sbar_DrawPic(288 + i * 16, -16, hsb_items[i]);
        end;
        if (time <> 0) and (time > cl.time - 2) then
          sb_updates := 0;
      end;

  if rogue then
  begin
  // new rogue items
    for i := 0 to 1 do
    begin
      if cl.items and (1 shl (29 + i)) <> 0 then
      begin
        time := cl.item_gettime[29 + i];

        if (time <> 0) and (time > cl.time - 2) and (flashon <> 0) then
        begin // flash frame
          sb_updates := 0;
        end
        else
        begin
          Sbar_DrawPic(288 + i * 16, -16, rsb_items[i]);
        end;

        if (time <> 0) and (time > cl.time - 2) then
          sb_updates := 0;
      end;
    end;
  end
  else
  begin
  // sigils
    for i := 0 to 3 do
    begin
      if cl.items and (1 shl (28 + i)) <> 0 then
      begin
        time := cl.item_gettime[28 + i];
        if (time <> 0) and (time > cl.time - 2) and (flashon <> 0) then
        begin // flash frame
          sb_updates := 0;
        end
        else
          Sbar_DrawPic(320 - 32 + i * 8, -16, sb_sigil[i]);
        if (time <> 0) and (time > cl.time - 2) then
          sb_updates := 0;
      end;
    end;
  end;
end;

//=============================================================================

(*
===============
Sbar_DrawFrags
===============
*)

procedure Sbar_DrawFrags;
var
  i, k, l: integer;
  top, bottom: integer;
  x, y, f: integer;
  xofs: integer;
  num: array[0..11] of char;
  s: Pscoreboard_t;
begin
  Sbar_SortFrags;

// draw the text
  if scoreboardlines <= 4 then
    l := scoreboardlines
  else
    l := 4;

  x := 23;
  if cl.gametype = GAME_DEATHMATCH then
    xofs := 0
  else
    xofs := (vid.width - 320) div 2;
  y := vid.height - SBAR_HEIGHT - 23;

  for i := 0 to l - 1 do
  begin
    k := fragsort[i];
    s := @cl.scores[k];
    if s.name[0] = #0 then
      continue;

  // draw background
    top := s.colors and $F0;
    bottom := (s.colors and 15) * 16;
    top := Sbar_ColorForMap(top);
    bottom := Sbar_ColorForMap(bottom);

    Draw_Fill(xofs + x * 8 + 10, y, 28, 4, top);
    Draw_Fill(xofs + x * 8 + 10, y + 4, 28, 3, bottom);

  // draw number
    f := s.frags;
    sprintf(num, '%3d', [f]);

    Sbar_DrawCharacter((x + 1) * 8, -24, Ord(num[0]));
    Sbar_DrawCharacter((x + 2) * 8, -24, Ord(num[1]));
    Sbar_DrawCharacter((x + 3) * 8, -24, Ord(num[2]));

    if k = cl.viewentity - 1 then
    begin
      Sbar_DrawCharacter(x * 8 + 2, -24, 16);
      Sbar_DrawCharacter((x + 4) * 8 - 4, -24, 17);
    end;
    inc(x, 4);
  end;
end;

//=============================================================================


(*
===============
Sbar_DrawFace
===============
*)

procedure Sbar_DrawFace;
var
  f, anim: integer;
  top, bottom: integer;
  xofs: integer;
  num: array[0..11] of char;
  s: Pscoreboard_t;
begin
// PGM 01/19/97 - team color drawing
// PGM 03/02/97 - fixed so color swatch only appears in CTF modes
  if rogue and
    (cl.maxclients <> 1) and
    (teamplay.value > 3) and
    (teamplay.value < 7) then
  begin
    s := @cl.scores[cl.viewentity - 1];
    // draw background
    top := s.colors and $F0;
    bottom := (s.colors and 15) * 16;
    top := Sbar_ColorForMap(top);
    bottom := Sbar_ColorForMap(bottom);

    if cl.gametype = GAME_DEATHMATCH then
      xofs := 113
    else
      xofs := ((vid.width - 320) div 2) + 113;

    Sbar_DrawPic(112, 0, rsb_teambord);
    Draw_Fill(xofs, vid.height - SBAR_HEIGHT + 3, 22, 9, top);
    Draw_Fill(xofs, vid.height - SBAR_HEIGHT + 12, 22, 9, bottom);

    // draw number
    f := s.frags;
    sprintf(num, '%3d', [f]);

    if top = 8 then
    begin
      if num[0] <> ' ' then
        Sbar_DrawCharacter(109, 3, 18 + Ord(num[0]) - Ord('0'));
      if num[1] <> ' ' then
        Sbar_DrawCharacter(116, 3, 18 + Ord(num[1]) - Ord('0'));
      if num[2] <> ' ' then
        Sbar_DrawCharacter(123, 3, 18 + Ord(num[2]) - Ord('0'));
    end
    else
    begin
      Sbar_DrawCharacter(109, 3, Ord(num[0]));
      Sbar_DrawCharacter(116, 3, Ord(num[1]));
      Sbar_DrawCharacter(123, 3, Ord(num[2]));
    end;

    exit;
  end;
// PGM 01/19/97 - team color drawing

  if cl.items and (IT_INVISIBILITY or IT_INVULNERABILITY) =
    (IT_INVISIBILITY or IT_INVULNERABILITY) then
  begin
    Sbar_DrawPic(112, 0, sb_face_invis_invuln);
    exit;
  end;

  if cl.items and IT_QUAD <> 0 then
  begin
    Sbar_DrawPic(112, 0, sb_face_quad);
    exit;
  end;

  if cl.items and IT_INVISIBILITY <> 0 then
  begin
    Sbar_DrawPic(112, 0, sb_face_invis);
    exit;
  end;

  if cl.items and IT_INVULNERABILITY <> 0 then
  begin
    Sbar_DrawPic(112, 0, sb_face_invuln);
    exit;
  end;

  if cl.stats[STAT_HEALTH] >= 100 then
    f := 4
  else
    f := cl.stats[STAT_HEALTH] div 20;

  if cl.time <= cl.faceanimtime then
  begin
    anim := 1;
    sb_updates := 0; // make sure the anim gets drawn over
  end
  else
    anim := 0;
  Sbar_DrawPic(112, 0, sb_faces[f][anim]);
end;

(*
===============
Sbar_Draw
===============
*)

procedure Sbar_Draw;
begin
  if scr_con_current = vid.height then
    exit; // console is full screen

  if sb_updates >= vid.numpages then
    exit;

  scr_copyeverything := true;

  inc(sb_updates);

  if (sb_lines <> 0) and (vid.width > 320) then
    Draw_TileClear(0, vid.height - sb_lines, vid.width, sb_lines);

  if sb_lines > 24 then
  begin
    Sbar_DrawInventory;
    if cl.maxclients <> 1 then
      Sbar_DrawFrags;
  end;

  if sb_showscores or (cl.stats[STAT_HEALTH] <= 0) then
  begin
    Sbar_DrawPic(0, 0, sb_scorebar);
    Sbar_DrawScoreboard;
    sb_updates := 0;
  end
  else if sb_lines <> 0 then
  begin
    Sbar_DrawPic(0, 0, sb_sbar);

   // keys (hipnotic only)
    //MED 01/04/97 moved keys here so they would not be overwritten
    if hipnotic then
    begin
      if cl.items and IT_KEY1 <> 0 then
        Sbar_DrawPic(209, 3, sb_items[0]);
      if cl.items and IT_KEY2 <> 0 then
        Sbar_DrawPic(209, 12, sb_items[1]);
    end;
   // armor
    if cl.items and IT_INVULNERABILITY <> 0 then
    begin
      Sbar_DrawNum(24, 0, 666, 3, 1);
      Sbar_DrawPic(0, 0, draw_disc);
    end
    else
    begin
      if rogue then
      begin
        Sbar_DrawNum(24, 0, cl.stats[STAT_ARMOR], 3, intval(cl.stats[STAT_ARMOR] <= 25));
        if cl.items and RIT_ARMOR3 <> 0 then
          Sbar_DrawPic(0, 0, sb_armor[2])
        else if cl.items and RIT_ARMOR2 <> 0 then
          Sbar_DrawPic(0, 0, sb_armor[1])
        else if cl.items and RIT_ARMOR1 <> 0 then
          Sbar_DrawPic(0, 0, sb_armor[0]);
      end
      else
      begin
        Sbar_DrawNum(24, 0, cl.stats[STAT_ARMOR], 3, intval(cl.stats[STAT_ARMOR] <= 25));
        if cl.items and IT_ARMOR3 <> 0 then
          Sbar_DrawPic(0, 0, sb_armor[2])
        else if cl.items and IT_ARMOR2 <> 0 then
          Sbar_DrawPic(0, 0, sb_armor[1])
        else if cl.items and IT_ARMOR1 <> 0 then
          Sbar_DrawPic(0, 0, sb_armor[0]);
      end;
    end;

  // face
    Sbar_DrawFace;

  // health
    Sbar_DrawNum(136, 0, cl.stats[STAT_HEALTH], 3, intval(cl.stats[STAT_HEALTH] <= 25));

  // ammo icon
    if rogue then
    begin
      if cl.items and RIT_SHELLS <> 0 then
        Sbar_DrawPic(224, 0, sb_ammo[0])
      else if cl.items and RIT_NAILS <> 0 then
        Sbar_DrawPic(224, 0, sb_ammo[1])
      else if cl.items and RIT_ROCKETS <> 0 then
        Sbar_DrawPic(224, 0, sb_ammo[2])
      else if cl.items and RIT_CELLS <> 0 then
        Sbar_DrawPic(224, 0, sb_ammo[3])
      else if cl.items and RIT_LAVA_NAILS <> 0 then
        Sbar_DrawPic(224, 0, rsb_ammo[0])
      else if cl.items and RIT_PLASMA_AMMO <> 0 then
        Sbar_DrawPic(224, 0, rsb_ammo[1])
      else if cl.items and RIT_MULTI_ROCKETS <> 0 then
        Sbar_DrawPic(224, 0, rsb_ammo[2]);
    end
    else
    begin
      if cl.items and IT_SHELLS <> 0 then
        Sbar_DrawPic(224, 0, sb_ammo[0])
      else if cl.items and IT_NAILS <> 0 then
        Sbar_DrawPic(224, 0, sb_ammo[1])
      else if cl.items and IT_ROCKETS <> 0 then
        Sbar_DrawPic(224, 0, sb_ammo[2])
      else if cl.items and IT_CELLS <> 0 then
        Sbar_DrawPic(224, 0, sb_ammo[3]);
    end;

    Sbar_DrawNum(248, 0, cl.stats[STAT_AMMO], 3, intval(cl.stats[STAT_AMMO] <= 10));
  end;

  if vid.width > 320 then
    if cl.gametype = GAME_DEATHMATCH then
      Sbar_MiniDeathmatchOverlay;
end;


//=============================================================================

(*
==================
Sbar_IntermissionNumber

==================
*)

procedure Sbar_IntermissionNumber(x, y: integer; const num: integer;
  const digits: integer; const color: integer);
var
  str: array[0..11] of char;
  ptr: PChar;
  l, frame: integer;
begin
  l := Sbar_itoa(num, str);
  ptr := @str[0];
  if l > digits then
    inc(ptr, (l - digits));
  if l < digits then
    x := x + (digits - l) * 24;

  while ptr^ <> #0 do
  begin
    if ptr^ = '-' then
      frame := STAT_MINUS
    else
      frame := Ord(ptr^) - Ord('0');

    Draw_TransPic(x, y, sb_nums[color][frame]);
    inc(x, 24);
    inc(ptr);
  end;
end;


(*
==================
Sbar_DeathmatchOverlay

==================
*)

procedure Sbar_DeathmatchOverlay;
var
  pic: Pqpic_t;
  i, k, l: integer;
  top, bottom: integer;
  x, y, f: integer;
  num: array[0..11] of char;
  s: Pscoreboard_t;
begin
  scr_copyeverything := true;
  scr_fullupdate := 0;

  pic := Draw_CachePic('gfx/ranking.lmp');
  M_DrawPic((320 - pic.width) div 2, 8, pic);

// scores
  Sbar_SortFrags;

// draw the text
  l := scoreboardlines;

  x := 80 + ((vid.width - 320) div 2);
  y := 40;
  for i := 0 to l - 1 do
  begin
    k := fragsort[i];
    s := @cl.scores[k];
    if s.name[0] = #0 then
      continue;

  // draw background
    top := s.colors and $F0;
    bottom := (s.colors and 15) * 16;
    top := Sbar_ColorForMap(top);
    bottom := Sbar_ColorForMap(bottom);

    Draw_Fill(x, y, 40, 4, top);
    Draw_Fill(x, y + 4, 40, 4, bottom);

  // draw number
    f := s.frags;
    sprintf(num, '%3d', [f]);

    Draw_Character(x + 8, y, num[0]);
    Draw_Character(x + 16, y, num[1]);
    Draw_Character(x + 24, y, num[2]);

    if k = cl.viewentity - 1 then
      Draw_Character(x - 8, y, 12);

  // draw name
    Draw_String(x + 64, y, s.name);

    inc(y, 10);
  end;
end;

(*
==================
Sbar_MiniDeathmatchOverlay

==================
*)

procedure Sbar_MiniDeathmatchOverlay;
var
  i, k: integer;
  top, bottom: integer;
  x, y, f: integer;
  num: array[0..11] of char;
  s: Pscoreboard_t;
  numlines: integer;
begin
  if (vid.width < 512) or (sb_lines = 0) then
    exit;

  scr_copyeverything := true;
  scr_fullupdate := 0;

// scores
  Sbar_SortFrags;

// draw the text
  y := vid.height - sb_lines;
  numlines := sb_lines div 8;
  if numlines < 3 then
    exit;

  //find us
  i := 0;
  while i < scoreboardlines do
  begin
    if fragsort[i] = cl.viewentity - 1 then
      break;
    inc(i);
  end;

  if i = scoreboardlines then // we're not there
    i := 0
  else // figure out start
    i := i - numlines div 2;

  if i > scoreboardlines - numlines then
    i := scoreboardlines - numlines;
  if i < 0 then
    i := 0;

  x := 324;
  while (i < scoreboardlines) and (y < vid.height - 8) do
  begin
    k := fragsort[i];
    s := @cl.scores[k];
    if s.name[0] <> #0 then
    begin

    // draw background
      top := s.colors and $F0;
      bottom := (s.colors and 15) * 16;
      top := Sbar_ColorForMap(top);
      bottom := Sbar_ColorForMap(bottom);

      Draw_Fill(x, y + 1, 40, 3, top);
      Draw_Fill(x, y + 4, 40, 4, bottom);

    // draw number
      f := s.frags;
      sprintf(num, '%3d', [f]);

      Draw_Character(x + 8, y, num[0]);
      Draw_Character(x + 16, y, num[1]);
      Draw_Character(x + 24, y, num[2]);

      if k = cl.viewentity - 1 then
      begin
        Draw_Character(x, y, 16);
        Draw_Character(x + 32, y, 17);
      end;

    // draw name
      Draw_String(x + 48, y, s.name);

      inc(y, 8);
      inc(i);
    end;
  end;
end;


(*
==================
Sbar_IntermissionOverlay

==================
*)

procedure Sbar_IntermissionOverlay;
var
  pic: Pqpic_t;
  dig: integer;
  num: integer;
begin
  scr_copyeverything := true;
  scr_fullupdate := 0;

  if cl.gametype = GAME_DEATHMATCH then
  begin
    Sbar_DeathmatchOverlay;
    exit;
  end;

  pic := Draw_CachePic('gfx/complete.lmp');
  Draw_Pic(64, 24, pic);

  pic := Draw_CachePic('gfx/inter.lmp');
  Draw_TransPic(0, 56, pic);

// time
  dig := cl.completed_time div 60;
  Sbar_IntermissionNumber(160, 64, dig, 3, 0);
  num := cl.completed_time - dig * 60;
  Draw_TransPic(234, 64, sb_colon);
  Draw_TransPic(246, 64, sb_nums[0][num div 10]);
  Draw_TransPic(266, 64, sb_nums[0][num mod 10]);

  Sbar_IntermissionNumber(160, 104, cl.stats[STAT_SECRETS], 3, 0);
  Draw_TransPic(232, 104, sb_slash);
  Sbar_IntermissionNumber(240, 104, cl.stats[STAT_TOTALSECRETS], 3, 0);

  Sbar_IntermissionNumber(160, 144, cl.stats[STAT_MONSTERS], 3, 0);
  Draw_TransPic(232, 144, sb_slash);
  Sbar_IntermissionNumber(240, 144, cl.stats[STAT_TOTALMONSTERS], 3, 0);

end;


(*
==================
Sbar_FinaleOverlay

==================
*)

procedure Sbar_FinaleOverlay;
var
  pic: Pqpic_t;
begin
  scr_copyeverything := true;

  pic := Draw_CachePic('gfx/finale.lmp');
  Draw_TransPic((vid.width - pic.width) div 2, 16, pic);
end;

end.
