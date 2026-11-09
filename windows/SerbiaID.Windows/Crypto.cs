using System.Security.Cryptography.Pkcs;
using System.Security.Cryptography.X509Certificates;

namespace SerbiaID;

internal static class Crypto
{
    /// MUP root + intermediate CAs, copied next to the exe in the CA folder.
    private static readonly Lazy<List<X509Certificate2>> Anchors = new(() =>
    {
        var dir = Path.Combine(AppContext.BaseDirectory, "CA");
        var list = new List<X509Certificate2>();
        if (Directory.Exists(dir))
            foreach (var f in Directory.GetFiles(dir, "*.crt"))
                try { list.Add(new X509Certificate2(f)); } catch { }
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
}
