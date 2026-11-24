using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace SerbiaID;

/// A4 printout of the vehicle registration card, matched to the printout of MUP's reader (see VehiclePrintSpec).
/// Same page size and scaling as PrintSheet, so the print preview, the printer and the PDF writer use it unchanged.
internal static class VehicleSheet
{
    public static FrameworkElement Build(VehicleData v, double w, double h, bool includeJmbg)
    {
        var page = new VehiclePage(VehiclePrintSpec.Build(v, includeJmbg));
        var root = new Viewbox { Width = w, Height = h, Stretch = Stretch.Uniform, VerticalAlignment = VerticalAlignment.Top, Child = page };
        var host = new Grid { Width = w, Height = h, Background = Brushes.White };
        host.Children.Add(root);
        host.Measure(new Size(w, h));
        host.Arrange(new Rect(0, 0, w, h));
        host.UpdateLayout();
        return host;
    }

    /// Draws every item at its baseline (FormattedText.Baseline), so that the position does not depend on the typeface's line spacing.
    private sealed class VehiclePage : FrameworkElement
    {
        private readonly List<PrintItem> _items;
        // Verdana first (as in MUP's printout); DejaVu Sans has nearly the same widths
        private static readonly FontFamily Face = new FontFamily("Verdana, DejaVu Sans, Tahoma, Segoe UI, Arial");

        public VehiclePage(List<PrintItem> items)
        {
            _items = items; Width = VehiclePrintSpec.PageW; Height = VehiclePrintSpec.PageH;
        }

        protected override Size MeasureOverride(Size availableSize) => new Size(Width, Height);

        protected override void OnRender(DrawingContext dc)
        {
            dc.DrawRectangle(Brushes.White, null, new Rect(0, 0, Width, Height));
            foreach (var it in _items)
            {
                if (it.IsRule) { dc.DrawRectangle(Brushes.Black, null, new Rect(it.X, it.B, it.Width, it.Thickness)); continue; }
                var brush = it.Size < 9 ? Brushes.Gray : Brushes.Black;
                var ft = new FormattedText(it.Text, CultureInfo.InvariantCulture, FlowDirection.LeftToRight,
                    new Typeface(Face, FontStyles.Normal, it.Bold ? FontWeights.Bold : FontWeights.Normal, FontStretches.Normal),
                    it.Size, brush);
                dc.DrawText(ft, new Point(it.X, it.B - ft.Baseline));
                if (it.Underline)
                    dc.DrawRectangle(brush, null, new Rect(it.X, it.B + VehiclePrintSpec.UnderlineOffset(it.Size), ft.WidthIncludingTrailingWhitespace, VehiclePrintSpec.UnderlineThickness));
            }
        }
    }
}
