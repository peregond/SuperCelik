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
///  - run as an AppImage: downloads the new .AppImage and replaces the file;
///  - run from a Flatpak: no self-update (Flatpak does that), the button opens the release page;
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

    private static string AppImagePath => Packaging.IsAppImage ? Environment.GetEnvironmentVariable("APPIMAGE") : null;
    private static bool IsDebInstall => AppContext.BaseDirectory.StartsWith("/opt/supercelik", StringComparison.Ordinal);
    private static bool Arm => RuntimeInformation.ProcessArchitecture == Architecture.Arm64;

    private static bool FolderWritable() => FileWritable(AppContext.BaseDirectory);

    private static bool FileWritable(string folder)
    {
        try { var f = Path.Combine(folder, ".write-test-" + Guid.NewGuid().ToString("N")); File.WriteAllText(f, ""); File.Delete(f); return true; }
        catch { return false; }
    }

    /// What the app can install on this machine: the full package, and for a portable install also the delta files.
    private sealed record Plan(Asset Full, Asset Manifest, Asset Zip);

    private static Plan MakePlan()
    {
        if (Packaging.IsFlatpak) return null;       // Flatpak updates itself through the store / `flatpak update`
        if (AppImagePath != null)
        {
            if (!File.Exists(AppImagePath) || !FileWritable(Path.GetDirectoryName(AppImagePath))) return null;
            var img = LatestAssets.FirstOrDefault(a => a.Sha256 != null && a.Name.EndsWith(Arm ? "linux-aarch64.AppImage" : "linux-x86_64.AppImage"));
            return img == null ? null : new Plan(img, null, null);
        }
        if (IsDebInstall)
        {
            if (!File.Exists("/usr/bin/pkexec")) return null;
            var deb = LatestAssets.FirstOrDefault(a => a.Sha256 != null && a.Name.EndsWith(Arm ? "linux-arm64.deb" : "linux-amd64.deb"));
            return deb == null ? null : new Plan(deb, null, null);      // a .deb is always installed whole: dpkg has to know the files
        }
        if (!FolderWritable()) return null;
        var tag = Arm ? "linux-arm64" : "linux-x64";
        var tar = LatestAssets.FirstOrDefault(a => a.Sha256 != null && a.Name.EndsWith(tag + ".tar.gz"));
        var man = LatestAssets.FirstOrDefault(a => a.Sha256 != null && a.Name.EndsWith(tag + ".manifest.json"));
        var zip = LatestAssets.FirstOrDefault(a => a.Name.EndsWith(tag + ".zip"));
        if (tar == null && (man == null || zip == null)) return null;
        return new Plan(tar, man, zip);
    }

    /// True when the app can install the new version itself (otherwise the release page is opened).
    public static bool CanSelfUpdate => MakePlan() != null;

    /// Downloads, verifies and installs the new version, then starts it and exits. Throws on any failure.
    /// A portable install first tries the delta update (only the files that changed); if that fails, it downloads the whole .tar.gz.
    public static async Task InstallAsync(Action<string> status, string downloading, string installing)
    {
        var plan = MakePlan() ?? throw new InvalidOperationException("nothing to install");
        var dir = Directory.CreateTempSubdirectory("supercelik-update").FullName;
        try
        {
            var done = false;
            if (plan.Manifest != null && plan.Zip != null)
            {
                try { await Task.Run(() => InstallDelta(plan.Manifest, plan.Zip, dir, status, downloading, installing)); done = true; }
                catch when (plan.Full != null) { /* fall back to the whole archive */ }
            }
            if (!done) await InstallFull(plan.Full, dir, status, downloading, installing);
        }
        finally { try { Directory.Delete(dir, true); } catch { } }

        Process.Start(new ProcessStartInfo(AppImagePath ?? Environment.ProcessPath!) { UseShellExecute = false });
        Environment.Exit(0);
    }

    private static HttpClient NewHttp(TimeSpan timeout)
    {
        var http = new HttpClient { Timeout = timeout };
        http.DefaultRequestHeaders.UserAgent.ParseAdd("SuperCelik-updater");
        return http;
    }

    private static async Task InstallFull(Asset asset, string dir, Action<string> status, string downloading, string installing)
    {
        var file = Path.Combine(dir, asset.Name);
        status(downloading);
        using (var http = NewHttp(TimeSpan.FromMinutes(10)))
        {
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
        if (AppImagePath != null)
        {
            // an AppImage is a single file: put the new one next to the old one and rename over it (the running image stays valid)
            var next = AppImagePath + ".new";
            File.Copy(file, next, true);
            File.SetUnixFileMode(next, UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute | UnixFileMode.GroupRead | UnixFileMode.GroupExecute | UnixFileMode.OtherRead | UnixFileMode.OtherExecute);
            File.Move(next, AppImagePath, true);
        }
        else if (IsDebInstall)
            await Run("pkexec", "env", "DEBIAN_FRONTEND=noninteractive", "apt-get", "install", "-y", file);
        else
        {
            var x = Path.Combine(dir, "x"); Directory.CreateDirectory(x);
            await Run("tar", "-xzf", file, "-C", x);
            var top = Directory.GetDirectories(x).FirstOrDefault() ?? x;
            await Run("cp", "-a", "--remove-destination", top + "/.", AppContext.BaseDirectory);   // unlink first: the running binary can be replaced
        }
    }

    private sealed class ManifestFile { public string p { get; set; } public string s { get; set; } public long n { get; set; } public bool x { get; set; } }
    private sealed class Manifest { public string version { get; set; } public List<ManifestFile> files { get; set; } }

    /// Delta update: the manifest (small, checked against the digest GitHub reports) lists the SHA-256 of every file of the new
    /// version; only the files that differ from the installed ones are read out of the .zip with HTTP range requests, each one
    /// checked against its manifest SHA-256, and then moved into place.
    private static void InstallDelta(Asset manifestAsset, Asset zipAsset, string dir, Action<string> status, string downloading, string installing)
    {
        using var http = NewHttp(TimeSpan.FromMinutes(5));
        var manBytes = http.GetByteArrayAsync(manifestAsset.Url).GetAwaiter().GetResult();
        if (!Convert.ToHexString(SHA256.HashData(manBytes)).Equals(manifestAsset.Sha256, StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("manifest SHA-256 does not match");
        var manifest = JsonSerializer.Deserialize<Manifest>(manBytes) ?? throw new InvalidOperationException("bad manifest");

        var baseDir = Path.GetFullPath(AppContext.BaseDirectory);
        var changed = new List<ManifestFile>();
        foreach (var f in manifest.files)
        {
            var dest = Path.GetFullPath(Path.Combine(baseDir, f.p));
            if (f.p.Contains("..") || Path.IsPathRooted(f.p) || !dest.StartsWith(baseDir)) throw new InvalidOperationException("unsafe path in manifest");
            if (!File.Exists(dest) || new FileInfo(dest).Length != f.n || !Sha(dest).Equals(f.s, StringComparison.OrdinalIgnoreCase)) changed.Add(f);
        }

        var staged = new List<(ManifestFile File, string Path)>();
        if (changed.Count > 0)
        {
            using var zipStream = new HttpRangeStream(http, zipAsset.Url);
            using var zip = new System.IO.Compression.ZipArchive(zipStream, System.IO.Compression.ZipArchiveMode.Read);
            var i = 0;
            foreach (var f in changed)
            {
                status($"{downloading} {++i}/{changed.Count}");
                var entry = zip.GetEntry(f.p) ?? throw new InvalidOperationException("missing in the archive: " + f.p);
                var tmp = Path.Combine(dir, "d" + staged.Count);
                using (var src = entry.Open()) using (var dst = File.Create(tmp)) src.CopyTo(dst);
                if (!Sha(tmp).Equals(f.s, StringComparison.OrdinalIgnoreCase)) throw new InvalidOperationException("SHA-256 does not match: " + f.p);
                staged.Add((f, tmp));
            }
        }

        status(installing);
        foreach (var (f, tmp) in staged)
        {
            var dest = Path.GetFullPath(Path.Combine(baseDir, f.p));
            Directory.CreateDirectory(Path.GetDirectoryName(dest)!);
            var next = dest + ".new";
            File.Copy(tmp, next, true);
            if (f.x) File.SetUnixFileMode(next, UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute | UnixFileMode.GroupRead | UnixFileMode.GroupExecute | UnixFileMode.OtherRead | UnixFileMode.OtherExecute);
            File.Move(next, dest, true);      // a rename: replacing the running binary is fine on Linux
        }
    }

    private static string Sha(string path)
    {
        using var fs = File.OpenRead(path);
        return Convert.ToHexString(SHA256.HashData(fs));
    }

    /// A read-only seekable stream over a file on the web, fetched in blocks with HTTP range requests (what ZipArchive needs).
    private sealed class HttpRangeStream : Stream
    {
        private readonly HttpClient _http; private string _url; private readonly long _length;
        private long _pos; private byte[] _block = Array.Empty<byte>(); private long _blockStart = -1;
        private const int MinBlock = 256 * 1024;

        public HttpRangeStream(HttpClient http, string url)
        {
            _http = http; _url = url;
            using var req = new HttpRequestMessage(HttpMethod.Get, url);
            req.Headers.Range = new System.Net.Http.Headers.RangeHeaderValue(0, 0);
            using var resp = _http.Send(req, HttpCompletionOption.ResponseHeadersRead);
            resp.EnsureSuccessStatusCode();
            _length = resp.Content.Headers.ContentRange?.Length ?? throw new InvalidOperationException("the server does not support range requests");
            _url = resp.RequestMessage?.RequestUri?.ToString() ?? url;      // the final (signed) address: no redirect for every block
        }

        public override bool CanRead => true; public override bool CanSeek => true; public override bool CanWrite => false;
        public override long Length => _length;
        public override long Position { get => _pos; set => _pos = value; }
        public override void Flush() { }
        public override long Seek(long offset, SeekOrigin origin) { _pos = origin == SeekOrigin.Begin ? offset : origin == SeekOrigin.Current ? _pos + offset : _length + offset; return _pos; }
        public override void SetLength(long value) => throw new NotSupportedException();
        public override void Write(byte[] buffer, int offset, int count) => throw new NotSupportedException();

        public override int Read(byte[] buffer, int offset, int count)
        {
            if (_pos >= _length || count == 0) return 0;
            if (_blockStart < 0 || _pos < _blockStart || _pos >= _blockStart + _block.Length)
            {
                var end = Math.Min(_pos + Math.Max(count, MinBlock), _length) - 1;
                using var req = new HttpRequestMessage(HttpMethod.Get, _url);
                req.Headers.Range = new System.Net.Http.Headers.RangeHeaderValue(_pos, end);
                using var resp = _http.Send(req);
                resp.EnsureSuccessStatusCode();
                _block = resp.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult();
                _blockStart = _pos;
                if (_block.Length == 0) return 0;
            }
            var n = (int)Math.Min(count, _blockStart + _block.Length - _pos);
            Array.Copy(_block, _pos - _blockStart, buffer, offset, n);
            _pos += n;
            return n;
        }
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
