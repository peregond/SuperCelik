using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Imaging;

namespace SerbiaID;

/// What the card reader "feels" (same states as the macOS app). Drives which pose the mascots take.
public enum ReaderMood
{
    NoReader,   // nothing plugged in: grey, sleepy, sad
    Waiting,    // reader connected, no card: looks up at the slot
    Ready,      // card inserted: happy
    Busy,       // reading: eyes scan left and right
    Error,      // the last operation failed: worried
}

/// Small motion helpers. Everything is skipped when Windows has animations turned off
/// (Settings > Accessibility > Visual effects) and in the screenshot mode.
internal static class Fx
{
    public static bool Enabled = true;
    public static bool Motion => Enabled && SystemParameters.ClientAreaAnimation;

    private static readonly IEasingFunction Ease = new CubicEase { EasingMode = EasingMode.EaseOut };

    /// Animates a double property to `value` (or just sets it when motion is off).
    public static void To(DependencyObject target, DependencyProperty property, double value, int ms = 260)
    {
        var a = (IAnimatable)target;
        if (!Motion || ms <= 0) { a.BeginAnimation(property, null); target.SetValue(property, value); return; }
        a.BeginAnimation(property, new DoubleAnimation(value, TimeSpan.FromMilliseconds(ms)) { EasingFunction = Ease });
    }

    /// Content appears: fades in while sliding a few pixels into place.
    public static void FadeIn(FrameworkElement el, double dy = 8, int ms = 220)
    {
        if (!Motion) { el.BeginAnimation(UIElement.OpacityProperty, null); el.Opacity = 1; el.RenderTransform = Transform.Identity; return; }
        var t = new TranslateTransform(0, dy);
        el.RenderTransform = t;
        el.BeginAnimation(UIElement.OpacityProperty, new DoubleAnimation(0, 1, TimeSpan.FromMilliseconds(ms)) { EasingFunction = Ease });
        t.BeginAnimation(TranslateTransform.YProperty, new DoubleAnimation(dy, 0, TimeSpan.FromMilliseconds(ms)) { EasingFunction = Ease });
    }

    /// A result pill pops in.
    public static void Pop(FrameworkElement el)
    {
        if (!Motion) return;
        var s = new ScaleTransform(1, 1);
        el.RenderTransformOrigin = new Point(0.5, 0.5);
        el.RenderTransform = s;
        var a = new DoubleAnimation(0.8, 1, TimeSpan.FromMilliseconds(280)) { EasingFunction = new BackEase { EasingMode = EasingMode.EaseOut, Amplitude = 0.6 } };
        s.BeginAnimation(ScaleTransform.ScaleXProperty, a);
        s.BeginAnimation(ScaleTransform.ScaleYProperty, a);
        el.BeginAnimation(UIElement.OpacityProperty, new DoubleAnimation(0, 1, TimeSpan.FromMilliseconds(160)));
    }
}

/// The two cartoon characters: the card reader and the token's key.
public enum MascotCharacter { Reader, Key }

/// A mascot drawn from illustrated poses (Mascots\<character>-<pose>.png), animated with cheap transforms only:
/// a slow breathing sway, a hop when something good happens, a quick rocking while busy, a shake on errors
/// and a soft cross-fade between poses. A pose that has no picture yet falls back to the greeting pose, greyed.
///
/// Nothing animates while the window is inactive or when Windows animations are off.
public sealed class MascotArt : Grid
{
    public MascotCharacter Character { get; set; } = MascotCharacter.Reader;

    private readonly Image _img = new() { Stretch = Stretch.Uniform };
    private readonly RotateTransform _sway = new();
    private readonly ScaleTransform _breathe = new(1, 1), _pop = new(1, 1);
    private readonly TranslateTransform _hop = new(), _shake = new();
    private ReaderMood _mood = ReaderMood.Waiting;
    private string _shown;

    private static readonly Dictionary<string, BitmapSource> Cache = new();

    public MascotArt()
    {
        _img.RenderTransformOrigin = new Point(0.5, 1);
        _img.RenderTransform = new TransformGroup { Children = { _pop, _breathe, _sway, _hop, _shake } };
        RenderOptions.SetBitmapScalingMode(_img, BitmapScalingMode.HighQuality);
        Children.Add(_img);
        Loaded += (_, _) =>
        {
            if (Window.GetWindow(this) is { } w) { w.Activated += (_, _) => Loop(); w.Deactivated += (_, _) => Stop(); }
            Show(animated: false); Loop();
        };
        IsVisibleChanged += (_, _) => { if (IsVisible) Loop(); else Stop(); };
    }

    private static string PoseFor(MascotCharacter c, ReaderMood m) => (c, m) switch
    {
        (_, ReaderMood.NoReader) => "sad",
        (_, ReaderMood.Waiting) => "present",
        (MascotCharacter.Reader, ReaderMood.Ready or ReaderMood.Busy) => "card",
        (MascotCharacter.Key, ReaderMood.Ready) => "thumbs",
        (MascotCharacter.Key, ReaderMood.Busy) => "look",
        _ => "worry",
    };

    private static BitmapSource Load(MascotCharacter c, string pose, bool grey)
    {
        string key = $"{c.ToString().ToLowerInvariant()}-{pose}{(grey ? "-grey" : "")}";
        if (Cache.TryGetValue(key, out var hit)) return hit;
        BitmapSource bmp = null;
        try
        {
            var uri = new Uri($"pack://application:,,,/Mascots/{c.ToString().ToLowerInvariant()}-{pose}.png");
            var src = new BitmapImage(uri); src.Freeze();
            bmp = grey ? Greyed(src) : src;
        }
        catch { }
        Cache[key] = bmp;
        return bmp;
    }

    /// Desaturated copy (alpha kept), for poses that are not drawn yet.
    private static BitmapSource Greyed(BitmapSource src)
    {
        var f = new FormatConvertedBitmap(src, PixelFormats.Bgra32, null, 0);
        int w = f.PixelWidth, h = f.PixelHeight, stride = w * 4;
        var px = new byte[h * stride]; f.CopyPixels(px, stride, 0);
        for (int i = 0; i < px.Length; i += 4)
        {
            byte g = (byte)((px[i] * 29 + px[i + 1] * 150 + px[i + 2] * 77) >> 8);
            px[i] = px[i + 1] = px[i + 2] = g;
        }
        var wb = BitmapSource.Create(w, h, 96, 96, PixelFormats.Bgra32, null, px, stride); wb.Freeze();
        return wb;
    }

    /// Sets the state; the pose changes with a short pop.
    public void Set(ReaderMood mood)
    {
        if (mood == _mood && _shown != null) return;
        bool moodChanged = mood != _mood;
        _mood = mood;
        Show(animated: IsLoaded);
        Loop();
        if (!moodChanged || !IsLoaded || !Fx.Motion) return;
        if (mood == ReaderMood.Ready)
        {
            var hop = new DoubleAnimationUsingKeyFrames { Duration = TimeSpan.FromMilliseconds(420) };
            hop.KeyFrames.Add(new EasingDoubleKeyFrame(-14, KeyTime.FromPercent(0.35), new CubicEase { EasingMode = EasingMode.EaseOut }));
            hop.KeyFrames.Add(new EasingDoubleKeyFrame(0, KeyTime.FromPercent(1), new BounceEase { EasingMode = EasingMode.EaseOut, Bounces = 2, Bounciness = 3 }));
            _hop.BeginAnimation(TranslateTransform.YProperty, hop);
        }
        else if (mood == ReaderMood.Error)
        {
            var shake = new DoubleAnimationUsingKeyFrames { Duration = TimeSpan.FromMilliseconds(450) };
            double[] xs = { -5, 5, -4, 4, -2, 0 };
            for (int i = 0; i < xs.Length; i++) shake.KeyFrames.Add(new LinearDoubleKeyFrame(xs[i], KeyTime.FromPercent((i + 1) / (double)xs.Length)));
            _shake.BeginAnimation(TranslateTransform.XProperty, shake);
        }
    }

    private void Show(bool animated)
    {
        string wanted = PoseFor(Character, _mood);
        var bmp = Load(Character, wanted, false);
        bool grey = false;
        if (bmp == null) { bmp = Load(Character, "present", true); wanted = "present-grey"; grey = true; }
        if (bmp == null || wanted == _shown) return;
        _shown = wanted;
        _img.Source = bmp;
        _img.Opacity = grey ? 0.85 : 1;
        if (animated && Fx.Motion)
        {
            // the new pose pops in from slightly smaller, anchored at the feet
            var pop = new DoubleAnimation(0.9, 1, TimeSpan.FromMilliseconds(320)) { EasingFunction = new BackEase { EasingMode = EasingMode.EaseOut, Amplitude = 0.5 } };
            _pop.BeginAnimation(ScaleTransform.ScaleXProperty, pop);
            _pop.BeginAnimation(ScaleTransform.ScaleYProperty, pop);
            _img.BeginAnimation(OpacityProperty, new DoubleAnimation(0, grey ? 0.85 : 1, TimeSpan.FromMilliseconds(200)));
        }
    }

    private void Stop()
    {
        _sway.BeginAnimation(RotateTransform.AngleProperty, null);
        _breathe.BeginAnimation(ScaleTransform.ScaleYProperty, null);
        _sway.Angle = 0; _breathe.ScaleY = 1;
    }

    /// The idle loop: sway and breathing, faster while busy. Skipped when nobody is looking.
    private void Loop()
    {
        Stop();
        if (!Fx.Motion || !IsVisible || Window.GetWindow(this) is not { IsActive: true }) return;
        (double deg, double secs) = _mood switch
        {
            ReaderMood.Busy => (3.2, 0.32), ReaderMood.Ready => (1.6, 0.9), ReaderMood.NoReader => (0.8, 2.2), _ => (1.3, 1.4),
        };
        var ease = new SineEase { EasingMode = EasingMode.EaseInOut };
        _sway.BeginAnimation(RotateTransform.AngleProperty, new DoubleAnimation(-deg, deg, TimeSpan.FromSeconds(secs)) { AutoReverse = true, RepeatBehavior = RepeatBehavior.Forever, EasingFunction = ease });
        _breathe.BeginAnimation(ScaleTransform.ScaleYProperty, new DoubleAnimation(1, 1.014, TimeSpan.FromSeconds(secs)) { AutoReverse = true, RepeatBehavior = RepeatBehavior.Forever, EasingFunction = ease });
    }
}
