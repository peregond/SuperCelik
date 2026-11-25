using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace SerbiaID;

/// Hidden card diagnostics (Settings, shown after tapping the version 5 times).
public partial class MainWindow
{
    private VehicleData _vehicle;
    private HealthData _health;
    private bool _diagUnlocked;
    private int _versionTaps;
    private Border _diagCard;
    private TextBox _diagLog;
    private Button _diagRun, _diagCopy;
    private TextBlock _diagTitle, _diagText;

    private void ApplyVehicleLanguage()
    {
        if (_diagCard != null)
        {
            _diagTitle.Text = Loc.T("diagTitle"); _diagText.Text = Loc.T("diagText");
            _diagRun.Content = Loc.T("diagRun"); _diagCopy.Content = Loc.T("diagCopy");
        }
    }

    // ---------- hidden diagnostics ----------
    private void Version_Click(object s, System.Windows.Input.MouseButtonEventArgs e)
    {
        if (++_versionTaps < 5 || _diagUnlocked) return;
        _diagUnlocked = true;
        BuildDiagCard();
        ShowInfo(Loc.T("diagUnlocked"));
    }

    private void BuildDiagCard()
    {
        _diagCard = new Border { Style = (Style)FindResource("Card"), Margin = new Thickness(0, 16, 0, 0) };
        var st = new StackPanel();
        _diagTitle = new TextBlock { Foreground = B("TextBrush"), FontSize = 15, FontWeight = FontWeights.Bold, Margin = new Thickness(0, 0, 0, 6) };
        _diagText = new TextBlock { Foreground = B("MutedBrush"), TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 0, 0, 10) };
        var row = new WrapPanel();
        _diagRun = new Button { Style = (Style)FindResource("SecondaryButton"), Margin = new Thickness(0, 0, 10, 8) };
        _diagCopy = new Button { Style = (Style)FindResource("SecondaryButton"), Margin = new Thickness(0, 0, 10, 8), IsEnabled = false };
        _diagLog = new TextBox { IsReadOnly = true, Height = 220, FontFamily = new FontFamily("Consolas"), FontSize = 11, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, HorizontalScrollBarVisibility = ScrollBarVisibility.Auto, Visibility = Visibility.Collapsed };
        _diagRun.Click += async (_, _) => await Run(async () =>
        {
            var reader = Reader;
            var text = await Compat.Run(() => CardDiag.Run(_pc, reader, Updater.CurrentText));
            _diagLog.Text = text; _diagLog.Visibility = Visibility.Visible; _diagCopy.IsEnabled = true;
        });
        _diagCopy.Click += (_, _) => { try { Clipboard.SetText(_diagLog.Text); ShowInfo(Loc.T("diagCopied")); } catch { } };
        row.Children.Add(_diagRun); row.Children.Add(_diagCopy);
        st.Children.Add(_diagTitle); st.Children.Add(_diagText); st.Children.Add(row); st.Children.Add(_diagLog);
        _diagCard.Child = st;
        SettingsStack.Children.Add(_diagCard);
        ApplyVehicleLanguage();
        _diagRun.IsEnabled = _cardPresent && !_busy;
    }
}
