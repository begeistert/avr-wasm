# Drop-in tools folder

The `MauiAvrAssembler` example expects the following files to be placed
in **this directory** (`Resources/Raw/avrwasm/`) before building:

```
Resources/Raw/avrwasm/
├── index.html               (already provided)
├── pipeline.js              (already provided)
├── avr-as.js                ◄ from the avr-wasm GitHub Release
├── avr-ld.js                ◄ from the avr-wasm GitHub Release
├── objcopy.js               ◄ from the avr-wasm GitHub Release
└── avr-libc/                ◄ from the avr-wasm GitHub Release
    ├── avr5/{libc.a,libm.a,crtatmega328p.o}
    ├── avr6/{libc.a,libm.a,crtatmega2560.o}
    └── avr25/{libc.a,libm.a,crtattiny85.o}
```

These artifacts are produced by the `Build` GitHub Actions workflow at
the root of this repository.  The easiest way to obtain them is to
download the matching release archive:

```bash
# From the example folder:
gh release download --pattern '*.js'   --dir Resources/Raw/avrwasm
gh release download --pattern 'avr-libc-*' --dir Resources/Raw/avrwasm
```

…or copy them from a local `dist/` after running the workflow yourself.

The `.gitignore` in this folder excludes the binary artifacts so they
are never accidentally committed.
