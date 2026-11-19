using Avalonia;
using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Layout;

namespace SerbiaID;

/// Small modal dialog with 1-3 password fields (PIN / PUK / new PIN).
public static class PinDialog
{
    /// Returns entered values, or null if cancelled. `labels` = one caption per field.
    public static async Task<string[]> Ask(Window owner, string title, string note, params string[] labels)
    {
        var boxes = labels.Select(_ => new TextBox { PasswordChar = '•', MaxLength = 8, Margin = new Thickness(0, 2, 0, 10), MinWidth = 280 }).ToArray();
        var panel = new StackPanel { Margin = new Thickness(20) };
        panel.Children.Add(new TextBlock { Text = note, TextWrapping = Avalonia.Media.TextWrapping.Wrap, Margin = new Thickness(0, 0, 0, 12), MaxWidth = 340 });
        for (int i = 0; i < labels.Length; i++) { panel.Children.Add(new TextBlock { Text = labels[i] }); panel.Children.Add(boxes[i]); }

        var win = new Window
        {
            Title = title, SizeToContent = SizeToContent.WidthAndHeight, WindowStartupLocation = WindowStartupLocation.CenterOwner,
            CanResize = false, ShowInTaskbar = false,
        };
        var ok = new Button { Content = "OK", MinWidth = 80, Margin = new Thickness(0, 0, 8, 0), IsDefault = true, HorizontalContentAlignment = HorizontalAlignment.Center };
        var cancel = new Button { Content = Loc.T("cancel"), MinWidth = 80, IsCancel = true, HorizontalContentAlignment = HorizontalAlignment.Center };
        ok.Click += (_, _) => win.Close(boxes.Select(b => b.Text ?? "").ToArray());
        cancel.Click += (_, _) => win.Close(null);
        var row = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right };
        row.Children.Add(ok); row.Children.Add(cancel);
        panel.Children.Add(row);
        win.Content = panel;
        win.Opened += (_, _) => boxes[0].Focus();
        return await win.ShowDialog<string[]>(owner);
    }
}
