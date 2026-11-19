using System.Diagnostics;
using System.Security.Cryptography;
using System.Security.Principal;
using Microsoft.Win32;

namespace SerbiaID;

/// Browser login on Windows: Chrome and Edge take client certificates from the Windows certificate store, and a smart
/// card gets there through a card minidriver. Super Čelik ships its own (SuperCelikMD.dll, windows/minidriver) and
/// registers it for the card's ATR. Registering needs administrator rights (HKLM and System32), so it is done by this
/// same exe started elevated (`--register-driver <ATR hex>`), once per card type, after a question in the app.
internal static class DriverSetup
{
    private const string SmartCards = @"SOFTWARE\Microsoft\Cryptography\Calais\SmartCards";
    private const string KeyPrefix = "SuperCelik-";
    private const string Dll = "SuperCelikMD.dll";

    /// One copy of the driver: the DLL shipped with the app, where Windows looks for it, and the registry view that
    /// lists it. A 64-bit Windows has two (32-bit programs read the 32-bit view and SysWOW64, 64-bit ones the native
    /// ones); only the 32-bit build for Windows XP / 7 (an x86 program that may run on 64-bit Windows) needs both.
    private sealed class Target
    {
        public string Bundled, Installed;
        public RegistryView View;
        public RegistryKey Open() => RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, View);
    }

    private static List<Target> Targets()
    {
        string baseDir = AppDomain.CurrentDomain.BaseDirectory;
#if LEGACY
        if (Environment.Is64BitOperatingSystem)
        {
            string win = Environment.GetFolderPath(Environment.SpecialFolder.Windows);
            return new List<Target>
            {
                // x64 driver for 64-bit browsers: native System32, reached from this 32-bit process as Sysnative
                new Target { View = RegistryView.Registry64, Bundled = Path.Combine(baseDir, "SuperCelikMD64.dll"), Installed = Path.Combine(win, "Sysnative", Dll) },
                new Target { View = RegistryView.Registry32, Bundled = Path.Combine(baseDir, Dll), Installed = Path.Combine(Environment.SystemDirectory, Dll) },
            };
        }
        return new List<Target> { new Target { View = RegistryView.Registry32, Bundled = Path.Combine(baseDir, Dll), Installed = Path.Combine(Environment.SystemDirectory, Dll) } };
#else
        return new List<Target> { new Target { View = RegistryView.Default, Bundled = Path.Combine(baseDir, Dll), Installed = Path.Combine(Environment.SystemDirectory, Dll) } };
#endif
    }

    /// This build carries the driver (the portable dev build does not), and Windows can use it
    /// (card minidrivers need Windows Vista or newer; on XP the rest of the app works without it).
    public static bool Available
    {
        get
        {
#if LEGACY
            if (Environment.OSVersion.Version.Major < 6) return false;
#endif
            return Targets().All(t => File.Exists(t.Bundled));
        }
    }

    public static string Hex(byte[] b) => Compat.Hex(b);

    /// Registered subkeys (name, ours?) whose ATR and mask match this card.
    private static IEnumerable<(string Name, bool Ours)> Matching(byte[] atr, Target t)
    {
        using var hklm = t.Open();
        using var all = hklm.OpenSubKey(SmartCards);
        if (all == null) yield break;
        foreach (var name in all.GetSubKeyNames())
        {
            using var k = all.OpenSubKey(name);
            if (k?.GetValue("ATR") is not byte[] a || k.GetValue("80000001") == null) continue;
            var mask = k.GetValue("ATRMask") as byte[] ?? Enumerable.Repeat((byte)0xFF, a.Length).ToArray();
            if (a.Length != atr.Length || mask.Length != a.Length) continue;
            bool same = true;
            for (int i = 0; i < a.Length && same; i++) same = (atr[i] & mask[i]) == (a[i] & mask[i]);
            if (same) yield return (name, name.StartsWith(KeyPrefix, StringComparison.OrdinalIgnoreCase));
        }
    }

    /// Super Čelik's driver is registered for this ATR and the installed DLL is the one shipped with this version
    /// (in every copy the system keeps).
    public static bool IsRegistered(byte[] atr)
    {
        try { return Targets().All(t => Matching(atr, t).Any(m => m.Ours) && SameFile(t.Bundled, t.Installed)); }
        catch { return false; }
    }

    /// Another driver (the official MUP / NetSeT one) is already registered for this ATR: two drivers for one card
    /// would fight over it, so Super Čelik leaves such a card alone.
    public static bool HandledByOtherDriver(byte[] atr)
    {
        try { return Targets().Any(t => Matching(atr, t).Any(m => !m.Ours)); }
        catch { return false; }
    }

    /// Any card type registered (Settings status).
    public static bool AnyRegistered()
    {
        try
        {
            return Targets().All(t =>
            {
                using var hklm = t.Open();
                using var k = hklm.OpenSubKey(SmartCards);
                return k != null && k.GetSubKeyNames().Any(n => n.StartsWith(KeyPrefix, StringComparison.OrdinalIgnoreCase)) && File.Exists(t.Installed);
            });
        }
        catch { return false; }
    }

    private static bool SameFile(string a, string b)
    {
        try
        {
            if (!File.Exists(a) || !File.Exists(b)) return false;
            using var sa = File.OpenRead(a); using var sb = File.OpenRead(b);
            return Compat.Sha256(sa).SequenceEqual(Compat.Sha256(sb));
        }
        catch { return false; }
    }

    public static bool IsAdmin()
    {
        using var id = WindowsIdentity.GetCurrent();
        return new WindowsPrincipal(id).IsInRole(WindowsBuiltInRole.Administrator);
    }

    /// Starts this exe elevated (UAC prompt) and waits; false when declined or failed.
    public static bool RunElevated(string args)
    {
        try
        {
            var p = Process.Start(new ProcessStartInfo(Process.GetCurrentProcess().MainModule.FileName, args) { UseShellExecute = true, Verb = "runas", WindowStyle = ProcessWindowStyle.Hidden });
            if (p == null) return false;
            p.WaitForExit();
            return p.ExitCode == 0;
        }
        catch { return false; }
    }

    // ---- the elevated side (exit code 0 = done) ----

    public static int Register(string atrHex)
    {
        try
        {
            if (!Available) return 2;
            byte[] atr = Compat.FromHex(atrHex);
            if (atr.Length < 2 || atr.Length > 33) return 3;
            foreach (var t in Targets())
            {
                if (!SameFile(t.Bundled, t.Installed))
                {
                    try { File.Copy(t.Bundled, t.Installed, true); }
                    catch (IOException) when (File.Exists(t.Installed)) { /* in use by a running browser: the old copy stays until it is closed */ }
                }
                using var hklm = t.Open();
                using var k = hklm.CreateSubKey(SmartCards + "\\" + KeyPrefix + atrHex);
                k.SetValue("ATR", atr, RegistryValueKind.Binary);
                k.SetValue("ATRMask", Enumerable.Repeat((byte)0xFF, atr.Length).ToArray(), RegistryValueKind.Binary);
                k.SetValue("Crypto Provider", "Microsoft Base Smart Card Crypto Provider", RegistryValueKind.String);
                k.SetValue("Smart Card Key Storage Provider", "Microsoft Smart Card Key Storage Provider", RegistryValueKind.String);
                k.SetValue("80000001", Dll, RegistryValueKind.String);
            }
            return 0;
        }
        catch { return 1; }
    }

    /// Registers the driver for every card with the CardEdge applet that is in a reader now (right after the install).
    /// Never fails: no reader or no card simply registers nothing.
    public static int RegisterAuto()
    {
        try
        {
            using var pc = new PcscService();
            foreach (var reader in pc.ListReaders())
            {
                var (atr, hasToken) = SerbianCard.ProbeToken(pc, reader);
                if (hasToken && atr != null && !IsRegistered(atr) && !HandledByOtherDriver(atr)) Register(Hex(atr));
            }
        }
        catch { }
        return 0;
    }

    public static int Unregister()
    {
        try
        {
            foreach (var t in Targets())
            {
                using (var hklm = t.Open())
                using (var k = hklm.OpenSubKey(SmartCards, true))
                    if (k != null)
                        foreach (var n in k.GetSubKeyNames().Where(n => n.StartsWith(KeyPrefix, StringComparison.OrdinalIgnoreCase)).ToList())
                            k.DeleteSubKeyTree(n, false);
                try { File.Delete(t.Installed); } catch (IOException) { /* in use: removed with the next restart of the browser and re-run */ }
            }
            return 0;
        }
        catch { return 1; }
    }
}
