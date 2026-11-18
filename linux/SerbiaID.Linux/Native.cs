using System.Runtime.InteropServices;
using System.Text;

namespace SerbiaID;

/// libpcsclite (pcsc-lite, the PC/SC daemon client). Same surface as the Windows Native class so that Card.cs is shared,
/// but on Linux DWORD is `unsigned long` (64 bits) and SCARD_IO_REQUEST has two of them, so the calls are adapted here.
internal static class Native
{
    private const string Lib = "libpcsclite.so.1";

    [DllImport(Lib, EntryPoint = "SCardEstablishContext")] private static extern nint PSCardEstablishContext(nuint scope, IntPtr r1, IntPtr r2, out nint ctx);
    [DllImport(Lib, EntryPoint = "SCardReleaseContext")] private static extern nint PSCardReleaseContext(nint ctx);
    [DllImport(Lib, EntryPoint = "SCardListReaders")] private static extern nint PSCardListReaders(nint ctx, IntPtr groups, byte[] readers, ref nuint len);
    [DllImport(Lib, EntryPoint = "SCardConnect")] private static extern nint PSCardConnect(nint ctx, byte[] reader, nuint share, nuint protocols, out nint card, out nuint active);
    [DllImport(Lib, EntryPoint = "SCardDisconnect")] private static extern nint PSCardDisconnect(nint card, nuint disposition);
    [DllImport(Lib, EntryPoint = "SCardTransmit")] private static extern nint PSCardTransmit(nint card, IntPtr sendPci, byte[] send, nuint sendLen, IntPtr recvPci, byte[] recv, ref nuint recvLen);
    [DllImport(Lib, EntryPoint = "SCardGetAttrib")] private static extern nint PSCardGetAttrib(nint card, nuint attr, byte[] buf, ref nuint len);

    // pcsc-lite error codes are the same numbers as on Windows (as 32-bit values)
    private static int Rc(nint r) => unchecked((int)r);

    public static int SCardEstablishContext(uint scope, IntPtr r1, IntPtr r2, out IntPtr ctx)
    {
        try { var rc = PSCardEstablishContext((nuint)scope, r1, r2, out var c); ctx = c; return Rc(rc); }
        catch (DllNotFoundException) { ctx = IntPtr.Zero; return SCARD_E_NO_SERVICE; }
    }

    public static int SCardReleaseContext(IntPtr ctx) { try { return Rc(PSCardReleaseContext((nint)ctx)); } catch (DllNotFoundException) { return 0; } }

    public static int SCardListReadersW(IntPtr ctx, string groups, char[] readers, ref int len)
    {
        if (ctx == IntPtr.Zero) return SCARD_E_NO_SERVICE;
        nuint n = 0;
        if (readers == null)
        {
            var rc0 = Rc(PSCardListReaders((nint)ctx, IntPtr.Zero, null, ref n));
            len = (int)n;
            return rc0;
        }
        n = (nuint)len;
        var buf = new byte[len];
        var rc = Rc(PSCardListReaders((nint)ctx, IntPtr.Zero, buf, ref n));
        if (rc == 0)
        {
            var s = Encoding.UTF8.GetString(buf, 0, (int)n);
            s.CopyTo(0, readers, 0, Math.Min(s.Length, readers.Length));
            len = s.Length;
        }
        return rc;
    }

    public static int SCardConnectW(IntPtr ctx, string reader, uint share, uint protocols, out IntPtr card, out uint active)
    {
        card = IntPtr.Zero; active = 0;
        if (ctx == IntPtr.Zero) return SCARD_E_NO_SERVICE;
        var name = Encoding.UTF8.GetBytes(reader + "\0");
        var rc = Rc(PSCardConnect((nint)ctx, name, share, protocols, out var c, out var a));
        card = c; active = (uint)a;
        return rc;
    }

    public static int SCardDisconnect(IntPtr card, uint disposition) => Rc(PSCardDisconnect((nint)card, (nuint)disposition));

    /// `sendPci` comes from Card.cs in the Windows layout (two int32: protocol, length); the real structure is built here.
    public static int SCardTransmit(IntPtr card, IntPtr sendPci, byte[] send, int sendLen, IntPtr recvPci, byte[] recv, ref int recvLen)
    {
        int proto = Marshal.ReadInt32(sendPci, 0);
        var pci = Marshal.AllocHGlobal(2 * IntPtr.Size);
        try
        {
            Marshal.WriteIntPtr(pci, 0, (IntPtr)proto);
            Marshal.WriteIntPtr(pci, IntPtr.Size, (IntPtr)(2 * IntPtr.Size));
            nuint n = (nuint)recvLen;
            var rc = Rc(PSCardTransmit((nint)card, pci, send, (nuint)sendLen, IntPtr.Zero, recv, ref n));
            recvLen = (int)n;
            return rc;
        }
        finally { Marshal.FreeHGlobal(pci); }
    }

    public static int SCardGetAttrib(IntPtr card, uint attr, byte[] buf, ref int len)
    {
        nuint n = (nuint)len;
        var rc = Rc(PSCardGetAttrib((nint)card, (nuint)attr, buf, ref n));
        len = (int)n;
        return rc;
    }

    public const int SCARD_E_NO_SMARTCARD = unchecked((int)0x8010000C);
    public const int SCARD_E_NO_READERS_AVAILABLE = unchecked((int)0x8010002E);
    public const int SCARD_E_NO_SERVICE = unchecked((int)0x8010001D);
    public const int SCARD_E_SERVICE_STOPPED = unchecked((int)0x8010001E);
    public const int SCARD_E_INVALID_HANDLE = unchecked((int)0x80100003);
    public const int SCARD_W_UNRESPONSIVE_CARD = unchecked((int)0x80100066);
    public const int SCARD_W_REMOVED_CARD = unchecked((int)0x80100069);
}
