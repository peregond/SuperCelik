namespace SerbiaID;

public enum CardType { ID2014 = 2, IF2020 = 3, RP2024 = 4 }

public sealed class DocumentData
{
    public string DocRegNo = "", DocumentType = "", IssuingDate = "", ExpiryDate = "";
    public string IssuingAuthority = "", DocumentSerialNumber = "", ChipSerialNumber = "", DocumentName = "";
}

public sealed class FixedPersonalData
{
    public string PersonalNumber = "", Surname = "", GivenName = "", ParentGivenName = "";
    public string Sex = "", PlaceOfBirth = "", StateOfBirth = "", DateOfBirth = "", CommunityOfBirth = "";
    public string StatusOfForeigner = "", NationalityFull = "", PurposeOfStay = "", ENote = "";
}

public sealed class VariablePersonalData
{
    public string State = "", Community = "", Place = "", Street = "", HouseNumber = "";
    public string HouseLetter = "", Entrance = "", Floor = "", ApartmentNumber = "";
    public string AddressDate = "", AddressLabel = "";

    public string Formatted
    {
        get
        {
            var parts = new List<string> { string.Join(" ", new[] { Street, HouseNumber + HouseLetter }.Where(s => s.Length > 0)) };
            if (Entrance.Length > 0) parts.Add("ul. " + Entrance);
            if (Floor.Length > 0) parts.Add("sprat " + Floor);
            if (ApartmentNumber.Length > 0) parts.Add("stan " + ApartmentNumber);
            parts.AddRange(new[] { Place, Community, State });
            return string.Join(", ", parts.Where(s => s.Length > 0));
        }
    }
}

public sealed class PersonalData
{
    public CardType CardType = CardType.ID2014;
    public DocumentData Document = new();
    public FixedPersonalData Fixed = new();
    public VariablePersonalData Variable = new();
    public byte[] Portrait;           // JPEG
}

public sealed class TokenCertificate
{
    public string Label = "";
    public byte[] Der;
    public string Subject = "", Issuer = "";
    public DateTime NotBefore, NotAfter;
    public bool ChainTrusted;
    public string ChainError;
}

public sealed class TokenInfo
{
    public string Label = "", Serial = "";
    public List<TokenCertificate> Certificates = new();
}

public enum SigResult { Ok, ChainNotTrusted, Invalid }

public sealed class SigStatus
{
    public SigResult Result;
    public string Detail = "";
}
