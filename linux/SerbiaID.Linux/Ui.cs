using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.Primitives;
using Avalonia.Controls.Shapes;
using Avalonia.Data;
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

    /// A line icon (Icons.Paths, drawn on a 24x24 grid) in the colour of the button it sits in.
    public static Control Icon(string name, double size = 16)
    {
        var path = new Avalonia.Controls.Shapes.Path
        {
            Data = Geometry.Parse(Icons.Paths[name]), StrokeThickness = 2, StrokeLineCap = PenLineCap.Round, StrokeJoin = PenLineJoin.Round, Fill = null,
        };
        path.Bind(Shape.StrokeProperty, new Binding("Foreground") { RelativeSource = new RelativeSource(RelativeSourceMode.FindAncestor) { AncestorType = typeof(Button) } });
        return new Viewbox { Width = size, Height = size, VerticalAlignment = VerticalAlignment.Center, Child = new Canvas { Width = 24, Height = 24, Children = { path } } };
    }

    /// A round tick (green) or cross (red) from the theme colours, for a list of checks.
    public static Control Mark(bool ok, double size = 16)
    {
        var path = new Avalonia.Controls.Shapes.Path
        {
            Data = Geometry.Parse(Icons.Paths[ok ? "circle-check" : "circle-x"]), StrokeThickness = 2, StrokeLineCap = PenLineCap.Round, StrokeJoin = PenLineJoin.Round, Fill = null,
        };
        path.Res(Shape.StrokeProperty, ok ? "OkBrush" : "BadBrush");
        return new Viewbox { Width = size, Height = size, VerticalAlignment = VerticalAlignment.Top, Child = new Canvas { Width = 24, Height = 24, Children = { path } } };
    }

    /// Button content: icon + text (text = null: icon only).
    public static void SetBtn(Button b, string icon, string text)
    {
        var sp = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8, HorizontalAlignment = HorizontalAlignment.Center };
        sp.Children.Add(Icon(icon));
        if (text != null) sp.Children.Add(new TextBlock { Text = text, VerticalAlignment = VerticalAlignment.Center });
        b.Content = sp;
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

/// The two cartoon characters, drawn from illustrated poses (Assets/Mascots/<character>-<pose>.png) and animated with cheap
/// transforms only (same motion as on Windows and the Mac): a slow breathing sway (faster while reading), a hop when a card
/// arrives, a shake on errors and a small pop when the pose changes. Nothing moves while the window is in the background
/// or the character is not on screen; --demo --shot renders a still picture.
public sealed class MascotArt : Border
{
    public MascotCharacter Character { get; }
    private readonly Image _img = new() { Stretch = Stretch.Uniform, RenderTransformOrigin = new RelativePoint(0.5, 1, RelativeUnit.Relative) };
    private readonly RotateTransform _sway = new();
    private readonly ScaleTransform _scale = new(1, 1);
    private readonly TranslateTransform _move = new();
    private ReaderMood _mood = ReaderMood.Waiting;
    private string _shown;
    private static readonly Dictionary<string, Bitmap> Cache = new();

    private readonly System.Diagnostics.Stopwatch _clock = System.Diagnostics.Stopwatch.StartNew();
    private readonly Avalonia.Threading.DispatcherTimer _timer = new() { Interval = TimeSpan.FromMilliseconds(33) };
    private double _hopStart = -1, _shakeStart = -1, _popStart = -1;

    public MascotArt(MascotCharacter c, double size)
    {
        Character = c; Width = size; Height = size; HorizontalAlignment = HorizontalAlignment.Center;
        _img.RenderTransform = new TransformGroup { Children = { _scale, _sway, _move } };
        Child = _img;
        Show(false);
        _timer.Tick += (_, _) => Tick();
        AttachedToVisualTree += (_, _) => { if (!Program.Opts.Demo || Program.Opts.Shot == null) _timer.Start(); };
        DetachedFromVisualTree += (_, _) => { _timer.Stop(); Reset(); };
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

    public void Set(ReaderMood mood)
    {
        if (mood == _mood) return;
        _mood = mood;
        Show(true);
        var now = _clock.Elapsed.TotalSeconds;
        if (mood == ReaderMood.Ready) _hopStart = now;
        else if (mood == ReaderMood.Error) _shakeStart = now;
    }

    private void Show(bool animated)
    {
        string wanted = null; Bitmap bmp = null;
        foreach (var pose in PosesFor(Character, _mood))
            if ((bmp = Load(Character, pose)) != null) { wanted = pose; break; }
        if (bmp == null) { bmp = Load(Character, "present"); wanted = "present"; }
        if (bmp == null || wanted == _shown) return;
        _shown = wanted;
        _img.Source = bmp;
        if (animated) _popStart = _clock.Elapsed.TotalSeconds;
    }

    private void Reset() { _sway.Angle = 0; _scale.ScaleX = _scale.ScaleY = 1; _move.X = _move.Y = 0; }

    private void Tick()
    {
        // only while somebody can see it: on screen, and the window in front
        if (!IsEffectivelyVisible || TopLevel.GetTopLevel(this) is not Window { IsActive: true }) { Reset(); return; }
        var t = _clock.Elapsed.TotalSeconds;
        var (deg, secs) = _mood switch
        {
            ReaderMood.Busy => (3.2, 0.32), ReaderMood.Ready => (1.6, 0.9), ReaderMood.NoReader => (0.8, 2.2), _ => (1.3, 1.4),
        };
        var wave = Math.Sin(2 * Math.PI * t / (secs * 2));          // one full back-and-forth takes two "secs"
        _sway.Angle = deg * wave;
        var breathe = 1 + 0.014 * (0.5 + 0.5 * wave);
        var pop = 1.0;
        if (_popStart >= 0)
        {
            var k = (t - _popStart) / 0.32;
            if (k >= 1) _popStart = -1; else pop = 0.9 + 0.1 * (1 + 1.7 * Math.Pow(k - 1, 3) + 0.7 * Math.Pow(k - 1, 2));   // ease-out with a little overshoot
        }
        _scale.ScaleX = pop; _scale.ScaleY = pop * breathe;
        double y = 0, x = 0;
        if (_hopStart >= 0)
        {
            var k = (t - _hopStart) / 0.42;
            if (k >= 1) _hopStart = -1; else y = -14 * Math.Abs(Math.Sin(k * Math.PI)) * (1 - k * 0.4);
        }
        if (_shakeStart >= 0)
        {
            var k = (t - _shakeStart) / 0.45;
            if (k >= 1) _shakeStart = -1; else x = 5 * Math.Sin(k * Math.PI * 5) * (1 - k);
        }
        _move.X = x; _move.Y = y;
    }
}
