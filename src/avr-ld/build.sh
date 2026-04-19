#!/bin/bash
set -xe -o pipefail

output_dir=${1:-/dist}

if [ ! -f "./configure" ]; then
    echo "Please run this script from the root of the binutils source tree"
    exit 1
fi
source_dir=$(pwd)
script_dir=$(dirname "$(realpath "$0")")

mkdir -p "$output_dir"
output_dir=$(realpath "$output_dir")

# Load device definitions (sets the DEVICES array)
# shellcheck source=devices.sh
source "$script_dir/devices.sh"

# Derive unique avr-libc architecture families and per-device CRT objects needed
declare -A arch_families
declare -A device_crts

for device in "${DEVICES[@]}"; do
    IFS=':' read -r _label _mcu arch crt <<< "$device"
    arch_families["$arch"]=1
    device_crts["$arch:$crt"]=1
done

# Build --embed-file flags for the required avr-libc files only.
# We embed: libc.a, libm.a, crtn.o (common to every arch family directory)
#           crt<mcu>.o (device-specific startup object)
embed_flags=""
for arch in "${!arch_families[@]}"; do
    lib_dir="/usr/lib/avr/lib/$arch"
    for f in libc.a libm.a crtn.o; do
        if [ -f "$lib_dir/$f" ]; then
            embed_flags+=" --embed-file ${lib_dir}/${f}@${lib_dir}/${f}"
        fi
    done
done

for key in "${!device_crts[@]}"; do
    arch="${key%%:*}"
    crt="${key##*:}"
    lib_dir="/usr/lib/avr/lib/$arch"
    # crtn.o is already covered above
    if [ "$crt" != "crtn.o" ] && [ -f "$lib_dir/$crt" ]; then
        embed_flags+=" --embed-file ${lib_dir}/${crt}@${lib_dir}/${crt}"
    fi
done

sed -i '/^development=/s/true/false/' bfd/development.sh

# Note on the libiberty / libsframe / zlib sub-configure failure
# ----------------------------------------------------------------
# Earlier versions of this script passed all the emscripten-specific
# link flags (-sMODULARIZE=1, -sSINGLE_FILE=1, --embed-file ...) as
# `LDFLAGS=` on the `emmake make` command line.  Make propagates that
# LDFLAGS into every sub-configure (libsframe, zlib, libiberty), where
# the very first thing AC_PROG_CC does is build a `conftest` to verify
# the C compiler can produce executables.  With the full emscripten
# LDFLAGS in place, that conftest link fails (the embed-file machinery
# and SINGLE_FILE wrapping are not appropriate for a tiny conftest),
# which sets `gcc_no_link=yes` inside the configure shell.  After that,
# `GCC_NO_EXECUTABLES` (called at the top of libiberty/configure.ac)
# turns every subsequent `AC_LINK_IFELSE` into a fatal
#     configure: error: Link tests are not allowed after GCC_NO_EXECUTABLES.
# The cascade we observed in CI:
#   configure-libsframe   -> "C compiler cannot create executables"
#   configure-zlib        -> "Link tests are not allowed ..."
#   configure-libiberty   -> "Link tests are not allowed ..." (fatal)
#
# We only need the emscripten link flags for the FINAL `ld-new`
# executable, so build everything first with a plain LDFLAGS, then
# relink just `ld/ld-new` with the full set of emscripten flags.
#
# The only remaining configure-time hint we keep is am_cv_ar_has_plugin
# to silence the (harmless) automake AM_PROG_AR --plugin probe noise.
_emsc_site=$(mktemp /tmp/emscripten-site.XXXXXX)
printf 'am_cv_ar_has_plugin=no\n' > "$_emsc_site"
export CONFIG_SITE="$_emsc_site"

work_dir=$(mktemp -d -t "avr-ld.XXXXXX")
cd "$work_dir"

emconfigure "$source_dir/configure" \
    --target=avr \
    --host=wasm32 \
    --enable-ld=default \
    --enable-default-execstack=no \
    --disable-doc \
    --disable-gprof \
    --disable-nls \
    --disable-gas \
    --disable-gold \
    --disable-binutils \
    --disable-gdb \
    --disable-gdbserver \
    --disable-libdecnumber \
    --disable-readline \
    --disable-sim \
    --disable-werror

# Phase 1: build all libraries and ld with default LDFLAGS so that
# sub-configures (libsframe, zlib, libiberty, bfd) succeed.
emmake make -O -j"$(nproc)" \
    "CFLAGS=-DHAVE_PSIGNAL=1 -DELIDE_CODE -Os"

# Phase 2: relink ld/ld-new with the full emscripten link flags so the
# resulting JavaScript module is self-contained, exposes FS, and embeds
# the avr-libc archives / startup objects required at runtime.
rm -f ld/ld-new
emmake make -O -j"$(nproc)" -C ld \
    "CFLAGS=-DHAVE_PSIGNAL=1 -DELIDE_CODE -Os" \
    "LDFLAGS=-sMODULARIZE=1 -sFORCE_FILESYSTEM=1 -sEXPORTED_RUNTIME_METHODS=FS -sSINGLE_FILE=1 -sALLOW_MEMORY_GROWTH=1 $embed_flags" \
    ld-new

install -D "ld/ld-new" "$output_dir/avr-ld.js"
