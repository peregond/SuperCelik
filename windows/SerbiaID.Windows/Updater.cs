using System.Diagnostics;
#if LEGACY
using System.Net;
using System.Text;
#else
using System.Net.Http;
#endif
using System.Reflection;
using System.Security.Cryptography;
#if !LEGACY
using System.Text.Json;
#endif
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

    /// The installer of this build among the release files (the 32-bit XP / 7 build has its own).
#if LEGACY
    private const string AssetSuffix = "-windows-x86-legacy-setup.exe";
#else
    private const string AssetSuffix = "-windows-x64-setup.exe";
#endif

    public static Version Current
    {
        get
        {
            var attrs = Assembly.GetExecutingAssembly().GetCustomAttributes(typeof(AssemblyInformationalVersionAttribute), false);
            var s = attrs.Length > 0 ? ((AssemblyInformationalVersionAttribute)attrs[0]).InformationalVersion : "0.0.0";
            return Parse(s) ?? new Version(0, 0, 0);
        }
    }

    public static string CurrentText => Current.ToString(3);

    private static Version Parse(string s)
    {
        var m = Regex.Match(s ?? "", @"(\d+)\.(\d+)\.(\d+)");
        return m.Success ? new Version(int.Parse(m.Groups[1].Value), int.Parse(m.Groups[2].Value), int.Parse(m.Groups[3].Value)) : null;
    }

    private static bool TrustedHost(string url) =>
        Uri.TryCreate(url, UriKind.Absolute, out var u) && u.Scheme == Uri.UriSchemeHttps &&
        (u.Host == "github.com" || u.Host.EndsWith(".github.com") || u.Host.EndsWith(".githubusercontent.com"));

#if LEGACY
    // .NET Framework 4.0: HttpWebRequest (no HttpClient), the small JSON reader, TLS 1.2 where the system has it.
    // Windows XP has no TLS 1.2, so GitHub is not reachable there: the check then reports "unavailable" and the
    // installer is downloaded by hand.
    static Updater()
    {
        try { ServicePointManager.SecurityProtocol = (SecurityProtocolType)(3072 | 768 | 192); } catch { }   // TLS 1.2 | 1.1 | 1.0
    }

    private static HttpWebResponse Get(string url, int timeoutMs)
    {
        var req = (HttpWebRequest)WebRequest.Create(url);
        req.UserAgent = "SuperCelik-updater";
        req.Accept = "application/vnd.github+json";
        req.Timeout = timeoutMs; req.ReadWriteTimeout = timeoutMs;
        return (HttpWebResponse)req.GetResponse();
    }

    private static byte[] ReadAll(Stream s)
    {
        using (var ms = new MemoryStream())
        {
            var buf = new byte[81920]; int n;
            while ((n = s.Read(buf, 0, buf.Length)) > 0) ms.Write(buf, 0, n);
            return ms.ToArray();
        }
    }

    private static string Str(Dictionary<string, object> d, string key)
    {
        object v;
        return d.TryGetValue(key, out v) ? (v as string ?? "") : "";
    }

    /// null = up to date (or no release information reachable).
    public static Task<(UpdateInfo Info, bool Reachable)> CheckAsync() => Compat.Run(() =>
    {
        string json;
        try
        {
            using (var resp = Get("https://api.github.com/repos/" + Repo + "/releases/latest", 20000))
                json = Encoding.UTF8.GetString(ReadAll(resp.GetResponseStream()));
        }
        catch (WebException) { return ((UpdateInfo)null, false); }   // 404 for private repos, no network, no TLS 1.2
        var root = (Dictionary<string, object>)MiniJson.Parse(json);
        var tag = Str(root, "tag_name");
        var remote = Parse(tag);
        if (remote == null || remote <= Current) return ((UpdateInfo)null, true);

        var info = new UpdateInfo { Version = remote, Tag = tag, PageUrl = Str(root, "html_url") };
        object assets;
        if (root.TryGetValue("assets", out assets) && assets is List<object>)
            foreach (var o in (List<object>)assets)
            {
                var a = (Dictionary<string, object>)o;
                var name = Str(a, "name");
                if (!name.EndsWith(AssetSuffix, StringComparison.OrdinalIgnoreCase)) continue;
                info.AssetName = name;
                info.AssetUrl = Str(a, "browser_download_url");
                var ds = Str(a, "digest");
                if (ds.StartsWith("sha256:")) info.Sha256 = ds.Substring(7);
                break;
            }
        // no published SHA-256 = nothing to check the download against: such a release is not installed automatically
        return (info.AssetUrl.Length > 0 && TrustedHost(info.AssetUrl) && info.Sha256.Length == 64 ? info : null, true);
    });

    /// Downloads the installer to a temp folder and verifies its hash. Returns the file path.
    public static Task<string> DownloadAsync(UpdateInfo info) => Compat.Run(() =>
    {
        if (!TrustedHost(info.AssetUrl)) throw new InvalidOperationException("Untrusted download URL");
        var dir = Path.Combine(Path.GetTempPath(), "SuperCelikUpdate");
        Directory.CreateDirectory(dir);
        var path = Path.Combine(dir, Path.GetFileName(info.AssetName));

        byte[] bytes;
        using (var resp = Get(info.AssetUrl, 600000)) bytes = ReadAll(resp.GetResponseStream());

        if (info.Sha256.Length != 64 || !Compat.Hex(Compat.Sha256(bytes)).Equals(info.Sha256, StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("Checksum mismatch: download rejected");
        File.WriteAllBytes(path, bytes);
        return path;
    });

#else
    private static HttpClient NewClient()
    {
        var c = new HttpClient { Timeout = TimeSpan.FromSeconds(20) };
        c.DefaultRequestHeaders.UserAgent.ParseAdd("SuperCelik-updater");
        c.DefaultRequestHeaders.Accept.ParseAdd("application/vnd.github+json");
        return c;
    }

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
            if (!name.EndsWith(AssetSuffix, StringComparison.OrdinalIgnoreCase)) continue;
            info.AssetName = name;
            info.AssetUrl = a.GetProperty("browser_download_url").GetString() ?? "";
            if (a.TryGetProperty("digest", out var d) && d.ValueKind == JsonValueKind.String)
            {
                var ds = d.GetString() ?? "";
                if (ds.StartsWith("sha256:")) info.Sha256 = ds[7..];
            }
            break;
        }
        // no published SHA-256 = nothing to check the download against: such a release is not installed automatically
        return (info.AssetUrl.Length > 0 && TrustedHost(info.AssetUrl) && info.Sha256.Length == 64 ? info : null, true);
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

        if (info.Sha256.Length != 64 || !Compat.Hex(Compat.Sha256(bytes)).Equals(info.Sha256, StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("Checksum mismatch: download rejected");
        await File.WriteAllBytesAsync(path, bytes);
        return path;
    }

#endif

    /// Starts the Inno Setup installer silently (it closes and restarts the app itself).
    public static void RunInstaller(string path, string sha256)
    {
        // The installer runs elevated. Keep the file open without write sharing from the check to the start, and
        // check the hash again on that handle, so nothing can swap the file in the temp folder in between.
        using var locked = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
        if (!Compat.Hex(Compat.Sha256(locked)).Equals(sha256, StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("Checksum mismatch: installer not started");
        var lang = Loc.Current switch { Lang.ru => "russian", Lang.sr or Lang.srCyrl => "serbian", _ => "english" };
        // the installer relaunches the app itself after a silent install (see installer.iss)
        Process.Start(new ProcessStartInfo(path, $"/SILENT /CLOSEAPPLICATIONS /LANG={lang}") { UseShellExecute = true });
    }
}
