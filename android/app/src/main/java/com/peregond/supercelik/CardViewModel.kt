package com.peregond.supercelik

import android.app.Application
import android.content.Context
import android.net.Uri
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
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

/** Where the app is in a card operation. Idle = nothing running; a connected USB reader starts the default read. */
enum class Phase { Idle, WaitingUsb, Reading }

/** A one-line result shown as a snackbar. */
data class Msg(@StringRes val id: Int, val arg: String? = null, val error: Boolean = true)

/** User-facing message for a failed card operation. */
fun cardError(e: Exception): Msg = when {
    e is PinException && e.blocked -> Msg(R.string.pin_blocked)
    e is PinException -> Msg(R.string.pin_wrong, e.triesLeft.toString())
    e is IllegalArgumentException -> Msg(R.string.pin_invalid)
    e is CardException && e.kind == CardException.Kind.NoCard -> Msg(R.string.err_no_card)
    e is CardException && e.kind == CardException.Kind.Unsupported -> Msg(R.string.card_unknown)
    e is CardException && e.kind == CardException.Kind.Lost -> Msg(R.string.err_lost)
    else -> Msg(R.string.err_generic, e.message)
}

class CardViewModel(app: Application) : AndroidViewModel(app) {
    private val prefs = app.getSharedPreferences("settings", Context.MODE_PRIVATE)

    private val _phase = MutableStateFlow(Phase.Idle)
    val phase: StateFlow<Phase> = _phase.asStateFlow()
    private val _personal = MutableStateFlow<PersonalData?>(null)
    val personal: StateFlow<PersonalData?> = _personal.asStateFlow()
    private val _vehicle = MutableStateFlow<VehicleData?>(null)
    val vehicle: StateFlow<VehicleData?> = _vehicle.asStateFlow()
    private val _health = MutableStateFlow<HealthData?>(null)
    val health: StateFlow<HealthData?> = _health.asStateFlow()
    private val _diagLog = MutableStateFlow<String?>(null)
    val diagLog: StateFlow<String?> = _diagLog.asStateFlow()
    private val _diagUnlocked = MutableStateFlow(false)
    val diagUnlocked: StateFlow<Boolean> = _diagUnlocked.asStateFlow()      // hidden: 5 taps on the version in Settings
    fun unlockDiag() { _diagUnlocked.value = true }
    private val _sig = MutableStateFlow<SigResult?>(null)
    val sig: StateFlow<SigResult?> = _sig.asStateFlow()
    private val _token = MutableStateFlow<TokenData?>(null)
    val token: StateFlow<TokenData?> = _token.asStateFlow()
    private val _message = MutableStateFlow<Msg?>(null)
    val message: StateFlow<Msg?> = _message.asStateFlow()

    // ---- settings ----
    private val _theme = MutableStateFlow(prefs.getInt("theme", 0))            // 0 system, 1 light, 2 dark
    val theme: StateFlow<Int> = _theme.asStateFlow()
    private val _dynamic = MutableStateFlow(prefs.getBoolean("wallpaper", false))
    val dynamic: StateFlow<Boolean> = _dynamic.asStateFlow()      // true = wallpaper (Material You) palette
    private val _mask = MutableStateFlow(prefs.getBoolean("mask", true))
    val mask: StateFlow<Boolean> = _mask.asStateFlow()

    private val _printJmbg = MutableStateFlow(prefs.getBoolean("printJmbg", true))
    val printJmbg: StateFlow<Boolean> = _printJmbg.asStateFlow()
    fun setPrintJmbg(v: Boolean) { _printJmbg.value = v; prefs.edit().putBoolean("printJmbg", v).apply() }

    private val _failed = MutableStateFlow(false)
    /** The last card operation (or the reader search) failed and nothing has been tried since: the mascots look worried. */
    val failed: StateFlow<Boolean> = _failed.asStateFlow()

    private fun report(m: Msg) { _message.value = m; if (m.error) _failed.value = true }

    private val _demo = MutableStateFlow(false)
    val demo: StateFlow<Boolean> = _demo.asStateFlow()      // fictional data on screen (Settings switch), no card involved

    /** Settings switch: shows fictional card data to look at the app, or goes back to the real reader. */
    fun setDemo(on: Boolean) { if (on) { cancel(); showDemo() } else { clear() } }

    private val _autoRead = MutableStateFlow(prefs.getBoolean("autoRead", true))
    val autoRead: StateFlow<Boolean> = _autoRead.asStateFlow()
    fun setAutoRead(v: Boolean) { _autoRead.value = v; prefs.edit().putBoolean("autoRead", v).apply() }

    fun setTheme(v: Int) { _theme.value = v; prefs.edit().putInt("theme", v).apply() }
    fun setDynamic(v: Boolean) { _dynamic.value = v; prefs.edit().putBoolean("wallpaper", v).apply() }
    fun setMask(v: Boolean) { _mask.value = v; prefs.edit().putBoolean("mask", v).apply() }

    // ---- card operations ----

    /** The operation that runs when a card shows up. Null = read the card (the default, started by plugging in a reader). */
    private var pending: ((EidCard) -> Unit)? = null
    /** A diagnostics run: gets the raw APDU channel instead of the eID protocol. */
    private var pendingRaw: ((CardTransport) -> Unit)? = null
    private var job: Job? = null

    private val readOp: (EidCard) -> Unit = { card ->
        val p = card.readPersonalData()
        val s = card.verifySignatures()
        _personal.value = p; _sig.value = s
    }

    private fun begin(op: (EidCard) -> Unit, context: Context) {
        _message.value = null; _failed.value = false
        pendingRaw = null
        pending = op
        startUsb(context)
    }

    /** One read for every card: an eID card (ID, foreigner card, residence permit), a health insurance card or a vehicle registration card. */
    fun readCard(context: Context) {
        _message.value = null; _failed.value = false
        pending = null; pendingRaw = null
        startUsb(context)
    }

    /** Hidden card diagnostics: structure of the card, no personal data, no PIN. */
    fun runDiagnostics(context: Context) {
        _message.value = null; _failed.value = false
        pending = null
        pendingRaw = { t ->
            val app = getApplication<Application>()
            val v = runCatching { app.packageManager.getPackageInfo(app.packageName, 0).versionName }.getOrNull() ?: ""
            _diagLog.value = CardDiag.run(t, v, "USB reader")
        }
        startUsb(context)
    }

    private fun readAny(t: CardTransport) {
        val eid = EidCard(t)
        val isEid = try { eid.selectApplet(); true } catch (e: CardException) { if (e.kind == CardException.Kind.Unsupported) false else throw e }
        if (isEid) { _vehicle.value = null; _health.value = null; readOp(eid); return }
        val hc = HealthCard(t)
        if (hc.selectApplet() != null) {
            _health.value = hc.read(); _vehicle.value = null
            _personal.value = null; _sig.value = null
            _message.value = Msg(R.string.h_note, error = false)
            return
        }
        _vehicle.value = RegistrationCard(t).read(); _health.value = null
        _personal.value = null; _sig.value = null
        _message.value = Msg(R.string.veh_note, error = false)
    }

    fun readToken(context: Context) = begin({ card ->
        _token.value = card.readToken()
    }, context)

    fun changePin(old: String, new: String, context: Context) = begin({ card ->
        card.changePin(old, new); _message.value = Msg(R.string.pin_changed, error = false)
    }, context)

    fun unblockPin(puk: String, new: String, context: Context) = begin({ card ->
        card.unblockPin(puk, new); _message.value = Msg(R.string.pin_unblocked, error = false)
    }, context)

    /** Signs `data` with the token key and writes a detached CMS (.p7s) to `out`. Needs the token certificate. */
    fun signFile(data: ByteArray, pin: String, out: Uri, context: Context) = begin({ card ->
        val cert = (_token.value ?: card.readToken()).certs.firstOrNull()
            ?: throw CardException(CardException.Kind.Other, "no certificate")
        val p7s = CardCrypto.signDetached(data, cert.der) { di -> card.sign(pin, di) }
        getApplication<Application>().contentResolver.openOutputStream(out)?.use { it.write(p7s) }
        _message.value = Msg(R.string.signed_saved, error = false)
    }, context)

    /** Certificates for the eUprava sign-in, read from the token; the screen opens when this turns true. */
    private val _euReady = MutableStateFlow(false)
    val euReady: StateFlow<Boolean> = _euReady.asStateFlow()
    fun consumeEuReady() { _euReady.value = false }

    /** Reads the token's certificate / key pairs (no PIN needed), then the sign-in screen opens. */
    fun prepareEuprava(context: Context) = begin({ card ->
        val pairs = card.tokenKeyPairs()
        if (pairs.isEmpty()) throw CardException(CardException.Kind.Other, "no certificate")
        EuLogin.pairs = pairs
        _euReady.value = true
    }, context)

    /** App opened or came back to the start screen: use a connected USB reader right away. */
    fun autoStart(context: Context) {
        // coming back from the eUprava sign-in screen: the user is on the Token tab, do not read the card by itself
        if (EuLogin.skipAutoStart) { EuLogin.skipAutoStart = false; return }
        if (!_autoRead.value) return                    // the user turned automatic reading off: only the buttons read
        if (_phase.value != Phase.Idle || _personal.value != null || _vehicle.value != null || _health.value != null) return
        val usb = usbManager(context) ?: return         // no USB service on this device: nothing to look for (the card screen says so)
        if (UsbCcidTransport.findReader(usb) != null) startUsb(context)
    }

    private var watchJob: Job? = null

    /** One user of the USB reader at a time: the card watcher's polling and a read must not open the reader together
     *  (claiming the interface twice makes the read fail with "connection lost"). */
    private val usbLock = kotlinx.coroutines.sync.Mutex()

    /** While the app is in front: when a card is put into an already connected reader, read it (the same as the desktop apps).
     *  A card that is already in when the app opens is read by autoStart; after any read the card has to be taken out first,
     *  so a card that cannot be read does not make the app retry in a loop. Needs the USB permission to be granted already. */
    fun watchCard(context: Context) {
        if (watchJob?.isActive == true) return
        val app = context.applicationContext
        watchJob = viewModelScope.launch {
            var removed = false                   // saw the slot empty since the last read
            while (true) {
                delay(1200)
                // keeps watching while a result is shown: taking the card out and putting another in reads the new one
                if (!_autoRead.value || _demo.value || _phase.value != Phase.Idle) { removed = false; continue }
                val usb = usbManager(app) ?: return@launch
                val device = UsbCcidTransport.findReader(usb)
                if (device == null || !usb.hasPermission(device)) { removed = false; continue }
                if (!usbLock.tryLock()) continue          // a read has the reader: do not touch it
                val present: Boolean?
                try {
                    present = withContext(Dispatchers.IO) {
                        try {
                            val t = UsbCcidTransport.open(app, device) ?: return@withContext null
                            try { t.cardPresent() } finally { t.release() }
                        } catch (_: Exception) { null }
                    }
                } finally { usbLock.unlock() }
                if (present == null) continue
                if (!present) removed = true
                else if (removed && _phase.value == Phase.Idle) { removed = false; readCard(app) }
            }
        }
    }

    fun stopWatching() { watchJob?.cancel(); watchJob = null }

    /** A reader was plugged in (the system started or woke the app for it): read only when automatic reading is on. */
    fun onReaderAttached(context: Context) { if (_autoRead.value) startUsb(context) }

    fun startUsb(context: Context) {
        val usb = usbManager(context)
        if (usb == null) { pending = null; pendingRaw = null; _phase.value = Phase.Idle; report(Msg(R.string.err_no_usb_host)); return }
        val device = UsbCcidTransport.findReader(usb)
        if (device == null) { pending = null; pendingRaw = null; _phase.value = Phase.Idle; report(Msg(R.string.err_no_usb)); return }
        _phase.value = Phase.WaitingUsb
        job = viewModelScope.launch {
          usbLock.withLock {
            val transport = UsbCcidTransport.open(context, device)
            if (transport == null) { pending = null; pendingRaw = null; _phase.value = Phase.Idle; report(Msg(R.string.err_usb_denied)); return@launch }
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
    }

    /** Runs the pending operation (or the default read) over a connected card. */
    private fun run(transport: CardTransport) {
        val t = FollowingTransport(transport)
        val raw = pendingRaw
        val op = pending
        try {
            when {
                raw != null -> raw(t)
                op != null -> op(EidCard(t))
                else -> readAny(t)
            }
            pending = null; pendingRaw = null
            _phase.value = Phase.Idle
        } catch (e: Exception) {
            fail(e)
        }
    }

    private fun fail(e: Exception) {
        DiagLog.error(e)
        pending = null; pendingRaw = null
        _phase.value = Phase.Idle
        report(cardError(e))
    }

    fun notify(m: Msg) = report(m)

    fun consumeMessage() { _message.value = null }

    /** Cancel a pending card operation / go back to listening. */
    fun cancel() {
        _euReady.value = false
        job?.cancel()
        pending = null; pendingRaw = null
        _phase.value = Phase.Idle
    }

    /** Drops all personal data from memory. */
    fun clear() {
        cancel()
        _demo.value = false; _failed.value = false
        _personal.value = null; _sig.value = null; _token.value = null; _vehicle.value = null; _health.value = null
    }

    /** Demo/screenshots only: open the PDF viewer as soon as the result is shown. */
    var demoOpenPdf = false

    /** Fictional data for screenshots (launch intent extra "demo"); never touches a card. */
    fun showDemo(vehicle: Boolean = false, health: Boolean = false) {
        _demo.value = true
        _personal.value = PersonalData(
            cardType = CardType.RP2024, docRegNo = "001234567", documentType = "RP",
            issuingDate = "01.01.2024", expiryDate = "01.01.2030", issuingAuthority = "MUP RS", docSerial = "RS1234567",
            personalNumber = "0101990710000", surname = "PETROVIĆ", givenName = "MARKO",
            parentGivenName = "Nikola", sex = "M", placeOfBirth = "Beograd", stateOfBirth = "Srbija",
            dateOfBirth = "01.01.1990", nationality = "Srbija",
            address = "Knez Mihailova 1, Beograd, Stari Grad", portrait = demoPortrait(),
            communityOfBirth = "Stari Grad", purposeOfStay = "Rad", documentName = "Dozvola za privremeni boravak i rad",
            addrState = "Srbija", community = "Stari Grad", place = "Beograd", street = "Knez Mihailova", houseNumber = "1",
            addressDate = "01.01.2024")
        _sig.value = SigResult.Ok
        _token.value = TokenData("NetSeT's CardEdge Token", "RP000000000", listOf(TokenCert("MARKO PETROVIC 000000000 Auth", ByteArray(0))))
        // launch extra "vehicle" with the demo: a vehicle registration card instead of the ID card
        if (vehicle) { _personal.value = null; _sig.value = null; _vehicle.value = VehicleRows.demo() }
        // launch extra "health": a health insurance card
        if (health) { _personal.value = null; _sig.value = null; _health.value = HealthRows.demo() }
    }

    /** A drawn silhouette so screenshots show the photo layout (demo mode only). */
    private fun demoPortrait(): ByteArray {
        val bmp = android.graphics.Bitmap.createBitmap(240, 310, android.graphics.Bitmap.Config.ARGB_8888)
        val c = android.graphics.Canvas(bmp)
        c.drawColor(0xFFD9E2EF.toInt())
        val p = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply { color = 0xFF8FA3BF.toInt() }
        c.drawCircle(120f, 120f, 56f, p)
        c.drawOval(android.graphics.RectF(30f, 190f, 210f, 400f), p)
        val out = java.io.ByteArrayOutputStream()
        bmp.compress(android.graphics.Bitmap.CompressFormat.JPEG, 90, out)
        return out.toByteArray()
    }
}
