using System.Text;

namespace SerbiaID;

/// Diagnostic mode: on a real card, selects applications and files, lists identifiers and sizes, reads files that are
/// open and records the answers WITHOUT personal data: only structure (tags, lengths, kinds of value), never values.
/// It sends no VERIFY / PIN command of any kind. Text of the report is meant to be copied by a button.
public static class CardDiag
{
    private static readonly string[][] KnownAids =
    {
        new[] { "SERID", "F381000002534552494401" },
        new[] { "SERIF", "F381000002534552494601" },
        new[] { "SERRP", "F381000002534552525001" },
        new[] { "PKCS15", "A000000063504B43532D3135" },
    };

    private static readonly string[][] VehicleAids =
    {
        new[] { "VL full (SERVL+01)", "F381000002534552564C01" },
        new[] { "VL prefix (SERVL)", "F381000002534552564C" },
        new[] { "VL (SERVL+040201)", "F381000002534552564C040201" },
        new[] { "eVL-001 (long)", "A0000000183414010065564C2D303031" },
        new[] { "eVL-001", "A00000001865564C2D303031" },
    };

    // health insurance card (KZO): applet names recovered from the official reader, see docs/health-card-protocol.md
    private static readonly string[][] HealthAids =
    {
        new[] { "KZO type 1 (SERVSZK+01)", "F38100000253455256535A4B01" },
        new[] { "KZO type 7 (SERSOVOZK+01)", "F381000002534552534F564F5A4B01" },
    };

    private static readonly ushort[] HealthFiles = { 0x0D00, 0x0D01, 0x0D02, 0x0D03, 0x0D04, 0x0D05, 0x0D06, 0x0D07, 0x0D09 };

    private static readonly ushort[] VehicleFiles =
        { 0xD001, 0xD011, 0xD021, 0xD031, 0xD041, 0xE001, 0xE011, 0xE021, 0xC001, 0xC011, 0xC021 };

    public static string Run(PcscService pc, string reader, string version)
    {
        var sb = new StringBuilder();
        void L(string s) => sb.AppendLine(s);
        L("Super Celik card diagnostics (no personal data: structure only, no PIN commands)");
        L("app: " + version + "   reader: " + reader);
        try
        {
            using (var s = pc.Connect(reader))
            {
                try { L("ATR: " + Compat.Hex(s.Atr())); } catch (CardException e) { L("ATR: " + e.Message); }

                L(""); L("== ISO discovery");
                Probe(s, L, "SELECT MF (3F00)", VehicleCard.Apdu(0, 0xA4, 0, 0, new byte[] { 0x3F, 0x00 }, 0), true);
                Probe(s, L, "SELECT MF (3F00) P2=0C", VehicleCard.Apdu(0, 0xA4, 0, 0x0C, new byte[] { 0x3F, 0x00 }), false);
                ReadPlain(s, L, "EF.DIR 2F00", 0x2F00, true);
                ReadPlain(s, L, "EF.ATR 2F01", 0x2F01, true);

                L(""); L("== Known applications");
                foreach (var a in KnownAids) TrySelect(s, L, a[0], a[1], false, null);

                L(""); L("== Health insurance card (KZO), names from the official reader, not yet seen on a real card");
                foreach (var a in HealthAids) TrySelect(s, L, a[0], a[1], true, HealthFiles);

                L(""); L("== Vehicle registration candidates (unconfirmed names)");
                foreach (var a in VehicleAids) TrySelect(s, L, a[0], a[1], true, VehicleFiles);
            }
        }
        catch (Exception e) { L("ERROR: " + e.GetType().Name + ": " + e.Message); }
        L(""); L("end");
        return sb.ToString();
    }

    private static void TrySelect(CardSession s, Action<string> L, string name, string aid, bool probeFiles, ushort[] files)
    {
        var r = s.TxFollow(VehicleCard.Apdu(0, 0xA4, 4, 0, Compat.FromHex(aid), 0));
        L($"SELECT {name} {aid}: SW={r.Sw:X4} fci={r.Data.Length}B");
        if (r.Sw != 0x9000) return;
        if (r.Data.Length > 0) Dump(r.Data, L, "  fci ", true);
        if (!probeFiles || files == null) return;
        foreach (var fid in files) ProbeFile(s, L, fid);
    }

    private static void ProbeFile(CardSession s, Action<string> L, ushort fid)
    {
        var id = new[] { (byte)(fid >> 8), (byte)fid };
        (byte, byte)[] forms = { (0x02, 0x04), (0x00, 0x00), (0x00, 0x0C) };
        byte[] fcp = null; bool ok = false;
        var sws = new List<string>();
        foreach (var f in forms)
        {
            var r = s.TxFollow(VehicleCard.Apdu(0, 0xA4, f.Item1, f.Item2, id, f.Item2 == 0x0C ? (int?)null : 0));
            sws.Add($"P1={f.Item1:X2}P2={f.Item2:X2}:{r.Sw:X4}");
            if (r.Sw == 0x9000) { ok = true; fcp = r.Data; break; }
        }
        L($"  file {fid:X4}: select {string.Join(" ", sws.ToArray())}");
        if (!ok) return;
        int size = VehicleCard.FcpSize(fcp);
        if (fcp.Length > 0) Dump(fcp, L, "    fcp ", true);
        L($"    size from fcp: {(size > 0 ? size.ToString() : "n/a")}");
        var o = new List<byte>();
        int limit = size > 0 ? Math.Min(size, 8192) : 4096; int lastSw = 0x9000;
        while (o.Count < limit)
        {
            var r = s.Tx(VehicleCard.Apdu(0, 0xB0, (byte)(o.Count >> 8), (byte)o.Count, null, Math.Min(0xE0, limit - o.Count)));
            lastSw = r.Sw;
            if (r.Sw != 0x9000 && r.Sw >> 8 != 0x62) break;
            o.AddRange(r.Data);
            if (r.Data.Length == 0) break;
        }
        L($"    read: {o.Count} bytes, last SW={lastSw:X4}");
        if (o.Count > 0) Describe(o.ToArray(), L, "    ");
    }

    private static void ReadPlain(CardSession s, Action<string> L, string name, ushort fid, bool showAppNames)
    {
        var id = new[] { (byte)(fid >> 8), (byte)fid };
        var r = s.TxFollow(VehicleCard.Apdu(0, 0xA4, 0, 0x0C, id));
        if (r.Sw != 0x9000) { L($"{name}: select SW={r.Sw:X4}"); return; }
        var o = new List<byte>(); int lastSw = 0x9000;
        while (o.Count < 1024)
        {
            var b = s.Tx(VehicleCard.Apdu(0, 0xB0, (byte)(o.Count >> 8), (byte)o.Count, null, 0xE0));
            lastSw = b.Sw;
            if (b.Sw != 0x9000 || b.Data.Length == 0) break;
            o.AddRange(b.Data);
        }
        L($"{name}: read {o.Count} bytes, last SW={lastSw:X4}");
        if (o.Count > 0) Dump(o.ToArray(), L, "  ", showAppNames);   // EF.DIR / EF.ATR hold application names, not personal data
    }

    private static void Probe(CardSession s, Action<string> L, string name, byte[] apdu, bool dump)
    {
        var r = s.TxFollow(apdu);
        L($"{name}: SW={r.Sw:X4} data={r.Data.Length}B");
        if (dump && r.Sw == 0x9000 && r.Data.Length > 0) Dump(r.Data, L, "  ", true);
    }

    /// Structure of a file: as BER-TLV, or as the ID-card record format [tag LE16][len LE16] after a 4-byte header,
    /// or as plain byte statistics.
    private static void Describe(byte[] d, Action<string> L, string ind)
    {
        var t = Ber.Parse(d);
        if (t != null && t.Count > 0 && t[0].Tag >= 0x40) { L(ind + "BER-TLV:"); Dump(d, L, ind + "  ", false); return; }
        if (d.Length > 8)
        {
            var recs = new List<string>(); int p = 4; bool good = true;
            while (p + 4 <= d.Length)
            {
                int tag = d[p] | d[p + 1] << 8, len = d[p + 2] | d[p + 3] << 8;
                if (p + 4 + len > d.Length) { good = false; break; }
                var v = new byte[len]; Buffer.BlockCopy(d, p + 4, v, 0, len);
                recs.Add($"{tag:X4}/{len} {Kind(v)}");
                p += 4 + len;
            }
            if (good && recs.Count > 0 && p == d.Length)
            {
                L(ind + $"records [tag LE16][len LE16] after a 4-byte header (file id {(d[0] | d[1] << 8):X4}, declared {(d[2] | d[3] << 8)} bytes):");
                foreach (var r in recs) L(ind + "  " + r);
                return;
            }
        }
        L(ind + "unstructured: " + Kind(d));
    }

    private static void Dump(byte[] d, Action<string> L, string ind, bool showNames)
    {
        var t = Ber.Parse(d);
        if (t == null) { L(ind + "(not BER) " + Kind(d)); return; }
        DumpNodes(t, L, ind, showNames);
    }

    private static void DumpNodes(List<Tlv> nodes, Action<string> L, string ind, bool showNames)
    {
        foreach (var n in nodes)
        {
            if (n.Constructed) { L($"{ind}{n.TagHex} len={n.Value.Length} constructed"); DumpNodes(n.Children, L, ind + "  ", showNames); }
            // application identifiers/names and sizes are not personal; everything else is shown as a kind only
            else if (showNames && (n.Tag == 0x4F || n.Tag == 0x84 || n.Tag == 0x50 || n.Tag == 0x80 || n.Tag == 0x81 || n.Tag == 0x82 || n.Tag == 0x83 || n.Tag == 0x88))
                L($"{ind}{n.TagHex} len={n.Value.Length} {Compat.Hex(n.Value)}");
            else L($"{ind}{n.TagHex} len={n.Value.Length} {Kind(n.Value)}");
        }
    }

    /// Kind of value without the value: counts of byte classes.
    private static string Kind(byte[] v)
    {
        if (v.Length == 0) return "empty";
        int dig = 0, up = 0, lo = 0, hi = 0, zero = 0, other = 0;
        foreach (var b in v)
        {
            if (b == 0) zero++;
            else if (b >= '0' && b <= '9') dig++;
            else if (b >= 'A' && b <= 'Z') up++;
            else if (b >= 'a' && b <= 'z') lo++;
            else if (b >= 0x80) hi++;
            else other++;
        }
        string cls = dig == v.Length ? (v.Length == 8 ? "digits(8, date?)" : "digits")
            : zero == v.Length ? "zeros"
            : hi == 0 && other == 0 && zero == 0 ? "ascii-text"
            : hi > 0 && hi + dig + up + lo + other + zero == v.Length && other < v.Length / 2 ? "text+high-bytes"
            : "binary";
        return $"{cls} [digits={dig} upper={up} lower={lo} high={hi} zero={zero} other={other}]";
    }
}
