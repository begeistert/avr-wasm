import gasLoader from "@binutils-wasm/gas";

import { Endianness } from "../components/EndiannessSegmentedControl";
import { ProcessorBits } from "../components/ProcessorBitsSegmentedControl";

type SupportedTargets = Parameters<typeof gasLoader>[0];

export const ASSEMBLE_PUBLIC_PREFIX = [
  ".arch avr5",
  ".text",
  ".global main",
  "",
  "main:",
] as const;

export const ASSEMBLERS_MAP: Record<
  string,
  {
    target: SupportedTargets;
    acceptBits?: ProcessorBits;
    acceptEndianness?: Endianness;
    paramsFactory: (arg: { e: Endianness; b: ProcessorBits }) => string[];
    asmPrefix?: string[];
  }
> = {
  AVR: {
    target: "avr",
    // AVR is neither endianness- nor bits-selectable; controls are hidden when
    // acceptEndianness / acceptBits are undefined.
    paramsFactory: () => [],
  },
};

export const DISASSEMBLERS_MAP: Record<
  string,
  {
    bfdArch: string;
    acceptEndianness?: Endianness;
    acceptBits?: ProcessorBits;
    bfdNameFactory: (props: { e: Endianness; b: ProcessorBits }) => string;
  }
> = {
  i386: {
    bfdArch: "i386",
    bfdNameFactory: () => "elf32-i386",
  },
  x86_64: {
    bfdArch: "i386:x86-64",
    bfdNameFactory: () => "elf64-x86-64",
  },
  ARMv7: {
    bfdArch: "arm",
    acceptEndianness: "little",
    bfdNameFactory: ({ e }) => `elf32-${e}arm`,
  },
  ARM64: {
    bfdArch: "aarch64",
    acceptEndianness: "little",
    bfdNameFactory: ({ e }) => `elf64-${e}aarch64`,
  },
  AVR: {
    bfdArch: "avr",
    bfdNameFactory: () => "elf32-avr",
  },
  MIPS: {
    bfdArch: "mips",
    acceptEndianness: "big",
    bfdNameFactory: ({ e }) => `elf32-trad${e}mips`,
  },
  MIPS64: {
    bfdArch: "mips",
    acceptEndianness: "big",
    bfdNameFactory: ({ e }) => `elf64-trad${e}mips`,
  },
  Alpha: {
    bfdArch: "alpha",
    bfdNameFactory: () => "elf64-alpha",
  },
  CRIS: {
    bfdArch: "cris",
    bfdNameFactory: () => "elf32-cris",
  },
  IA64: {
    bfdArch: "ia64",
    acceptEndianness: "big",
    bfdNameFactory: ({ e }) => `elf64-ia64-${e}`,
  },
  M68k: {
    bfdArch: "m68k",
    bfdNameFactory: () => "elf32-m68k",
  },
  MSP430: {
    bfdArch: "msp430",
    bfdNameFactory: () => "elf32-msp430",
  },
  PowerPC: {
    bfdArch: "powerpc",
    acceptEndianness: "big",
    bfdNameFactory: ({ e }) => `elf32-${e}powerpc`,
  },
  PowerPC64: {
    bfdArch: "powerpc",
    acceptEndianness: "big",
    bfdNameFactory: ({ e }) => `elf64-${e}powerpc`,
  },
  RISC_V: {
    bfdArch: "riscv",
    acceptEndianness: "little",
    acceptBits: 32,
    bfdNameFactory: ({ e, b }) => `elf${b}-${e}riscv`,
  },
  RISC_V64: {
    bfdArch: "riscv",
    acceptEndianness: "little",
    acceptBits: 64,
    bfdNameFactory: ({ e, b }) => `elf${b}-${e}riscv`,
  },
  VAX: {
    bfdArch: "vax",
    bfdNameFactory: () => "elf32-vax",
  },
  S390: {
    bfdArch: "s390",
    acceptBits: 32,
    bfdNameFactory: ({ b }) => `elf${b}-s390`,
  },
  SPARC: {
    bfdArch: "sparc",
    bfdNameFactory: () => "elf32-sparc",
  },
  SPARC64: {
    bfdArch: "sparc",
    bfdNameFactory: () => "elf64-sparc",
  },
  LoongArch32: {
    bfdArch: "LoongArch32",
    bfdNameFactory: () => "elf32-loongarch",
  },
  LoongArch64: {
    bfdArch: "LoongArch64",
    bfdNameFactory: () => "elf64-loongarch",
  },
};
