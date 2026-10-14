# chimera-core-virtualjaguar

A core for [Chimera](https://github.com/ToolAssisted-run/chimera), the
frontend for tool-assisted speedruns, for the **Atari Jaguar** and the **Jaguar CD**. It is built
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
- The Jaguar CD starts a disc (a .cue with its tracks, a .chd or a .cdi)
  through Virtual Jaguar's replacement for the CD's start-up, or through
  the console's own CD BIOS (carried in the core): a test disc the tests
  write, and upstream's synthetic CHD. No commercial CD was tried.
- On Windows, Chimera's headless runner plays a project to the same memory
  and picture as on Linux. Chimera's window was tried on Linux only.
- Every controller Virtual Jaguar has: pads, the Team Tap (eight pads),
  the Tempest 2000 rotary, the mice (ST, and Amiga through either
  adapter), the analog joystick, the driving controller, the paddle input,
  the 6D controller and the light gun. A test program sees each of their
  controls; no game made for them was tried.
- Not there: link play (two consoles linked).

## What you bring

The game: a cartridge as a `.j64` or `.rom` file (or `.jag`, `.abs`, `.cof`,
`.bin` for homebrew), or with Machine set to `jaguarcd` a disc as a `.cue`
with its track files, a `.chd` or a `.cdi`. Nothing else: Virtual Jaguar
carries the console's boot ROMs and starts a game through its own
replacement for the console's start-up.

## Buttons and settings

- **Pads**: Up, Down, Left, Right, A, B, C, Option, Pause, and the keypad's 0
  to 9, * and #; P1 and P2, and P3 to P8 behind Team Taps.
- **Port 1 and Port 2** (settings) say what is in each port; each port's
  other controllers have their own controls: the rotary's wheel (Spinner),
  a mouse's movement and two buttons, a stick (Stick X and Y) with A to D,
  the 6D's six axes and buttons A to G and Rezero, and in port 1 a light
  gun (Gun X and Gun Y, a fraction of the picture, and its trigger and
  buttons).
- **Settings**: Machine (the console, or the console with the Jaguar CD),
  CD Boot (the replacement start-up, or the CD's own BIOS), CD BIOS
  (retail or developers'), CD Read Speed, Boot (start at once, or through the console's own boot ROM,
  which refuses cartridges that are not signed, as the console does), Boot
  ROM (Series K or Model M), PAL, Fast Blitter, Idle-Loop Fast-Forward,
  Internal Resolution, True Color and Widescreen. All but Widescreen are
  part of the machine, so a movie needs the same values.

A cartridge's save memory (EEPROM) is exported by Emulator > Export Save
Data as `jaguar.eeprom`, the CD console's (with the Memory Track's saves)
as `jaguarcd.memtrack`, and a project's Save data slot takes such a file
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
