namespace SerbiaID;

public sealed class CardException : Exception
{
    public int Code { get; }
    public CardException(int code, string what) : base($"{what}: 0x{code:X8}") { Code = code; }
    public CardException(string message) : base(message) { }
}

/// Wrong PIN: card reports how many tries are left (63Cx).
public sealed class PinException : Exception
{
    public int TriesLeft { get; }
    public bool Blocked { get; }
    public PinException(int triesLeft, bool blocked)
        : base(blocked ? "PIN blocked" : $"Wrong PIN, {triesLeft} tries left") { TriesLeft = triesLeft; Blocked = blocked; }
}
