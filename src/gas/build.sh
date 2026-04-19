#!/bin/bash
set -xe -o pipefail

output_dir=${1:-/dist}

if [ ! -f "./configure" ]; then
    echo "Please run this script from the root of the binutils source tree"
    exit 1
fi
source_dir=$(pwd)

mkdir -p "$output_dir"
output_dir=$(realpath "$output_dir")

sed -i '/^development=/s/true/false/' bfd/development.sh

# Prevent emar's --plugin check from failing in libiberty's configure.
# emscripten's emar (llvm-ar) does not support the --plugin flag; without
# this override the automake AM_PROG_AR probe fails and configure falls back
# to link tests that are then blocked by GCC_NO_EXECUTABLES.
export am_cv_ar_has_plugin=no

work_dir=$(mktemp -d -t "gas.avr.XXXXXX")
cd "$work_dir"

emconfigure "$source_dir/configure" \
    --target=avr \
    --host=wasm32 \
    --enable-default-execstack=no \
    --enable-deterministic-archives \
    --enable-ld=default \
    --enable-new-dtags \
    --disable-doc \
    --disable-gprof \
    --disable-nls \
    --disable-binutils \
    --disable-gdb \
    --disable-gdbserver \
    --disable-libdecnumber \
    --disable-readline \
    --disable-sim \
    --disable-werror

emmake make -O -j"$(nproc)" \
    "CFLAGS=-DHAVE_PSIGNAL=1 -DELIDE_CODE -Os" \
    "LDFLAGS=-sMODULARIZE=1 -sFORCE_FILESYSTEM=1 -sEXPORTED_RUNTIME_METHODS=FS -sSINGLE_FILE=1 -sUSE_ZLIB=1"

install -D "gas/as-new" "$output_dir/avr-as.js"
