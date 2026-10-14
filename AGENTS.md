# AGENTS.md - Virtual Jaguar core for Chimera

This repository builds Virtual Jaguar (https://github.com/libretro/virtualjaguar-libretro),
the Atari Jaguar emulator, as a core for Chimera
(https://github.com/ToolAssisted-run/chimera), a frontend for tool-assisted
speedruns. It produces one file, `virtualjaguar.chimeraCore`: Virtual Jaguar
compiled to run inside Chimera's sandbox (miniBox), a small program around
it, and the declarations Chimera reads (buttons, settings, file types).

Read [docs/BUILDING.md](docs/BUILDING.md) before building and
[docs/PLAN.md](docs/PLAN.md) before changing how the core works: it is the
design log, with what was decided, why, and what was measured.

## Layout

- `extern/virtualjaguar` - Virtual Jaguar at its release 3.9.0, a
  submodule. Never edited in place: a change is a numbered patch in
  `patches/`, laid over the submodule by `waterbox/apply-patches.sh` and
  written by `waterbox/make-patches.sh` (its list says which file is in
  which patch; a file is in one patch, whole). Every change is inside
  `#ifdef CHIMERA_CORE` with a comment that says why.
- `meson.build` - the build of both flavors, with Virtual Jaguar's files
  listed from its own `Makefile.common`.
- `waterbox/cinterface.c` - the program around Virtual Jaguar: it answers
  its libretro questions from the project, forces off what a core must not
  do (`kForced`: the network link, voice chat, the debugger stub, texture
  folders, the GameDrive's SD card, frameskip), drives `retro_load_game`
  and `retro_run`, fills the Jaguar's button tables, and is what Chimera's
  engine calls. It also defines the C library's time functions. The same
  file is compiled for the sandbox and for the host.
- `waterbox/config/version.h` - stands in for upstream's generated header.
- `waterbox/waterbox.config`, `file_slots.json`, `default_keybinds.json`,
  `package-licenses.json` - what the package declares.
- `waterbox/run-native.c`, `waterbox/run-wbx.c` - the native runner and the
  sandbox runner, with `waterbox/gate-harness.h`.
- `waterbox/*.sh` - `apply-patches.sh`, `make-patches.sh`, `setup-guest.sh`,
  `build-package.sh`, `run-gate.sh` (the test script).
- `tests/` - `make-jaguar-program.py` (writes the test cartridge),
  `run-frontend.sh` (the window test, with its helpers), `make-project.py`.
- `build/` - every build output; `tests/games-local/` - the JaguarDemos
  clone. Both are ignored by git.

## Build and test

```sh
git submodule update --init
meson setup build/meson-native -Dminibox_dir=<miniBox> && ninja -C build/meson-native
waterbox/setup-guest.sh -m <miniBox> && ninja -C build/meson-guest
waterbox/build-package.sh -r <chimera checkout>
CHIMERA_ROOT=<chimera checkout> waterbox/run-gate.sh
TMPDIR=$PWD/build/t bash tests/run-frontend.sh --chimera-root <chimera checkout>
```

Run both test scripts before every commit that touches what they cover, and
say in the commit what ran, with the numbers. A new test is broken on
purpose once and seen to fail.

## Rules of the repository

- **One thread, no sockets.** Virtual Jaguar starts no thread; its link
  play and debugger sockets are left out by patch 0001 (upstream's own
  inert versions are built).
- **No host clock.** The core defines `time`, `gettimeofday`,
  `clock_gettime`, `localtime` and `localtime_r` from the frames run.
- **Pads go into the Jaguar's button tables directly** at the end of the
  libretro layer's input step (patch 0002), not through its RetroPad
  mapping; the other controllers are upstream's models, fed through
  `controller_state()`'s answers to the layer's libretro questions. The test `package:controls` compares the panel with
  `waterbox.config`; `jag:buttons` holds that each button reaches the
  machine as one bit of its own.
- **Read memory with `od -v`**: without it a repeated line prints as `*`.
- **A quadrature device moved by a multiple of 4** comes back to the same
  phase: test a mouse or the wheel with 5 steps a frame.
- **The test program keeps a press only while it lasts.** A test that
  reads memory at the end holds the button to the end
  (`--press F:N` holds frames F to F+N-1).
- **The console's real boot ROM refuses unsigned cartridges**, as the
  console does: the test cartridge runs with Boot 'disabled' only; the
  demos in upstream's tree are signed and test the boot ROM.
- **Options by name**: a setting named like an option less
  `virtualjaguar_` sets it; an option that names no default has its first
  value.
- **No commercial game** is committed, uploaded to CI or attached to an
  issue. The JaguarDemos are public domain; credit them where they are used.
- **Say what was not tried.** No commercial Jaguar game has been run.
- **Write in plain language**; `.md` files are ASCII.
- **Commits**: `type(scope): what changed`; a short body with what changed,
  why, and how it was tested, with the numbers. Stage explicit paths. No
  amending, no force push.

## What is the owner's to decide

Publishing, the roster row in Chimera, moving to another Virtual Jaguar
release, and anything a licence does not plainly allow. The owner decided
on 2026-10-14 that the package ships the boot ROMs as upstream's builds do.
