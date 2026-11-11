package com.peregond.supercelik

import org.bouncycastle.asn1.x509.AlgorithmIdentifier
import org.bouncycastle.cert.X509CertificateHolder
import org.bouncycastle.cert.jcajce.JcaCertStore
import org.bouncycastle.cert.jcajce.JcaX509CertificateConverter
import org.bouncycastle.cms.CMSProcessableByteArray
import org.bouncycastle.cms.CMSSignedData
import org.bouncycastle.cms.CMSSignedDataGenerator
import org.bouncycastle.cms.jcajce.JcaSignerInfoGeneratorBuilder
import org.bouncycastle.cms.jcajce.JcaSimpleSignerInfoVerifierBuilder
import org.bouncycastle.jce.provider.BouncyCastleProvider
import org.bouncycastle.operator.ContentSigner
import org.bouncycastle.operator.DefaultSignatureAlgorithmIdentifierFinder
import org.bouncycastle.operator.jcajce.JcaDigestCalculatorProviderBuilder
import org.bouncycastle.util.Selector
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.OutputStream
import java.security.MessageDigest
import java.security.cert.CertPathBuilder
import java.security.cert.CertStore
import java.security.cert.CertificateFactory
import java.security.cert.CollectionCertStoreParameters
import java.security.cert.PKIXBuilderParameters
import java.security.cert.TrustAnchor
import java.security.cert.X509CertSelector
import java.security.cert.X509Certificate
import java.util.Date

/** CMS verification (card signatures, chain to the bundled MUP CAs) and detached CMS signing with the token key. */
object CardCrypto {
    private val bc = BouncyCastleProvider()

    /** MUP root + intermediate CAs, shipped as assets/CA/*.crt (same files as the Mac and Windows apps). */
    private val anchors: List<X509Certificate> by lazy {
        val assets = App.instance.assets
        val cf = CertificateFactory.getInstance("X.509")
        (assets.list("CA") ?: emptyArray()).filter { it.endsWith(".crt") }.mapNotNull { name ->
            runCatching { assets.open("CA/$name").use { cf.generateCertificate(it) as X509Certificate } }.getOrNull()
        }
    }

    private fun isRoot(c: X509Certificate) = c.subjectX500Principal == c.issuerX500Principal

    /** True if `cert` chains to a bundled MUP root. Revocation is not checked (offline). */
    fun chains(cert: X509Certificate, extra: List<X509Certificate> = emptyList(), at: Date = Date()): String? = try {
        val roots = anchors.filter(::isRoot).map { TrustAnchor(it, null) }.toSet()
        val params = PKIXBuilderParameters(roots, X509CertSelector().apply { certificate = cert }).apply {
            isRevocationEnabled = false
            date = at
            addCertStore(CertStore.getInstance("Collection", CollectionCertStoreParameters(anchors.filterNot(::isRoot) + extra)))
        }
        CertPathBuilder.getInstance("PKIX").build(params)
        null
    } catch (e: Exception) {
        e.message ?: e.javaClass.simpleName
    }

    fun parseCert(der: ByteArray): X509Certificate =
        CertificateFactory.getInstance("X.509").generateCertificate(ByteArrayInputStream(der)) as X509Certificate

    class CmsResult(val content: ByteArray?, val chainOk: Boolean, val error: String?)

    /** Verifies a BER CMS SignedData. `content` is null if the signature itself is bad. */
    @Suppress("UNCHECKED_CAST")
    fun verifyCms(blob: ByteArray): CmsResult = try {
        val cms = CMSSignedData(blob)
        val signer = cms.signerInfos.signers.first()
        val holders = cms.certificates.getMatches(signer.sid as Selector<X509CertificateHolder>)
        val holder = holders.firstOrNull() ?: return CmsResult(null, false, "signer certificate missing")
        if (!signer.verify(JcaSimpleSignerInfoVerifierBuilder().setProvider(bc).build(holder))) {
            return CmsResult(null, false, "signature invalid")
        }
        val conv = JcaX509CertificateConverter().setProvider(bc)
        val all = cms.certificates.getMatches(null).map { conv.getCertificate(it) }
        val err = chains(conv.getCertificate(holder), all)
        CmsResult(cms.signedContent?.content as? ByteArray, err == null, err)
    } catch (e: Exception) {
        CmsResult(null, false, e.message ?: e.javaClass.simpleName)
    }

    private val SHA256_PREFIX = byteArrayOf(0x30, 0x31, 0x30, 0x0D, 0x06, 0x09, 0x60, 0x86.toByte(), 0x48, 0x01,
        0x65, 0x03, 0x04, 0x02, 0x01, 0x05, 0x00, 0x04, 0x20)

    /** ContentSigner whose RSA operation is done by the card: hashes the stream, wraps it in a DigestInfo, asks the card. */
    private class CardSigner(private val signDigestInfo: (ByteArray) -> ByteArray) : ContentSigner {
        private val buf = ByteArrayOutputStream()
        override fun getAlgorithmIdentifier(): AlgorithmIdentifier = DefaultSignatureAlgorithmIdentifierFinder().find("SHA256WITHRSA")
        override fun getOutputStream(): OutputStream = buf
        override fun getSignature(): ByteArray =
            signDigestInfo(SHA256_PREFIX + MessageDigest.getInstance("SHA-256").digest(buf.toByteArray()))
    }

    /** Detached CMS (.p7s) over `data`, signed by the token key. */
    fun signDetached(data: ByteArray, certDer: ByteArray, signDigestInfo: (ByteArray) -> ByteArray): ByteArray {
        val holder = X509CertificateHolder(certDer)
        val gen = CMSSignedDataGenerator()
        gen.addSignerInfoGenerator(
            JcaSignerInfoGeneratorBuilder(JcaDigestCalculatorProviderBuilder().setProvider(bc).build())
                .build(CardSigner(signDigestInfo), holder))
        gen.addCertificates(JcaCertStore(listOf(JcaX509CertificateConverter().setProvider(bc).getCertificate(holder))))
        return gen.generate(CMSProcessableByteArray(data), false).encoded
    }
}
