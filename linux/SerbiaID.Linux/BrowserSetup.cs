using System.Diagnostics;

namespace SerbiaID;

/// Browser sign-in with the card certificate on Linux: the browser needs a PKCS#11 module (srb-id-pkcs11, public domain,
/// shipped inside the app in <app folder>/pkcs11) in its NSS database. This finds Firefox profiles and the Chrome / Chromium
/// database and registers the module with `modutil` (package libnss3-tools). It only runs when the user asks for it.
public static class BrowserSetup
{
    public const string ModuleName = "Srb Id PKCS11";
    public static string ModulePath => Path.Combine(AppContext.BaseDirectory, "pkcs11", "libsrb-id-pkcs11.so");
    public static bool HasModule => File.Exists(ModulePath);

    public sealed record Target(string Label, string Dir);
    public sealed record Result(string Kind, List<string> Names, string Detail);      // Kind: nomodule / notool / none / done / failed

    private static string Home => Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);

    /// NSS databases of the installed browsers: every Firefox profile, and the shared Chrome / Chromium database.
    public static List<Target> FindTargets(bool createChromeDb = false)
    {
        var list = new List<Target>();
        foreach (var root in new[] { Path.Combine(Home, ".mozilla", "firefox"), Path.Combine(Home, "snap", "firefox", "common", ".mozilla", "firefox") })
        {
            if (!Directory.Exists(root)) continue;
            foreach (var dir in Directory.GetDirectories(root))
                if (File.Exists(Path.Combine(dir, "cert9.db")) || File.Exists(Path.Combine(dir, "prefs.js")))
                    list.Add(new Target("Firefox", dir));
        }
        var chromeDb = new[] { Path.Combine(Home, ".pki", "nssdb"), Path.Combine(Home, ".local", "share", "pki", "nssdb") }
            .FirstOrDefault(d => File.Exists(Path.Combine(d, "cert9.db")));
        if (chromeDb != null) list.Add(new Target("Chrome / Chromium", chromeDb));
        else if (createChromeDb && ChromiumInstalled()) list.Add(new Target("Chrome / Chromium", Path.Combine(Home, ".pki", "nssdb")));
        return list;
    }

    private static bool ChromiumInstalled() =>
        new[] { "google-chrome", "google-chrome-stable", "chromium", "chromium-browser", "microsoft-edge", "brave-browser" }.Any(n => Which(n) != null);

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
        var targets = FindTargets(createChromeDb: true);
        if (targets.Count == 0) return new Result("none", new(), ModulePath);

        var done = new List<string>(); string error = null;
        foreach (var t in targets)
        {
            try
            {
                var db = "sql:" + t.Dir;
                if (!File.Exists(Path.Combine(t.Dir, "cert9.db")))
                {
                    Directory.CreateDirectory(t.Dir);
                    var certutil = Which("certutil");
                    if (certutil == null) { error = "certutil"; continue; }
                    var (c0, o0) = await Run(certutil, "-N", "-d", db, "--empty-password");
                    if (c0 != 0) { error = o0.Trim(); continue; }
                }
                var (lc, listing) = await Run(modutil, "-dbdir", db, "-list");
                if (lc == 0 && listing.Contains(ModuleName))
                {
                    if (listing.Contains(ModulePath)) { if (!done.Contains(t.Label)) done.Add(t.Label); continue; }
                    await Run(modutil, "-dbdir", db, "-delete", ModuleName, "-force");        // the app moved: replace the old entry
                }
                var (ac, ao) = await Run(modutil, "-dbdir", db, "-add", ModuleName, "-libfile", ModulePath, "-force");
                if (ac == 0) { if (!done.Contains(t.Label)) done.Add(t.Label); }
                else error = ao.Trim();
            }
            catch (Exception ex) { error = ex.Message; }
        }
        return done.Count > 0 ? new Result("done", done, "") : new Result("failed", new(), error ?? "");
    }
}
