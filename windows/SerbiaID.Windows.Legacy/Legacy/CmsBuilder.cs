using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text;

namespace SerbiaID;

/// Builds a detached CMS SignedData (.p7s, RSA PKCS#1 v1.5 + SHA-256) by hand. .NET Framework's CmsSigner can only sign
/// with a key it holds itself, and here the key stays on the card: it signs the DigestInfo we hand it.
internal static class CmsBuilder
{
    // OIDs (DER, without tag and length)
    private static readonly byte[] OidData = { 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x07, 0x01 };            // 1.2.840.113549.1.7.1
    private static readonly byte[] OidSignedData = { 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x07, 0x02 };      // 1.2.840.113549.1.7.2
    private static readonly byte[] OidSha256 = { 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x01 };          // 2.16.840.1.101.3.4.2.1
    private static readonly byte[] OidRsa = { 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01 };             // 1.2.840.113549.1.1.1
    private static readonly byte[] OidContentType = { 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x09, 0x03 };     // 1.2.840.113549.1.9.3
    private static readonly byte[] OidMessageDigest = { 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x09, 0x04 };   // 1.2.840.113549.1.9.4
    private static readonly byte[] OidSigningTime = { 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x09, 0x05 };     // 1.2.840.113549.1.9.5

    // DigestInfo prefix for SHA-256 (the card does the PKCS#1 padding only)
    private static readonly byte[] DigestInfoSha256 =
        { 0x30, 0x31, 0x30, 0x0D, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x01, 0x05, 0x00, 0x04, 0x20 };

    public static byte[] SignDetached(byte[] data, byte[] certDer, Func<byte[], byte[]> signDigestInfo) =>
        SignDetached(data, certDer, signDigestInfo, DateTime.UtcNow);

    internal static byte[] SignDetached(byte[] data, byte[] certDer, Func<byte[], byte[]> signDigestInfo, DateTime signingTimeUtc)
    {
        using (var sha = SHA256.Create())
        {
            var cert = new X509Certificate2(certDer);
            if (cert.PublicKey.Oid.Value != "1.2.840.113549.1.1.1") throw new CryptographicException("Token certificate is not RSA");

            // the attributes that are signed (encoded as SET OF when hashed, as [0] IMPLICIT in the SignerInfo)
            var attrs = Cat(
                Attr(OidContentType, Der(0x06, OidData)),
                Attr(OidMessageDigest, Der(0x04, sha.ComputeHash(data))),
                Attr(OidSigningTime, Der(0x17, Encoding.ASCII.GetBytes(signingTimeUtc.ToString("yyMMddHHmmss") + "Z"))));
            var toSign = Der(0x31, attrs);
            var signature = signDigestInfo(Cat(DigestInfoSha256, sha.ComputeHash(toSign)));

            var algSha256 = Der(0x30, Der(0x06, OidSha256), new byte[] { 0x05, 0x00 });
            var algRsa = Der(0x30, Der(0x06, OidRsa), new byte[] { 0x05, 0x00 });
            var signerInfo = Der(0x30,
                Der(0x02, new byte[] { 1 }),                                                       // version 1 (issuerAndSerialNumber)
                Der(0x30, cert.IssuerName.RawData, Der(0x02, SerialNumber(cert))),                 // sid
                algSha256,
                Der(0xA0, attrs),                                                                  // signedAttrs [0] IMPLICIT
                algRsa,
                Der(0x04, signature));

            var signedData = Der(0x30,
                Der(0x02, new byte[] { 1 }),                                                       // version 1
                Der(0x31, algSha256),                                                              // digestAlgorithms
                Der(0x30, Der(0x06, OidData)),                                                     // encapContentInfo, detached: no content
                Der(0xA0, certDer),                                                                // certificates [0] IMPLICIT
                Der(0x31, signerInfo));

            return Der(0x30, Der(0x06, OidSignedData), Der(0xA0, signedData));
        }
    }

    private static byte[] Attr(byte[] oid, byte[] value) => Der(0x30, Der(0x06, oid), Der(0x31, value));

    /// The certificate serial number as the content of a DER INTEGER (big endian, positive).
    private static byte[] SerialNumber(X509Certificate2 cert)
    {
        var hex = cert.SerialNumber.TrimStart('0');
        if (hex.Length == 0) hex = "00";
        if (hex.Length % 2 == 1) hex = "0" + hex;
        var b = Compat.FromHex(hex);
        return b[0] >= 0x80 ? Cat(new byte[] { 0 }, b) : b;
    }

    private static byte[] Der(byte tag, params byte[][] parts)
    {
        var body = Cat(parts);
        int n = body.Length;
        byte[] len;
        if (n < 0x80) len = new[] { (byte)n };
        else if (n < 0x100) len = new byte[] { 0x81, (byte)n };
        else if (n < 0x10000) len = new byte[] { 0x82, (byte)(n >> 8), (byte)n };
        else if (n < 0x1000000) len = new byte[] { 0x83, (byte)(n >> 16), (byte)(n >> 8), (byte)n };
        else len = new byte[] { 0x84, (byte)(n >> 24), (byte)(n >> 16), (byte)(n >> 8), (byte)n };
        return Cat(new[] { tag }, len, body);
    }

    private static byte[] Cat(params byte[][] parts)
    {
        int n = 0;
        foreach (var p in parts) n += p.Length;
        var r = new byte[n]; int o = 0;
        foreach (var p in parts) { Buffer.BlockCopy(p, 0, r, o, p.Length); o += p.Length; }
        return r;
    }
}
