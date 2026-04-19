# avr-wasm

AVR GNU Assembler (`avr-as`), Linker (`avr-ld` + avr-libc), and Binutils (`objcopy`, `objdump`, …) compiled to WebAssembly using [Emscripten](https://emscripten.org/).

Each tool is a self-contained `.js` file with the WASM binary embedded — no separate `.wasm` file, no server, no native AVR toolchain required.

## Outputs

| File | Description |
|------|-------------|
| `avr-as.js` | GNU Assembler for AVR — assembles `.s` → `.o` |
| `avr-ld.js` | GNU Linker for AVR with avr-libc embedded — links `.o` → `.elf` |
| `objcopy.js` | Converts `.elf` → Intel HEX (`.hex`) |
| `objdump.js` | Disassembles / inspects ELF binaries |
| `nm.js`, `readelf.js`, `size.js`, … | Additional binutils tools |

## Getting the files

**Latest release:** download individual `.js` files from the [Releases page](../../releases/latest).

**Build manually:** trigger the [Build workflow](../../actions/workflows/build.yml) via *Run workflow* — the compiled files are saved as a workflow artifact.

## Usage

Each file exposes an Emscripten module factory (`Module()`). Load the `.js` file in any JavaScript environment (browser, WKWebView, Node.js) and call `Module()` to get an instance with a virtual filesystem.

See [`docs/AVR_TOOLCHAIN.md`](docs/AVR_TOOLCHAIN.md) for a full end-to-end guide covering the `.s → .o → .elf → .hex` pipeline.

## Supported devices (avr-ld)

| Label | MCU | avr-libc arch family |
|-------|-----|----------------------|
| `arduino-uno` | ATmega328P | avr5 |
| `arduino-nano` | ATmega328P | avr5 |
| `arduino-mega` | ATmega2560 | avr6 |
| `attiny85` | ATtiny85 | avr25 |

To add more devices edit [`src/avr-ld/devices.sh`](src/avr-ld/devices.sh) (one line per device) and rebuild.

## Repository layout

```
src/
  gas/          Dockerfile + build.sh → avr-as.js
  binutils/     Dockerfile + build.sh → objcopy.js, objdump.js, …
  avr-ld/       Dockerfile + build.sh + devices.sh → avr-ld.js
docs/
  AVR_TOOLCHAIN.md   End-to-end pipeline tutorial
```

## Building locally

Docker is the only dependency.

```bash
# avr-as
docker buildx build --output=type=local,dest=dist src/gas

# binutils (objcopy, objdump, …)
docker buildx build --output=type=local,dest=dist src/binutils

# avr-ld + avr-libc
docker buildx build --output=type=local,dest=dist src/avr-ld
```

Compiled `.js` files appear in `dist/`.

## License

GPL-3.0-or-later — in accordance with the license of GNU Binutils.

