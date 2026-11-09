using System.Text;

namespace SerbiaID;

/// Headless check against a real card. Never prints personal data: only lengths and verdicts.
internal static class SelfTest
{
    public static void Run(string outFile)
    {
        var sb = new StringBuilder();
        void L(string s) => sb.AppendLine(s);
        try
        {
            using var pc = new PcscService();
            var readers = pc.ListReaders();
            L($"readers: {readers.Count}");
            if (readers.Count == 0) return;
            var r = readers[0];
            var atr = pc.Atr(r);
            L("atr: " + (atr == null ? "none" : Convert.ToHexString(atr)));
            if (atr == null) return;

            var p = SerbianCard.ReadPersonalData(pc, r);
            L($"cardType: {p.CardType}");
            string Len(string n, string v) => $"  {n}: {v.Length} chars";
            L(Len("surname", p.Fixed.Surname)); L(Len("givenName", p.Fixed.GivenName));
            L(Len("personalNumber", p.Fixed.PersonalNumber)); L(Len("dateOfBirth", p.Fixed.DateOfBirth));
            L(Len("docRegNo", p.Document.DocRegNo)); L(Len("issuingDate", p.Document.IssuingDate));
            L(Len("expiryDate", p.Document.ExpiryDate)); L(Len("address", p.Variable.Formatted));
            L($"  portrait: {(p.Portrait?.Length ?? 0)} bytes, jpeg={(p.Portrait is { Length: > 2 } && p.Portrait[0] == 0xFF && p.Portrait[1] == 0xD8)}");
            L($"  dateFormatsOk: {System.Text.RegularExpressions.Regex.IsMatch(p.Fixed.DateOfBirth + p.Document.IssuingDate + p.Document.ExpiryDate, @"^(\d\d\.\d\d\.\d{4}){3}$")}");

            foreach (var b in new[] { SerbianCard.Block.Fixed, SerbianCard.Block.Variable })
            {
                var v = SerbianCard.Verify(pc, r, b);
                L($"verify {b}: {v.Result} {v.Detail}");
            }

            var t = SerbianCard.ReadToken(pc, r);
            L($"token: label={t.Label.Length} chars, serial={t.Serial.Length} chars, certs={t.Certificates.Count}");
            foreach (var c in t.Certificates)
                L($"  cert der={c.Der.Length} bytes, subject={c.Subject.Length} chars, chainTrusted={c.ChainTrusted} {c.ChainError}");
        }
        catch (Exception e) { L("ERROR: " + e); }
        finally { File.WriteAllText(outFile, sb.ToString()); }
    }
}
