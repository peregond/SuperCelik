using System.Windows;
using System.Windows.Controls;

namespace SerbiaID;

/// Small modal dialog with 1-3 password fields (PIN / PUK / new PIN).
public static class PinDialog
{
    /// Returns entered values, or null if cancelled. `labels` = one caption per field.
    public static string[] Ask(Window owner, string title, string note, params string[] labels)
    {
        var boxes = labels.Select(_ => new PasswordBox { MaxLength = 8, Margin = new Thickness(0, 2, 0, 10), Padding = new Thickness(6, 4, 6, 4) }).ToArray();
        var panel = new StackPanel { Margin = new Thickness(20) };
        panel.Children.Add(new TextBlock { Text = note, TextWrapping = Wrap, Margin = new Thickness(0, 0, 0, 12), MaxWidth = 340 });
        for (int i = 0; i < labels.Length; i++)
        {
            panel.Children.Add(new TextBlock { Text = labels[i] });
            panel.Children.Add(boxes[i]);
        }
        var ok = new Button { Content = "OK", IsDefault = true, MinWidth = 80, Margin = new Thickness(0, 0, 8, 0), Padding = new Thickness(8, 4, 8, 4) };
        var cancel = new Button { Content = Loc.T("cancel"), IsCancel = true, MinWidth = 80, Padding = new Thickness(8, 4, 8, 4) };
        var row = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right };
        row.Children.Add(ok); row.Children.Add(cancel);
        panel.Children.Add(row);
        var win = new Window
        {
            Title = title, Content = panel, Owner = owner, SizeToContent = SizeToContent.WidthAndHeight,
            WindowStartupLocation = WindowStartupLocation.CenterOwner, ResizeMode = ResizeMode.NoResize, ShowInTaskbar = false,
        };
        ok.Click += (_, _) => win.DialogResult = true;
        win.Loaded += (_, _) => boxes[0].Focus();
        return win.ShowDialog() == true ? boxes.Select(b => b.Password).ToArray() : null;
    }

    private const TextWrapping Wrap = TextWrapping.Wrap;
}
