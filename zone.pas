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

unit zone;

(*
 memory allocation


H_??? The hunk manages the entire memory block given to quake.  It must be
contiguous.  Memory can be allocated from either the low or high end in a
stack fashion.  The only way memory is released is by resetting one of the
pointers.

Hunk allocations should be given a name, so the Hunk_Print () function
can display usage.

Hunk allocations are guaranteed to be 16 byte aligned.

The video buffers are allocated high to avoid leaving a hole underneath
server allocations when changing to a higher video mode.


Z_??? Zone memory functions used for small, dynamic allocations like text
strings from command input.  There is only about 48K for it, allocated at
the very bottom of the hunk.

Cache_??? Cache memory is for objects that can be dynamically loaded and
can usefully stay persistant between levels.  The size of the cache
fluctuates from level to level.

To allocate a cachable object


Temp_??? Temp memory is used for file loading and surface caching.  The size
of the cache memory is adjusted so that there is a minimum of 512k remaining
for temp memory.


------ Top of Memory -------

high hunk allocations

<--- high hunk reset point held by vid

video buffer

z buffer

surface cache

<--- high hunk used

cachable memory

<--- low hunk used

client and server low hunk allocations

<-- low hunk reset point held by host

startup hunk allocations

Zone block

----- Bottom of Memory -----



*)

interface

procedure Memory_Init(buf: pointer; size: integer);

procedure Z_Free(ptr: pointer);

function Z_Malloc(size: integer): pointer; // returns 0 filled memory
function Z_TagMalloc(size: integer; tag: integer): pointer;

//procedure Z_DumpHeap;
procedure Z_CheckHeap;
//function Z_FreeMemory: integer;

function Hunk_Alloc(size: integer): pointer; // returns 0 filled memory
function Hunk_AllocName(size: integer; name: PChar): pointer;

function Hunk_HighAllocName(size: integer; name: PChar): pointer;

function Hunk_LowMark: integer;
procedure Hunk_FreeToLowMark(mark: integer);

function Hunk_HighMark: integer;
procedure Hunk_FreeToHighMark(mark: integer);

function Hunk_TempAlloc(size: integer): pointer;

procedure Hunk_Check;

type
  Pcache_user_t = ^cache_user_t;
  cache_user_t = record
    data: pointer;
  end;

procedure Cache_Flush;

function Cache_Check(c: Pcache_user_t): pointer;
// returns the cached data, and moves to the head of the LRU list
// if present, otherwise returns NULL

procedure Cache_Free(c: Pcache_user_t);

function Cache_Alloc(c: Pcache_user_t; size: integer; name: PChar): pointer;
// Returns NULL if all purgable data was tossed and there still
// wasn't enough room.

procedure Cache_Report;

procedure Memory_Shutdown;

implementation

uses
  q_delphi,
  sys_win,
  common,
  console,
  cmd;

const
  DYNAMIC_SIZE = $C000;

  ZONEID = $1D4A11;
  MINFRAGMENT = 64;

type
  Pmemblock_t = ^memblock_t;
  memblock_t = record
    size: integer; // including the header and possibly tiny fragments
    tag: integer; // a tag of 0 is a free block
    id: integer; // should be ZONEID
    next, prev: Pmemblock_t;
    pad: integer; // pad to 64 bit boundary
  end;

type
  Pmemzone_t = ^memzone_t;
  memzone_t = record
    size: integer; // total bytes malloced, including header
    blocklist: memblock_t; // start / end cap for linked list
    rover: Pmemblock_t;
  end;

procedure Cache_FreeLow(new_low_hunk: integer); forward;
procedure Cache_FreeHigh(new_high_hunk: integer); forward;


(*
==============================================================================

            ZONE MEMORY ALLOCATION

There is never any space between memblocks, and there will never be two
contiguous free memblocks.

The rover can be left pointing at a non-empty block

The zone calls are pretty much only used for small strings and structures,
all big things are allocated on the hunk.
==============================================================================
*)

var
  mainzone: Pmemzone_t;

(*
========================
Z_ClearZone
========================
*)

procedure Z_ClearZone(zone: Pmemzone_t; size: integer);
var
  block: Pmemblock_t;
begin
// set the entire zone to one free block

  block := Pmemblock_t(integer(zone) + SizeOf(memzone_t));
  zone.blocklist.next := block;
  zone.blocklist.prev := block;
  zone.blocklist.tag := 1; // in use block
  zone.blocklist.id := 0;
  zone.blocklist.size := 0;
  zone.rover := block;

  block.prev := @zone.blocklist;
  block.next := @zone.blocklist;
  block.tag := 0; // free block
  block.id := ZONEID;
  block.size := size - SizeOf(memzone_t);
end;


(*
========================
Z_Free
========================
*)

procedure Z_Free(ptr: pointer);
var
  block, other: Pmemblock_t;
begin
  if ptr = nil then
    Sys_Error('Z_Free: NULL pointer');

  block := Pmemblock_t(integer(ptr) - SizeOf(memblock_t));
  if block.id <> ZONEID then
    Sys_Error('Z_Free: freed a pointer without ZONEID');
  if block.tag = 0 then
    Sys_Error('Z_Free: freed a freed pointer');

  block.tag := 0; // mark as free

  other := block.prev;
  if other.tag = 0 then
  begin // merge with previous free block
    other.size := other.size + block.size;
    other.next := block.next;
    other.next.prev := other;
    if block = mainzone.rover then
      mainzone.rover := other;
    block := other;
  end;

  other := block.next;
  if other.tag = 0 then
  begin // merge the next free block onto the end
    block.size := block.size + other.size;
    block.next := other.next;
    block.next.prev := block;
    if other = mainzone.rover then
      mainzone.rover := block;
  end;
end;


(*
========================
Z_Malloc
========================
*)

function Z_Malloc(size: integer): pointer;
begin
  Z_CheckHeap; // DEBUG
  result := Z_TagMalloc(size, 1);
  if result = nil then
    Sys_Error('Z_Malloc: failed on allocation of %d bytes', [size]);
  ZeroMemory(result, size);
end;

function Z_TagMalloc(size: integer; tag: integer): pointer;
var
  extra: integer;
  start, rover, new, base: Pmemblock_t;
begin
  if tag = 0 then
    Sys_Error('Z_TagMalloc: tried to use a 0 tag');

//
// scan through the block list looking for the first free block
// of sufficient size
//
  size := size + SizeOf(memblock_t); // account for size of block header
  size := size + 4; // space for memory trash tester
  size := (size + 7) and (not 7); // align to 8-byte boundary

  base := mainzone.rover;
  rover := mainzone.rover;
  start := base.prev;

  repeat
    if rover = start then // scaned all the way around the list
    begin
      result := nil;
      exit;
    end;
    if rover.tag <> 0 then
    begin
      base := rover.next;
      rover := rover.next;
    end
    else
      rover := rover.next;
  until not ((base.tag <> 0) or (base.size < size));

//
// found a block big enough
//
  extra := base.size - size;
  if extra > MINFRAGMENT then
  begin // there will be a free fragment after the allocated block
    new := Pmemblock_t(integer(base) + size);
    new.size := extra;
    new.tag := 0; // free block
    new.prev := base;
    new.id := ZONEID;
    new.next := base.next;
    new.next.prev := new;
    base.next := new;
    base.size := size;
  end;

  base.tag := tag; // no longer a free block

  mainzone.rover := base.next; // next allocation will start looking here

  base.id := ZONEID;

// marker for memory trash testing
  PInteger(integer(base) + base.size - 4)^ := ZONEID;

  result := pointer(integer(base) + SizeOf(memblock_t));
end;


(*
========================
Z_Print
========================
*)

procedure Z_Print(zone: Pmemzone_t);
var
  block: Pmemblock_t;
begin
  Con_Printf('zone size: %d  location: %x'#10, [mainzone.size, integer(mainzone)]);

  block := zone.blocklist.next;
  while true do
  begin
    Con_Printf('block:%x    size:%7d    tag:%3d'#10, [integer(block), block.size, block.tag]);

    if block.next = @zone.blocklist then
      break; // all blocks have been hit
    if (integer(block) + block.size) <> integer(block.next) then
      Con_Printf('ERROR: block size does not touch the next block'#10);
    if block.next.prev <> block then
      Con_Printf('ERROR: next block doesn''t have proper back link'#10);
    if (block.tag = 0) and (block.next.tag = 0) then
      Con_Printf('ERROR: two consecutive free blocks'#10);
    block := block.next;
  end;
end;


(*
========================
Z_CheckHeap
========================
*)

procedure Z_CheckHeap;
var
  block: Pmemblock_t;
begin
  block := mainzone.blocklist.next;
  while true do
  begin
    if block.next = @mainzone.blocklist then
      break; // all blocks have been hit
    if (integer(block) + block.size) <> integer(block.next) then
      Sys_Error('Z_CheckHeap: block size does not touch the next block');
    if block.next.prev <> block then
      Sys_Error('Z_CheckHeap: next block doesn''t have proper back link');
    if (block.tag = 0) and (block.next.tag = 0) then
      Sys_Error('Z_CheckHeap: two consecutive free blocks');
    block := block.next;
  end;
end;

//============================================================================

const
  HUNK_SENTINAL = $1DF001ED;

type
  Phunk_t = ^hunk_t;
  hunk_t = record
    sentinal: integer;
    size: integer; // including sizeof(hunk_t), -1 := not allocated
    name: array[0..7] of char;
  end;

var
  hunk_base: PByte;
  hunk_size: integer;

  hunk_low_used: integer;
  hunk_high_used: integer;

  hunk_tempactive: qboolean;
  hunk_tempmark: integer;

(*
==============
Hunk_Check

Run consistancy and sentinal trahing checks
==============
*)

procedure Hunk_Check;
var
  h: Phunk_t;
begin
  h := Phunk_t(hunk_base);
  while integer(h) <> integer(hunk_base) + hunk_low_used do
  begin
    if h.sentinal <> HUNK_SENTINAL then
      Sys_Error('Hunk_Check: trahsed sentinal');
    if (h.size < 16) or (h.size + integer(h) - integer(hunk_base) > hunk_size) then
      Sys_Error('Hunk_Check: bad size');
    h := Phunk_t(integer(h) + h.size);
  end;
end;

(*
==============
Hunk_Print

If 'all' is specified, every single allocation is printed.
Otherwise, allocations with the same name will be totaled up before printing.
==============
*)

procedure Hunk_Print(all: qboolean);
var
  h, next, endlow, starthigh, endhigh: Phunk_t;
  sum: integer;
  totalblocks: integer;
  name: array[0..8] of char;
begin
  name[8] := #0;
  sum := 0;
  totalblocks := 0;

  h := Phunk_t(hunk_base);
  endlow := Phunk_t(integer(hunk_base) + hunk_low_used);
  starthigh := Phunk_t(integer(hunk_base) + hunk_size - hunk_high_used);
  endhigh := Phunk_t(integer(hunk_base) + hunk_size);

  Con_Printf('          :%8d total hunk size'#10, [hunk_size]);
  Con_Printf('-------------------------'#10);

  while true do
  begin
  //
  // skip to the high hunk if done with low hunk
  //
    if h = endlow then
    begin
      Con_Printf('-------------------------'#10);
      Con_Printf('          :%8d REMAINING'#10, [hunk_size - hunk_low_used - hunk_high_used]);
      Con_Printf('-------------------------'#10);
      h := starthigh;
    end;

  //
  // if totally done, break
  //
    if h = endhigh then
      break;

  //
  // run consistancy checks
  //
    if h.sentinal <> HUNK_SENTINAL then
      Sys_Error('Hunk_Check: trahsed sentinal');
    if (h.size < 16) or (h.size + integer(h) - integer(hunk_base) > hunk_size) then
      Sys_Error('Hunk_Check: bad size');

    next := Phunk_t(integer(h) + h.size);
    inc(totalblocks);
    inc(sum, h.size);

  //
  // print the single block
  //
    memcpy(@name, @h.name, 8);
    if all then
      Con_Printf('%8x :%8d %8s'#10, [integer(h), h.size, name]);

  //
  // print the total
  //
    if (next = endlow) or (next = endhigh) or (strncmp(h.name, next.name, 8) <> 0) then
    begin
      if not all then
        Con_Printf('          :%8d %8s (TOTAL)'#10, [sum, name]);
      sum := 0;
    end;

    h := next;
  end;

  Con_Printf('-------------------------'#10);
  Con_Printf('%8d total blocks'#10, [totalblocks]);

end;

(*
===================
Hunk_AllocName
===================
*)

function Hunk_AllocName(size: integer; name: PChar): pointer;
var
  h: Phunk_t;
begin
  if size < 0 then Sys_Error('Hunk_Alloc: bad size: %d', [size]);

  size := SizeOf(hunk_t) + ((size + 15) and (not 15));

  if hunk_size - hunk_low_used - hunk_high_used < size then
    Sys_Error('Hunk_Alloc: failed on %d bytes', [size]);

  h := Phunk_t(integer(hunk_base) + hunk_low_used);
  inc(hunk_low_used, size);

  Cache_FreeLow(hunk_low_used);

  memset(h, 0, size);

  h.size := size;
  h.sentinal := HUNK_SENTINAL;
  Q_strncpy(h.name, name, 8);

  result := pointer(integer(h) + SizeOf(h^));
end;

(*
===================
Hunk_Alloc
===================
*)

function Hunk_Alloc(size: integer): pointer;
begin
  result := Hunk_AllocName(size, 'unknown');
end;

function Hunk_LowMark: integer;
begin
  result := hunk_low_used;
end;

procedure Hunk_FreeToLowMark(mark: integer);
begin
  if (mark < 0) or (mark > hunk_low_used) then
    Sys_Error('Hunk_FreeToLowMark: bad mark %d', [mark]);
  memset(pointer(integer(hunk_base) + mark), 0, hunk_low_used - mark);
  hunk_low_used := mark;
end;

function Hunk_HighMark: integer;
begin
  if hunk_tempactive then
  begin
    hunk_tempactive := false;
    Hunk_FreeToHighMark(hunk_tempmark);
  end;

  result := hunk_high_used;
end;

procedure Hunk_FreeToHighMark(mark: integer);
begin
  if hunk_tempactive then
  begin
    hunk_tempactive := false;
    Hunk_FreeToHighMark(hunk_tempmark);
  end;
  if (mark < 0) or (mark > hunk_high_used) then
    Sys_Error('Hunk_FreeToHighMark: bad mark %d', [mark]);
  memset(pointer(integer(hunk_base) + hunk_size - hunk_high_used), 0, hunk_high_used - mark);
  hunk_high_used := mark;
end;


(*
===================
Hunk_HighAllocName
===================
*)

function Hunk_HighAllocName(size: integer; name: PChar): pointer;
var
  h: Phunk_t;
begin
  if size < 0 then
    Sys_Error('Hunk_HighAllocName: bad size: %d', [size]);

  if hunk_tempactive then
  begin
    Hunk_FreeToHighMark(hunk_tempmark);
    hunk_tempactive := false;
  end;

  size := SizeOf(hunk_t) + ((size + 15) and (not 15));

  if hunk_size - hunk_low_used - hunk_high_used < size then
  begin
    Con_Printf('Hunk_HighAlloc: failed on %d bytes'#10, [size]);
    result := nil;
    exit;
  end;

  inc(hunk_high_used, size);
  Cache_FreeHigh(hunk_high_used);

  h := Phunk_t(integer(hunk_base) + hunk_size - hunk_high_used);

  memset(h, 0, size);
  h.size := size;
  h.sentinal := HUNK_SENTINAL;
  Q_strncpy(h.name, name, 8);

  result := pointer(integer(h) + SizeOf(h^));
end;


(*
=================
Hunk_TempAlloc

Return space from the top of the hunk
=================
*)

function Hunk_TempAlloc(size: integer): pointer;
begin
  size := (size + 15) and (not 15);

  if hunk_tempactive then
  begin
    Hunk_FreeToHighMark(hunk_tempmark);
    hunk_tempactive := false;
  end;

  hunk_tempmark := Hunk_HighMark;

  result := Hunk_HighAllocName(size, 'temp');

  hunk_tempactive := true;
end;

(*
===============================================================================

CACHE MEMORY

===============================================================================
*)

type
  Pcache_system_t = ^cache_system_t;
  cache_system_t = record
    size: integer; // including this header
    user: Pcache_user_t;
    name: array[0..15] of char;
    prev, next: Pcache_system_t;
    lru_prev, lru_next: Pcache_system_t; // for LRU flushing
  end;

function Cache_TryAlloc(size: integer; nobottom: qboolean): Pcache_system_t; forward;

var
  cache_head: cache_system_t;

(*
===========
Cache_Move
===========
*)

procedure Cache_Move(c: Pcache_system_t);
var
  n: Pcache_system_t;
begin
// we are clearing up space at the bottom, so only allocate it late
  n := Cache_TryAlloc(c.size, true);
  if n <> nil then
  begin
//    Con_Printf ('cache_move ok\n');

    memcpy(pointer(integer(n) + SizeOf(cache_system_t)),
      pointer(integer(c) + SizeOf(cache_system_t)),
      c.size - SizeOf(cache_system_t));
    n.user := c.user;
    memcpy(@n.name, @c.name, SizeOf(n.name));
    Cache_Free(c.user);
    n.user.data := pointer(integer(n) + SizeOf(cache_system_t));
  end
  else
  begin
//    Con_Printf ('cache_move failed\n');

    Cache_Free(c.user); // tough luck...
  end;
end;

(*
============
Cache_FreeLow

Throw things out until the hunk can be expanded to the given point
============
*)

procedure Cache_FreeLow(new_low_hunk: integer);
var
  c: Pcache_system_t;
begin
  while true do
  begin
    c := cache_head.next;
    if c = @cache_head then
      exit; // nothing in cache at all
    if integer(c) >= integer(hunk_base) + new_low_hunk then
      exit; // there is space to grow the hunk
    Cache_Move(c); // reclaim the space
  end;
end;

(*
============
Cache_FreeHigh

Throw things out until the hunk can be expanded to the given point
============
*)

procedure Cache_FreeHigh(new_high_hunk: integer);
var
  c, prev: Pcache_system_t;
begin
  prev := nil;
  while true do
  begin
    c := cache_head.prev;
    if c = @cache_head then
      exit; // nothing in cache at all
    if integer(c) + c.size <= integer(hunk_base) + hunk_size - new_high_hunk then
      exit; // there is space to grow the hunk
    if c = prev then
      Cache_Free(c.user) // didn't move out of the way
    else
    begin
      Cache_Move(c); // try to move it
      prev := c;
    end;
  end;
end;

procedure Cache_UnlinkLRU(cs: Pcache_system_t);
begin
  if (cs.lru_next = nil) or (cs.lru_prev = nil) then
    Sys_Error('Cache_UnlinkLRU: NULL link');

  cs.lru_next.lru_prev := cs.lru_prev;
  cs.lru_prev.lru_next := cs.lru_next;

  cs.lru_prev := nil;
  cs.lru_next := nil;
end;

procedure Cache_MakeLRU(cs: Pcache_system_t);
begin
  if (cs.lru_next <> nil) or (cs.lru_prev <> nil) then
    Sys_Error('Cache_MakeLRU: active link');

  cache_head.lru_next.lru_prev := cs;
  cs.lru_next := cache_head.lru_next;
  cs.lru_prev := @cache_head;
  cache_head.lru_next := cs;
end;

(*
============
Cache_TryAlloc

Looks for a free block of memory between the high and low hunk marks
Size should already include the header and padding
============
*)

function Cache_TryAlloc(size: integer; nobottom: qboolean): Pcache_system_t;
var
  cs: Pcache_system_t;
begin

// is the cache completely empty?

  if not nobottom and (cache_head.prev = @cache_head) then
  begin
    if hunk_size - hunk_high_used - hunk_low_used < size then
      Sys_Error('Cache_TryAlloc: %d is greater then free hunk', [size]);

    result := Pcache_system_t(integer(hunk_base) + hunk_low_used);
    memset(result, 0, SizeOf(result^));
    result.size := size;

    cache_head.prev := result;
    cache_head.next := result;
    result.prev := @cache_head;
    result.next := @cache_head;

    Cache_MakeLRU(result);
    exit;
  end;

// search from the bottom up for space

  result := Pcache_system_t(integer(hunk_base) + hunk_low_used);
  cs := cache_head.next;

  repeat
    if not nobottom or (cs <> cache_head.next) then
    begin
      if integer(cs) - integer(result) >= size then
      begin // found space
        memset(result, 0, SizeOf(result^));
        result.size := size;

        result.next := cs;
        result.prev := cs.prev;
        cs.prev.next := result;
        cs.prev := result;

        Cache_MakeLRU(result);

        exit;
      end;
    end;

  // continue looking
    result := Pcache_system_t(integer(cs) + cs.size);
    cs := cs.next;

  until cs = @cache_head;

// try to allocate one at the very end
  if integer(hunk_base) + hunk_size - hunk_high_used - integer(result) >= size then
  begin
    memset(result, 0, SizeOf(result^));
    result.size := size;

    result.next := @cache_head;
    result.prev := cache_head.prev;
    cache_head.prev.next := result;
    cache_head.prev := result;

    Cache_MakeLRU(result);

    exit;
  end;

  result := nil; // couldn't allocate
end;

(*
============
Cache_Flush

Throw everything out, so new data will be demand cached
============
*)

procedure Cache_Flush;
begin
  while cache_head.next <> @cache_head do
    Cache_Free(cache_head.next.user); // reclaim the space
end;


(*
============
Cache_Print

============
*)

procedure Cache_Print;
var
  cd: Pcache_system_t;
begin
  cd := cache_head.next;
  while cd <> @cache_head do
  begin
    Con_Printf('%8d : %s'#10, [cd.size, cd.name]);
    cd := cd.next;
  end;
end;

(*
============
Cache_Report

============
*)

procedure Cache_Report;
begin
  Con_DPrintf('%4.1f megabyte data cache'#10, [(hunk_size - hunk_high_used - hunk_low_used) / (1024 * 1024)]);
end;

(*
============
Cache_Compact

============
*)

procedure Cache_Compact; // JVAL remove?
begin
end;

(*
============
Cache_Init

============
*)

procedure Cache_Init;
begin
  cache_head.next := @cache_head;
  cache_head.prev := @cache_head;
  cache_head.lru_next := @cache_head;
  cache_head.lru_prev := @cache_head;

  Cmd_AddCommand('flush', Cache_Flush);
end;

(*
==============
Cache_Free

Frees the memory and removes it from the LRU list
==============
*)

procedure Cache_Free(c: Pcache_user_t);
var
  cs: Pcache_system_t;
begin
  if c.data = nil then
    Sys_Error('Cache_Free: not allocated');

  cs := Pcache_system_t(c.data);
  dec(cs);

  cs.prev.next := cs.next;
  cs.next.prev := cs.prev;
  cs.next := nil;
  cs.prev := nil;

  c.data := nil;

  Cache_UnlinkLRU(cs);
end;



(*
==============
Cache_Check
==============
*)

function Cache_Check(c: Pcache_user_t): pointer;
var
  cs: Pcache_system_t;
begin
  if c.data = nil then
  begin
    result := nil;
    exit;
  end;

  cs := Pcache_system_t(c.data);
  dec(cs);

// move to head of LRU
  Cache_UnlinkLRU(cs);
  Cache_MakeLRU(cs);

  result := c.data;
end;


(*
==============
Cache_Alloc
==============
*)

function Cache_Alloc(c: Pcache_user_t; size: integer; name: PChar): pointer;
var
  cs: Pcache_system_t;
begin
  if c.data <> nil then
    Sys_Error('Cache_Alloc: allready allocated');

  if size <= 0 then
    Sys_Error('Cache_Alloc: size %d', [size]);

  size := (size + SizeOf(cache_system_t) + 15) and (not 15);

// find memory for it
  while true do
  begin
    cs := Cache_TryAlloc(size, false);
    if cs <> nil then
    begin
      strncpy(cs.name, name, SizeOf(cs.name) - 1);
      c.data := pointer(integer(cs) + SizeOf(cache_system_t));
      cs.user := c;
      break;
    end;

  // free the least recently used cahedat
    if cache_head.lru_prev = @cache_head then
      Sys_Error('Cache_Alloc: out of memory');
                          // not enough memory at all
    Cache_Free(cache_head.lru_prev.user);
  end;

  result := Cache_Check(c);
end;

//============================================================================


(*
========================
Memory_Init
========================
*)
procedure Memory_Init(buf: pointer; size: integer);
var
  p: integer;
  zonesize: integer;
begin
  zonesize := DYNAMIC_SIZE;
  hunk_base := buf;
  hunk_size := size;
  hunk_low_used := 0;
  hunk_high_used := 0;

  Cache_Init;
  p := COM_CheckParm('-zone');
  if p <> 0 then
  begin
    if p < com_argc - 1 then
      zonesize := Q_atoi(com_argv[p + 1]) * 1024
    else
      Sys_Error('Memory_Init: you must specify a size in KB after -zone');
  end;
  mainzone := Hunk_AllocName(zonesize, 'zone');
  Z_ClearZone(mainzone, zonesize);
end;


procedure Memory_Shutdown;
begin
  memfree(Pointer(hunk_base), hunk_size);
end;

end.

