import type { Emscripten } from "./emscripten";

export { DEVICE_INFO, type DeviceInfo, type SupportedDevice } from "./devices";

export default async function loader(): Promise<Emscripten.ModuleFactory> {
  return (await import("../build/dist/cjs/avr-ld.js"))
    .default as Emscripten.ModuleFactory;
}
