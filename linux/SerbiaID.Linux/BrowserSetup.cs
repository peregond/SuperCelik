using System.Diagnostics;

namespace SerbiaID;

/// Browser sign-in with the card certificate on Linux: the browser needs a PKCS#11 module (srb-id-pkcs11, public domain,
/// shipped inside the app in <app folder>/pkcs11) in its NSS database. This finds Firefox profiles (every place Firefox keeps
/// them, see FirefoxProfiles.cs) and the shared NSS database of the Chromium-based browsers (Chrome, Chromium, Edge, Brave) and
/// registers the module with `modutil` (package libnss3-tools). It only runs when the user agrees (and keeps running after that,
/// so a new profile is covered too).
public static class BrowserSetup
{
    public const string ModuleName = "Srb Id PKCS11";
    private static string Bundled => Path.Combine(AppContext.BaseDirectory, "pkcs11", "libsrb-id-pkcs11.so");

    /// The module the browsers load. An AppImage is mounted at a new path on every start, so its module is copied to a fixed
    /// place first; otherwise the browser entry would break after the next launch.
    public static string ModulePath
    {
        get
        {
            if (!Packaging.IsAppImage) return Bundled;
            try
            {
                var dir = Path.Combine(Home, ".local", "share", "SuperCelik", "pkcs11");
                var dest = Path.Combine(dir, "libsrb-id-pkcs11.so");
                if (!File.Exists(dest) || new FileInfo(dest).Length != new FileInfo(Bundled).Length) { Directory.CreateDirectory(dir); File.Copy(Bundled, dest, true); }
                return dest;
            }
            catch { return Bundled; }
        }
    }

    /// A Flatpak app cannot reach the browsers' databases and a host browser cannot load a library from inside the sandbox.
    public static bool HasModule => !Packaging.IsFlatpak && File.Exists(Bundled);

    public sealed record Target(string Label, string Dir);
    /// Kind: nomodule / notool / none, or sandboxed (only browsers that cannot be connected were found), or one of the reasons the module
    /// could not be added: noservice (pcscd is not running) / oldlibc (the C library is older than the module needs) / nolib (libpcsclite is
    /// missing) / failed (anything else), or done (everything connected) / partial (some of it; `Detail` and `Why` say why the rest failed).
    /// Names = the browsers that have the module now. Sandboxed = browsers from Snap / Flatpak that were found and left alone.
    /// Changed = something was connected just now.
    public sealed record Result(string Kind, List<string> Names, string Detail, List<string> Sandboxed = null, string Why = null, bool Changed = false);

    private static string Home => Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);

    private static string ConfigHome
    {
        get
        {
            var xdg = Environment.GetEnvironmentVariable("XDG_CONFIG_HOME");
            return !string.IsNullOrEmpty(xdg) && Path.IsPathRooted(xdg) ? xdg : Path.Combine(Home, ".config");
        }
    }

    // ---- Firefox ----

    /// The folders where Firefox keeps profiles.ini, and whether that Firefox is sandboxed. Firefox up to 146 (and every Firefox that
    /// was started before 147) uses ~/.mozilla/firefox; a new Firefox 147+ profile lives under XDG_CONFIG_HOME (~/.config/mozilla/firefox).
    private static List<(string Root, string Kind)> FirefoxRoots() => new()
    {
        (Path.Combine(Home, ".mozilla", "firefox"), ""),
        (Path.Combine(ConfigHome, "mozilla", "firefox"), ""),
        (Path.Combine(Home, "snap", "firefox", "common", ".mozilla", "firefox"), "Snap"),                    // Ubuntu's default Firefox
        (Path.Combine(Home, "snap", "firefox", "common", ".config", "mozilla", "firefox"), "Snap"),
        (Path.Combine(Home, "snap", "firefox", "current", ".config", "mozilla", "firefox"), "Snap"),
        (Path.Combine(Home, ".var", "app", "org.mozilla.firefox", ".mozilla", "firefox"), "Flatpak"),
        (Path.Combine(Home, ".var", "app", "org.mozilla.firefox", "config", "mozilla", "firefox"), "Flatpak"),
    };

    // ---- Chrome, Chromium, Edge, Brave: one NSS database for all of them ----

    /// A Chromium-based browser. Bins = the commands that show it is installed; Configs = folders under XDG_CONFIG_HOME that show it has been
    /// used; Snap / Flatpak = the Snap name / Flatpak id of its sandboxed build (null = there is none).
    private sealed record ChromiumBrowser(string Name, string[] Bins, string[] Configs, string Snap, string Flatpak);

    private static readonly ChromiumBrowser[] ChromiumFamily =
    {
        new("Chrome", new[] { "google-chrome", "google-chrome-stable", "google-chrome-beta", "google-chrome-unstable" },
            new[] { "google-chrome", "google-chrome-beta", "google-chrome-unstable" }, null, "com.google.Chrome"),
        new("Chromium", new[] { "chromium", "chromium-browser" }, new[] { "chromium" }, "chromium", "org.chromium.Chromium"),
        new("Edge", new[] { "microsoft-edge", "microsoft-edge-stable", "microsoft-edge-beta", "microsoft-edge-dev" },
            new[] { "microsoft-edge", "microsoft-edge-beta", "microsoft-edge-dev" }, null, "com.microsoft.Edge"),
        new("Brave", new[] { "brave-browser", "brave-browser-stable", "brave" }, new[] { "BraveSoftware" }, "brave", "com.brave.Browser"),
    };

    /// The places Chromium keeps its shared NSS database: ~/.pki/nssdb (older versions, and still the one any Chromium uses when it finds it
    /// there) and ~/.local/share/pki/nssdb (the default of Chromium 146 and newer when ~/.pki/nssdb does not exist; Edge follows Chromium).
    /// The module is registered in every one that exists, so it does not matter which one the installed version reads.
    private static List<string> ChromiumDbDirs()
    {
        var dirs = new List<string> { Path.Combine(Home, ".pki", "nssdb"), Path.Combine(Home, ".local", "share", "pki", "nssdb") };
        var data = Environment.GetEnvironmentVariable("XDG_DATA_HOME");
        if (!string.IsNullOrEmpty(data) && Path.IsPathRooted(data))
        {
            var d = Path.Combine(data, "pki", "nssdb");
            if (!dirs.Contains(d)) dirs.Add(d);
        }
        return dirs;
    }

    /// On Ubuntu `chromium-browser` (or a link into /snap/bin) is only a stub for the Snap version, which has its own sandbox and its own
    /// NSS database: as far as this app can tell, that is not an installed browser.
    private static bool IsSnapStub(string path)
    {
        try
        {
            if (path.StartsWith("/snap/", StringComparison.Ordinal)) return true;
            var real = new FileInfo(path).ResolveLinkTarget(true)?.FullName ?? path;
            if (real.StartsWith("/snap/", StringComparison.Ordinal)) return true;
            if (new FileInfo(real).Length >= 16384) return false;           // a real browser, not a small stub script
            var text = File.ReadAllText(real);
            return text.Contains("/snap/") || text.Contains("snap install") || text.Contains("snap run");
        }
        catch { return false; }
    }

    /// The Chromium-based browsers that look installed (as a regular package): one of their commands is on PATH, or their config folder exists.
    private static List<string> InstalledChromium()
    {
        var names = new List<string>();
        foreach (var b in ChromiumFamily)
        {
            bool found = b.Bins.Any(bin => { var p = Which(bin); return p != null && !(b.Snap != null && IsSnapStub(p)); })
                         || b.Configs.Any(c => Directory.Exists(Path.Combine(ConfigHome, c)));
            if (found) names.Add(b.Name);
        }
        return names;
    }

    /// What to call the shared database in messages: the installed browsers ("Chrome / Edge"), or all the usual names when none is found.
    private static string ChromiumLabel()
    {
        var names = InstalledChromium();
        return names.Count > 0 ? string.Join(" / ", names) : "Chrome / Chromium / Edge";
    }

    // ---- what to connect ----

    /// NSS databases of the installed browsers: every Firefox profile, and the shared Chromium database (every copy of it that exists; if there is
    /// none and a Chromium-based browser is installed, `createChromeDb` makes one in ~/.pki/nssdb, which every Chromium version picks up).
    public static List<Target> FindTargets(bool createChromeDb = false)
    {
        var list = new List<Target>();
        foreach (var (root, kind) in FirefoxRoots())
        {
            if (kind != "") continue;
            foreach (var p in FirefoxProfiles.Find(root))
                if (!list.Any(t => t.Dir == p.Dir)) list.Add(new Target("Firefox", p.Dir));
        }
        var dbs = ChromiumDbDirs().Where(d => File.Exists(Path.Combine(d, "cert9.db"))).ToList();
        if (dbs.Count > 0 || (createChromeDb && InstalledChromium().Count > 0))
        {
            var label = ChromiumLabel();
            if (dbs.Count == 0) dbs.Add(ChromiumDbDirs()[0]);
            foreach (var d in dbs) list.Add(new Target(label, d));
        }
        return list;
    }

    /// Browsers installed as a Snap or a Flatpak ("Firefox (Snap)", "Edge (Flatpak)", ...). Their sandbox keeps the card module of this app out
    /// (Ubuntu describes manual steps for Snap browsers, but calls them experimental), so there is nothing reliable to register: the user is told
    /// what to do instead. Firefox is recognised by its profiles, the others by their data folder.
    public static List<string> FindSandboxedBrowsers()
    {
        var found = new List<string>();
        void Add(string name, string kind) { var s = name + " (" + kind + ")"; if (!found.Contains(s)) found.Add(s); }
        foreach (var (root, kind) in FirefoxRoots())
            if (kind != "" && FirefoxProfiles.Find(root, kind).Count > 0) Add("Firefox", kind);
        foreach (var b in ChromiumFamily)
        {
            if (b.Snap != null && Directory.Exists(Path.Combine(Home, "snap", b.Snap))) Add(b.Name, "Snap");
            if (b.Flatpak != null && Directory.Exists(Path.Combine(Home, ".var", "app", b.Flatpak))) Add(b.Name, "Flatpak");
        }
        return found;
    }

    public static string Which(string tool)
    {
        foreach (var dir in (Environment.GetEnvironmentVariable("PATH") ?? "").Split(':', StringSplitOptions.RemoveEmptyEntries))
        {
            var f = Path.Combine(dir, tool);
            if (File.Exists(f)) return f;
        }
        return null;
    }

    private static async Task<(int Code, string Output)> Run(string tool, params string[] args)
    {
        var psi = new ProcessStartInfo(tool) { UseShellExecute = false, RedirectStandardOutput = true, RedirectStandardError = true, RedirectStandardInput = true };
        foreach (var a in args) psi.ArgumentList.Add(a);
        using var p = Process.Start(psi)!;
        p.StandardInput.Close();
        var o = p.StandardOutput.ReadToEndAsync(); var e = p.StandardError.ReadToEndAsync();
        await p.WaitForExitAsync();
        return (p.ExitCode, (await o) + (await e));
    }

    /// True when every found browser database already has the module at the current path (nothing to do).
    public static async Task<bool> IsSetUp()
    {
        if (!HasModule || Which("modutil") == null) return true;       // nothing we could do anyway
        var targets = FindTargets();
        if (targets.Count == 0) return true;
        foreach (var t in targets)
        {
            var (code, text) = await Run("modutil", "-dbdir", "sql:" + t.Dir, "-list");
            if (code != 0 || !text.Contains(ModuleName) || !text.Contains(ModulePath)) return false;
        }
        return true;
    }

    /// Why NSS refused to add the module, when its output says so (null = no known reason). NSS loads the module to add it, so the answers
    /// come from the module's own start-up: it connects to the smart card service first (pcscd stopped: CKR_FUNCTION_FAILED), and the system
    /// has to provide the libraries it was built against (the loader's text is part of the message).
    internal static string WhyFailed(string modutilOutput)
    {
        if (modutilOutput.Contains("CKR_FUNCTION_FAILED")) return "noservice";
        if (modutilOutput.Contains("GLIBC_") && modutilOutput.Contains("not found")) return "oldlibc";             // version `GLIBC_2.36' not found
        if (modutilOutput.Contains("libpcsclite") && modutilOutput.Contains("cannot open shared object")) return "nolib";
        return null;
    }

    /// Registers the module in every found browser database (replacing an entry with another path).
    public static async Task<Result> Setup()
    {
        if (!HasModule) return new Result("nomodule", new(), ModulePath);
        var modutil = Which("modutil");
        if (modutil == null) return new Result("notool", new(), "");
        var sandboxed = FindSandboxedBrowsers();
        var targets = FindTargets(createChromeDb: true);
        if (targets.Count == 0) return sandboxed.Count > 0 ? new Result("sandboxed", new(), "", sandboxed) : new Result("none", new(), ModulePath);

        var done = new List<string>(); string error = null, why = null; bool failed = false, changed = false;
        foreach (var t in targets)
        {
            bool good = false;
            try
            {
                var db = "sql:" + t.Dir;
                if (!File.Exists(Path.Combine(t.Dir, "cert9.db")))
                {
                    Directory.CreateDirectory(t.Dir);
                    var certutil = Which("certutil");
                    if (certutil == null) throw new InvalidOperationException("certutil (libnss3-tools)");
                    var (c0, o0) = await Run(certutil, "-N", "-d", db, "--empty-password");
                    if (c0 != 0) throw new InvalidOperationException(o0.Trim());
                }
                var (lc, listing) = await Run(modutil, "-dbdir", db, "-list");
                if (lc == 0 && listing.Contains(ModuleName) && listing.Contains(ModulePath)) good = true;
                else
                {
                    if (lc == 0 && listing.Contains(ModuleName))
                        await Run(modutil, "-dbdir", db, "-delete", ModuleName, "-force");        // the app moved: replace the old entry
                    var (ac, ao) = await Run(modutil, "-dbdir", db, "-add", ModuleName, "-libfile", ModulePath, "-force");
                    if (ac == 0) { good = true; changed = true; }
                    else { error = ao.Trim(); why ??= WhyFailed(ao); }
                }
            }
            catch (Exception ex) { error = ex.Message; }
            if (good) { if (!done.Contains(t.Label)) done.Add(t.Label); }
            else failed = true;
        }
        if (done.Count == 0) return new Result(why ?? "failed", new(), error ?? "", sandboxed, why);
        return new Result(failed ? "partial" : "done", done, failed ? error ?? "" : "", sandboxed, why, changed);
    }
}
