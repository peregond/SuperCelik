using System.Text;

namespace SerbiaID;

// Health insurance card (KZO, RFZO): the data model, the block parser and the rows for the screen.
// STATUS: written from the analysis of the official RFZO reader and its middleware (docs/health-card-protocol.md).
// Confirmed by that analysis ONLY, NOT yet against a real card. The tag <-> name assignment is inferred from the declaration
// order and the field sizes. Pure code (no PC/SC), shared by the Windows and Linux apps and covered by the unit tests.

public sealed class HealthData
{
    // block 0D01 document
    public string InsurerName = "", InsurerId = "", CardId = "", IssueDate = "", ExpiryDate = "", ChipSerial = "", PrintLanguage = "";
    // block 0D02 fixed personal
    public string InsurantNumber = "", Surname = "", SurnameLatin = "", GivenName = "", GivenNameLatin = "", DateOfBirth = "";
    // block 0D03 card validity
    public bool Permanent;
    // block 0D04 administrative
    public string ParentName = "", ParentNameLatin = "", Gender = "", PersonalNumber = "";
    public string Street = "", PostNumber = "", Municipality = "", Place = "", StreetCode = "", HouseNumber = "", Entrance = "", Apartment = "";
    public string RegistrationNumber = "", BasisCode = "", BasisDescription = "";
    public string CarrierRelationship = "", CarrierFamilyMember = "", CarrierPersonalNumber = "", CarrierInsurantNumber = "";
    public string CarrierSurname = "", CarrierSurnameLatin = "", CarrierGivenName = "", CarrierGivenNameLatin = "";
    public string InsuredFrom = "", CountryCode = "", Country = "", BookletIssuerCode = "", InsurerBranch = "", InsurerOffice = "";
    public string TaxpayerName = "", TaxpayerResidence = "", TaxpayerNumber = "", TaxpayerIdNumber = "", TaxpayerActivityCode = "", ParticipationFree = "";

    /// Blocks that could not be read (ids), and tags found in a block that the table does not know (structure only, no values).
    public List<string> Problems = new List<string>();
    public List<string> UnknownTags = new List<string>();

    public string FullName => (GivenName + " " + Surname).Trim();
    public string CarrierFullName => (CarrierGivenName + " " + CarrierSurname).Trim();
}

public static class HealthParser
{
    public const ushort Document = 0x0D01, Fixed = 0x0D02, Card = 0x0D03, Admin = 0x0D04;

    /// Kinds of values: A = ASCII, U = UTF-16LE, D = date DDMMYYYY (ASCII), N = little-endian number.
    private static readonly Dictionary<int, char> Kinds = new Dictionary<int, char>
    {
        [0x611] = 'U', [0x612] = 'A', [0x613] = 'A', [0x615] = 'D', [0x616] = 'D', [0x617] = 'A', [0x618] = 'A',
        [0x621] = 'A', [0x622] = 'U', [0x623] = 'U', [0x624] = 'U', [0x625] = 'U', [0x626] = 'D',
        [0x630] = 'A', [0x631] = 'D', [0x632] = 'D', [0x633] = 'N',
        [0x640] = 'A', [0x641] = 'U', [0x642] = 'U', [0x643] = 'N', [0x644] = 'A', [0x645] = 'U', [0x646] = 'A', [0x647] = 'U', [0x648] = 'U',
        [0x649] = 'A', [0x64A] = 'U', [0x64B] = 'U', [0x64C] = 'U', [0x64D] = 'A', [0x64E] = 'A', [0x64F] = 'U', [0x650] = 'U', [0x651] = 'N',
        [0x652] = 'A', [0x653] = 'A', [0x654] = 'U', [0x655] = 'U', [0x656] = 'U', [0x657] = 'U', [0x658] = 'D', [0x659] = 'A', [0x65A] = 'U',
        [0x65B] = 'A', [0x65C] = 'U', [0x65D] = 'U', [0x65E] = 'U', [0x65F] = 'U', [0x660] = 'A', [0x661] = 'A', [0x662] = 'A', [0x663] = 'A',
    };

    /// The elements of a block file: 4-byte header [id LE16][length LE16], then [tag LE16][length LE16][value]...
    /// Returns null if the header does not match `expectedId` or the declared length is not what the file holds.
    public static Dictionary<int, byte[]> Records(byte[] file, ushort expectedId)
    {
        if (file == null || file.Length < 4) return null;
        if ((file[0] | file[1] << 8) != expectedId) return null;
        int declared = file[2] | file[3] << 8;
        if (declared > file.Length - 4) return null;
        var d = new Dictionary<int, byte[]>();
        int p = 4, end = 4 + declared;
        while (p + 4 <= end)
        {
            int tag = file[p] | file[p + 1] << 8, len = file[p + 2] | file[p + 3] << 8;
            if (p + 4 + len > end) break;
            d[tag] = Compat.Slice(file, p + 4, len);
            p += 4 + len;
        }
        return d;
    }

    /// Text of an element by its kind. Strings are trimmed of padding (NUL / spaces).
    internal static string Value(Dictionary<int, byte[]> d, int tag)
    {
        if (!d.TryGetValue(tag, out var b) || b.Length == 0) return "";
        char kind; if (!Kinds.TryGetValue(tag, out kind)) kind = 'A';
        if (kind == 'N')
        {
            long n = 0;
            for (int i = Math.Min(b.Length, 8) - 1; i >= 0; i--) n = n << 8 | b[i];
            return n.ToString();
        }
        string s;
        // UTF-16LE needs an even length; if a card hands odd bytes, read them as UTF-8 rather than lose the text
        if (kind == 'U') s = b.Length % 2 == 0 ? Encoding.Unicode.GetString(b) : Encoding.UTF8.GetString(b);
        else s = Encoding.UTF8.GetString(b);
        s = s.Trim('\0', ' ');
        return kind == 'D' ? Date(s) : s;
    }

    /// The card stores DDMMYYYY; shown as DD.MM.YYYY like the ID card.
    public static string Date(string s)
    {
        if (s.Length != 8) return s;
        for (int i = 0; i < 8; i++) if (s[i] < '0' || s[i] > '9') return s;
        return s.Substring(0, 2) + "." + s.Substring(2, 2) + "." + s.Substring(4);
    }

    /// Builds the data from the four block files (null = block not read). Never throws on content.
    public static HealthData Parse(byte[] doc, byte[] fix, byte[] card, byte[] admin)
    {
        var h = new HealthData();
        var files = new[] { (Document, doc), (Fixed, fix), (Card, card), (Admin, admin) };
        var rec = new Dictionary<ushort, Dictionary<int, byte[]>>();
        foreach (var (id, f) in files)
        {
            if (f == null) { h.Problems.Add(id.ToString("X4") + ": not read"); continue; }
            var r = Records(f, id);
            if (r == null) { h.Problems.Add(id.ToString("X4") + ": bad header"); continue; }
            rec[id] = r;
            foreach (var t in r.Keys) if (!Kinds.ContainsKey(t)) h.UnknownTags.Add(id.ToString("X4") + "/" + t.ToString("X3") + "/" + r[t].Length);
        }
        Dictionary<int, byte[]> D;
        if (rec.TryGetValue(Document, out D))
        {
            h.InsurerName = Value(D, 0x611); h.InsurerId = Value(D, 0x612); h.CardId = Value(D, 0x613);
            h.IssueDate = Value(D, 0x615); h.ExpiryDate = Value(D, 0x616); h.ChipSerial = Value(D, 0x617); h.PrintLanguage = Value(D, 0x618);
        }
        if (rec.TryGetValue(Fixed, out D))
        {
            h.InsurantNumber = Value(D, 0x621); h.Surname = Value(D, 0x622); h.SurnameLatin = Value(D, 0x623);
            h.GivenName = Value(D, 0x624); h.GivenNameLatin = Value(D, 0x625); h.DateOfBirth = Value(D, 0x626);
        }
        if (rec.TryGetValue(Card, out D))
        {
            if (h.CardId.Length == 0) h.CardId = Value(D, 0x630);
            if (h.IssueDate.Length == 0) h.IssueDate = Value(D, 0x631);
            var exp = Value(D, 0x632);
            if (exp.Length > 0) h.ExpiryDate = exp;          // the validity block is the one that changes when the card is renewed
            h.Permanent = Value(D, 0x633) == "1";
        }
        if (rec.TryGetValue(Admin, out D))
        {
            h.ParentName = Value(D, 0x641); h.ParentNameLatin = Value(D, 0x642);
            var g = Value(D, 0x643); h.Gender = g == "1" ? "M" : g == "2" ? "Ž" : g;
            h.PersonalNumber = Value(D, 0x644); h.Street = Value(D, 0x645); h.PostNumber = Value(D, 0x646);
            h.Municipality = Value(D, 0x647); h.Place = Value(D, 0x648); h.StreetCode = Value(D, 0x649);
            h.HouseNumber = Value(D, 0x64A); h.Entrance = Value(D, 0x64B); h.Apartment = Value(D, 0x64C);
            h.RegistrationNumber = Value(D, 0x64D); h.BasisCode = Value(D, 0x64E); h.BasisDescription = Value(D, 0x64F);
            h.CarrierRelationship = Value(D, 0x650); h.CarrierFamilyMember = Value(D, 0x651);
            h.CarrierPersonalNumber = Value(D, 0x652); h.CarrierInsurantNumber = Value(D, 0x653);
            h.CarrierSurname = Value(D, 0x654); h.CarrierSurnameLatin = Value(D, 0x655);
            h.CarrierGivenName = Value(D, 0x656); h.CarrierGivenNameLatin = Value(D, 0x657);
            h.InsuredFrom = Value(D, 0x658); h.CountryCode = Value(D, 0x659); h.Country = Value(D, 0x65A);
            h.BookletIssuerCode = Value(D, 0x65B); h.InsurerBranch = Value(D, 0x65C); h.InsurerOffice = Value(D, 0x65D);
            h.TaxpayerName = Value(D, 0x65E); h.TaxpayerResidence = Value(D, 0x65F); h.TaxpayerNumber = Value(D, 0x660);
            h.TaxpayerIdNumber = Value(D, 0x661); h.TaxpayerActivityCode = Value(D, 0x662); h.ParticipationFree = Value(D, 0x663);
        }
        return h;
    }
}

/// The rows shown for a health card: (label key, value), empty values left out. Same list in every app.
public static class HealthRows
{
    /// Hidden behind the eye like the ID card's personal number and address.
    public static readonly string[] Sensitive =
        { "hLbo", "hJmbg", "hAddress", "hCardId", "hRfzoNo", "hCarrierName", "hCarrierLbo", "hCarrierJmbg", "hTaxPib", "hTaxId" };

    public static string Address(HealthData h)
    {
        var street = (h.Street + " " + h.HouseNumber).Trim();
        var parts = new List<string> { street };
        if (h.Entrance.Length > 0) parts.Add("ul. " + h.Entrance);
        if (h.Apartment.Length > 0) parts.Add("stan " + h.Apartment);
        parts.Add((h.PostNumber + " " + h.Place).Trim());
        parts.Add(h.Municipality); parts.Add(h.Country);
        var r = new List<string>();
        foreach (var p in parts) if (p.Length > 0) r.Add(p);
        return string.Join(", ", r.ToArray());
    }

    /// (section title key, rows): the insured person, the card, the insurance, the holder and the payer when present.
    public static List<(string Title, List<(string Key, string Value)> Rows)> Sections(HealthData h, bool includeJmbg = true)
    {
        List<(string, string)> G(params (string, string)[] kv)
        {
            var l = new List<(string, string)>();
            foreach (var (k, s) in kv) if (!string.IsNullOrEmpty(s)) l.Add((k, s));
            return l;
        }
        var person = G(("hSurname", h.Surname), ("hGivenName", h.GivenName), ("hParent", h.ParentName), ("hDob", h.DateOfBirth), ("hSex", h.Gender),
            ("hJmbg", includeJmbg ? h.PersonalNumber : ""), ("hLbo", h.InsurantNumber), ("hAddress", Address(h)));
        var card = G(("hInsurer", h.InsurerName), ("hCardId", h.CardId), ("hIssued", h.IssueDate),
            ("hValidUntil", h.Permanent ? "" : h.ExpiryDate), ("hPermanent", h.Permanent ? "✔" : ""), ("hIssuerCode", h.BookletIssuerCode));
        var ins = G(("hBasis", string.Join(" — ", new[] { h.BasisCode, h.BasisDescription }.Where(x => x.Length > 0).ToArray())),
            ("hInsuredFrom", h.InsuredFrom), ("hBranch", h.InsurerBranch), ("hOffice", h.InsurerOffice),
            ("hRfzoNo", h.RegistrationNumber), ("hExempt", h.ParticipationFree));
        var carrier = G(("hCarrierName", h.CarrierFullName), ("hCarrierLbo", h.CarrierInsurantNumber),
            ("hCarrierJmbg", includeJmbg ? h.CarrierPersonalNumber : ""), ("hRelation", h.CarrierRelationship), ("hFamilyMember", h.CarrierFamilyMember));
        var tax = G(("hTaxName", h.TaxpayerName), ("hTaxResidence", h.TaxpayerResidence), ("hTaxPib", h.TaxpayerNumber),
            ("hTaxId", h.TaxpayerIdNumber), ("hTaxActivity", h.TaxpayerActivityCode));
        return new List<(string, List<(string, string)>)>
            { ("hSecPerson", person), ("hSecCard", card), ("hSecInsurance", ins), ("hSecCarrier", carrier), ("hSecTaxpayer", tax) };
    }

    /// For the screen: a heading entry (Key = null) before every non-empty group, then its rows.
    public static List<(string Heading, string Key, string Value)> Entries(HealthData h, bool includeJmbg = true)
    {
        var r = new List<(string, string, string)>();
        foreach (var sec in Sections(h, includeJmbg))
        {
            if (sec.Rows.Count == 0) continue;
            r.Add((sec.Title, null, null));
            foreach (var (k, val) in sec.Rows) r.Add((null, k, val));
        }
        return r;
    }

    public static List<(string Key, string Value)> Build(HealthData h, bool includeJmbg = true)
    {
        var r = new List<(string, string)>();
        foreach (var sec in Sections(h, includeJmbg)) r.AddRange(sec.Rows);
        return r;
    }

    /// Fictional data for demo mode, screenshots and the tests.
    public static HealthData Demo() => new HealthData
    {
        InsurerName = "REPUBLIČKI FOND ZA ZDRAVSTVENO OSIGURANJE", InsurerId = "100000000", CardId = "00000000001",
        IssueDate = "01.01.2024", ExpiryDate = "01.01.2029", ChipSerial = "0000000000000000", PrintLanguage = "sr",
        InsurantNumber = "00000000001", Surname = "PETROVIĆ", SurnameLatin = "PETROVIC", GivenName = "MARKO", GivenNameLatin = "MARKO",
        DateOfBirth = "01.01.1990", ParentName = "JOVAN", ParentNameLatin = "JOVAN", Gender = "M", PersonalNumber = "0101990710000",
        Street = "Knez Mihailova", HouseNumber = "1", PostNumber = "11000", Place = "Beograd", Municipality = "Stari Grad", Country = "Srbija", CountryCode = "688",
        RegistrationNumber = "0000000001", BasisCode = "010", BasisDescription = "Zaposleni", InsuredFrom = "01.01.2015",
        InsurerBranch = "Filijala za grad Beograd", InsurerOffice = "Ispostava Stari Grad", BookletIssuerCode = "001",
        TaxpayerName = "PRIMER D.O.O.", TaxpayerResidence = "Beograd", TaxpayerNumber = "100000000", TaxpayerIdNumber = "0000000000000", TaxpayerActivityCode = "6201",
    };
}
