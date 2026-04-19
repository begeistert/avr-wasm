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

# Prevent AM_PROG_AR from setting AR="emar --plugin liblto_plugin.so".
#
# llvm-ar (emar) advertises "--plugin=<string>  ignored for compatibility",
# so the automake AM_PROG_AR probe succeeds and sets
#   AR="emar --plugin liblto_plugin.so"
# But liblto_plugin.so does not exist in emscripten.  Every subsequent
# AC_LINK_IFELSE step that needs to create a test archive then fails, which
# causes GCC_NO_EXECUTABLES to fire and makes AC_SEARCH_LIBS abort fatally
# inside libiberty's sub-configure (triggered by make, not by emconfigure).
#
# We need am_cv_ar_has_plugin=no to be visible to EVERY configure script,
# including the libiberty sub-configure that make spawns as a fresh process.
# Exporting the variable alone is insufficient for some autoconf versions
# that do not import *_cv_* env vars into the cache automatically.  Writing
# to CONFIG_SITE guarantees the value is sourced at the very top of every
# ./configure script before any AC_CACHE_VAL check runs.
_emsc_site=$(mktemp /tmp/emscripten-site.XXXXXX)
printf 'am_cv_ar_has_plugin=no\n' > "$_emsc_site"
export CONFIG_SITE="$_emsc_site"
export am_cv_ar_has_plugin=no

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

emmake make -O -j"$(nproc)" \
    "CFLAGS=-DHAVE_PSIGNAL=1 -DELIDE_CODE -Os" \
    "LDFLAGS=-sMODULARIZE=1 -sFORCE_FILESYSTEM=1 -sEXPORTED_RUNTIME_METHODS=FS -sSINGLE_FILE=1 -sALLOW_MEMORY_GROWTH=1 $embed_flags"

install -D "ld/ld-new" "$output_dir/avr-ld.js"
