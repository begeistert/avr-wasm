#!/bin/bash
set -xe -o pipefail

output_dir=$1
if [ -z "$output_dir" ]; then
    echo "Usage: $0 <output_dir>"
    exit 1
fi

if [ ! -f "./configure" ]; then
    echo "Please run this script from the root of the binutils source tree"
    exit 1
fi
source_dir=$(pwd)
script_dir=$(dirname "$(realpath "$0")")

if [ ! -d "$output_dir" ]; then
    mkdir -p "$output_dir"
fi
output_dir=$(realpath "$output_dir")

# Load device definitions (sets the DEVICES array)
# shellcheck source=devices.sh
source "$script_dir/devices.sh"

# Derive the set of unique avr-libc architecture families and per-device CRT
# objects we need to embed from the DEVICES list.
declare -A arch_families   # key=family  → value=1
declare -A device_crts     # key=family:crt → value=1

for device in "${DEVICES[@]}"; do
    IFS=':' read -r _label _mcu arch crt <<< "$device"
    arch_families["$arch"]=1
    device_crts["$arch:$crt"]=1
done

# Build the --embed-file flags for all needed avr-libc files.
# We embed only what is strictly required for linking:
#   libc.a, libm.a, crtn.o  — present in every arch-family directory
#   crt<mcu>.o              — device-specific startup object
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
    # crtn.o is already covered in the loop above
    if [ "$crt" != "crtn.o" ] && [ -f "$lib_dir/$crt" ]; then
        embed_flags+=" --embed-file ${lib_dir}/${crt}@${lib_dir}/${crt}"
    fi
done

# Patch bfd/development.sh to suppress "development build" warnings
sed -i '/^development=/s/true/false/' bfd/development.sh

function build_avr_ld() {
    local build_type=$1

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

    local ldflags="-sMODULARIZE=1 -sFORCE_FILESYSTEM=1 -sEXPORTED_RUNTIME_METHODS=FS -sSINGLE_FILE=1 -sALLOW_MEMORY_GROWTH=1"
    if [ "$build_type" = "esm" ]; then
        ldflags="$ldflags -sEXPORT_ES6=1"
    fi
    ldflags="$ldflags $embed_flags"

    emmake make -O -j"$(nproc)" \
        "CFLAGS=-DHAVE_PSIGNAL=1 -DELIDE_CODE -Os" \
        "LDFLAGS=$ldflags"

    local install_path="$output_dir/$build_type"
    install -D "ld/ld-new" "$install_path/avr-ld.js"
}

for type in "esm" "cjs"; do
    work_dir=$(mktemp -d -t "avr-ld.$type.XXXXXX")
    (cd "$work_dir" && build_avr_ld "$type")
done
