using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace SerbiaID;

/// A4 printout of the vehicle registration card data: a plain table (label, value), not a copy of any official form.
/// Same page size and scaling as PrintSheet, so the print preview, the printer and the PDF writer use it unchanged.
internal static class VehicleSheet
{
    private const double PageW = 595.28, PageH = 841.89;

    public static FrameworkElement Build(VehicleData v, double w, double h, bool includeJmbg)
    {
        var rows = VehicleRows.Build(v, includeJmbg);
        var page = new Canvas { Width = PageW, Height = PageH, Background = Brushes.White };
        var face = new FontFamily("Arial");
        double y = 52;
        TextBlock T(string s, double size, bool bold, Brush b = null) => new TextBlock
        { Text = s, FontFamily = face, FontSize = size, FontWeight = bold ? FontWeights.Bold : FontWeights.Normal, Foreground = b ?? Brushes.Black, TextWrapping = TextWrapping.Wrap };
        void Put(UIElement e, double x, double top, double width = double.NaN)
        {
            if (!double.IsNaN(width)) ((FrameworkElement)e).Width = width;
            Canvas.SetLeft(e, x); Canvas.SetTop(e, top); page.Children.Add(e);
        }

        Put(T(Loc.T("vehTitle"), 20, true), 50, y); y += 30;
        Put(T(v.RegistrationNumber ?? "", 14, true), 50, y); y += 26;
        page.Children.Add(new System.Windows.Shapes.Rectangle { Width = PageW - 100, Height = 1.2, Fill = Brushes.Black, Margin = new Thickness(50, y, 0, 0) }); y += 10;

        // as many rows as fit: the step shrinks a little for long data, the font stays readable
        double step = Math.Min(20, (PageH - y - 70) / Math.Max(1, rows.Count));
        double font = step >= 18 ? 11 : 9.5;
        foreach (var (key, value) in rows)
        {
            Put(T(Loc.T(key), font, false, Brushes.DimGray), 50, y, 190);
            Put(T(value, font, true), 245, y, PageW - 245 - 50);
            y += step;
        }

        Put(T($"{Loc.T("vehNote")}   {DateTime.Now:dd.MM.yyyy}", 8, false, Brushes.Gray), 50, PageH - 44, PageW - 100);

        var root = new Viewbox { Width = w, Height = h, Stretch = Stretch.Uniform, VerticalAlignment = VerticalAlignment.Top, Child = page };
        var host = new Grid { Width = w, Height = h, Background = Brushes.White };
        host.Children.Add(root);
        host.Measure(new Size(w, h));
        host.Arrange(new Rect(0, 0, w, h));
        host.UpdateLayout();
        return host;
    }
}
