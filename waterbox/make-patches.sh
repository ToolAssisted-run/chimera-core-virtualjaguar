#!/bin/sh
# Writes patches/ from the patched extern/virtualjaguar tree: the reverse of
# apply-patches.sh. A patch is the tree's difference in a list of files. Edit
# the tree, run this, and apply-patches.sh must then say "already applied".
# A file is in ONE patch, whole.
set -eu
trap '' PIPE
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
tree="$root/extern/virtualjaguar"

# name | files (space separated), in the order the patches apply
series='
0001-chimera-no-sockets|src/jerry/jlink_tcp.c src/jerry/jlink_discover.c src/debug/gdbsock.c
0002-chimera-the-cores-controls-go-in-last|libretro.c
0003-chimera-reads-of-the-controllers-are-counted|src/jerry/joystick.c
'

rm -f "$root"/patches/*.patch
printf '%s\n' "$series" | grep '|' | while IFS='|' read -r name files; do
	# shellcheck disable=SC2086
	git -C "$tree" diff -- $files > "$root/patches/$name.patch"
	echo "$name.patch: $(grep -c '^diff --git' "$root/patches/$name.patch") files"
done
# a changed file no patch names would be lost by a fresh clone
left="$(git -C "$tree" status --porcelain | wc -l)"
named="$(cat "$root"/patches/*.patch | grep -c '^diff --git')"
[ "$left" -eq "$named" ] || { echo "extern/virtualjaguar has $left changed files and the patches name $named: add the rest to the series" >&2; exit 1; }
