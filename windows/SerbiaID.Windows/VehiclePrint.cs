using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace SerbiaID;

/// A4 printout of the vehicle registration card, laid out after the printout of MUP's reader (see VehiclePrintSpec).
/// Same page size and scaling as PrintSheet, so the print preview, the printer and the PDF writer use it unchanged.
internal static class VehicleSheet
{
    public static FrameworkElement Build(VehicleData v, double w, double h, bool includeJmbg)
    {
        var page = new Canvas { Width = VehiclePrintSpec.PageW, Height = VehiclePrintSpec.PageH, Background = Brushes.White };
        var face = new FontFamily("Verdana, Tahoma, Segoe UI, Arial");
        foreach (var it in VehiclePrintSpec.Build(v, includeJmbg))
        {
            if (it.IsRule)
            {
                var rule = new System.Windows.Shapes.Rectangle { Width = it.Width, Height = it.Thickness, Fill = Brushes.Black };
                Canvas.SetLeft(rule, it.X); Canvas.SetTop(rule, it.Y - it.Thickness / 2); page.Children.Add(rule);
                continue;
            }
            if (string.IsNullOrEmpty(it.Text)) continue;
            var t = new TextBlock
            {
                Text = it.Text, FontFamily = face, FontSize = it.Size, FontWeight = it.Bold ? FontWeights.Bold : FontWeights.Normal,
                Foreground = it.Size < 9 ? Brushes.Gray : Brushes.Black, TextWrapping = TextWrapping.Wrap,
                TextDecorations = it.Underline ? TextDecorations.Underline : null,
            };
            if (it.Width > 0) t.Width = it.Width;
            t.Measure(new Size(it.Width > 0 ? it.Width : double.PositiveInfinity, double.PositiveInfinity));
            Canvas.SetLeft(t, it.X);
            // Y is the centre of the first line; a wrapped item grows downwards
            double first = it.Size * 1.2;
            Canvas.SetTop(t, it.Y - first / 2);
            page.Children.Add(t);
        }
        var root = new Viewbox { Width = w, Height = h, Stretch = Stretch.Uniform, VerticalAlignment = VerticalAlignment.Top, Child = page };
        var host = new Grid { Width = w, Height = h, Background = Brushes.White };
        host.Children.Add(root);
        host.Measure(new Size(w, h));
        host.Arrange(new Rect(0, 0, w, h));
        host.UpdateLayout();
        return host;
    }
}
