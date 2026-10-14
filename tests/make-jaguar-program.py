#!/usr/bin/env python3
"""Writes a Jaguar cartridge (.j64, 1 MB) whose program is a small test of
the controllers for the Virtual Jaguar core's tests. It needs no file of
anyone's.

usage: make-jaguar-program.py <out.j64> [nopad]
       make-jaguar-program.py --cd <folder> [nopad]

With --cd it writes a Jaguar CD instead, disc.cue with track01.bin and
track02.bin in the folder: a silent first session, and in the second the
Atari boot header with the same program after it, loaded at $4000 (the
layout upstream's tests/tools/gen_synth_jagcd_vpregap.py writes).

The program, hand-assembled below (68000 machine code), starts at $802000,
where the high-level BIOS jumps. For ever, it:
  - for each of 28 select values (SELECTS below: four passes through both
    ports' four rows in order, then the twelve values that select the
    sockets behind a Team Tap), writes it to $F14000 with the controllers
    and the sound on, and copies $F14000 and $F14002 to main RAM from
    $10000 on: 56 words, a pair for each select;
  - copies the light pen's latched place, LPH and LPV ($F00008, $F0000A),
    to $10070;
  - selects each of the paddle converter's four channels ($F17C00, written
    channel | 4) and copies the conversion to $10074, a word each;
  - adds one to a long word at $1007C, the count of its turns.
A pad's button held clears its own bit in the controller words (0 while
held), in each of the four passes. Made with "nopad" it reads no controller register, so every frame is
a lag frame.
"""
import struct
import sys

BASE = 0x10000
# Each port's four rows in order, 0 to 3, as games read them: the analog,
# driving and 6D controllers switch banks when row 3 is followed by row 0.
# A port's nibble for row r: port 1 (low nibble) $E, $D, $B, $7; port 2
# (high nibble) $7, $B, $D, $E. Then the twelve other values, which select
# the sockets behind a Team Tap (and nothing without one).
ROW_P1 = [0xE, 0xD, 0xB, 0x7]
ROW_P2 = [0x7, 0xB, 0xD, 0xE]
# Four passes through the rows, so that each bank of a bank-switching
# controller (the 6D has three) is read in one of them.
SELECTS = [0x8100 | (ROW_P2[r] << 4) | ROW_P1[r] for r in range(4)] * 4 + \
          [0x8100 | (n << 4) | n for n in range(16) if n not in (0x7, 0xB, 0xD, 0xE)]


def w(v):
    return struct.pack(">H", v & 0xFFFF)


def l(v):
    return struct.pack(">I", v & 0xFFFFFFFF)


def program(nopad):
    code = bytearray()
    code += w(0x46FC) + w(0x2700)           # move.w #$2700,sr
    code += w(0x4FF8) + w(0x1000)           # lea $1000.w,sp
    code += w(0x7E00)                       # moveq #0,d7
    loop = len(code)
    code += w(0x41F9) + l(BASE)             # lea BASE,a0
    if nopad:
        code += w(0x41E8) + w(0x7C)         # lea $7c(a0),a0   (the same places, nothing read)
    else:
        for sel in SELECTS:
            code += w(0x33FC) + w(sel) + l(0xF14000)   # move.w #sel,$f14000
            code += w(0x30F9) + l(0xF14000)            # move.w $f14000,(a0)+
            code += w(0x30F9) + l(0xF14002)            # move.w $f14002,(a0)+
        code += w(0x30F9) + l(0xF00008)                # move.w LPH,(a0)+
        code += w(0x30F9) + l(0xF0000A)                # move.w LPV,(a0)+
        for ch in range(4):
            code += w(0x33FC) + w(ch | 4) + l(0xF17C00)   # move.w #ch|4,$f17c00
            code += w(0x30F9) + l(0xF17C00)               # move.w $f17c00,(a0)+
    code += w(0x5287)                       # addq.l #1,d7
    code += w(0x20C7)                       # move.l d7,(a0)+
    code += w(0x6000) + w(loop - (len(code) + 2))   # bra.w loop
    return bytes(code)


SECTOR = 2352


def swap16(b):
    out = bytearray(len(b))
    out[0::2] = b[1::2]
    out[1::2] = b[0::2]
    return bytes(out)


def write_cd(folder, nopad):
    import os
    os.makedirs(folder, exist_ok=True)
    code = program(nopad)
    code += bytes(len(code) % 2)
    track = bytearray(4 * SECTOR)
    track[0x42:0x42 + 32] = b"ATARI APPROVED DATA HEADER ATRI "
    track[0x62:0x66] = l(0x4000)               # load address
    track[0x66:0x6A] = l(len(code))            # length
    track[0x6A:0x6A + len(code)] = code
    # on the disc, the bytes are in the order the Jaguar's I2S bus has them
    open(os.path.join(folder, "track02.bin"), "wb").write(swap16(bytes(track)))
    open(os.path.join(folder, "track01.bin"), "wb").write(bytes(4 * SECTOR))
    cue = ["REM SESSION 01", 'FILE "track01.bin" BINARY', "  TRACK 01 AUDIO", "    INDEX 01 00:00:00",
           "REM SESSION 02", 'FILE "track02.bin" BINARY', "  TRACK 02 AUDIO", "    INDEX 01 00:00:00"]
    open(os.path.join(folder, "disc.cue"), "w", newline="\n").write("\n".join(cue) + "\n")
    print("%s: a disc with %d bytes of code%s" % (folder, len(code), " (no controller read)" if nopad else ""))


def main():
    if sys.argv[1] == "--cd":
        write_cd(sys.argv[2], len(sys.argv) > 3 and sys.argv[3] == "nopad")
        return
    out = sys.argv[1]
    nopad = len(sys.argv) > 2 and sys.argv[2] == "nopad"
    cart = bytearray(b"\xff" * 0x100000)
    # the header the boot ROM and the high-level BIOS read: the ROM's width
    # and speed, and the run address
    cart[0x400:0x408] = bytes([0x04, 0x04, 0x04, 0x04]) + l(0x802000)
    code = program(nopad)
    cart[0x2000:0x2000 + len(code)] = code
    open(out, "wb").write(cart)
    print("%s: %d bytes of code%s" % (out, len(code), " (no controller read)" if nopad else ""))


if __name__ == "__main__":
    main()
