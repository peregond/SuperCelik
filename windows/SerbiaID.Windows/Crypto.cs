using System.Security.Cryptography;
using System.Security.Cryptography.Pkcs;
using System.Security.Cryptography.X509Certificates;

namespace SerbiaID;

internal static class Crypto
{
    /// MUP root + intermediate CAs, copied next to the exe in the CA folder.
    /// The files are on disk, so each one is checked against the SHA-256 of the certificates this version shipped
    /// with: a .crt dropped into (or changed in) the folder is ignored and cannot become a trusted root.
    private static readonly HashSet<string> PinnedCa = new(StringComparer.OrdinalIgnoreCase)
    {
        "DF9F1F1F4844119D9EF60FEC211E19A44E8FD652013299BE0533A5B12EE606F0",   // MUPCAResursi3
        "68C197522983366A263A5E3BF45E672DF509ADF794B9EB1E9314D7487573DF1F",   // MUPCARoot3
        "0E3EFEB4F77F95118D2A2D5870709C924647BBDB801CAFDBE727D3F4DC354566",   // MUPGradjaniCA4
        "5D71C57BA744FFDFD532C7914193A7E1264F2E97D890D69595EDAB2F623544F1",   // MUPResursiCA4
        "6DCA4AB9CABD18E5CB0023054316ABF78C99B531B2E3AA103109AFB9DFA836D4",   // MUPRootCA4
        "923234E9382D75390BF2B67595301E2CFE2BB1650F707F5436BDF652D9F339FC",   // MUPStranciCA4
    };

    private static readonly Lazy<List<X509Certificate2>> Anchors = new(() =>
    {
        var dir = Path.Combine(AppContext.BaseDirectory, "CA");
        var list = new List<X509Certificate2>();
        if (Directory.Exists(dir))
            foreach (var f in Directory.GetFiles(dir, "*.crt"))
                try
                {
                    var c = new X509Certificate2(f);
                    if (PinnedCa.Contains(Convert.ToHexString(SHA256.HashData(c.RawData)))) list.Add(c);
                }
                catch { }
        return list;
    });

    private static bool Chains(X509Certificate2 cert, out string error)
    {
        using var chain = new X509Chain();
        chain.ChainPolicy.TrustMode = X509ChainTrustMode.CustomRootTrust;
        chain.ChainPolicy.RevocationMode = X509RevocationMode.NoCheck;   // no CRL/OCSP (offline)
        foreach (var a in Anchors.Value)
        {
            if (a.Subject == a.Issuer) chain.ChainPolicy.CustomTrustStore.Add(a);   // self-signed roots only
            else chain.ChainPolicy.ExtraStore.Add(a);
        }
        bool ok = chain.Build(cert);
        error = ok ? null : string.Join("; ", chain.ChainStatus.Select(s => s.StatusInformation.Trim()));
        return ok;
    }

    /// Verifies a BER CMS SignedData. Returns the signed content (null if the signature itself is bad).
    /// `chainOk` tells whether the signer chains to the bundled MUP CAs.
    public static byte[] VerifyCms(byte[] blob, out bool chainOk, out string error)
    {
        chainOk = false; error = null;
        try
        {
            var cms = new SignedCms();
            cms.Decode(blob);
            cms.CheckSignature(verifySignatureOnly: true);
            var signer = cms.SignerInfos[0].Certificate;
            chainOk = signer != null && Chains(signer, out error);
            return cms.ContentInfo.Content;
        }
        catch (Exception e) { error = e.Message; return null; }
    }

    public static void Describe(TokenCertificate c)
    {
        try
        {
            using var x = new X509Certificate2(c.Der);
            c.Subject = x.GetNameInfo(X509NameType.SimpleName, false);
            c.Issuer = x.GetNameInfo(X509NameType.SimpleName, true);
            c.NotBefore = x.NotBefore; c.NotAfter = x.NotAfter;
            c.ChainTrusted = Chains(x, out c.ChainError);
        }
        catch (Exception e) { c.ChainError = e.Message; }
    }

    private static byte[] DigestInfoPrefix(HashAlgorithmName n) =>
        n == HashAlgorithmName.SHA1 ? Convert.FromHexString("3021300906052B0E03021A05000414")
        : n == HashAlgorithmName.SHA256 ? Convert.FromHexString("3031300D060960864801650304020105000420")
        : n == HashAlgorithmName.SHA384 ? Convert.FromHexString("3041300D060960864801650304020205000430")
        : n == HashAlgorithmName.SHA512 ? Convert.FromHexString("3051300D060960864801650304020305000440")
        : throw new CryptographicException("Unsupported hash");

    /// RSA key that lives on the card: SignHash goes to the token (PIN is verified on every call).
    private sealed class CardRsa : System.Security.Cryptography.RSA
    {
        private readonly Func<byte[], byte[]> _sign;
        public CardRsa(int keySize, Func<byte[], byte[]> sign) { _sign = sign; KeySizeValue = keySize; }
        public override byte[] SignHash(byte[] hash, HashAlgorithmName n, RSASignaturePadding padding)
        {
            if (padding != RSASignaturePadding.Pkcs1) throw new CryptographicException("Only PKCS#1 v1.5");
            return _sign(DigestInfoPrefix(n).Concat(hash).ToArray());
        }
        public override RSAParameters ExportParameters(bool includePrivateParameters) => throw new NotSupportedException();
        public override void ImportParameters(RSAParameters parameters) => throw new NotSupportedException();
    }

    /// Detached CMS (.p7s) over `data`, signed by the token key. `signDigestInfo` performs the card operation.
    public static byte[] SignDetachedCms(byte[] data, byte[] certDer, Func<byte[], byte[]> signDigestInfo)
    {
        using var cert = new X509Certificate2(certDer);
        int bits = cert.GetRSAPublicKey()?.KeySize ?? throw new CryptographicException("Token certificate is not RSA");
        using var rsa = new CardRsa(bits, signDigestInfo);
        var signer = new CmsSigner(SubjectIdentifierType.IssuerAndSerialNumber, cert, rsa)
        {
            DigestAlgorithm = new System.Security.Cryptography.Oid("2.16.840.1.101.3.4.2.1"),   // SHA-256
            IncludeOption = X509IncludeOption.EndCertOnly,
        };
        var cms = new SignedCms(new ContentInfo(data), detached: true);
        cms.ComputeSignature(signer, silent: true);
        return cms.Encode();
    }
}
