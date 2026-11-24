using System.Text;

namespace SerbiaID;

// Vehicle registration card (Saobraćajna dozvola). Parsing is written from the EU directive 1999/37/EC as amended by
// 2003/127/EC (Annex I, chapter III) and from the MUP RS "eVehicle Registration SDK" field table; see docs/cards-research.md.
// STATUS: confirmed against the specification only, NOT yet against a real card.

/// One BER-TLV object (ISO/IEC 7816-4).
public sealed class Tlv
{
    public int Tag;
    public bool Constructed;
    public byte[] Value = new byte[0];
    public List<Tlv> Children = new List<Tlv>();
    public string TagHex => Tag > 0xFFFF ? Tag.ToString("X6") : Tag > 0xFF ? Tag.ToString("X4") : Tag.ToString("X2");
}

public static class Ber
{
    /// Parses a run of TLV objects; trailing zero padding is ignored. Constructed objects are parsed recursively.
    /// Returns null if the bytes are not well-formed BER.
    public static List<Tlv> Parse(byte[] d) => Parse(d, 0, d.Length, 0);

    private static List<Tlv> Parse(byte[] d, int pos, int end, int depth)
    {
        var list = new List<Tlv>();
        if (depth > 8) return null;
        while (pos < end)
        {
            if (d[pos] == 0x00 || d[pos] == 0xFF)           // padding
            {
                for (int i = pos; i < end; i++) if (d[i] != d[pos]) return null;
                break;
            }
            int b0 = d[pos++];
            int tag = b0;
            if ((b0 & 0x1F) == 0x1F)
            {
                int n = 0;
                do
                {
                    if (pos >= end || ++n > 2) return null;
                    tag = tag << 8 | d[pos];
                } while ((d[pos++] & 0x80) != 0);
            }
            if (pos >= end) return null;
            int len = d[pos++];
            if (len >= 0x80)
            {
                int n = len & 0x7F;
                if (n < 1 || n > 3 || pos + n > end) return null;
                len = 0;
                for (int i = 0; i < n; i++) len = len << 8 | d[pos++];
            }
            if (len < 0 || pos + len > end) return null;
            var t = new Tlv { Tag = tag, Constructed = (b0 & 0x20) != 0 };
            t.Value = new byte[len];
            Buffer.BlockCopy(d, pos, t.Value, 0, len);
            if (t.Constructed)
            {
                t.Children = Parse(d, pos, pos + len, depth + 1);
                if (t.Children == null) return null;
            }
            else if (tag == 0x5A && len > 2)
            {
                // The MUP SDK table nests the engine data under '5A', which is a primitive tag by the BER rules.
                // If the value is a well-formed run of TLVs, treat it as constructed (unconfirmed, see docs).
                var inner = Parse(d, pos, pos + len, depth + 1);
                if (inner != null && inner.Count > 0) { t.Constructed = true; t.Children = inner; }
            }
            list.Add(t);
            pos += len;
        }
        return list;
    }

    /// Builds a TLV (used by the tests and the demo data).
    public static byte[] Build(int tag, byte[] value)
    {
        var o = new List<byte>();
        if (tag > 0xFFFF) o.Add((byte)(tag >> 16));
        if (tag > 0xFF) o.Add((byte)(tag >> 8));
        o.Add((byte)tag);
        if (value.Length < 0x80) o.Add((byte)value.Length);
        else if (value.Length < 0x100) { o.Add(0x81); o.Add((byte)value.Length); }
        else { o.Add(0x82); o.Add((byte)(value.Length >> 8)); o.Add((byte)value.Length); }
        o.AddRange(value);
        return o.ToArray();
    }
}

public sealed class VehicleData
{
    // document
    public string StateIssuing = "", CompetentAuthority = "", AuthorityIssuing = "", UnambiguousNumber = "";
    public string IssuingDate = "", ExpiryDate = "", SerialNumber = "";
    // vehicle
    public string RegistrationNumber = "", FirstRegistrationDate = "", YearOfProduction = "", Make = "", Type = "";
    public string CommercialDescription = "", Vin = "", MaxNetPower = "", EngineCapacity = "", FuelType = "";
    public string PowerWeightRatio = "", Mass = "", MaxLadenMass = "", TypeApprovalNumber = "", Seats = "", StandingPlaces = "";
    public string EngineNumber = "", Axles = "", Category = "", Colour = "", SaleBan = "", Load = "";
    // owner and user
    public string OwnerPersonalNo = "", OwnerSurname = "", OwnerName = "", OwnerAddress = "";
    public string UserPersonalNo = "", UserSurname = "", UserName = "", UserAddress = "";

    /// Character set tag 9F37 as read (-1 = absent).
    public int CharsetTag = -1;
    /// Structure of what was not recognised (path/length), no values.
    public List<string> UnknownTags = new List<string>();
    /// true only after the issuer signature has been checked (not implemented: algorithm unknown, see docs).
    public bool SignatureVerified;

    public string OwnerFull => (OwnerName + " " + OwnerSurname).Trim();
    public string UserFull => (UserName + " " + UserSurname).Trim();
}

public static class VehicleParser
{
    /// Parses the content of the registration data files (D001, D011, D021 and the unsigned national file, in any order).
    public static VehicleData Parse(IEnumerable<byte[]> files)
    {
        var v = new VehicleData();
        var trees = new List<List<Tlv>>();
        foreach (var f in files)
        {
            if (f == null) continue;
            var t = Ber.Parse(f);
            if (t != null && t.Count > 0) trees.Add(t);
        }
        foreach (var t in trees) FindCharset(t, v);
        var holder = new string[3];   // A2 (holder in part 1): used as the owner only if there is no A7
        foreach (var t in trees) Walk(t, "", v, holder);
        if (v.OwnerSurname.Length == 0 && v.OwnerName.Length == 0 && v.OwnerAddress.Length == 0)
        {
            v.OwnerSurname = holder[0] ?? ""; v.OwnerName = holder[1] ?? ""; v.OwnerAddress = holder[2] ?? "";
        }
        return v;
    }

    private static void FindCharset(List<Tlv> nodes, VehicleData v)
    {
        foreach (var n in nodes)
        {
            if (n.Tag == 0x9F37 && n.Value.Length > 0 && v.CharsetTag < 0) v.CharsetTag = n.Value[0];
            if (n.Constructed) FindCharset(n.Children, v);
        }
    }

    private static void Walk(List<Tlv> nodes, string path, VehicleData v, string[] holder)
    {
        foreach (var n in nodes)
        {
            string key = path.Length == 0 ? n.TagHex : path + "." + n.TagHex;
            if (path.Length == 0 && (n.Tag == 0x71 || n.Tag == 0x72 || n.Tag == 0x73 || n.Tag == 0x74))
            { Walk(n.Children, "", v, holder); continue; }   // the data template itself does not count in the path
            if (n.Constructed) { Walk(n.Children, key, v, holder); continue; }
            Assign(v, key, Text.Decode(n.Value, v.CharsetTag), n.Value.Length, holder);
        }
    }

    private static void Assign(VehicleData v, string key, string s, int len, string[] holder)
    {
        switch (key)
        {
            case "78.4F": case "80": case "9F34": case "9F37": case "A1.A2.86": break;   // AID, tag version, other name, charset, owner flag
            case "9F33": v.StateIssuing = s; break;
            case "9F35": v.CompetentAuthority = s; break;
            case "9F36": v.AuthorityIssuing = s; break;
            case "9F38": v.UnambiguousNumber = s; break;
            case "81": v.RegistrationNumber = s; break;
            case "82": v.FirstRegistrationDate = Text.Date(s); break;
            case "8D": v.ExpiryDate = Text.Date(s); break;
            case "8E": v.IssuingDate = Text.Date(s); break;
            case "8A": v.Vin = s; break;
            case "8C": v.Mass = s; break;
            case "8F": v.TypeApprovalNumber = s; break;
            case "93": v.PowerWeightRatio = s; break;
            case "98": v.Category = s; break;
            case "99": v.Axles = s; break;
            case "9F24": v.Colour = s; break;
            case "A3.87": v.Make = s; break;
            case "A3.88": v.Type = s; break;
            case "A3.89": v.CommercialDescription = s; break;
            case "A4.8B": case "A4.96": v.MaxLadenMass = s; break;
            // the directive nests the engine under A5, the MUP SDK table writes 5A: accept both
            case "A5.90": case "5A.90": v.EngineCapacity = s; break;
            case "A5.91": case "5A.91": v.MaxNetPower = s; break;
            case "A5.92": case "5A.92": v.FuelType = s; break;
            case "A5.9E": case "5A.9E": v.EngineNumber = s; break;
            case "A6.94": v.Seats = s; break;
            case "A6.95": v.StandingPlaces = s; break;
            case "A1.A2.83": holder[0] = s; break;
            case "A1.A2.84": holder[1] = s; break;
            case "A1.A2.85": holder[2] = s; break;
            case "A1.A7.83": v.OwnerSurname = s; break;
            case "A1.A7.84": v.OwnerName = s; break;
            case "A1.A7.85": v.OwnerAddress = s; break;
            case "A1.A9.83": v.UserSurname = s; break;
            case "A1.A9.84": v.UserName = s; break;
            case "A1.A9.85": v.UserAddress = s; break;
            // Serbian extension tags (MUP SDK table)
            case "C1": v.SaleBan = s; break;
            case "C2": v.OwnerPersonalNo = s; break;
            case "C3": v.UserPersonalNo = s; break;
            case "C4": v.Load = s; break;
            case "C5": v.YearOfProduction = s; break;
            case "C9": v.SerialNumber = s; break;
            default: v.UnknownTags.Add(key + "/" + len); break;
        }
    }
}

/// Text decoding for card values: ASCII with ISO 8859-1 / -5 / -7 above 0xBF, chosen by tag 9F37 (directive III.11).
public static class Text
{
    public static string Decode(byte[] b, int charsetTag)
    {
        int end = b.Length;
        while (end > 0 && (b[end - 1] == 0 || b[end - 1] == 0x20)) end--;
        int start = 0;
        while (start < end && b[start] == 0x20) start++;
        var sb = new StringBuilder(end - start);
        bool high = false;
        for (int i = start; i < end; i++) if (b[i] >= 0x80) { high = true; break; }
        // Not in the spec: if the bytes are valid UTF-8 with multi-byte characters, take them as UTF-8
        // (a national deviation would look like this). Which one the cards use is to be seen in the diagnostic log.
        if (high && IsUtf8(b, start, end)) return Encoding.UTF8.GetString(b, start, end - start);
        for (int i = start; i < end; i++) sb.Append(Map(b[i], charsetTag));
        return sb.ToString();
    }

    private static bool IsUtf8(byte[] b, int s, int e)
    {
        int i = s; bool multi = false;
        while (i < e)
        {
            int c = b[i];
            int n = c < 0x80 ? 0 : (c & 0xE0) == 0xC0 ? 1 : (c & 0xF0) == 0xE0 ? 2 : (c & 0xF8) == 0xF0 ? 3 : -1;
            if (n < 0 || i + n >= e && n > 0) return false;
            for (int k = 1; k <= n; k++) if ((b[i + k] & 0xC0) != 0x80) return false;
            if (n > 0) multi = true;
            i += n + 1;
        }
        return multi;
    }

    private static char Map(byte x, int cs)
    {
        if (x < 0xA0) return (char)x;
        if (cs == 1)   // ISO 8859-5 (Cyrillic)
        {
            if (x == 0xA0 || x == 0xAD) return (char)x;
            if (x == 0xF0) return '№';
            if (x == 0xFD) return '§';
            if (x >= 0xA1 && x <= 0xFF) return (char)(0x0400 + (x - 0xA0));
        }
        else if (cs == 2)   // ISO 8859-7 (Greek), letters only
        {
            if (x >= 0xC1 && x <= 0xD1) return (char)(0x0391 + (x - 0xC1));
            if (x >= 0xD3 && x <= 0xD9) return (char)(0x03A3 + (x - 0xD3));
            if (x >= 0xE1 && x <= 0xF9) return (char)(0x03B1 + (x - 0xE1));
        }
        return (char)x;   // ISO 8859-1
    }

    /// The card stores YYYYMMDD (directive III.11); shown as DD.MM.YYYY like the ID card.
    public static string Date(string s)
    {
        if (s.Length != 8) return s;
        for (int i = 0; i < 8; i++) if (s[i] < '0' || s[i] > '9') return s;
        return s.Substring(6, 2) + "." + s.Substring(4, 2) + "." + s.Substring(0, 4);
    }
}

/// The rows shown for a vehicle: (label key, value), empty values left out. Same list in every C# app.
public static class VehicleRows
{
    /// Hidden behind the eye like the ID card's personal number and address.
    public static readonly string[] Sensitive =
        { "vOwner", "vOwnerAddr", "vOwnerJmbg", "vUser", "vUserAddr", "vUserJmbg", "vDocSerial", "vDocNo", "vSaleBan" };

    /// The rows in three groups, in the order of the printout of MUP's reader: the document, the owner and user, the vehicle.
    /// (group title key, rows); empty values are left out.
    public static List<(string Title, List<(string Key, string Value)> Rows)> Sections(VehicleData v, bool includeJmbg = true)
    {
        List<(string, string)> G(params (string, string)[] kv)
        {
            var l = new List<(string, string)>();
            foreach (var (k, s) in kv) if (!string.IsNullOrEmpty(s)) l.Add((k, s));
            return l;
        }
        var doc = G(("vRegNo", v.RegistrationNumber), ("vIssued", Text.Date(v.IssuingDate)), ("vValidUntil", Text.Date(v.ExpiryDate)),
            ("vSaleBan", Text.Date(v.SaleBan)), ("vState", v.StateIssuing), ("vAuthority", v.AuthorityIssuing),
            ("vDocNo", v.UnambiguousNumber), ("vDocSerial", v.SerialNumber));
        var owner = G(("vOwner", v.OwnerFull), ("vOwnerAddr", v.OwnerAddress), ("vOwnerJmbg", includeJmbg ? v.OwnerPersonalNo : ""),
            ("vUser", v.UserFull), ("vUserAddr", v.UserAddress), ("vUserJmbg", includeJmbg ? v.UserPersonalNo : ""));
        var car = G(("vFirstReg", Text.Date(v.FirstRegistrationDate)), ("vYear", v.YearOfProduction), ("vMake", v.Make), ("vModel", v.CommercialDescription),
            ("vType", v.Type), ("vApproval", v.TypeApprovalNumber), ("vColour", v.Colour), ("vVin", v.Vin), ("vEngineNo", v.EngineNumber),
            ("vPower", v.MaxNetPower), ("vPowerWeight", v.PowerWeightRatio), ("vCategory", v.Category), ("vFuel", v.FuelType),
            ("vSeats", v.Seats), ("vStanding", v.StandingPlaces), ("vAxles", v.Axles), ("vCapacity", v.EngineCapacity),
            ("vMass", v.Mass), ("vLoad", v.Load), ("vMaxMass", v.MaxLadenMass));
        return new List<(string, List<(string, string)>)> { ("vSecDoc", doc), ("vSecOwner", owner), ("vSecVehicle", car) };
    }

    /// For the screen: a heading entry (Key = null) before every non-empty group, then its rows. The plate (the title of the card) is not repeated.
    public static List<(string Heading, string Key, string Value)> Entries(VehicleData v, bool includeJmbg = true)
    {
        var r = new List<(string, string, string)>();
        foreach (var sec in Sections(v, includeJmbg))
        {
            var rows = sec.Rows.FindAll(x => x.Key != "vRegNo");
            if (rows.Count == 0) continue;
            r.Add((sec.Title, null, null));
            foreach (var (k, val) in rows) r.Add((null, k, val));
        }
        return r;
    }

    public static List<(string Key, string Value)> Build(VehicleData v, bool includeJmbg = true)
    {
        var r = new List<(string, string)>();
        foreach (var sec in Sections(v, includeJmbg)) r.AddRange(sec.Rows);
        return r;
    }

    /// Fictional data for demo mode, screenshots and the PDF.
    public static VehicleData Demo() => new VehicleData
    {
        RegistrationNumber = "BG 123-AB", Make = "ZASTAVA", Type = "103", CommercialDescription = "YUGO 55",
        Vin = "VX1146A0000000001", YearOfProduction = "1989", Colour = "CRVENA", Category = "M1",
        FirstRegistrationDate = "12.03.1989", ExpiryDate = "12.03.2027", IssuingDate = "12.03.2026",
        FuelType = "BENZIN", EngineCapacity = "1116", MaxNetPower = "41", EngineNumber = "0000001", Mass = "790", MaxLadenMass = "1215",
        Seats = "5", StandingPlaces = "0", Axles = "2", TypeApprovalNumber = "e1*00/00*0000",
        OwnerSurname = "PETROVIĆ", OwnerName = "MARKO", OwnerAddress = "Knez Mihailova 1, Beograd", OwnerPersonalNo = "0101990710000",
        UnambiguousNumber = "000000001", SerialNumber = "SD0000001", StateIssuing = "REPUBLIKA SRBIJA", Load = "0", PowerWeightRatio = "0",
        AuthorityIssuing = "PU ZA GRAD BEOGRAD, MINISTARSTVO UNUTRASNJIH POSLOVA REPUBLIKE SRBIJE",
    };
}

/// One drawn item of the vehicle printout: text (or a rule) at a position in points on an A4 page (595.28 x 841.89).
/// X is the left edge of the text, B its baseline measured from the top of the page.
public sealed class PrintItem
{
    public string Text = ""; public double X, B, Size = 11.9, Width = 0, Thickness = 0;
    public bool Bold = true, Underline;
    public bool IsRule => Thickness > 0;
}

/// The printout of the vehicle registration card, matched to the printout of MUP's own reader "Čitač saobraćajne dozvole"
/// (a standard document, like the ID-card printout). The numbers were measured on a scan of that printout: the typeface
/// is Verdana (bold 11.9 pt for the fields, regular 20.3 pt for the section headings, 25.85 pt for the title), the rows
/// sit on a 19.85 pt grid, and the text widths agree with the scan to within 0.5 pt. Shared by the Windows and Linux apps;
/// the Swift (VehiclePrintLayout) and Kotlin (Pdf.kt) ports use the same numbers.
public static class VehiclePrintSpec
{
    public const double PageW = 595.28, PageH = 841.89;
    public const string Font = "Verdana";
    /// Underline: top edge this far below the baseline (0.09 * size + 0.2), 0.75 pt thick.
    public static double UnderlineOffset(double size) => 0.09 * size + 0.2;
    public const double UnderlineThickness = 0.75;
    private const double L = 39.4, R = 348.9;

    public static List<PrintItem> Build(VehicleData v, bool includeJmbg)
    {
        var r = new List<PrintItem>();
        void T(string s, double x, double b, double size = 11.9, bool bold = true, bool ul = false)
        { if (!string.IsNullOrEmpty(s)) r.Add(new PrintItem { Text = s, X = x, B = b, Size = size, Bold = bold, Underline = ul }); }
        string Dash(string s) => string.IsNullOrEmpty(s) ? "-" : s;
        string D(string s) => Text.Date(s);

        T("Čitač saobraćajne dozvole", 43.9, 76.36, 25.85);
        r.Add(new PrintItem { X = 39.2, B = 90.13, Width = 506.7, Thickness = 4.39 });
        T("Registarska oznaka: " + v.RegistrationNumber, 42.5, 126.66, 19.92);

        T("Datum izdavanja: " + D(v.IssuingDate), L, 175.17);
        T("Važi do: " + D(v.ExpiryDate), R, 175.17, 11.98, false, true);
        T("Saobraćajnu izdao: " + v.StateIssuing, L, 195.04);
        T("Zabrana otuđenja: " + D(v.SaleBan), R, 195.04);
        // the issuing authority wraps after the first comma ("PU U PANCEVU," / "MINISTARSTVO UNUTRASNJIH POSLOVA REPUBLIKE SRBIJE")
        string auth = (v.AuthorityIssuing ?? "").Trim();
        int cut = auth.Length > 40 ? auth.IndexOf(", ", StringComparison.Ordinal) : -1;
        if (cut > 0) { T(auth.Substring(0, cut + 1), L, 215.40); T(auth.Substring(cut + 2), L, 229.07); }
        else T(auth, L, 229.07);
        T("Broj saobraćajne: " + v.UnambiguousNumber, L, 249.24);
        T("Serijski broj: " + v.SerialNumber, L, 269.30);

        T("Podaci o vlasniku", L, 312.02, 20.3, false, true);
        string[] owner =
        {
            "Vlasnik: " + v.OwnerSurname, "Ime vlasnika: " + v.OwnerName, "Adresa vlasnika: " + v.OwnerAddress,
            "Jmbg vlasnika: " + (includeJmbg ? v.OwnerPersonalNo : ""),
            "Korisnik: " + v.UserSurname, "Ime korisnika: " + v.UserName, "Adresa korisnika: " + v.UserAddress,
            "Jmbg korisnika: " + (includeJmbg ? v.UserPersonalNo : ""),
        };
        for (int i = 0; i < owner.Length; i++) T(owner[i], L, 331.78 + 19.863 * i);

        T("Podaci o vozilu", L, 502.07, 20.3, false, true);
        string[] left =
        {
            "Datum prve registracije: " + D(v.FirstRegistrationDate),
            "Marka: " + v.Make + "   Model: " + v.CommercialDescription,
            "Tip: " + Dash(v.Type),
            "Boja: " + v.Colour, "Broj šasije: " + v.Vin, "Broj motora: " + v.EngineNumber,
            "Snaga motora: " + v.MaxNetPower, "Odnos snaga/masa: " + v.PowerWeightRatio,
            "Kategorija: " + v.Category, "Pogonsko gorivo: " + v.FuelType, "Broj mesta za sedenje: " + v.Seats,
        };
        string[] right =
        {
            "Godina proizvodnje: " + v.YearOfProduction, null, null,
            "Broj osovina: " + v.Axles, "Zapremina motora: " + v.EngineCapacity, "Masa: " + v.Mass,
            "Nosivost: " + v.Load, "Najveća dozvoljena", "masa: " + v.MaxLadenMass, null, "Broj mesta za stajanje: " + v.StandingPlaces,
        };
        for (int i = 0; i < left.Length; i++)
        {
            double b = 521.53 + 19.793 * i;
            T(left[i], L, b);
            T(right[i], R, b);
        }
        // second column of the "Tip" row at x = 90.6 as in the printout; a longer type pushes it right (about 8 pt per extra character)
        T("Homologacijska oznaka: " + Dash(v.TypeApprovalNumber), 90.6 + Math.Max(0, ("Tip: " + Dash(v.Type)).Length - 6) * 8, 521.53 + 19.793 * 2);

        // the note about the unverified parser, small and grey at the foot of the page (not part of MUP's printout), wrapped by hand
        string note = Loc.T("vehNote") + "   " + DateTime.Now.ToString("dd.MM.yyyy");
        double nb = 806;
        while (note.Length > 0 && nb < 835)
        {
            int n = note.Length;
            if (n > 125) { n = note.LastIndexOf(' ', 125); if (n <= 0) n = 125; }
            T(note.Substring(0, n).Trim(), 41.5, nb, 7.5, false);
            note = note.Substring(n).Trim(); nb += 9;
        }
        return r;
    }
}
