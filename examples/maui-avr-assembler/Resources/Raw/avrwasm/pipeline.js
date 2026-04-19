// pipeline.js — runs inside the HybridWebView.
//
// Exposes a single async function `compile({ source, mcu, arch, crt })`
// invoked by C# via HybridWebView.InvokeJavaScriptAsync.  Returns
// `{ ok, hex, log }`.  The implementation chains:
//
//     avr-as   →  program.s   ──► program.o
//     avr-ld   →  program.o   ──► program.elf   (links with avr-libc)
//     objcopy  →  program.elf ──► program.hex   (Intel HEX)
//
// Each tool is a fresh emscripten Module instance; emscripten modules are
// *not* re-entrant so we never reuse one across calls.
//
// Diagnostic output from each tool is forwarded to the C# side through
// HybridWebView.SendRawMessage — the host appends those lines to its log
// label so the user sees what happened on a failure.

(function () {
    "use strict";

    function logToHost(line) {
        try {
            // Provided by Microsoft.Maui.Controls.HybridWebView.
            window.HybridWebView.SendRawMessage(line);
        } catch {
            console.log(line);
        }
    }

    function fail(stage, log) {
        return { ok: false, hex: null, log: `[${stage}]\n${log}` };
    }

    // Run an emscripten Module factory with the given argv, optional
    // input files (Map<path, Uint8Array>) and a single expected output
    // file path.  Resolves to the output bytes; rejects with the captured
    // stderr/stdout log on non-zero exit.
    async function run(factory, label, argv, inputs, outputPath) {
        const log = [];
        const pipe = (s) => { log.push(`[${label}] ${s}`); logToHost(`[${label}] ${s}`); };

        let outputBytes;
        let exitCode = 0;

        const module = await factory({
            arguments: argv,
            print:     pipe,
            printErr:  pipe,
            noExitRuntime: false,
            // emscripten calls quit() with the program's exit code.
            // It runs after main() returns but before postRun, so the
            // captured value is reliable inside the postRun callback.
            quit: (code) => { exitCode = code; },
            preRun: [(m) => {
                for (const [path, bytes] of inputs) {
                    const slash = path.lastIndexOf("/");
                    if (slash > 0) {
                        m.FS.mkdirTree(path.substring(0, slash));
                    }
                    m.FS.writeFile(path, bytes);
                }
            }],
            postRun: [(m) => {
                if (exitCode === 0) {
                    try { outputBytes = m.FS.readFile(outputPath); }
                    catch (e) { pipe(`could not read ${outputPath}: ${e.message}`); }
                }
            }],
        });

        // A non-zero exit, or an output file we could not read, both
        // mean the tool did not produce the expected artifact.  The
        // captured stdout/stderr is the user's only diagnostic so we
        // pass it through verbatim.
        if (exitCode !== 0 || !outputBytes) {
            const err = new Error(log.join("\n") || `${label} failed`);
            err.tool = label;
            throw err;
        }
        return outputBytes;
    }

    // Cache for avr-libc files keyed by `${arch}/${name}` so we only
    // fetch each one once per session.
    const libcCache = new Map();
    async function loadLibc(arch, name) {
        const key = `${arch}/${name}`;
        let bytes = libcCache.get(key);
        if (!bytes) {
            const r = await fetch(`avr-libc/${arch}/${name}`);
            if (!r.ok) {
                throw new Error(`avr-libc/${arch}/${name}: HTTP ${r.status}`);
            }
            bytes = new Uint8Array(await r.arrayBuffer());
            libcCache.set(key, bytes);
        }
        return bytes;
    }

    window.compile = async function compile(req) {
        const enc = new TextEncoder();
        const dec = new TextDecoder();

        try {
            // ── Step 1: assemble ────────────────────────────────────────
            const objectBytes = await run(
                window.__avrAsFactory, "as",
                ["-mmcu=" + req.mcu, "-o", "program.o", "program.s"],
                new Map([["program.s", enc.encode(req.source)]]),
                "program.o");

            // ── Step 2: link.  avr-ld needs the avr-libc archives and the
            //     device-specific CRT object at the same paths a native
            //     `avr-gcc` install uses, so we mirror them under
            //     /usr/lib/avr/lib/<arch>/ in the Emscripten MEMFS. ────
            const libDir = `/usr/lib/avr/lib/${req.arch}`;
            const linkInputs = new Map([
                ["program.o",                          objectBytes],
                [`${libDir}/${req.crt}`, await loadLibc(req.arch, req.crt)],
                [`${libDir}/crtn.o`,     await loadLibc(req.arch, "crtn.o")],
                [`${libDir}/libc.a`,     await loadLibc(req.arch, "libc.a")],
                [`${libDir}/libm.a`,     await loadLibc(req.arch, "libm.a")],
            ]);
            const elfBytes = await run(
                window.__avrLdFactory, "ld",
                [
                    "-m", req.arch,
                    `${libDir}/${req.crt}`,
                    "program.o",
                    `-L${libDir}`, "-lc",
                    "-o", "program.elf",
                ],
                linkInputs,
                "program.elf");

            // ── Step 3: convert ELF → Intel HEX ─────────────────────────
            const hexBytes = await run(
                window.__objcopyFactory, "objcopy",
                ["-O", "ihex", "-R", ".eeprom", "program.elf", "program.hex"],
                new Map([["program.elf", elfBytes]]),
                "program.hex");

            return { ok: true, hex: dec.decode(hexBytes), log: null };
        } catch (e) {
            return fail(e.tool || "host", e.message || String(e));
        }
    };

    document.getElementById("status").textContent =
        "Toolchain ready. Waiting for a compile request from the host…";
})();
