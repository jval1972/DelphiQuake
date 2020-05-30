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

program dquake;

{$R *.res}


uses
  FastMM4,
  FastMM4Messages,
  bspfile in 'bspfile.pas',
  bspconst in 'bspconst.pas',
  bsptypes in 'bsptypes.pas',
  q_vector in 'q_vector.pas',
  quakedef in 'quakedef.pas',
  cd_win in 'cd_win.pas',
  cl_demo in 'cl_demo.pas',
  cl_main in 'cl_main.pas',
  cl_parse in 'cl_parse.pas',
  cl_tent in 'cl_tent.pas',
  in_win in 'in_win.pas',
  cvar in 'cvar.pas',
  menu in 'menu.pas',
  wad in 'wad.pas',
  chase in 'chase.pas',
  cl_main_h in 'cl_main_h.pas',
  cl_input in 'cl_input.pas',
  client in 'client.pas',
  cmd in 'cmd.pas',
  common in 'common.pas',
  conproc in 'conproc.pas',
  console in 'console.pas',
  crc in 'crc.pas',
  gl_draw in 'gl_draw.pas',
  gl_mesh in 'gl_mesh.pas',
  gl_model in 'gl_model.pas',
  gl_model_h in 'gl_model_h.pas',
  gl_refrag in 'gl_refrag.pas',
  gl_rlight in 'gl_rlight.pas',
  gl_rmain in 'gl_rmain.pas',
  gl_rmisc in 'gl_rmisc.pas',
  gl_rsurf in 'gl_rsurf.pas',
  gl_screen in 'gl_screen.pas',
  gl_vidnt in 'gl_vidnt.pas',
  gl_warp in 'gl_warp.pas',
  gl_planes in 'gl_planes.pas',
  gl_rmain_h in 'gl_rmain_h.pas',
  gl_defs in 'gl_defs.pas',
  server_h in 'server_h.pas',
  host in 'host.pas',
  host_h in 'host_h.pas',
  host_cmd in 'host_cmd.pas',
  keys in 'keys.pas',
  keys_h in 'keys_h.pas',
  mathlib in 'mathlib.pas',
  modelgen in 'modelgen.pas',
  net in 'net.pas',
  net_loop in 'net_loop.pas',
  net_dgrm in 'net_dgrm.pas',
  net_main in 'net_main.pas',
  net_win in 'net_win.pas',
  net_vcr in 'net_vcr.pas',
  net_wins in 'net_wins.pas',
  net_wipx in 'net_wipx.pas',
  wsipx_h in 'wsipx_h.pas',
  pr_comp in 'pr_comp.pas',
  pr_cmds in 'pr_cmds.pas',
  pr_edict in 'pr_edict.pas',
  pr_exec in 'pr_exec.pas',
  progdefs in 'progdefs.pas',
  progs_h in 'progs_h.pas',
  gl_part in 'gl_part.pas',
  render_h in 'render_h.pas',
  sbar in 'sbar.pas',
  spritegn in 'spritegn.pas',
  snd_dma in 'snd_dma.pas',
  snd_mem in 'snd_mem.pas',
  snd_mix in 'snd_mix.pas',
  snd_win in 'snd_win.pas',
  snd_dma_h in 'snd_dma_h.pas',
  snd_win_h in 'snd_win_h.pas',
  sound in 'sound.pas',
  sv_main in 'sv_main.pas',
  sv_move in 'sv_move.pas',
  sv_phys in 'sv_phys.pas',
  sv_user in 'sv_user.pas',
  sys_win in 'sys_win.pas',
  vid_h in 'vid_h.pas',
  view in 'view.pas',
  world in 'world.pas',
  zone in 'zone.pas',
  protocol in 'protocol.pas',
  jpg_COMapi in 'JPEGLIB\jpg_comapi.pas',
  jpg_dAPImin in 'JPEGLIB\jpg_dapimin.pas',
  jpg_dAPIstd in 'JPEGLIB\jpg_dapistd.pas',
  jpg_DCoefCt in 'JPEGLIB\jpg_dcoefct.pas',
  jpg_dColor in 'JPEGLIB\jpg_dcolor.pas',
  jpg_dct in 'JPEGLIB\jpg_dct.pas',
  jpg_dDctMgr in 'JPEGLIB\jpg_ddctmgr.pas',
  jpg_defErr in 'JPEGLIB\jpg_deferr.pas',
  jpg_dHuff in 'JPEGLIB\jpg_dhuff.pas',
  jpg_dInput in 'JPEGLIB\jpg_dinput.pas',
  jpg_dMainCt in 'JPEGLIB\jpg_dmainct.pas',
  jpg_dMarker in 'JPEGLIB\jpg_dmarker.pas',
  jpg_dMaster in 'JPEGLIB\jpg_dmaster.pas',
  jpg_dMerge in 'JPEGLIB\jpg_dmerge.pas',
  jpg_dpHuff in 'JPEGLIB\jpg_dphuff.pas',
  jpg_dPostCt in 'JPEGLIB\jpg_dpostct.pas',
  jpg_dSample in 'JPEGLIB\jpg_dsample.pas',
  jpg_error in 'JPEGLIB\jpg_error.pas',
  jpg_IDctAsm in 'JPEGLIB\jpg_idctasm.pas',
  jpg_IDctFlt in 'JPEGLIB\jpg_idctflt.pas',
  jpg_IDctFst in 'JPEGLIB\jpg_idctfst.pas',
  jpg_IDctRed in 'JPEGLIB\jpg_IDctRed.pas',
  jpg_Lib in 'JPEGLIB\jpg_lib.pas',
  jpg_MemMgr in 'JPEGLIB\jpg_memmgr.pas',
  jpg_memnobs in 'JPEGLIB\jpg_memnobs.pas',
  jpg_moreCfg in 'JPEGLIB\jpg_morecfg.pas',
  jpg_Quant1 in 'JPEGLIB\jpg_quant1.pas',
  jpg_Quant2 in 'JPEGLIB\jpg_quant2.pas',
  jpg_utils in 'JPEGLIB\jpg_utils.pas',
  t_bmp in 'TEXLIB\t_bmp.pas',
  t_colors in 'TEXLIB\t_colors.pas',
  t_jpeg in 'TEXLIB\t_jpeg.pas',
  t_main in 'TEXLIB\t_main.pas',
  t_material in 'TEXLIB\t_material.pas',
  t_png in 'TEXLIB\t_png.pas',
  t_tex in 'TEXLIB\t_tex.pas',
  t_tga in 'TEXLIB\t_tga.pas',
  z_files in 'ZLIB\z_files.pas',
  w_pak in 'w_pak.pas',
  q_delphi in 'q_delphi.pas',
  m_fixed in 'm_fixed.pas',
  q_extra in 'q_extra.pas',
  gl_texture in 'gl_texture.pas',
  gl_sky in 'gl_sky.pas',
  OpenGL12 in 'OpenGL12.pas', DirectX;

var
  Saved8087CW: Word;
begin
  Saved8087CW := Default8087CW;
  Set8087CW($133F);

  WinMain;

  Set8087CW(Saved8087CW);
end.

