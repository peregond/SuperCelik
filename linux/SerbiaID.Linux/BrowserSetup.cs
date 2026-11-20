using System.Diagnostics;
using System.Text.RegularExpressions;

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

    /// Like Run, but gives up after `limit` and kills the tool: a stuck smart card service (pcscd) makes `modutil` wait for ever, and the check is
    /// what people press when something is wrong.
    private static async Task<(int Code, string Output, bool TimedOut)> RunLimited(TimeSpan limit, string tool, params string[] args)
    {
        var psi = new ProcessStartInfo(tool) { UseShellExecute = false, RedirectStandardOutput = true, RedirectStandardError = true, RedirectStandardInput = true };
        foreach (var a in args) psi.ArgumentList.Add(a);
        using var p = Process.Start(psi)!;
        p.StandardInput.Close();
        var o = p.StandardOutput.ReadToEndAsync(); var e = p.StandardError.ReadToEndAsync();
        using var cts = new CancellationTokenSource(limit);
        try { await p.WaitForExitAsync(cts.Token); }
        catch (OperationCanceledException) { try { p.Kill(true); } catch { } return (-1, "", true); }
        return (p.ExitCode, (await o) + (await e), false);
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

    /// True when at least one browser database already has our module, under any path: the user connected it earlier (this also covers people who
    /// agreed in a version that did not remember it yet).
    public static async Task<bool> AnyConnected()
    {
        if (!HasModule || Which("modutil") == null) return false;
        foreach (var t in FindTargets())
        {
            var (code, text) = await Run("modutil", "-dbdir", "sql:" + t.Dir, "-list");
            if (code == 0 && text.Contains(ModuleName)) return true;
        }
        return false;
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

    // ---- "Check browser sign-in": what a browser would find ----

    /// What `modutil -list` says about our module in one database. NSS loads the module to print this, the same way a browser does, so it shows
    /// what the browser would get: Loaded = the module started (it does not when the smart card service is stopped or a library is missing),
    /// Slots = the readers it reports (one slot per reader), Token = the name of the card in the first reader that has one ("" = no card seen).
    public sealed record ModuleState(bool Registered, bool Loaded, int Slots, string Token);

    internal static ModuleState ParseListing(string listing)
    {
        bool inside = false, registered = false, loaded = false; int slots = 0; string token = "";
        foreach (var raw in listing.Split('\n'))
        {
            var line = raw.Trim();
            if (line.Length == 0) continue;
            var header = Regex.Match(line, @"^\d+\.\s+(.*)$");                         // "2. Srb Id PKCS11": the next module starts
            if (header.Success) { inside = header.Groups[1].Value.Trim() == ModuleName; registered |= inside; continue; }
            if (line.StartsWith("---")) { inside = false; continue; }
            if (!inside) continue;
            if (line.StartsWith("status:")) loaded = line.Substring("status:".Length).Trim() == "loaded";       // otherwise "Not loaded"
            else if (line.StartsWith("slot:")) slots++;
            else if (line.StartsWith("token:") && token.Length == 0) token = line.Substring("token:".Length).Trim();    // empty for a reader without a card
        }
        return new ModuleState(registered, loaded, slots, token);
    }

    /// How long one `modutil` call may take in the check (it takes a fraction of a second when the smart card service is healthy).
    internal static TimeSpan CheckTimeout = TimeSpan.FromSeconds(15);

    /// Kind: nomodule / notool / none / sandboxed (nothing the app could check), stuck (the smart card service does not answer), or checked. Connected / Missing = the browsers whose database has
    /// the module (at the current path) and those whose database lacks it. Loaded / Why / Slots / Token: what the module does when loaded
    /// (Why = the reason it does not start, see WhyFailed; only known when no database loads it).
    public sealed record Diagnosis(string Kind, List<string> Connected, List<string> Missing, List<string> Sandboxed, bool Loaded, string Why, int Slots, string Token);

    public static async Task<Diagnosis> Diagnose()
    {
        var none = new List<string>();
        if (!HasModule) return new Diagnosis("nomodule", none, none, none, false, null, 0, "");
        var modutil = Which("modutil");
        if (modutil == null) return new Diagnosis("notool", none, none, none, false, null, 0, "");
        var sandboxed = FindSandboxedBrowsers();
        var targets = FindTargets(createChromeDb: true);                // a database that Setup would make counts as "not connected yet"
        if (targets.Count == 0) return new Diagnosis(sandboxed.Count > 0 ? "sandboxed" : "none", none, none, sandboxed, false, null, 0, "");

        var connected = new List<string>(); var missing = new List<string>();
        bool loaded = false; int slots = 0; string token = "";
        foreach (var t in targets)
        {
            var (code, text, timedOut) = await RunLimited(CheckTimeout, modutil, "-dbdir", "sql:" + t.Dir, "-list");
            if (timedOut) return new Diagnosis("stuck", none, none, sandboxed, false, null, 0, "");
            var s = code == 0 ? ParseListing(text) : new ModuleState(false, false, 0, "");
            if (s.Registered && text.Contains(ModulePath))
            {
                if (!connected.Contains(t.Label)) connected.Add(t.Label);
                loaded |= s.Loaded; slots = Math.Max(slots, s.Slots);
                if (token.Length == 0) token = s.Token;
            }
            else if (!missing.Contains(t.Label)) missing.Add(t.Label);                  // not there, or there under an old path (Setup replaces it)
        }
        var why = connected.Count > 0 && !loaded ? await WhyNotLoaded() : null;
        return new Diagnosis("checked", connected, missing, sandboxed, loaded, why, slots, token);
    }

    /// Adds the module to an empty throw-away database to get NSS's own explanation of why it does not start (the listing only says "Not loaded").
    private static async Task<string> WhyNotLoaded()
    {
        var dir = Path.Combine(Path.GetTempPath(), "supercelik-nss-" + Guid.NewGuid().ToString("N"));
        try
        {
            var certutil = Which("certutil"); var modutil = Which("modutil");
            if (certutil == null || modutil == null) return null;
            Directory.CreateDirectory(dir);
            var (c, _, _) = await RunLimited(CheckTimeout, certutil, "-N", "-d", "sql:" + dir, "--empty-password");
            if (c != 0) return null;
            var (ac, ao, timedOut) = await RunLimited(CheckTimeout, modutil, "-dbdir", "sql:" + dir, "-add", ModuleName, "-libfile", ModulePath, "-force");
            return timedOut ? null : ac == 0 ? null : WhyFailed(ao);
        }
        catch { return null; }
        finally { try { Directory.Delete(dir, true); } catch { } }
    }

    /// The one thing to do next, from the first thing that is wrong. `readers` / `cardInApp` = what the app itself sees through the smart card
    /// service. Returns the Kind for the cases Diagnose could not check (nomodule / notool / none / sandboxed / stuck), otherwise: connect (the browsers lack the module), noservice / oldlibc /
    /// nolib / noload (the module does not start), noreader / nocard (nothing to read yet), reinsert (the app sees the card, the module does not), ok.
    public static string NextStep(Diagnosis d, int readers, bool cardInApp)
    {
        if (d.Kind != "checked") return d.Kind;
        if (d.Missing.Count > 0) return "connect";
        if (!d.Loaded) return (d.Why is "noservice" or "oldlibc" or "nolib") ? d.Why : "noload";
        if (d.Token.Length > 0) return "ok";
        if (d.Slots == 0) return readers == 0 ? "noreader" : "reinsert";
        return cardInApp ? "reinsert" : "nocard";
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
                    else if (error == null) { error = ao.Trim(); why = WhyFailed(ao); }          // the first failure explains the result: its text and its reason belong together
                }
            }
            catch (Exception ex) { error ??= ex.Message; }
            if (good) { if (!done.Contains(t.Label)) done.Add(t.Label); }
            else failed = true;
        }
        if (done.Count == 0) return new Result(why ?? "failed", new(), error ?? "", sandboxed, why);
        return new Result(failed ? "partial" : "done", done, failed ? error ?? "" : "", sandboxed, why, changed);
    }
}
