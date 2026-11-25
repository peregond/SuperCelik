using Avalonia;
using Avalonia.Controls;
using Avalonia.Layout;
using Avalonia.Media;

namespace SerbiaID;

/// Hidden card diagnostics (Settings, shown after tapping the version 5 times).
public sealed partial class MainWindow
{
    private VehicleData _vehicle;
    private HealthData _health;
    private bool _diagUnlocked;
    private int _versionTaps;
    private Button _diagRun, _diagCopy;
    private TextBlock _diagTitle, _diagText;
    private TextBox _diagLog;
    private Border _diagCard;

    private void ApplyVehicleLanguage()
    {
        if (_diagCard != null)
        {
            _diagTitle.Text = Loc.T("diagTitle"); _diagText.Text = Loc.T("diagText");
            Ui.SetBtn(_diagRun, "refresh-cw", Loc.T("diagRun")); Ui.SetBtn(_diagCopy, "copy", Loc.T("diagCopy"));
        }
    }

    // ---------- hidden diagnostics ----------
    private Control BuildDiagCard()
    {
        _diagTitle = Ui.Label("", 15, true); _diagTitle.FontWeight = FontWeight.Bold; _diagTitle.Margin = new Thickness(0, 0, 0, 6);
        _diagText = Ui.Label("", 13, false, "MutedBrush", true); _diagText.Margin = new Thickness(0, 0, 0, 10);
        _diagRun = Ui.Btn(""); _diagCopy = Ui.Btn(""); _diagCopy.IsEnabled = false;
        _diagRun.Margin = _diagCopy.Margin = new Thickness(0, 0, 10, 8);
        _diagLog = new TextBox { IsReadOnly = true, Height = 220, FontFamily = new FontFamily("monospace"), FontSize = 11, IsVisible = false, AcceptsReturn = true };
        _diagRun.Click += async (_, _) => await Run(async () =>
        {
            var reader = Reader;
            var text = await Task.Run(() => CardDiag.Run(_pc, reader, Updater.CurrentText));
            _diagLog.Text = text; _diagLog.IsVisible = true; _diagCopy.IsEnabled = true;
        });
        _diagCopy.Click += async (_, _) => { try { await CopyText(_diagLog.Text); ShowInfo(Loc.T("diagCopied")); } catch { } };
        _diagCard = Ui.Card(new StackPanel { Children = { _diagTitle, _diagText, new WrapPanel { Children = { _diagRun, _diagCopy } }, _diagLog } });
        _diagCard.Margin = new Thickness(0, 16, 0, 0);
        _diagCard.IsVisible = _diagUnlocked;
        return _diagCard;
    }

    private void VersionTapped()
    {
        if (++_versionTaps < 5 || _diagUnlocked) return;
        _diagUnlocked = true; _diagCard.IsVisible = true;
        ShowInfo(Loc.T("diagUnlocked"));
    }
}
