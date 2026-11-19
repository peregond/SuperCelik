using System.Globalization;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.Shapes;
using Avalonia.Media;

namespace SerbiaID;

/// The printout of the official MUP Čelik application ("ČITAČ ELEKTRONSKE LIČNE KARTE: ŠTAMPA PODATAKA"),
/// reproduced one-to-one: same A4 page, positions (in points), line widths, font sizes, labels and footnotes.
/// It is a standard document — do not restyle it. Same layout as the Windows (PrintSheet) and macOS (MupPrintView) apps.
internal static class PrintSheet
{
    private const double PageW = 595.28, PageH = 841.89;
    private const double LeftMargin = 58.8, RightMargin = 535, TextLeftMargin = 67.3;

    public static Control Build(PersonalData p, double w, double h, bool includeJmbg)
    {
        var page = new Sheet(p, includeJmbg).Draw();
        var root = new Viewbox { Width = w, Height = h, Stretch = Stretch.Uniform, VerticalAlignment = Avalonia.Layout.VerticalAlignment.Top, Child = page };
        var host = new Grid { Width = w, Height = h, Background = Brushes.White };
        host.Children.Add(root);
        host.Measure(new Size(w, h));
        host.Arrange(new Rect(0, 0, w, h));
        return host;
    }

    private sealed class Sheet
    {
        private readonly PersonalData _p;
        private readonly bool _jmbg;
        private readonly Canvas _c = new() { Width = PageW, Height = PageH, Background = Brushes.White };
        private readonly Typeface _face = new(new FontFamily("Arial, Liberation Sans, Arimo, Helvetica, DejaVu Sans"));
        private readonly Canvas _content = new() { Width = PageW, Height = PageH };   // the form itself; may be scaled to fit
        private double _y, _lineWidth = 1, _fontSize = 13.5, _rowStep = 24.67;
        private int _rowCount;
        private const double BottomLimit = 826;

        public Sheet(PersonalData p, bool includeJmbg) { _p = p; _jmbg = includeJmbg; _c.Children.Add(_content); }

        /// The form is laid out top to bottom, so long data (wrapped addresses, a note) pushes the footnotes off the page.
        /// If it does not fit, the rows are packed a little tighter and, as a last resort, the page is scaled down a few percent.
        public Canvas Draw()
        {
            _rowStep = 24.67;
            double natural = Layout();
            double scale = 1;
            if (natural > BottomLimit)
            {
                _rowStep = Math.Max(18, _rowStep - (natural - BottomLimit) / Math.Max(_rowCount, 1));
                double packed = Layout();
                if (packed > BottomLimit) scale = BottomLimit / packed;
            }
            _content.RenderTransformOrigin = RelativePoint.TopLeft;
            _content.RenderTransform = new ScaleTransform(scale, scale);
            return _c;
        }

        /// Draws the whole page afresh and returns the y where it ends.
        private double Layout()
        {
            _content.Children.Clear();
            _y = 0; _lineWidth = 1; _fontSize = 13.5; _rowCount = 0;
            if (_p.CardType == CardType.IF2020) Foreigner(false);
            else if (_p.CardType == CardType.RP2024) Foreigner(true);
            else Regular();
            return _y;
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
            var img = Ui.LoadImage(_p.Portrait);
            if (img != null)
            {
                var i = new Image { Source = img, Width = 119.9, Height = 159, Stretch = Stretch.Fill };
                Canvas.SetLeft(i, LeftMargin); Canvas.SetTop(i, top);
                _content.Children.Add(i);
            }
            var r = new Rectangle { Width = 179 - LeftMargin, Height = 159, Stroke = Brushes.Black, StrokeThickness = 0.48 };
            Canvas.SetLeft(r, LeftMargin); Canvas.SetTop(r, top);
            _content.Children.Add(r);
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
            _y = top + (Math.Max(Math.Max(l.Count, v.Count), 1) - 1) * 12 + _rowStep;
            _rowCount++;
        }

        private void Text(string s, double x, double y)
        {
            var t = new TextBlock { Text = s, FontFamily = _face.FontFamily, FontSize = _fontSize, Foreground = Brushes.Black };
            Canvas.SetLeft(t, x); Canvas.SetTop(t, y);
            _content.Children.Add(t);
        }

        private void Line(double? width)
        {
            if (width.HasValue) _lineWidth = width.Value;
            _content.Children.Add(new Line { StartPoint = new Point(LeftMargin, _y), EndPoint = new Point(RightMargin, _y), Stroke = Brushes.Black, StrokeThickness = _lineWidth });
        }

        private double Measure(string s) =>
            new FormattedText(s, CultureInfo.InvariantCulture, FlowDirection.LeftToRight, _face, _fontSize, Brushes.Black).WidthIncludingTrailingWhitespace;

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
