# chimera-core-virtualjaguar

A core for [Chimera](https://github.com/ToolAssisted-run/chimera), the
frontend for tool-assisted speedruns, for the **Atari Jaguar**. It is built
on [Virtual Jaguar](https://github.com/libretro/virtualjaguar-libretro) 3.9.0
and produces one file, `virtualjaguar.chimeraCore`, that goes in Chimera's
`Cores` folder.

## Status

New, and not published yet.

- Cartridges run, and the sandboxed core gives the same results as a plain
  native build: picture, sound, both controllers, lag frames and
  savestates. Tried: the public-domain demos of 42Bastian's JaguarDemos
  (YARC, JagNICCC 2000, Nostalgia, the GPU object demo and others), with
  and without the console's boot ROM, NTSC and PAL. No commercial game was
  tried.
- On Windows, Chimera's headless runner plays a project to the same memory
  and picture as on Linux. Chimera's window was tried on Linux only.
- Not there: the Jaguar CD, the controllers other than the pad (the Team
  Tap, the rotary, the mouse, the analog and driving controllers, the light
  gun), and link play.

## What you bring

The game's cartridge: a `.j64` or `.rom` file (or `.jag`, `.abs`, `.cof`,
`.bin` for homebrew). Nothing else: Virtual Jaguar carries the console's
boot ROMs and starts a cartridge through its own replacement for the
console's start-up.

## Buttons and settings

- **Two controllers**: Up, Down, Left, Right, A, B, C, Option, Pause, and the
  keypad's 0 to 9, * and #.
- **Settings**: Boot (start at once, or through the console's own boot ROM,
  which refuses cartridges that are not signed, as the console does), Boot
  ROM (Series K or Model M), PAL, Fast Blitter, Idle-Loop Fast-Forward,
  Internal Resolution, True Color and Widescreen. All but Widescreen are
  part of the machine, so a movie needs the same values.

A cartridge's save memory (EEPROM) is exported by Emulator > Export Save
Data as `jaguar.eeprom`, and a project's Save data slot takes such a file
(or a RetroArch `.srm`) to start from. RAM Watch and RAM Search read the
Jaguar's 2 MB of main memory as Main RAM.

## Building and testing

[docs/BUILDING.md](docs/BUILDING.md) has every step. [docs/PLAN.md](docs/PLAN.md)
is the design log: what was decided, why, and what was measured.

## Licence

This repository's own code is MIT. Virtual Jaguar is under the GNU General
Public License version 3, and so are the patches to it here and the program
in the built package. As upstream's own builds do, the package carries the
Atari Jaguar's boot ROMs that Virtual Jaguar has in its source. It contains
no game. See [LICENSE](LICENSE).

The test demos are 42Bastian's [JaguarDemos](https://codeberg.org/42Bastian/JaguarDemos),
public domain; two of them are in Virtual Jaguar's own tree.
