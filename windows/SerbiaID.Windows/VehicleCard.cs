using System.Text;

namespace SerbiaID;

/// Reading the vehicle registration card over PC/SC. STATUS: written from the specification (docs/cards-research.md);
/// the application identifier is NOT published, the candidates below come from analysing MUP's own SDK binary and are
/// unconfirmed. Nothing here has been seen on a real card yet: use the diagnostic mode (CardDiag) first.
public static class VehicleCard
{
    /// Candidate application names, tried in this order. The first is the ID-card naming scheme (F381000002 + "SERVL" + 01)
    /// applied by analogy; the second is a prefix (ISO 7816-4 allows partial DF names with P2=00).
    public static readonly string[] CandidateAids =
    {
        "F381000002534552564C01",
        "F381000002534552564C",
        "F381000002534552564C040201",
    };

    /// EF.Registration_A/B/C (data, signature, issuer certificate); directive III.10 and MUP SDK table.
    public static readonly ushort[] DataFiles = { 0xD001, 0xD011, 0xD021 };
    public static readonly ushort[] SignatureFiles = { 0xE001, 0xE011, 0xE021 };
    public static readonly ushort[] CertificateFiles = { 0xC001, 0xC011, 0xC021 };

    internal static byte[] Apdu(byte cla, byte ins, byte p1, byte p2, byte[] data = null, int? le = null)
    {
        var l = new List<byte> { cla, ins, p1, p2 };
        if (data != null && data.Length > 0) { l.Add((byte)data.Length); l.AddRange(data); }
        if (le != null) l.Add((byte)le.Value);
        return l.ToArray();
    }

    /// Selects the registration application by trying the candidate names. Returns the name used, or null.
    public static string SelectApplication(CardSession s)
    {
        foreach (var aid in CandidateAids)
        {
            var r = s.Tx(Apdu(0, 0xA4, 4, 0, Compat.FromHex(aid)));
            if (r.Sw == 0x9000 || r.Sw >> 8 == 0x61) return aid;
        }
        return null;
    }

    /// SELECT an EF by identifier inside the current application and read it whole.
    /// The directive's form (P1=02, P2=04: return the FCP) first, then the two forms the ID card answers to.
    public static byte[] ReadEf(CardSession s, ushort fid)
    {
        var id = new[] { (byte)(fid >> 8), (byte)fid };
        (byte, byte)[] forms = { (0x02, 0x04), (0x00, 0x00), (0x00, 0x0C) };
        byte[] fcp = null; bool ok = false; int sw = 0;
        foreach (var f in forms)
        {
            var r = s.TxFollow(Apdu(0, 0xA4, f.Item1, f.Item2, id, f.Item2 == 0x0C ? (int?)null : 0));
            sw = r.Sw;
            if (r.Sw == 0x9000) { ok = true; fcp = r.Data; break; }
        }
        if (!ok) throw new CardException($"Select file {fid:X4}: {sw:X4}");
        int size = FcpSize(fcp);
        var o = new List<byte>();
        int limit = size > 0 ? size : 4096;
        while (o.Count < limit)
        {
            int n = Math.Min(0xE0, limit - o.Count);
            var r = s.Tx(Apdu(0, 0xB0, (byte)(o.Count >> 8), (byte)o.Count, null, n));
            if (r.Sw != 0x9000 && !(r.Sw >> 8 == 0x62)) { if (size > 0 || o.Count == 0) throw new CardException($"Read {fid:X4}: {r.Sw:X4}"); break; }
            o.AddRange(r.Data);
            if (r.Data.Length == 0) break;
        }
        return o.ToArray();
    }

    /// File size from the FCP/FCI: tag 80 (data bytes) or 81 inside 62 / 6F. 0 = not given.
    public static int FcpSize(byte[] fcp)
    {
        if (fcp == null || fcp.Length == 0) return 0;
        var t = Ber.Parse(fcp);
        if (t == null) return 0;
        return FindSize(t);
    }

    private static int FindSize(List<Tlv> nodes)
    {
        foreach (var n in nodes)
        {
            if ((n.Tag == 0x80 || n.Tag == 0x81) && n.Value.Length >= 1 && n.Value.Length <= 3)
            { int v = 0; foreach (var b in n.Value) v = v << 8 | b; return v; }
            if (n.Constructed) { int v = FindSize(n.Children); if (v > 0) return v; }
        }
        return 0;
    }

    public static VehicleData Read(PcscService pc, string reader)
    {
        using (var s = pc.Connect(reader))
        {
            if (SelectApplication(s) == null)
                throw new CardException(Loc.T("cardUnknown"));
            var files = new List<byte[]>();
            foreach (var fid in DataFiles)
            {
                try { files.Add(ReadEf(s, fid)); }
                catch (CardException) when (files.Count > 0) { }   // B and C are optional; A is required
            }
            if (files.Count == 0) throw new CardException("No registration data files");
            return VehicleParser.Parse(files);
        }
    }
}
