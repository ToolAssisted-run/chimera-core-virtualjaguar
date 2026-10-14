# Plan and design log - Virtual Jaguar core for Chimera

This is the design log of the core: what was decided, why, and what was
measured. Entries are dated. Read it before changing how the core works.

## Why this core (2026-10-14)

The owner wants every system BizHawk supports to be supported in Chimera
too. The Atari Jaguar is one of the gaps. BizHawk runs it on Virtual Jaguar;
the owner asked for a fresh port of the latest upstream, taking nothing from
BizHawk's port but ideas.

## What was read (2026-10-14)

virtualjaguar-libretro at its latest commit, 6bf3574 (release 3.9.0, the
same day), GPL version 3: the emulator (`src/`), its libretro layer
(`libretro.c`) and its documents.

## The eight questions (docs/new-core.md in chimera)

1. **Is it a new core?** Yes. No core here runs the Jaguar.
2. **May it be distributed and modified?** Yes: GPL version 3. The package
   is GPL-3.0.
3. **One thread on one clock?** Yes: the emulator starts no thread. Its
   only sockets are for link play over TCP and a debugger stub, which are
   left out (patch 0001 builds upstream's own inert versions of them).
4. **Where does the picture come from?** The emulator's own buffer, handed
   to the libretro video callback once a frame: 32-bit pixels, whose size
   follows the game's video mode.
5. **Does it recompile?** No: its processors are interpreters.
6. **What must the user bring?** The game. Virtual Jaguar carries the
   Jaguar's boot ROMs and starts a cartridge through a high-level BIOS.
7. **What can a public runner test?** Two public-domain demos in upstream's
   own tree (`test/roms`: YARC and JagNICCC 2000, from 42Bastian's
   JaguarDemos), and a test program of the core's own for the controllers
   (to be done).
8. **How big is it?** Small: 2 MB of main memory and a cartridge of up to
   6 MB.

## Owner decisions (2026-10-14)

- **The boot ROMs ship in the package, as upstream's builds have them**
  (owner-decided, 2026-10-14). Even with the high-level BIOS, Virtual
  Jaguar maps the cartridge boot ROM at 0xE00000, where games may read it.
  The licence file says so.
- **Test games are free homebrew** (owner-decided, 2026-10-14): the owner
  has no Jaguar game. Downloaded homebrew is kept in the ignored
  `tests/games-local` only.

## How the core drives Virtual Jaguar (2026-10-14)

As the PUAE core does: `waterbox/cinterface.c` calls upstream's `retro_*`
functions and answers its questions. A project's setting named like an
option less `virtualjaguar_` sets it. The controls go into the Jaguar's own
button tables at the end of the libretro layer's input step (patch 0002),
not through its RetroPad mapping. A lag frame is one in which the machine
read neither of its controller registers, $F14000 and $F14002 (patch 0003;
$F14002 also carries the cartridge EEPROM's data line, so an EEPROM read
counts too). The core defines the C library's time functions, from the
frames run (the Jaguar has no clock of its own), and locals are
zero-filled, as in the PUAE core.

## What the first step found (2026-10-14)

- Upstream builds as it is with meson from its `Makefile.common` list
  (70 files, the SSE2 blitter, libchdr's unity build); `version.h`, which
  upstream's Makefile generates, is a fixed file in `waterbox/config`.
- YARC (a wireframe) and JagNICCC 2000 (a 3D scene) run. Native and
  sandbox print the same 36 digests of memory, picture and sound over 900
  frames for each. A state saved and loaded every frame, a state moved to
  a new sandbox, and a state kept at frame 800 and loaded at 1,200 (79
  digests repeat) change nothing.
