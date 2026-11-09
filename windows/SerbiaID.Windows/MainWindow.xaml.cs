using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Microsoft.Win32;

namespace SerbiaID;

public partial class MainWindow : Window
{
    private readonly PcscService _pc = new();
    private PersonalData _personal;
    private TokenInfo _token;
    private SigStatus _sig;
    private UpdateInfo _update;
    private bool _loading = true;
    private bool _cardPresent;

    public MainWindow()
    {
        InitializeComponent();
        foreach (var l in Enum.GetValues<Lang>()) CmbLang.Items.Add(l switch { Lang.ru => "Русский", Lang.en => "English", _ => "Srpski" });
        CmbLang.SelectedIndex = (int)Loc.Current;
        _loading = false;
        ApplyLanguage();
        Refresh();
        Loaded += async (_, _) => await AutoCheckUpdateAsync();
    }

    protected override void OnClosed(EventArgs e) { _pc.Dispose(); base.OnClosed(e); }

    private string Reader => CmbReader.SelectedItem as string;
    private Brush B(string key) => (Brush)FindResource(key);

    // ---------- demo / screenshot (fictional data) ----------
    internal void LoadDemo(int tab)
    {
        _cardPresent = true; UpdateCardLabel();
        CmbReader.Items.Clear(); CmbReader.Items.Add("Demo Reader"); CmbReader.SelectedIndex = 0;
        _personal = new PersonalData
        {
            CardType = CardType.RP2024,
            Document = new DocumentData { DocRegNo = "001234567", DocumentSerialNumber = "RS1234567", IssuingAuthority = "MUP RS", IssuingDate = "01.01.2024", ExpiryDate = "01.01.2027" },
            Fixed = new FixedPersonalData { Surname = "PETROVIĆ", GivenName = "MARKO", Sex = "M", DateOfBirth = "01.01.1990", StateOfBirth = "Srbija", PersonalNumber = "0101990710000", NationalityFull = "Srbija" },
            Variable = new VariablePersonalData { Place = "Beograd", Community = "Stari Grad", Street = "Knez Mihailova", HouseNumber = "1" },
        };
        _sig = new SigStatus { Result = SigResult.Ok };
        _token = new TokenInfo { Label = "NetSeT's CardEdge Token", Serial = "RP000000000" };
        _token.Certificates.Add(new TokenCertificate { Label = "MARKO PETROVIC 000000000 Auth", ChainTrusted = true });
        Tabs.SelectedIndex = tab;
        ApplyLanguage();
    }

    internal void ExportDemoPdf(string path) => PdfWriter.SaveSheet(PrintSheet.Build(_personal, 793.7, 1122.5), path);

    internal void SaveScreenshot(string path)
    {
        UpdateLayout();
        var el = (FrameworkElement)Content;
        var rtb = new RenderTargetBitmap((int)ActualWidth, (int)ActualHeight, 96, 96, PixelFormats.Pbgra32);
        rtb.Render(el);
        var enc = new PngBitmapEncoder(); enc.Frames.Add(BitmapFrame.Create(rtb));
        using var fs = File.Create(path); enc.Save(fs);
    }

    // ---------- pills ----------
    private void SetPill(Border pill, TextBlock label, string text, string fg, string bg)
    {
        label.Text = text; label.Foreground = B(fg); pill.Background = B(bg); pill.Visibility = Visibility.Visible;
    }

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
        LblBrand.Text = Loc.T("appTitle");
        LblBrandSub.Text = Loc.T("brandSub");
        BtnRefresh.Content = Loc.T("refresh");
        BtnRead.Content = Loc.T("readCard");
        BtnPrint.Content = Loc.T("printCard");
        BtnPdf.Content = Loc.T("savePdf");
        BtnVerify.Content = Loc.T("verifySignature");
        BtnReadToken.Content = Loc.T("readToken");
        BtnCheckUpdates.Content = Loc.T("checkUpdates");
        BtnUpdate.Content = Loc.T("updateNow");
        TabPersonal.Header = Loc.T("tabPersonal");
        TabToken.Header = Loc.T("tabToken");
        TabAbout.Header = Loc.T("tabAbout");
        LblCerts.Text = Loc.T("certificates");
        LblPinNote.Text = Loc.T("pinNote");
        LblHint.Text = Loc.T("hintRead");
        LblAboutTitle.Text = Loc.T("appTitle");
        LblAboutText.Text = Loc.T("aboutText");
        LblVersion.Text = $"{Loc.T("version")} {Updater.CurrentText}";
        if (_update != null) LblUpdate.Text = string.Format(Loc.T("updateAvailable"), _update.Version.ToString(3));
        UpdateCardLabel();
        RenderPersonal();
        RenderSig();
        RenderToken();
    }

    // ---------- readers ----------
    private void UpdateCardLabel()
    {
        DotCard.Fill = B(_cardPresent ? "OkBrush" : "MutedBrush");
        LblCard.Text = _cardPresent ? Loc.T("cardPresent") : Loc.T("noCard");
        LblCard.Foreground = B(_cardPresent ? "OkBrush" : "MutedBrush");
        PillCard.Background = B(_cardPresent ? "OkBgBrush" : "BgBrush");
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
        catch (Exception ex) { ShowError(ex.Message); }
    }

    private void Refresh_Click(object s, RoutedEventArgs e) => Refresh();
    private void CmbReader_Changed(object s, SelectionChangedEventArgs e) { if (!_loading) Refresh(); }

    private void ShowError(string msg) =>
        MessageBox.Show(this, msg, Loc.T("error"), MessageBoxButton.OK, MessageBoxImage.Warning);

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
        catch (Exception ex) { ShowError(ex.Message); }
        finally { Mouse.OverrideCursor = null; }
    }

    internal static List<(string Key, string Value)> Rows(PersonalData p)
    {
        var f = p.Fixed; var d = p.Document;
        var rows = new List<(string, string)> { ("surname", f.Surname), ("givenName", f.GivenName) };
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

    internal static string DocTypeName(CardType t) =>
        Loc.T(t switch { CardType.IF2020 => "docIF", CardType.RP2024 => "docRP", _ => "docID" });

    private void RenderPersonal()
    {
        FieldsPanel.Children.Clear();
        ImgPortrait.Source = null;
        bool has = _personal != null;
        BtnPrint.IsEnabled = has; BtnPdf.IsEnabled = has;
        PersonalContent.Visibility = has ? Visibility.Visible : Visibility.Collapsed;
        LblHint.Visibility = has ? Visibility.Collapsed : Visibility.Visible;
        if (!has) return;

        LblName.Text = $"{_personal.Fixed.GivenName} {_personal.Fixed.Surname}".Trim();
        LblDocType.Text = DocTypeName(_personal.CardType);
        ImgPortrait.Source = LoadImage(_personal.Portrait);

        foreach (var (key, value) in Rows(_personal))
        {
            var cell = new StackPanel { Width = 280, Margin = new Thickness(0, 0, 18, 16) };
            cell.Children.Add(new TextBlock { Text = Loc.T(key), FontSize = 11, Foreground = B("MutedBrush"), Margin = new Thickness(0, 0, 0, 2) });
            cell.Children.Add(new TextBox
            {
                Text = value, IsReadOnly = true, BorderThickness = new Thickness(0), Background = Brushes.Transparent,
                FontSize = 14, FontWeight = FontWeights.SemiBold, Foreground = B("TextBrush"), TextWrapping = TextWrapping.Wrap, Padding = new Thickness(0),
            });
            FieldsPanel.Children.Add(cell);
        }
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
        catch (Exception ex) { ShowError(ex.Message); }
        finally { Mouse.OverrideCursor = null; }
    }

    private void RenderSig()
    {
        if (_sig == null) { PillSig.Visibility = Visibility.Collapsed; return; }
        switch (_sig.Result)
        {
            case SigResult.Ok: SetPill(PillSig, LblSig, "✔  " + Loc.T("sigOk"), "OkBrush", "OkBgBrush"); break;
            case SigResult.ChainNotTrusted: SetPill(PillSig, LblSig, "⚠  " + Loc.T("sigChain"), "WarnBrush", "WarnBgBrush"); break;
            default: SetPill(PillSig, LblSig, "✘  " + Loc.T("sigBad"), "BadBrush", "BadBgBrush"); break;
        }
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
        catch (Exception ex) { ShowError(ex.Message); }
        finally { Mouse.OverrideCursor = null; }
    }

    private void RenderToken()
    {
        LstCerts.Items.Clear();
        LblTokenInfo.Text = _token == null ? "" : $"{_token.Label}  {_token.Serial}".Trim();
        if (_token == null) return;
        foreach (var c in _token.Certificates)
        {
            var row = new DockPanel { Margin = new Thickness(0, 0, 0, 10) };
            var pill = new Border { CornerRadius = new CornerRadius(12), Padding = new Thickness(10, 4, 10, 4), VerticalAlignment = VerticalAlignment.Center };
            var pt = new TextBlock { FontSize = 12, FontWeight = FontWeights.SemiBold };
            SetPill(pill, pt, c.ChainTrusted ? "✔  " + Loc.T("chainOk") : "⚠  " + Loc.T("sigChain"),
                    c.ChainTrusted ? "OkBrush" : "WarnBrush", c.ChainTrusted ? "OkBgBrush" : "WarnBgBrush");
            pill.Child = pt;
            DockPanel.SetDock(pill, Dock.Right);
            row.Children.Add(pill);
            row.Children.Add(new TextBlock { Text = c.Label.Length > 0 ? c.Label : c.Subject, FontSize = 14, FontWeight = FontWeights.SemiBold, VerticalAlignment = VerticalAlignment.Center });
            LstCerts.Items.Add(new Border { BorderBrush = B("LineBrush"), BorderThickness = new Thickness(0, 0, 0, 1), Padding = new Thickness(0, 0, 0, 10), Child = row });
        }
    }

    // ---------- print / PDF ----------
    private void Print_Click(object s, RoutedEventArgs e)
    {
        if (_personal == null) return;
        var dlg = new PrintDialog();
        if (dlg.ShowDialog() != true) return;
        var sheet = PrintSheet.Build(_personal, dlg.PrintableAreaWidth, dlg.PrintableAreaHeight);
        dlg.PrintVisual(sheet, "Super Celik");
    }

    private void Pdf_Click(object s, RoutedEventArgs e)
    {
        if (_personal == null) return;
        var dlg = new SaveFileDialog { Filter = "PDF (*.pdf)|*.pdf", FileName = "SuperCelik.pdf", DefaultExt = ".pdf" };
        if (dlg.ShowDialog(this) != true) return;
        try
        {
            Mouse.OverrideCursor = Cursors.Wait;
            PdfWriter.SaveSheet(PrintSheet.Build(_personal, 793.7, 1122.5), dlg.FileName);   // A4 @ 96 dpi
            MessageBox.Show(this, $"{Loc.T("pdfSaved")}:\n{dlg.FileName}", Loc.T("appTitle"), MessageBoxButton.OK, MessageBoxImage.Information);
        }
        catch (Exception ex) { ShowError(ex.Message); }
        finally { Mouse.OverrideCursor = null; }
    }

    // ---------- updates ----------
    private async Task AutoCheckUpdateAsync()
    {
        try
        {
            var (info, _) = await Updater.CheckAsync();
            if (info == null) return;
            _update = info;
            LblUpdate.Text = string.Format(Loc.T("updateAvailable"), info.Version.ToString(3));
            UpdateBanner.Visibility = Visibility.Visible;
        }
        catch { /* offline: stay silent */ }
    }

    private async void CheckUpdates_Click(object s, RoutedEventArgs e)
    {
        LblUpdateStatus.Text = "…";
        try
        {
            var (info, reachable) = await Updater.CheckAsync();
            if (!reachable) { LblUpdateStatus.Text = Loc.T("updateUnavailable"); return; }
            if (info == null) { LblUpdateStatus.Text = Loc.T("upToDate"); return; }
            _update = info;
            LblUpdate.Text = string.Format(Loc.T("updateAvailable"), info.Version.ToString(3));
            UpdateBanner.Visibility = Visibility.Visible;
            LblUpdateStatus.Text = LblUpdate.Text;
        }
        catch { LblUpdateStatus.Text = Loc.T("updateUnavailable"); }
    }

    private async void Update_Click(object s, RoutedEventArgs e)
    {
        if (_update == null) return;
        BtnUpdate.IsEnabled = false;
        LblUpdate.Text = Loc.T("updateDownloading");
        try
        {
            var path = await Updater.DownloadAsync(_update);
            Updater.RunInstaller(path);
            Application.Current.Shutdown();
        }
        catch (Exception ex)
        {
            BtnUpdate.IsEnabled = true;
            LblUpdate.Text = string.Format(Loc.T("updateAvailable"), _update.Version.ToString(3));
            ShowError($"{Loc.T("updateFailed")}: {ex.Message}");
        }
    }
}

internal static class PrintSheet
{
    public static FrameworkElement Build(PersonalData p, double w, double h)
    {
        var root = new Grid { Width = w, Height = h, Background = Brushes.White };
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });

        // flag-colored strip: red / blue / white
        var strip = new Grid { Height = 10 };
        foreach (var c in new[] { "#C6363C", "#0C4076", "#E3E7EE" })
        {
            strip.ColumnDefinitions.Add(new ColumnDefinition());
            var r = new Border { Background = (Brush)new BrushConverter().ConvertFromString(c) };
            Grid.SetColumn(r, strip.ColumnDefinitions.Count - 1);
            strip.Children.Add(r);
        }
        root.Children.Add(strip);

        var stack = new StackPanel { Margin = new Thickness(48, 36, 48, 36) };
        Grid.SetRow(stack, 1);
        stack.Children.Add(new TextBlock { Text = MainWindow.DocTypeName(p.CardType), FontSize = 22, FontWeight = FontWeights.Bold, Foreground = (Brush)new BrushConverter().ConvertFromString("#0C4076") });
        stack.Children.Add(new TextBlock { Text = $"{p.Fixed.GivenName} {p.Fixed.Surname}".Trim(), FontSize = 15, Foreground = Brushes.Gray, Margin = new Thickness(0, 2, 0, 22) });

        var body = new DockPanel();
        var img = new Image { Source = MainWindow.LoadImage(p.Portrait), Width = 130, Height = 165, Stretch = Stretch.UniformToFill, Margin = new Thickness(0, 0, 28, 0), VerticalAlignment = VerticalAlignment.Top };
        DockPanel.SetDock(img, Dock.Left);
        body.Children.Add(img);

        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(165) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        int i = 0;
        foreach (var (key, value) in MainWindow.Rows(p))
        {
            grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            var k = new TextBlock { Text = Loc.T(key), Foreground = Brushes.Gray, FontSize = 12, Margin = new Thickness(0, 5, 0, 5) };
            var v = new TextBlock { Text = value, FontSize = 13, FontWeight = FontWeights.SemiBold, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 5, 0, 5) };
            Grid.SetRow(k, i); Grid.SetRow(v, i); Grid.SetColumn(v, 1);
            grid.Children.Add(k); grid.Children.Add(v);
            i++;
        }
        body.Children.Add(grid);
        stack.Children.Add(body);
        stack.Children.Add(new TextBlock { Text = $"Super Celik · {DateTime.Now:g}", FontSize = 10, Foreground = Brushes.Gray, Margin = new Thickness(0, 30, 0, 0) });
        root.Children.Add(stack);
        root.Measure(new Size(w, h));
        root.Arrange(new Rect(0, 0, w, h));
        return root;
    }
}
