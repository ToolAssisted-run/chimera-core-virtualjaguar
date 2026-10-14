#!/bin/bash
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
# GATE_KEEP=1 keeps the work folder (the runs' output and dumps) and says where
if [ -n "${GATE_KEEP:-}" ]; then trap 'echo "work folder kept: $work"' EXIT; else trap 'rm -rf "$work"' EXIT; fi
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
# main RAM, big-endian): block <dump> is the 56 controller words, the light
# pen's place and the paddle's four channels in hex, count <dump> its count
# of turns
block() { od -v -An -tx1 -j $((0x10000)) -N124 "$1" 2> /dev/null | tr -d ' \n'; }
count() { printf '%d' "0x$(od -v -An -tx1 -j $((0x1007C)) -N4 "$1" 2> /dev/null | tr -d ' ')"; }
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
check "package:controls" "the package declares the core's own $(grep -c '^panel' "$work/panel.out") buttons, in the core's order, and 22 axes, for both machines" \
	python3 - "$here/waterbox.config" "$work/panel.out" <<'PY'
import json, sys
cfg = json.load(open(sys.argv[1]))
buttons = [l[l.index("'") + 1:l.rindex("'")] for l in open(sys.argv[2]) if l.startswith("panel ")]
m = cfg["machines"]
sys.exit(0 if len(m) == 2 and all(x["input"]["buttons"] == buttons and len(x["input"]["axes"]) == 22 for x in m) and len(buttons) == 194 else 1)
PY

nat pr-idle pr --frames 300 --report 25 --dump-domain "Main RAM" "$work/pr-idle.ram"
check "jag:runs" "a cartridge this script writes runs through the replacement start-up: its count reached $(count "$work/pr-idle.ram") in 300 frames, and it read both pads' four rows ($(block "$work/pr-idle.ram" | cut -c1-32))" \
	sh -c "[ $(count "$work/pr-idle.ram") -gt 100 ] && [ '$(block "$work/pr-idle.ram" | cut -c1-32)' = ff7fff7fffbdff7fffdbff7fffe7ff7f ]"

# clears <idle block> <file of "index block" lines> <count>: each line
# differs from idle, only by bits cleared (a pad's button reads 0 while held,
# in each of the program's four passes through the rows), and no two lines
# alike; there are <count> lines
clears() {
	python3 - "$1" "$2" "$3" <<'PY'
import sys
idle = bytes.fromhex(sys.argv[1])
seen = set(); n = 0
for line in open(sys.argv[2]):
    i, h = line.split()
    b = bytes.fromhex(h); n += 1
    if b == idle or any(y & ~x & 0xFF for x, y in zip(idle, b)):
        sys.exit(1)
    seen.add(b)
sys.exit(0 if len(seen) == n == int(sys.argv[3]) else 1)
PY
}
# held_each <folder> <out file>: every live button of the folder's panel,
# held alone from frame 60 to the end
held_each() {
	: > "$2"
	"$native" "$work/$1" --frames 1 --list-panel 2> /dev/null | grep "^panel .* active$" | while read -r _ i _; do
		"$native" "$work/$1" --frames 120 --press "$i":60:100 --dump-domain "Main RAM" "$work/he.ram" > /dev/null 2>&1
		echo "$i $(block "$work/he.ram")" >> "$2"
	done
}
held_each pr "$work/buttons.txt"
check "jag:buttons" "each of the 42 buttons of the two pads, held alone, clears bits of what the program reads and sets none, and no two the same" \
	clears "$(block "$work/pr-idle.ram")" "$work/buttons.txt" 42

# a Team Tap in each port: eight pads, 168 buttons
folder tap '{"p1_device":"teamtap","p2_device":"teamtap"}' "$work/carts/prog.j64"
nat tap-idle tap --frames 120 --dump-domain "Main RAM" "$work/tap-idle.ram"
held_each tap "$work/tap.txt"
check "jag:teamtap" "with a Team Tap in each port, each of the 168 buttons of the eight pads (P1 to P8), held alone, clears bits of its own and sets none" \
	clears "$(block "$work/tap-idle.ram")" "$work/tap.txt" 168

# the other controllers: every live control alone changes what the program
# reads (a mouse or the wheel is moved 5 steps a frame: a quadrature
# counter's phase comes round again after 4)
devices=""
for dv in '{"p1_device":"rotary","p2_device":"mouse_st"}' '{"p2_device":"mouse_amiga"}' '{"p2_device":"mouse_amiga_adapter"}' \
          '{"p1_device":"analog","p2_device":"driving"}' '{"p1_device":"paddle","p2_device":"6d"}' '{"p1_device":"lightgun","p2_device":"rotary"}'; do
	folder dev "$dv" "$work/carts/prog.j64"
	nat dev-idle dev --frames 120 --dump-domain "Main RAM" "$work/dev-idle.ram"
	idle="$(block "$work/dev-idle.ram")"
	"$native" "$work/dev" --frames 1 --list-panel > "$work/dev-panel.out" 2> /dev/null
	nb=0; nbad=""
	while read -r _ i rest; do
		name="$(echo "$rest" | sed "s/'\(.*\)' active/\1/")"
		[ "$name" = "P1 Gun Offscreen" ] && continue
		"$native" "$work/dev" --frames 120 --press "$i":60:100 --dump-domain "Main RAM" "$work/d.ram" > /dev/null 2>&1
		nb=$((nb + 1)); [ "$(block "$work/d.ram")" = "$idle" ] && nbad="$nbad [$name]"
	done < <(grep "^panel .* active$" "$work/dev-panel.out")
	na=0
	while read -r _ i _; do
		moved=""
		for v in 5 20000 50000; do
			"$native" "$work/dev" --frames 120 --axis "$i":$v:60:100 --dump-domain "Main RAM" "$work/d.ram" > /dev/null 2>&1
			[ "$(block "$work/d.ram")" != "$idle" ] && { moved=1; break; }
		done
		na=$((na + 1)); [ -z "$moved" ] && nbad="$nbad [axis $i]"
	done < <(grep "^axis .* active$" "$work/dev-panel.out")
	devices="$devices $(echo "$dv" | tr -d '{}"'): $nb buttons and $na axes;"
	[ -n "$nbad" ] && devices="$devices NOT:$nbad;"
done
check "jag:devices" "every live control of the other controllers changes what the program reads:$devices" \
	sh -c "! echo '$devices' | grep -q NOT"

# the light gun: Gun Offscreen changes the trigger's shot
folder gun '{"p1_device":"lightgun"}' "$work/carts/prog.j64"
gt="$(index gun "P1 Trigger")"; go="$(index gun "P1 Gun Offscreen")"
nat gun-on gun --frames 120 --axis 9:32768:1:200 --axis 10:32768:1:200 --press "$gt":60:100 --dump-domain "Main RAM" "$work/gun-on.ram"
nat gun-off gun --frames 120 --axis 9:32768:1:200 --axis 10:32768:1:200 --press "$gt":60:100 --press "$go":1:200 --dump-domain "Main RAM" "$work/gun-off.ram"
check "jag:gun-offscreen" "the light gun's shot at the middle of the picture latches the light pen's place ($(block "$work/gun-on.ram" | cut -c225-232)); with Gun Offscreen held it does not ($(block "$work/gun-off.ram" | cut -c225-232))" \
	sh -c "[ '$(block "$work/gun-on.ram" | cut -c225-232)' != '$(block "$work/gun-off.ram" | cut -c225-232)' ]"

allrun="--frames 300 --report 10 --press 0:50:40 --press 4:60:20 --press 8:100:10 --press 20:120:5 --press 21:150:30 --press 26:200:20"
nat all pr $allrun
box all-box pr $allrun
for n in all all-box pr-idle; do stream "$work/$n.out" > "$work/$n.stream"; done
check "jag:sandbox" "native and sandbox print the same $(wc -l < "$work/all.stream") digests of memory, picture and sound, with buttons of both controllers pressed" \
	same "$work/all.stream" "$work/all-box.stream"
check "jag:presses-change-the-run" "the run with presses differs from the idle one" differ "$work/all.stream" "$work/pr-idle.stream"

folder dvs '{"p1_device":"analog","p2_device":"mouse_st"}' "$work/carts/prog.j64"
dvrun="--frames 300 --report 10 --axis 3:20000:50:100 --axis 4:-15000:80:60 --axis 12:5:100:50 --axis 13:-3:120:40 --press $(index dvs "P2 Mouse Left"):150:20 --press $(index dvs "P1 D"):170:30"
nat dvs dvs $dvrun
box dvs-box dvs $dvrun
box dvs-rerecord dvs $dvrun --rerecord
for n in dvs dvs-box dvs-rerecord; do stream "$work/$n.out" > "$work/$n.stream"; done
check "jag:devices-sandbox" "with an analog stick in port 1 and a mouse in port 2, both moved, native and sandbox print the same $(wc -l < "$work/dvs.stream") digests, also with a state saved and loaded every frame" \
	sh -c "[ -s '$work/dvs.stream' ] && cmp -s '$work/dvs.stream' '$work/dvs-box.stream' && cmp -s '$work/dvs-box.stream' '$work/dvs-rerecord.stream'"

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
	sh -c "cmp -s '$work/yarc.stream' '$work/yarc-box.stream' && cmp -s '$work/jagniccc.stream' '$work/jagniccc-box.stream' && [ -s '$work/yarc.stream' ] && [ -s '$work/jagniccc.stream' ]"
check "demo:boot-rom" "through the console's own boot ROM (Boot 'enabled') both start, another run than without it: YARC $(pictures "$work/yarc-bios.out") and JagNICCC $(pictures "$work/jagniccc-bios.out") pictures" \
	sh -c "[ $(pictures "$work/yarc-bios.out") -gt 10 ] && [ $(pictures "$work/jagniccc-bios.out") -gt 10 ] && ! cmp -s '$work/yarc-bios.stream' '$work/yarc.stream'"
check "demo:pal" "a PAL console hands out 960 pairs of samples a frame (48 kHz at 50 frames a second; $(field "$work/yarc-pal.out" aud)), an NTSC one 800 ($(field "$work/yarc.out" aud))" \
	[ "$(field "$work/yarc-pal.out" aud)" = 960 -a "$(field "$work/yarc.out" aud)" = 800 ]
box rewind yarc --frames 1600 --report 5 --rewind
check "demo:state-rewind" "a state kept at frame 800 and loaded at 1200: the frames after the load repeat those after the save" \
	repeats "$work/rewind.out" 800 1200 400 5

# ------------------------------------------------- the Jaguar CD
# the same program on a disc the script writes (tests/make-jaguar-program.py
# --cd), started by Virtual Jaguar's replacement for the CD's start-up
python3 "$root/tests/make-jaguar-program.py" --cd "$work/cdfiles" > /dev/null
mkdir -p "$work/cd"
for f in disc.cue track01.bin track02.bin; do ln -sf "$work/cdfiles/$f" "$work/cd/$f"; done
printf '{"disc":["disc.cue"]}' > "$work/cd/slots"; printf '{"machine":"jaguarcd"}' > "$work/cd/settings"
nat cd-idle cd --frames 300 --report 25 --dump-domain "Main RAM" "$work/cd-idle.ram"
nat cd-a cd --frames 300 --press 4:100:300 --dump-domain "Main RAM" "$work/cd-a.ram"
nat cd-hash cd --frames 300 --press 41:100:300 --dump-domain "Main RAM" "$work/cd-hash.ram"
check "cd:runs" "a disc this script writes boots on the Jaguar CD: the program's count reached $(count "$work/cd-idle.ram") in 300 frames; it reads what the cartridge's does, and P1 A and P2 # reach it" \
	sh -c "[ $(count "$work/cd-idle.ram") -gt 100 ] && [ '$(block "$work/cd-idle.ram")' = '$(block "$work/pr-idle.ram")' ] && [ '$(block "$work/cd-a.ram")' != '$(block "$work/cd-idle.ram")' ] && [ '$(block "$work/cd-hash.ram")' != '$(block "$work/cd-idle.ram")' ]"
cdrun="--frames 300 --report 10 --press 4:100:40 --press 30:150:30"
nat cd cd $cdrun
box cd-box cd $cdrun
box cd-rerecord cd $cdrun --rerecord
box cd-session cd $cdrun --session
for n in cd cd-box cd-rerecord cd-session; do stream "$work/$n.out" > "$work/$n.stream"; done
check "cd:sandbox" "native and sandbox print the same $(wc -l < "$work/cd.stream") digests for the disc, with presses" same "$work/cd.stream" "$work/cd-box.stream"
check "cd:states" "a state saved and loaded every frame, and a state moved to a new sandbox, change nothing on the CD" \
	sh -c "[ -s '$work/cd-box.stream' ] && cmp -s '$work/cd-box.stream' '$work/cd-rerecord.stream' && cmp -s '$work/cd-box.stream' '$work/cd-session.stream'"
# the console's own CD BIOS: its start-up animation, then the same program
mkdir -p "$work/cdb"
for f in disc.cue track01.bin track02.bin; do ln -sf "$work/cdfiles/$f" "$work/cdb/$f"; done
printf '{"disc":["disc.cue"]}' > "$work/cdb/slots"; printf '{"machine":"jaguarcd","cd_boot_mode":"bios"}' > "$work/cdb/settings"
nat cdb cdb --frames 1200 --report 100 --press 4:1000:300 --dump-domain "Main RAM" "$work/cdb.ram"
box cdb-box cdb --frames 1200 --report 100 --press 4:1000:300
nat cdh cd --frames 1200 --report 100 --press 4:1000:300
for n in cdb cdb-box cdh; do stream "$work/$n.out" > "$work/$n.stream"; done
check "cd:bios" "through the console's own CD BIOS (CD Boot 'bios') the disc starts after the BIOS's animation ($(pictures "$work/cdb.out") pictures in 12 reports) and the program runs (its count $(count "$work/cdb.ram")) and sees P1 A, another run than the same one through the replacement start-up ($(pictures "$work/cdh.out") pictures); the sandbox gives the native build's digests" \
	sh -c "[ $(count "$work/cdb.ram") -gt 100 ] && [ '$(block "$work/cdb.ram")' != '$(block "$work/cd-idle.ram")' ] && [ -s '$work/cdb.stream' ] && cmp -s '$work/cdb.stream' '$work/cdb-box.stream' && [ -s '$work/cdh.stream' ] && ! cmp -s '$work/cdb.stream' '$work/cdh.stream' && [ $(pictures "$work/cdb.out") -gt $(pictures "$work/cdh.out") ]"

# upstream's synthetic CHD: two sessions, an Atari boot header and a stub
mkdir -p "$work/chd"
ln -sf "$intree/synth_jagcd.chd" "$work/chd/synth_jagcd.chd"
printf '{"disc":["synth_jagcd.chd"]}' > "$work/chd/slots"; printf '{"machine":"jaguarcd"}' > "$work/chd/settings"
nat chd chd --frames 120 --report 30
box chd-box chd --frames 120 --report 30
stream "$work/chd.out" > "$work/chd.stream"; stream "$work/chd-box.out" > "$work/chd-box.stream"
check "cd:chd" "upstream's synthetic CHD (synth_jagcd.chd) opens and starts, and the sandbox gives the native build's $(wc -l < "$work/chd.stream") digests" \
	sh -c "[ \$(wc -l < '$work/chd.stream') = 4 ] && cmp -s '$work/chd.stream' '$work/chd-box.stream'"

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
	check "engine:jag" "a project of the program with presses plays in Chimera's headless runner to the sandbox runner's main RAM ($(wc -c < "$work/eng.ram" 2> /dev/null) bytes; the program's reads changed), another than the idle run's" \
		sh -c "cmp -s '$work/engine.ram' '$work/eng.ram' && [ '$(block "$work/engine.ram")' != '$(block "$work/pr-idle.ram")' ]"
	mkdir -p "$work/projcd"
	cp "$work/cdfiles/disc.cue" "$work/cdfiles/track01.bin" "$work/cdfiles/track02.bin" "$work/projcd/"
	python3 "$root/tests/make-project.py" "$package" "$work/projcd/cd.chimeraProject" 300 machine=jaguarcd \
		"press=P1 B:99:201" panel="$work/panel.out" -- disc="$work/projcd/disc.cue" > /dev/null
	"$runner" --project "$work/projcd/cd.chimeraProject" "$package" --files "$work/projcd" --frames 300 \
		--dump "Main RAM=$work/engine-cd.ram" > "$work/engine-cd.log" 2>&1
	box engcd cd --frames 300 --press "$(index pr "P1 B")":100:201 --dump-domain "Main RAM" "$work/engcd.ram"
	check "engine:jagcd" "a project of the disc (its .cue and two track files) plays in Chimera's headless runner to the sandbox runner's main RAM , another than the idle run's" \
		sh -c "cmp -s '$work/engine-cd.ram' '$work/engcd.ram' && [ '$(block "$work/engine-cd.ram")' != '$(block "$work/cd-idle.ram")' ]"
else
	report "engine:jag" SKIP "needs CHIMERA_ROOT with build/dll/chimera-run and build/Cores/virtualjaguar.chimeraCore"
	report "engine:jagcd" SKIP "needs CHIMERA_ROOT with build/dll/chimera-run and build/Cores/virtualjaguar.chimeraCore"
fi

# ------------------------------------------------- homebrew
if [ -d "$demos" ]; then
	# Jag Ball runs only through the console's own boot ROM (docs/PLAN.md):
	# A held with Up changes its turning
	folder hb-jb '{"bios":"enabled"}' "$demos/jag_ball/jag_ball.j64"
	nat hb-jb-idle hb-jb --frames 900 --report 25
	nat hb-jb hb-jb --frames 900 --report 25 --press "$(index hb-jb "P1 A")":300:30 --press "$(index hb-jb "P1 Up")":300:30
	box hb-jb-box hb-jb --frames 900 --report 25 --press "$(index hb-jb "P1 A")":300:30 --press "$(index hb-jb "P1 Up")":300:30
	for n in hb-jb-idle hb-jb hb-jb-box; do stream "$work/$n.out" > "$work/$n.stream"; done
	check "homebrew:jag_ball" "Jag Ball through the boot ROM turns ($(pictures "$work/hb-jb-idle.out") pictures), A held with Up changes the run, and the sandbox gives the native build's digests" \
		sh -c "[ $(pictures "$work/hb-jb-idle.out") -gt 10 ] && ! cmp -s '$work/hb-jb.stream' '$work/hb-jb-idle.stream' && cmp -s '$work/hb-jb.stream' '$work/hb-jb-box.stream'"
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
	for n in jag_ball nostalgia yarc_reloaded gpuobj_hack; do report "homebrew:$n" SKIP "no JaguarDemos clone (JAGUAR_DEMOS)"; done
fi

echo
echo "$ok passed, $failed failed, $skipped skipped"
[ "$failed" -eq 0 ]
