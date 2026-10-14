#!/bin/sh
# The core's tests. Each line says what was compared. The script ends with a
# count of tests that passed, failed and were skipped, and with an error if
# any failed. A skipped test is not a pass.
#
#   waterbox/run-gate.sh
#
# CHIMERA_ROOT=<a Chimera checkout> adds the test that runs the package in
# Chimera's own headless runner (waterbox/build-package.sh -r <it> first).
# JAGUAR_DEMOS=<folder> is a clone of 42Bastian's JaguarDemos
# (https://codeberg.org/42Bastian/JaguarDemos, public domain), for the
# "homebrew:" tests (tests/games-local/JaguarDemos when not given).
#
# Needs the native build (meson setup build/meson-native ... && ninja) and
# the sandboxed core (waterbox/setup-guest.sh && ninja -C build/meson-guest):
# docs/BUILDING.md.
#
# WHAT RUNS WITH NO FILES OF YOURS. The core needs no BIOS file (Virtual
# Jaguar carries the console's boot ROMs), tests/make-jaguar-program.py
# writes a cartridge whose program reads the controllers, and upstream's own
# tree holds two public-domain demos (YARC and JagNICCC 2000), so the
# "jag:" and "demo:" tests run everywhere: the program runs, every button of
# both controllers reaches it, its reads are seen, the demos run with and
# without the console's boot ROM, PAL is 50 frames a second, and the sandbox
# gives the native build's results with savestates. The "homebrew:" tests
# need the JaguarDemos clone and say SKIP without it.
#
# The ways a test passes on a broken thing (Chimera's docs/gates.md) that
# these are written against: a machine that did nothing agrees with itself,
# so a run is first checked to have got somewhere; the end of a run hides a
# run that went another way and came back, so runs are compared as a stream
# of digests; and a comparison that cannot fail proves nothing, so each
# "the same" has a run beside it that must come out different.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
native="$root/build/meson-native/run-native"
runwbx="$root/build/meson-native/run-wbx"
core="$root/build/meson-guest/core.wbx"
chimera_root="${CHIMERA_ROOT:-}"
demos="${JAGUAR_DEMOS:-$root/tests/games-local/JaguarDemos}"
intree="$root/extern/virtualjaguar/test/roms"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
ok=0; failed=0; skipped=0
report() { # <test> <PASS|FAIL|SKIP> <what>
	printf '%-22s %-6s %s\n' "$1" "$2" "$3"
	case "$2" in PASS) ok=$((ok + 1)) ;; FAIL) failed=$((failed + 1)) ;; *) skipped=$((skipped + 1)) ;; esac
}
# check <test> <what> <condition...>
check() {
	ck_test="$1"; ck_what="$2"; shift 2
	if "$@"; then report "$ck_test" PASS "$ck_what"; else report "$ck_test" FAIL "$ck_what"; fi
}
stream() { grep '^frame' "$1"; }
same() { [ -s "$1" ] && [ -s "$2" ] && cmp -s "$1" "$2"; }
differ() { [ -s "$1" ] && [ -s "$2" ] && ! cmp -s "$1" "$2"; }
# field <file> <name>: the value after a name in the file's last report line
field() { stream "$1" | tail -1 | awk -v f="$2" '{for (i = 1; i <= NF; i++) if ($i == f) { print $(i + 1); exit }}'; }
pictures() { stream "$1" | awk '{print $7}' | sort -u | wc -l; }
# the program's words (tests/make-jaguar-program.py keeps them at $10000 of
# main RAM, big-endian): block <dump> is the eight controller words in hex,
# count <dump> its count of turns
block() { od -An -tx1 -j $((0x10000)) -N16 "$1" 2> /dev/null | tr -d ' \n'; }
count() { printf '%d' "0x$(od -An -tx1 -j $((0x10010)) -N4 "$1" 2> /dev/null | tr -d ' ')"; }
# folder <name> <settings json> <cartridge>: a work folder as the sandbox
# mounts a project - every file under its name
folder() {
	mkdir -p "$work/$1"
	ln -sf "$3" "$work/$1/$(basename "$3")"
	printf '{"cart":["%s"]}' "$(basename "$3")" > "$work/$1/slots"
	printf '%s' "$2" > "$work/$1/settings"
}
nat() { nt_out="$1"; nt_dir="$2"; shift 2; "$native" "$work/$nt_dir" "$@" > "$work/$nt_out.out" 2> "$work/$nt_out.err"; }
box() { bx_out="$1"; bx_dir="$2"; shift 2; "$runwbx" "$core" "$work/$bx_dir" "$@" > "$work/$bx_out.out" 2> "$work/$bx_out.err"; }
# index <folder> <control>: the control's place in the panel
index() { "$native" "$work/$1" --frames 1 --list-panel 2> /dev/null | grep "'$2'" | awk '{print $2}'; }
# repeats <file> <first> <second> <count> <step>: do the report lines from
# frame <second> on repeat those from frame <first> on (run-wbx --rewind)
repeats() {
	awk -v a="$2" -v b="$3" -v n="$4" -v step="$5" '
		/^frame/ { f = $2; $1 = ""; $2 = ""; sub(/ lag [0-9]+$/, ""); line[f] = $0 }
		END {
			for (i = step; i < n; i += step) {
				if (!((a + i) in line) || !((b + i) in line) || line[a + i] != line[b + i]) exit 1
				seen++
			}
			exit seen > 0 ? 0 : 1
		}' "$1"
}

if [ ! -x "$native" ] || [ ! -x "$runwbx" ] || [ ! -f "$core" ]; then
	echo "not built: this needs build/meson-native/run-native and run-wbx, and build/meson-guest/core.wbx (docs/BUILDING.md)" >&2
	exit 1
fi

# ------------------------------------------------- the source and the package
patches="$(ls "$root"/patches/*.patch 2> /dev/null | wc -l)"
check "source:patched" "extern/virtualjaguar is the pinned commit with the $patches patches of patches/" \
	sh -c "sh '$here/apply-patches.sh' > '$work/patches.log' 2>&1 && [ \"\$(git -C '$root' rev-parse HEAD:extern/virtualjaguar)\" = \"\$(git -C '$root/extern/virtualjaguar' rev-parse HEAD)\" ]"

stale=""
for src in "$here"/cinterface.c "$root"/patches/*.patch; do
	[ -e "$src" ] || continue
	[ "$core" -nt "$src" ] || stale="$stale $(basename "$src")"
done
check "package:fresh" "core.wbx is not older than its sources${stale:+ (older than:$stale)}" [ -z "$stale" ]

# ------------------------------------------------- the Jaguar, everywhere
mkdir -p "$work/carts"
python3 "$root/tests/make-jaguar-program.py" "$work/carts/prog.j64" > /dev/null
python3 "$root/tests/make-jaguar-program.py" "$work/carts/quiet.j64" nopad > /dev/null
folder pr '{}' "$work/carts/prog.j64"
folder qu '{}' "$work/carts/quiet.j64"

"$native" "$work/pr" --frames 1 --list-panel > "$work/panel.out" 2> /dev/null
check "package:controls" "the package declares the core's own $(grep -c '^panel' "$work/panel.out") buttons, in the core's order" \
	python3 - "$here/waterbox.config" "$work/panel.out" <<'PY'
import json, sys
cfg = json.load(open(sys.argv[1]))
buttons = [l[l.index("'") + 1:l.rindex("'")] for l in open(sys.argv[2]) if l.startswith("panel ")]
sys.exit(0 if cfg["input"]["buttons"] == buttons and len(buttons) == 42 else 1)
PY

nat pr-idle pr --frames 300 --report 25 --dump-domain "Main RAM" "$work/pr-idle.ram"
check "jag:runs" "a cartridge this script writes runs through the replacement start-up: its count reached $(count "$work/pr-idle.ram") in 300 frames, and it read the controllers ($(block "$work/pr-idle.ram"))" \
	sh -c "[ $(count "$work/pr-idle.ram") -gt 1000 ] && [ '$(block "$work/pr-idle.ram")' = ffefff7fffddff7fffbbff7fff77ff7f ]"

# every one of the 42 buttons, held alone: it clears one bit of the
# program's eight words, and no two buttons the same one
: > "$work/buttons.txt"
i=0
while [ $i -lt 42 ]; do
	nat b$i pr --frames 120 --press $i:60:100 --dump-domain "Main RAM" "$work/b$i.ram"
	echo "$i $(block "$work/b$i.ram")" >> "$work/buttons.txt"
	i=$((i + 1))
done
check "jag:buttons" "each of the 42 buttons of the two controllers, held alone, clears one bit of what the program reads, and each a different one" \
	python3 - "$work/buttons.txt" "$(block "$work/pr-idle.ram")" <<'PY'
import sys
idle = bytes.fromhex(sys.argv[2])
seen = set()
for line in open(sys.argv[1]):
    i, h = line.split()
    b = bytes.fromhex(h)
    diff = [(k, idle[k] ^ b[k]) for k in range(16) if idle[k] != b[k]]
    if len(diff) != 1 or bin(diff[0][1]).count("1") != 1 or (idle[diff[0][0]] & diff[0][1]) == 0:
        sys.exit(1)
    seen.add(diff[0])
sys.exit(0 if len(seen) == 42 else 1)
PY

allrun="--frames 300 --report 10 --press 0:50:40 --press 4:60:20 --press 8:100:10 --press 20:120:5 --press 21:150:30 --press 26:200:20"
nat all pr $allrun
box all-box pr $allrun
for n in all all-box pr-idle; do stream "$work/$n.out" > "$work/$n.stream"; done
check "jag:sandbox" "native and sandbox print the same $(wc -l < "$work/all.stream") digests of memory, picture and sound, with buttons of both controllers pressed" \
	same "$work/all.stream" "$work/all-box.stream"
check "jag:presses-change-the-run" "the run with presses differs from the idle one" differ "$work/all.stream" "$work/pr-idle.stream"

nat q qu --frames 300 --report 100
check "jag:lag" "the program that reads the controllers has no lag frame in 300 ($(field "$work/pr-idle.out" lag)); its twin that reads none, 300 ($(field "$work/q.out" lag))" \
	[ "$(field "$work/pr-idle.out" lag)" = 0 -a "$(field "$work/q.out" lag)" = 300 ]

box all-rerecord pr $allrun --rerecord
box all-session pr $allrun --session
stream "$work/all-rerecord.out" > "$work/all-rerecord.stream"
stream "$work/all-session.out" > "$work/all-session.stream"
check "jag:state-every-frame" "a state saved and loaded every frame changes nothing" same "$work/all-box.stream" "$work/all-rerecord.stream"
check "jag:state-other-box" "a state moved to a new sandbox half way changes nothing" same "$work/all-box.stream" "$work/all-session.stream"

# ------------------------------------------------- upstream's two demos
for d in yarc jagniccc; do
	folder $d '{}' "$intree/$d.j64"
	folder $d-bios '{"bios":"enabled"}' "$intree/$d.j64"
	folder $d-pal '{"pal":"enabled"}' "$intree/$d.j64"
	nat $d $d --frames 900 --report 25
	box $d-box $d --frames 900 --report 25
	nat $d-bios $d-bios --frames 900 --report 25
	nat $d-pal $d-pal --frames 300 --report 300
	for n in $d $d-box $d-bios; do stream "$work/$n.out" > "$work/$n.stream"; done
done
check "demo:runs" "upstream's two public-domain demos run: YARC $(pictures "$work/yarc.out") and JagNICCC 2000 $(pictures "$work/jagniccc.out") different pictures in 36 reports" \
	[ "$(pictures "$work/yarc.out")" -gt 10 -a "$(pictures "$work/jagniccc.out")" -gt 10 ]
check "demo:sandbox" "native and sandbox print the same 36 digests for each" \
	sh -c "cmp -s '$work/yarc.stream' '$work/yarc-box.stream' && cmp -s '$work/jagniccc.stream' '$work/jagniccc-box.stream' && [ -s '$work/yarc.stream' ]"
check "demo:boot-rom" "through the console's own boot ROM (Boot 'enabled') both start, another run than without it: YARC $(pictures "$work/yarc-bios.out") and JagNICCC $(pictures "$work/jagniccc-bios.out") pictures" \
	sh -c "[ $(pictures "$work/yarc-bios.out") -gt 10 ] && [ $(pictures "$work/jagniccc-bios.out") -gt 10 ] && ! cmp -s '$work/yarc-bios.stream' '$work/yarc.stream'"
check "demo:pal" "a PAL console hands out 960 pairs of samples a frame (48 kHz at 50 frames a second; $(field "$work/yarc-pal.out" aud)), an NTSC one 800 ($(field "$work/yarc.out" aud))" \
	[ "$(field "$work/yarc-pal.out" aud)" = 960 -a "$(field "$work/yarc.out" aud)" = 800 ]
box rewind yarc --frames 1600 --report 5 --rewind
check "demo:state-rewind" "a state kept at frame 800 and loaded at 1200: the frames after the load repeat those after the save" \
	repeats "$work/rewind.out" 800 1200 400 5

# ------------------------------------------------- what is refused
mkdir -p "$work/none"
printf '{"cart":[]}' > "$work/none/slots"; printf '{}' > "$work/none/settings"
nat none none --frames 1
check "refused:no-game" "a console with no game is refused, and says so" grep -q "Init failed.*no game was given" "$work/none.out" "$work/none.err"

# ------------------------------------------------- Chimera's engine
runner="$chimera_root/build/dll/chimera-run"
package="$chimera_root/build/Cores/virtualjaguar.chimeraCore"
if [ -n "$chimera_root" ] && [ -x "$runner" ] && [ -f "$package" ]; then
	mkdir -p "$work/proj"
	cp "$work/carts/prog.j64" "$work/proj/"
	python3 "$root/tests/make-project.py" "$package" "$work/proj/prog.chimeraProject" 300 \
		"press=P1 A:199:101" "press=P2 #:149:151" panel="$work/panel.out" -- cart="$work/proj/prog.j64" > /dev/null
	"$runner" --project "$work/proj/prog.chimeraProject" "$package" --files "$work/proj" --frames 300 \
		--dump "Main RAM=$work/engine.ram" > "$work/engine.log" 2>&1
	box eng pr --frames 300 --press "$(index pr "P1 A")":200:101 --press "$(index pr "P2 #")":150:151 --dump-domain "Main RAM" "$work/eng.ram"
	check "engine:jag" "a project of the program with presses plays in Chimera's headless runner to the sandbox runner's main RAM ($(wc -c < "$work/eng.ram" 2> /dev/null) bytes; the program read $(block "$work/engine.ram")), another than the idle run's" \
		sh -c "cmp -s '$work/engine.ram' '$work/eng.ram' && [ '$(block "$work/engine.ram")' != '$(block "$work/pr-idle.ram")' ]"
else
	report "engine:jag" SKIP "needs CHIMERA_ROOT with build/dll/chimera-run and build/Cores/virtualjaguar.chimeraCore"
fi

# ------------------------------------------------- homebrew
if [ -d "$demos" ]; then
	for d in nostalgia/nostalgia.j64 yarc_reloaded/cube.j64 gpuobj_hack/gpuobj.j64; do
		n="$(basename "$(dirname "$d")")"
		folder hb-$n '{}' "$demos/$d"
		nat hb-$n hb-$n --frames 1200 --report 50
		box hb-$n-box hb-$n --frames 1200 --report 50
		stream "$work/hb-$n.out" > "$work/hb-$n.stream"; stream "$work/hb-$n-box.out" > "$work/hb-$n-box.stream"
		check "homebrew:$n" "$d from JaguarDemos runs ($(pictures "$work/hb-$n.out") different pictures in 24 reports) and the sandbox gives the native build's digests" \
			sh -c "[ $(pictures "$work/hb-$n.out") -gt 10 ] && cmp -s '$work/hb-$n.stream' '$work/hb-$n-box.stream'"
	done
else
	for n in nostalgia yarc_reloaded gpuobj_hack; do report "homebrew:$n" SKIP "no JaguarDemos clone (JAGUAR_DEMOS)"; done
fi

echo
echo "$ok passed, $failed failed, $skipped skipped"
[ "$failed" -eq 0 ]
