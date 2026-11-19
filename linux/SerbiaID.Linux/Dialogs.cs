using Avalonia;
using Avalonia.Controls;
using Avalonia.Layout;
using Avalonia.Media;

namespace SerbiaID;

/// A small modal question with two buttons.
public static class Dialogs
{
    public static async Task<bool> Confirm(Window owner, string title, string text, string okText, string cancelText)
    {
        var win = new Window { Title = title, SizeToContent = SizeToContent.WidthAndHeight, WindowStartupLocation = WindowStartupLocation.CenterOwner, CanResize = false, ShowInTaskbar = false };
        var ok = new Button { Content = okText, MinWidth = 100, Margin = new Thickness(0, 0, 8, 0), IsDefault = true, HorizontalContentAlignment = HorizontalAlignment.Center, Classes = { "primary" } };
        var cancel = new Button { Content = cancelText, MinWidth = 100, IsCancel = true, HorizontalContentAlignment = HorizontalAlignment.Center };
        ok.Click += (_, _) => win.Close(true);
        cancel.Click += (_, _) => win.Close(false);
        var row = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 16, 0, 0), Children = { ok, cancel } };
        win.Content = new StackPanel { Margin = new Thickness(22), Children = { new TextBlock { Text = text, TextWrapping = TextWrapping.Wrap, MaxWidth = 420 }, row } };
        return await win.ShowDialog<bool>(owner);
    }
}
