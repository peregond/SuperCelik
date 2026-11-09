using System.Runtime.InteropServices;

namespace SerbiaID;

internal static class Native
{
    [DllImport("winscard.dll")]
    public static extern int SCardEstablishContext(uint scope, IntPtr r1, IntPtr r2, out IntPtr ctx);

    [DllImport("winscard.dll")]
    public static extern int SCardReleaseContext(IntPtr ctx);

    [DllImport("winscard.dll", CharSet = CharSet.Unicode)]
    public static extern int SCardListReadersW(IntPtr ctx, string groups, char[] readers, ref int len);

    [DllImport("winscard.dll", CharSet = CharSet.Unicode)]
    public static extern int SCardConnectW(IntPtr ctx, string reader, uint share, uint protocols,
                                           out IntPtr card, out uint active);

    [DllImport("winscard.dll")]
    public static extern int SCardDisconnect(IntPtr card, uint disposition);

    [DllImport("winscard.dll")]
    public static extern int SCardTransmit(IntPtr card, IntPtr sendPci, byte[] send, int sendLen,
                                           IntPtr recvPci, byte[] recv, ref int recvLen);

    [DllImport("winscard.dll")]
    public static extern int SCardGetAttrib(IntPtr card, uint attr, byte[] buf, ref int len);

    public const int SCARD_E_NO_SMARTCARD = unchecked((int)0x8010000C);
    public const int SCARD_E_NO_READERS_AVAILABLE = unchecked((int)0x8010002E);
    public const int SCARD_W_UNRESPONSIVE_CARD = unchecked((int)0x80100066);
    public const int SCARD_W_REMOVED_CARD = unchecked((int)0x80100069);
}

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
