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
