using System.Diagnostics;
using System.Security.Cryptography;
using System.Security.Principal;
using Microsoft.Win32;

namespace SerbiaID;

/// Browser login on Windows: Chrome and Edge take client certificates from the Windows certificate store, and a smart
/// card gets there through a card minidriver. Super Celik ships its own (SuperCelikMD.dll, windows/minidriver) and
/// registers it for the card's ATR. Registering needs administrator rights (HKLM and System32), so it is done by this
/// same exe started elevated (`--register-driver <ATR hex>`), once per card type, after a question in the app.
internal static class DriverSetup
{
    private const string SmartCards = @"SOFTWARE\Microsoft\Cryptography\Calais\SmartCards";
    private const string KeyPrefix = "SuperCelik-";
    private const string Dll = "SuperCelikMD.dll";

    private static string Bundled => Path.Combine(AppContext.BaseDirectory, Dll);
    private static string Installed => Path.Combine(Environment.SystemDirectory, Dll);

    /// This build carries the driver (the portable dev build does not).
    public static bool Available => File.Exists(Bundled);

    public static string Hex(byte[] b) => Convert.ToHexString(b);

    /// Registered subkeys (name, ours?) whose ATR and mask match this card.
    private static IEnumerable<(string Name, bool Ours)> Matching(byte[] atr)
    {
        using var all = Registry.LocalMachine.OpenSubKey(SmartCards);
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

    /// Super Celik's driver is registered for this ATR and the installed DLL is the one shipped with this version.
    public static bool IsRegistered(byte[] atr)
    {
        try { return Matching(atr).Any(m => m.Ours) && SameFile(Bundled, Installed); }
        catch { return false; }
    }

    /// Another driver (the official MUP / NetSeT one) is already registered for this ATR: two drivers for one card
    /// would fight over it, so Super Celik leaves such a card alone.
    public static bool HandledByOtherDriver(byte[] atr)
    {
        try { return Matching(atr).Any(m => !m.Ours); }
        catch { return false; }
    }

    /// Any card type registered (Settings status).
    public static bool AnyRegistered()
    {
        try
        {
            using var k = Registry.LocalMachine.OpenSubKey(SmartCards);
            return k != null && k.GetSubKeyNames().Any(n => n.StartsWith(KeyPrefix, StringComparison.OrdinalIgnoreCase)) && File.Exists(Installed);
        }
        catch { return false; }
    }

    private static bool SameFile(string a, string b)
    {
        try
        {
            if (!File.Exists(a) || !File.Exists(b)) return false;
            using var sa = File.OpenRead(a); using var sb = File.OpenRead(b);
            return SHA256.HashData(sa).AsSpan().SequenceEqual(SHA256.HashData(sb));
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
            var p = Process.Start(new ProcessStartInfo(Environment.ProcessPath!, args) { UseShellExecute = true, Verb = "runas", WindowStyle = ProcessWindowStyle.Hidden });
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
            byte[] atr = Convert.FromHexString(atrHex);
            if (atr.Length < 2 || atr.Length > 33) return 3;
            if (!SameFile(Bundled, Installed))
            {
                try { File.Copy(Bundled, Installed, true); }
                catch (IOException) when (File.Exists(Installed)) { /* in use by a running browser: the old copy stays until it is closed */ }
            }
            using var k = Registry.LocalMachine.CreateSubKey(SmartCards + "\\" + KeyPrefix + atrHex);
            k.SetValue("ATR", atr, RegistryValueKind.Binary);
            k.SetValue("ATRMask", Enumerable.Repeat((byte)0xFF, atr.Length).ToArray(), RegistryValueKind.Binary);
            k.SetValue("Crypto Provider", "Microsoft Base Smart Card Crypto Provider", RegistryValueKind.String);
            k.SetValue("Smart Card Key Storage Provider", "Microsoft Smart Card Key Storage Provider", RegistryValueKind.String);
            k.SetValue("80000001", Dll, RegistryValueKind.String);
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
            using (var k = Registry.LocalMachine.OpenSubKey(SmartCards, true))
                if (k != null)
                    foreach (var n in k.GetSubKeyNames().Where(n => n.StartsWith(KeyPrefix, StringComparison.OrdinalIgnoreCase)).ToList())
                        k.DeleteSubKeyTree(n, false);
            try { File.Delete(Installed); } catch (IOException) { /* in use: removed with the next restart of the browser and re-run */ }
            return 0;
        }
        catch { return 1; }
    }
}
