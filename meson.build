# chimera-core-virtualjaguar: Virtual Jaguar, the libretro Atari Jaguar
# emulator, in miniBox's sandbox, as a Chimera core.
#
# Native reference build (run-native + run-wbx under the build directory):
#     meson setup build/meson-native -Dminibox_dir=<miniBox> && ninja -C build/meson-native
# Guest (core.wbx) build via the cross file waterbox/setup-guest.sh writes:
#     sh waterbox/setup-guest.sh -m <miniBox> && ninja -C build/meson-guest core.wbx
#
# The file list is upstream's Makefile.common, with its SSE2 blitter (the
# one upstream's Makefile picks on x86-64) and libchdr's unity build for
# CHD discs. The emulator is driven through upstream's libretro functions
# by waterbox/cinterface.c. Both flavours compile the SAME sources; only
# emulibc.h differs (waterbox/native-shim for the reference).
project('chimera-core-virtualjaguar', 'c',
  default_options: ['c_std=gnu11', 'optimization=2', 'debug=false', 'warning_level=0'])

vj = 'extern/virtualjaguar'

# the submodule pin is upstream as it is; the patches are laid over it
# (waterbox/apply-patches.sh does nothing to a tree that has them)
run_command(files('waterbox/apply-patches.sh'), check: true)

mb = get_option('minibox_dir')
if mb == ''
  mb_candidate = meson.current_source_dir() / '../chimera/extern/chimera-common-minibox'
  if import('fs').is_dir(mb_candidate)
    mb = mb_candidate
  else
    error('pass -Dminibox_dir=<miniBox checkout> (or keep one at ../chimera/extern/chimera-common-minibox)')
  endif
endif

# upstream's own defines (Makefile, Makefile.common), and what the patches
# test for
defs = [
  '-D__LIBRETRO__', '-DINLINE=inline', '-DNDEBUG', '-DBLITTER_SIMD_SSE2',
  '-DCHIMERA_CORE',
]
# upstream's -fno-strict-overflow and -fno-strict-aliasing; one answer from
# a floating-point expression on every machine (no fused multiply-adds);
# locals the code reads before writing them read as zero in every build
flags = [
  '-fwrapv',
  '-fno-strict-aliasing',
  '-ffp-contract=off',
  '-ftrivial-auto-var-init=zero',
  '-msse2',
]
add_project_arguments(defs + flags, language: 'c')

inc = include_directories(
  'waterbox', 'waterbox/config',
  vj, vj / 'src', vj / 'src/core', vj / 'src/tom', vj / 'src/jerry', vj / 'src/cd',
  vj / 'src/bios', vj / 'src/m68000', vj / 'src/debug',
  vj / 'libretro-common/include',
  vj / 'deps/libchdr/include', vj / 'deps/libchdr/deps/lzma-25.01/include',
  vj / 'deps/libchdr/deps/miniz-3.1.1', vj / 'deps/libchdr/deps/zstd-1.5.7',
)

vj_names = [
  'libretro.c',
  'src/tom/blit_memo.c',
  'src/tom/blitter.c',
  'src/tom/blitter_compare.c',
  'src/tom/blitter_mmio.c',
  'src/jerry/dac.c',
  'src/jerry/dsp.c',
  'src/core/file.c',
  'src/tom/gpu.c',
  'src/core/jaguar.c',
  'src/jerry/jerry.c',
  'src/jerry/jlink.c',
  'src/jerry/jlink_tcp.c',
  'src/jerry/jlink_discover.c',
  'src/jerry/jlink_netpacket.c',
  'src/jerry/voicemodem.c',
  'src/jerry/voicechat.c',
  'src/jerry/uart.c',
  'src/tom/op.c',
  'src/tom/shadowfb.c',
  'src/tom/texdump.c',
  'src/tom/texreplace.c',
  'src/tom/tom.c',
  'src/cd/cdintf.c',
  'src/cd/cdrom.c',
  'src/cd/jagcd_bios.c',
  'src/cd/jagcd_cart.c',
  'src/cd/jagcd_hle.c',
  'src/core/biosdb.c',
  'src/core/bus_arbiter.c',
  'src/core/cheat.c',
  'src/core/crc32.c',
  'src/core/perf_counters.c',
  'src/core/perf_iface.c',
  'src/core/crash_detect.c',
  'src/core/event.c',
  'src/jerry/eeprom.c',
  'src/core/filedb.c',
  'src/core/titledb.c',
  'src/core/titlehook.c',
  'src/core/hookfile.c',
  'src/m68000/cpustbl.c',
  'src/m68000/cpudefs.c',
  'src/m68000/cpuemu.c',
  'src/m68000/cpuextra.c',
  'src/m68000/m68kinterface.c',
  'src/m68000/readcpu.c',
  'src/bios/jagbios.c',
  'src/bios/jagbios_m.c',
  'src/bios/jagcdbios.c',
  'src/bios/jagdevcdbios.c',
  'src/jerry/joystick.c',
  'src/jerry/quadrature.c',
  'src/jerry/axistune.c',
  'src/jerry/inputdev.c',
  'src/jerry/paddle.c',
  'src/core/settings.c',
  'src/core/memtrack.c',
  'src/core/jaggd.c',
  'src/core/jaggd_fs.c',
  'src/core/nvmbios.c',
  'src/core/vjag_memory.c',
  'src/core/vjtrace.c',
  'src/core/vj_frontend_ext.c',
  'src/core/universalhdr.c',
  'src/jerry/wavetable.c',
  'src/debug/gdbstub.c',
  'src/debug/gdbtarget.c',
  'src/debug/vjdebug.c',
  'src/debug/gdbsock.c',
  'src/tom/blitter_simd_sse2.c',
]
lrc_names = [
  'compat/compat_strcasestr.c',
  'encodings/encoding_utf.c',
  'compat/compat_snprintf.c',
  'compat/compat_strl.c',
  'compat/compat_posix_string.c',
  'compat/fopen_utf8.c',
  'streams/file_stream.c',
  'streams/file_stream_transforms.c',
  'string/stdstring.c',
  'vfs/vfs_implementation.c',
  'file/file_path.c',
  'file/file_path_io.c',
  'time/rtime.c',
]
core_sources = files('waterbox/cinterface.c')
foreach n : vj_names
  core_sources += files(vj / n)
endforeach
foreach n : lrc_names
  core_sources += files(vj / 'libretro-common' / n)
endforeach

# libchdr's unity build, with its own flags (upstream's unity.o rule)
chdr_args = ['-D_7ZIP_ST', '-DMINIZ_DEFLATE_APIS', '-DWANT_RAW_DATA_SECTOR=1', '-DWANT_SUBCODE=1',
  '-DVERIFY_BLOCK_CRC=1', '-std=c99']

if meson.is_cross_build()
  # ---- the guest: core.wbx --------------------------------------------------
  mbdir = meson.get_external_property('minibox_dir')
  mbuild = meson.get_external_property('minibox_build')
  sr = meson.get_external_property('guest_sysroot')

  chdr = static_library('chdr', files(vj / 'deps/libchdr/unity.c'), include_directories: inc, c_args: chdr_args)
  executable('core', core_sources + files('waterbox/guest-syscalls.c'),
    name_suffix: 'wbx',
    include_directories: inc,
    link_with: chdr,
    link_args: [
      '-static', '-no-pie',
      '-Wl,--eh-frame-hdr', '-Wl,-O2', '-Wl,--no-relax', '-Wl,-z,stack-size=8388608',
      '-T', mbdir / 'source/guest/linkscript.T',
      mbuild / 'source/guest/emulibc.c.o',
      '-L' + sr / 'lib', '-lgcc', '-lc'])
else
  # ---- the native reference -------------------------------------------------
  m = meson.get_compiler('c').find_library('m', required: false)
  chdr = static_library('chdr', files(vj / 'deps/libchdr/unity.c'), include_directories: inc, c_args: chdr_args)
  executable('run-native', core_sources + files('waterbox/run-native.c'),
    include_directories: [include_directories('waterbox/native-shim'), inc],
    c_args: ['-I' + mb / 'source/guest/include', '-I' + mb / 'extern/jsmn'],
    link_with: chdr,
    dependencies: [m])

  mbhost = mb / 'build/meson-linux/source/host'
  executable('run-wbx', files('waterbox/run-wbx.c'),
    c_args: ['-I' + mb / 'source/host'],
    link_args: [mbhost / 'libminiboxhost.so'],
    build_rpath: mbhost)
endif
