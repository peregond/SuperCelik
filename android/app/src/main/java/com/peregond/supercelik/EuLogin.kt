package com.peregond.supercelik

import android.content.Context
import android.hardware.usb.UsbManager
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.runBlocking
import java.security.InvalidKeyException
import java.security.InvalidParameterException
import java.security.MessageDigest
import java.security.PrivateKey
import java.security.Provider
import java.security.PublicKey
import java.security.Security
import java.security.SignatureException
import java.security.SignatureSpi
import java.util.concurrent.CompletableFuture
import java.util.concurrent.TimeUnit

/*
 * Signing in to eUprava (prijava.eid.gov.rs) with the card certificate inside the app's own WebView.
 *
 * Chrome on Android takes TLS client certificates only from the system KeyChain, which a USB token cannot join.
 * A WebView, though, lets the app answer the certificate request itself: WebViewClient.onReceivedClientCertRequest
 * -> ClientCertRequest.proceed(privateKey, chain). Chromium then takes the public key from the certificate and asks
 * for each TLS signature through plain JCA (net/android/.../AndroidKeyStore.java):
 *     Signature.getInstance("SHA256withRSA").initSign(key); update(message); sign()
 * So the private key here is a handle (CardPrivateKey) and a small JCA provider, put first in the provider list while
 * the sign-in screen is open, claims exactly that key class and has the card do the RSA operation over USB.
 *
 * The certificate sign-in host (prijavas.eid.gov.rs) speaks TLS 1.2 only and asks for RSA PKCS#1 v1.5 with
 * SHA-1/256/384/512 (checked with openssl s_client). The card pads PKCS#1 v1.5 itself (MSE alg 2), so only those are
 * offered; RSA-PSS (TLS 1.3) is not needed there.
 *
 * PIN: asked in the app each time the card has to sign, kept only in a char array that is zeroed right after the one
 * VERIFY. After any failed attempt (wrong PIN, cancel, reader gone) no further card signature is made until the user
 * starts over, so Chromium's automatic handshake retries can never spend another PIN try.
 */

/** Handle for a private key that stays on the card. Not extractable. */
class CardPrivateKey(val pair: TokenKeyPair) : PrivateKey {
    override fun getAlgorithm(): String = "RSA"
    override fun getFormat(): String? = null
    override fun getEncoded(): ByteArray? = null
}

/** RSA PKCS#1 v1.5 signature: hashes what Chromium feeds in, wraps the hash in a DigestInfo, the card pads and signs. */
private class CardSignatureSpi(hash: String, private val prefix: ByteArray) : SignatureSpi() {
    private val md = MessageDigest.getInstance(hash)
    private var key: CardPrivateKey? = null

    override fun engineInitSign(privateKey: PrivateKey?) {
        key = privateKey as? CardPrivateKey ?: throw InvalidKeyException("not a card key")
        md.reset()
    }
    override fun engineInitVerify(publicKey: PublicKey?) = throw InvalidKeyException("signing only")
    override fun engineUpdate(b: Byte) = md.update(b)
    override fun engineUpdate(b: ByteArray, off: Int, len: Int) = md.update(b, off, len)
    override fun engineSign(): ByteArray {
        val k = key ?: throw SignatureException("not initialized")
        return EuLogin.signWithCard(k.pair, prefix + md.digest())
    }
    override fun engineVerify(sigBytes: ByteArray?): Boolean = throw SignatureException("signing only")
    @Deprecated("JCA legacy") override fun engineSetParameter(param: String?, value: Any?) = throw InvalidParameterException()
    @Deprecated("JCA legacy") override fun engineGetParameter(param: String?): Any = throw InvalidParameterException()
}

@Suppress("DEPRECATION")
private class CardKeyProvider : Provider(EuLogin.PROVIDER, 1.0, "Super Čelik: TLS client signatures by the card") {
    init {
        for ((alg, hash, prefix) in ALGS) {
            putService(object : Service(this, "Signature", alg, CardSignatureSpi::class.java.name, null, null) {
                override fun newInstance(constructorParameter: Any?): Any = CardSignatureSpi(hash, prefix)
                // only our own key handle: every other key goes to the normal providers
                override fun supportsParameter(parameter: Any?) = parameter is CardPrivateKey
            })
        }
    }

    companion object {
        private fun b(vararg v: Int) = ByteArray(v.size) { v[it].toByte() }
        val ALGS = listOf(
            Triple("SHA1withRSA", "SHA-1", b(0x30, 0x21, 0x30, 0x09, 0x06, 0x05, 0x2B, 0x0E, 0x03, 0x02, 0x1A, 0x05, 0x00, 0x04, 0x14)),
            Triple("SHA256withRSA", "SHA-256", b(0x30, 0x31, 0x30, 0x0D, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x01, 0x05, 0x00, 0x04, 0x20)),
            Triple("SHA384withRSA", "SHA-384", b(0x30, 0x41, 0x30, 0x0D, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x02, 0x05, 0x00, 0x04, 0x30)),
            Triple("SHA512withRSA", "SHA-512", b(0x30, 0x51, 0x30, 0x0D, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x03, 0x05, 0x00, 0x04, 0x40)),
        )
    }
}

/** State shared by the token tab (which reads the certificates) and the sign-in screen. Memory only. */
object EuLogin {
    const val START_URL = "https://euprava.gov.rs/prijava"
    const val PROVIDER = "SuperCelikCard"
    private const val DIRTY = "euWebDataDirty"

    /** Certificates of the token, read just before the sign-in screen opens. Never written to disk. */
    @Volatile var pairs: List<TokenKeyPair> = emptyList()

    sealed interface Status {
        data object Idle : Status
        data object Signing : Status
        data class Failed(val msg: Msg) : Status
    }

    /** A PIN request from Chromium's signing thread, answered by the dialog (null = cancelled). */
    class PinAsk(val label: String, val answer: CompletableFuture<CharArray?>)

    private val _status = MutableStateFlow<Status>(Status.Idle)
    val status: StateFlow<Status> = _status.asStateFlow()
    private val _pinAsk = MutableStateFlow<PinAsk?>(null)
    val pinAsk: StateFlow<PinAsk?> = _pinAsk.asStateFlow()

    /** Set after a failed card attempt: no further PIN prompt or card signature until [startOver]. */
    @Volatile var stopped = false
        private set

    fun startOver() { stopped = false; _status.value = Status.Idle }

    fun stop(msg: Msg) { stopped = true; _status.value = Status.Failed(msg) }

    /** Sign-in screen closed: forget the certificates and any pending PIN request. */
    fun reset() {
        _pinAsk.value?.answer?.complete(null)
        _pinAsk.value = null
        pairs = emptyList()
        startOver()
    }

    fun installProvider() {
        if (Security.getProvider(PROVIDER) == null) Security.insertProviderAt(CardKeyProvider(), 1)
    }

    fun removeProvider() = Security.removeProvider(PROVIDER)

    /** Remembers that the WebView may have left cookies / cache on disk, so the next app start wipes them. */
    fun markDirty(context: Context, dirty: Boolean) =
        context.getSharedPreferences("settings", Context.MODE_PRIVATE).edit().putBoolean(DIRTY, dirty).apply()

    fun isDirty(context: Context) = context.getSharedPreferences("settings", Context.MODE_PRIVATE).getBoolean(DIRTY, false)

    /** Called on Chromium's signing thread (blocking is expected there): asks for the PIN, then signs with the card. */
    internal fun signWithCard(pair: TokenKeyPair, digestInfo: ByteArray): ByteArray {
        if (stopped) throw SignatureException("stopped after a failed attempt")
        val ask = PinAsk(pair.label, CompletableFuture())
        _pinAsk.value = ask
        val pin = try { ask.answer.get(5, TimeUnit.MINUTES) } catch (_: Exception) { null } finally { _pinAsk.compareAndSet(ask, null) }
        if (pin == null) {
            stop(Msg(R.string.eu_cancelled))
            throw SignatureException("PIN entry cancelled")
        }
        _status.value = Status.Signing
        try {
            val sig = withCard { it.signWithPin(pin, digestInfo, pair.keyFile) }
            _status.value = Status.Idle
            return sig
        } catch (e: Exception) {
            stop(cardErrorMsg(e))
            throw SignatureException(e.message, e)
        } finally {
            pin.fill('\u0000')
        }
    }

    private class UsbProblem(val msg: Msg) : Exception(msg.toString())

    private fun <T> withCard(op: (EidCard) -> T): T {
        val ctx = App.instance
        val usb = ctx.getSystemService(Context.USB_SERVICE) as UsbManager
        val device = UsbCcidTransport.findReader(usb) ?: throw UsbProblem(Msg(R.string.err_no_usb))
        val transport = runBlocking { UsbCcidTransport.open(ctx, device) } ?: throw UsbProblem(Msg(R.string.err_usb_denied))
        return transport.use { it.powerOn(); op(EidCard(FollowingTransport(it))) }
    }

    private fun cardErrorMsg(e: Exception): Msg = if (e is UsbProblem) e.msg else cardError(e)
}
