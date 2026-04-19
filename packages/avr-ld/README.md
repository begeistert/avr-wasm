# @binutils-wasm/avr-ld

AVR GNU Linker (`avr-ld`) compiled to WebAssembly, bundled with avr-libc for Arduino UNO/NANO, Arduino MEGA, and ATtiny85.

## Overview

This package provides a WebAssembly port of `avr-ld` (GNU Linker for AVR) with avr-libc pre-embedded for the most common Arduino-compatible boards and ATtiny85.  It is built using [Emscripten](https://emscripten.org/).

Together with [`@binutils-wasm/gas`](https://www.npmjs.com/package/@binutils-wasm/gas) (assembler) and [`@binutils-wasm/binutils`](https://www.npmjs.com/package/@binutils-wasm/binutils) (`objcopy`), this package provides a complete AVR compilation pipeline that runs entirely in WebAssembly — no native toolchain required.

See [`docs/AVR_TOOLCHAIN.md`](../../docs/AVR_TOOLCHAIN.md) for a full end-to-end tutorial.

## Supported Devices

| Label | MCU | avr-libc arch family |
|---|---|---|
| `arduino-uno` | ATmega328P | avr5 |
| `arduino-nano` | ATmega328P | avr5 |
| `arduino-mega` | ATmega2560 | avr6 |
| `attiny85` | ATtiny85 | avr25 |

To add more devices, edit [`build/devices.sh`](./build/devices.sh) and rebuild.

## Installation

```bash
npm install @binutils-wasm/avr-ld
```

## Usage

```typescript
import avrLd from "@binutils-wasm/avr-ld";
import { DEVICE_INFO } from "@binutils-wasm/avr-ld";

const device = DEVICE_INFO["arduino-uno"];

const ld = await avrLd();
await ld({
  print: console.log,
  printErr: console.error,
  arguments: [
    "-m", device.ldEmulation,
    `/usr/lib/avr/lib/${device.archFamily}/${device.crtObject}`,
    "program.o",
    `-L/usr/lib/avr/lib/${device.archFamily}`,
    "-lc",
    "-o", "program.elf",
  ],
  preRun: [(m) => {
    // Write the object file produced by avr-as into the virtual filesystem
    m.FS.writeFile("program.o", objectFileBytes);
  }],
  postRun: [(m) => {
    // Read the linked ELF from the virtual filesystem
    const elfBytes = m.FS.readFile("program.elf");
    console.log("ELF size:", elfBytes.byteLength);
  }],
});
```

## License

GPL-3.0-or-later — in accordance with the license of GNU Binutils.
