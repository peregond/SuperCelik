using System.Text;
using Xunit;

namespace SerbiaID;

/// Synthetic blocks built from docs/health-card-protocol.md (the layout recovered from the official reader). Not from a real card.
public class HealthParserTests
{
    static byte[] U(string s) => Encoding.Unicode.GetBytes(s);
    static byte[] A(string s) => Encoding.ASCII.GetBytes(s);
    static byte[] N(int v, int size) { var b = new byte[size]; for (int i = 0; i < size; i++) b[i] = (byte)(v >> (8 * i)); return b; }

    static byte[] El(int tag, byte[] v) => new[] { (byte)tag, (byte)(tag >> 8), (byte)v.Length, (byte)(v.Length >> 8) }.Concat(v).ToArray();

    static byte[] Block(ushort id, params byte[][] els)
    {
        var body = els.SelectMany(x => x).ToArray();
        return new[] { (byte)id, (byte)(id >> 8), (byte)body.Length, (byte)(body.Length >> 8) }.Concat(body).ToArray();
    }

    static byte[] Doc() => Block(0x0D01, El(0x611, U("RFZO")), El(0x612, A("100000000")), El(0x613, A("00000000001")),
        El(0x615, A("01012024")), El(0x616, A("01012029")), El(0x617, A("0123456789ABCDEF")), El(0x618, A("sr")));
    static byte[] Fix() => Block(0x0D02, El(0x621, A("00000000001")), El(0x622, U("Петровић")), El(0x623, U("Petrovic")),
        El(0x624, U("Марко")), El(0x625, U("Marko")), El(0x626, A("01011990")));
    static byte[] Card(bool permanent = false, bool expiry = true) => Block(0x0D03, El(0x630, A("00000000001")), El(0x631, A("01012024")),
        expiry ? El(0x632, A("31122030")) : new byte[0], El(0x633, N(permanent ? 1 : 0, 1)));
    static byte[] Admin() => Block(0x0D04, El(0x640, A("00000000001")), El(0x641, U("Јован")), El(0x643, N(2, 2)), El(0x644, A("0101990710000")),
        El(0x645, U("Кнез Михаилова")), El(0x646, A("11000")), El(0x648, U("Београд")), El(0x64A, U("1")),
        El(0x64E, A("010")), El(0x64F, U("Запослени")), El(0x658, A("01012015")), El(0x65A, U("Србија")));

    [Fact]
    public void ParsesAllBlocks()
    {
        var h = HealthParser.Parse(Doc(), Fix(), Card(), Admin());
        Assert.Empty(h.Problems); Assert.Empty(h.UnknownTags);
        Assert.Equal("RFZO", h.InsurerName); Assert.Equal("00000000001", h.CardId);
        Assert.Equal("01.01.2024", h.IssueDate);
        Assert.Equal("31.12.2030", h.ExpiryDate);            // the validity block wins over the document block
        Assert.Equal("0123456789ABCDEF", h.ChipSerial);
        Assert.Equal("Петровић", h.Surname); Assert.Equal("Petrovic", h.SurnameLatin);
        Assert.Equal("Марко Петровић", h.FullName);
        Assert.Equal("01.01.1990", h.DateOfBirth); Assert.Equal("00000000001", h.InsurantNumber);
        Assert.Equal("Ž", h.Gender); Assert.Equal("0101990710000", h.PersonalNumber);
        Assert.Equal("Јован", h.ParentName);
        Assert.Equal("010", h.BasisCode); Assert.Equal("Запослени", h.BasisDescription);
        Assert.Equal("01.01.2015", h.InsuredFrom); Assert.Equal("Србија", h.Country);
        Assert.False(h.Permanent);
    }

    [Fact]
    public void GenderNumberMapsToLetters()
    {
        var m = HealthParser.Parse(Doc(), Fix(), Card(), Block(0x0D04, El(0x643, N(1, 2))));
        Assert.Equal("M", m.Gender);
    }

    [Fact]
    public void PermanentCardHasNoValidUntilRow()
    {
        var h = HealthParser.Parse(Doc(), Fix(), Card(true, false), Admin());
        Assert.True(h.Permanent);
        Assert.Equal("01.01.2029", h.ExpiryDate);            // falls back to the document block
        var rows = HealthRows.Build(h);
        Assert.DoesNotContain(rows, r => r.Key == "hValidUntil");
        Assert.Contains(rows, r => r.Key == "hPermanent");
    }

    [Fact]
    public void WrongBlockIdIsReportedNotParsed()
    {
        var wrong = Fix(); wrong[0] = 0x09;                  // header says another block
        var h = HealthParser.Parse(Doc(), wrong, Card(), Admin());
        Assert.Contains(h.Problems, p => p.StartsWith("0D02"));
        Assert.Equal("", h.Surname);
    }

    [Fact]
    public void DeclaredLengthLargerThanFileIsRejected()
    {
        var f = Fix(); f[2] = 0xFF; f[3] = 0x7F;
        Assert.Null(HealthParser.Records(f, 0x0D02));
        var h = HealthParser.Parse(null, f, null, null);
        Assert.Equal(4, h.Problems.Count);                   // three not read, one bad header
    }

    [Fact]
    public void MissingBlockLeavesTheRestAndNoException()
    {
        var h = HealthParser.Parse(Doc(), Fix(), null, null);
        Assert.Equal("Марко", h.GivenName); Assert.Equal("RFZO", h.InsurerName);
        Assert.Equal("01.01.2029", h.ExpiryDate);
        Assert.Equal(2, h.Problems.Count);
    }

    [Fact]
    public void UnknownTagsAreLoggedByStructureOnly()
    {
        var h = HealthParser.Parse(null, Block(0x0D02, El(0x6FF, A("secret"))), null, null);
        Assert.Contains("0D02/6FF/6", h.UnknownTags);
        Assert.DoesNotContain(h.UnknownTags, t => t.Contains("secret"));
    }

    [Fact]
    public void OddLengthUtf16FallsBackToUtf8()
    {
        var h = HealthParser.Parse(null, Block(0x0D02, El(0x624, Encoding.UTF8.GetBytes("Ana"))), null, null);
        Assert.Equal("Ana", h.GivenName);
    }

    [Fact]
    public void RowsAreGroupedAndHideEmptyOnes()
    {
        var h = HealthParser.Parse(Doc(), Fix(), Card(), Admin());
        var e = HealthRows.Entries(h);
        Assert.Equal("hSecPerson", e[0].Heading);
        Assert.DoesNotContain(e, x => x.Heading == "hSecCarrier" || x.Heading == "hSecTaxpayer");   // no holder, no payer in this data
        Assert.DoesNotContain(e, x => x.Key != null && x.Value.Length == 0);
        var noJmbg = HealthRows.Build(h, false);
        Assert.DoesNotContain(noJmbg, r => r.Key == "hJmbg");
        Assert.Contains(HealthRows.Build(h), r => r.Key == "hAddress" && r.Value.Contains("Кнез Михаилова 1"));
    }

    [Fact]
    public void DemoDataHasEverySection()
    {
        var titles = HealthRows.Entries(HealthRows.Demo()).Where(x => x.Heading != null).Select(x => x.Heading).ToList();
        Assert.Equal(new[] { "hSecPerson", "hSecCard", "hSecInsurance", "hSecTaxpayer" }, titles);
    }

    [Fact]
    public void EveryRowAndSectionKeyHasAText()
    {
        var keys = HealthRows.Entries(HealthRows.Demo()).Select(x => x.Heading ?? x.Key).Concat(new[] { "hSecCarrier", "hTitle", "hNote",
            "hCarrierName", "hCarrierLbo", "hCarrierJmbg", "hRelation", "hFamilyMember", "hPermanent" }).Distinct();
        foreach (var l in new[] { Lang.ru, Lang.en, Lang.sr, Lang.srCyrl, Lang.hu, Lang.sq, Lang.sk, Lang.ro, Lang.hr, Lang.uk, Lang.be })
            foreach (var k in keys) { var t = LocCards.Get(l, k); Assert.True(t != k && t.Length > 0, l + " " + k); }
    }
}
