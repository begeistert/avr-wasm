/**
 * Supported AVR devices — each maps to a specific MCU + avr-libc arch family.
 *
 * These values are derived from `build/devices.sh`.  To add a new device,
 * update that file (single source of truth) and extend this type + DEVICE_INFO.
 */
export type SupportedDevice =
  | "arduino-uno"
  | "arduino-nano"
  | "arduino-mega"
  | "attiny85";

export interface DeviceInfo {
  /** MCU name passed to avr-as via -mmcu (e.g. "atmega328p") */
  mcu: string;
  /** avr-libc architecture family directory (e.g. "avr5") */
  archFamily: string;
  /** Device-specific CRT startup object embedded in this bundle */
  crtObject: string;
  /** LD emulation name passed to avr-ld via -m (e.g. "avr5") */
  ldEmulation: string;
}

/**
 * Per-device metadata used when invoking avr-ld.
 *
 * Example usage:
 * ```ts
 * import avrLd from "@binutils-wasm/avr-ld";
 * import { DEVICE_INFO } from "@binutils-wasm/avr-ld";
 *
 * const device = DEVICE_INFO["arduino-uno"];
 * const ld = await avrLd();
 * await ld({
 *   arguments: [
 *     "-m", device.ldEmulation,
 *     `/usr/lib/avr/lib/${device.archFamily}/${device.crtObject}`,
 *     "program.o",
 *     `-L/usr/lib/avr/lib/${device.archFamily}`,
 *     "-lc",
 *     "-o", "program.elf",
 *   ],
 *   // ...
 * });
 * ```
 */
export const DEVICE_INFO: Record<SupportedDevice, DeviceInfo> = {
  "arduino-uno": {
    mcu: "atmega328p",
    archFamily: "avr5",
    crtObject: "crtm328p.o",
    ldEmulation: "avr5",
  },
  "arduino-nano": {
    mcu: "atmega328p",
    archFamily: "avr5",
    crtObject: "crtm328p.o",
    ldEmulation: "avr5",
  },
  "arduino-mega": {
    mcu: "atmega2560",
    archFamily: "avr6",
    crtObject: "crtm2560.o",
    ldEmulation: "avr6",
  },
  attiny85: {
    mcu: "attiny85",
    archFamily: "avr25",
    crtObject: "crtt85.o",
    ldEmulation: "avr25",
  },
};
