using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace SerbiaID;

public partial class MainWindow : Window
{
    private readonly PcscService _pc = new();
    private PersonalData _personal;
    private TokenInfo _token;
    private SigStatus _sig;
    private bool _loading = true;

    public MainWindow()
    {
        InitializeComponent();
        foreach (var l in Enum.GetValues<Lang>()) CmbLang.Items.Add(l switch { Lang.ru => "Русский", Lang.en => "English", _ => "Srpski" });
        CmbLang.SelectedIndex = (int)Loc.Current;
        _loading = false;
        ApplyLanguage();
        Refresh();
    }

    protected override void OnClosed(EventArgs e) { _pc.Dispose(); base.OnClosed(e); }

    private string Reader => CmbReader.SelectedItem as string;

    // ---------- language ----------
    private void Lang_Changed(object s, SelectionChangedEventArgs e)
    {
        if (_loading || CmbLang.SelectedIndex < 0) return;
        Loc.Current = (Lang)CmbLang.SelectedIndex;
        ApplyLanguage();
    }

    private void ApplyLanguage()
    {
        Title = Loc.T("appTitle");
        LblReader.Text = Loc.T("reader");
        BtnRefresh.Content = Loc.T("refresh");
        BtnRead.Content = Loc.T("readCard");
        BtnPrint.Content = Loc.T("printCard");
        BtnVerify.Content = Loc.T("verifySignature");
        BtnReadToken.Content = Loc.T("readToken");
        TabPersonal.Header = Loc.T("tabPersonal");
        TabToken.Header = Loc.T("tabToken");
        TabAbout.Header = Loc.T("tabAbout");
        LblCerts.Text = Loc.T("certificates");
        LblPinNote.Text = Loc.T("pinNote");
        LblAboutTitle.Text = Loc.T("appTitle");
        LblAboutText.Text = Loc.T("aboutText");
        UpdateCardLabel();
        RenderPersonal();
        RenderSig();
        RenderToken();
    }

    // ---------- readers ----------
    private bool _cardPresent;

    private void UpdateCardLabel()
    {
        LblCard.Text = _cardPresent ? "✔ " + Loc.T("cardPresent") : "✘ " + Loc.T("noCard");
        LblCard.Foreground = _cardPresent ? Brushes.Green : Brushes.Gray;
        BtnRead.IsEnabled = _cardPresent;
        BtnReadToken.IsEnabled = _cardPresent;
        BtnVerify.IsEnabled = _cardPresent;
    }

    private void Refresh()
    {
        try
        {
            var prev = Reader;
            var readers = _pc.ListReaders();
            _loading = true;
            CmbReader.Items.Clear();
            foreach (var r in readers) CmbReader.Items.Add(r);
            if (readers.Count == 0) CmbReader.Items.Add(Loc.T("noReader"));
            CmbReader.SelectedItem = prev != null && readers.Contains(prev) ? prev : CmbReader.Items[0];
            _loading = false;
            _cardPresent = readers.Count > 0 && _pc.Atr(Reader) != null;
            UpdateCardLabel();
        }
        catch (Exception ex) { ShowError(ex); }
    }

    private void Refresh_Click(object s, RoutedEventArgs e) => Refresh();
    private void CmbReader_Changed(object s, SelectionChangedEventArgs e) { if (!_loading) Refresh(); }

    private void ShowError(Exception ex) =>
        MessageBox.Show(this, ex.Message, Loc.T("error"), MessageBoxButton.OK, MessageBoxImage.Warning);

    // ---------- personal ----------
    private void Read_Click(object s, RoutedEventArgs e)
    {
        try
        {
            Mouse.OverrideCursor = Cursors.Wait;
            _personal = SerbianCard.ReadPersonalData(_pc, Reader);
            _sig = null;
            RenderPersonal(); RenderSig();
        }
        catch (Exception ex) { ShowError(ex); }
        finally { Mouse.OverrideCursor = null; }
    }

    internal static List<(string Key, string Value)> Rows(PersonalData p)
    {
        var f = p.Fixed; var d = p.Document;
        var rows = new List<(string, string)>
        {
            ("surname", f.Surname), ("givenName", f.GivenName),
        };
        if (p.CardType == CardType.ID2014 && f.ParentGivenName.Length > 0) rows.Add(("parentName", f.ParentGivenName));
        rows.Add(("dob", f.DateOfBirth)); rows.Add(("sex", f.Sex));
        rows.Add(("placeOfBirth", string.Join(", ", new[] { f.PlaceOfBirth, f.CommunityOfBirth, f.StateOfBirth }.Where(x => x.Length > 0))));
        if (f.NationalityFull.Length > 0) rows.Add(("nationality", f.NationalityFull));
        rows.Add(("jmbg", f.PersonalNumber)); rows.Add(("address", p.Variable.Formatted));
        rows.Add(("docNumber", d.DocRegNo));
        if (d.DocumentSerialNumber.Length > 0) rows.Add(("docSerial", d.DocumentSerialNumber));
        rows.Add(("issuedBy", d.IssuingAuthority)); rows.Add(("issueDate", d.IssuingDate)); rows.Add(("expiryDate", d.ExpiryDate));
        return rows;
    }

    private void RenderPersonal()
    {
        FieldsGrid.RowDefinitions.Clear();
        FieldsGrid.Children.Clear();
        ImgPortrait.Source = null;
        BtnPrint.IsEnabled = _personal != null;
        if (_personal == null) return;

        int i = 0;
        foreach (var (key, value) in Rows(_personal))
        {
            FieldsGrid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            var k = new TextBlock { Text = Loc.T(key), Foreground = Brushes.Gray, Margin = new Thickness(0, 3, 8, 3) };
            var v = new TextBox { Text = value, IsReadOnly = true, BorderThickness = new Thickness(0), Background = Brushes.Transparent, Margin = new Thickness(0, 3, 0, 3), TextWrapping = TextWrapping.Wrap };
            Grid.SetRow(k, i); Grid.SetColumn(k, 0); Grid.SetRow(v, i); Grid.SetColumn(v, 1);
            FieldsGrid.Children.Add(k); FieldsGrid.Children.Add(v);
            i++;
        }
        ImgPortrait.Source = LoadImage(_personal.Portrait);
    }

    internal static BitmapImage LoadImage(byte[] jpeg)
    {
        if (jpeg == null || jpeg.Length == 0) return null;
        var bi = new BitmapImage();
        bi.BeginInit();
        bi.CacheOption = BitmapCacheOption.OnLoad;
        bi.StreamSource = new MemoryStream(jpeg);
        bi.EndInit();
        bi.Freeze();
        return bi;
    }

    // ---------- signature ----------
    private void Verify_Click(object s, RoutedEventArgs e)
    {
        try
        {
            Mouse.OverrideCursor = Cursors.Wait;
            var a = SerbianCard.Verify(_pc, Reader, SerbianCard.Block.Fixed);
            var b = SerbianCard.Verify(_pc, Reader, SerbianCard.Block.Variable);
            _sig = a.Result == SigResult.Invalid ? a : b.Result == SigResult.Invalid ? b
                 : a.Result == SigResult.ChainNotTrusted ? a : b;
            RenderSig();
        }
        catch (Exception ex) { ShowError(ex); }
        finally { Mouse.OverrideCursor = null; }
    }

    private void RenderSig()
    {
        if (_sig == null) { LblSig.Text = ""; return; }
        (LblSig.Text, LblSig.Foreground) = _sig.Result switch
        {
            SigResult.Ok => ("✔ " + Loc.T("sigOk"), Brushes.Green),
            SigResult.ChainNotTrusted => ("⚠ " + Loc.T("sigChain"), Brushes.DarkOrange),
            _ => ("✘ " + Loc.T("sigBad"), Brushes.Red),
        };
    }

    // ---------- token ----------
    private void ReadToken_Click(object s, RoutedEventArgs e)
    {
        try
        {
            Mouse.OverrideCursor = Cursors.Wait;
            _token = SerbianCard.ReadToken(_pc, Reader);
            RenderToken();
        }
        catch (Exception ex) { ShowError(ex); }
        finally { Mouse.OverrideCursor = null; }
    }

    private void RenderToken()
    {
        LstCerts.Items.Clear();
        LblTokenInfo.Text = _token == null ? "" : $"{_token.Label} {_token.Serial}";
        if (_token == null) return;
        foreach (var c in _token.Certificates)
        {
            var title = c.Label.Length > 0 ? c.Label : c.Subject;
            var status = c.ChainTrusted ? "✔ " + Loc.T("chainOk") : "⚠ " + Loc.T("sigChain");
            var panel = new StackPanel();
            panel.Children.Add(new TextBlock { Text = title });
            panel.Children.Add(new TextBlock { Text = status, FontSize = 11, Foreground = c.ChainTrusted ? Brushes.Green : Brushes.DarkOrange });
            LstCerts.Items.Add(panel);
        }
    }

    // ---------- print ----------
    private void Print_Click(object s, RoutedEventArgs e)
    {
        if (_personal == null) return;
        var dlg = new PrintDialog();
        if (dlg.ShowDialog() != true) return;
        var sheet = PrintSheet.Build(_personal, dlg.PrintableAreaWidth, dlg.PrintableAreaHeight);
        dlg.PrintVisual(sheet, "SerbiaID");
    }
}

internal static class PrintSheet
{
    public static FrameworkElement Build(PersonalData p, double w, double h)
    {
        var root = new Grid { Width = w, Height = h, Background = Brushes.White };
        var stack = new StackPanel { Margin = new Thickness(40) };
        stack.Children.Add(new TextBlock { Text = Loc.T("appTitle"), FontSize = 20, FontWeight = FontWeights.Bold, Margin = new Thickness(0, 0, 0, 14) });
        var body = new DockPanel();
        var img = new Image { Source = MainWindow.LoadImage(p.Portrait), Width = 120, Height = 150, Margin = new Thickness(0, 0, 24, 0), VerticalAlignment = VerticalAlignment.Top };
        DockPanel.SetDock(img, Dock.Left);
        body.Children.Add(img);
        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(160) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        int i = 0;
        foreach (var (key, value) in MainWindow.Rows(p))
        {
            grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            var k = new TextBlock { Text = Loc.T(key), Foreground = Brushes.Gray, FontSize = 12, Margin = new Thickness(0, 3, 0, 3) };
            var v = new TextBlock { Text = value, FontSize = 12, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 3, 0, 3) };
            Grid.SetRow(k, i); Grid.SetRow(v, i); Grid.SetColumn(v, 1);
            grid.Children.Add(k); grid.Children.Add(v);
            i++;
        }
        body.Children.Add(grid);
        stack.Children.Add(body);
        stack.Children.Add(new TextBlock { Text = DateTime.Now.ToString("g"), FontSize = 10, Foreground = Brushes.Gray, Margin = new Thickness(0, 24, 0, 0) });
        root.Children.Add(stack);
        root.Measure(new Size(w, h));
        root.Arrange(new Rect(0, 0, w, h));
        return root;
    }
}
