using System.Text.Json;
using System.Windows;
using System.Windows.Media;
using Microsoft.Win32;

namespace SerbiaID;

/// User preferences, stored as JSON in %APPDATA%\SuperCelik\settings.json.
public sealed class AppSettings
{
    public string Lang { get; set; }                 // ru / en / sr (null = system)
    public string Theme { get; set; } = "system";    // system / light / dark
    public bool AutoUpdate { get; set; } = true;
    public bool MaskSensitive { get; set; } = true;  // hide JMBG / address / document number behind •••
    public bool AutoRead { get; set; } = true;       // read the card as soon as it is inserted
    public string DriverDeclined { get; set; } = "";   // ATRs (hex;) for which the user said "no" to the browser-login driver
    public int Version { get; set; }                 // settings schema; 2 = auto-read is on by default
    public bool PrintJmbg { get; set; } = true;      // include the personal number on printouts / PDF
    public int AutoHideMinutes { get; set; } = 3;    // clear data after N idle minutes (0 = never)
    public double WindowWidth { get; set; }
    public double WindowHeight { get; set; }
    public double WindowLeft { get; set; } = double.NaN;
    public double WindowTop { get; set; } = double.NaN;
    public int Tab { get; set; }

    private static string PathFile => System.IO.Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "SuperCelik", "settings.json");

    /// Language chosen in the installer (HKCU\Software\SuperCelik\Lang = russian / english / serbian), used on first run.
    public static string InstallerLang()
    {
        try
        {
            return (Registry.GetValue(@"HKEY_CURRENT_USER\Software\SuperCelik", "Lang", null) as string) switch
            {
                "russian" => "ru", "serbian" => "sr", "english" => "en", _ => null,
            };
        }
        catch { return null; }
    }

    public static AppSettings Load()
    {
        try
        {
            if (File.Exists(PathFile))
            {
                var s = JsonSerializer.Deserialize<AppSettings>(File.ReadAllText(PathFile)) ?? new();
                // the old default was "off", and it sits in every saved file: switch it on once, like on macOS
                if (s.Version < 2) { s.AutoRead = true; s.Version = 2; }
                return s;
            }
        }
        catch { }
        return new() { Version = 2 };
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

/// Light / dark palettes. Replaces the brush resources in App.xaml (all references are DynamicResource).
public static class Theme
{
    public static bool SystemIsDark()
    {
        try { return (int)(Registry.GetValue(@"HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize", "AppsUseLightTheme", 1) ?? 1) == 0; }
        catch { return false; }
    }

    private static void Set(string key, string color) =>
        Application.Current.Resources[key] = new SolidColorBrush((Color)ColorConverter.ConvertFromString(color));

    public static void Apply(string mode)
    {
        bool dark = mode == "dark" || (mode == "system" && SystemIsDark());
        if (dark)
        {
            Set("BgBrush", "#0F131A"); Set("SurfaceBrush", "#1A212C"); Set("TextBrush", "#E8ECF2"); Set("MutedBrush", "#9AA5B5");
            Set("LineBrush", "#2A3341"); Set("ControlLineBrush", "#364154"); Set("HoverBrush", "#263041"); Set("PlaceholderBrush", "#232C3A");
            Set("DisabledBrush", "#3A4557"); Set("BannerBrush", "#4A3F15");
            Set("AccentBrush", "#D23F46"); Set("AccentHoverBrush", "#E0525A"); Set("AccentTextBrush", "#FF8A90"); Set("RedBrush", "#E0525A");
            Set("OkBrush", "#5FD08B"); Set("OkBgBrush", "#1B3A2A"); Set("WarnBrush", "#F2B45A"); Set("WarnBgBrush", "#43331A");
            Set("BadBrush", "#FF7A80"); Set("BadBgBrush", "#472226");
        }
        else
        {
            Set("BgBrush", "#F3F5F9"); Set("SurfaceBrush", "#FFFFFF"); Set("TextBrush", "#1B2430"); Set("MutedBrush", "#6B7686");
            Set("LineBrush", "#E3E7EE"); Set("ControlLineBrush", "#D5DAE3"); Set("HoverBrush", "#EAEEF5"); Set("PlaceholderBrush", "#EEF1F7");
            Set("DisabledBrush", "#B8C2D1"); Set("BannerBrush", "#FFF4CE");
            Set("AccentBrush", "#C6363C"); Set("AccentHoverBrush", "#A92D33"); Set("AccentTextBrush", "#C6363C"); Set("RedBrush", "#C6363C");
            Set("OkBrush", "#1E8E4E"); Set("OkBgBrush", "#E6F4EC"); Set("WarnBrush", "#B26B00"); Set("WarnBgBrush", "#FFF1DB");
            Set("BadBrush", "#C6363C"); Set("BadBgBrush", "#FBE7E8");
        }
    }
}
