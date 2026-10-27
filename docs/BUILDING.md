# Building

This core is built on Linux. The result, `core.wbx`, is one file that runs in
Chimera on Linux and on Windows.

## What is needed

- GCC 13 or newer, meson, ninja, git, python3.
- A checkout of Chimera with miniBox built, for the sandbox toolchain
  (Chimera's `AGENTS.md`, "Build"). Below, `<miniBox>` is its
  `extern/chimera-common-minibox` folder.

## Virtual Jaguar's source

Virtual Jaguar is a submodule, `extern/virtualjaguar`, at the commit of its
release 3.9.0:

```sh
git submodule update --init
```

A change to Virtual Jaguar is kept as a numbered patch in `patches/`.
`waterbox/apply-patches.sh` lays the patches over the submodule (the build
runs it; it does nothing to a tree that has them). To make a patch, edit the
files in `extern/virtualjaguar`, build and test, add the file to the list in
`waterbox/make-patches.sh` if it is new, and run that script.

## What is compiled

`meson.build` lists Virtual Jaguar's files: the same list as its own
`Makefile.common`, with the SSE2 blitter its Makefile picks on x86-64 and
libchdr's unity build. Its libretro layer is compiled and used:
`waterbox/cinterface.c` calls its `retro_*` functions and answers its
questions, as a libretro frontend does. `waterbox/config/version.h` stands
in for the header upstream's Makefile generates.

## The two flavors

- `native`: for the host. `run-native` is the reference the tests compare
  the sandbox with.
- `guest`: for miniBox's sandbox. This is `core.wbx`, and `run-wbx` runs it.

```sh
meson setup build/meson-native -Dminibox_dir=<miniBox> && ninja -C build/meson-native
waterbox/setup-guest.sh -m <miniBox> && ninja -C build/meson-guest
```

Both runners take a work folder that holds what the sandbox would see: the
cartridge under its name, a file `slots` (`{"cart":["game.j64"]}`) and a
file `settings` (`{}` or, say, `{"pal":"enabled"}`); for the CD, the disc's
files, `{"disc":["disc.cue"]}` and `{"machine":"jaguarcd"}`.
`waterbox/gate-harness.h` lists the options they share (`--frames`,
`--report`, `--press`, `--axis`, `--vid-out`, `--dump-domain`,
`--savedata-out`, `--list-panel`). `CHIMERA_VJ_LOG=1` makes the native
runner print Virtual Jaguar's whole log, and `CHIMERA_VJ_OPTIONS=1` every
option with the value it was given.

## The package

```sh
waterbox/build-package.sh -r <chimera checkout>
```

builds the sandbox core and writes `build/Cores/virtualjaguar.chimeraCore` in that
checkout. `tests/make-project.py` writes a project for a game, which
Chimera's `chimera-run --project` then plays.

## The tests

```sh
CHIMERA_ROOT=<chimera checkout> waterbox/run-gate.sh
```

runs every test and says, for each, what was compared. The "jag:" and
"demo:" tests need nothing: `tests/make-jaguar-program.py` writes a
cartridge whose program reads the controllers, and upstream's tree holds
two public-domain demos. The "homebrew:" tests take a clone of 42Bastian's
JaguarDemos (public domain) and say SKIP without it:

| Tests | What they need | Where the script looks | Or name it with |
|---|---|---|---|
| `homebrew:` | `git clone https://codeberg.org/42Bastian/JaguarDemos.git` | `tests/games-local/JaguarDemos` | `JAGUAR_DEMOS` |

Without
`CHIMERA_ROOT` the test that runs the package in Chimera's engine is
skipped.

`bash tests/run-frontend.sh --chimera-root <chimera checkout>` is the window
test: the package in Chimera's own window (run headless: it needs no
display; Chimera's `tools/ci-chimera.sh` builds it). It takes the same files.

## What CI does

`.github/workflows/chimera.yml` builds the core from a fresh clone, runs
both test scripts and Chimera's checks of the package, and publishes the
package. The "jag:" and "demo:" tests, with the core's test cartridge and
upstream's two demos, run there in full; the "homebrew:" tests are skipped.
