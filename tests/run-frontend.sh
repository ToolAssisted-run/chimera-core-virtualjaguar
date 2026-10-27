#!/bin/bash
# The package in Chimera's own window (run headless: it needs no display),
# which the headless runner cannot show:
#  - the test cartridge (tests/make-jaguar-program.py) runs in the window and
#    leaves the main RAM the headless runner leaves at the same frame, with a
#    button pressed, at the picture size Virtual Jaguar gives (320x240);
#  - the keys the package ships become Chimera's keys for the controllers;
#  - upstream's YARC demo (public domain, in its tree) runs in the window
#    and leaves the headless runner's main RAM.
#
# Usage: tests/run-frontend.sh --chimera-root <chimera checkout> [--frames N] [--keep]
#   --keep   leave the work folder (logs, configurations, projects) and say where it is
# Needs: Chimera built with its window (chimera --headless), and the
# package installed in that checkout (waterbox/build-package.sh -r <chimera>).
set -u

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
wb="$root/waterbox"
frames=300
chimera_root=""
keep=""
while [ $# -gt 0 ]; do
	case "$1" in
		--keep) keep=1 ;;
		--chimera-root) chimera_root="$2"; shift ;;
		--frames) frames="$2"; shift ;;
		-*) echo "unknown option: $1" >&2; exit 2 ;;
		*) break ;;
	esac
	shift
done
[ -n "$chimera_root" ] && [ -d "$chimera_root" ] || { echo "say where Chimera is: --chimera-root <chimera checkout>" >&2; exit 2; }
chimera_root="$(cd "$chimera_root" && pwd)"
yarc="$root/extern/virtualjaguar/test/roms/yarc.j64"

chimera_exe="$chimera_root/build/meson-linux/source/ui/chimera"
package="$chimera_root/build/Cores/virtualjaguar.chimeraCore"
runwbx="$root/build/meson-native/run-wbx"
core="$root/build/meson-guest/core.wbx"
runner="$chimera_root/build/meson-linux/chimera-run"
[ -x "$chimera_exe" ] || { echo "Chimera's window is not built: $chimera_exe" >&2; exit 1; }
[ -f "$package" ] || { echo "the package is not installed: $package (run waterbox/build-package.sh -r $chimera_root)" >&2; exit 1; }
[ -x "$runwbx" ] && [ -f "$core" ] || { echo "the sandbox build is not there: $runwbx, $core" >&2; exit 1; }
[ -x "$runner" ] || { echo "Chimera's headless runner is not built: $runner" >&2; exit 1; }

work="$(mktemp -d)"
cleanup() {
	if [ -n "$keep" ]; then echo "work folder kept: $work"; else rm -rf "$work"; fi
}
trap cleanup EXIT

# run-wbx finds miniBox's host library in Chimera's build/dll
export LD_LIBRARY_PATH="$chimera_root/build/dll${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

# Chimera's window, run headless: the cores installed in the checkout, its
# settings, cache and recovery files the run's own, and nothing carried over
# from a Chimera installed on this machine
export ALSOFT_DRIVERS=null CHIMERA_CORES_DIR="$chimera_root/build/Cores" CHIMERA_QT_CACHE="$work/qt-cache" CHIMERA_QT_RECOVERY="$work/qt-recovery" \
	CHIMERA_QT_HASHES="$work/qt-file-hashes.txt" CHIMERA_QT_CHIMERA_SETTINGS="$work/no-chimera-config.ini"

ok=0
failed=0
skipped=0
report() {
	printf '%-16s %-5s %s\n' "$1" "$2" "$3"
	case "$2" in PASS) ok=$((ok + 1)) ;; SKIP) skipped=$((skipped + 1)) ;; *) failed=$((failed + 1)) ;; esac
}

# make_project <tag> <frames> <cartridge> [<setting>=<value> | press=... | firmware=<id>=<file>]...
# A project with the cartridge beside it, where Chimera looks, and a movie
# of that many frames over the controllers.
make_project() {
	local tag="$1" nframes="$2" gamefile="$3"; shift 3
	local dir="$work/$tag"
	mkdir -p "$dir"
	cp "$gamefile" "$dir/"
	python3 "$here/make-project.py" "$package" "$dir/$tag.chimeraProject" "$nframes" "panel=$work/panel.out" "$@" \
		-- "cart=$dir/$(basename "$gamefile")" > "$work/$tag.log" 2>&1
}
# run_frontend <tag> <configuration> <frames> <domain or "">: the project in the window
run_frontend() {
	local tag="$1" cfg="$2" nframes="$3" domain="$4" job="$work/job.$1.txt"
	{
		echo "frames=$nframes"
		echo "out=$work/$tag.ram.bin"
		echo "meta=$work/$tag.meta.txt"
		echo "shot="
		echo "domain=$domain"
	} > "$job"
	( cd "$chimera_root" && MINIHAWK_JOB="$job" timeout 900 "$chimera_exe" --headless \
		"--config=$cfg" "--project=$work/$tag/$tag.chimeraProject" "--lua=$here/frontend-ram.lua" ) >> "$work/$tag.log" 2>&1
	[ -f "$work/$tag.meta.txt" ] && grep -q "^status=OK" "$work/$tag.meta.txt"
}
value() { sed -n "s/^$2=//p" "$work/$1.meta.txt" 2>/dev/null; }

python3 "$here/settings-config.py" "$work/settings.base.json" '{}'

# ---- the test cartridge: needs no file of anyone's
mkdir -p "$work/prog" "$work/probe"
python3 "$here/make-jaguar-program.py" "$work/prog/prog.j64" > /dev/null
ln -sf "$work/prog/prog.j64" "$work/probe/prog.j64"
printf '{"cart":["prog.j64"]}' > "$work/probe/slots"; printf '{}' > "$work/probe/settings"
"$runwbx" "$core" "$work/probe" --frames 1 --list-panel > "$work/panel.out" 2> /dev/null
# the movie is longer than the run: a window whose movie ends stops there;
# P1 A is held from frame 100 (row 99) to the end
make_project jg $((frames + 100)) "$work/prog/prog.j64" "press=P1 A:99:$frames"
"$runner" --project "$work/jg/jg.chimeraProject" "$package" --files "$work/jg" --frames "$frames" \
	--dump "Main RAM=$work/engine.ram.bin" > "$work/engine.log" 2>&1
words="$(od -An -tx1 -j $((0x10000)) -N4 "$work/engine.ram.bin" 2> /dev/null | tr -d ' ')"
if ! run_frontend jg "$work/settings.base.json" "$frames" "Main RAM"; then
	report "window:jag" FAIL "Chimera did not finish the run: $(value jg detail) $(tail -2 "$work/jg.log" | tr '\n' ' ' | cut -c1-200)"
elif [ "$(value jg frames)" != "$frames" ] || [ "$(value jg width)" != 320 ] || [ "$(value jg height)" != 240 ]; then
	report "window:jag" FAIL "frames $(value jg frames) of $frames, picture $(value jg width)x$(value jg height) and not 320x240"
elif [ -s "$work/engine.ram.bin" ] && cmp -s "$work/engine.ram.bin" "$work/jg.ram.bin" && [ "$words" = ff7fff7d ]; then
	report "window:jag" PASS "the test cartridge ran $frames frames in Chimera's window, 320x240, with P1 A held from frame 100 (the program read $words); its main RAM ($(wc -c < "$work/jg.ram.bin") bytes) is what the headless runner leaves"
else
	report "window:jag" FAIL "the main RAM differs from the headless runner's (or one of the two is missing), or P1 A did not reach the program ($words)"
fi

# the keys the package ships are the machine's when nobody changed them (the
# window keeps only the keys a person changed; fresh settings have none)
mkdir -p "$work/keys"; cp "$work/jg/prog.j64" "$work/keys/"; sed 's/"virtualjaguar-test-[^"]*"/"virtualjaguar-test-keys"/' "$work/jg/jg.chimeraProject" > "$work/keys/keys.chimeraProject"
printf 'out=%s/keys.controls.json\nmeta=%s/keys.meta.txt\n' "$work" "$work" > "$work/job.keys.txt"
( cd "$chimera_root" && MINIHAWK_JOB="$work/job.keys.txt" timeout 900 "$chimera_exe" --headless \
	"--config=$work/settings.keys.json" "--project=$work/keys/keys.chimeraProject" "--lua=$here/dump-controls.lua" ) >> "$work/keys.log" 2>&1
if [ -f "$work/keys.meta.txt" ] && grep -q "^status=OK" "$work/keys.meta.txt"; then
	if python3 "$here/check-keybinds.py" "$work/keys.controls.json" "$wb/default_keybinds.json" "Jaguar Controllers" "P1 A" > "$work/keys.txt" 2>&1; then
		report "window:keys" PASS "$(cat "$work/keys.txt")"
	else
		report "window:keys" FAIL "$(head -1 "$work/keys.txt")"
	fi
else
	report "window:keys" FAIL "Chimera did not finish the run: $(tail -2 "$work/keys.log" | tr '\n' ' ' | cut -c1-200)"
fi

# ---- upstream's YARC demo (public domain), in the window
dframes=600
make_project yarc $((dframes + 100)) "$yarc"
"$runner" --project "$work/yarc/yarc.chimeraProject" "$package" --files "$work/yarc" --frames "$dframes" \
	--dump "Main RAM=$work/yarc-engine.ram.bin" > "$work/yarc-engine.log" 2>&1
if ! run_frontend yarc "$work/settings.base.json" "$dframes" "Main RAM"; then
	report "window:demo" FAIL "Chimera did not finish the run: $(value yarc detail) $(tail -2 "$work/yarc.log" | tr '\n' ' ' | cut -c1-200)"
elif [ "$(value yarc frames)" = "$dframes" ] && [ -s "$work/yarc-engine.ram.bin" ] && cmp -s "$work/yarc-engine.ram.bin" "$work/yarc.ram.bin"; then
	report "window:demo" PASS "upstream's YARC demo ran $dframes frames in the window, $(value yarc width)x$(value yarc height), and left the main RAM the headless runner leaves"
else
	report "window:demo" FAIL "frames $(value yarc frames) of $dframes, or the main RAM differs from the headless runner's"
fi

echo
echo "$ok passed, $failed failed, $skipped skipped"
[ "$failed" -eq 0 ]
