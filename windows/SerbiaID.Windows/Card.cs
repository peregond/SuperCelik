using System.IO.Compression;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;

namespace SerbiaID;

/// One connection to a card. Same protocol as the macOS app (see CardService.swift).
public sealed class CardSession : IDisposable
{
    private readonly IntPtr _card;
    private readonly uint _proto;

    internal CardSession(IntPtr card, uint proto) { _card = card; _proto = proto; }

    public void Dispose() => Native.SCardDisconnect(_card, 0 /* LEAVE_CARD */);

    public (byte[] Data, int Sw) Tx(byte[] apdu)
    {
        var pci = Marshal.AllocHGlobal(8);
        try
        {
            Marshal.WriteInt32(pci, 0, (int)_proto);
            Marshal.WriteInt32(pci, 4, 8);
            var recv = new byte[65538];
            int len = recv.Length;
            int rc = Native.SCardTransmit(_card, pci, apdu, apdu.Length, IntPtr.Zero, recv, ref len);
            if (rc != 0 || len < 2) throw new CardException(rc, "Transmit");
            return (recv.AsSpan(0, len - 2).ToArray(), recv[len - 2] << 8 | recv[len - 1]);
        }
        finally { Marshal.FreeHGlobal(pci); }
    }

    /// Like Tx but follows T=0 "61xx" (GET RESPONSE).
    public (byte[] Data, int Sw) TxFollow(byte[] apdu)
    {
        var r = Tx(apdu);
        var data = new List<byte>(r.Data);
        while (r.Sw >> 8 == 0x61)
        {
            r = Tx(new byte[] { 0x00, 0xC0, 0x00, 0x00, (byte)(r.Sw & 0xFF) });
            data.AddRange(r.Data);
        }
        return (data.ToArray(), r.Sw);
    }

    public byte[] Atr()
    {
        var buf = new byte[64]; int len = buf.Length;
        int rc = Native.SCardGetAttrib(_card, 0x00090303, buf, ref len);
        if (rc != 0) throw new CardException(rc, "GetAttrib");
        return buf.AsSpan(0, len).ToArray();
    }
}

public sealed class PcscService : IDisposable
{
    private IntPtr _ctx;

    public PcscService()
    {
        Native.SCardEstablishContext(2 /* SYSTEM */, IntPtr.Zero, IntPtr.Zero, out _ctx);
    }

    public void Dispose() { if (_ctx != IntPtr.Zero) Native.SCardReleaseContext(_ctx); }

    public List<string> ListReaders()
    {
        int len = 0;
        int rc = Native.SCardListReadersW(_ctx, null, null, ref len);
        if (rc == Native.SCARD_E_NO_READERS_AVAILABLE) return new();
        if (rc != 0 || len <= 0) throw new CardException(rc, "ListReaders");
        var buf = new char[len];
        rc = Native.SCardListReadersW(_ctx, null, buf, ref len);
        if (rc != 0) throw new CardException(rc, "ListReaders");
        return new string(buf).Split('\0', StringSplitOptions.RemoveEmptyEntries).ToList();
    }

    public CardSession Connect(string reader)
    {
        int rc = Native.SCardConnectW(_ctx, reader, 2 /* SHARED */, 3 /* T0|T1 */, out var card, out var proto);
        if (rc != 0) throw new CardException(rc, "Connect");
        return new CardSession(card, proto);
    }

    /// null = no card in the reader.
    public byte[] Atr(string reader)
    {
        try { using var s = Connect(reader); return s.Atr(); }
        catch (CardException e) when (e.Code == Native.SCARD_E_NO_SMARTCARD || e.Code == Native.SCARD_W_UNRESPONSIVE_CARD
                                      || e.Code == Native.SCARD_W_REMOVED_CARD) { return null; }
    }
}

/// Protocol of the Serbian eID / foreigner ID / residence permit and its PKCS#15 token applet.
public static class SerbianCard
{
    private static readonly (CardType Type, string Aid)[] Applets =
    {
        (CardType.ID2014, "F381000002534552494401"),  // SERID
        (CardType.IF2020, "F381000002534552494601"),  // SERIF
        (CardType.RP2024, "F381000002534552525001"),  // SERRP
    };
    private const string Pkcs15Aid = "A000000063504B43532D3135";

    private static byte[] Hex(string h) => Convert.FromHexString(h);

    private static byte[] Apdu(byte cla, byte ins, byte p1, byte p2, byte[] data = null, int? le = null)
    {
        var l = new List<byte> { cla, ins, p1, p2 };
        if (data != null && data.Length > 0) { l.Add((byte)data.Length); l.AddRange(data); }
        if (le != null) l.Add((byte)le.Value);
        return l.ToArray();
    }

    private static CardType SelectApplet(CardSession s)
    {
        foreach (var (type, aid) in Applets)
        {
            var a = Hex(aid);
            if (s.Tx(Apdu(0, 0xA4, 4, 0, a)).Sw == 0x9000) return type;
        }
        throw new CardException("Unsupported card (no known applet; old Apollo cards are not supported)");
    }

    /// Whole file incl. 4-byte header: id LE16, length LE16.
    private static byte[] ReadRawFile(CardSession s, ushort fid)
    {
        var r = s.Tx(Apdu(0, 0xA4, 0, 0x0C, new[] { (byte)(fid >> 8), (byte)fid }));
        if (r.Sw != 0x9000) throw new CardException($"Select file {fid:X4}: {r.Sw:X4}");
        r = s.Tx(Apdu(0, 0xB0, 0, 0, null, 4));
        if (r.Sw != 0x9000 || r.Data.Length != 4) throw new CardException($"Read header {fid:X4}: {r.Sw:X4}");
        int total = 4 + r.Data[2] + (r.Data[3] << 8);
        var data = new List<byte>(r.Data);
        while (data.Count < total)
        {
            int n = Math.Min(0xE0, total - data.Count), o = data.Count;
            r = s.Tx(Apdu(0, 0xB0, (byte)(o >> 8), (byte)o, null, n));
            if (r.Sw != 0x9000) throw new CardException($"Read {fid:X4}: {r.Sw:X4}");
            data.AddRange(r.Data);
        }
        return data.ToArray();
    }

    private static Dictionary<ushort, byte[]> Records(byte[] file)
    {
        var d = new Dictionary<ushort, byte[]>();
        int p = 4;
        while (p + 4 <= file.Length)
        {
            ushort tag = (ushort)(file[p] | file[p + 1] << 8);
            int len = file[p + 2] | file[p + 3] << 8;
            if (p + 4 + len > file.Length) break;
            d[tag] = file.AsSpan(p + 4, len).ToArray();
            p += 4 + len;
        }
        return d;
    }

    private static string Str(Dictionary<ushort, byte[]> d, ushort tag) =>
        d.TryGetValue(tag, out var v) ? Encoding.UTF8.GetString(v) : "";

    /// Card stores DDMMYYYY; the official API shows DD.MM.YYYY
    private static string Date(Dictionary<ushort, byte[]> d, ushort tag)
    {
        var s = Str(d, tag);
        return s.Length == 8 ? $"{s[..2]}.{s.Substring(2, 2)}.{s[4..]}" : s;
    }

    public static PersonalData ReadPersonalData(PcscService pc, string reader)
    {
        using var s = pc.Connect(reader);
        var p = new PersonalData { CardType = SelectApplet(s) };
        var doc = Records(ReadRawFile(s, 0x0F02));
        var fix = Records(ReadRawFile(s, 0x0F03));
        var var = Records(ReadRawFile(s, 0x0F04));

        // VERIFIED against CelikApi.dll on an RP2024 card
        p.Document = new DocumentData
        {
            DocRegNo = Str(doc, 0x060A), DocumentType = Str(doc, 0x060B),
            IssuingDate = Date(doc, 0x060D), ExpiryDate = Date(doc, 0x060E),
            IssuingAuthority = Str(doc, 0x060F), DocumentSerialNumber = Str(doc, 0x0691), DocumentName = Str(doc, 0x0692),
        };
        p.Fixed = new FixedPersonalData
        {
            PersonalNumber = Str(fix, 0x0616), Surname = Str(fix, 0x0617), GivenName = Str(fix, 0x0618),
            ParentGivenName = Str(fix, 0x0619),      // UNVERIFIED tag
            Sex = Str(fix, 0x061A),
            PlaceOfBirth = Str(fix, 0x061B),         // UNVERIFIED tag
            StateOfBirth = Str(fix, 0x061D), DateOfBirth = Date(fix, 0x061E),
            CommunityOfBirth = Str(fix, 0x061C),     // UNVERIFIED tag
            NationalityFull = Str(fix, 0x062F), PurposeOfStay = Str(fix, 0x0693), ENote = Str(fix, 0x0694),
        };
        p.Variable = new VariablePersonalData
        {
            State = Str(var, 0x0620),                // UNVERIFIED tag
            Community = Str(var, 0x0621), Place = Str(var, 0x0622), Street = Str(var, 0x0623), HouseNumber = Str(var, 0x0624),
            HouseLetter = Str(var, 0x0625), Entrance = Str(var, 0x0626),   // UNVERIFIED tags
            Floor = Str(var, 0x0627), ApartmentNumber = Str(var, 0x0628),  // UNVERIFIED tags
            AddressDate = Date(var, 0x062C),
        };
        // Portrait: file 0F06, record 0110 = JPEG (verified)
        Records(ReadRawFile(s, 0x0F06)).TryGetValue(0x0110, out p.Portrait);
        return p;
    }

    // ---- signatures: 0F1C = CMS over SHA-256 of whole files; 0F1D = CMS over SHA-256 of 0F04 ----

    public enum Block { Fixed, Variable }

    public static SigStatus Verify(PcscService pc, string reader, Block block)
    {
        try
        {
            using var s = pc.Connect(reader);
            SelectApplet(s);
            ushort cmsFile = block == Block.Fixed ? (ushort)0x0F1C : (ushort)0x0F1D;
            ushort tag = block == Block.Fixed ? (ushort)0x0810 : (ushort)0x0820;
            ushort[] covered = block == Block.Fixed
                ? new ushort[] { 0x0F1B, 0x0F02, 0x0F03, 0x0F06, 0x0FA1, 0x0FA2 }
                : new ushort[] { 0x0F04 };
            if (!Records(ReadRawFile(s, cmsFile)).TryGetValue(tag, out var blob))
                return new SigStatus { Result = SigResult.Invalid, Detail = "signature block missing" };

            var content = Crypto.VerifyCms(blob, out var chainOk, out var chainErr);
            if (content == null) return new SigStatus { Result = SigResult.Invalid, Detail = chainErr };
            foreach (var fid in covered)
            {
                var h = SHA256.HashData(ReadRawFile(s, fid));
                bool found = false;
                for (int i = 0; i + 32 <= content.Length && !found; i += 32)
                    found = content.AsSpan(i, 32).SequenceEqual(h);
                if (!found) return new SigStatus { Result = SigResult.Invalid, Detail = $"hash mismatch for file {fid:X4}" };
            }
            return chainOk
                ? new SigStatus { Result = SigResult.Ok }
                : new SigStatus { Result = SigResult.ChainNotTrusted, Detail = chainErr };
        }
        catch (CardException e) { return new SigStatus { Result = SigResult.Invalid, Detail = e.Message }; }
    }

    // ---- token (PKCS#15 / CardEdge): read-only, no PIN ----

    private static byte[] ReadTokenFile(CardSession s, ushort fid)
    {
        var sel = s.Tx(Apdu(0, 0xA4, 0, 0, new[] { (byte)(fid >> 8), (byte)fid }));
        if (sel.Sw != 0x9000 || sel.Data.Length < 4) throw new CardException($"Select token file {fid:X4}: {sel.Sw:X4}");
        int size = sel.Data[2] << 8 | sel.Data[3];
        var o = new List<byte>();
        while (o.Count < size)
        {
            var r = s.Tx(Apdu(0, 0xB0, (byte)(o.Count >> 8), (byte)o.Count, null, Math.Min(0xE0, size - o.Count)));
            if (r.Sw != 0x9000) throw new CardException($"Read token file {fid:X4}: {r.Sw:X4}");
            o.AddRange(r.Data);
        }
        return o.ToArray();
    }

    private static void SelectTokenApplet(CardSession s)
    {
        if (s.Tx(Apdu(0, 0xA4, 4, 0, Hex(Pkcs15Aid))).Sw != 0x9000)
            throw new CardException("No token applet on this card");
    }

    public static TokenInfo ReadToken(PcscService pc, string reader)
    {
        using var s = pc.Connect(reader);
        SelectTokenApplet(s);
        var info = new TokenInfo();
        try
        {
            var d = ReadTokenFile(s, 0x70F3);
            if (d.Length > 32)
            {
                info.Label = Encoding.UTF8.GetString(d, 0, 32).Trim();
                info.Serial = new string(d.Skip(32).TakeWhile(b => b >= 0x20 && b < 0x7F).Select(b => (char)b).ToArray()).Trim();
            }
        }
        catch (CardException) { }
        try
        {
            var blob = ReadTokenFile(s, 0x7102);   // [len LE16][01 00][usize LE16][zlib]
            if (blob.Length > 8)
            {
                using var ms = new MemoryStream(blob, 6, blob.Length - 6);
                using var z = new ZLibStream(ms, CompressionMode.Decompress);
                using var outMs = new MemoryStream();
                z.CopyTo(outMs);
                var cert = new TokenCertificate { Der = outMs.ToArray() };
                try
                {
                    var l = ReadTokenFile(s, 0x8007);     // [01 71 02 len] + label
                    if (l.Length > 4) cert.Label = Encoding.UTF8.GetString(l, 4, Math.Min(l[3], l.Length - 4));
                }
                catch (CardException) { }
                Crypto.Describe(cert);
                info.Certificates.Add(cert);
            }
        }
        catch (CardException) { }
        return info;
    }

    // ---- token PIN / signing (NOT used by the UI yet; wrong PIN burns a try) ----

    private static byte[] PaddedPin(string pin)
    {
        var b = Encoding.ASCII.GetBytes(pin);
        if (b.Length < 4 || b.Length > 8 || b.Any(c => c < '0' || c > '9')) throw new ArgumentException("PIN must be 4-8 digits");
        return b.Concat(new byte[8 - b.Length]).ToArray();
    }

    private static void ThrowPin(int sw)
    {
        if (sw == 0x6983 || sw == 0x63C0) throw new PinException(0, true);
        if (sw >> 4 == 0x063C) throw new PinException(sw & 0xF, false);
        throw new CardException($"PIN operation failed: {sw:X4}");
    }

    public static byte[] TokenSign(PcscService pc, string reader, string pin, ushort keyFile, byte[] digestInfo)
    {
        using var s = pc.Connect(reader);
        SelectTokenApplet(s);
        var v = s.TxFollow(Apdu(0, 0x20, 0, 0x80, PaddedPin(pin)));
        if (v.Sw != 0x9000) ThrowPin(v.Sw);               // single attempt, never retried
        var mse = new byte[] { 0x80, 0x01, 0x02, 0x84, 0x02, (byte)(keyFile >> 8), (byte)keyFile };
        var r = s.TxFollow(Apdu(0, 0x22, 0x41, 0xB6, mse));
        if (r.Sw != 0x9000) throw new CardException($"MSE SET: {r.Sw:X4}");
        r = s.TxFollow(Apdu(0, 0x2A, 0x9E, 0x00, digestInfo, 0));
        if (r.Sw != 0x9000 || r.Data.Length == 0) throw new CardException($"Sign: {r.Sw:X4}");
        return r.Data;
    }

    public static void ChangeTokenPin(PcscService pc, string reader, string oldPin, string newPin)
    {
        using var s = pc.Connect(reader);
        SelectTokenApplet(s);
        var r = s.TxFollow(Apdu(0, 0x24, 0, 0x80, PaddedPin(oldPin).Concat(PaddedPin(newPin)).ToArray()));
        if (r.Sw != 0x9000) ThrowPin(r.Sw);
    }
}
