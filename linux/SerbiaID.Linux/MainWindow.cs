using System.Diagnostics;
using System.Globalization;
using System.Text;
using System.Text.Json;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.Primitives;
using Avalonia.Input;
using Avalonia.Layout;
using Avalonia.Media;
using Avalonia.Media.Imaging;
using Avalonia.Platform.Storage;
using Avalonia.Threading;

namespace SerbiaID;

public sealed partial class MainWindow : Window
{
    private PcscService _pc = new();
    private readonly AppSettings _cfg = AppSettings.Load();
    private readonly Options _opts;
    private PersonalData _personal;
    private TokenInfo _token;
    private SigStatus _sig;
    private Version _newVersion; private string _newPage;
    private List<string> _readers = new();
    private bool _revealAll, _loading = true, _cardPresent, _busy, _demo, _hasError, _serviceDown;
    private DateTime _lastActivity = DateTime.Now;
    private readonly DispatcherTimer _poll = new() { Interval = TimeSpan.FromMilliseconds(1500) };
    private readonly DispatcherTimer _idle = new() { Interval = TimeSpan.FromSeconds(15) };

    private static readonly string[] Sensitive = { "jmbg", "address", "docNumber", "docSerial" };

    // ---- controls ----
    private Border _updateBanner, _problemBanner, _pillExpiry, _pillSig, _portraitFrame;
    private TextBlock _lblUpdate, _lblBrand, _lblBrandSub, _lblReader, _lblProblemTitle, _lblProblemHint;
    private TextBlock _lblEmptyTitle, _lblHint, _lblName, _lblDocType, _lblTokenInfo, _lblCerts, _lblPinNote;
    private TextBlock _lblSetAppearance, _lblSetLang, _lblSetTheme, _lblSetPrivacy, _lblSetBehavior, _lblAutoHide;
    private TextBlock _lblAboutTitle, _lblAboutText, _lblVersion, _lblUpdateStatus;
    private ComboBox _cmbReader, _cmbLang, _cmbTheme;
    private CheckBox _chkMask, _chkPrintJmbg, _chkAutoRead, _chkAutoUpdate, _chkDemo;
    private TextBlock _lblDemoHint, _lblCopyLogsHint; private Button _btnCopyLogs;
    private TextBox _txtAutoHide;
    private ProgressBar _busyBar;
    private Button _btnRefresh, _btnRead, _btnReadBig, _btnPrint, _btnPdf, _btnVerify, _btnEye, _btnMore, _btnProblemClose;
    private TextBlock _lblBeta; private Button _btnFeedback, _btnLoginEu, _btnSetupBrowser;
    private const string EuLoginUrl = "https://euprava.gov.rs/prijava";
    private const string FeedbackUrl = "https://github.com/peregond/SuperCelik/issues/new";
    // the site pages open in the language of the app (?lang=), the changelog in this app's own section (?app=)
    private static string LangCode => Loc.SiteCode;
    private static string ReaderPageUrl => "https://celik.peregon.cc/reader/?lang=" + LangCode;
    private static string ChangelogUrl => "https://celik.peregon.cc/changelog/?lang=" + LangCode + "&app=linux";
    private Button _btnReadToken, _btnChangePin, _btnUnblockPin, _btnSignFile, _btnCheckUpdates, _btnUpdate, _btnWhatsNew, _btnReaderHelp;
    private StackPanel _emptyState, _certList;
    // "Check browser sign-in": the result sits in the certificates card, under the certificates
    private StackPanel _checkPanel, _checkRows; private TextBlock _checkTitle, _checkStep;
    private sealed record CheckShown(BrowserSetup.Diagnosis D, int Readers, bool Card);
    private CheckShown _checkShown;
    private Control _personalContent;
    private WrapPanel _fields;
    private Image _imgPortrait;
    private MascotArt _emptyMascot, _keyMascot;
    private const int TabCount = 4;   // card data, token, settings, about
    private readonly Button[] _tabButtons = new Button[TabCount];
    private readonly Control[] _tabPages = new Control[TabCount];
    private ContextMenu _moreMenu;
    private int _tab;

    public MainWindow(Options opts)
    {
        _opts = opts;
        Width = 1020; Height = 720; MinWidth = 820; MinHeight = 600;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        FontSize = 13;
        try { Icon = new WindowIcon(new Bitmap(Avalonia.Platform.AssetLoader.Open(new Uri("avares://SuperCelik/Assets/icon.png")))); } catch { }
        this.Res(BackgroundProperty, "BgBrush");
        this.Res(ForegroundProperty, "TextBrush");

        Loc.Current = _cfg.Lang != null && Enum.TryParse<Lang>(_cfg.Lang, out var l) ? l : SystemLang();
        if (_cfg.WindowWidth >= MinWidth && _cfg.WindowHeight >= MinHeight) { Width = _cfg.WindowWidth; Height = _cfg.WindowHeight; }
        ApplyTheme(_cfg.Theme);

        Content = BuildUi();
        _cmbLang.SelectedIndex = Array.IndexOf(Loc.PickerOrder, Loc.Current);
        _cmbTheme.SelectedIndex = _cfg.Theme switch { "light" => 1, "dark" => 2, _ => 0 };
        _chkMask.IsChecked = _cfg.MaskSensitive; _chkPrintJmbg.IsChecked = _cfg.PrintJmbg;
        _chkAutoRead.IsChecked = _cfg.AutoRead; _chkAutoUpdate.IsChecked = _cfg.AutoUpdate;
        _txtAutoHide.Text = _cfg.AutoHideMinutes.ToString();
        SelectTab(Math.Clamp(_cfg.Tab, 0, TabCount - 1));
        _loading = false;

        if (opts.Demo) { LoadDemo(); _loading = true; _chkDemo.IsChecked = true; _loading = false; return; }
        ApplyLanguage();
        Refresh();
        StartPolling();
        Opened += async (_, _) =>
        {
            if (!_demo && BrowserSetup.HasModule)
            {
                if (!_cfg.BrowserSetupAsked) await OfferBrowserSetup();
                else
                {
                    // someone who connected the module in an earlier version has agreed too, that version just did not write it down
                    if (!_cfg.BrowserSetupAccepted && await BrowserSetup.AnyConnected()) { _cfg.BrowserSetupAccepted = true; _cfg.Save(); }
                    if (_cfg.BrowserSetupAccepted) await KeepBrowserSetup();
                }
            }
            if (_cfg.AutoUpdate) await AutoCheckUpdateAsync();
        };
    }

    private bool _polling;
    /// Starts watching the reader (and the idle timer). Called once; a window launched with --demo starts it when the demo data is switched off.
    private void StartPolling()
    {
        if (_polling) return;
        _polling = true;
        _poll.Tick += (_, _) => Poll(); _poll.Start();
        _idle.Tick += (_, _) => CheckIdle(); _idle.Start();
        AddHandler(PointerMovedEvent, (_, _) => _lastActivity = DateTime.Now, Avalonia.Interactivity.RoutingStrategies.Tunnel);
        AddHandler(KeyDownEvent, (_, _) => _lastActivity = DateTime.Now, Avalonia.Interactivity.RoutingStrategies.Tunnel);
        AddHandler(PointerPressedEvent, (_, _) => _lastActivity = DateTime.Now, Avalonia.Interactivity.RoutingStrategies.Tunnel);
    }

    protected override void OnClosing(WindowClosingEventArgs e)
    {
        if (!_demo)
        {
            _cfg.Tab = _tab;
            if (WindowState == WindowState.Normal) { _cfg.WindowWidth = Width; _cfg.WindowHeight = Height; }
            _cfg.Save();
        }
        base.OnClosing(e);
    }

    protected override void OnClosed(EventArgs e) { _poll.Stop(); _idle.Stop(); _pc.Dispose(); base.OnClosed(e); }

    /// The language from the locale variables (LANGUAGE, LC_ALL, LC_MESSAGES, LANG): ru_RU.UTF-8, sr_RS@latin, ...
    private static Lang SystemLang()
    {
        foreach (var v in new[] { "LANGUAGE", "LC_ALL", "LC_MESSAGES", "LANG" })
        {
            var s = Environment.GetEnvironmentVariable(v);
            if (string.IsNullOrEmpty(s)) continue;
            s = s.Split(':')[0].ToLowerInvariant();
            if (s.StartsWith("ru")) return Lang.ru;
            if (s.StartsWith("sr")) return s.Contains("latin") ? Lang.sr : Lang.srCyrl;
            if (s.StartsWith("bs")) return Lang.sr;
            if (s.Length >= 2 && Loc.FromCode(s.Substring(0, 2)) is Lang extra) return extra;
            if (s.StartsWith("c") && (s == "c" || s.StartsWith("c.") || s.StartsWith("c@"))) continue;
            return Lang.en;
        }
        return Lang.en;
    }

    private string Reader => _cmbReader.SelectedItem as string;

    private void ApplyTheme(string mode)
    {
        if (Application.Current != null)
            Application.Current.RequestedThemeVariant = mode switch { "light" => Avalonia.Styling.ThemeVariant.Light, "dark" => Avalonia.Styling.ThemeVariant.Dark, _ => Avalonia.Styling.ThemeVariant.Default };
    }

    // ======================= UI construction =======================
    private Control BuildUi()
    {
        var root = new DockPanel();

        // update banner
        _lblUpdate = Ui.Label("", 13, true);
        _btnUpdate = Ui.Btn("", "primary"); _btnUpdate.Click += async (_, _) => await StartUpdate();
        var ub = new DockPanel { Margin = new Thickness(0) };
        DockPanel.SetDock(_btnUpdate, Dock.Right); ub.Children.Add(_btnUpdate);
        _lblUpdate.VerticalAlignment = VerticalAlignment.Center; ub.Children.Add(_lblUpdate);
        _updateBanner = new Border { Padding = new Thickness(24, 9), Child = ub, IsVisible = false }.Res(Border.BackgroundProperty, "BannerBrush");
        DockPanel.SetDock(_updateBanner, Dock.Top); root.Children.Add(_updateBanner);

        // header
        var logo = new Image { Width = 40, Height = 40 };
        try { logo.Source = new Bitmap(Avalonia.Platform.AssetLoader.Open(new Uri("avares://SuperCelik/Assets/icon.png"))); } catch { }
        _lblBrand = Ui.Label("", 19, true); _lblBrand.FontWeight = FontWeight.Bold;
        _lblBrandSub = Ui.Label("", 11, false, "MutedBrush");
        var brand = new StackPanel { Margin = new Thickness(12, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center, Children = { _lblBrand, _lblBrandSub } };
        var left = new StackPanel { Orientation = Orientation.Horizontal, Children = { logo, brand } };
        _lblReader = Ui.Label("", 12, false, "MutedBrush"); _lblReader.TextTrimming = TextTrimming.CharacterEllipsis; _lblReader.MaxWidth = 260;
        _lblReader.VerticalAlignment = VerticalAlignment.Center; _lblReader.Margin = new Thickness(0, 0, 8, 0);
        _cmbReader = new ComboBox { Width = 260, Margin = new Thickness(0, 0, 8, 0), VerticalAlignment = VerticalAlignment.Center, IsVisible = false };
        _cmbReader.SelectionChanged += (_, _) => { if (!_loading) Refresh(); };
        _btnRefresh = Ui.Btn("", "icon"); Ui.SetBtn(_btnRefresh, "rotate-cw", null); _btnRefresh.Click += (_, _) => Refresh();
        var right = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Center, Children = { _lblReader, _cmbReader, _btnRefresh } };
        var hdr = new DockPanel { Children = { right } };
        DockPanel.SetDock(left, Dock.Left); hdr.Children.Insert(0, left);
        var header = new Border { Padding = new Thickness(24, 14), BorderThickness = new Thickness(0, 0, 0, 1), Child = hdr }
            .Res(Border.BackgroundProperty, "SurfaceBrush").Res(Border.BorderBrushProperty, "LineBrush");
        DockPanel.SetDock(header, Dock.Top); root.Children.Add(header);

        _busyBar = new ProgressBar { IsIndeterminate = true, Height = 3, IsVisible = false, Background = Brushes.Transparent }.Res(ProgressBar.ForegroundProperty, "RedBrush");
        DockPanel.SetDock(_busyBar, Dock.Top); root.Children.Add(_busyBar);

        // problem banner
        _lblProblemTitle = Ui.Label("", 13, true, "TextBrush", true); _lblProblemTitle.FontWeight = FontWeight.Bold;
        _lblProblemHint = Ui.Label("", 13, false, "TextBrush", true); _lblProblemHint.Margin = new Thickness(0, 2, 0, 0);
        _btnProblemClose = Ui.Btn("", "icon"); Ui.SetBtn(_btnProblemClose, "x", null); _btnProblemClose.VerticalAlignment = VerticalAlignment.Top; _btnProblemClose.Click += (_, _) => HideProblem();
        var pb = new DockPanel();
        DockPanel.SetDock(_btnProblemClose, Dock.Right); pb.Children.Add(_btnProblemClose);
        pb.Children.Add(new StackPanel { Children = { _lblProblemTitle, _lblProblemHint } });
        _problemBanner = new Border { Padding = new Thickness(24, 10), Child = pb, IsVisible = false };
        DockPanel.SetDock(_problemBanner, Dock.Top); root.Children.Add(_problemBanner);

        // tab strip
        var strip = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(16, 0, 0, 0) };
        for (int i = 0; i < TabCount; i++)
        {
            int idx = i;
            var tb = new Button { Classes = { "tab" } };
            tb.Click += (_, _) => SelectTab(idx);
            _tabButtons[i] = tb; strip.Children.Add(tb);
        }
        var stripBorder = new Border { BorderThickness = new Thickness(0, 0, 0, 1), Child = strip }.Res(Border.BorderBrushProperty, "LineBrush");
        DockPanel.SetDock(stripBorder, Dock.Top); root.Children.Add(stripBorder);

        var pages = new Grid();
        _tabPages[0] = BuildPersonalTab(); _tabPages[1] = BuildTokenTab(); _tabPages[2] = BuildSettingsTab(); _tabPages[3] = BuildAboutTab();
        foreach (var p in _tabPages) pages.Children.Add(p);
        root.Children.Add(pages);
        return root;
    }

    private void SelectTab(int i)
    {
        _tab = i;
        for (int k = 0; k < TabCount; k++)
        {
            _tabPages[k].IsVisible = k == i;
            if (k == i) _tabButtons[k].Classes.Add("active"); else _tabButtons[k].Classes.Remove("active");
        }
    }

    private Control BuildPersonalTab()
    {
        var grid = new Grid { Margin = new Thickness(24, 18, 24, 20) };

        // empty state
        _emptyMascot = new MascotArt(MascotCharacter.Reader, 170);
        _lblEmptyTitle = Ui.Label("", 20, true); _lblEmptyTitle.TextAlignment = TextAlignment.Center; _lblEmptyTitle.Margin = new Thickness(0, 14, 0, 0);
        _lblHint = Ui.Label("", 14, false, "MutedBrush", true); _lblHint.TextAlignment = TextAlignment.Center; _lblHint.MaxWidth = 420; _lblHint.Margin = new Thickness(0, 8, 0, 0);
        _btnReaderHelp = Ui.Btn(""); _btnReaderHelp.HorizontalAlignment = HorizontalAlignment.Center; _btnReaderHelp.Margin = new Thickness(0, 16, 0, 0); _btnReaderHelp.IsVisible = false;
        _btnReaderHelp.Click += (_, _) => OpenUrl(ReaderPageUrl);
        _btnReadBig = Ui.Btn("", "primary"); _btnReadBig.HorizontalAlignment = HorizontalAlignment.Center; _btnReadBig.Margin = new Thickness(0, 20, 0, 0);
        _btnReadBig.Click += async (_, _) => await Run(ReadCardAsync);
        _emptyState = new StackPanel { VerticalAlignment = VerticalAlignment.Center, HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 0, 0, 40),
            Children = { _emptyMascot, _lblEmptyTitle, _lblHint, _btnReaderHelp, _btnReadBig } };
        grid.Children.Add(_emptyState);

        // content
        _btnRead = Ui.Btn("", "primary"); _btnRead.Click += async (_, _) => await Run(ReadCardAsync);
        _btnPrint = Ui.Btn(""); _btnPrint.Click += async (_, _) =>
        {
            if (_vehicle != null) { var vv = _vehicle; await new PreviewWindow((w, h) => VehicleSheet.Build(vv, w, h, _cfg.PrintJmbg)).ShowDialog(this); }
            else if (_personal != null) { var pp = _personal; await new PreviewWindow((w, h) => PrintSheet.Build(pp, w, h, _cfg.PrintJmbg)).ShowDialog(this); }
        };
        _btnPdf = Ui.Btn(""); _btnPdf.Click += async (_, _) => await SavePdf();
        _btnVerify = Ui.Btn(""); _btnVerify.Click += async (_, _) => await Run(VerifyAsync);
        _btnEye = Ui.Btn(""); _btnEye.Click += (_, _) => { _revealAll = !_revealAll; RenderPersonal(); };
        _btnMore = Ui.Btn(""); _btnMore.Click += (_, _) => _moreMenu?.Open(_btnMore);
        _moreMenu = new ContextMenu();
        var bar = new WrapPanel { Margin = new Thickness(0, 0, 0, 12) };
        foreach (var b in new[] { _btnRead, _btnPrint, _btnPdf, _btnVerify, _btnEye, _btnMore }) { b.Margin = new Thickness(0, 0, 8, 8); bar.Children.Add(b); }

        _imgPortrait = new Image { Stretch = Stretch.UniformToFill };
        _portraitFrame = new Border { Width = 170, Height = 215, CornerRadius = new CornerRadius(12), ClipToBounds = true, Child = _imgPortrait }.Res(Border.BackgroundProperty, "PlaceholderBrush");
        _lblName = Ui.Label("", 17, true); _lblName.FontWeight = FontWeight.Bold; _lblName.TextAlignment = TextAlignment.Center; _lblName.Margin = new Thickness(0, 16, 0, 2); _lblName.TextWrapping = TextWrapping.Wrap;
        _lblDocType = Ui.Label("", 13, false, "MutedBrush"); _lblDocType.TextAlignment = TextAlignment.Center;
        _pillExpiry = Ui.Pill(new TextBlock()); _pillExpiry.Margin = new Thickness(0, 12, 0, 0);
        _pillSig = Ui.Pill(new TextBlock()); _pillSig.Margin = new Thickness(0, 8, 0, 0);
        // the pills fill the column (a fixed width), so a long text wraps inside the pill instead of being cut off
        _pillExpiry.HorizontalAlignment = _pillSig.HorizontalAlignment = HorizontalAlignment.Stretch;
        var side = Ui.Card(new StackPanel { HorizontalAlignment = HorizontalAlignment.Center, Width = 236, Children = { _portraitFrame, _lblName, _lblDocType, _pillExpiry, _pillSig } });
        side.VerticalAlignment = VerticalAlignment.Top;
        _fields = new WrapPanel();
        var data = Ui.Card(new ScrollViewer { Content = _fields, VerticalScrollBarVisibility = ScrollBarVisibility.Auto });

        var cols = new Grid { ColumnDefinitions = new ColumnDefinitions("250,18,*") };
        cols.Children.Add(side); Grid.SetColumn(data, 2); cols.Children.Add(data);
        var dock = new DockPanel();
        DockPanel.SetDock(bar, Dock.Top); dock.Children.Add(bar); dock.Children.Add(cols);
        _personalContent = dock; dock.IsVisible = false;
        grid.Children.Add(dock);
        return grid;
    }

    private Control BuildTokenTab()
    {
        _btnReadToken = Ui.Btn("", "primary"); _btnReadToken.Click += async (_, _) => await Run(ReadTokenAsync);
        _btnChangePin = Ui.Btn(""); _btnChangePin.Click += async (_, _) => await ChangePin();
        _btnUnblockPin = Ui.Btn(""); _btnUnblockPin.Click += async (_, _) => await UnblockPin();
        _btnSignFile = Ui.Btn(""); _btnSignFile.Click += async (_, _) => await SignFile();
        _btnLoginEu = Ui.Btn(""); _btnLoginEu.Click += async (_, _) => await LoginEu();
        _btnSetupBrowser = Ui.Btn(""); _btnSetupBrowser.IsVisible = BrowserSetup.HasModule; _btnSetupBrowser.Click += async (_, _) => await SetupAndCheckBrowser();
        _lblTokenInfo = Ui.Label("", 13, false, "MutedBrush"); _lblTokenInfo.VerticalAlignment = VerticalAlignment.Center;
        // the buttons wrap with a gap in a narrow window; the token name sits on its own line under them
        var buttons = new WrapPanel();
        foreach (var b in new[] { _btnReadToken, _btnChangePin, _btnUnblockPin, _btnSignFile, _btnLoginEu, _btnSetupBrowser }) { b.Margin = new Thickness(0, 0, 10, 10); buttons.Children.Add(b); }
        _lblTokenInfo.VerticalAlignment = VerticalAlignment.Center; _lblTokenInfo.Margin = new Thickness(2, 0, 0, 12);
        var bar = new StackPanel { Margin = new Thickness(0, 0, 0, 4), Children = { buttons, _lblTokenInfo } };
        _lblPinNote = Ui.Label("", 13, false, "MutedBrush", true); _lblPinNote.Margin = new Thickness(2, 14, 0, 0);
        _lblCerts = Ui.Label("", 15, true); _lblCerts.FontWeight = FontWeight.Bold; _lblCerts.Margin = new Thickness(0, 0, 0, 10);
        _certList = new StackPanel();
        _checkTitle = Ui.Label("", 14, true); _checkTitle.VerticalAlignment = VerticalAlignment.Center;
        var checkClose = Ui.Btn("", "icon"); Ui.SetBtn(checkClose, "x", null); checkClose.Click += (_, _) => HideCheck();
        var checkHead = new DockPanel { Margin = new Thickness(0, 0, 0, 8) };
        DockPanel.SetDock(checkClose, Dock.Right); checkHead.Children.Add(checkClose); checkHead.Children.Add(_checkTitle);
        _checkRows = new StackPanel { Spacing = 6 };
        _checkStep = Ui.Label("", 13, false, "MutedBrush", true); _checkStep.Margin = new Thickness(0, 10, 0, 0);
        _checkPanel = new StackPanel { IsVisible = false, Margin = new Thickness(0, 6, 0, 4), Children = { checkHead, _checkRows, _checkStep } };
        var inner = new DockPanel();
        DockPanel.SetDock(_lblCerts, Dock.Top); inner.Children.Add(_lblCerts);
        inner.Children.Add(new ScrollViewer { Content = new StackPanel { Children = { _certList, _checkPanel } }, VerticalScrollBarVisibility = ScrollBarVisibility.Auto });
        var dock = new DockPanel { Margin = new Thickness(24, 18, 24, 20) };
        DockPanel.SetDock(bar, Dock.Top); dock.Children.Add(bar);
        DockPanel.SetDock(_lblPinNote, Dock.Bottom); dock.Children.Add(_lblPinNote);
        dock.Children.Add(Ui.Card(inner));
        return dock;
    }

    private Control BuildSettingsTab()
    {
        Control Row(TextBlock label, Control ctl)
        {
            var d = new DockPanel { Margin = new Thickness(0, 0, 0, 12) };
            DockPanel.SetDock(ctl, Dock.Right); d.Children.Add(ctl);
            label.VerticalAlignment = VerticalAlignment.Center; d.Children.Add(label);
            return d;
        }
        _lblSetAppearance = Ui.Label("", 15, true); _lblSetAppearance.FontWeight = FontWeight.Bold; _lblSetAppearance.Margin = new Thickness(0, 0, 0, 10);
        _lblSetLang = Ui.Label(""); _lblSetTheme = Ui.Label("");
        _cmbLang = new ComboBox { Width = 190 };
        foreach (var lang in Loc.PickerOrder) _cmbLang.Items.Add(Loc.Flag(lang) + "  " + Loc.NativeName(lang));
        _cmbLang.SelectionChanged += (_, _) =>
        {
            if (_loading || _cmbLang.SelectedIndex < 0) return;
            Loc.Current = Loc.PickerOrder[_cmbLang.SelectedIndex]; _cfg.Lang = Loc.Current.ToString(); _cfg.Save(); ApplyLanguage();
        };
        _cmbTheme = new ComboBox { Width = 190 };
        for (int i = 0; i < 3; i++) _cmbTheme.Items.Add("");
        _cmbTheme.SelectionChanged += (_, _) =>
        {
            if (_loading || _cmbTheme.SelectedIndex < 0) return;
            _cfg.Theme = _cmbTheme.SelectedIndex switch { 1 => "light", 2 => "dark", _ => "system" };
            ApplyTheme(_cfg.Theme); _cfg.Save();
        };
        var appearance = Ui.Card(new StackPanel { Children = { _lblSetAppearance, Row(_lblSetLang, _cmbLang), Row(_lblSetTheme, _cmbTheme) } });
        appearance.Margin = new Thickness(0, 0, 0, 16);

        _lblSetPrivacy = Ui.Label("", 15, true); _lblSetPrivacy.FontWeight = FontWeight.Bold; _lblSetPrivacy.Margin = new Thickness(0, 0, 0, 6);
        _chkMask = new CheckBox(); _chkPrintJmbg = new CheckBox();
        _lblAutoHide = Ui.Label("", 13, false, "TextBrush", true);
        _txtAutoHide = new TextBox { Width = 70, TextAlignment = TextAlignment.Center };
        _txtAutoHide.LostFocus += (_, _) => SettingChanged();
        var hide = new DockPanel { Margin = new Thickness(0, 6, 0, 0) };
        DockPanel.SetDock(_txtAutoHide, Dock.Right); hide.Children.Add(_txtAutoHide);
        _lblAutoHide.VerticalAlignment = VerticalAlignment.Center; _lblAutoHide.Margin = new Thickness(0, 0, 12, 0); hide.Children.Add(_lblAutoHide);
        var privacy = Ui.Card(new StackPanel { Children = { _lblSetPrivacy, _chkMask, _chkPrintJmbg, hide } });
        privacy.Margin = new Thickness(0, 0, 0, 16);

        _lblSetBehavior = Ui.Label("", 15, true); _lblSetBehavior.FontWeight = FontWeight.Bold; _lblSetBehavior.Margin = new Thickness(0, 0, 0, 6);
        _chkAutoRead = new CheckBox(); _chkAutoUpdate = new CheckBox();
        var behavior = Ui.Card(new StackPanel { Children = { _lblSetBehavior, _chkAutoRead, _chkAutoUpdate } });

        foreach (var c in new[] { _chkMask, _chkPrintJmbg, _chkAutoRead, _chkAutoUpdate }) c.IsCheckedChanged += (_, _) => SettingChanged();

        _chkDemo = new CheckBox();
        _lblDemoHint = Ui.Label("", 12, false, "MutedBrush", true); _lblDemoHint.Margin = new Thickness(28, 0, 0, 0);
        _chkDemo.IsCheckedChanged += (_, _) =>
        {
            if (_loading) return;
            if (_chkDemo.IsChecked == true)
            {
                // a card operation is still running: it would put real data over the demo data, so wait for it
                if (_busy) { _loading = true; _chkDemo.IsChecked = false; _loading = false; return; }
                ShowDemoData();
            }
            else HideDemoData();
        };
        var demo = Ui.Card(new StackPanel { Children = { _chkDemo, _lblDemoHint } });
        demo.Margin = new Thickness(0, 16, 0, 0);

        _btnCopyLogs = Ui.Btn(""); _btnCopyLogs.HorizontalAlignment = HorizontalAlignment.Left; _btnCopyLogs.Click += async (_, _) => await CopyLogs();
        _lblCopyLogsHint = Ui.Label("", 12, false, "MutedBrush", true); _lblCopyLogsHint.Margin = new Thickness(0, 8, 0, 0);
        var logs = Ui.Card(new StackPanel { Children = { _btnCopyLogs, _lblCopyLogsHint } });
        logs.Margin = new Thickness(0, 16, 0, 0);

        return new ScrollViewer
        {
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            Content = new StackPanel { Margin = new Thickness(24, 18, 24, 20), Width = 560, HorizontalAlignment = HorizontalAlignment.Left, Children = { appearance, privacy, behavior, demo, logs, BuildDiagCard() } },
        };
    }

    private Control BuildAboutTab()
    {
        var logo = new Image { Width = 112, Height = 112, HorizontalAlignment = HorizontalAlignment.Center };
        try { logo.Source = new Bitmap(Avalonia.Platform.AssetLoader.Open(new Uri("avares://SuperCelik/Assets/icon.png"))); } catch { }
        _lblAboutTitle = Ui.Label("", 26, true); _lblAboutTitle.FontWeight = FontWeight.Bold; _lblAboutTitle.HorizontalAlignment = HorizontalAlignment.Center; _lblAboutTitle.Margin = new Thickness(0, 12, 0, 8);
        _lblAboutText = Ui.Label("", 13, false, "MutedBrush", true); _lblAboutText.TextAlignment = TextAlignment.Center;
        _lblBeta = Ui.Label("", 13, true, "AccentBrush", true); _lblBeta.TextAlignment = TextAlignment.Center; _lblBeta.Margin = new Thickness(0, 14, 0, 0);
        _btnFeedback = Ui.Btn(""); _btnFeedback.HorizontalAlignment = HorizontalAlignment.Center; _btnFeedback.Margin = new Thickness(0, 10, 0, 0); _btnFeedback.Click += (_, _) => OpenUrl(FeedbackUrl);
        _lblVersion = Ui.Label("", 13, true); _lblVersion.HorizontalAlignment = HorizontalAlignment.Center; _lblVersion.Margin = new Thickness(0, 18, 0, 8);
        _lblVersion.PointerReleased += (_, _) => VersionTapped();
        _btnCheckUpdates = Ui.Btn(""); _btnCheckUpdates.Click += async (_, _) => await CheckUpdates();
        _btnWhatsNew = Ui.Btn(""); _btnWhatsNew.Click += (_, _) => OpenUrl(ChangelogUrl);
        var updateButtons = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 10, HorizontalAlignment = HorizontalAlignment.Center, Children = { _btnCheckUpdates, _btnWhatsNew } };
        _lblUpdateStatus = Ui.Label("", 13, false, "MutedBrush", true); _lblUpdateStatus.HorizontalAlignment = HorizontalAlignment.Center; _lblUpdateStatus.TextAlignment = TextAlignment.Center; _lblUpdateStatus.Margin = new Thickness(0, 10, 0, 0);
        var card = Ui.Card(new StackPanel { HorizontalAlignment = HorizontalAlignment.Center, Children = { logo, _lblAboutTitle, _lblAboutText, _lblBeta, _btnFeedback, _lblVersion, updateButtons, _lblUpdateStatus } }, new Thickness(40, 32));
        card.HorizontalAlignment = HorizontalAlignment.Center; card.VerticalAlignment = VerticalAlignment.Center; card.MaxWidth = 520;
        return new Grid { Children = { card } };
    }

    // ======================= language / texts =======================
    private void ApplyLanguage()
    {
        Title = Loc.T("appTitle") + " (beta)";
        _lblBrand.Text = Loc.T("appTitle"); _lblBrandSub.Text = Loc.T("brandSub") + " · beta";
        ToolTip.SetTip(_btnRefresh, Loc.T("refresh"));
        Ui.SetBtn(_btnRead, "user-round", Loc.T("readCard")); Ui.SetBtn(_btnReadBig, "user-round", Loc.T("readCard"));
        Ui.SetBtn(_btnPrint, "printer", Loc.T("printCard")); Ui.SetBtn(_btnPdf, "save", Loc.T("savePdf")); Ui.SetBtn(_btnVerify, "check", Loc.T("verifySignature"));
        Ui.SetBtn(_btnMore, "ellipsis", Loc.T("more"));
        Ui.SetBtn(_btnReadToken, "key-round", Loc.T("readToken")); Ui.SetBtn(_btnChangePin, "lock", Loc.T("changePin")); Ui.SetBtn(_btnUnblockPin, "lock-open", Loc.T("unblockPin")); Ui.SetBtn(_btnSignFile, "pen-line", Loc.T("signFile"));
        Ui.SetBtn(_btnWhatsNew, "info", Loc.T("whatsNew")); Ui.SetBtn(_btnReaderHelp, "circle-help", Loc.T("readerHelp"));
        Ui.SetBtn(_btnCheckUpdates, "refresh-cw", Loc.T("checkUpdates")); Ui.SetBtn(_btnUpdate, "download", Loc.T("updateNow"));
        _tabButtons[0].Content = Loc.T("tabPersonal"); _tabButtons[1].Content = Loc.T("tabToken"); _tabButtons[2].Content = Loc.T("tabSettings"); _tabButtons[3].Content = Loc.T("tabAbout");
        ApplyVehicleLanguage();
        _lblCerts.Text = Loc.T("certificates"); _lblPinNote.Text = Loc.T(BrowserSetup.HasModule ? "loginEupravaNote" : "loginEupravaNoteManual");
        Ui.SetBtn(_btnLoginEu, "log-in", Loc.T("loginEuprava")); Ui.SetBtn(_btnSetupBrowser, "plug", Loc.T("setupBrowser"));
        if (_checkPanel != null) RenderCheck();
        _lblAboutTitle.Text = Loc.T("appTitle"); _lblAboutText.Text = Loc.T("aboutText"); _lblBeta.Text = "BETA · " + Loc.T("betaNote"); Ui.SetBtn(_btnFeedback, "bug", Loc.T("betaReport")); _lblVersion.Text = $"{Loc.T("version")} {Updater.CurrentText}";
        _lblSetLang.Text = Loc.T("language"); _lblSetAppearance.Text = Loc.T("setAppearance"); _lblSetTheme.Text = Loc.T("setTheme");
        _lblSetPrivacy.Text = Loc.T("setPrivacy"); _lblSetBehavior.Text = Loc.T("setBehavior");
        _chkMask.Content = Loc.T("setMask"); _chkPrintJmbg.Content = Loc.T("setPrintJmbg");
        _chkAutoRead.Content = Loc.T("setAutoRead"); _chkAutoUpdate.Content = Loc.T("setAutoUpdate");
        _chkDemo.Content = Loc.T("demoData"); _lblDemoHint.Text = Loc.T("demoHint");
        Ui.SetBtn(_btnCopyLogs, "copy", Loc.T("copyLogs")); _lblCopyLogsHint.Text = Loc.T("copyLogsHint");
        _lblAutoHide.Text = Loc.T("setAutoHide");
        _loading = true;
        var ti = _cmbTheme.SelectedIndex;
        _cmbTheme.Items.Clear();
        foreach (var k in new[] { "themeSystem", "themeLight", "themeDark" }) _cmbTheme.Items.Add(Loc.T(k));
        _cmbTheme.SelectedIndex = ti < 0 ? 0 : ti;
        _loading = false;
        BuildMoreMenu();
        if (_newVersion != null) _lblUpdate.Text = string.Format(Loc.T("updateAvailable"), _newVersion.ToString(3));
        UpdateCardLabel();
        RenderAll();
    }

    private void RenderAll() { RenderPersonal(); RenderSig(); RenderToken(); UpdateEnabled(); }

    private void UpdateEnabled()
    {
        bool can = _cardPresent && !_busy;
        _btnRead.IsEnabled = _btnReadBig.IsEnabled = can;
        _btnReadToken.IsEnabled = _btnChangePin.IsEnabled = _btnUnblockPin.IsEnabled = _btnSignFile.IsEnabled = can;
        _btnVerify.IsEnabled = can && _vehicle == null;
        if (_diagRun != null) _diagRun.IsEnabled = can;
        bool has = (_personal != null || _vehicle != null) && !_busy;
        _btnPrint.IsEnabled = _btnPdf.IsEnabled = _btnMore.IsEnabled = has;
    }

    // ======================= busy / errors =======================
    private async Task Run(Func<Task> work)
    {
        if (_busy || _demo) return;           // demo data on screen: no real reader access
        _busy = true; _busyBar.IsVisible = true; UpdateCardLabel();
        try { await work(); }
        catch (Exception ex) { ShowProblem(ex); }
        finally { _busy = false; _busyBar.IsVisible = false; UpdateCardLabel(); }
    }

    private static bool IsServiceDown(CardException ce) =>
        ce.Code is Native.SCARD_E_NO_SERVICE or Native.SCARD_E_SERVICE_STOPPED or Native.SCARD_E_INVALID_HANDLE;

    private void ShowProblem(Exception ex)
    {
        DiagLog.Error(ex);
        string t = "errGenericT", h = "errGenericH";
        if (ex is CardException ce)
        {
            if (IsServiceDown(ce)) { t = "errNoServiceT"; h = "errNoServiceH"; _serviceDown = true; }
            else if (ce.Code == Native.SCARD_E_NO_READERS_AVAILABLE) { t = "errNoReaderT"; h = "errNoReaderH"; }
            else if (ce.Code == Native.SCARD_E_NO_SMARTCARD || ce.Code == Native.SCARD_W_REMOVED_CARD || ce.Code == Native.SCARD_W_UNRESPONSIVE_CARD)
            { t = "errNoCardT"; h = "errNoCardH"; }
            else if (ce.Message.StartsWith("Unsupported card") || ce.Message.StartsWith("No token applet")) { t = "errUnsupportedT"; h = "errUnsupportedH"; }
        }
        _problemBanner.Res(Border.BackgroundProperty, "BadBgBrush"); _lblProblemTitle.Res(TextBlock.ForegroundProperty, "BadBrush");
        _lblProblemTitle.Text = Loc.T(t); _lblProblemHint.Text = Loc.T(h); _lblProblemHint.IsVisible = true;
        ShowBanner(error: true);
    }

    private void ShowBanner(bool error) { _problemBanner.IsVisible = true; _hasError = error; UpdateCardLabel(); }

    // ---- browser sign-in: connect the card module (PKCS#11) to Firefox and Chrome / Chromium ----

    /// One-time offer on the first start (only if there is something to connect).
    private async Task OfferBrowserSetup()
    {
        _cfg.BrowserSetupAsked = true; _cfg.Save();
        if (await BrowserSetup.IsSetUp()) return;
        if (await Dialogs.Confirm(this, Loc.T("setupBrowser"), Loc.T("setupAsk"), Loc.T("setupConnect"), Loc.T("setupLater"))) await SetupBrowser();
    }

    /// The user agreed once: when a browser (a new Firefox profile, a browser installed later, the app moved) lacks the module,
    /// connect it again without asking. Silent unless something was actually connected.
    private async Task KeepBrowserSetup()
    {
        try { if (!await BrowserSetup.IsSetUp()) await SetupBrowser(quiet: true); }
        catch { }
    }

    /// "Sign in to eUprava": connects the module first if the browsers do not have it yet (asking only the first time), then opens the page.
    private async Task LoginEu()
    {
        try
        {
            if (!_demo && BrowserSetup.HasModule && !await BrowserSetup.IsSetUp())
            {
                if (_cfg.BrowserSetupAccepted) await SetupBrowser(quiet: true);
                else if (await Dialogs.Confirm(this, Loc.T("setupBrowser"), Loc.T("setupAsk"), Loc.T("setupConnect"), Loc.T("setupLater"))) await SetupBrowser();
            }
        }
        catch { }
        OpenUrl(EuLoginUrl);
    }

    /// Connects the card module to the browsers. `quiet`: a background re-check, so only a success is announced.
    private async Task SetupBrowser(bool quiet = false)
    {
        try
        {
            var r = await BrowserSetup.Setup();
            var sandbox = r.Sandboxed is { Count: > 0 } ? "\n" + string.Format(Loc.T("setupSandboxed"), string.Join(", ", r.Sandboxed)) : "";
            if (r.Kind is "done" or "partial")
            {
                if (quiet && !r.Changed) return;                      // a background re-check has nothing to say when nothing was connected
                if (!_cfg.BrowserSetupAccepted) { _cfg.BrowserSetupAccepted = true; _cfg.Save(); }
                var text = string.Format(Loc.T("setupDone"), string.Join(", ", r.Names));
                if (r.Kind == "partial") text += "\n" + ProblemText(r);
                ShowInfo(text + sandbox);
                return;
            }
            if (quiet) return;
            switch (r.Kind)
            {
                case "notool": ShowInfo(Loc.T("setupNoTool")); break;
                case "noservice" or "oldlibc" or "nolib": ShowInfo(ProblemText(r) + sandbox); break;
                case "none": ShowInfo(string.Format(Loc.T("setupNone"), r.Detail)); break;
                case "sandboxed": ShowInfo(sandbox.TrimStart('\n')); break;
                case "nomodule": ShowInfo(Loc.T("loginEupravaNoteManual")); break;
                default: ShowInfo(ProblemText(r) + sandbox); break;
            }
        }
        catch (Exception ex) { if (!quiet) ShowInfo(string.Format(Loc.T("setupFailed"), ex.Message)); }
    }

    /// "Check browser sign-in": what the app sees (reader, card), what the browsers have (the module), what the module itself sees, and the one
    /// thing to do next, in the certificates card. The browsers' view comes from NSS (`modutil -list` loads the module the way a browser does),
    /// so it is the real one.
    /// The one browser button: connects what is not connected yet (a background-style attempt, so only a success is announced), then shows the check.
    private async Task SetupAndCheckBrowser()
    {
        _btnSetupBrowser.IsEnabled = false;
        try
        {
            // a stuck pcscd or modutil must not keep the check from appearing: give the setup a while, then show what the check finds
            // (the setup goes on in the background and announces itself if it connects something)
            if (!_demo) await Task.WhenAny(SetupBrowser(quiet: true), Task.Delay(TimeSpan.FromSeconds(25)));
        }
        finally { _btnSetupBrowser.IsEnabled = true; }
        await CheckBrowser();
    }

    private async Task CheckBrowser()
    {
        try
        {
            var d = _demo ? new BrowserSetup.Diagnosis("checked", new() { "Firefox", "Chrome" }, new(), new(), true, null, 1, "Super Čelik")
                          : await BrowserSetup.Diagnose();
            _checkShown = new CheckShown(d, _readers.Count, _cardPresent);
            RenderCheck();
            Dispatcher.UIThread.Post(() => _checkPanel.BringIntoView());      // the certificates can fill the card: scroll the result into view
        }
        catch (Exception ex) { ShowInfo(string.Format(Loc.T("setupFailed"), ex.Message)); }
    }

    private void HideCheck() { _checkShown = null; if (_checkPanel != null) _checkPanel.IsVisible = false; }

    /// Draws the last check (again after a language change): up to three lines with a tick or a cross, then what to do.
    private void RenderCheck()
    {
        if (_checkShown == null) { _checkPanel.IsVisible = false; return; }
        var (d, readers, card) = _checkShown;
        _checkTitle.Text = Loc.T("chkTitle");
        _checkRows.Children.Clear();
        void Row(bool ok, string text)
        {
            var row = new Grid { ColumnDefinitions = new ColumnDefinitions("Auto,*") };
            var mark = Ui.Mark(ok); mark.Margin = new Thickness(0, 1, 8, 0);
            var label = Ui.Label(text, 13, false, "TextBrush", true); Grid.SetColumn(label, 1);
            row.Children.Add(mark); row.Children.Add(label);
            _checkRows.Children.Add(row);
        }
        if (d.Kind == "checked")
        {
            Row(card, Loc.T(card ? "chkCardOk" : readers == 0 ? "chkNoReader" : "chkNoCard"));
            if (d.Missing.Count > 0) Row(false, string.Format(Loc.T("chkNotConnected"), string.Join(", ", d.Missing)));
            else if (!d.Loaded) Row(false, Loc.T("chkNotLoaded"));
            else
            {
                Row(true, string.Format(Loc.T("chkConnected"), string.Join(", ", d.Connected)));
                Row(d.Token.Length > 0, Loc.T(d.Token.Length > 0 ? "chkSeesCard" : d.Slots == 0 ? "chkNoSeeReader" : "chkNoSeeCard"));
            }
        }
        if (d.Kind == "checked" && d.Sandboxed.Count > 0) Row(false, string.Format(Loc.T("chkSandboxed"), string.Join(", ", d.Sandboxed)));     // a browser from Snap / Flatpak next to the others
        _checkStep.Text = CheckStepText(d, BrowserSetup.NextStep(d, readers, card));
        _checkPanel.IsVisible = true;
    }

    private static string CheckStepText(BrowserSetup.Diagnosis d, string step) => step switch
    {
        "nomodule" => Loc.T("loginEupravaNoteManual"),
        "notool" => Loc.T("setupNoTool"),
        "none" => string.Format(Loc.T("setupNone"), BrowserSetup.ModulePath),
        "sandboxed" => string.Format(Loc.T("setupSandboxed"), string.Join(", ", d.Sandboxed)),
        "stuck" => Loc.T("stepStuck"),
        "connect" => Loc.T("stepConnect"),
        "noservice" => Loc.T("stepNoService"),
        "oldlibc" => Loc.T("setupOldLibc"),
        "nolib" => Loc.T("stepNoLib"),
        "noload" => Loc.T("stepNoLoad"),
        "noreader" => Loc.T("stepNoReader"),
        "nocard" => Loc.T("stepNoCard"),
        "reinsert" => Loc.T("stepReinsert"),
        _ => Loc.T("stepOk"),
    };

    /// What went wrong, in words the user can act on (the raw NSS text only when nothing more specific is known).
    private static string ProblemText(BrowserSetup.Result r) => r.Why switch
    {
        "noservice" => Loc.T("setupNoService"),
        "oldlibc" => Loc.T("setupOldLibc"),
        "nolib" => Loc.T("setupNoPcscLib"),
        _ => string.Format(Loc.T("setupFailed"), r.Detail),
    };

    private void ShowInfo(string text)
    {
        _problemBanner.Res(Border.BackgroundProperty, "BannerBrush"); _lblProblemTitle.Res(TextBlock.ForegroundProperty, "TextBrush");
        // the first line in bold, a longer explanation (the messages about the browsers can have several sentences) in the normal weight below it
        int nl = text.IndexOf('\n');
        _lblProblemTitle.Text = nl < 0 ? text : text.Substring(0, nl);
        _lblProblemHint.Text = nl < 0 ? "" : text.Substring(nl + 1);
        _lblProblemHint.IsVisible = nl >= 0;
        ShowBanner(error: false);
    }

    private void HideProblem()
    {
        _problemBanner.IsVisible = false;
        if (_hasError) { _hasError = false; UpdateCardLabel(); }
    }

    // ======================= readers + automatic card detection =======================
    private ReaderMood Mood =>
        _busy ? ReaderMood.Busy : _readers.Count == 0 ? ReaderMood.NoReader : _hasError ? ReaderMood.Error
        : _cardPresent ? ReaderMood.Ready : ReaderMood.Waiting;

    private void UpdateCardLabel()
    {
        var mood = Mood;
        _lblReader.Text = _readers.Count == 1 ? _readers[0] : "";
        _lblReader.IsVisible = _readers.Count == 1;
        _cmbReader.IsVisible = _readers.Count > 1;
        _emptyMascot.Set(mood);
        string title = mood switch { ReaderMood.Busy => "statusReading", ReaderMood.NoReader => "emptyNoReaderT", _ => _cardPresent ? "emptyReadyT" : "emptyNoCardT" };
        string hint = mood switch { ReaderMood.Busy => null, ReaderMood.NoReader => "emptyNoReaderH", _ => _cardPresent ? "emptyReadyH" : "emptyNoCardH" };
        _lblEmptyTitle.Text = Loc.T(title);
        _lblHint.Text = hint == null ? "" : Loc.T(hint);
        _btnReaderHelp.IsVisible = mood == ReaderMood.NoReader;      // which reader to get: the page opens in the browser
        _btnReadBig.Opacity = _cardPresent && !_busy ? 1 : 0;
        _btnReadBig.IsHitTestVisible = _cardPresent && !_busy;
        if (_keyMascot != null) _keyMascot.Set(mood);
        UpdateEnabled();
    }

    private void FillReaders(List<string> readers)
    {
        var prev = Reader;
        _loading = true;
        _cmbReader.Items.Clear();
        foreach (var r in readers) _cmbReader.Items.Add(r);
        if (readers.Count == 0) _cmbReader.Items.Add(Loc.T("noReader"));
        _cmbReader.SelectedItem = prev != null && readers.Contains(prev) ? prev : _cmbReader.Items[0];
        _loading = false;
        _readers = readers;
    }

    /// A fresh PC/SC context: needed when pcscd was not running at the start (the context is then empty for good).
    private void ResetPc() { try { _pc.Dispose(); } catch { } _pc = new PcscService(); }

    private void Refresh()
    {
        if (_demo) return;
        try
        {
            if (_serviceDown) { ResetPc(); _serviceDown = false; }
            FillReaders(_pc.ListReaders());
            var cardWas = _cardPresent;
            _cardPresent = _readers.Count > 0 && _pc.Atr(Reader) != null;
            if (cardWas != _cardPresent) HideCheck();
            HideProblem();
            UpdateCardLabel();
        }
        catch (CardException ce) when (IsServiceDown(ce))
        {
            _readers = new(); _cardPresent = false; FillReaders(_readers); ShowProblem(ce);
        }
        catch (Exception ex) { ShowProblem(ex); }
    }

    private async void Poll()
    {
        if (_busy || _demo) return;
        try
        {
            if (_serviceDown) { ResetPc(); }
            var readers = _pc.ListReaders();
            if (_serviceDown) { _serviceDown = false; HideProblem(); }
            if (!readers.SequenceEqual(_readers)) { FillReaders(readers); UpdateCardLabel(); }
            bool present = _readers.Count > 0 && _pc.Atr(Reader) != null;
            if (present == _cardPresent) return;
            _cardPresent = present;
            HideCheck();                                          // what the check found was about the card that was in the reader then
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
        catch (CardException ce) when (IsServiceDown(ce)) { if (!_serviceDown) { _serviceDown = true; _readers = new(); _cardPresent = false; _personal = null; _token = null; _sig = null; _revealAll = false; RenderAll(); FillReaders(_readers); ShowProblem(ce); } }
        catch { /* reader unplugged mid-poll: the next tick or a manual refresh reports it */ }
    }

    private void CheckIdle()
    {
        if (_demo || _cfg.AutoHideMinutes <= 0 || (_personal == null && _token == null && _vehicle == null)) return;
        if ((DateTime.Now - _lastActivity).TotalMinutes < _cfg.AutoHideMinutes) return;
        _personal = null; _token = null; _sig = null; _vehicle = null; _revealAll = false;
        RenderAll();
        ShowInfo(Loc.T("autoHidden"));
    }

    // ======================= personal =======================
    private async Task ReadCardAsync()
    {
        var reader = Reader;
        // one button for every card: an ID card, a foreigner card, a residence permit or a vehicle registration card
        if (await Task.Run(() => SerbianCard.HasEidApplet(_pc, reader)))
        {
            var p = await Task.Run(() => SerbianCard.ReadPersonalData(_pc, reader));
            _personal = p; _vehicle = null; _sig = null; _revealAll = false; HideProblem();
        }
        else
        {
            var v = await Task.Run(() => VehicleCard.Read(_pc, reader));
            _vehicle = v; _personal = null; _sig = null; _revealAll = false; HideProblem();
            ShowInfo(Loc.T("vehNote"));
        }
        RenderAll();
    }

    internal static List<(string Key, string Value)> Rows(PersonalData p)
    {
        var f = p.Fixed; var d = p.Document;
        var rows = new List<(string, string)> { ("surname", f.Surname), ("givenName", f.GivenName) };
        if (p.CardType == CardType.ID2014 && f.ParentGivenName.Length > 0) rows.Add(("parentName", f.ParentGivenName));
        rows.Add(("dob", f.DateOfBirth)); rows.Add(("sex", f.Sex));
        rows.Add(("placeOfBirth", string.Join(", ", new[] { f.PlaceOfBirth, f.CommunityOfBirth, f.StateOfBirth }.Where(x => x.Length > 0))));
        if (f.NationalityFull.Length > 0) rows.Add(("nationality", f.NationalityFull));
        rows.Add(("jmbg", f.PersonalNumber));
        rows.Add(("address", p.Variable.Formatted));
        rows.Add(("docNumber", d.DocRegNo));
        if (d.DocumentSerialNumber.Length > 0) rows.Add(("docSerial", d.DocumentSerialNumber));
        rows.Add(("issuedBy", d.IssuingAuthority)); rows.Add(("issueDate", d.IssuingDate)); rows.Add(("expiryDate", d.ExpiryDate));
        return rows;
    }

    private static string DocTypeName(CardType t) => Loc.T(t switch { CardType.IF2020 => "docIF", CardType.RP2024 => "docRP", _ => "docID" });

    private static bool TryDate(string s, out DateTime d) => DateTime.TryParseExact(s, "dd.MM.yyyy", CultureInfo.InvariantCulture, DateTimeStyles.None, out d);

    private static void SetExpiry(Border pill, DateTime until)
    {
        int days = (until.Date - DateTime.Today).Days;
        if (days < 0) Ui.SetPill(pill, "✘  " + Loc.T("expiredOn"), "BadBrush", "BadBgBrush");
        else if (days <= 90) Ui.SetPill(pill, "⚠  " + string.Format(Loc.T("expiresIn"), days), "WarnBrush", "WarnBgBrush");
        else Ui.SetPill(pill, "✔  " + string.Format(Loc.T("expiresIn"), days), "OkBrush", "OkBgBrush");
    }

    private async Task CopyLogs()
    {
        string module = BrowserSetup.HasModule ? "card module present" : "no card module in this build";
        string state = "Readers: " + (_readers.Count == 0 ? "none" : string.Join(", ", _readers)) + "; card in the reader: " + (_cardPresent ? "yes" : "no")
            + "; " + module + (Packaging.IsFlatpak ? "; Flatpak" : "");
        try { await CopyText(DiagLog.Report(Updater.CurrentText, state)); ShowInfo(Loc.T("copyLogsDone")); }
        catch (Exception ex) { ShowProblem(ex); }
    }

    private async Task CopyText(string text)
    {
        var cb = Clipboard;
        if (cb != null) await cb.SetTextAsync(text);
    }

    private void RenderPersonal()
    {
        _btnEye.IsVisible = (_personal != null || _vehicle != null) && _cfg.MaskSensitive;
        Ui.SetBtn(_btnEye, _revealAll ? "eye-off" : "eye", _revealAll ? Loc.T("hideValue") : Loc.T("reveal"));
        _fields.Children.Clear();
        _imgPortrait.Source = null;
        bool has = _personal != null || _vehicle != null;
        _personalContent.IsVisible = has;
        _emptyState.IsVisible = !has;
        if (!has) return;

        bool veh = _vehicle != null;
        _portraitFrame.IsVisible = !veh;     // a vehicle has no photo
        _lblName.Text = veh ? _vehicle.RegistrationNumber : $"{_personal.Fixed.GivenName} {_personal.Fixed.Surname}".Trim();
        _lblDocType.Text = veh ? Loc.T("vehTitle") : DocTypeName(_personal.CardType);
        _imgPortrait.Source = veh ? null : Ui.LoadImage(_personal.Portrait);
        _pillExpiry.IsVisible = true;
        if (TryDate(veh ? _vehicle.ExpiryDate : _personal.Document.ExpiryDate, out var until)) SetExpiry(_pillExpiry, until); else _pillExpiry.IsVisible = false;

        foreach (var (key, value) in veh ? VehicleRows.Build(_vehicle) : Rows(_personal))
        {
            bool hidden = (Sensitive.Contains(key) || Array.IndexOf(VehicleRows.Sensitive, key) >= 0) && _cfg.MaskSensitive && !_revealAll;
            var copy = Ui.Btn("", "icon"); Ui.SetBtn(copy, "copy", null); copy.Opacity = 0.55; copy.VerticalAlignment = VerticalAlignment.Bottom;
            ToolTip.SetTip(copy, Loc.T("copy"));
            var v = value;
            copy.Click += async (_, _) => { try { await CopyText(v); Ui.SetBtn(copy, "check", null); await Task.Delay(1000); Ui.SetBtn(copy, "copy", null); } catch { } };
            var text = new StackPanel();
            text.Children.Add(Ui.Label(Loc.T(key), 11, false, "MutedBrush"));
            // plain text, not an input box: nothing to click or edit, the field has only its copy button
            var tb = Ui.Label(hidden ? "••••••••••" : value, 14, true, "TextBrush", true);
            tb.FontWeight = FontWeight.SemiBold; tb.Margin = new Thickness(0, 4);
            text.Children.Add(tb);
            var cell = new DockPanel { Width = 290, Margin = new Thickness(0, 0, 14, 14), Background = Brushes.Transparent };
            DockPanel.SetDock(copy, Dock.Right); cell.Children.Add(copy); cell.Children.Add(text);
            cell.PointerEntered += (_, _) => copy.Opacity = 1;
            cell.PointerExited += (_, _) => copy.Opacity = 0.55;
            _fields.Children.Add(cell);
        }
    }

    // ---- "More" menu ----
    private void BuildMoreMenu()
    {
        _moreMenu.Items.Clear();
        MenuItem Item(string text, Func<Task> a) { var mi = new MenuItem { Header = text }; mi.Click += async (_, _) => await a(); return mi; }
        _moreMenu.Items.Add(Item(Loc.T("copyAll"), CopyAll));
        _moreMenu.Items.Add(Item(Loc.T("savePhoto"), SavePhoto));
        _moreMenu.Items.Add(Item(Loc.T("exportJson"), ExportJson));
    }

    private async Task<string> PickSave(string name, string ext, string label)
    {
        var f = await StorageProvider.SaveFilePickerAsync(new FilePickerSaveOptions
        {
            SuggestedFileName = name, DefaultExtension = ext,
            FileTypeChoices = new[] { new FilePickerFileType(label) { Patterns = new[] { "*." + ext } } },
        });
        return f?.TryGetLocalPath();
    }

    private async Task CopyAll()
    {
        if (_personal == null) return;
        var sb = new StringBuilder();
        foreach (var (k, v) in Rows(_personal)) sb.AppendLine($"{Loc.T(k)}: {v}");
        try { await CopyText(sb.ToString()); ShowInfo(Loc.T("copied")); } catch (Exception ex) { ShowProblem(ex); }
    }

    private async Task SavePhoto()
    {
        if (_personal?.Portrait == null) return;
        var path = await PickSave("photo.jpg", "jpg", "JPEG");
        if (path != null) File.WriteAllBytes(path, _personal.Portrait);
    }

    private async Task ExportJson()
    {
        if (_personal == null) return;
        var path = await PickSave("SuperCelik.json", "json", "JSON");
        if (path == null) return;
        var obj = new Dictionary<string, string> { ["cardType"] = _personal.CardType.ToString() };
        foreach (var (k, v) in Rows(_personal)) obj[k] = v;
        File.WriteAllText(path, JsonSerializer.Serialize(obj, new JsonSerializerOptions { WriteIndented = true, Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping }));
    }

    private async Task SavePdf()
    {
        if (_personal == null && _vehicle == null) return;
        var path = await PickSave("SuperCelik.pdf", "pdf", "PDF");
        if (path == null) return;
        try { PdfWriter.SaveSheet(_vehicle != null ? VehicleSheet.Build(_vehicle, 793.7, 1122.5, _cfg.PrintJmbg) : PrintSheet.Build(_personal, 793.7, 1122.5, _cfg.PrintJmbg), path); ShowInfo($"{Loc.T("pdfSaved")}: {path}"); }
        catch (Exception ex) { ShowProblem(ex); }
    }

    // ======================= signature =======================
    private async Task VerifyAsync()
    {
        var reader = Reader;
        var (a, b) = await Task.Run(() => (SerbianCard.Verify(_pc, reader, SerbianCard.Block.Fixed), SerbianCard.Verify(_pc, reader, SerbianCard.Block.Variable)));
        _sig = a.Result == SigResult.Invalid ? a : b.Result == SigResult.Invalid ? b : a.Result == SigResult.ChainNotTrusted ? a : b;
        HideProblem(); RenderSig();
    }

    private void RenderSig()
    {
        if (_sig == null) { _pillSig.IsVisible = false; return; }
        switch (_sig.Result)
        {
            case SigResult.Ok: Ui.SetPill(_pillSig, "✔  " + Loc.T("sigOk"), "OkBrush", "OkBgBrush"); break;
            case SigResult.ChainNotTrusted: Ui.SetPill(_pillSig, "⚠  " + Loc.T("sigChain"), "WarnBrush", "WarnBgBrush"); break;
            default: Ui.SetPill(_pillSig, "✘  " + Loc.T("sigBad"), "BadBrush", "BadBgBrush"); break;
        }
    }

    // ======================= token =======================
    private async Task ReadTokenAsync()
    {
        var reader = Reader;
        _token = await Task.Run(() => SerbianCard.ReadToken(_pc, reader));
        HideProblem(); RenderToken();
    }

    private static bool ValidPin(string p) => p != null && p.Length is >= 4 and <= 8 && p.All(c => c is >= '0' and <= '9');

    /// Each wrong PIN/PUK burns a card try: one attempt, no retries.
    private async Task PinOp(Func<Task> work)
    {
        await Run(async () =>
        {
            try { await work(); }
            catch (PinException pe) { ShowInfo(pe.Blocked ? Loc.T("pinBlockedMsg") : string.Format(Loc.T("pinWrong"), pe.TriesLeft)); }
            catch (ArgumentException) { ShowInfo(Loc.T("pinInvalid")); }
        });
    }

    /// Three separate dialogs (current/PUK, new, confirm) so it is always clear which PIN is being asked for.
    private async Task<string[]> AskPinSteps(string title, string firstNoteKey, string firstLabelKey)
    {
        var a = await PinDialog.Ask(this, title, Loc.T(firstNoteKey) + "\n\n" + Loc.T("pinWarn"), Loc.T(firstLabelKey));
        if (a == null) return null;
        var b = await PinDialog.Ask(this, title, Loc.T("pinStepNew"), Loc.T("pinNew"));
        if (b == null) return null;
        var c = await PinDialog.Ask(this, title, Loc.T("pinStepConfirm"), Loc.T("pinNew2"));
        if (c == null) return null;
        return new[] { a[0], b[0], c[0] };
    }

    private async Task ChangePin()
    {
        if (_demo || _busy) return;
        var v = await AskPinSteps(Loc.T("changePin"), "pinStepOld", "pinOld");
        if (v == null) return;
        if (!v.All(ValidPin)) { ShowInfo(Loc.T("pinInvalid")); return; }
        if (v[1] != v[2]) { ShowInfo(Loc.T("pinMismatch")); return; }
        var reader = Reader;
        await PinOp(async () => { await Task.Run(() => SerbianCard.ChangeTokenPin(_pc, reader, v[0], v[1])); ShowInfo(Loc.T("pinChanged")); });
    }

    private async Task UnblockPin()
    {
        if (_demo || _busy) return;
        var v = await AskPinSteps(Loc.T("unblockPin"), "pinStepPuk", "pukEnter");
        if (v == null) return;
        if (!v.All(ValidPin)) { ShowInfo(Loc.T("pinInvalid")); return; }
        if (v[1] != v[2]) { ShowInfo(Loc.T("pinMismatch")); return; }
        var reader = Reader;
        await PinOp(async () => { await Task.Run(() => SerbianCard.UnblockTokenPin(_pc, reader, v[0], v[1])); ShowInfo(Loc.T("pinUnblocked")); });
    }

    private async Task SignFile()
    {
        if (_demo || _busy) return;
        var files = await StorageProvider.OpenFilePickerAsync(new FilePickerOpenOptions { AllowMultiple = false });
        var src = files.FirstOrDefault()?.TryGetLocalPath();
        if (src == null) return;
        var v = await PinDialog.Ask(this, Loc.T("signFile"), Loc.T("pinWarn"), Loc.T("pinEnter"));
        if (v == null) return;
        if (!ValidPin(v[0])) { ShowInfo(Loc.T("pinInvalid")); return; }
        var dst = await PickSave(Path.GetFileName(src) + ".p7s", "p7s", "CMS signature");
        if (dst == null) return;
        var reader = Reader; var pin = v[0];
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
        _certList.Children.Clear();
        _lblTokenInfo.Text = _token == null ? "" : $"{_token.Label}  {_token.Serial}".Trim();
        if (_token == null)
        {
            _keyMascot ??= new MascotArt(MascotCharacter.Key, 170);
            _keyMascot.Set(Mood);
            var hint = Ui.Label(Loc.T("hintToken"), 13, false, "MutedBrush", true);
            hint.TextAlignment = TextAlignment.Center; hint.HorizontalAlignment = HorizontalAlignment.Center; hint.Margin = new Thickness(0, 8, 0, 0);
            _certList.Children.Add(_keyMascot); _certList.Children.Add(hint);
            return;
        }
        foreach (var c in _token.Certificates)
        {
            var box = new StackPanel { Margin = new Thickness(0, 0, 0, 14) };
            var top = new DockPanel();
            var pill = Ui.Pill(new TextBlock(), 4); pill.CornerRadius = new CornerRadius(12); pill.VerticalAlignment = VerticalAlignment.Center;
            Ui.SetPill(pill, c.ChainTrusted ? "✔  " + Loc.T("chainOk") : "⚠  " + Loc.T("sigChain"),
                       c.ChainTrusted ? "OkBrush" : "WarnBrush", c.ChainTrusted ? "OkBgBrush" : "WarnBgBrush");
            DockPanel.SetDock(pill, Dock.Right); top.Children.Add(pill);
            var name = Ui.Label(c.Label.Length > 0 ? c.Label : c.Subject, 14, true); name.VerticalAlignment = VerticalAlignment.Center; top.Children.Add(name);
            box.Children.Add(top);
            if (c.Issuer.Length > 0) { var l = Ui.Label($"{Loc.T("certIssuer")}: {c.Issuer}", 13, false, "MutedBrush"); l.Margin = new Thickness(0, 4, 0, 0); box.Children.Add(l); }
            if (c.NotAfter != default)
            {
                var row = new WrapPanel { Margin = new Thickness(0, 4, 0, 0) };
                var valid = Ui.Label(string.Format(Loc.T("certValid"), c.NotBefore.ToString("dd.MM.yyyy"), c.NotAfter.ToString("dd.MM.yyyy")), 13, false, "MutedBrush");
                valid.VerticalAlignment = VerticalAlignment.Center; valid.Margin = new Thickness(0, 0, 10, 0); row.Children.Add(valid);
                var ep = Ui.Pill(new TextBlock(), 3); ep.CornerRadius = new CornerRadius(12); SetExpiry(ep, c.NotAfter); row.Children.Add(ep);
                box.Children.Add(row);
            }
            var export = Ui.Btn(""); Ui.SetBtn(export, "save", Loc.T("exportCert")); export.Margin = new Thickness(0, 10, 0, 0); export.HorizontalAlignment = HorizontalAlignment.Left;
            var cert = c;
            export.Click += async (_, _) => { var p = await PickSave("certificate.cer", "cer", "Certificate"); if (p != null) File.WriteAllBytes(p, cert.Der); };
            box.Children.Add(export);
            _certList.Children.Add(new Border { BorderThickness = new Thickness(0, 0, 0, 1), Padding = new Thickness(0, 0, 0, 4), Child = box }.Res(Border.BorderBrushProperty, "LineBrush"));
        }
    }

    // ======================= settings =======================
    private void SettingChanged()
    {
        if (_loading) return;
        _cfg.MaskSensitive = _chkMask.IsChecked == true;
        _cfg.PrintJmbg = _chkPrintJmbg.IsChecked == true;
        _cfg.AutoRead = _chkAutoRead.IsChecked == true;
        _cfg.AutoUpdate = _chkAutoUpdate.IsChecked == true;
        _cfg.AutoHideMinutes = int.TryParse(_txtAutoHide.Text, out var m) ? Math.Clamp(m, 0, 240) : 3;
        _txtAutoHide.Text = _cfg.AutoHideMinutes.ToString();
        _cfg.Save();
        RenderPersonal();
    }

    // ======================= updates (notice only) =======================
    private static void OpenUrl(string url)
    {
        if (string.IsNullOrEmpty(url)) return;
        try { Process.Start(new ProcessStartInfo("xdg-open", new[] { url }) { UseShellExecute = false }); } catch { }
    }

    private async Task AutoCheckUpdateAsync()
    {
        try
        {
            var (v, page, _) = await Updater.CheckAsync();
            if (v == null) return;
            _newVersion = v; _newPage = page;
            _lblUpdate.Text = string.Format(Loc.T("updateAvailable"), v.ToString(3));
            _updateBanner.IsVisible = true;
        }
        catch { /* offline: stay silent */ }
    }

    /// "Update": installs the new version by itself when it can (see Updater.Pick), otherwise opens the release page.
    private async Task StartUpdate()
    {
        if (_demo || _updateFailed || !Updater.CanSelfUpdate) {      // after a failed attempt the button opens the release page
            OpenUrl(_newPage); return; }
        _btnUpdate.IsEnabled = false; _btnCheckUpdates.IsEnabled = false;
        try { await Updater.InstallAsync(t => Avalonia.Threading.Dispatcher.UIThread.Post(() => _lblUpdate.Text = t), Loc.T("updDownloading"), Loc.T("updInstalling")); }
        catch (Exception ex)
        {
            _lblUpdate.Text = Loc.T("updateFailed") + ": " + ex.Message;
            _btnUpdate.IsEnabled = true; _btnCheckUpdates.IsEnabled = true;
            Ui.SetBtn(_btnUpdate, "download", Loc.T("openReleasePage"));
            _updateFailed = true;
        }
    }
    private bool _updateFailed;

    private async Task CheckUpdates()
    {
        _lblUpdateStatus.Text = "…";
        try
        {
            var (v, page, reachable) = await Updater.CheckAsync();
            if (!reachable) { _lblUpdateStatus.Text = Loc.T("updateUnavailable"); return; }
            if (v == null) { _lblUpdateStatus.Text = Loc.T("upToDate"); return; }
            _newVersion = v; _newPage = page;
            _lblUpdate.Text = string.Format(Loc.T("updateAvailable"), v.ToString(3));
            _updateBanner.IsVisible = true;
            _lblUpdateStatus.Text = _lblUpdate.Text;
        }
        catch { _lblUpdateStatus.Text = Loc.T("updateUnavailable"); }
    }

    // ======================= demo / screenshots (fictional data) =======================
    private void FillDemoData()
    {
        _cardPresent = true;
        _readers = new() { "Demo Reader" }; FillReaders(_readers);
        _personal = new PersonalData
        {
            CardType = CardType.RP2024,
            Document = new DocumentData { DocRegNo = "001234567", DocumentSerialNumber = "RS1234567", IssuingAuthority = "MUP RS", IssuingDate = "01.01.2024", ExpiryDate = DateTime.Today.AddDays(412).ToString("dd.MM.yyyy"), DocumentName = "Dozvola za privremeni boravak i rad" },
            Fixed = new FixedPersonalData { Surname = "PETROVIĆ", GivenName = "MARKO", Sex = "M", DateOfBirth = "01.01.1990", StateOfBirth = "Srbija", PersonalNumber = "0101990710000", NationalityFull = "Srbija" },
            Variable = new VariablePersonalData { Place = "Beograd", Community = "Stari Grad", Street = "Knez Mihailova", HouseNumber = "1" },
        };
        _sig = new SigStatus { Result = SigResult.Ok };
        // `--vehicle` with the demo: a vehicle registration card instead of the ID card
        if (Environment.GetCommandLineArgs().Contains("--vehicle")) { _vehicle = VehicleRows.Demo(); _personal = null; _sig = null; }
        _token = new TokenInfo { Label = "NetSeT's CardEdge Token", Serial = "RP000000000" };
        _token.Certificates.Add(new TokenCertificate
        {
            Label = "MARKO PETROVIC 000000000 Auth", ChainTrusted = true, Issuer = "MUP Stranci CA 4",
            NotBefore = DateTime.Today.AddMonths(-14), NotAfter = DateTime.Today.AddDays(75), Der = new byte[] { 0 },
        });
    }

    /// Settings > "Show demo data": fictional data on screen, the real reader is not polled meanwhile.
    private void ShowDemoData()
    {
        _demo = true; _serviceDown = false;
        FillDemoData();
        _revealAll = false;
        HideProblem();
        ApplyLanguage();
    }

    /// Back to the real reader.
    private void HideDemoData()
    {
        _demo = false;
        _personal = null; _token = null; _sig = null; _vehicle = null; _revealAll = false; _cardPresent = false; _readers = new();
        FillReaders(_readers);
        ApplyLanguage();
        StartPolling();
        Refresh();
    }

    private void LoadDemo()
    {
        _demo = true;
        _loading = true;
        if (_opts.Dark) { _cfg.Theme = "dark"; ApplyTheme("dark"); }
        FillDemoData();
        var state = _opts.State;
        if (state != null)
        {
            _personal = null; _sig = null; _token = null; _vehicle = null;
            if (state == "noreader") { _readers = new(); FillReaders(_readers); _cardPresent = false; }
            if (state == "nocard") _cardPresent = false;
            if (state == "busy") _busy = true;
        }
        SelectTab(_opts.Tab);
        _loading = false;
        HideProblem();
        ApplyLanguage();
        if (_opts.Problem) ShowProblem(new CardException(Native.SCARD_E_NO_READERS_AVAILABLE, "ListReaders"));
        if (state == "error") ShowProblem(new CardException("Unsupported card (demo)"));

        if (_opts.Pdf != null)
        {
            Opened += (_, _) => Dispatcher.UIThread.Post(() => { PdfWriter.SaveSheet(_vehicle != null ? VehicleSheet.Build(_vehicle, 793.7, 1122.5, true) : PrintSheet.Build(_personal, 793.7, 1122.5, true), _opts.Pdf); Close(); });
        }
        else if (_opts.Shot != null)
        {
            Opened += async (_, _) =>
            {
                await Task.Delay(700);
                var size = new PixelSize((int)Bounds.Width, (int)Bounds.Height);
                using var rtb = new RenderTargetBitmap(size, new Vector(96, 96));
                rtb.Render(this);
                rtb.Save(_opts.Shot);
                Close();
            };
        }
    }
}
