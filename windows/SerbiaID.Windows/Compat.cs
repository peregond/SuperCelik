using System.Security.Cryptography;
using System.Text;
using System.Threading.Tasks;

namespace SerbiaID;

/// Small helpers that exist in modern .NET but not in .NET Framework 4.0 (the build for Windows XP / 7, see
/// windows/SerbiaID.Windows.Legacy). Both builds use them, so the shared code stays identical.
internal static class Compat
{
    public static string Hex(byte[] b)
    {
        var sb = new StringBuilder(b.Length * 2);
        foreach (var x in b) sb.Append(x.ToString("X2"));
        return sb.ToString();
    }

    public static byte[] FromHex(string h)
    {
        if (h == null || h.Length % 2 != 0) throw new FormatException("Bad hex string");
        var r = new byte[h.Length / 2];
        for (int i = 0; i < r.Length; i++) r[i] = Convert.ToByte(h.Substring(i * 2, 2), 16);
        return r;
    }

    public static byte[] Sha256(byte[] data) { using (var s = SHA256.Create()) return s.ComputeHash(data); }

    public static byte[] Sha256(Stream data) { using (var s = SHA256.Create()) return s.ComputeHash(data); }

    public static int Clamp(int v, int min, int max) => v < min ? min : v > max ? max : v;

    public static byte[] Slice(byte[] src, int start, int count)
    {
        var r = new byte[count];
        Buffer.BlockCopy(src, start, r, 0, count);
        return r;
    }

    // ---- JSON: System.Text.Json on modern .NET, the small reader/writer in Legacy\MiniJson.cs on .NET 4.0 ----

    /// Reads a settings-like object (public properties of simple types); a missing or null value keeps the default.
    public static T FromJson<T>(string text) where T : class, new() =>
#if LEGACY
        MiniJson.Populate(new T(), MiniJson.Parse(text));
#else
        System.Text.Json.JsonSerializer.Deserialize<T>(text) ?? new T();
#endif

    public static string ToJson(object o) =>
#if LEGACY
        MiniJson.Write(MiniJson.ToTree(o));
#else
        System.Text.Json.JsonSerializer.Serialize(o, new System.Text.Json.JsonSerializerOptions { WriteIndented = true });
#endif

    /// Indented, non-ASCII text kept readable (the export file).
    public static string ToJsonReadable(Dictionary<string, string> o) =>
#if LEGACY
        MiniJson.Write(o);
#else
        System.Text.Json.JsonSerializer.Serialize(o, new System.Text.Json.JsonSerializerOptions
            { WriteIndented = true, Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping });
#endif

    public static Task<T> Run<T>(Func<T> f) =>
#if LEGACY
        TaskEx.Run(f);
#else
        Task.Run(f);
#endif

    public static Task<T> Run<T>(Func<Task<T>> f) =>
#if LEGACY
        TaskEx.Run(f);
#else
        Task.Run(f);
#endif

    public static Task Run(Action a) =>
#if LEGACY
        TaskEx.Run(a);
#else
        Task.Run(a);
#endif
}
