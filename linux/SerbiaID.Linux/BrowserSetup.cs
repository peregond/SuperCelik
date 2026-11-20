using System.Diagnostics;

namespace SerbiaID;

/// Browser sign-in with the card certificate on Linux: the browser needs a PKCS#11 module (srb-id-pkcs11, public domain,
/// shipped inside the app in <app folder>/pkcs11) in its NSS database. This finds Firefox profiles (every place Firefox keeps
/// them, see FirefoxProfiles.cs) and the Chrome / Chromium database and registers the module with `modutil` (package
/// libnss3-tools). It only runs when the user agrees (and keeps running after that, so a new profile is covered too).
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
    /// Kind: nomodule / notool / none / noservice / sandboxed / failed, or done (everything connected) / partial (some of it; `Detail`
    /// says why the rest failed). Names = the browsers that have the module now. Sandboxed = Firefox from Snap / Flatpak found: it cannot
    /// load a module from outside its sandbox, so it is left alone. NoService = pcscd is not running. Changed = something was connected just now.
    public sealed record Result(string Kind, List<string> Names, string Detail, List<string> Sandboxed = null, bool NoService = false, bool Changed = false);

    private static string Home => Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);

    private static string ConfigHome
    {
        get
        {
            var xdg = Environment.GetEnvironmentVariable("XDG_CONFIG_HOME");
            return !string.IsNullOrEmpty(xdg) && Path.IsPathRooted(xdg) ? xdg : Path.Combine(Home, ".config");
        }
    }

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

    /// NSS databases of the installed browsers: every Firefox profile, and the shared Chrome / Chromium database.
    public static List<Target> FindTargets(bool createChromeDb = false)
    {
        var list = new List<Target>();
        foreach (var (root, kind) in FirefoxRoots())
        {
            if (kind != "") continue;
            foreach (var p in FirefoxProfiles.Find(root))
                if (!list.Any(t => t.Dir == p.Dir)) list.Add(new Target("Firefox", p.Dir));
        }
        var chromeDb = new[] { Path.Combine(Home, ".pki", "nssdb"), Path.Combine(Home, ".local", "share", "pki", "nssdb") }
            .FirstOrDefault(d => File.Exists(Path.Combine(d, "cert9.db")));
        if (chromeDb != null) list.Add(new Target("Chrome / Chromium", chromeDb));
        else if (createChromeDb && ChromiumInstalled()) list.Add(new Target("Chrome / Chromium", Path.Combine(Home, ".pki", "nssdb")));
        return list;
    }

    private static bool ChromiumInstalled() =>
        new[] { "google-chrome", "google-chrome-stable", "chromium", "chromium-browser", "microsoft-edge", "brave-browser" }.Any(n => Which(n) != null);

    /// "Snap" / "Flatpak" for every sandboxed Firefox that has a profile. Its sandbox hides our module (and the host's smart card
    /// libraries), so there is nothing we could register: the user is told what to do instead.
    public static List<string> FindSandboxedFirefox()
    {
        var kinds = new List<string>();
        foreach (var (root, kind) in FirefoxRoots())
            if (kind != "" && !kinds.Contains(kind) && FirefoxProfiles.Find(root, kind).Count > 0) kinds.Add(kind);
        return kinds;
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

    /// Registers the module in every found browser database (replacing an entry with another path).
    public static async Task<Result> Setup()
    {
        if (!HasModule) return new Result("nomodule", new(), ModulePath);
        var modutil = Which("modutil");
        if (modutil == null) return new Result("notool", new(), "");
        var sandboxed = FindSandboxedFirefox();
        var targets = FindTargets(createChromeDb: true);
        if (targets.Count == 0) return sandboxed.Count > 0 ? new Result("sandboxed", new(), "", sandboxed) : new Result("none", new(), ModulePath);

        var done = new List<string>(); string error = null; bool noService = false, failed = false, changed = false;
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
                    else
                    {
                        error = ao.Trim();
                        // NSS loads the module to add it, and the module starts by connecting to the smart card service: without a running pcscd it answers CKR_FUNCTION_FAILED
                        if (ao.Contains("CKR_FUNCTION_FAILED")) noService = true;
                    }
                }
            }
            catch (Exception ex) { error = ex.Message; }
            if (good) { if (!done.Contains(t.Label)) done.Add(t.Label); }
            else failed = true;
        }
        if (done.Count == 0) return new Result(noService ? "noservice" : "failed", new(), error ?? "", sandboxed, noService);
        return new Result(failed ? "partial" : "done", done, failed ? error ?? "" : "", sandboxed, noService, changed);
    }
}
