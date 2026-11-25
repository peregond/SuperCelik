namespace SerbiaID;

/// Reading the health insurance card (KZO, RFZO) over PC/SC. STATUS: written from the analysis of the official reader
/// and its middleware (docs/health-card-protocol.md); NOT yet confirmed on a real card. No PIN is used and no signature is checked,
/// exactly like the official program. Use the diagnostic mode (CardDiag) to send a structure log.
public static class HealthCard
{
    /// The card's own applet: "F381000002" + "SERVSZK" + 01 (card type 1, the one the official reader asks for) and the
    /// second type's name ("SERSOVOZK"). Selected by name: 00 A4 04 00 Lc AID.
    public static readonly string[] Aids = { "F38100000253455256535A4B01", "F381000002534552534F564F5A4B01" };

    /// The four data blocks (file ids = block ids).
    public static readonly ushort[] Blocks = { HealthParser.Document, HealthParser.Fixed, HealthParser.Card, HealthParser.Admin };

    /// Selects the applet of a health card; returns its AID, or null if the card has none of them.
    public static string SelectApplet(CardSession s)
    {
        foreach (var aid in Aids)
        {
            var r = s.Tx(VehicleCard.Apdu(0, 0xA4, 4, 0, Compat.FromHex(aid)));
            if (r.Sw == 0x9000 || r.Sw >> 8 == 0x61) return aid;
        }
        return null;
    }

    /// true if the card carries a health card applet.
    public static bool IsHealthCard(PcscService pc, string reader)
    {
        using (var s = pc.Connect(reader)) return SelectApplet(s) != null;
    }

    /// One block: select the applet, select the file (00 A4 00 00 02 <id>), read the 4-byte header, then the rest in chunks of 0x80.
    internal static byte[] ReadBlock(CardSession s, string aid, ushort id)
    {
        var sel = s.TxFollow(VehicleCard.Apdu(0, 0xA4, 4, 0, Compat.FromHex(aid)));
        if (sel.Sw != 0x9000) throw new CardException($"Select applet: {sel.Sw:X4}");
        var fid = new[] { (byte)(id >> 8), (byte)id };
        var r = s.TxFollow(VehicleCard.Apdu(0, 0xA4, 0, 0, fid));
        if (r.Sw != 0x9000) r = s.TxFollow(VehicleCard.Apdu(0, 0xA4, 0, 0x0C, fid));   // some cards answer only to the "no response" form
        if (r.Sw != 0x9000) throw new CardException($"Select file {id:X4}: {r.Sw:X4}");
        int fileSize = r.Data.Length >= 4 ? r.Data[2] << 8 | r.Data[3] : 0;            // bytes 2-3, big-endian, when the card returns them
        if (fileSize > 0 && fileSize < 4) throw new CardException($"File {id:X4} is too small");

        r = s.Tx(VehicleCard.Apdu(0, 0xB0, 0, 0, null, 4));
        if (r.Sw != 0x9000 || r.Data.Length != 4) throw new CardException($"Read header {id:X4}: {r.Sw:X4}");
        if ((r.Data[0] | r.Data[1] << 8) != id) throw new CardException($"File {id:X4} holds another block");
        int total = 4 + (r.Data[2] | r.Data[3] << 8);
        if (total > 16384 || (fileSize > 0 && total > fileSize)) throw new CardException($"File {id:X4}: bad length");
        var data = new List<byte>(r.Data);
        while (data.Count < total)
        {
            int o = data.Count, n = Math.Min(0x80, total - o);
            r = s.Tx(VehicleCard.Apdu(0, 0xB0, (byte)(o >> 8), (byte)o, null, n));
            if (r.Sw != 0x9000 || r.Data.Length == 0) throw new CardException($"Read {id:X4}: {r.Sw:X4}");
            data.AddRange(r.Data);
        }
        return data.ToArray();
    }

    public static HealthData Read(PcscService pc, string reader)
    {
        using (var s = pc.Connect(reader))
        {
            var aid = SelectApplet(s);
            if (aid == null) throw new CardException(Loc.T("cardUnknown"));
            var files = new byte[Blocks.Length][];
            var problems = new List<string>();
            for (int i = 0; i < Blocks.Length; i++)
            {
                try { files[i] = ReadBlock(s, aid, Blocks[i]); }
                catch (CardException e) { problems.Add(Blocks[i].ToString("X4") + ": " + e.Message); }
            }
            // the names are the minimum: without the fixed personal block there is nothing worth showing
            if (files[1] == null) throw new CardException(problems.Count > 0 ? problems[0] : "No health card data");
            var h = HealthParser.Parse(files[0], files[1], files[2], files[3]);
            h.Problems.AddRange(problems);
            return h;
        }
    }
}
