# AVR Toolchain Tutorial: From PyMCU Output to Intel HEX

This tutorial walks through the complete compilation pipeline for AVR microcontrollers using the WebAssembly tools in this repository.

```
PyMCU (.s)  ──►  avr-as (.o)  ──►  avr-ld (.elf)  ──►  avr-objcopy (.hex)
```

All three tools run entirely in WebAssembly — no native AVR toolchain is needed.

---

## Packages

| Step | Tool | npm package |
|------|------|-------------|
| Assemble | `avr-as` | `@binutils-wasm/gas` (target `"avr"`) |
| Link | `avr-ld` | `@binutils-wasm/avr-ld` |
| Convert | `avr-objcopy` | `@binutils-wasm/binutils` (executable `"objcopy"`) |

---

## Device Reference

| Board | MCU | `-mmcu` flag | avr-libc arch family | CRT object | LD emulation |
|-------|-----|---|---|---|---|
| Arduino UNO | ATmega328P | `atmega328p` | `avr5` | `crtm328p.o` | `avr5` |
| Arduino NANO | ATmega328P | `atmega328p` | `avr5` | `crtm328p.o` | `avr5` |
| Arduino MEGA | ATmega2560 | `atmega2560` | `avr6` | `crtm2560.o` | `avr6` |
| ATtiny85 | ATtiny85 | `attiny85` | `avr25` | `crtt85.o` | `avr25` |

The `@binutils-wasm/avr-ld` package exports a `DEVICE_INFO` map that contains all of these values — you do not need to hardcode them.

---

## Step 1 — Assemble: `.s` → `.o`

PyMCU produces standard GNU assembler syntax, which `avr-as` accepts directly.

```typescript
import gasLoader from "@binutils-wasm/gas";
import { DEVICE_INFO } from "@binutils-wasm/avr-ld";

const device = DEVICE_INFO["arduino-uno"];

// Load the AVR assembler
const gas = await gasLoader("avr");

// Input: assembly source produced by PyMCU
const asmSource = `
    .arch avr5
    .text
    .global main
main:
    ldi r16, 0xFF
    out 0x04, r16     ; DDRB = 0xFF (all outputs)
loop:
    sbi 0x05, 5       ; set PB5 (LED on Arduino UNO pin 13)
    rjmp loop
`;

let objectBytes: Uint8Array | undefined;

await gas({
  print:    (s) => console.log("[as]", s),
  printErr: (s) => console.error("[as]", s),
  arguments: [
    `-mmcu=${device.mcu}`,   // -mmcu=atmega328p
    "-o", "program.o",
    "program.s",
  ],
  preRun: [(m) => {
    m.FS.writeFile("program.s", asmSource);
  }],
  postRun: [(m) => {
    objectBytes = m.FS.readFile("program.o");
  }],
});
```

> **Note:** PyMCU targets that use AVR architecture directives (`.arch avr5`, etc.) work
> without any extra flags.  If your source does not declare an architecture, pass
> `-march=avr5` (or the appropriate arch string for your MCU) on the command line.

---

## Step 2 — Link: `.o` → `.elf`

```typescript
import avrLd from "@binutils-wasm/avr-ld";
import { DEVICE_INFO } from "@binutils-wasm/avr-ld";

const device = DEVICE_INFO["arduino-uno"];

// avr-libc paths are embedded inside the WASM bundle
const libDir = `/usr/lib/avr/lib/${device.archFamily}`;
const crtPath = `${libDir}/${device.crtObject}`;

const ld = await avrLd();

let elfBytes: Uint8Array | undefined;

await ld({
  print:    (s) => console.log("[ld]", s),
  printErr: (s) => console.error("[ld]", s),
  arguments: [
    "-m", device.ldEmulation,   // -m avr5
    crtPath,                     // CRT startup object (from embedded avr-libc)
    "program.o",                 // your object file
    `-L${libDir}`,               // avr-libc library search path
    "-lc",                       // link libc
    "-o", "program.elf",
  ],
  preRun: [(m) => {
    m.FS.writeFile("program.o", objectBytes!);
  }],
  postRun: [(m) => {
    elfBytes = m.FS.readFile("program.elf");
  }],
});
```

### Linking with libm

If your program uses floating-point math, add `-lm` before `-lc`:

```
"-lm", "-lc",
```

### Providing a custom linker script

Pass `-T /path/to/script.ld` before the output flag if you need precise memory
layout control.  The standard emulations (`avr5`, `avr6`, `avr25`) use safe
defaults that match the hardware memory map for each device family.

---

## Step 3 — Convert: `.elf` → `.hex`

Arduino bootloaders and `avrdude` expect Intel HEX format.  Use `objcopy` from
the `@binutils-wasm/binutils` package:

```typescript
import binutilsLoader from "@binutils-wasm/binutils";

const objcopy = await binutilsLoader("objcopy");

let hexString: string | undefined;

await objcopy({
  print:    (s) => console.log("[objcopy]", s),
  printErr: (s) => console.error("[objcopy]", s),
  arguments: [
    "-O", "ihex",       // output format: Intel HEX
    "-R", ".eeprom",    // strip EEPROM section (flash only)
    "program.elf",
    "program.hex",
  ],
  preRun: [(m) => {
    m.FS.writeFile("program.elf", elfBytes!);
  }],
  postRun: [(m) => {
    hexString = m.FS.readFile("program.hex", { encoding: "utf8" });
  }],
});

console.log(hexString);
// :100000000CCFF ... (Intel HEX records)
```

### Writing EEPROM data separately

If your program stores data in EEPROM, extract it to a separate `.eep` file:

```typescript
arguments: [
  "-O", "ihex",
  "-j", ".eeprom",
  "--set-section-flags=.eeprom=alloc,load",
  "--no-change-warnings",
  "--change-section-lma", ".eeprom=0",
  "program.elf",
  "program.eep",
],
```

---

## Complete Pipeline Example

```typescript
import gasLoader from "@binutils-wasm/gas";
import avrLd, { DEVICE_INFO } from "@binutils-wasm/avr-ld";
import binutilsLoader from "@binutils-wasm/binutils";

async function compile(
  asmSource: string,
  deviceName: keyof typeof DEVICE_INFO
): Promise<string> {
  const device = DEVICE_INFO[deviceName];
  const libDir = `/usr/lib/avr/lib/${device.archFamily}`;

  // 1. Assemble
  const gas = await gasLoader("avr");
  let objectBytes: Uint8Array | undefined;
  await gas({
    arguments: [`-mmcu=${device.mcu}`, "-o", "out.o", "in.s"],
    preRun:  [(m) => m.FS.writeFile("in.s", asmSource)],
    postRun: [(m) => { objectBytes = m.FS.readFile("out.o"); }],
  });

  // 2. Link
  const ld = await avrLd();
  let elfBytes: Uint8Array | undefined;
  await ld({
    arguments: [
      "-m", device.ldEmulation,
      `${libDir}/${device.crtObject}`,
      "out.o",
      `-L${libDir}`, "-lc",
      "-o", "out.elf",
    ],
    preRun:  [(m) => m.FS.writeFile("out.o", objectBytes!)],
    postRun: [(m) => { elfBytes = m.FS.readFile("out.elf"); }],
  });

  // 3. Convert to Intel HEX
  const objcopy = await binutilsLoader("objcopy");
  let hex = "";
  await objcopy({
    arguments: ["-O", "ihex", "-R", ".eeprom", "out.elf", "out.hex"],
    preRun:  [(m) => m.FS.writeFile("out.elf", elfBytes!)],
    postRun: [(m) => { hex = m.FS.readFile("out.hex", { encoding: "utf8" }); }],
  });

  return hex;
}

// Usage:
const hex = await compile(myAsmSource, "arduino-uno");
console.log(hex);
```

---

## Adding More Devices

1. Open `packages/avr-ld/build/devices.sh`.
2. Find the device in the [avr-libc device list](https://avrdudes.github.io/avr-libc/avr-libc-user-manual/index.html).
3. Append a new entry: `"label:mcu:arch_family:crt_obj"`

   ```bash
   DEVICES=(
     "arduino-uno:atmega328p:avr5:crtm328p.o"
     # ... existing entries ...
     "atmega1284p:atmega1284p:avr51:crtm1284p.o"   # ← new entry
   )
   ```

4. Add the matching entry to `packages/avr-ld/src/devices.ts`:

   ```typescript
   export type SupportedDevice =
     | "arduino-uno"
     // ...
     | "atmega1284p";   // ← new type member

   export const DEVICE_INFO = {
     // ...
     "atmega1284p": {
       mcu: "atmega1284p",
       archFamily: "avr51",
       crtObject: "crtm1284p.o",
       ldEmulation: "avr51",
     },
   };
   ```

5. Rebuild: `pnpm --filter @binutils-wasm/avr-ld build`

---

## Offline Use (MAUI / iOS)

The `@binutils-wasm/avr-ld` package uses `-sSINGLE_FILE=1`, which means the
entire WASM binary and all avr-libc data are base64-encoded inside a single
JavaScript file (`avr-ld.js`).  The `@binutils-wasm/gas` AVR assembler and
`@binutils-wasm/binutils` objcopy are similarly self-contained.

For a C# MAUI application:

1. Download the three `.js` files once and store them in local app storage.
2. Load them via `WKWebView` (iOS) or `WebView` (Android) using a local HTTP
   server or a custom URL scheme.
3. Call the tools from JavaScript/TypeScript running inside the WebView, passing
   assembly source text in and receiving Intel HEX bytes out.

The files do not phone home, require no server, and work fully offline after the
initial download.
