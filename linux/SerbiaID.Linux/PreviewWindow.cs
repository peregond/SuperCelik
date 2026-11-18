using System.Diagnostics;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Layout;
using Avalonia.Media;
using Avalonia.Platform.Storage;

namespace SerbiaID;

/// In-app print preview. Linux has no common print dialog for apps like this, so "Print" saves a PDF to a
/// temporary file and opens it in the default viewer (which has the printer dialog); "Save PDF" saves it where you choose.
internal sealed class PreviewWindow : Window
{
    private readonly PersonalData _p;
    private readonly bool _jmbg;

    public PreviewWindow(PersonalData p, bool includeJmbg)
    {
        _p = p; _jmbg = includeJmbg;
        Title = $"{Loc.T("preview")} — {Loc.T("appTitle")}";
        Width = 760; Height = 860; MinWidth = 520; MinHeight = 500;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        this.Res(BackgroundProperty, "BgBrush");

        var dock = new DockPanel();
        var print = Ui.Btn(Loc.T("printCard"), "primary"); print.Click += (_, _) => DoPrint();
        var pdf = Ui.Btn(Loc.T("savePdf")); pdf.Click += async (_, _) => await DoPdf();
        var close = Ui.Btn(Loc.T("close")); close.Click += (_, _) => Close();
        var bar = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(16, 12), Spacing = 8 };
        foreach (var b in new[] { close, pdf, print }) bar.Children.Add(b);
        DockPanel.SetDock(bar, Dock.Bottom);
        dock.Children.Add(bar);

        var page = PrintSheet.Build(p, 793.7, 1122.5, includeJmbg);
        dock.Children.Add(new Border
        {
            Margin = new Thickness(24), Background = Brushes.White,
            BoxShadow = BoxShadows.Parse("0 2 18 0 #40000000"),
            Child = new Viewbox { Stretch = Stretch.Uniform, Child = page },
        });
        Content = dock;
    }

    private void DoPrint()
    {
        try
        {
            var path = Path.Combine(Path.GetTempPath(), $"SuperCelik-{Environment.UserName}-{Guid.NewGuid():N}.pdf");
            PdfWriter.SaveSheet(PrintSheet.Build(_p, 793.7, 1122.5, _jmbg), path);
            Process.Start(new ProcessStartInfo("xdg-open", new[] { path }) { UseShellExecute = false });
        }
        catch { }
    }

    private async Task DoPdf()
    {
        var f = await StorageProvider.SaveFilePickerAsync(new FilePickerSaveOptions
        {
            SuggestedFileName = "SuperCelik.pdf", DefaultExtension = "pdf",
            FileTypeChoices = new[] { new FilePickerFileType("PDF") { Patterns = new[] { "*.pdf" } } },
        });
        if (f?.TryGetLocalPath() is { } path) PdfWriter.SaveSheet(PrintSheet.Build(_p, 793.7, 1122.5, _jmbg), path);
    }
}
