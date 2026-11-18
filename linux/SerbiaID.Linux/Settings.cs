using System.Text.Json;

namespace SerbiaID;

/// User preferences, stored as JSON in ~/.config/SuperCelik/settings.json (XDG_CONFIG_HOME is respected).
public sealed class AppSettings
{
    public string Lang { get; set; }                 // ru / en / sr / srCyrl (null = system)
    public string Theme { get; set; } = "system";    // system / light / dark
    public bool AutoUpdate { get; set; } = true;     // look for a newer release on start (only tells, never installs)
    public bool MaskSensitive { get; set; } = true;  // hide JMBG / address / document number behind •••
    public bool AutoRead { get; set; } = true;       // read the card as soon as it is inserted
    public bool PrintJmbg { get; set; } = true;      // include the personal number on printouts / PDF
    public int AutoHideMinutes { get; set; } = 3;    // clear data after N idle minutes (0 = never)
    public double WindowWidth { get; set; }
    public double WindowHeight { get; set; }
    public int Tab { get; set; }

    private static string PathFile
    {
        get
        {
            var xdg = Environment.GetEnvironmentVariable("XDG_CONFIG_HOME");
            var dir = !string.IsNullOrEmpty(xdg) ? xdg
                : System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".config");
            return System.IO.Path.Combine(dir, "SuperCelik", "settings.json");
        }
    }

    public static AppSettings Load()
    {
        try { if (File.Exists(PathFile)) return JsonSerializer.Deserialize<AppSettings>(File.ReadAllText(PathFile)) ?? new(); }
        catch { }
        return new();
    }

    public void Save()
    {
        try
        {
            Directory.CreateDirectory(System.IO.Path.GetDirectoryName(PathFile)!);
            File.WriteAllText(PathFile, JsonSerializer.Serialize(this, new JsonSerializerOptions { WriteIndented = true }));
        }
        catch { }
    }
}
