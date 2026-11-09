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
    public bool AutoRead { get; set; } = false;      // read the card as soon as it is inserted
    public bool PrintJmbg { get; set; } = true;      // include the personal number on printouts / PDF
    public int AutoHideMinutes { get; set; } = 3;    // clear data after N idle minutes (0 = never)
    public double WindowWidth { get; set; }
    public double WindowHeight { get; set; }
    public double WindowLeft { get; set; } = double.NaN;
    public double WindowTop { get; set; } = double.NaN;
    public int Tab { get; set; }

    private static string PathFile => System.IO.Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "SuperCelik", "settings.json");

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
            Set("AccentBrush", "#2F6DB8"); Set("AccentHoverBrush", "#3C7FCF"); Set("AccentTextBrush", "#8DB8F0"); Set("RedBrush", "#E0525A");
            Set("OkBrush", "#5FD08B"); Set("OkBgBrush", "#1B3A2A"); Set("WarnBrush", "#F2B45A"); Set("WarnBgBrush", "#43331A");
            Set("BadBrush", "#FF7A80"); Set("BadBgBrush", "#472226");
        }
        else
        {
            Set("BgBrush", "#F3F5F9"); Set("SurfaceBrush", "#FFFFFF"); Set("TextBrush", "#1B2430"); Set("MutedBrush", "#6B7686");
            Set("LineBrush", "#E3E7EE"); Set("ControlLineBrush", "#D5DAE3"); Set("HoverBrush", "#EAEEF5"); Set("PlaceholderBrush", "#EEF1F7");
            Set("DisabledBrush", "#B8C2D1"); Set("BannerBrush", "#FFF4CE");
            Set("AccentBrush", "#0C4076"); Set("AccentHoverBrush", "#0A3560"); Set("AccentTextBrush", "#0C4076"); Set("RedBrush", "#C6363C");
            Set("OkBrush", "#1E8E4E"); Set("OkBgBrush", "#E6F4EC"); Set("WarnBrush", "#B26B00"); Set("WarnBgBrush", "#FFF1DB");
            Set("BadBrush", "#C6363C"); Set("BadBgBrush", "#FBE7E8");
        }
    }
}
