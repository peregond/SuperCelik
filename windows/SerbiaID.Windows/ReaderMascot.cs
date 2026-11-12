using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Shapes;
using System.Windows.Threading;

namespace SerbiaID;

/// What the card reader "feels" (same states as the macOS app).
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

/// The card reader as a small character: a rounded body with a card slot on top, two eyes and a mouth.
/// The card slides into it when inserted. Drawn on a 100 x 100 canvas and scaled to the control's size.
///
/// Cheap by design: a dozen shapes, short state-change animations, and one blink every few seconds
/// (skipped while the window is inactive or hidden).
public sealed class ReaderMascot : Viewbox
{
    private readonly Border _card, _body, _tint, _slot;
    private readonly Ellipse _cheekL, _cheekR;
    private readonly QuadraticBezierSegment _mouth;
    private readonly TranslateTransform _cardMove = new(0, -16), _gaze = new(), _shake = new();
    private readonly ScaleTransform _lids = new(1, 1), _bounce = new(1, 1);
    private readonly DispatcherTimer _blink = new();
    private readonly Random _rnd = new();
    private ReaderMood _mood = ReaderMood.Waiting;
    private bool _hasCard;

    public ReaderMascot()
    {
        Stretch = Stretch.Uniform;
        var c = new Canvas { Width = 100, Height = 100, RenderTransformOrigin = new Point(0.5, 0.5) };
        c.RenderTransform = new TransformGroup { Children = { _bounce, _shake } };

        // the card, added first so that the body covers its lower part (it "goes into the slot")
        _card = new Border { Width = 44, Height = 40, CornerRadius = new CornerRadius(5), BorderThickness = new Thickness(2), Opacity = 0, RenderTransform = _cardMove };
        _card.SetResourceReference(Border.BackgroundProperty, "SurfaceBrush");
        _card.SetResourceReference(Border.BorderBrushProperty, "MutedBrush");
        _card.Child = new Border
        {
            Width = 12, Height = 9, CornerRadius = new CornerRadius(2), Background = new SolidColorBrush(Color.FromRgb(0xE3, 0xB3, 0x41)),
            HorizontalAlignment = HorizontalAlignment.Left, VerticalAlignment = VerticalAlignment.Top, Margin = new Thickness(5, 5, 0, 0),
        };
        Place(c, _card, 28, 8);

        _tint = new Border { CornerRadius = new CornerRadius(14), Opacity = 0.13 };
        _body = new Border { Width = 76, Height = 60, CornerRadius = new CornerRadius(18), BorderThickness = new Thickness(4), Child = _tint };
        _body.SetResourceReference(Border.BackgroundProperty, "SurfaceBrush");
        Place(c, _body, 12, 32);

        _slot = new Border { Width = 50, Height = 4, CornerRadius = new CornerRadius(2), Opacity = 0.55 };
        Place(c, _slot, 25, 37);

        Place(c, Eye(), 33, 54);
        Place(c, Eye(), 57, 54);

        var pink = new SolidColorBrush(Color.FromRgb(0xF2, 0x8B, 0x9B));
        _cheekL = new Ellipse { Width = 12, Height = 12, Fill = pink, Opacity = 0 };
        _cheekR = new Ellipse { Width = 12, Height = 12, Fill = pink, Opacity = 0 };
        Place(c, _cheekL, 21, 65);
        Place(c, _cheekR, 67, 65);

        _mouth = new QuadraticBezierSegment(new Point(50, 79), new Point(59, 77), true);
        var figure = new PathFigure { StartPoint = new Point(41, 77), IsClosed = false, IsFilled = false };
        figure.Segments.Add(_mouth);
        var geometry = new PathGeometry();
        geometry.Figures.Add(figure);
        var mouth = new System.Windows.Shapes.Path { Data = geometry, StrokeThickness = 3.5, StrokeStartLineCap = PenLineCap.Round, StrokeEndLineCap = PenLineCap.Round };
        mouth.SetResourceReference(Shape.StrokeProperty, "TextBrush");
        c.Children.Add(mouth);

        Child = c;
        Apply(animated: false, moodChanged: false);
        _blink.Tick += (_, _) => Blink();
        Loaded += (_, _) => ScheduleBlink();
        Unloaded += (_, _) => _blink.Stop();
    }

    private static void Place(Canvas c, UIElement el, double left, double top)
    {
        Canvas.SetLeft(el, left); Canvas.SetTop(el, top); c.Children.Add(el);
    }

    private Ellipse Eye()
    {
        var e = new Ellipse { Width = 10, Height = 12, RenderTransformOrigin = new Point(0.5, 0.5) };
        e.RenderTransform = new TransformGroup { Children = { _lids, _gaze } };
        e.SetResourceReference(Shape.FillProperty, "TextBrush");
        return e;
    }

    /// Sets the state; the face animates to it.
    public void Set(ReaderMood mood, bool card)
    {
        if (mood == _mood && card == _hasCard) return;
        bool moodChanged = mood != _mood;
        _mood = mood; _hasCard = card;
        Apply(animated: IsLoaded, moodChanged);
    }

    private double LidsOpen => _mood == ReaderMood.NoReader ? 0.5 : 1;

    private void Apply(bool animated, bool moodChanged)
    {
        int ms = animated ? 280 : 0;

        // colour of the outline, the slot and the faint body tint
        string key = _mood switch { ReaderMood.NoReader => "MutedBrush", ReaderMood.Ready => "OkBrush", ReaderMood.Error => "BadBrush", _ => "AccentTextBrush" };
        _body.SetResourceReference(Border.BorderBrushProperty, key);
        _tint.SetResourceReference(Border.BackgroundProperty, key);
        _slot.SetResourceReference(Border.BackgroundProperty, key);

        // mouth: -1 = frown ... +1 = big smile
        double smile = _mood switch { ReaderMood.NoReader => -0.8, ReaderMood.Waiting => 0.25, ReaderMood.Ready => 1, ReaderMood.Busy => 0.1, _ => -0.55 };
        var control = new Point(50, 77 + 9 * smile);
        if (ms > 0 && Fx.Motion)
            _mouth.BeginAnimation(QuadraticBezierSegment.Point1Property, new PointAnimation(control, TimeSpan.FromMilliseconds(ms)) { EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut } });
        else { _mouth.BeginAnimation(QuadraticBezierSegment.Point1Property, null); _mouth.Point1 = control; }

        // eyes: half closed and looking down without a reader, looking up at the slot while waiting
        Fx.To(_lids, ScaleTransform.ScaleYProperty, LidsOpen, ms);
        Fx.To(_gaze, TranslateTransform.YProperty, _mood switch { ReaderMood.NoReader => 2.5, ReaderMood.Waiting => -2.5, ReaderMood.Busy => 1, _ => 0 }, ms);
        if (_mood == ReaderMood.Busy && Fx.Motion)
        {
            _gaze.BeginAnimation(TranslateTransform.XProperty, new DoubleAnimation(-3, 3, TimeSpan.FromMilliseconds(450))
            {
                AutoReverse = true, RepeatBehavior = RepeatBehavior.Forever, EasingFunction = new SineEase { EasingMode = EasingMode.EaseInOut },
            });
        }
        else Fx.To(_gaze, TranslateTransform.XProperty, 0, animated ? 180 : 0);

        // the card slides into the slot
        Fx.To(_card, OpacityProperty, _hasCard ? 1 : 0, ms);
        Fx.To(_cardMove, TranslateTransform.YProperty, _hasCard ? 0 : -16, animated ? 360 : 0);

        Fx.To(_cheekL, OpacityProperty, _mood == ReaderMood.Ready ? 0.5 : 0, ms);
        Fx.To(_cheekR, OpacityProperty, _mood == ReaderMood.Ready ? 0.5 : 0, ms);

        if (!animated || !moodChanged || !Fx.Motion) return;
        if (_mood == ReaderMood.Ready)
        {
            var hop = new DoubleAnimationUsingKeyFrames { Duration = TimeSpan.FromMilliseconds(340) };
            hop.KeyFrames.Add(new EasingDoubleKeyFrame(1.1, KeyTime.FromPercent(0.35), new CubicEase { EasingMode = EasingMode.EaseOut }));
            hop.KeyFrames.Add(new EasingDoubleKeyFrame(1, KeyTime.FromPercent(1), new CubicEase { EasingMode = EasingMode.EaseInOut }));
            _bounce.BeginAnimation(ScaleTransform.ScaleXProperty, hop);
            _bounce.BeginAnimation(ScaleTransform.ScaleYProperty, hop);
        }
        else if (_mood == ReaderMood.Error)
        {
            var shake = new DoubleAnimationUsingKeyFrames { Duration = TimeSpan.FromMilliseconds(420) };
            double[] xs = { -4, 4, -3, 3, -1.5, 0 };
            for (int i = 0; i < xs.Length; i++) shake.KeyFrames.Add(new LinearDoubleKeyFrame(xs[i], KeyTime.FromPercent((i + 1) / (double)xs.Length)));
            _shake.BeginAnimation(TranslateTransform.XProperty, shake);
        }
    }

    private void ScheduleBlink()
    {
        _blink.Stop();
        if (!Fx.Motion) return;
        _blink.Interval = TimeSpan.FromMilliseconds(3200 + _rnd.Next(3300));
        _blink.Start();
    }

    private void Blink()
    {
        ScheduleBlink();
        // nobody is looking: do not animate
        if (!IsVisible || Window.GetWindow(this) is not { IsActive: true }) return;
        var a = new DoubleAnimationUsingKeyFrames { Duration = TimeSpan.FromMilliseconds(230) };
        a.KeyFrames.Add(new EasingDoubleKeyFrame(0.12, KeyTime.FromPercent(0.4)));
        a.KeyFrames.Add(new EasingDoubleKeyFrame(LidsOpen, KeyTime.FromPercent(1)));
        _lids.BeginAnimation(ScaleTransform.ScaleYProperty, a);
    }
}
