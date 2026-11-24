using System.Text;
using Xunit;

namespace SerbiaID;

/// Synthetic data built from the directive 1999/37/EC (as amended) and the MUP SDK table. Not from a real card.
public class VehicleParserTests
{
    static byte[] T(int tag, string s, int cs = 0) => Ber.Build(tag, Enc(s, cs));
    static byte[] T(int tag, params byte[][] children) => Ber.Build(tag, children.SelectMany(x => x).ToArray());

    // ISO 8859-5 encoder for the test (inverse of the decoder)
    static byte[] Enc(string s, int cs)
    {
        var o = new List<byte>();
        foreach (var c in s)
        {
            if (cs == 1 && c >= 'Ё' && c <= 'џ') o.Add((byte)(0xA0 + (c - 0x0400)));
            else o.Add((byte)c);
        }
        return o.ToArray();
    }

    static byte[] Pad(byte[] d, int total) => d.Concat(new byte[total - d.Length]).ToArray();

    static byte[] FileA(int cs = 0, bool enginePath5A = false) =>
        T(0x78, T(0x4F, "AID-TEST")).Concat(
        T(0x71,
            T(0x80, "\u0001"),
            Ber.Build(0x9F33, Enc("SRB", cs)),
            Ber.Build(0x9F35, Enc("MUP", cs)),
            Ber.Build(0x9F37, new byte[] { (byte)cs }),
            Ber.Build(0x9F38, Enc("123456", cs)),
            T(0x81, "BG123AB"),
            T(0x82, "20150312"),
            T(0xA1,
                T(0xA2, T(0x83, "Petrovic"), T(0x84, "Marko"), T(0x85, "Ulica 1, Beograd"), T(0x86, "\0"))),
            T(0xA3, T(0x87, "FIAT"), T(0x88, "199A"), T(0x89, "PUNTO")),
            T(0x8A, "ZFA19900000000001"),
            T(0xA4, T(0x8B, "1500")),
            T(0x8C, "1100"),
            T(0x8D, "20260312"),
            T(0x8E, "20250312"),
            T(0x8F, "e3*2001/116"),
            T(enginePath5A ? 0x5A : 0xA5, T(0x90, "1242"), T(0x91, "44"), T(0x92, "BENZIN")),
            T(0xA6, T(0x94, "5"), T(0x95, "0")))).ToArray();

    [Fact]
    public void ParsesMandatoryData()
    {
        var v = VehicleParser.Parse(new[] { Pad(FileA(), 400) });
        Assert.Equal("BG123AB", v.RegistrationNumber);
        Assert.Equal("12.03.2015", v.FirstRegistrationDate);
        Assert.Equal("12.03.2026", v.ExpiryDate);
        Assert.Equal("12.03.2025", v.IssuingDate);
        Assert.Equal("FIAT", v.Make); Assert.Equal("199A", v.Type); Assert.Equal("PUNTO", v.CommercialDescription);
        Assert.Equal("ZFA19900000000001", v.Vin);
        Assert.Equal("1500", v.MaxLadenMass); Assert.Equal("1100", v.Mass);
        Assert.Equal("1242", v.EngineCapacity); Assert.Equal("44", v.MaxNetPower); Assert.Equal("BENZIN", v.FuelType);
        Assert.Equal("5", v.Seats); Assert.Equal("0", v.StandingPlaces);
        Assert.Equal("SRB", v.StateIssuing); Assert.Equal("123456", v.UnambiguousNumber);
        Assert.Equal("e3*2001/116", v.TypeApprovalNumber);
        Assert.Empty(v.UnknownTags);
        Assert.False(v.SignatureVerified);
    }

    [Fact]
    public void HolderBecomesOwnerWhenNoVehicleOwnerObject()
    {
        var v = VehicleParser.Parse(new[] { FileA() });
        Assert.Equal("Petrovic", v.OwnerSurname); Assert.Equal("Marko", v.OwnerName);
        Assert.Equal("Ulica 1, Beograd", v.OwnerAddress);
    }

    [Fact]
    public void EngineUnderTag5AIsAccepted()
    {
        var v = VehicleParser.Parse(new[] { FileA(enginePath5A: true) });
        Assert.Equal("1242", v.EngineCapacity); Assert.Equal("BENZIN", v.FuelType);
    }

    [Fact]
    public void OptionalFileGivesOwnerUserAndNationalExtension()
    {
        var b = T(0x78, T(0x4F, "AID-TEST")).Concat(
            T(0x72,
                T(0xA1, T(0xA7, T(0x83, "Vlasnik"), T(0x84, "Ime"), T(0x85, "Adresa vlasnika")),
                        T(0xA9, T(0x83, "Korisnik"), T(0x84, "Ime2"), T(0x85, "Adresa korisnika"))),
                T(0x98, "M1"), T(0x99, "2"), Ber.Build(0x9F24, Enc("CRVENA", 0)))).ToArray();
        var c = T(0x78, T(0x4F, "AID-TEST")).Concat(
            T(0x72, T(0xC1, "20300101"), T(0xC2, "0101990710000"), T(0xC3, "0202985710001"),
                T(0xC4, "480"), T(0xC5, "2014"), T(0xC9, "SN-0001"))).ToArray();
        var v = VehicleParser.Parse(new[] { FileA(), b, c });
        Assert.Equal("Vlasnik", v.OwnerSurname);          // A7 wins over the holder A2 of part 1
        Assert.Equal("Adresa korisnika", v.UserAddress);
        Assert.Equal("M1", v.Category); Assert.Equal("2", v.Axles); Assert.Equal("CRVENA", v.Colour);
        Assert.Equal("20300101", v.SaleBan); Assert.Equal("0101990710000", v.OwnerPersonalNo);
        Assert.Equal("0202985710001", v.UserPersonalNo); Assert.Equal("480", v.Load);
        Assert.Equal("2014", v.YearOfProduction); Assert.Equal("SN-0001", v.SerialNumber);
    }

    [Fact]
    public void Cyrillic8859_5IsDecodedByCharsetTag()
    {
        var f = T(0x78, T(0x4F, "X")).Concat(T(0x71,
            Ber.Build(0x9F37, new byte[] { 1 }),
            T(0xA1, T(0xA7, T(0x83, "Петровић", 1), T(0x84, "Њуба Ђурђевић", 1))))).ToArray();
        var v = VehicleParser.Parse(new[] { f });
        Assert.Equal("Петровић", v.OwnerSurname);
        Assert.Equal("Њуба Ђурђевић", v.OwnerName);
        Assert.Equal(1, v.CharsetTag);
    }

    [Fact]
    public void Utf8TextIsAcceptedWhenTheBytesAreValidUtf8()
    {
        var f = T(0x71, Ber.Build(0x81, Encoding.UTF8.GetBytes("Ćuprija")));
        var v = VehicleParser.Parse(new[] { f });
        Assert.Equal("Ćuprija", v.RegistrationNumber);
    }

    [Fact]
    public void LongFormLengthAndTwoByteTags()
    {
        var big = new string('A', 300);
        var f = T(0x71, T(0xA1, T(0xA7, T(0x85, big))));
        var v = VehicleParser.Parse(new[] { f });
        Assert.Equal(300, v.OwnerAddress.Length);
        var nodes = Ber.Parse(Ber.Build(0x9F33, new byte[] { 0x41 }));
        Assert.Equal(0x9F33, nodes[0].Tag);
    }

    [Fact]
    public void UnknownTagsAreCollectedWithoutValues()
    {
        var f = T(0x71, T(0x81, "X"), T(0xDF55, "secret"));
        var v = VehicleParser.Parse(new[] { f });
        Assert.Single(v.UnknownTags);
        Assert.Equal("DF55/6", v.UnknownTags[0]);
    }

    [Fact]
    public void GarbageDoesNotThrow()
    {
        Assert.Null(Ber.Parse(new byte[] { 0x71, 0x05, 1, 2 }));
        var v = VehicleParser.Parse(new byte[][] { new byte[] { 0x71, 0x05, 1, 2 }, null, new byte[0] });
        Assert.Equal("", v.RegistrationNumber);
    }

    [Fact]
    public void BadDatesAreKept()
    {
        Assert.Equal("2015", Text.Date("2015"));
        Assert.Equal("1x0312yy", Text.Date("1x0312yy"));
    }
}

public class VehicleRowsAndTextTests
{
    [Fact]
    public void RowsSkipEmptyAndHideNothingByThemselves()
    {
        var rows = VehicleRows.Build(VehicleRows.Demo());
        Assert.Contains(rows, r => r.Key == "vRegNo" && r.Value == "BG 123-AB");
        Assert.DoesNotContain(rows, r => r.Key == "vUser");           // demo has no user
        Assert.DoesNotContain(VehicleRows.Build(VehicleRows.Demo(), includeJmbg: false), r => r.Key == "vOwnerJmbg");
        Assert.All(rows, r => Assert.NotEqual("", r.Value));
    }

    [Fact]
    public void EveryRowKeyHasTextsInAllLanguages()
    {
        var data = VehicleRows.Demo();
        data.UserName = "A"; data.UserSurname = "B"; data.UserAddress = "C"; data.UserPersonalNo = "D"; data.SaleBan = "20300101";
        var keys = VehicleRows.Build(data).Select(r => r.Key).Concat(VehicleRows.Sensitive)
            .Concat(new[] { "vehNote", "vehTitle", "cardUnknown", "diagTitle", "diagText", "diagRun", "diagCopy", "diagCopied" }).Distinct();
        foreach (var lang in Enum.GetValues<Lang>())
        {
            Loc.Current = lang;
            foreach (var k in keys) { var s = Loc.T(k); Assert.False(string.IsNullOrWhiteSpace(s) || s == k, $"{lang} {k}"); }
        }
    }

    [Fact]
    public void SerbianCyrillicIsDerivedFromLatin()
    {
        Loc.Current = Lang.srCyrl;
        Assert.Equal("Регистарски број", Loc.T("vRegNo"));
        Loc.Current = Lang.en;
    }
}
