using System.Globalization;
using System.Text;
using System.Text.Json;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using Microsoft.Win32;

namespace SerbiaID;

public partial class MainWindow : Window
{
    private readonly PcscService _pc = new();
    private readonly AppSettings _cfg = AppSettings.Load();
    private PersonalData _personal;
    private TokenInfo _token;
    private SigStatus _sig;
    private UpdateInfo _update;
    private List<string> _readers = new();
    private bool _revealAll;     // one global eye: show / hide all sensitive fields
    private bool _loading = true, _cardPresent, _busy, _demo;
    private DateTime _lastActivity = DateTime.Now;
    private readonly DispatcherTimer _poll = new() { Interval = TimeSpan.FromMilliseconds(1500) };
    private readonly DispatcherTimer _idle = new() { Interval = TimeSpan.FromSeconds(15) };

    private static readonly string[] Sensitive = { "jmbg", "address", "docNumber", "docSerial" };

    public MainWindow()
    {
        InitializeComponent();
        _cfg.Lang ??= AppSettings.InstallerLang();
        if (_cfg.Lang != null && Enum.TryParse<Lang>(_cfg.Lang, out var l)) Loc.Current = l;
        Theme.Apply(_cfg.Theme);
        RestoreWindow();

        foreach (var lang in Enum.GetValues<Lang>()) CmbLang.Items.Add(lang switch { Lang.ru => "Русский", Lang.en => "English", Lang.sr => "Srpski (latinica)", _ => "Српски (ћирилица)" });
        CmbLang.SelectedIndex = (int)Loc.Current;
        for (int i = 0; i < 3; i++) CmbTheme.Items.Add("");
        CmbTheme.SelectedIndex = _cfg.Theme switch { "light" => 1, "dark" => 2, _ => 0 };
        ChkMask.IsChecked = _cfg.MaskSensitive; ChkPrintJmbg.IsChecked = _cfg.PrintJmbg;
        ChkAutoRead.IsChecked = _cfg.AutoRead; ChkAutoUpdate.IsChecked = _cfg.AutoUpdate;
        TxtAutoHide.Text = _cfg.AutoHideMinutes.ToString();
        Tabs.SelectedIndex = Math.Clamp(_cfg.Tab, 0, Tabs.Items.Count - 1);
        _loading = false;

        ApplyLanguage();
        Refresh();
        _poll.Tick += (_, _) => Poll(); _poll.Start();
        _idle.Tick += (_, _) => CheckIdle(); _idle.Start();
        PreviewMouseMove += (_, _) => _lastActivity = DateTime.Now;
        PreviewKeyDown += (_, _) => _lastActivity = DateTime.Now;
        PreviewMouseDown += (_, _) => _lastActivity = DateTime.Now;
        Loaded += async (_, _) => { if (_cfg.AutoUpdate && !_demo) await AutoCheckUpdateAsync(); };
    }

    protected override void OnClosing(System.ComponentModel.CancelEventArgs e)
    {
        if (!_demo)
        {
            _cfg.Tab = Tabs.SelectedIndex;
            if (WindowState == WindowState.Normal) { _cfg.WindowWidth = Width; _cfg.WindowHeight = Height; _cfg.WindowLeft = Left; _cfg.WindowTop = Top; }
            _cfg.Save();
        }
        base.OnClosing(e);
    }

    protected override void OnClosed(EventArgs e) { _poll.Stop(); _idle.Stop(); _pc.Dispose(); base.OnClosed(e); }

    private void RestoreWindow()
    {
        if (_cfg.WindowWidth >= MinWidth && _cfg.WindowHeight >= MinHeight) { Width = _cfg.WindowWidth; Height = _cfg.WindowHeight; }
        if (!double.IsNaN(_cfg.WindowLeft) && !double.IsNaN(_cfg.WindowTop) &&
            _cfg.WindowLeft > SystemParameters.VirtualScreenLeft - 50 && _cfg.WindowLeft < SystemParameters.VirtualScreenWidth - 100 &&
            _cfg.WindowTop > SystemParameters.VirtualScreenTop - 10 && _cfg.WindowTop < SystemParameters.VirtualScreenHeight - 100)
        {
            WindowStartupLocation = WindowStartupLocation.Manual; Left = _cfg.WindowLeft; Top = _cfg.WindowTop;
        }
    }

    private string Reader => CmbReader.SelectedItem as string;
    private Brush B(string key) => (Brush)FindResource(key);

    // ---------- small UI helpers ----------
    private void SetPill(Border pill, TextBlock label, string text, string fg, string bg)
    {
        label.Text = text; label.Foreground = B(fg); pill.Background = B(bg); pill.Visibility = Visibility.Visible;
    }

    private static TextBlock Glyph(string g, double size = 15) => new()
    {
        Text = g, FontFamily = new FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets"), FontSize = size, VerticalAlignment = VerticalAlignment.Center,
    };

    private static void SetBtn(Button b, string glyph, string text)
    {
        var sp = new StackPanel { Orientation = Orientation.Horizontal };
        var g = Glyph(glyph); g.Width = 20; g.TextAlignment = TextAlignment.Center; g.Margin = new Thickness(0, 0, 8, 0);
        sp.Children.Add(g);
        sp.Children.Add(new TextBlock { Text = text, VerticalAlignment = VerticalAlignment.Center });
        b.Content = sp;
        AutomationProperties.SetName(b, text);
    }

    private Button IconBtn(string glyph, string tip)
    {
        var b = new Button { Style = (Style)FindResource("IconButton"), Content = Glyph(glyph, 14), ToolTip = tip, Margin = new Thickness(2, 0, 0, 0) };
        AutomationProperties.SetName(b, tip);
        return b;
    }

    private void Flash(Button b)
    {
        var old = b.Content; b.Content = Glyph("", 14);
        var t = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
        t.Tick += (_, _) => { t.Stop(); b.Content = old; }; t.Start();
    }

    private void Tabs_SelectionChanged(object s, SelectionChangedEventArgs e)
    {
        // SelectionChanged bubbles up from the combo boxes inside the tabs too
        if (!ReferenceEquals(e.OriginalSource, Tabs) || _loading) return;
        if (Tabs.SelectedContent is FrameworkElement page) Fx.FadeIn(page, 6, 180);
    }

    // ---------- language ----------
    private void Lang_Changed(object s, SelectionChangedEventArgs e)
    {
        if (_loading || CmbLang.SelectedIndex < 0) return;
        Loc.Current = (Lang)CmbLang.SelectedIndex;
        _cfg.Lang = Loc.Current.ToString(); _cfg.Save();
        ApplyLanguage();
    }

    private void ApplyLanguage()
    {
        Title = Loc.T("appTitle");
        BtnRefresh.Content = Glyph("", 15); BtnRefresh.ToolTip = Loc.T("refresh"); AutomationProperties.SetName(BtnRefresh, Loc.T("refresh"));
        SetBtn(BtnRead, "", Loc.T("readCard"));
        SetBtn(BtnReadBig, "", Loc.T("readCard"));
        SetBtn(BtnPrint, "", Loc.T("printCard"));
        SetBtn(BtnPdf, "", Loc.T("savePdf"));
        SetBtn(BtnVerify, "", Loc.T("verifySignature"));
        SetBtn(BtnMore, "", Loc.T("more"));
        SetBtn(BtnReadToken, "", Loc.T("readToken"));
        SetBtn(BtnChangePin, "\uE72E", Loc.T("changePin"));
        SetBtn(BtnUnblockPin, "\uE785", Loc.T("unblockPin"));
        SetBtn(BtnSignFile, "\uE70F", Loc.T("signFile"));
        SetBtn(BtnCheckUpdates, "", Loc.T("checkUpdates"));
        SetBtn(BtnUpdate, "", Loc.T("updateNow"));
        BtnProblemClose.Content = Glyph("", 12); AutomationProperties.SetName(BtnProblemClose, Loc.T("close"));
        TabPersonal.Header = Loc.T("tabPersonal");
        TabToken.Header = Loc.T("tabToken");
        TabSettings.Header = Loc.T("tabSettings");
        TabAbout.Header = Loc.T("tabAbout");
        LblCerts.Text = Loc.T("certificates");
        LblPinNote.Text = Loc.T("pinNote");
        LblAboutTitle.Text = Loc.T("appTitle");
        LblAboutText.Text = Loc.T("aboutText");
        LblVersion.Text = $"{Loc.T("version")} {Updater.CurrentText}";
        LblSetLang.Text = Loc.T("language");
        LblSetAppearance.Text = Loc.T("setAppearance"); LblSetTheme.Text = Loc.T("setTheme");
        LblSetPrivacy.Text = Loc.T("setPrivacy"); LblSetBehavior.Text = Loc.T("setBehavior");
        ChkMask.Content = Loc.T("setMask"); ChkPrintJmbg.Content = Loc.T("setPrintJmbg");
        ChkAutoRead.Content = Loc.T("setAutoRead"); ChkAutoUpdate.Content = Loc.T("setAutoUpdate");
        LblSetAutoHide.Text = Loc.T("setAutoHide");
        _loading = true;
        var ti = CmbTheme.SelectedIndex;
        CmbTheme.Items.Clear();
        foreach (var k in new[] { "themeSystem", "themeLight", "themeDark" }) CmbTheme.Items.Add(Loc.T(k));
        CmbTheme.SelectedIndex = ti < 0 ? 0 : ti;
        _loading = false;
        BuildMoreMenu();
        if (_update != null) LblUpdate.Text = string.Format(Loc.T("updateAvailable"), _update.Version.ToString(3));
        UpdateCardLabel();
        RenderAll();
    }

    private void RenderAll() { RenderPersonal(); RenderSig(); RenderToken(); UpdateEnabled(); }

    // ---------- busy / errors ----------
    private void UpdateEnabled()
    {
        BtnRead.IsEnabled = BtnReadBig.IsEnabled = _cardPresent && !_busy;
        BtnReadToken.IsEnabled = _cardPresent && !_busy;
        BtnChangePin.IsEnabled = BtnUnblockPin.IsEnabled = BtnSignFile.IsEnabled = _cardPresent && !_busy;
        BtnVerify.IsEnabled = _cardPresent && !_busy;
        bool has = _personal != null && !_busy;
        BtnPrint.IsEnabled = has; BtnPdf.IsEnabled = has; BtnMore.IsEnabled = has;
    }

    private async Task Run(Func<Task> work)
    {
        if (_busy) return;
        _busy = true; BusyBar.Visibility = Visibility.Visible; UpdateCardLabel();
        try { await work(); }
        catch (Exception ex) { ShowProblem(ex); }
        finally { _busy = false; BusyBar.Visibility = Visibility.Collapsed; UpdateCardLabel(); }
    }

    private void ShowProblem(Exception ex)
    {
        string t = "errGenericT", h = "errGenericH";
        if (ex is CardException ce)
        {
            if (ce.Code == Native.SCARD_E_NO_READERS_AVAILABLE) { t = "errNoReaderT"; h = "errNoReaderH"; }
            else if (ce.Code == Native.SCARD_E_NO_SMARTCARD || ce.Code == Native.SCARD_W_REMOVED_CARD || ce.Code == Native.SCARD_W_UNRESPONSIVE_CARD)
            { t = "errNoCardT"; h = "errNoCardH"; }
            else if (ce.Message.StartsWith("Unsupported card") || ce.Message.StartsWith("No token applet")) { t = "errUnsupportedT"; h = "errUnsupportedH"; }
        }
        ProblemBanner.Background = B("BadBgBrush"); LblProblemTitle.Foreground = B("BadBrush");
        LblProblemTitle.Text = Loc.T(t); LblProblemHint.Text = Loc.T(h);
        LblProblemHint.Visibility = Visibility.Visible;
        LblProblemTech.Text = $"{Loc.T("techDetails")}: {ex.Message}";
        ShowBanner(error: true);
    }

    private bool _hasError;     // a red banner is showing: the mascot looks worried

    private void ShowBanner(bool error)
    {
        bool was = ProblemBanner.Visibility == Visibility.Visible;
        ProblemBanner.Visibility = Visibility.Visible;
        if (!was) Fx.FadeIn(ProblemBanner, -6, 200);
        _hasError = error;
        UpdateCardLabel();
    }

    private void ShowInfo(string text)
    {
        ProblemBanner.Background = B("BannerBrush"); LblProblemTitle.Foreground = B("TextBrush");
        LblProblemTitle.Text = text; LblProblemHint.Visibility = Visibility.Collapsed; LblProblemTech.Text = "";
        ShowBanner(error: false);
    }

    private void HideProblem()
    {
        ProblemBanner.Visibility = Visibility.Collapsed;
        if (_hasError) { _hasError = false; UpdateCardLabel(); }
    }
    private void ProblemClose_Click(object s, RoutedEventArgs e) => HideProblem();

    // ---------- readers + automatic card detection ----------
    private ReaderMood Mood =>
        _busy ? ReaderMood.Busy : _readers.Count == 0 ? ReaderMood.NoReader : _hasError ? ReaderMood.Error
        : _cardPresent ? ReaderMood.Ready : ReaderMood.Waiting;

    /// One place for the reader / card status: the face and the line in the header, and the empty state of the first tab.
    private void UpdateCardLabel()
    {
        var mood = Mood;
        LblCard.Text = Loc.T(_busy ? "statusReading" : _readers.Count == 0 ? "noReader" : _cardPresent ? "cardPresent" : "noCard");
        // one reader: its name as plain text; several: a list to choose from; none: nothing (the line above says it)
        LblReader.Text = _readers.Count == 1 ? _readers[0] : "";
        LblReader.Visibility = _readers.Count == 1 ? Visibility.Visible : Visibility.Collapsed;
        CmbReader.Visibility = _readers.Count > 1 ? Visibility.Visible : Visibility.Collapsed;
        Mascot.Set(mood, _cardPresent);

        // the empty state tells what to do next (the status itself is in the header)
        EmptyMascot.Set(mood, _cardPresent);
        string title = mood switch
        {
            ReaderMood.Busy => "statusReading",
            ReaderMood.NoReader => "emptyNoReaderT",
            _ => _cardPresent ? "emptyReadyT" : "emptyNoCardT",
        };
        string hint = mood switch
        {
            ReaderMood.Busy => null,
            ReaderMood.NoReader => "emptyNoReaderH",
            _ => _cardPresent ? "emptyReadyH" : "emptyNoCardH",
        };
        LblEmptyTitle.Text = Loc.T(title);
        LblHint.Text = hint == null ? "" : Loc.T(hint);
        bool canRead = _cardPresent && !_busy;
        if (canRead && BtnReadBig.Visibility != Visibility.Visible && EmptyState.Visibility == Visibility.Visible) Fx.Pop(BtnReadBig);
        BtnReadBig.Visibility = canRead ? Visibility.Visible : Visibility.Hidden;
        UpdateEnabled();
    }

    private void FillReaders(List<string> readers)
    {
        var prev = Reader;
        _loading = true;
        CmbReader.Items.Clear();
        foreach (var r in readers) CmbReader.Items.Add(r);
        if (readers.Count == 0) CmbReader.Items.Add(Loc.T("noReader"));
        CmbReader.SelectedItem = prev != null && readers.Contains(prev) ? prev : CmbReader.Items[0];
        _loading = false;
        _readers = readers;
    }

    private void Refresh()
    {
        try
        {
            FillReaders(_pc.ListReaders());
            _cardPresent = _readers.Count > 0 && _pc.Atr(Reader) != null;
            UpdateCardLabel();
            HideProblem();
        }
        catch (Exception ex) { ShowProblem(ex); }
    }

    private void Refresh_Click(object s, RoutedEventArgs e) => Refresh();
    private void CmbReader_Changed(object s, SelectionChangedEventArgs e) { if (!_loading) Refresh(); }

    /// Silent background check: reader list and card insert / remove.
    private async void Poll()
    {
        if (_busy || _demo) return;
        try
        {
            var readers = _pc.ListReaders();
            if (!readers.SequenceEqual(_readers)) { FillReaders(readers); UpdateCardLabel(); }
            bool present = _readers.Count > 0 && _pc.Atr(Reader) != null;
            if (present == _cardPresent) return;
            _cardPresent = present;
            UpdateCardLabel();
            if (present)
            {
                HideProblem();
                if (_cfg.AutoRead) await Run(ReadCardAsync);
            }
            else if (_personal != null || _token != null)
            {
                _personal = null; _token = null; _sig = null; _revealAll = false; RenderAll();   // privacy: drop data when the card is removed
            }
        }
        catch { /* reader unplugged mid-poll: the next tick or a manual refresh reports it */ }
    }

    private void CheckIdle()
    {
        if (_demo || _cfg.AutoHideMinutes <= 0 || (_personal == null && _token == null)) return;
        if ((DateTime.Now - _lastActivity).TotalMinutes < _cfg.AutoHideMinutes) return;
        _personal = null; _token = null; _sig = null; _revealAll = false;
        RenderAll();
        ShowInfo(Loc.T("autoHidden"));
    }

    // ---------- personal ----------
    private async Task ReadCardAsync()
    {
        var reader = Reader;
        var p = await Task.Run(() => SerbianCard.ReadPersonalData(_pc, reader));
        _personal = p; _sig = null; _revealAll = false; HideProblem();
        RenderAll();
    }

    private async void Read_Click(object s, RoutedEventArgs e) => await Run(ReadCardAsync);

    internal static List<(string Key, string Value)> Rows(PersonalData p, bool includeJmbg = true)
    {
        var f = p.Fixed; var d = p.Document;
        var rows = new List<(string, string)> { ("surname", f.Surname), ("givenName", f.GivenName) };
        if (p.CardType == CardType.ID2014 && f.ParentGivenName.Length > 0) rows.Add(("parentName", f.ParentGivenName));
        rows.Add(("dob", f.DateOfBirth)); rows.Add(("sex", f.Sex));
        rows.Add(("placeOfBirth", string.Join(", ", new[] { f.PlaceOfBirth, f.CommunityOfBirth, f.StateOfBirth }.Where(x => x.Length > 0))));
        if (f.NationalityFull.Length > 0) rows.Add(("nationality", f.NationalityFull));
        if (includeJmbg) rows.Add(("jmbg", f.PersonalNumber));
        rows.Add(("address", p.Variable.Formatted));
        rows.Add(("docNumber", d.DocRegNo));
        if (d.DocumentSerialNumber.Length > 0) rows.Add(("docSerial", d.DocumentSerialNumber));
        rows.Add(("issuedBy", d.IssuingAuthority)); rows.Add(("issueDate", d.IssuingDate)); rows.Add(("expiryDate", d.ExpiryDate));
        return rows;
    }

    internal static string DocTypeName(CardType t) =>
        Loc.T(t switch { CardType.IF2020 => "docIF", CardType.RP2024 => "docRP", _ => "docID" });

    private static bool TryDate(string s, out DateTime d) =>
        DateTime.TryParseExact(s, "dd.MM.yyyy", CultureInfo.InvariantCulture, DateTimeStyles.None, out d);

    private void SetExpiry(Border pill, TextBlock label, DateTime until)
    {
        int days = (until.Date - DateTime.Today).Days;
        if (days < 0) SetPill(pill, label, "✘  " + Loc.T("expiredOn"), "BadBrush", "BadBgBrush");
        else if (days <= 90) SetPill(pill, label, "⚠  " + string.Format(Loc.T("expiresIn"), days), "WarnBrush", "WarnBgBrush");
        else SetPill(pill, label, "✔  " + string.Format(Loc.T("expiresIn"), days), "OkBrush", "OkBgBrush");
    }

    private void UpdateEye()
    {
        BtnEye.Visibility = _personal != null && _cfg.MaskSensitive ? Visibility.Visible : Visibility.Collapsed;
        // eye = data is hidden (click to show); crossed eye = data is shown (click to hide)
        SetBtn(BtnEye, _revealAll ? "\uED1A" : "\uE7B3", _revealAll ? Loc.T("hideValue") : Loc.T("reveal"));
    }

    private void Eye_Click(object s, RoutedEventArgs e) { _revealAll = !_revealAll; RenderPersonal(); }

    private void RenderPersonal()
    {
        UpdateEye();
        FieldsPanel.Children.Clear();
        ImgPortrait.Source = null;
        bool has = _personal != null;
        bool appeared = has && PersonalContent.Visibility != Visibility.Visible;
        bool emptied = !has && EmptyState.Visibility != Visibility.Visible;
        PersonalContent.Visibility = has ? Visibility.Visible : Visibility.Collapsed;
        EmptyState.Visibility = has ? Visibility.Collapsed : Visibility.Visible;
        if (appeared) Fx.FadeIn(PersonalContent);
        if (emptied) Fx.FadeIn(EmptyState, 0);
        if (!has) return;

        LblName.Text = $"{_personal.Fixed.GivenName} {_personal.Fixed.Surname}".Trim();
        LblDocType.Text = DocTypeName(_personal.CardType);
        ImgPortrait.Source = LoadImage(_personal.Portrait);
        if (TryDate(_personal.Document.ExpiryDate, out var until)) SetExpiry(PillExpiry, LblExpiry, until);
        else PillExpiry.Visibility = Visibility.Collapsed;

        foreach (var (key, value) in Rows(_personal))
        {
            bool sensitive = Sensitive.Contains(key);
            bool hidden = sensitive && _cfg.MaskSensitive && !_revealAll;

            var cell = new DockPanel { Width = 290, Margin = new Thickness(0, 0, 14, 14) };
            var buttons = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Bottom };
            DockPanel.SetDock(buttons, Dock.Right);

            var copy = IconBtn("", Loc.T("copy"));
            var v = value;
            copy.Click += (_, _) => { try { Clipboard.SetText(v); } catch { } Flash(copy); };
            // quiet until needed: the copy button shows when the pointer is over the field (or it has keyboard focus)
            copy.Opacity = 0;
            cell.Background = Brushes.Transparent;      // so that the whole cell reacts to the pointer
            cell.MouseEnter += (_, _) => Fx.To(copy, OpacityProperty, 1, 120);
            cell.MouseLeave += (_, _) => { if (!copy.IsKeyboardFocused) Fx.To(copy, OpacityProperty, 0, 160); };
            copy.GotKeyboardFocus += (_, _) => Fx.To(copy, OpacityProperty, 1, 0);
            copy.LostKeyboardFocus += (_, _) => { if (!cell.IsMouseOver) Fx.To(copy, OpacityProperty, 0, 160); };
            buttons.Children.Add(copy);
            cell.Children.Add(buttons);

            var text = new StackPanel();
            text.Children.Add(new TextBlock { Text = Loc.T(key), FontSize = 11, Foreground = B("MutedBrush"), Margin = new Thickness(0, 0, 0, 2) });
            text.Children.Add(new TextBox
            {
                Text = hidden ? "••••••••••" : value, IsReadOnly = true, BorderThickness = new Thickness(0), Background = Brushes.Transparent,
                FontSize = 14, FontWeight = FontWeights.SemiBold, Foreground = B("TextBrush"), TextWrapping = TextWrapping.Wrap, Padding = new Thickness(0),
            });
            cell.Children.Add(text);
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

    // ---------- "More" menu: copy all / save photo / JSON ----------
    private void BuildMoreMenu()
    {
        MoreMenu.Items.Clear();
        MenuItem Item(string glyph, string text, RoutedEventHandler h)
        {
            var mi = new MenuItem { Header = text, Icon = Glyph(glyph, 14) };
            mi.Click += h; return mi;
        }
        MoreMenu.Items.Add(Item("", Loc.T("copyAll"), (_, _) => CopyAll()));
        MoreMenu.Items.Add(Item("", Loc.T("savePhoto"), (_, _) => SavePhoto()));
        MoreMenu.Items.Add(Item("", Loc.T("exportJson"), (_, _) => ExportJson()));
    }

    private void More_Click(object s, RoutedEventArgs e)
    {
        MoreMenu.PlacementTarget = BtnMore; MoreMenu.Placement = System.Windows.Controls.Primitives.PlacementMode.Bottom; MoreMenu.IsOpen = true;
    }

    private void CopyAll()
    {
        if (_personal == null) return;
        var sb = new StringBuilder();
        foreach (var (k, v) in Rows(_personal)) sb.AppendLine($"{Loc.T(k)}: {v}");
        try { Clipboard.SetText(sb.ToString()); ShowInfo(Loc.T("copied")); } catch (Exception ex) { ShowProblem(ex); }
    }

    private void SavePhoto()
    {
        if (_personal?.Portrait == null) return;
        var dlg = new SaveFileDialog { Filter = "JPEG (*.jpg)|*.jpg", FileName = "photo.jpg", DefaultExt = ".jpg" };
        if (dlg.ShowDialog(this) == true) File.WriteAllBytes(dlg.FileName, _personal.Portrait);
    }

    private void ExportJson()
    {
        if (_personal == null) return;
        var dlg = new SaveFileDialog { Filter = "JSON (*.json)|*.json", FileName = "SuperCelik.json", DefaultExt = ".json" };
        if (dlg.ShowDialog(this) != true) return;
        var obj = new Dictionary<string, string> { ["cardType"] = _personal.CardType.ToString() };
        foreach (var (k, v) in Rows(_personal)) obj[k] = v;
        File.WriteAllText(dlg.FileName, JsonSerializer.Serialize(obj, new JsonSerializerOptions { WriteIndented = true, Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping }));
    }

    // ---------- signature ----------
    private async void Verify_Click(object s, RoutedEventArgs e) => await Run(async () =>
    {
        var reader = Reader;
        var (a, b) = await Task.Run(() => (SerbianCard.Verify(_pc, reader, SerbianCard.Block.Fixed), SerbianCard.Verify(_pc, reader, SerbianCard.Block.Variable)));
        _sig = a.Result == SigResult.Invalid ? a : b.Result == SigResult.Invalid ? b
             : a.Result == SigResult.ChainNotTrusted ? a : b;
        HideProblem(); RenderSig();
    });

    private void RenderSig()
    {
        if (_sig == null) { PillSig.Visibility = Visibility.Collapsed; return; }
        bool wasShown = PillSig.Visibility == Visibility.Visible;
        try { RenderSigPill(); } finally { if (!wasShown) Fx.Pop(PillSig); }
    }

    private void RenderSigPill()
    {
        switch (_sig.Result)
        {
            case SigResult.Ok: SetPill(PillSig, LblSig, "✔  " + Loc.T("sigOk"), "OkBrush", "OkBgBrush"); break;
            case SigResult.ChainNotTrusted: SetPill(PillSig, LblSig, "⚠  " + Loc.T("sigChain"), "WarnBrush", "WarnBgBrush"); break;
            default: SetPill(PillSig, LblSig, "✘  " + Loc.T("sigBad"), "BadBrush", "BadBgBrush"); break;
        }
    }

    // ---------- token ----------
    private async void ReadToken_Click(object s, RoutedEventArgs e) => await Run(async () =>
    {
        var reader = Reader;
        _token = await Task.Run(() => SerbianCard.ReadToken(_pc, reader));
        HideProblem(); RenderToken();
    });

    // ---------- PIN / PUK / signing (each wrong PIN/PUK burns a card try: one attempt, no retries) ----------
    private static bool ValidPin(string p) => p != null && p.Length is >= 4 and <= 8 && p.All(c => c is >= '0' and <= '9');

    private async Task PinOp(Func<Task> work)
    {
        await Run(async () =>
        {
            try { await work(); }
            catch (PinException pe)
            {
                ShowInfo(pe.Blocked ? Loc.T("pinBlockedMsg") : string.Format(Loc.T("pinWrong"), pe.TriesLeft));
            }
            catch (ArgumentException) { ShowInfo(Loc.T("pinInvalid")); }
        });
    }

    /// Three separate dialogs (current/PUK, new, confirm) so it is always clear which PIN is being asked for.
    private string[] AskPinSteps(string title, string firstNoteKey, string firstLabelKey)
    {
        var a = PinDialog.Ask(this, title, Loc.T(firstNoteKey) + "\n\n" + Loc.T("pinWarn"), Loc.T(firstLabelKey));
        if (a == null) return null;
        var b = PinDialog.Ask(this, title, Loc.T("pinStepNew"), Loc.T("pinNew"));
        if (b == null) return null;
        var c = PinDialog.Ask(this, title, Loc.T("pinStepConfirm"), Loc.T("pinNew2"));
        if (c == null) return null;
        return new[] { a[0], b[0], c[0] };
    }

    private async void ChangePin_Click(object s, RoutedEventArgs e)
    {
        var v = AskPinSteps(Loc.T("changePin"), "pinStepOld", "pinOld");
        if (v == null) return;
        if (!v.All(ValidPin)) { ShowInfo(Loc.T("pinInvalid")); return; }
        if (v[1] != v[2]) { ShowInfo(Loc.T("pinMismatch")); return; }
        var reader = Reader;
        await PinOp(async () =>
        {
            await Task.Run(() => SerbianCard.ChangeTokenPin(_pc, reader, v[0], v[1]));
            ShowInfo(Loc.T("pinChanged"));
        });
    }

    private async void UnblockPin_Click(object s, RoutedEventArgs e)
    {
        var v = AskPinSteps(Loc.T("unblockPin"), "pinStepPuk", "pukEnter");
        if (v == null) return;
        if (!v.All(ValidPin)) { ShowInfo(Loc.T("pinInvalid")); return; }
        if (v[1] != v[2]) { ShowInfo(Loc.T("pinMismatch")); return; }
        var reader = Reader;
        await PinOp(async () =>
        {
            await Task.Run(() => SerbianCard.UnblockTokenPin(_pc, reader, v[0], v[1]));
            ShowInfo(Loc.T("pinUnblocked"));
        });
    }

    private async void SignFile_Click(object s, RoutedEventArgs e)
    {
        var open = new OpenFileDialog();
        if (open.ShowDialog(this) != true) return;
        var v = PinDialog.Ask(this, Loc.T("signFile"), Loc.T("pinWarn"), Loc.T("pinEnter"));
        if (v == null) return;
        if (!ValidPin(v[0])) { ShowInfo(Loc.T("pinInvalid")); return; }
        var save = new SaveFileDialog { Filter = "CMS signature (*.p7s)|*.p7s", FileName = Path.GetFileName(open.FileName) + ".p7s", DefaultExt = ".p7s" };
        if (save.ShowDialog(this) != true) return;
        var reader = Reader; var pin = v[0]; var src = open.FileName; var dst = save.FileName;
        await PinOp(async () =>
        {
            var p7s = await Task.Run(() =>
            {
                var tok = _token ?? SerbianCard.ReadToken(_pc, reader);
                if (tok.Certificates.Count == 0) throw new CardException(Loc.T("signNeedCert"));
                var data = File.ReadAllBytes(src);
                return Crypto.SignDetachedCms(data, tok.Certificates[0].Der,
                    di => SerbianCard.TokenSign(_pc, reader, pin, SerbianCard.DefaultSignKeyFile, di));
            });
            File.WriteAllBytes(dst, p7s);
            ShowInfo(string.Format(Loc.T("signed"), Path.GetFileName(dst)));
        });
    }

    private void RenderToken()
    {
        LstCerts.Children.Clear();
        LblTokenInfo.Text = _token == null ? "" : $"{_token.Label}  {_token.Serial}".Trim();
        if (_token == null)
        {
            LstCerts.Children.Add(new TextBlock { Text = Loc.T("hintToken"), Foreground = B("MutedBrush"), TextWrapping = TextWrapping.Wrap });
            return;
        }
        foreach (var c in _token.Certificates)
        {
            var box = new StackPanel { Margin = new Thickness(0, 0, 0, 14) };
            var top = new DockPanel();
            var pill = new Border { CornerRadius = new CornerRadius(12), Padding = new Thickness(10, 4, 10, 4), VerticalAlignment = VerticalAlignment.Center };
            var pt = new TextBlock { FontSize = 12, FontWeight = FontWeights.SemiBold };
            pill.Child = pt;
            SetPill(pill, pt, c.ChainTrusted ? "✔  " + Loc.T("chainOk") : "⚠  " + Loc.T("sigChain"),
                    c.ChainTrusted ? "OkBrush" : "WarnBrush", c.ChainTrusted ? "OkBgBrush" : "WarnBgBrush");
            DockPanel.SetDock(pill, Dock.Right);
            top.Children.Add(pill);
            top.Children.Add(new TextBlock { Text = c.Label.Length > 0 ? c.Label : c.Subject, Foreground = B("TextBrush"), FontSize = 14, FontWeight = FontWeights.SemiBold, VerticalAlignment = VerticalAlignment.Center });
            box.Children.Add(top);

            if (c.Issuer.Length > 0)
                box.Children.Add(new TextBlock { Text = $"{Loc.T("certIssuer")}: {c.Issuer}", Foreground = B("MutedBrush"), Margin = new Thickness(0, 4, 0, 0) });
            if (c.NotAfter != default)
            {
                var row = new WrapPanel { Margin = new Thickness(0, 4, 0, 0) };
                row.Children.Add(new TextBlock
                {
                    Text = string.Format(Loc.T("certValid"), c.NotBefore.ToString("dd.MM.yyyy"), c.NotAfter.ToString("dd.MM.yyyy")),
                    Foreground = B("MutedBrush"), VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 10, 0),
                });
                var ep = new Border { CornerRadius = new CornerRadius(12), Padding = new Thickness(10, 3, 10, 3) };
                var et = new TextBlock { FontSize = 12, FontWeight = FontWeights.SemiBold }; ep.Child = et;
                SetExpiry(ep, et, c.NotAfter);
                row.Children.Add(ep);
                box.Children.Add(row);
            }
            var export = new Button { Style = (Style)FindResource("SecondaryButton"), Margin = new Thickness(0, 10, 0, 0), HorizontalAlignment = HorizontalAlignment.Left };
            SetBtn(export, "", Loc.T("exportCert"));
            var cert = c;
            export.Click += (_, _) =>
            {
                var dlg = new SaveFileDialog { Filter = "Certificate (*.cer)|*.cer", FileName = "certificate.cer", DefaultExt = ".cer" };
                if (dlg.ShowDialog(this) == true) File.WriteAllBytes(dlg.FileName, cert.Der);
            };
            box.Children.Add(export);
            LstCerts.Children.Add(new Border { BorderBrush = B("LineBrush"), BorderThickness = new Thickness(0, 0, 0, 1), Padding = new Thickness(0, 0, 0, 4), Child = box });
        }
    }

    // ---------- print (with preview) / PDF ----------
    private void Print_Click(object s, RoutedEventArgs e)
    {
        if (_personal == null) return;
        new PreviewWindow(_personal, _cfg.PrintJmbg) { Owner = this }.ShowDialog();
    }

    private void Pdf_Click(object s, RoutedEventArgs e)
    {
        if (_personal == null) return;
        var dlg = new SaveFileDialog { Filter = "PDF (*.pdf)|*.pdf", FileName = "SuperCelik.pdf", DefaultExt = ".pdf" };
        if (dlg.ShowDialog(this) != true) return;
        try
        {
            Mouse.OverrideCursor = Cursors.Wait;
            PdfWriter.SaveSheet(PrintSheet.Build(_personal, 793.7, 1122.5, _cfg.PrintJmbg), dlg.FileName);   // A4 @ 96 dpi
            ShowInfo($"{Loc.T("pdfSaved")}: {dlg.FileName}");
        }
        catch (Exception ex) { ShowProblem(ex); }
        finally { Mouse.OverrideCursor = null; }
    }

    // ---------- settings ----------
    private void Theme_Changed(object s, SelectionChangedEventArgs e)
    {
        if (_loading || CmbTheme.SelectedIndex < 0) return;
        _cfg.Theme = CmbTheme.SelectedIndex switch { 1 => "light", 2 => "dark", _ => "system" };
        Theme.Apply(_cfg.Theme); _cfg.Save();
        UpdateCardLabel(); RenderAll();
    }

    private void Setting_Click(object s, RoutedEventArgs e)
    {
        if (_loading) return;
        _cfg.MaskSensitive = ChkMask.IsChecked == true;
        _cfg.PrintJmbg = ChkPrintJmbg.IsChecked == true;
        _cfg.AutoRead = ChkAutoRead.IsChecked == true;
        _cfg.AutoUpdate = ChkAutoUpdate.IsChecked == true;
        _cfg.AutoHideMinutes = int.TryParse(TxtAutoHide.Text, out var m) ? Math.Clamp(m, 0, 240) : 3;
        TxtAutoHide.Text = _cfg.AutoHideMinutes.ToString();
        _cfg.Save();
        RenderPersonal();
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
            ShowProblem(new Exception($"{Loc.T("updateFailed")}: {ex.Message}"));
        }
    }

    // ---------- demo / screenshot (fictional data) ----------
    /// `state` (screenshots of the empty states): noreader | nocard | ready | busy | error
    internal void LoadDemo(int tab, bool dark = false, bool problem = false, string state = null)
    {
        _demo = true; _poll.Stop(); _idle.Stop();
        Fx.Enabled = false;      // a screenshot must not catch a half-finished fade
        if (dark) { _cfg.Theme = "dark"; Theme.Apply("dark"); }
        _cardPresent = true;
        _readers = new() { "Demo Reader" }; FillReaders(_readers);
        _personal = new PersonalData
        {
            CardType = CardType.RP2024,
            Document = new DocumentData { DocRegNo = "001234567", DocumentSerialNumber = "RS1234567", IssuingAuthority = "MUP RS", IssuingDate = "01.01.2024", ExpiryDate = DateTime.Today.AddDays(412).ToString("dd.MM.yyyy") },
            Fixed = new FixedPersonalData { Surname = "PETROVIĆ", GivenName = "MARKO", Sex = "M", DateOfBirth = "01.01.1990", StateOfBirth = "Srbija", PersonalNumber = "0101990710000", NationalityFull = "Srbija" },
            Variable = new VariablePersonalData { Place = "Beograd", Community = "Stari Grad", Street = "Knez Mihailova", HouseNumber = "1" },
        };
        _sig = new SigStatus { Result = SigResult.Ok };
        _token = new TokenInfo { Label = "NetSeT's CardEdge Token", Serial = "RP000000000" };
        _token.Certificates.Add(new TokenCertificate
        {
            Label = "MARKO PETROVIC 000000000 Auth", ChainTrusted = true, Issuer = "MUP Stranci CA 4",
            NotBefore = DateTime.Today.AddMonths(-14), NotAfter = DateTime.Today.AddDays(75), Der = new byte[] { 0 },
        });
        if (state != null)
        {
            _personal = null; _sig = null; _token = null;
            if (state == "noreader") { _readers = new(); FillReaders(_readers); _cardPresent = false; }
            if (state == "nocard") _cardPresent = false;
            if (state == "busy") _busy = true;
        }
        Tabs.SelectedIndex = tab;
        HideProblem();
        ApplyLanguage();
        if (problem) ShowProblem(new CardException(Native.SCARD_E_NO_READERS_AVAILABLE, "ListReaders"));
        if (state == "error") ShowProblem(new CardException("Unsupported card (demo)"));
    }

    internal void ExportDemoPdf(string path) => PdfWriter.SaveSheet(PrintSheet.Build(_personal, 793.7, 1122.5, true), path);

    internal void SaveScreenshot(string path)
    {
        UpdateLayout();
        var el = (FrameworkElement)Content;
        var rtb = new RenderTargetBitmap((int)ActualWidth, (int)ActualHeight, 96, 96, PixelFormats.Pbgra32);
        rtb.Render(el);
        var enc = new PngBitmapEncoder(); enc.Frames.Add(BitmapFrame.Create(rtb));
        using var fs = File.Create(path); enc.Save(fs);
    }
}

/// The printout of the official MUP Čelik application ("ČITAČ ELEKTRONSKE LIČNE KARTE: ŠTAMPA PODATAKA"),
/// reproduced one-to-one: same A4 page, positions (in points), line widths, font sizes, labels and footnotes.
/// It is a standard document — do not restyle it. Same layout as MupPrintView on macOS.
internal static class PrintSheet
{
    private const double PageW = 595.28, PageH = 841.89;
    private const double LeftMargin = 58.8, RightMargin = 535, TextLeftMargin = 67.3;

    public static FrameworkElement Build(PersonalData p, double w, double h, bool includeJmbg)
    {
        var page = new Sheet(p, includeJmbg).Draw();
        var root = new Viewbox { Width = w, Height = h, Stretch = Stretch.Uniform, VerticalAlignment = VerticalAlignment.Top, Child = page };
        var host = new Grid { Width = w, Height = h, Background = Brushes.White };
        host.Children.Add(root);
        host.Measure(new Size(w, h));
        host.Arrange(new Rect(0, 0, w, h));
        host.UpdateLayout();
        return host;
    }

    private sealed class Sheet
    {
        private readonly PersonalData _p;
        private readonly bool _jmbg;
        private readonly Canvas _c = new() { Width = PageW, Height = PageH, Background = Brushes.White };
        private readonly Typeface _face = new(new FontFamily("Arial"), FontStyles.Normal, FontWeights.Normal, FontStretches.Normal);
        private double _y, _lineWidth = 1, _fontSize = 13.5;

        public Sheet(PersonalData p, bool includeJmbg) { _p = p; _jmbg = includeJmbg; }

        public Canvas Draw()
        {
            if (_p.CardType == CardType.IF2020) Foreigner(false);
            else if (_p.CardType == CardType.RP2024) Foreigner(true);
            else Regular();
            return _c;
        }

        private void Regular()
        {
            Header(68.5, 88);
            Photo(102.8);
            _y = 276;
            Line(1.08);
            Section("Podaci o građaninu", true);
            var f = _p.Fixed; var v = _p.Variable;
            Row("Prezime:", f.Surname);
            Row("Ime:", f.GivenName);
            Row("Ime jednog roditelja:", f.ParentGivenName);
            Row("Datum rođenja:", Date(f.DateOfBirth));
            Row("Mesto rođenja\nopština i država:", Join(f.PlaceOfBirth, f.CommunityOfBirth, f.StateOfBirth));
            Row(AddressLabel, Address);
            Row("Datum promene adrese:", Date(v.AddressDate));
            if (_jmbg) Row("JMBG:", f.PersonalNumber);
            Row("Pol:", f.Sex);
            DocumentSection(false);
            PrintDate();
            if (_y < 700) _y = 730.6;
            Line(0.83);
            _fontSize = 9;
            _y += 10;
            Notes(
                "1. U čipu lične karte, podaci o imenu i prezimenu imaoca lične karte ispisani su na nacionalnom pismu onako kako su",
                "ispisani na samom obrascu lične karte, dok su ostali podaci ispisani latiničkim pismom.",
                "2. Ako se ime lica sastoji od dve reči čija je ukupna dužina između 20 i 30 karaktera ili prezimena od dve reči čija je",
                "ukupna dužina između 30 i 36 karaktera, u čipu lične karte izdate pre 18.08.2014. godine, druga reč u imenu ili prezimenu",
                "skraćuje se na prva dva karaktera");
            _y += 15.7;
            Line(null);
        }

        private void Foreigner(bool permit)
        {
            Header(64.95, 79.8);
            Photo(86);
            _y = 250;
            Line(1.08);
            Section("Podaci o strancu", true);
            var f = _p.Fixed; var v = _p.Variable;
            Row("Prezime:", f.Surname);
            Row("Ime:", f.GivenName);
            Row("Državljanstvo:", f.NationalityFull);
            Row("Datum rođenja:", Date(f.DateOfBirth));
            if (permit)
            {
                Row("Mesto rođenja,\nopština i država:", Join(f.PlaceOfBirth, f.CommunityOfBirth, f.StateOfBirth));
                Row(AddressLabel, Address);
            }
            else
            {
                Row("Osnov boravka:", f.PurposeOfStay);
                Row(AddressLabel, Join(v.State, Address));
            }
            Row("Datum promene adrese:", Date(v.AddressDate));
            if (_jmbg) Row("Evidencijski broj\nstranca:", f.PersonalNumber);
            Row("Pol:", f.Sex);
            if (permit)
            {
                Row("Osnov boravka:", f.PurposeOfStay);
                Row("Napomena:", f.ENote);
            }
            DocumentSection(permit);
            PrintDate();
            Line(0.83);
            _fontSize = 9;
            _y += 4;
            if (permit) Notes(
                "1. U čipu dozvole za privremeni boravak i rad, podaci o imenu i prezimenu imaoca dozvole ispisani su onako kako su",
                "ispisani na samom obrascu dozvole za privremeni boravak latiničnim pismom.",
                "2. Ako se ime ili prezime stranca sastoji od dve ili više reči čija dužina prelazi 30 karaktera za ime, odnosno 36 karaktera",
                "za prezime u čip se upisuje puno ime stranca, a na obrascu dozvole za privremeni boravak se upisuje do 30 karaktera za",
                "ime, odnosno 36 karaktera za prezime.");
            else Notes(
                "1. U čipu lične karte za strance, podaci o imenu i prezimenu stranca ispisani su onako kako su ispisani na samom",
                "obrascu lične karte za stranca latiničnim pismom.",
                "2. Ako se ime ili prezime stranca sastoji od dve ili više reči čija dužina prelazi 30 karaktera za ime, odnosno 36",
                "karaktera za prezime, u čip se upisuje puno ime i prezime stranca, a na obrascu lične karte za stranca se upisuje do",
                "30 karaktera za ime, odnosno 36 karaktera za prezime.");
            _y += 9.7;
            Line(null);
        }

        private void Header(double titleY, double ruleY)
        {
            _y = 59.041;
            Line(0.83);
            Text("ČITAČ ELEKTRONSKE LIČNE KARTE: ŠTAMPA PODATAKA", TextLeftMargin + 1, titleY);
            _y = ruleY;
            Line(null);
        }

        private void Photo(double top)
        {
            var img = MainWindow.LoadImage(_p.Portrait);
            if (img != null)
            {
                var i = new Image { Source = img, Width = 119.9, Height = 159, Stretch = Stretch.Fill };
                Canvas.SetLeft(i, LeftMargin); Canvas.SetTop(i, top);
                _c.Children.Add(i);
            }
            var r = new System.Windows.Shapes.Rectangle { Width = 179 - LeftMargin, Height = 159, Stroke = Brushes.Black, StrokeThickness = 0.48 };
            Canvas.SetLeft(r, LeftMargin); Canvas.SetTop(r, top);
            _c.Children.Add(r);
            _lineWidth = 0.48;
        }

        private void Section(string title, bool first)
        {
            if (!first) { _y -= 8.67; Line(null); }
            _y += first ? 8 : 9;
            if (first) _fontSize = 11.1;
            Text(title, TextLeftMargin, _y);
            _y += 16;
            Line(null);
            _y += 9;
        }

        private void DocumentSection(bool withName)
        {
            Section("Podaci o dokumentu", false);
            var d = _p.Document;
            if (withName) Row("Naziv dokumenta:", d.DocumentName);
            Row("Dokument izdaje:", d.IssuingAuthority);
            Row("Broj dokumenta:", d.DocRegNo);
            Row("Datum izdavanja:", Date(d.IssuingDate));
            Row("Važi do:", Date(d.ExpiryDate));
        }

        private void PrintDate()
        {
            _y -= 8.67; Line(null);
            _y += 3; Line(null);
            _y += 9;
            Text("Datum štampe: " + DateTime.Now.ToString("dd.MM.yyyy.", CultureInfo.InvariantCulture), TextLeftMargin, _y);
            _y += 19;
        }

        private void Notes(params string[] lines)
        {
            for (int i = 0; i < lines.Length; i++)
            {
                if (i > 0) _y += 9.7;
                Text(lines[i], LeftMargin, _y);
            }
        }

        /// Label column 120 pt wide, value column 350 pt wide 128 pt to the right; wrapped lines 12 pt apart, rows 24.67 pt apart.
        private void Row(string label, string value)
        {
            double top = _y;
            var l = Wrap(label, 120); var v = Wrap(value ?? "", 350);
            for (int i = 0; i < l.Count; i++) Text(l[i], TextLeftMargin, top + i * 12);
            for (int i = 0; i < v.Count; i++) Text(v[i], TextLeftMargin + 128, top + i * 12);
            _y = top + (Math.Max(Math.Max(l.Count, v.Count), 1) - 1) * 12 + 24.67;
        }

        private void Text(string s, double x, double y)
        {
            var t = new TextBlock { Text = s, FontFamily = _face.FontFamily, FontSize = _fontSize, Foreground = Brushes.Black };
            Canvas.SetLeft(t, x); Canvas.SetTop(t, y);
            _c.Children.Add(t);
        }

        private void Line(double? width)
        {
            if (width.HasValue) _lineWidth = width.Value;
            _c.Children.Add(new System.Windows.Shapes.Line { X1 = LeftMargin, X2 = RightMargin, Y1 = _y, Y2 = _y, Stroke = Brushes.Black, StrokeThickness = _lineWidth });
        }

        private double Measure(string s) =>
            new FormattedText(s, CultureInfo.InvariantCulture, FlowDirection.LeftToRight, _face, _fontSize, Brushes.Black, 1.0).WidthIncludingTrailingWhitespace;

        private List<string> Wrap(string s, double width)
        {
            var output = new List<string>();
            foreach (var para in s.Split('\n'))
            {
                var cur = "";
                foreach (var word in para.Split(' ', StringSplitOptions.RemoveEmptyEntries))
                {
                    var next = cur.Length == 0 ? word : cur + " " + word;
                    if (cur.Length > 0 && Measure(next) > width) { output.Add(cur); cur = word; }
                    else cur = next;
                }
                output.Add(cur);
            }
            return output;
        }

        private string AddressLabel =>
            string.Equals(_p.Variable.AddressLabel, "prebivalište", StringComparison.OrdinalIgnoreCase) ? "Prebivalište:" : "Prebivalište\ni adresa stana:";

        /// "MESTO, OPŠTINA, ULICA 12A/3/7"
        private string Address
        {
            get
            {
                var v = _p.Variable;
                var street = v.Street;
                if (v.HouseNumber.Length > 0 || v.HouseLetter.Length > 0 || v.Entrance.Length > 0)
                {
                    street += " " + v.HouseNumber + v.HouseLetter;
                    if (v.Floor.Length > 0) street += "/" + v.Floor;
                    if (v.ApartmentNumber.Length > 0) street += "/" + v.ApartmentNumber;
                }
                return Join(v.Place, v.Community, street);
            }
        }

        private static string Join(params string[] parts) =>
            string.Join(", ", parts.Select(x => (x ?? "").Trim()).Where(x => x.Length > 0));

        /// "dd.MM.yyyy" -> "dd.MM.yyyy."; a date with year 0000 is "Nije dostupan".
        private static string Date(string s)
        {
            var parts = (s ?? "").TrimEnd('.').Split('.');
            if (parts.Length != 3 || parts[2].Length != 4) return s ?? "";
            if (parts[2] == "0000") return "Nije dostupan";
            return s.EndsWith(".") ? s : s + ".";
        }
    }
}

/// In-app print preview with Print / Save PDF buttons.
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
        FontFamily = new FontFamily("Segoe UI");
        SetResourceReference(BackgroundProperty, "BgBrush");

        var dock = new DockPanel();
        var bar = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(16, 12, 16, 12) };
        DockPanel.SetDock(bar, Dock.Bottom);
        var print = Make("PrimaryButton", "", Loc.T("printCard")); print.Click += (_, _) => DoPrint();
        var pdf = Make("SecondaryButton", "", Loc.T("savePdf")); pdf.Click += (_, _) => DoPdf();
        var close = Make("SecondaryButton", "", Loc.T("close")); close.Click += (_, _) => Close();
        foreach (var b in new[] { close, pdf, print }) { b.Margin = new Thickness(8, 0, 0, 0); bar.Children.Add(b); }
        dock.Children.Add(bar);

        var page = PrintSheet.Build(p, 793.7, 1122.5, includeJmbg);
        var shadow = new Border { Child = new Viewbox { Child = page, Stretch = Stretch.Uniform }, Margin = new Thickness(24), Background = Brushes.White,
                                  Effect = new System.Windows.Media.Effects.DropShadowEffect { BlurRadius = 18, ShadowDepth = 2, Opacity = 0.25 } };
        dock.Children.Add(shadow);
        Content = dock;
    }

    private Button Make(string style, string glyph, string text)
    {
        var b = new Button { Style = (Style)FindResource(style) };
        var sp = new StackPanel { Orientation = Orientation.Horizontal };
        sp.Children.Add(new TextBlock { Text = glyph, FontFamily = new FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets"), FontSize = 15, Margin = new Thickness(0, 1, 8, 0), VerticalAlignment = VerticalAlignment.Center });
        sp.Children.Add(new TextBlock { Text = text, VerticalAlignment = VerticalAlignment.Center });
        b.Content = sp;
        return b;
    }

    private void DoPrint()
    {
        var dlg = new PrintDialog();
        if (dlg.ShowDialog() != true) return;
        dlg.PrintVisual(PrintSheet.Build(_p, dlg.PrintableAreaWidth, dlg.PrintableAreaHeight, _jmbg), "Super Celik");
    }

    private void DoPdf()
    {
        var dlg = new SaveFileDialog { Filter = "PDF (*.pdf)|*.pdf", FileName = "SuperCelik.pdf", DefaultExt = ".pdf" };
        if (dlg.ShowDialog(this) == true) PdfWriter.SaveSheet(PrintSheet.Build(_p, 793.7, 1122.5, _jmbg), dlg.FileName);
    }
}
