using System.Windows;
using System.Windows.Media;

namespace SerbiaID;

/// The button icons are glyphs of "Segoe MDL2 Assets" / "Segoe Fluent Icons" (Windows 10 and newer). Windows XP and 7 do
/// not have them, so the build for those (windows/SerbiaID.Windows.Legacy) carries a small subset of the open
/// "Fluent System Icons" font (MIT) and maps each icon to it; likewise Open Sans (OFL) replaces Segoe UI on Windows XP.
internal static class Icons
{
    public static readonly bool Available = Detect();   // the system icon font is there

    public static readonly FontFamily Font = Available
        ? new FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets")
        : Embedded("FluentSystemIcons-Regular");

    private static bool Detect()
    {
#if LEGACY
        return HasFont("Segoe MDL2 Assets") || HasFont("Segoe Fluent Icons");
#else
        return true;
#endif
    }

#if LEGACY
    private static bool HasFont(string family)
    {
        try
        {
            foreach (var f in Fonts.SystemFontFamilies)
                foreach (var n in f.FamilyNames.Values)
                    if (n == family) return true;
        }
        catch { }
        return false;
    }

    private static FontFamily Embedded(string family) =>
        new FontFamily(new Uri("pack://application:,,,/"), "./Fonts/#" + family);

    // Segoe MDL2 glyph -> Fluent System Icons glyph (the same pictogram)
    private static readonly System.Collections.Generic.Dictionary<string, string> Map_ = new System.Collections.Generic.Dictionary<string, string>
    {
        { "\uE72C", "\uF190" }, // refresh
        { "\uE77B", "\uF5BD" }, // read card (person)
        { "\uE749", "\uF62A" }, // print
        { "\uE74E", "\uF67F" }, // save
        { "\uE73E", "\uF294" }, // check
        { "\uE712", "\uE824" }, // more
        { "\uE192", "\uF4B6" }, // token (key)
        { "\uE72E", "\uE78F" }, // lock
        { "\uE785", "\uE795" }, // unlock
        { "\uE70F", "\uF6DC" }, // sign
        { "\uE895", "\uF190" }, // check for updates
        { "\uE896", "\uF150" }, // download
        { "\uE711", "\uF369" }, // close
        { "\uED1A", "\uE5F5" }, // hide
        { "\uE7B3", "\uE5F2" }, // show
        { "\uE8C8", "\uF32B" }, // copy
        { "\uE91B", "\uF488" }, // photo
        { "\uE943", "\uF2EF" }, // code (JSON)
        { "\uE70D", "\uF2A3" }, // chevron down
    };

    public static string Map(string glyph)
    {
        if (Available) return glyph;
        string r;
        return Map_.TryGetValue(glyph, out r) ? r : "";
    }

    /// Open Sans, embedded, for Windows without Segoe UI (XP).
    private static FontFamily UiFont() => HasFont("Segoe UI")
        ? new FontFamily("Segoe UI, Tahoma, Arial") : Embedded("Open Sans");
#else
    private static FontFamily Embedded(string family) => new FontFamily(family);

    public static string Map(string glyph) => glyph;

    private static FontFamily UiFont() => new FontFamily("Segoe UI, Tahoma, Arial");
#endif

    /// Called at startup: points the font and icon resources of App.xaml to what this Windows can show.
    public static void Init()
    {
        Application.Current.Resources["UiFont"] = UiFont();
        if (Available) return;
        Application.Current.Resources["IconFont"] = Font;
        Application.Current.Resources["ChevronGlyph"] = Map("\uE70D");
    }
}
