using Avalonia;
using Avalonia.Controls;
using Avalonia.Media;

namespace SerbiaID;

/// A4 printout of the vehicle registration card, laid out after the printout of MUP's reader (see VehiclePrintSpec).
internal static class VehicleSheet
{
    public static Control Build(VehicleData v, double w, double h, bool includeJmbg)
    {
        var page = new Canvas { Width = VehiclePrintSpec.PageW, Height = VehiclePrintSpec.PageH, Background = Brushes.White };
        var face = new FontFamily("Verdana, DejaVu Sans, Liberation Sans, Arial");
        foreach (var it in VehiclePrintSpec.Build(v, includeJmbg))
        {
            if (it.IsRule)
            {
                var rule = new Avalonia.Controls.Shapes.Rectangle { Width = it.Width, Height = it.Thickness, Fill = Brushes.Black };
                Canvas.SetLeft(rule, it.X); Canvas.SetTop(rule, it.Y - it.Thickness / 2); page.Children.Add(rule);
                continue;
            }
            if (string.IsNullOrEmpty(it.Text)) continue;
            var t = new TextBlock
            {
                Text = it.Text, FontFamily = face, FontSize = it.Size, FontWeight = it.Bold ? FontWeight.Bold : FontWeight.Normal,
                Foreground = it.Size < 9 ? Brushes.Gray : Brushes.Black, TextWrapping = TextWrapping.Wrap,
                TextDecorations = it.Underline ? TextDecorations.Underline : null,
            };
            if (it.Width > 0) t.Width = it.Width;
            Canvas.SetLeft(t, it.X);
            Canvas.SetTop(t, it.Y - it.Size * 1.2 / 2);
            page.Children.Add(t);
        }
        var root = new Viewbox { Width = w, Height = h, Stretch = Avalonia.Media.Stretch.Uniform, VerticalAlignment = Avalonia.Layout.VerticalAlignment.Top, Child = page };
        var host = new Grid { Width = w, Height = h, Background = Brushes.White };
        host.Children.Add(root);
        host.Measure(new Size(w, h));
        host.Arrange(new Rect(0, 0, w, h));
        return host;
    }
}
