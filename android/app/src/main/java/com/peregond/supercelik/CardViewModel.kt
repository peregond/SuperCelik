package com.peregond.supercelik

import android.app.Application
import android.content.Context
import android.hardware.usb.UsbManager
import android.net.Uri
import android.nfc.NfcAdapter
import android.nfc.Tag
import android.nfc.tech.IsoDep
import androidx.annotation.StringRes
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** Where the app is in a card operation. Idle = listening for an NFC card with the default operation (read the card). */
enum class Phase { Idle, WaitingNfc, WaitingUsb, Reading }

/** A one-line result shown as a snackbar. */
data class Msg(@StringRes val id: Int, val arg: String? = null, val error: Boolean = true)

class CardViewModel(app: Application) : AndroidViewModel(app) {
    private val prefs = app.getSharedPreferences("settings", Context.MODE_PRIVATE)

    private val _phase = MutableStateFlow(Phase.Idle)
    val phase: StateFlow<Phase> = _phase.asStateFlow()
    private val _personal = MutableStateFlow<PersonalData?>(null)
    val personal: StateFlow<PersonalData?> = _personal.asStateFlow()
    private val _sig = MutableStateFlow<SigResult?>(null)
    val sig: StateFlow<SigResult?> = _sig.asStateFlow()
    private val _token = MutableStateFlow<TokenData?>(null)
    val token: StateFlow<TokenData?> = _token.asStateFlow()
    private val _message = MutableStateFlow<Msg?>(null)
    val message: StateFlow<Msg?> = _message.asStateFlow()

    // ---- settings ----
    private val _theme = MutableStateFlow(prefs.getInt("theme", 0))            // 0 system, 1 light, 2 dark
    val theme: StateFlow<Int> = _theme.asStateFlow()
    private val _dynamic = MutableStateFlow(prefs.getBoolean("dynamic", true))
    val dynamic: StateFlow<Boolean> = _dynamic.asStateFlow()
    private val _mask = MutableStateFlow(prefs.getBoolean("mask", true))
    val mask: StateFlow<Boolean> = _mask.asStateFlow()
    private val _autoClear = MutableStateFlow(prefs.getInt("autoClear", 5))     // minutes, 0 = off
    val autoClear: StateFlow<Int> = _autoClear.asStateFlow()

    fun setTheme(v: Int) { _theme.value = v; prefs.edit().putInt("theme", v).apply() }
    fun setDynamic(v: Boolean) { _dynamic.value = v; prefs.edit().putBoolean("dynamic", v).apply() }
    fun setMask(v: Boolean) { _mask.value = v; prefs.edit().putBoolean("mask", v).apply() }
    fun setAutoClear(v: Int) { _autoClear.value = v; prefs.edit().putInt("autoClear", v).apply(); scheduleClear() }

    // ---- card operations ----

    /** The operation that runs when a card shows up. Null = read the card (the default, started by a plain NFC tap). */
    private var pending: ((EidCard) -> Unit)? = null
    private var job: Job? = null
    private var clearJob: Job? = null

    /** NFC reader mode stays on whenever the app waits for a card. */
    fun listensNfc(p: Phase = _phase.value) = p == Phase.Idle || p == Phase.WaitingNfc

    private val readOp: (EidCard) -> Unit = { card ->
        val p = card.readPersonalData()
        val s = card.verifySignatures()
        _personal.value = p; _sig.value = s
        scheduleClear()
    }

    private fun begin(op: (EidCard) -> Unit, nfc: NfcAdapter?, context: Context?) {
        _message.value = null
        pending = op
        val usb = context?.let { UsbCcidTransport.findReader(it.getSystemService(Context.USB_SERVICE) as UsbManager) }
        if (usb != null && context != null) { startUsb(context); return }
        if (nfc == null || !nfc.isEnabled) { pending = null; _message.value = Msg(R.string.err_no_nfc_or_usb); return }
        _phase.value = Phase.WaitingNfc
    }

    fun readCard(nfc: NfcAdapter?, context: Context) = begin(readOp, nfc, context)

    fun readToken(nfc: NfcAdapter?, context: Context) = begin({ card ->
        _token.value = card.readToken()
    }, nfc, context)

    fun changePin(old: String, new: String, nfc: NfcAdapter?, context: Context) = begin({ card ->
        card.changePin(old, new); _message.value = Msg(R.string.pin_changed, error = false)
    }, nfc, context)

    fun unblockPin(puk: String, new: String, nfc: NfcAdapter?, context: Context) = begin({ card ->
        card.unblockPin(puk, new); _message.value = Msg(R.string.pin_unblocked, error = false)
    }, nfc, context)

    /** Signs `data` with the token key and writes a detached CMS (.p7s) to `out`. Needs the token certificate. */
    fun signFile(data: ByteArray, pin: String, out: Uri, nfc: NfcAdapter?, context: Context) = begin({ card ->
        val cert = (_token.value ?: card.readToken()).certs.firstOrNull()
            ?: throw CardException(CardException.Kind.Other, "no certificate")
        val p7s = CardCrypto.signDetached(data, cert.der) { di -> card.sign(pin, di) }
        getApplication<Application>().contentResolver.openOutputStream(out)?.use { it.write(p7s) }
        _message.value = Msg(R.string.signed_saved, error = false)
    }, nfc, context)

    /** Called by NFC reader mode (on a binder thread). */
    fun onTag(tag: Tag) {
        val iso = IsoDep.get(tag) ?: return     // some other tag: keep waiting
        if (!listensNfc()) return
        _phase.value = Phase.Reading
        job = viewModelScope.launch(Dispatchers.IO) {
            try {
                iso.connect()
                run(NfcTransport(iso))
            } catch (e: Exception) {
                fail(e)
            } finally {
                try { iso.close() } catch (_: Exception) { }
            }
        }
    }

    /** App opened or came back to the start screen: use a connected USB reader right away. */
    fun autoStart(context: Context) {
        if (_phase.value != Phase.Idle || _personal.value != null) return
        val usb = context.getSystemService(Context.USB_SERVICE) as UsbManager
        if (UsbCcidTransport.findReader(usb) != null) startUsb(context)
    }

    fun startUsb(context: Context) {
        val usb = context.getSystemService(Context.USB_SERVICE) as UsbManager
        val device = UsbCcidTransport.findReader(usb)
        if (device == null) { pending = null; _phase.value = Phase.Idle; _message.value = Msg(R.string.err_no_usb); return }
        _phase.value = Phase.WaitingUsb
        job = viewModelScope.launch {
            val transport = UsbCcidTransport.open(context, device)
            if (transport == null) { pending = null; _phase.value = Phase.Idle; _message.value = Msg(R.string.err_usb_denied); return@launch }
            _phase.value = Phase.Reading
            withContext(Dispatchers.IO) {
                try {
                    transport.use { it.powerOn(); run(it) }
                } catch (e: Exception) {
                    fail(e)
                }
            }
        }
    }

    /** Runs the pending operation (or the default read) over a connected card. */
    private fun run(transport: CardTransport) {
        val op = pending ?: readOp
        try {
            op(EidCard(FollowingTransport(transport)))
            pending = null
            _phase.value = Phase.Idle
        } catch (e: Exception) {
            fail(e)
        }
    }

    private fun fail(e: Exception) {
        pending = null
        _phase.value = Phase.Idle
        _message.value = when {
            e is PinException && e.blocked -> Msg(R.string.pin_blocked)
            e is PinException -> Msg(R.string.pin_wrong, e.triesLeft.toString())
            e is IllegalArgumentException -> Msg(R.string.pin_invalid)
            e is CardException && e.kind == CardException.Kind.NoCard -> Msg(R.string.err_no_card)
            e is CardException && e.kind == CardException.Kind.Unsupported -> Msg(R.string.err_unsupported)
            e is CardException && e.kind == CardException.Kind.Lost -> Msg(R.string.err_lost)
            else -> Msg(R.string.err_generic, e.message)
        }
    }

    fun notify(m: Msg) { _message.value = m }

    fun consumeMessage() { _message.value = null }

    /** Cancel a pending card operation / go back to listening. */
    fun cancel() {
        job?.cancel()
        pending = null
        _phase.value = Phase.Idle
    }

    /** Drops all personal data from memory. */
    fun clear() {
        cancel()
        clearJob?.cancel()
        _personal.value = null; _sig.value = null; _token.value = null
    }

    private fun scheduleClear() {
        clearJob?.cancel()
        val minutes = _autoClear.value
        if (minutes <= 0 || _personal.value == null) return
        clearJob = viewModelScope.launch {
            delay(minutes * 60_000L)
            _personal.value = null; _sig.value = null; _token.value = null
            _message.value = Msg(R.string.auto_cleared, error = false)
        }
    }

    /** Fictional data for screenshots (launch intent extra "demo"); never touches a card. */
    fun showDemo() {
        _personal.value = PersonalData(
            cardType = CardType.RP2024, docRegNo = "001234567", documentType = "RP",
            issuingDate = "01.01.2024", expiryDate = "01.01.2030", issuingAuthority = "MUP RS", docSerial = "RS1234567",
            personalNumber = "0101990710000", surname = "PETROVIĆ", givenName = "MARKO",
            parentGivenName = "Nikola", sex = "M", placeOfBirth = "Beograd", stateOfBirth = "Srbija",
            dateOfBirth = "01.01.1990", nationality = "Srbija",
            address = "Knez Mihailova 1, Beograd, Stari Grad", portrait = null)
        _sig.value = SigResult.Ok
        _token.value = TokenData("NetSeT's CardEdge Token", "RP000000000", listOf(TokenCert("MARKO PETROVIC 000000000 Auth", ByteArray(0))))
    }
}
