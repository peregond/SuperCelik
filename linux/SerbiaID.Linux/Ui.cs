using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.Primitives;
using Avalonia.Layout;
using Avalonia.Media;
using Avalonia.Media.Imaging;

namespace SerbiaID;

/// What the card reader "feels" (same states as the macOS and Windows apps). Drives which mascot pose is shown.
public enum ReaderMood { NoReader, Waiting, Ready, Busy, Error }

public enum MascotCharacter { Reader, Key }

/// Small helpers for building the UI in code. Colours always come from the theme resources (App.axaml),
/// so a theme switch repaints everything without rebuilding.
internal static class Ui
{
    public static T Res<T>(this T c, AvaloniaProperty p, string key) where T : Control
    {
        c.Bind(p, c.GetResourceObservable(key));
        return c;
    }

    public static Bitmap LoadImage(byte[] jpeg)
    {
        if (jpeg == null || jpeg.Length == 0) return null;
        try { return new Bitmap(new MemoryStream(jpeg)); } catch { return null; }
    }

    public static TextBlock Label(string text, double size = 13, bool bold = false, string fg = "TextBrush", bool wrap = false)
    {
        var t = new TextBlock { Text = text, FontSize = size, FontWeight = bold ? FontWeight.SemiBold : FontWeight.Normal };
        if (wrap) t.TextWrapping = TextWrapping.Wrap;
        return t.Res(TextBlock.ForegroundProperty, fg);
    }

    public static Button Btn(string text, string kind = "secondary")
    {
        var b = new Button { Content = text, Classes = { kind } };
        return b;
    }

    public static Border Card(Control child, Thickness? padding = null)
    {
        var b = new Border { Child = child, Classes = { "card" } };
        if (padding != null) b.Padding = padding.Value;
        return b;
    }

    public static Border Pill(TextBlock label, double vpad = 5)
    {
        label.FontSize = 12; label.FontWeight = FontWeight.SemiBold; label.TextWrapping = TextWrapping.Wrap; label.TextAlignment = TextAlignment.Center;
        return new Border { CornerRadius = new CornerRadius(14), Padding = new Thickness(12, vpad), Child = label, IsVisible = false, HorizontalAlignment = HorizontalAlignment.Center };
    }

    public static void SetPill(Border pill, string text, string fg, string bg)
    {
        var label = (TextBlock)pill.Child;
        label.Text = text;
        label.Res(TextBlock.ForegroundProperty, fg);
        pill.Res(Border.BackgroundProperty, bg);
        pill.IsVisible = true;
    }
}

/// The two cartoon characters, drawn from illustrated poses (Assets/Mascots/<character>-<pose>.png).
public sealed class MascotArt : Border
{
    public MascotCharacter Character { get; }
    private readonly Image _img = new() { Stretch = Stretch.Uniform };
    private ReaderMood _mood = ReaderMood.Waiting;
    private static readonly Dictionary<string, Bitmap> Cache = new();

    public MascotArt(MascotCharacter c, double size)
    {
        Character = c; Width = size; Height = size; HorizontalAlignment = HorizontalAlignment.Center;
        Child = _img;
        Show();
    }

    private static string[] PosesFor(MascotCharacter c, ReaderMood m) => (c, m) switch
    {
        (_, ReaderMood.NoReader) => new[] { "sad", "worry" },
        (_, ReaderMood.Waiting) => new[] { "present" },
        (MascotCharacter.Reader, ReaderMood.Ready or ReaderMood.Busy) => new[] { "card" },
        (MascotCharacter.Key, ReaderMood.Ready) => new[] { "thumbs" },
        (MascotCharacter.Key, ReaderMood.Busy) => new[] { "look" },
        _ => new[] { "worry", "sad" },
    };

    private static Bitmap Load(MascotCharacter c, string pose)
    {
        var name = $"{c.ToString().ToLowerInvariant()}-{pose}";
        if (Cache.TryGetValue(name, out var hit)) return hit;
        Bitmap bmp = null;
        try { bmp = new Bitmap(Avalonia.Platform.AssetLoader.Open(new Uri($"avares://SuperCelik/Assets/Mascots/{name}.png"))); } catch { }
        Cache[name] = bmp;
        return bmp;
    }

    public void Set(ReaderMood mood) { _mood = mood; Show(); }

    private void Show()
    {
        foreach (var pose in PosesFor(Character, _mood))
            if (Load(Character, pose) is { } bmp) { _img.Source = bmp; return; }
        _img.Source = Load(Character, "present");
    }
}
