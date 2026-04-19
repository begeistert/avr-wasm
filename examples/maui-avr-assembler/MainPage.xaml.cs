using System.Text.Json;

namespace MauiAvrAssembler;

/// <summary>
/// Bridges the MAUI UI to the JavaScript AVR toolchain hosted inside a
/// <see cref="HybridWebView"/>.  The web view loads <c>avrwasm/index.html</c>
/// (shipped under <c>Resources/Raw/avrwasm/</c>), which in turn loads the
/// emscripten-built <c>avr-as.js</c>, <c>avr-ld.js</c> and <c>objcopy.js</c>
/// modules together with the <c>avr-libc/</c> sidecar tree.  The user enters
/// AVR assembly, picks a target device, and we round-trip:
///
///     C# source string ──► JS pipeline ──► .o ──► .elf ──► Intel HEX ──► C# UI
///
/// On iOS this runs entirely inside <c>WKWebView</c>, with no native code
/// other than MAUI itself, so the pipeline works on a real device or in
/// the simulator without any extra entitlements.
/// </summary>
public partial class MainPage : ContentPage
{
    /// <summary>
    /// Devices supported by the bundled avr-ld build.  MUST stay in sync
    /// with <c>src/avr-ld/devices.sh</c> in the avr-wasm repository.
    /// </summary>
    private static readonly DeviceInfo[] Devices =
    [
        new("Arduino Uno (ATmega328P)",  "atmega328p", "avr5",  "crtatmega328p.o"),
        new("Arduino Nano (ATmega328P)", "atmega328p", "avr5",  "crtatmega328p.o"),
        new("Arduino Mega (ATmega2560)", "atmega2560", "avr6",  "crtatmega2560.o"),
        new("ATtiny85",                  "attiny85",   "avr25", "crtattiny85.o"),
    ];

    public MainPage()
    {
        InitializeComponent();

        DevicePicker.ItemsSource = Devices.Select(d => d.Label).ToList();
        DevicePicker.SelectedIndex = 0;

        SourceEditor.Text =
            """
            ; Blink PB5 (Arduino Uno pin 13) forever.
            .arch atmega328p
            .text
            .global main
            main:
                ldi r16, 0x20      ; PB5 mask
                out 0x04, r16      ; DDRB  = 0x20  (PB5 as output)
            loop:
                in  r17, 0x05      ; r17 = PORTB
                eor r17, r16       ; toggle PB5
                out 0x05, r17
                rcall delay
                rjmp loop
            delay:
                ldi r18, 0xFF
            d1: ldi r19, 0xFF
            d2: dec r19
                brne d2
                dec r18
                brne d1
                ret
            """;
    }

    private async void OnCompileClicked(object? sender, EventArgs e)
    {
        if (DevicePicker.SelectedIndex < 0)
        {
            return;
        }

        var device = Devices[DevicePicker.SelectedIndex];

        SetBusy(true, $"Assembling for {device.Label}…");
        try
        {
            var request = new CompileRequest(
                Source: SourceEditor.Text ?? string.Empty,
                Mcu:    device.Mcu,
                Arch:   device.Arch,
                Crt:    device.Crt);

            // HybridWebView.InvokeJavaScriptAsync<TReturn>(method, args, …)
            // serialises arguments with System.Text.Json and deserialises
            // the JS return value the same way.  The JS side defines
            // window.compile(request) in pipeline.js.
            var result = await ToolHost.InvokeJavaScriptAsync<CompileResult>(
                methodName: "compile",
                paramValues: [request],
                paramJsonTypeInfos: [JsonContext.Default.CompileRequest],
                returnTypeJsonTypeInfo: JsonContext.Default.CompileResult)
                ?? new CompileResult(false, null, "JS pipeline returned null");

            if (!result.Ok)
            {
                OutputLabel.Text =
                    $"❌ Compilation failed:\n\n{result.Log ?? "(no diagnostics)"}";
            }
            else
            {
                OutputLabel.Text =
                    $"✅ {result.Hex!.Split('\n').Length - 1} lines of Intel HEX\n\n{result.Hex}";
            }
        }
        catch (Exception ex)
        {
            OutputLabel.Text = $"❌ Host error: {ex.Message}";
        }
        finally
        {
            SetBusy(false);
        }
    }

    /// <summary>
    /// HybridWebView raises this every time the JS side calls
    /// <c>HybridWebView.SendRawMessage(text)</c>.  We use it as a one-way
    /// channel for streaming progress / log output from the linker.
    /// </summary>
    private void OnHybridRawMessage(object? sender, HybridWebViewRawMessageReceivedEventArgs e)
    {
        if (string.IsNullOrEmpty(e.Message))
        {
            return;
        }

        // Marshal back to the UI thread; HybridWebView events on iOS may
        // arrive on a non-UI dispatcher.
        Dispatcher.Dispatch(() =>
        {
            OutputLabel.Text = string.IsNullOrEmpty(OutputLabel.Text)
                ? e.Message
                : $"{OutputLabel.Text}\n{e.Message}";
        });
    }

    private void SetBusy(bool busy, string? statusText = null)
    {
        BusyIndicator.IsRunning = busy;
        BusyIndicator.IsVisible = busy;
        CompileButton.IsEnabled = !busy;
        if (busy && statusText is not null)
        {
            OutputLabel.Text = statusText;
        }
    }

    private sealed record DeviceInfo(string Label, string Mcu, string Arch, string Crt);
}
