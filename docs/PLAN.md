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
lighting up the screen only. (Looked into on 2026-10-14: see "Jag Ball".)

## Not done, and why

- **Link play** (JagLink, the CatBox, the Voice Modem): two consoles
  joined by a cable. A Chimera core is one machine, so there is no second
  console to join; Virtual Jaguar's own ways of joining one (over TCP, or
  RetroArch's netplay) are network links, which a core does not have.
- **A commercial game**: none was tried (the owner has none).

## The Jaguar CD (2026-10-14)

- **A second machine, `JAGCD` ("Atari Jaguar CD")**, chosen by the Machine
  setting (`jaguar` or `jaguarcd`); the same controls. Its slot is a Disc
  (a .cue with its track files, a .chd or a .cdi), given to Virtual Jaguar
  by its name as upstream wants (it reads the tracks itself). The CD starts
  through Virtual Jaguar's replacement for the CD's start-up (its default),
  or through the console's own CD BIOS (see "The CD BIOS").
- **Save data**: a CD console's save memory is the EEPROM and the Memory
  Track together (131,328 bytes), exported as `jaguarcd.memtrack`.
- **A test disc**: `tests/make-jaguar-program.py --cd` writes `disc.cue`
  with two tracks: a silent first session, and in the second the Atari
  boot header with the same test program after it, loaded at $4000 (the
  layout of upstream's own synthetic discs, the bytes swapped as the
  Jaguar's bus has them).

Measured: the test disc boots and its program sees P1 A and P2 #; native
and sandbox print the same 30 digests with presses; a state saved and
loaded every frame and one moved to a new sandbox change nothing;
upstream's synthetic CHD opens and starts in both; a project of the disc
(the .cue and its two tracks) plays in Chimera's headless runner to the
sandbox runner's main RAM. With the Machine setting ignored on purpose,
four of these tests failed; `cd:states` passed on two empty runs, and now
requires a run that got somewhere.

Counts: the test script 25 passed, 0 failed, 0 skipped; the window test 3
passed.

A trap for whoever writes the next test: the test program keeps a press
only while it lasts (`--press F:N` holds frames F to F+N-1), so a test
that reads memory at the end holds the button to the end.

## Jag Ball (2026-10-14)

Through the console's own boot ROM (Boot 'enabled'), Jag Ball runs: its
ball turns (19 different pictures in 36 reports), and A held with Up
changes the run from the frame they are pressed; the sandbox gives the
native build's digests. Through Virtual Jaguar's replacement start-up its
graphics processor never draws, on PAL or NTSC, with or without the
idle-loop fast-forward and the fast blitter: the demo depends on a state
the real boot ROM leaves, which upstream's replacement does not make. That
is a gap in upstream's start-up and is left as it is; the test
`homebrew:jag_ball` runs it with Boot 'enabled'.

## Every controller (2026-10-14)

- **Port 1 and Port 2 are settings**, with Virtual Jaguar's own values:
  pad, teamtap, rotary, analog, driving, paddle and 6d in either port, a
  light gun in port 1, the three mice (ST, Amiga through the ST adapter,
  Amiga through the Amiga adapter) in port 2.
- **Pads, also behind a Team Tap, go into the button tables directly**
  (P1, P3, P4, P5 in port 1's four sockets; P2, P6, P7, P8 in port 2's).
  The rotary keeps its pad's buttons there too, without the directions.
- **The other controllers are Virtual Jaguar's own models** (inputdev.c:
  quadrature counters, bank switching, the light pen latch, the paddle's
  converter). Its libretro layer asks for their state through libretro;
  `controller_state()` answers from the project's controls. A light gun's
  aim is a fraction of the picture (0 to 65535), as Chimera's pointers
  are, turned into libretro's -32768 to 32767.
- **A device is live from the start.** Upstream keeps a mouse or a stick
  inert until it first moves (a frontend might not send analog input at
  all); a project says what is plugged in, so patch 0002 makes it live at
  once.
- **The test program** now writes both ports' four rows in order 0 to 3,
  four times over (the analog, driving and 6D controllers switch banks on
  row 3 followed by row 0, and the 6D has three banks), then the twelve
  selects of the Team Tap's sockets, and reads the light pen's latch and
  the paddle's four channels.

Measured: each of the 168 buttons of eight pads clears bits of its own
(`jag:teamtap`); every live control of every other controller changes
what the program reads (`jag:devices`, all six pairings); a shot with Gun
Offscreen held latches nothing (`jag:gun-offscreen`); an analog stick and
a mouse moved give the same digests natively and in the sandbox, also
with a state saved and loaded every frame (`jag:devices-sandbox`). Broken
on purpose (the Team Tap's sockets not filled, the mouse given nothing,
Gun Offscreen ignored): those three tests failed.

Traps found on the way: a mouse or the wheel moved by a multiple of 4
steps a frame shows no change in a program that keeps the last read (a
quadrature counter's phase comes round); `od` prints `*` for a line that
repeats the one before, so the test script reads memory with `od -v`.

Counts: the test script 30 passed, 0 failed, 0 skipped (with homebrew:jag_ball); the window test 3
passed; package checks 18 of 18.

## The CD BIOS (2026-10-14)

Three settings, upstream's options: CD Boot (`cd_boot_mode`: 'hle', the
default, Virtual Jaguar's replacement start-up; 'bios', the console's own
CD BIOS, which also turns the boot ROM on; 'auto', Virtual Jaguar's choice
by the disc), CD BIOS (`cd_bios_type`: 'retail' or 'dev'), and CD Read
Speed (`cd_read_speed`, for the replacement start-up only). The CD BIOSes
are among the ROMs Virtual Jaguar carries.

Measured: the retail CD BIOS shows its start-up animation and then starts
the test disc; the program runs and sees P1 A; native and sandbox print the
same digests; the run differs from the same run through the replacement
start-up (`cd:bios`). The developers' CD BIOS does not start the test
disc: it is made for developers' discs. Broken on purpose (CD Boot forced
to 'hle'): `cd:bios` failed. It had first passed with the fault in,
because it compared with an unrelated run, which always differs; it now
compares with the same run through the replacement start-up.

Counts: the test script 31 passed, 0 failed, 0 skipped.

**On Windows** (2026-10-14, the package at this point): Chimera's
headless runner plays a project of the test disc through the console's CD
BIOS (1,300 frames, P1 A held at the end) and one of the test cartridge
with an analog stick in port 1 and a mouse in port 2, both moved in the
movie, to the Linux runner's main RAM and picture.
