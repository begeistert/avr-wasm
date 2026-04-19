using System.Text.Json.Serialization;

namespace MauiAvrAssembler;

/// <summary>Payload sent from C# to <c>window.compile</c> in pipeline.js.</summary>
public sealed record CompileRequest(
    [property: JsonPropertyName("source")] string Source,
    [property: JsonPropertyName("mcu")]    string Mcu,
    [property: JsonPropertyName("arch")]   string Arch,
    [property: JsonPropertyName("crt")]    string Crt);

/// <summary>Result returned by <c>window.compile</c>.</summary>
public sealed record CompileResult(
    [property: JsonPropertyName("ok")]  bool    Ok,
    [property: JsonPropertyName("hex")] string? Hex,
    [property: JsonPropertyName("log")] string? Log);

/// <summary>
/// Source-generated <c>JsonSerializerContext</c>.  Required because the
/// project ships AOT/trimmer-friendly via .NET 9 — using reflection-based
/// serialisation would either warn or fail outright on iOS.
/// </summary>
[JsonSourceGenerationOptions(WriteIndented = false)]
[JsonSerializable(typeof(CompileRequest))]
[JsonSerializable(typeof(CompileResult))]
public partial class JsonContext : JsonSerializerContext
{
}
