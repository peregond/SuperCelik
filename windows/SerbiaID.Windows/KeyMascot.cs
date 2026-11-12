using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Shapes;
using System.Windows.Threading;

namespace SerbiaID;

/// The token's key as a little cartoon character (same moods as the reader): a gold key with a big face on its bow,
/// white-gloved hands and white shoes, in the spirit of old rubber-hose cartoons. It waves when a card is inserted,
/// scans with its eyes while reading and droops without a reader. Drawn on a 100 x 100 canvas.
///
/// Cheap by design: a few dozen shapes, short state-change animations and one blink every few seconds
/// (skipped while the window is inactive or hidden).
public sealed class KeyMascot : Viewbox
{
    private readonly Ellipse _bow, _cheekL, _cheekR;
    private readonly Rectangle _shaft;
    private readonly System.Windows.Shapes.Path _teeth, _mouthFill;
    private readonly QuadraticBezierSegment _mouthA, _mouthB;
    private readonly RotateTransform _arm = new(-32, 44, 63), _browL = new(0, 39.5, 15), _browR = new(0, 60.5, 15);
    private readonly TranslateTransform _browLift = new(), _gaze = new(), _shake = new();
    private readonly ScaleTransform _lids = new(1, 1), _bounce = new(1, 1);
    private readonly DispatcherTimer _blink = new();
    private readonly Random _rnd = new();
    private ReaderMood _mood = ReaderMood.Waiting;

    private static readonly Brush White = Brushes.White;
    private static readonly Brush Pupil = new SolidColorBrush(Color.FromRgb(0x1F, 0x1F, 0x1F));

    public KeyMascot()
    {
        Stretch = Stretch.Uniform;
        var c = new Canvas { Width = 100, Height = 100, RenderTransformOrigin = new Point(0.5, 1) };
        c.RenderTransform = new TransformGroup { Children = { _bounce, _shake } };

        // legs and shoes
        c.Children.Add(Ink(Geometry.Parse("M46,82 Q44,88 43,91 M54,82 Q56,88 57,91")));
        c.Children.Add(Glove(new Ellipse { Width = 15, Height = 7.2 }, 32, 89.9));
        c.Children.Add(Glove(new Ellipse { Width = 15, Height = 7.2 }, 53, 89.9));

        // right arm (always relaxed)
        c.Children.Add(Ink(Geometry.Parse("M56,64 Q70,66 78,72")));
        c.Children.Add(Glove(new Ellipse { Width = 12.4, Height = 12.4 }, 73.8, 67.3));

        // teeth, shaft, bow
        _teeth = Ink(Geometry.Parse("M44,66 H33 V71 H44 M44,75 H36 V80 H44"));
        c.Children.Add(_teeth);
        _shaft = new Rectangle { Width = 12, Height = 32, StrokeThickness = 3.2, StrokeLineJoin = PenLineJoin.Round };
        _shaft.SetResourceReference(Shape.StrokeProperty, "TextBrush");
        Place(c, _shaft, 44, 50);
        _bow = new Ellipse { Width = 50, Height = 50, StrokeThickness = 3.2 };
        _bow.SetResourceReference(Shape.StrokeProperty, "TextBrush");
        Place(c, _bow, 25, 6);
        c.Children.Add(new System.Windows.Shapes.Path
        {
            Data = Geometry.Parse("M33,18 Q38,11 46,10"), Stroke = White, Opacity = 0.65, StrokeThickness = 3, StrokeStartLineCap = PenLineCap.Round, StrokeEndLineCap = PenLineCap.Round,
        });

        // left arm with the glove: raised, waves, hangs down
        var arm = new Canvas { Width = 100, Height = 100, RenderTransform = _arm };
        arm.Children.Add(Ink(Geometry.Parse("M44,63 Q30,62 24,50")));
        arm.Children.Add(Glove(new Ellipse { Width = 12.4, Height = 12.4 }, 15.8, 39.8));
        c.Children.Add(arm);

        // face: eyes, brows, cheeks, mouth
        Place(c, Eye(1), 33, 20);
        Place(c, Eye(-1), 53, 20);
        var browL = Ink(Geometry.Parse("M33,17 Q40,13 46,17"), 2.4);
        browL.RenderTransform = new TransformGroup { Children = { _browL, _browLift } };
        var browR = Ink(Geometry.Parse("M54,17 Q60,13 67,17"), 2.4);
        browR.RenderTransform = new TransformGroup { Children = { _browR, _browLift } };
        c.Children.Add(browL); c.Children.Add(browR);

        var pink = new SolidColorBrush(Color.FromRgb(0xF2, 0x8B, 0x9B));
        _cheekL = new Ellipse { Width = 9, Height = 9, Fill = pink, Opacity = 0.35 };
        _cheekR = new Ellipse { Width = 9, Height = 9, Fill = pink, Opacity = 0.35 };
        Place(c, _cheekL, 26.5, 37.5); Place(c, _cheekR, 64.5, 37.5);

        _mouthA = new QuadraticBezierSegment(new Point(50, 55), new Point(58, 44), true);
        var fig = new PathFigure { StartPoint = new Point(42, 44), IsClosed = true, IsFilled = true };
        fig.Segments.Add(_mouthA);
        _mouthFill = new System.Windows.Shapes.Path { Data = new PathGeometry { Figures = { fig } }, Fill = new SolidColorBrush(Color.FromRgb(0x7A, 0x22, 0x30)), Opacity = 0 };
        c.Children.Add(_mouthFill);
        _mouthB = new QuadraticBezierSegment(new Point(50, 55), new Point(58, 44), true);
        var line = new PathFigure { StartPoint = new Point(42, 44), IsClosed = false, IsFilled = false };
        line.Segments.Add(_mouthB);
        c.Children.Add(Ink(new PathGeometry { Figures = { line } }, 2.6));

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

    private static System.Windows.Shapes.Path Ink(Geometry g, double width = 3.2)
    {
        var p = new System.Windows.Shapes.Path
        {
            Data = g, StrokeThickness = width, StrokeStartLineCap = PenLineCap.Round, StrokeEndLineCap = PenLineCap.Round, StrokeLineJoin = PenLineJoin.Round,
        };
        p.SetResourceReference(Shape.StrokeProperty, "TextBrush");
        return p;
    }

    /// A white glove / shoe with the ink outline, placed on the canvas.
    private static Ellipse Glove(Ellipse e, double left, double top)
    {
        e.Fill = White; e.StrokeThickness = 3.2;
        e.SetResourceReference(Shape.StrokeProperty, "TextBrush");
        Canvas.SetLeft(e, left); Canvas.SetTop(e, top);
        return e;
    }

    private Grid Eye(double side)
    {
        var g = new Grid { Width = 14, Height = 18, RenderTransformOrigin = new Point(0.5, 0.5), RenderTransform = _lids };
        var white = new Ellipse { Fill = White, StrokeThickness = 2.4 };
        white.SetResourceReference(Shape.StrokeProperty, "TextBrush");
        g.Children.Add(white);
        var pupil = new Grid { Width = 7.2, Height = 7.2 };
        pupil.Children.Add(new Ellipse { Fill = Pupil });
        pupil.Children.Add(new Ellipse { Width = 2.2, Height = 2.2, Fill = White, HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Top, Margin = new Thickness(0, 0.6, 0.8, 0) });
        pupil.RenderTransform = new TransformGroup { Children = { new TranslateTransform(-side * 1.5, 2), _gaze } };
        g.Children.Add(pupil);
        return g;
    }

    /// Sets the state; the face animates to it.
    public void Set(ReaderMood mood)
    {
        if (mood == _mood) return;
        _mood = mood;
        Apply(animated: IsLoaded, moodChanged: true);
    }

    private double LidsOpen => _mood == ReaderMood.NoReader ? 0.55 : 1;

    private void Apply(bool animated, bool moodChanged)
    {
        int ms = animated ? 280 : 0;
        bool grey = _mood == ReaderMood.NoReader;
        _bow.Fill = new SolidColorBrush(grey ? Color.FromRgb(0xCC, 0xCC, 0xCC) : Color.FromRgb(0xF2, 0xC9, 0x4C));
        var shaft = new SolidColorBrush(grey ? Color.FromRgb(0xB3, 0xB3, 0xB3) : Color.FromRgb(0xE8, 0xBA, 0x3D));
        _shaft.Fill = shaft; _teeth.Fill = shaft;

        // mouth: -1 = frown ... +1 = big smile
        double smile = _mood switch { ReaderMood.NoReader => -0.8, ReaderMood.Waiting => 0.2, ReaderMood.Ready => 1, ReaderMood.Busy => 0.15, _ => -0.6 };
        var control = new Point(50, 44 + 11 * smile);
        foreach (var seg in new[] { _mouthA, _mouthB })
        {
            if (ms > 0 && Fx.Motion)
                seg.BeginAnimation(QuadraticBezierSegment.Point1Property, new PointAnimation(control, TimeSpan.FromMilliseconds(ms)) { EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut } });
            else { seg.BeginAnimation(QuadraticBezierSegment.Point1Property, null); seg.Point1 = control; }
        }
        Fx.To(_mouthFill, OpacityProperty, Math.Clamp((smile - 0.4) / 0.6, 0, 1), ms);

        // eyes and brows
        Fx.To(_lids, ScaleTransform.ScaleYProperty, LidsOpen, ms);
        Fx.To(_gaze, TranslateTransform.YProperty, _mood switch { ReaderMood.NoReader => 3, ReaderMood.Waiting => -2, ReaderMood.Busy => 0.5, _ => 0 }, ms);
        if (_mood == ReaderMood.Busy && Fx.Motion)
        {
            _gaze.BeginAnimation(TranslateTransform.XProperty, new DoubleAnimation(-3, 3, TimeSpan.FromMilliseconds(450))
            {
                AutoReverse = true, RepeatBehavior = RepeatBehavior.Forever, EasingFunction = new SineEase { EasingMode = EasingMode.EaseInOut },
            });
        }
        else Fx.To(_gaze, TranslateTransform.XProperty, 0, animated ? 180 : 0);
        double tilt = _mood == ReaderMood.NoReader || _mood == ReaderMood.Error ? 14 : 0;
        Fx.To(_browL, RotateTransform.AngleProperty, -tilt, ms);
        Fx.To(_browR, RotateTransform.AngleProperty, tilt, ms);
        Fx.To(_browLift, TranslateTransform.YProperty, _mood == ReaderMood.Ready ? -2.5 : 0, ms);
        double cheeks = _mood == ReaderMood.Ready ? 1 : 0.35;
        Fx.To(_cheekL, OpacityProperty, cheeks, ms); Fx.To(_cheekR, OpacityProperty, cheeks, ms);

        // the left arm: raised when happy, half raised when waiting, hanging when sad
        Fx.To(_arm, RotateTransform.AngleProperty, _mood switch { ReaderMood.Ready => 0, ReaderMood.Waiting or ReaderMood.Busy => -32, _ => -78 }, ms > 0 ? 380 : 0);

        if (!animated || !moodChanged || !Fx.Motion) return;
        if (_mood == ReaderMood.Ready)
        {
            var hop = new DoubleAnimationUsingKeyFrames { Duration = TimeSpan.FromMilliseconds(340) };
            hop.KeyFrames.Add(new EasingDoubleKeyFrame(1.07, KeyTime.FromPercent(0.35), new CubicEase { EasingMode = EasingMode.EaseOut }));
            hop.KeyFrames.Add(new EasingDoubleKeyFrame(1, KeyTime.FromPercent(1), new CubicEase { EasingMode = EasingMode.EaseInOut }));
            _bounce.BeginAnimation(ScaleTransform.ScaleXProperty, hop);
            _bounce.BeginAnimation(ScaleTransform.ScaleYProperty, hop);
            // a few waves, then rest with the arm up
            var wave = new DoubleAnimationUsingKeyFrames { Duration = TimeSpan.FromMilliseconds(1300), BeginTime = TimeSpan.FromMilliseconds(380) };
            double[] angles = { 14, -4, 14, -4, 8, 0 };
            for (int i = 0; i < angles.Length; i++)
                wave.KeyFrames.Add(new EasingDoubleKeyFrame(angles[i], KeyTime.FromPercent((i + 1) / (double)angles.Length), new SineEase { EasingMode = EasingMode.EaseInOut }));
            _arm.BeginAnimation(RotateTransform.AngleProperty, wave);
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
        if (!IsVisible || Window.GetWindow(this) is not { IsActive: true }) return;
        var a = new DoubleAnimationUsingKeyFrames { Duration = TimeSpan.FromMilliseconds(230) };
        a.KeyFrames.Add(new EasingDoubleKeyFrame(0.1, KeyTime.FromPercent(0.4)));
        a.KeyFrames.Add(new EasingDoubleKeyFrame(LidsOpen, KeyTime.FromPercent(1)));
        _lids.BeginAnimation(ScaleTransform.ScaleYProperty, a);
    }
}
