using Avalonia;
using Avalonia.Controls;
using Avalonia.Media;
using Avalonia.Media.TextFormatting;

namespace SerbiaID;

/// A4 printout of the vehicle registration card, matched to the printout of MUP's reader (see VehiclePrintSpec).
internal static class VehicleSheet
{
    public static Control Build(VehicleData v, double w, double h, bool includeJmbg)
    {
        var page = new VehiclePage(VehiclePrintSpec.Build(v, includeJmbg));
        var root = new Viewbox { Width = w, Height = h, Stretch = Avalonia.Media.Stretch.Uniform, VerticalAlignment = Avalonia.Layout.VerticalAlignment.Top, Child = page };
        var host = new Grid { Width = w, Height = h, Background = Brushes.White };
        host.Children.Add(root);
        host.Measure(new Size(w, h));
        host.Arrange(new Rect(0, 0, w, h));
        return host;
    }

    /// Draws every item at its baseline (TextLayout.Baseline), so that the position does not depend on the typeface's line spacing.
    private sealed class VehiclePage : Control
    {
        private readonly List<PrintItem> _items;
        // Verdana first (as in MUP's printout); DejaVu Sans, the usual Linux font, has nearly the same widths
        private static readonly FontFamily Face = new FontFamily("Verdana, DejaVu Sans, Liberation Sans, Arial");

        public VehiclePage(List<PrintItem> items)
        {
            _items = items; Width = VehiclePrintSpec.PageW; Height = VehiclePrintSpec.PageH;
        }

        protected override Size MeasureOverride(Size availableSize) => new Size(Width, Height);

        public override void Render(DrawingContext dc)
        {
            dc.DrawRectangle(Brushes.White, null, new Rect(0, 0, Width, Height));
            foreach (var it in _items)
            {
                if (it.IsRule) { dc.DrawRectangle(Brushes.Black, null, new Rect(it.X, it.B, it.Width, it.Thickness)); continue; }
                var brush = it.Size < 9 ? Brushes.Gray : Brushes.Black;
                var tl = new TextLayout(it.Text, new Typeface(Face, FontStyle.Normal, it.Bold ? FontWeight.Bold : FontWeight.Normal), it.Size, brush);
                tl.Draw(dc, new Point(it.X, it.B - tl.Baseline));
                if (it.Underline)
                    dc.DrawRectangle(brush, null, new Rect(it.X, it.B + VehiclePrintSpec.UnderlineOffset(it.Size), tl.WidthIncludingTrailingWhitespace, VehiclePrintSpec.UnderlineThickness));
            }
        }
    }
}
