using System.Diagnostics;
using System.Net.Http;
using System.Reflection;
using System.Security.Cryptography;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace SerbiaID;

public sealed class UpdateInfo
{
    public Version Version;
    public string Tag = "", PageUrl = "", AssetName = "", AssetUrl = "", Sha256 = "";
}

/// Checks the latest GitHub release and installs it. Works only while the release is readable
/// without authentication (public repository). Downloads are restricted to GitHub hosts and
/// verified against the SHA-256 digest published by GitHub when available.
public static class Updater
{
    public const string Repo = "peregond/SuperCelik";

    public static Version Current
    {
        get
        {
            var s = Assembly.GetExecutingAssembly().GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion ?? "0.0.0";
            return Parse(s) ?? new Version(0, 0, 0);
        }
    }

    public static string CurrentText => Current.ToString(3);

    private static Version Parse(string s)
    {
        var m = Regex.Match(s ?? "", @"(\d+)\.(\d+)\.(\d+)");
        return m.Success ? new Version(int.Parse(m.Groups[1].Value), int.Parse(m.Groups[2].Value), int.Parse(m.Groups[3].Value)) : null;
    }

    private static HttpClient NewClient()
    {
        var c = new HttpClient { Timeout = TimeSpan.FromSeconds(20) };
        c.DefaultRequestHeaders.UserAgent.ParseAdd("SuperCelik-updater");
        c.DefaultRequestHeaders.Accept.ParseAdd("application/vnd.github+json");
        return c;
    }

    private static bool TrustedHost(string url) =>
        Uri.TryCreate(url, UriKind.Absolute, out var u) && u.Scheme == Uri.UriSchemeHttps &&
        (u.Host == "github.com" || u.Host.EndsWith(".github.com") || u.Host.EndsWith(".githubusercontent.com"));

    /// null = up to date (or no release information reachable).
    public static async Task<(UpdateInfo Info, bool Reachable)> CheckAsync()
    {
        using var http = NewClient();
        using var resp = await http.GetAsync($"https://api.github.com/repos/{Repo}/releases/latest");
        if (!resp.IsSuccessStatusCode) return (null, false);   // 404 for private repos
        using var doc = JsonDocument.Parse(await resp.Content.ReadAsStringAsync());
        var root = doc.RootElement;
        var tag = root.GetProperty("tag_name").GetString() ?? "";
        var remote = Parse(tag);
        if (remote == null || remote <= Current) return (null, true);

        var info = new UpdateInfo { Version = remote, Tag = tag, PageUrl = root.GetProperty("html_url").GetString() ?? "" };
        foreach (var a in root.GetProperty("assets").EnumerateArray())
        {
            var name = a.GetProperty("name").GetString() ?? "";
            if (!name.EndsWith("-windows-x64-setup.exe", StringComparison.OrdinalIgnoreCase)) continue;
            info.AssetName = name;
            info.AssetUrl = a.GetProperty("browser_download_url").GetString() ?? "";
            if (a.TryGetProperty("digest", out var d) && d.ValueKind == JsonValueKind.String)
            {
                var ds = d.GetString() ?? "";
                if (ds.StartsWith("sha256:")) info.Sha256 = ds[7..];
            }
            break;
        }
        return (info.AssetUrl.Length > 0 && TrustedHost(info.AssetUrl) ? info : null, true);
    }

    /// Downloads the installer to a temp folder and verifies its hash. Returns the file path.
    public static async Task<string> DownloadAsync(UpdateInfo info)
    {
        if (!TrustedHost(info.AssetUrl)) throw new InvalidOperationException("Untrusted download URL");
        var dir = Path.Combine(Path.GetTempPath(), "SuperCelikUpdate");
        Directory.CreateDirectory(dir);
        var path = Path.Combine(dir, Path.GetFileName(info.AssetName));

        using var http = new HttpClient { Timeout = TimeSpan.FromMinutes(10) };
        http.DefaultRequestHeaders.UserAgent.ParseAdd("SuperCelik-updater");
        var bytes = await http.GetByteArrayAsync(info.AssetUrl);

        if (info.Sha256.Length > 0)
        {
            var hash = Convert.ToHexString(SHA256.HashData(bytes));
            if (!hash.Equals(info.Sha256, StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("Checksum mismatch: download rejected");
        }
        await File.WriteAllBytesAsync(path, bytes);
        return path;
    }

    /// Starts the Inno Setup installer silently (it closes and restarts the app itself).
    public static void RunInstaller(string path)
    {
        Process.Start(new ProcessStartInfo(path, "/SILENT /CLOSEAPPLICATIONS /RESTARTAPPLICATIONS") { UseShellExecute = true });
    }
}
