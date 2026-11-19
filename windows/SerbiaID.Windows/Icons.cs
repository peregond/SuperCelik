using System.Windows;
using System.Windows.Media;

namespace SerbiaID;

/// The button icons are glyphs of "Segoe MDL2 Assets" / "Segoe Fluent Icons" (Windows 10 and newer). Windows XP and 7 do
/// not have them: there the few icons that matter are replaced by plain characters, the rest are dropped (the buttons
/// carry text anyway) — see windows/SerbiaID.Windows.Legacy.
internal static class Icons
{
    public static readonly FontFamily Font = new FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets");

    public static readonly bool Available = Detect();

    private static bool Detect()
    {
#if LEGACY
        try
        {
            foreach (var f in Fonts.SystemFontFamilies)
                foreach (var n in f.FamilyNames.Values)
                    if (n == "Segoe MDL2 Assets" || n == "Segoe Fluent Icons") return true;
        }
        catch { }
        return false;
#else
        return true;
#endif
    }

    /// A character that every Windows has (Arial / Tahoma) for the icons that carry meaning; "" = no icon.
    public static string Fallback(string glyph)
    {
        switch (glyph)
        {
            case "": return "√";   // check mark
            case "": return "×";   // close
            case "": return "▼";   // drop-down arrow
            default: return "";
        }
    }

    /// Called at startup: points the icon resources of App.xaml to what this Windows can show.
    public static void Init()
    {
        if (Available) return;
        Application.Current.Resources["IconFont"] = new FontFamily("Arial");
        Application.Current.Resources["ChevronGlyph"] = Fallback("");
    }
}
