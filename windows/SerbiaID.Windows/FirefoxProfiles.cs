using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;

namespace SerbiaID;

/// A Firefox profile folder found on disk.
internal sealed class FirefoxProfile
{
    public string Dir;          // full path of the profile folder
    public string Name;         // folder name (what Firefox calls it in about:profiles, plus a random prefix), for messages
    public string Kind = "";    // "" = a regular install; "Snap" / "Flatpak" = sandboxed Firefox, whose files are here but which cannot use anything outside its sandbox
    public int Major;           // Firefox version this profile was last started with (0 = unknown)
}

/// What Firefox does with the certificates of the operating system (smart card certificates among them).
internal enum OsCertsState
{
    Ok,          // Firefox takes client certificates from the system store (Windows) / keychain (macOS)
    Disabled,    // switched off in this profile: one preference fixes it
    TooOld,      // this Firefox cannot use system certificates at all
}

/// Finding Firefox profiles and reading / writing their preferences. The folder layout is the same on every system, only the
/// root differs: ~/.mozilla/firefox or ~/.config/mozilla/firefox (Linux), %APPDATA%\Mozilla\Firefox (Windows),
/// ~/Library/Application Support/Firefox (macOS). Shared by the Linux, Windows and Windows XP / 7 builds.
internal static class FirefoxProfiles
{
    /// Since Firefox 90 (Windows and macOS) this is on by default: Firefox offers the certificates that the system holds.
    public const string OsCertsPref = "security.osclientcerts.autoload";
    public const int OsCertsSince = 75;          // the first Firefox that can use them at all (before 90 only with the preference turned on)

    private static bool IsWindows => Path.DirectorySeparatorChar == '\\';

    private static string Key(string path)
    {
        try { path = Path.GetFullPath(path); } catch { }
        path = path.TrimEnd('/', '\\');
        return IsWindows ? path.ToLowerInvariant() : path;
    }

    /// Every profile of the Firefox data folder `root` (the folder that holds profiles.ini): the ones profiles.ini lists, wherever
    /// they live, and the folders that look like a profile next to it (also under Profiles\, where Windows and macOS keep them).
    public static List<FirefoxProfile> Find(string root, string kind = "")
    {
        var list = new List<FirefoxProfile>();
        var seen = new HashSet<string>();
        if (string.IsNullOrEmpty(root) || !Directory.Exists(root)) return list;

        void Add(string dir)
        {
            if (string.IsNullOrEmpty(dir) || !Directory.Exists(dir)) return;
            if (!seen.Add(Key(dir))) return;
            list.Add(new FirefoxProfile { Dir = dir, Name = Path.GetFileName(dir.TrimEnd('/', '\\')), Kind = kind, Major = ReadMajor(dir) });
        }

        try
        {
            var ini = Path.Combine(root, "profiles.ini");
            if (File.Exists(ini))
                foreach (var s in ParseIni(ReadAllTextShared(ini)))
                {
                    if (s.Name.StartsWith("Profile", StringComparison.OrdinalIgnoreCase))
                    {
                        if (!s.Values.TryGetValue("Path", out var p) || p.Length == 0) continue;
                        bool relative = !s.Values.TryGetValue("IsRelative", out var rel) || rel.Trim() != "0";
                        p = p.Replace('/', Path.DirectorySeparatorChar);
                        Add(relative ? Path.Combine(root, p) : p);
                    }
                    else if (s.Name.StartsWith("Install", StringComparison.OrdinalIgnoreCase) && s.Values.TryGetValue("Default", out var d) && d.Length > 0)
                        Add(Path.Combine(root, d.Replace('/', Path.DirectorySeparatorChar)));       // always relative to the data folder
                }
        }
        catch { /* a broken profiles.ini: the folder scan below still finds the profiles */ }

        foreach (var parent in new[] { root, Path.Combine(root, "Profiles") })
        {
            if (!Directory.Exists(parent)) continue;
            string[] dirs;
            try { dirs = Directory.GetDirectories(parent); } catch { continue; }
            Array.Sort(dirs, StringComparer.Ordinal);
            foreach (var dir in dirs)
                if (LooksLikeProfile(dir)) Add(dir);
        }
        return list;
    }

    private static bool LooksLikeProfile(string dir) =>
        File.Exists(Path.Combine(dir, "prefs.js")) || File.Exists(Path.Combine(dir, "cert9.db")) || File.Exists(Path.Combine(dir, "compatibility.ini"));

    // ---- profiles.ini ----

    internal sealed class IniSection
    {
        public string Name;
        public readonly Dictionary<string, string> Values = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
    }

    internal static List<IniSection> ParseIni(string text)
    {
        var sections = new List<IniSection>();
        IniSection cur = null;
        foreach (var raw in SplitLines(text))
        {
            var line = raw.Trim();
            if (line.Length == 0 || line[0] == ';' || line[0] == '#') continue;
            if (line[0] == '[' && line[line.Length - 1] == ']') { cur = new IniSection { Name = line.Substring(1, line.Length - 2) }; sections.Add(cur); continue; }
            int eq = line.IndexOf('=');
            if (cur == null || eq <= 0) continue;
            cur.Values[line.Substring(0, eq).Trim()] = line.Substring(eq + 1).Trim();
        }
        return sections;
    }

    /// The Firefox version this profile was last started with, from compatibility.ini ("LastVersion=147.0_2025…/…"). 0 = unknown.
    public static int ReadMajor(string profileDir)
    {
        try
        {
            var file = Path.Combine(profileDir, "compatibility.ini");
            if (!File.Exists(file)) return 0;
            foreach (var raw in SplitLines(ReadAllTextShared(file)))
            {
                var line = raw.Trim();
                if (!line.StartsWith("LastVersion=", StringComparison.OrdinalIgnoreCase)) continue;
                var v = line.Substring("LastVersion=".Length);
                int end = 0;
                while (end < v.Length && char.IsDigit(v[end])) end++;
                int major;
                return end > 0 && int.TryParse(v.Substring(0, end), NumberStyles.None, CultureInfo.InvariantCulture, out major) ? major : 0;
            }
        }
        catch { }
        return 0;
    }

    // ---- preferences: prefs.js (written by Firefox) and user.js (ours to write; applied at every start, wins over prefs.js) ----

    private static Regex PrefLine(string name) =>
        new Regex(@"^\s*user_pref\(\s*""" + Regex.Escape(name) + @"""\s*,\s*(?<v>[^)]*?)\s*\)\s*;", RegexOptions.CultureInvariant);

    /// The value a boolean preference will have at the next start of Firefox, or null when no file sets it (Firefox then uses its default).
    public static bool? ReadBoolPref(string profileDir, string name)
    {
        var re = PrefLine(name);
        bool? result = null;
        foreach (var file in new[] { "prefs.js", "user.js" })           // later wins: user.js is applied after prefs.js
        {
            try
            {
                var path = Path.Combine(profileDir, file);
                if (!File.Exists(path)) continue;
                foreach (var line in SplitLines(ReadAllTextShared(path)))
                {
                    var m = re.Match(line);
                    if (!m.Success) continue;
                    var v = m.Groups["v"].Value;
                    if (v == "true") result = true;
                    else if (v == "false") result = false;
                    else result = null;                                  // not a boolean: leave it to Firefox
                }
            }
            catch { /* locked or unreadable: treat as not set */ }
        }
        return result;
    }

    /// Writes `user_pref("name", value);` into the profile's user.js (replacing a line that sets it, keeping every other line).
    /// Takes effect when Firefox starts the next time. Returns false when the file could not be written.
    public static bool SetBoolPref(string profileDir, string name, bool value)
    {
        try
        {
            var path = Path.Combine(profileDir, "user.js");
            var text = File.Exists(path) ? ReadAllTextShared(path) : "";
            var nl = text.IndexOf("\r\n", StringComparison.Ordinal) >= 0 ? "\r\n" : text.IndexOf('\n') >= 0 ? "\n" : Environment.NewLine;
            var re = PrefLine(name);
            var wanted = "user_pref(\"" + name + "\", " + (value ? "true" : "false") + ");";
            var lines = new List<string>(SplitLines(text));
            if (lines.Count > 0 && lines[lines.Count - 1].Length == 0) lines.RemoveAt(lines.Count - 1);       // the file's final newline
            bool replaced = false;
            for (int i = 0; i < lines.Count; i++)
            {
                if (!re.IsMatch(lines[i])) continue;
                if (!replaced) { lines[i] = wanted; replaced = true; }
                else lines.RemoveAt(i--);                                // a duplicate of the same preference
            }
            if (!replaced) lines.Add(wanted);
            var result = string.Join(nl, lines.ToArray()) + nl;
            if (result == text) return true;

            var tmp = path + ".supercelik-tmp";
            File.WriteAllText(tmp, result, new UTF8Encoding(false));
            if (File.Exists(path)) File.Replace(tmp, path, null); else File.Move(tmp, path);
            return true;
        }
        catch { return false; }
    }

    // ---- what the system certificates need ----

    /// Whether this profile will offer the certificates of the operating system (Windows and macOS only; Linux needs a PKCS#11 module instead).
    /// "Disabled" means the preference is explicitly off. A profile last used with Firefox 75-89 (where it was off by default) is not flagged:
    /// that is 2021 or older, so it is an abandoned profile and not worth a question.
    public static OsCertsState CheckOsCerts(FirefoxProfile p)
    {
        if (p.Major > 0 && p.Major < OsCertsSince) return OsCertsState.TooOld;
        return ReadBoolPref(p.Dir, OsCertsPref) == false ? OsCertsState.Disabled : OsCertsState.Ok;
    }

    /// Turns the preference on in every profile that needs it. Returns the profiles that were fixed.
    public static List<FirefoxProfile> EnableOsCerts(IEnumerable<FirefoxProfile> profiles)
    {
        var fixedOnes = new List<FirefoxProfile>();
        foreach (var p in profiles)
            if (CheckOsCerts(p) == OsCertsState.Disabled && SetBoolPref(p.Dir, OsCertsPref, true)) fixedOnes.Add(p);
        return fixedOnes;
    }

    // ---- small helpers ----

    private static string[] SplitLines(string text) => text.Replace("\r\n", "\n").Replace('\r', '\n').Split('\n');

    /// Reads a file that Firefox may have open (Windows would refuse a plain File.ReadAllText then).
    private static string ReadAllTextShared(string path)
    {
        using (var fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
        using (var sr = new StreamReader(fs, new UTF8Encoding(false), true))
            return sr.ReadToEnd();
    }
}
