# MAUI AVR Assembler example

A minimal **.NET 9 MAUI** app that lets you type AVR assembly, pick an
Arduino-style target device, and compile it to an Intel HEX file
**entirely on-device** — using the WebAssembly builds of GNU `as`,
GNU `ld` and GNU `objcopy` from this repository.

The whole toolchain runs inside MAUI's `HybridWebView` (`WKWebView` on
iOS / Mac Catalyst, the system WebView on Android), so there is **no
native code** beyond MAUI itself.  The example is therefore
iOS-compatible by design: nothing you would need entitlements for,
nothing the App Store would reject.

```
┌──────────────────────────┐    InvokeJavaScriptAsync      ┌─────────────────────┐
│ MAUI page (C#)           │ ─────────────────────────────►│ HybridWebView       │
│  • Editor (asm source)   │                               │  • avr-as.js  (wasm)│
│  • Picker (device)       │ ◄──── { ok, hex, log } ──────│  • avr-ld.js  (wasm)│
│  • "Compile" button      │                               │  • objcopy.js (wasm)│
│  • HEX / log output      │                               │  • avr-libc/  data  │
└──────────────────────────┘                               └─────────────────────┘
```

## Project layout

```
examples/maui-avr-assembler/
├── MauiAvrAssembler.csproj           net9.0-ios;net9.0-maccatalyst;net9.0-android
├── MauiProgram.cs                    standard MAUI bootstrap
├── App.xaml(.cs)                     application + window
├── MainPage.xaml(.cs)                UI + bridge to JS
├── Models.cs                         CompileRequest / CompileResult + JsonContext
├── Platforms/
│   ├── iOS/                          AppDelegate, Info.plist
│   ├── MacCatalyst/                  AppDelegate, Info.plist, Entitlements.plist
│   └── Android/                      MainApplication, MainActivity, AndroidManifest
├── Resources/
│   ├── AppIcon/appicon.svg
│   ├── Splash/splash.svg
│   └── Raw/avrwasm/
│       ├── index.html                loads the three emscripten modules
│       ├── pipeline.js               window.compile() — chains as → ld → objcopy
│       ├── README.md                 explains where avr-as.js etc. must be dropped
│       └── .gitignore                excludes the binary artifacts
└── README.md                         (this file)
```

## Prerequisites

- **.NET 9 SDK** with the `maui`, `maui-ios`, `maui-maccatalyst` and
  `maui-android` workloads:
  ```bash
  dotnet workload install maui
  ```
- **For iOS / Mac Catalyst**: macOS host with the matching Xcode and
  command-line tools.
- **For Android**: any host plus the Android SDK installed by the
  workload.

## 1.  Drop the avr-wasm artifacts into the project

The `.js` modules and the `avr-libc/` sidecar are produced by the
`Build` GitHub Actions workflow at the root of this repository and
attached to every release.  From inside this example folder:

```bash
# Either grab them from the latest release …
gh release download --repo begeistert/avr-wasm \
    --pattern '*.js' --pattern 'avr-libc-*' \
    --dir Resources/Raw/avrwasm

# … or copy them from your own local build:
cp ../../dist/avr-as.js   Resources/Raw/avrwasm/
cp ../../dist/avr-ld.js   Resources/Raw/avrwasm/
cp ../../dist/objcopy.js  Resources/Raw/avrwasm/
cp -R ../../dist/avr-libc Resources/Raw/avrwasm/
```

`Resources/Raw/avrwasm/.gitignore` keeps these binary artifacts out of
git so the example folder stays small.

The expected final layout under `Resources/Raw/avrwasm/` is:

```
avr-as.js
avr-ld.js
objcopy.js
index.html         (provided)
pipeline.js        (provided)
avr-libc/
├── avr5/{libc.a,libm.a,crtm328p.o}
├── avr6/{libc.a,libm.a,crtm2560.o}
└── avr25/{libc.a,libm.a,crtt85.o}
```

## 2.  Build & run

```bash
cd examples/maui-avr-assembler

# iOS simulator (run from a Mac):
dotnet build -t:Run -f net9.0-ios

# Mac Catalyst:
dotnet build -t:Run -f net9.0-maccatalyst

# Android emulator:
dotnet build -t:Run -f net9.0-android
```

## How it works

1. `MainPage.xaml` declares a `HybridWebView` whose `HybridRoot` points
   at the `avrwasm/` folder shipped under `Resources/Raw/`.  MAUI
   serves that folder over an internal `https://` origin to
   `WKWebView` / WebView.
2. When the user clicks **Compile**, `MainPage.xaml.cs` calls
   `HybridWebView.InvokeJavaScriptAsync<CompileResult>("compile", …)`
   with a `CompileRequest` carrying the source, the `-mmcu` value,
   the avr-libc arch family (`avr5`, `avr6`, `avr25`, …) and the name
   of the device CRT object (`crtm328p.o`, …).
3. `pipeline.js` instantiates a fresh `avr-as` Module, writes the
   source string into MEMFS, runs the assembler, then chains the same
   pattern through `avr-ld` (after fetching the avr-libc sidecar files
   via `fetch()`) and finally `objcopy` to produce Intel HEX.
4. The HEX text is returned as JSON and rendered in the `OutputLabel`.
   While the link step is running, the linker prints progress through
   `HybridWebView.SendRawMessage`, which the C# side appends to the
   same label.

## Adding a new device

The `Devices` list in `MainPage.xaml.cs` mirrors
`src/avr-ld/devices.sh` in the parent repository.  When you add a new
entry to the latter and rebuild `avr-ld.js` / the `avr-libc/` sidecar,
add the matching row here:

```csharp
new("My Board (ATmegaXYZ)", "atmegaxyz", "avr5", "crtmxyz.o"),
```

…and make sure the corresponding files exist under
`Resources/Raw/avrwasm/avr-libc/<arch>/`.

## Troubleshooting

| Symptom                                        | Likely cause |
|------------------------------------------------|--------------|
| `Toolchain ready.` never appears               | The three `.js` files are missing under `Resources/Raw/avrwasm/`. |
| `[ld] cannot find -lc`                         | The `avr-libc/<arch>/libc.a` for the selected device is missing. |
| `[ld] /usr/lib/avr/lib/<arch>/<crt>: No such…` | The CRT object for the selected device is missing from the sidecar. |
| Build error `HybridWebView is not defined`     | Ensure the project targets **.NET 9**; `HybridWebView` was added in .NET 9 MAUI. |
