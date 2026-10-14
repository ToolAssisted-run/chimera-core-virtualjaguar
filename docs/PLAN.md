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

## The package, the controls and the tests (2026-10-14)

- **One system, `JAG` ("Atari Jaguar")**, with a cartridge slot and a Save
  data slot for the EEPROM (exported as `jaguar.eeprom`).
- **Settings**: Boot (`virtualjaguar_bios`: the replacement start-up, or the
  console's own boot ROM), Boot ROM (Series K or Model M), PAL, Fast
  Blitter, Idle-Loop Fast-Forward (on, as upstream has it), Internal
  Resolution, True Color, Widescreen.
- **Forced off, whatever a project says**: the network link, voice chat,
  the debugger stub, texture dumping and replacing (folders), the
  GameDrive's SD card (a folder), frameskip, and upstream's input
  remapping; both ports hold a pad.
- **Controls**: two controllers, each with Up, Down, Left, Right, A, B, C,
  Option, Pause and the keypad (0 to 9, *, #): 42 buttons.

**A test cartridge of the tests' own.** `tests/make-jaguar-program.py`
writes a 1 MB cartridge whose 68000 program selects each of the four rows
of both ports and copies $F14000 and $F14002 to main RAM at $10000, and
counts its turns. Each of the 42 buttons, held alone, clears one bit of
those words and no two the same one (`jag:buttons`).

**The console's own boot ROM** refuses a cartridge that is not signed, as
the console does, so the test cartridge runs only with Boot 'disabled'.
The two demos in upstream's tree are signed, and both start through it.

**The test script**, `waterbox/run-gate.sh`: 20 tests, 20 passed, in under
a minute. 17 need no file of anyone's (the test cartridge, upstream's two
demos, Chimera's headless runner); 3 run demos from a JaguarDemos clone
(Nostalgia, YARC Reloaded, the GPU object demo). **The window test**:
3 passed (the test cartridge with a button held, the keys, the YARC demo).
**On Windows**, Chimera's headless runner plays a project of the test
cartridge and one of YARC to the Linux runner's main RAM and picture.

**Broken on purpose once**: with player 2's buttons dropped, every frame
said to have read the controllers, Boot forced off and PAL forced off,
four tests failed: `jag:buttons`, `jag:lag`, `demo:boot-rom`, `demo:pal`.

**Tried and not working**: Jag Ball (JaguarDemos) draws its scene and does
not move, nor answer the controls its README names; it reads the
controllers in about half the frames. Upstream's own check passes it on
lighting up the screen only. Not looked into.

## Not done, and why

- **The Jaguar CD**: Virtual Jaguar runs it (cue, cdi, chd); not wired up
  yet. Upstream's tree has synthetic CD images to test with.
- **The other controllers** (Team Tap, rotary, mice, analog, driving, light
  gun): pads only for now.
- **Link play**: the core is one machine, and has no sockets.
- **A commercial game**: none was tried (the owner has none).
