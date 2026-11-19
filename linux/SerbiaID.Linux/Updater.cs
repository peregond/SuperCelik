using System.Diagnostics;
using System.Net.Http;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace SerbiaID;

public sealed record Asset(string Name, string Url, string Sha256);

/// Looks for a newer GitHub release and can install it.
///  - installed from the .deb (/opt/supercelik): downloads the matching .deb and installs it with `pkexec apt-get install`
///    (the system asks for the administrator password);
///  - unpacked from the .tar.gz into a folder the user can write to: downloads the .tar.gz and copies the new files over the old ones.
/// A file is installed only if its SHA-256 equals the digest GitHub reports for that release asset; otherwise the app only
/// opens the release page. After a successful update the app starts itself again.
public static class Updater
{
    public const string Repo = "peregond/SuperCelik";

    public static Version Current => Parse(Assembly.GetExecutingAssembly().GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion) ?? new Version(0, 0, 0);
    public static string CurrentText => Current.ToString(3);

    private static Version Parse(string s)
    {
        var m = Regex.Match(s ?? "", @"(\d+)\.(\d+)\.(\d+)");
        return m.Success ? new Version(int.Parse(m.Groups[1].Value), int.Parse(m.Groups[2].Value), int.Parse(m.Groups[3].Value)) : null;
    }

    /// Info = null when up to date; Reachable = false when the release could not be read.
    public static async Task<(Version Info, string Page, bool Reachable)> CheckAsync()
    {
        using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(20) };
        http.DefaultRequestHeaders.UserAgent.ParseAdd("SuperCelik-updater");
        http.DefaultRequestHeaders.Accept.ParseAdd("application/vnd.github+json");
        using var resp = await http.GetAsync($"https://api.github.com/repos/{Repo}/releases/latest");
        if (!resp.IsSuccessStatusCode) return (null, null, false);
        using var doc = JsonDocument.Parse(await resp.Content.ReadAsStringAsync());
        var assets = new List<Asset>();
        if (doc.RootElement.TryGetProperty("assets", out var arr) && arr.ValueKind == JsonValueKind.Array)
            foreach (var a in arr.EnumerateArray())
            {
                var digest = a.TryGetProperty("digest", out var d) && d.ValueKind == JsonValueKind.String ? d.GetString() : null;
                assets.Add(new Asset(a.GetProperty("name").GetString(), a.GetProperty("browser_download_url").GetString(),
                    digest != null && digest.StartsWith("sha256:", StringComparison.OrdinalIgnoreCase) ? digest[7..] : null));
            }
        LatestAssets = assets;
        var remote = Parse(doc.RootElement.GetProperty("tag_name").GetString());
        var page = $"https://github.com/{Repo}/releases/latest";
        return (remote != null && remote > Current ? remote : null, page, true);
    }

    public static List<Asset> LatestAssets { get; private set; } = new();

    private static bool IsDebInstall => AppContext.BaseDirectory.StartsWith("/opt/supercelik", StringComparison.Ordinal);
    private static bool Arm => RuntimeInformation.ProcessArchitecture == Architecture.Arm64;

    private static bool FolderWritable()
    {
        try { var f = Path.Combine(AppContext.BaseDirectory, ".write-test-" + Guid.NewGuid().ToString("N")); File.WriteAllText(f, ""); File.Delete(f); return true; }
        catch { return false; }
    }

    /// The package to install for this machine, or null when the app cannot update itself (then the release page is opened).
    public static Asset Pick()
    {
        if (IsDebInstall)
        {
            if (!File.Exists("/usr/bin/pkexec")) return null;
            return LatestAssets.FirstOrDefault(a => a.Sha256 != null && a.Name.EndsWith(Arm ? "linux-arm64.deb" : "linux-amd64.deb"));
        }
        if (!FolderWritable()) return null;
        return LatestAssets.FirstOrDefault(a => a.Sha256 != null && a.Name.EndsWith(Arm ? "linux-arm64.tar.gz" : "linux-x64.tar.gz"));
    }

    /// Downloads, verifies and installs the package, then starts the new version and exits. Throws on any failure.
    public static async Task InstallAsync(Asset asset, Action<string> status, string downloading, string installing)
    {
        var dir = Directory.CreateTempSubdirectory("supercelik-update").FullName;
        try
        {
            var file = Path.Combine(dir, asset.Name);
            status(downloading);
            using (var http = new HttpClient { Timeout = TimeSpan.FromMinutes(10) })
            {
                http.DefaultRequestHeaders.UserAgent.ParseAdd("SuperCelik-updater");
                using var resp = await http.GetAsync(asset.Url, HttpCompletionOption.ResponseHeadersRead);
                resp.EnsureSuccessStatusCode();
                await using var src = await resp.Content.ReadAsStreamAsync();
                await using var dst = File.Create(file);
                await src.CopyToAsync(dst);
            }
            string hash;
            await using (var fs = File.OpenRead(file)) hash = Convert.ToHexString(await SHA256.HashDataAsync(fs));
            if (!hash.Equals(asset.Sha256, StringComparison.OrdinalIgnoreCase)) throw new InvalidOperationException("SHA-256 does not match");

            status(installing);
            if (IsDebInstall)
                await Run("pkexec", "env", "DEBIAN_FRONTEND=noninteractive", "apt-get", "install", "-y", file);
            else
            {
                var x = Path.Combine(dir, "x"); Directory.CreateDirectory(x);
                await Run("tar", "-xzf", file, "-C", x);
                var top = Directory.GetDirectories(x).FirstOrDefault() ?? x;
                await Run("cp", "-a", "--remove-destination", top + "/.", AppContext.BaseDirectory);   // unlink first: the running binary can be replaced
            }
        }
        finally { try { Directory.Delete(dir, true); } catch { } }

        Process.Start(new ProcessStartInfo(Environment.ProcessPath!) { UseShellExecute = false });
        Environment.Exit(0);
    }

    private static async Task Run(string tool, params string[] args)
    {
        var psi = new ProcessStartInfo(tool) { UseShellExecute = false, RedirectStandardError = true, RedirectStandardOutput = true };
        foreach (var a in args) psi.ArgumentList.Add(a);
        using var p = Process.Start(psi)!;
        var err = p.StandardError.ReadToEndAsync();
        var outp = p.StandardOutput.ReadToEndAsync();      // drained too: a full pipe would block apt forever
        await p.WaitForExitAsync();
        await outp;
        if (p.ExitCode != 0) throw new InvalidOperationException($"{tool} exited with {p.ExitCode}: {(await err).Trim()}");
    }
}
