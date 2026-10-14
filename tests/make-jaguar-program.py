#!/usr/bin/env python3
"""Writes a Jaguar cartridge (.j64, 1 MB) whose program is a small test of
the controllers for the Virtual Jaguar core's tests. It needs no file of
anyone's.

usage: make-jaguar-program.py <out.j64> [nopad]

The program, hand-assembled below (68000 machine code), starts at $802000,
where the high-level BIOS jumps. For ever, it:
  - for each of the four row selects ($E, $D, $B, $7 in both ports' nibbles
    of $F14000, with the controllers and the sound switched on), writes the
    select and copies $F14000 and $F14002 to main RAM, from $10000 on:
    eight words, a pair for each select;
  - adds one to a long word at $10010, the count of its turns.
A button held clears its own bit in one of those words (0 while held).
Made with "nopad" it reads no controller register, so every frame is a lag
frame.
"""
import struct
import sys

BASE = 0x10000
SELECTS = [0x81EE, 0x81DD, 0x81BB, 0x8177]


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
    for sel in SELECTS:
        if nopad:
            code += w(0x5488)               # addq.l #2,a0   (the same places, nothing read)
            code += w(0x5488)
            continue
        code += w(0x33FC) + w(sel) + l(0xF14000)   # move.w #sel,$f14000
        code += w(0x30F9) + l(0xF14000)            # move.w $f14000,(a0)+
        code += w(0x30F9) + l(0xF14002)            # move.w $f14002,(a0)+
    code += w(0x5287)                       # addq.l #1,d7
    code += w(0x20C7)                       # move.l d7,(a0)+
    code += w(0x6000) + w(loop - (len(code) + 2))   # bra.w loop
    return bytes(code)


def main():
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
