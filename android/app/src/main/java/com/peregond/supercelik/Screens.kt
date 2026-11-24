package com.peregond.supercelik

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.FileProvider
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.text.SimpleDateFormat
import java.util.Locale

// ---------------------------------------------------------------- shared pieces

@Composable
fun Pill(text: String, color: Color, container: Color) {
    Surface(color = container, shape = RoundedCornerShape(50)) {
        Text(text, Modifier.padding(horizontal = 12.dp, vertical = 6.dp), color = color, style = MaterialTheme.typography.labelLarge)
    }
}

/** The illustrated mascot (the card reader or the key, as on the other systems) with a slow, small "breathing" motion. */
@Composable
private fun Mascot(@androidx.annotation.DrawableRes id: Int, size: Dp = 168.dp) {
    val t = rememberInfiniteTransition(label = "mascot")
    val scale by t.animateFloat(1f, 1.04f, infiniteRepeatable(tween(1800, easing = FastOutSlowInEasing), RepeatMode.Reverse), label = "scale")
    Image(painterResource(id), null, Modifier.size(size).scale(scale), contentScale = ContentScale.Fit)
}

/** Full-screen "looking for the reader / reading" overlay for a card operation. */
@Composable
fun WaitingOverlay(phase: Phase, onCancel: () -> Unit) {
    val text = if (phase == Phase.Reading) R.string.reading else R.string.hint_usb_wait
    Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.surface.copy(alpha = 0.97f)) {
        Column(Modifier.fillMaxSize().padding(24.dp), Arrangement.Center, Alignment.CenterHorizontally) {
            Mascot(if (phase == Phase.Reading) R.drawable.mascot_reader_card else R.drawable.mascot_reader_present, 144.dp)
            Spacer(Modifier.height(16.dp))
            CircularProgressIndicator()
            Spacer(Modifier.height(24.dp))
            Text(stringResource(text), textAlign = TextAlign.Center, style = MaterialTheme.typography.titleMedium)
            if (phase != Phase.Reading) {
                Spacer(Modifier.height(16.dp))
                TextButton(onClick = onCancel) { Text(stringResource(R.string.cancel)) }
            }
        }
    }
}

@Composable
fun msgText(m: Msg): String = if (m.arg != null) stringResource(m.id, m.arg) else stringResource(m.id)

// ---------------------------------------------------------------- card tab

/** The reader page of the site, in the language of the app (Cyrillic or Latin Serbian by the script of the locale). */
private fun siteLang(ctx: Context): String {
    val loc = ctx.resources.configuration.locales[0]
    return when (loc.language) {
        "ru" -> "ru"
        "sr" -> if (loc.script == "Latn") "sr" else "sc"
        "hu", "sq", "sk", "ro", "hr", "uk", "be" -> loc.language
        else -> "en"
    }
}

private fun readerUrl(ctx: Context): String = "https://celik.peregon.cc/reader/?lang=${siteLang(ctx)}"
private fun changelogUrl(ctx: Context): String = "https://celik.peregon.cc/changelog/?lang=${siteLang(ctx)}&app=android"
private const val FEEDBACK_URL = "https://github.com/peregond/SuperCelik/issues/new"

private fun openUrl(ctx: Context, url: String) {
    try { ctx.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))) } catch (_: ActivityNotFoundException) { }
}

@Composable
fun CardScreen(vm: CardViewModel, reveal: Boolean) {
    val personal by vm.personal.collectAsStateWithLifecycle()
    val vehicle by vm.vehicle.collectAsStateWithLifecycle()
    val ctx = LocalContext.current
    val p = personal
    val v = vehicle
    if (p == null && v != null) { VehicleResult(vm, v, reveal); return }
    if (p == null) {
        Column(
            Modifier.fillMaxSize().padding(24.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp, Alignment.CenterVertically),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            val noHost = remember { usbManager(ctx) == null }
            val failed by vm.failed.collectAsStateWithLifecycle()
            Mascot(if (noHost || failed) R.drawable.mascot_reader_sad else R.drawable.mascot_reader_present)
            Text(stringResource(R.string.hint_ready), textAlign = TextAlign.Center, style = MaterialTheme.typography.titleMedium)
            Text(stringResource(R.string.hint_idle), textAlign = TextAlign.Center, style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
            // a device without USB host support (some emulators, cloud phones): a reader cannot be connected here
            if (noHost) {
                Text(stringResource(R.string.err_no_usb_host), textAlign = TextAlign.Center, style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.error)
            }
            FilledTonalButton(onClick = { vm.readCard(ctx) }, Modifier.fillMaxWidth().height(56.dp)) {
                Icon(Icons.Filled.Usb, null); Spacer(Modifier.width(8.dp)); Text(stringResource(R.string.read_usb))
            }
            // which reader to get: the page opens in the browser (the same page as in the macOS and iOS apps)
            TextButton(onClick = {
                try { ctx.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(readerUrl(ctx)))) } catch (_: ActivityNotFoundException) { }
            }) { Text(stringResource(R.string.reader_help)) }
            Text(stringResource(R.string.about_note), textAlign = TextAlign.Center,
                style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        return
    }
    PersonalResult(vm, p, reveal)
}

/** A vehicle registration card on the card-data tab. STATUS: parsed per the specification, not yet checked on a real card. */
@Composable
private fun VehicleResult(vm: CardViewModel, v: VehicleData, revealAll: Boolean) {
    val mask by vm.mask.collectAsStateWithLifecycle()
    val flagPalette = LocalFlagPalette.current
    val heroBg = if (flagPalette) Flag.Blue else MaterialTheme.colorScheme.primaryContainer
    val heroFg = if (flagPalette) Color.White else MaterialTheme.colorScheme.onPrimaryContainer
    val show = revealAll || !mask
    val ctx = LocalContext.current
    val printJmbg by vm.printJmbg.collectAsStateWithLifecycle()
    var pdfFile by remember { mutableStateOf<File?>(null) }
    // three groups in the order of the printout of MUP's reader: document, owner and user, vehicle (the plate is the card's title)
    val sections = VehicleRows.sections(v).map { (title, rows) ->
        vehicleLabel(title) to rows.filter { it.first != "vRegNo" }.map { (k, s) -> Triple(vehicleLabel(k), s, k in VehicleRows.sensitive) }
    }
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(16.dp, 8.dp, 16.dp, 24.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        item {
            Card(Modifier.fillMaxWidth(), colors = CardDefaults.cardColors(containerColor = heroBg), shape = RoundedCornerShape(28.dp)) {
                Column(Modifier.padding(16.dp).fillMaxWidth()) {
                    Text(stringResource(R.string.veh_title), style = MaterialTheme.typography.labelLarge, color = heroFg.copy(alpha = 0.85f))
                    Text(v.registrationNumber, style = MaterialTheme.typography.titleLarge, color = heroFg)
                    ExpiryPill(v.expiryDate, onHero = flagPalette)
                }
            }
        }
        sections.forEach { (title, rows) -> item { Section(title, rows, show) } }
        item { Text(stringResource(R.string.veh_note), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
        item {
            FilledTonalButton(onClick = { pdfFile = Pdf.createVehicle(ctx, v, printJmbg) }, Modifier.fillMaxWidth()) {
                Icon(Icons.Filled.PictureAsPdf, null); Spacer(Modifier.width(8.dp)); Text(stringResource(R.string.view_pdf))
            }
        }
    }
    pdfFile?.let { PdfViewer(it) { pdfFile = null } }
}

@Composable
private fun PersonalResult(vm: CardViewModel, p: PersonalData, revealAll: Boolean) {
    val sig by vm.sig.collectAsStateWithLifecycle()
    val mask by vm.mask.collectAsStateWithLifecycle()
    val ctx = LocalContext.current
    val clipboard = LocalClipboardManager.current
    val bitmap = remember(p.portrait) { p.portrait?.let { BitmapFactory.decodeByteArray(it, 0, it.size)?.asImageBitmap() } }
    val show = revealAll || !mask
    val printJmbg by vm.printJmbg.collectAsStateWithLifecycle()
    val flagPalette = LocalFlagPalette.current
    val heroBg = if (flagPalette) Flag.Blue else MaterialTheme.colorScheme.primaryContainer
    val heroFg = if (flagPalette) Color.White else MaterialTheme.colorScheme.onPrimaryContainer
    var photoOpen by remember { mutableStateOf(false) }
    var pdfFile by remember { mutableStateOf<File?>(null) }
    LaunchedEffect(Unit) { if (vm.demoOpenPdf) { vm.demoOpenPdf = false; pdfFile = Pdf.create(ctx, p, true) } }

    val rows = listOf(
        Triple(R.string.surname, p.surname, false), Triple(R.string.given_name, p.givenName, false),
        Triple(R.string.parent_name, p.parentGivenName, false), Triple(R.string.dob, p.dateOfBirth, false),
        Triple(R.string.place_of_birth, p.placeOfBirth.ifBlank { p.stateOfBirth }, false), Triple(R.string.sex, p.sex, false),
        Triple(R.string.nationality, p.nationality, false), Triple(R.string.jmbg, p.personalNumber, true),
    )
    val docRows = listOf(
        Triple(R.string.doc_number, p.docRegNo, true), Triple(R.string.doc_serial, p.docSerial, true),
        Triple(R.string.issued_by, p.issuingAuthority, false), Triple(R.string.issue_date, p.issuingDate, false),
        Triple(R.string.expiry_date, p.expiryDate, false),
    )
    val allRows = (rows + docRows + Triple(R.string.address, p.address, true)).map { (k, v, _) -> ctx.getString(k) to v }

    LazyColumn(
        Modifier.fillMaxSize(),
        contentPadding = PaddingValues(16.dp, 8.dp, 16.dp, 24.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item {
            Card(Modifier.fillMaxWidth(), colors = CardDefaults.cardColors(containerColor = heroBg),
                shape = RoundedCornerShape(28.dp)) {
                Row(Modifier.padding(16.dp).fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    if (bitmap != null) {
                        Image(bitmap, stringResource(R.string.photo),
                            Modifier.size(96.dp, 124.dp).clip(RoundedCornerShape(16.dp)).clickable { photoOpen = true },
                            contentScale = ContentScale.Crop)
                        Spacer(Modifier.width(16.dp))
                    }
                    Column(Modifier.weight(1f)) {
                        Text(stringResource(docName(p.cardType)), style = MaterialTheme.typography.labelLarge, color = heroFg.copy(alpha = 0.85f))
                        Text("${p.givenName} ${p.surname}", style = MaterialTheme.typography.titleLarge, color = heroFg)
                        ExpiryPill(p.expiryDate, onHero = flagPalette)
                    }
                }
            }
        }
        item { SigCard(sig) }
        item { Section(R.string.person_section, rows, show) }
        item { Section(R.string.doc_section, docRows, show) }
        item { Section(R.string.address_section, listOf(Triple(R.string.address, p.address, true)), show) }
        item {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(onClick = {
                    clipboard.setText(AnnotatedString(allRows.filter { it.second.isNotBlank() }.joinToString("\n") { "${it.first}: ${it.second}" }))
                    vm.notify(Msg(R.string.copied, error = false))
                }, Modifier.weight(1f)) { Icon(Icons.Filled.ContentCopy, null); Spacer(Modifier.width(8.dp)); Text(stringResource(R.string.copy_all)) }
                FilledTonalButton(onClick = { pdfFile = Pdf.create(ctx, p, printJmbg) }, Modifier.weight(1f)) {
                    Icon(Icons.Filled.PictureAsPdf, null); Spacer(Modifier.width(8.dp)); Text(stringResource(R.string.view_pdf))
                }
            }
        }
    }
    if (photoOpen && bitmap != null) PhotoDialog(bitmap) { photoOpen = false }
    pdfFile?.let { PdfViewer(it) { pdfFile = null } }
}

@Composable
private fun PhotoDialog(bitmap: androidx.compose.ui.graphics.ImageBitmap, onClose: () -> Unit) {
    androidx.compose.ui.window.Dialog(onDismissRequest = onClose) {
        Card(shape = RoundedCornerShape(28.dp), modifier = Modifier.clickable { onClose() }) {
            Image(bitmap, stringResource(R.string.photo), Modifier.fillMaxWidth().padding(12.dp).clip(RoundedCornerShape(20.dp)), contentScale = ContentScale.FillWidth)
        }
    }
}

private fun docName(t: CardType) = when (t) {
    CardType.ID2014 -> R.string.doc_id
    CardType.IF2020 -> R.string.doc_if
    CardType.RP2024 -> R.string.doc_rp
}

@Composable
private fun ExpiryPill(expiry: String, onHero: Boolean) {
    val date = remember(expiry) { runCatching { SimpleDateFormat("dd.MM.yyyy", Locale.US).parse(expiry) }.getOrNull() } ?: return
    val days = ((date.time - System.currentTimeMillis()) / 86_400_000L).toInt()
    val (text, bad) = when {
        days < 0 -> stringResource(R.string.expired) to true
        days < 90 -> stringResource(R.string.expires_in_days, days) to true
        else -> stringResource(R.string.valid_until, expiry) to false
    }
    Spacer(Modifier.height(6.dp))
    if (onHero) {
        Pill(text, if (bad) Color(0xFFFFB3B0) else Color.White, Color.White.copy(alpha = 0.16f))
    } else {
        Pill(text, if (bad) MaterialTheme.colorScheme.onErrorContainer else MaterialTheme.colorScheme.onSecondaryContainer,
            if (bad) MaterialTheme.colorScheme.errorContainer else MaterialTheme.colorScheme.secondaryContainer)
    }
}

@Composable
private fun SigCard(sig: SigResult?) {
    val (icon, text, detail, bad) = when (sig) {
        SigResult.Ok -> listOf(Icons.Filled.Verified, stringResource(R.string.sig_ok), null, false)
        is SigResult.ChainNotTrusted -> listOf(Icons.Filled.Warning, stringResource(R.string.sig_chain), sig.detail, false)
        is SigResult.Invalid -> listOf(Icons.Filled.Error, stringResource(R.string.sig_bad), sig.detail, true)
        null -> return
    }
    val container = if (bad == true) MaterialTheme.colorScheme.errorContainer else MaterialTheme.colorScheme.secondaryContainer
    val content = if (bad == true) MaterialTheme.colorScheme.onErrorContainer else MaterialTheme.colorScheme.onSecondaryContainer
    Card(Modifier.fillMaxWidth(), colors = CardDefaults.cardColors(containerColor = container), shape = RoundedCornerShape(20.dp)) {
        Row(Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(icon as androidx.compose.ui.graphics.vector.ImageVector, null, tint = content)
            Spacer(Modifier.width(12.dp))
            Column {
                Text(text as String, color = content, style = MaterialTheme.typography.titleSmall)
                if (detail != null) Text(detail as String, color = content, style = MaterialTheme.typography.bodySmall)
            }
        }
    }
}

@Composable
private fun Section(title: Int, rows: List<Triple<Int, String, Boolean>>, show: Boolean) {
    val shown = rows.filter { it.second.isNotBlank() }
    if (shown.isEmpty()) return
    val clipboard = LocalClipboardManager.current
    Column {
        Text(stringResource(title), Modifier.padding(start = 16.dp, bottom = 4.dp),
            style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.primary)
        ElevatedCard(Modifier.fillMaxWidth(), shape = RoundedCornerShape(24.dp)) {
            shown.forEachIndexed { i, (label, value, sensitive) ->
                ListItem(
                    modifier = Modifier.clickable { clipboard.setText(AnnotatedString(value)) },
                    headlineContent = { Text(if (sensitive && !show) "••••••••••" else value) },
                    supportingContent = { Text(stringResource(label)) },
                    colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                )
                if (i < shown.lastIndex) HorizontalDivider(Modifier.padding(horizontal = 16.dp))
            }
        }
    }
}

// ---------------------------------------------------------------- token tab

@Composable
fun TokenScreen(vm: CardViewModel) {
    val token by vm.token.collectAsStateWithLifecycle()
    val ctx = LocalContext.current
    var dialog by remember { mutableStateOf<String?>(null) }          // "change" | "unblock" | "sign"
    var signSrc by remember { mutableStateOf<Uri?>(null) }
    var signPin by remember { mutableStateOf<String?>(null) }
    var exportCert by remember { mutableStateOf<TokenCert?>(null) }

    val pickFile = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) { signSrc = uri; dialog = "sign" }
    }
    val saveSig = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/pkcs7-signature")) { out ->
        val src = signSrc; val pin = signPin
        signSrc = null; signPin = null
        if (out != null && src != null && pin != null) {
            val data = ctx.contentResolver.openInputStream(src)?.use { it.readBytes() }
            if (data != null) vm.signFile(data, pin, out, ctx)
        }
    }
    val euReady by vm.euReady.collectAsStateWithLifecycle()
    LaunchedEffect(euReady) {
        if (euReady) { vm.consumeEuReady(); ctx.startActivity(Intent(ctx, EuLoginActivity::class.java)) }
    }
    val saveCert = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/x-x509-ca-cert")) { out ->
        val c = exportCert; exportCert = null
        if (out != null && c != null) ctx.contentResolver.openOutputStream(out)?.use { it.write(c.der) }
    }

    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(16.dp, 8.dp, 16.dp, 24.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        item {
            Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                val failed by vm.failed.collectAsStateWithLifecycle()
                val phase by vm.phase.collectAsStateWithLifecycle()
                Mascot(when {
                    phase != Phase.Idle -> R.drawable.mascot_key_look
                    failed -> R.drawable.mascot_key_worry
                    token != null -> R.drawable.mascot_key_thumbs
                    else -> R.drawable.mascot_key_present
                }, 144.dp)
            }
        }
        item {
            Button(onClick = { vm.readToken(ctx) }, Modifier.fillMaxWidth().height(56.dp)) {
                Icon(Icons.Filled.Key, null); Spacer(Modifier.width(8.dp)); Text(stringResource(R.string.read_token))
            }
        }
        val t = token
        if (t == null) {
            item { Text(stringResource(R.string.token_hint), color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth()) }
        } else {
            item {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Filled.Key, null, tint = MaterialTheme.colorScheme.primary)
                    Spacer(Modifier.width(8.dp))
                    Text(t.label, style = MaterialTheme.typography.titleMedium)
                    Spacer(Modifier.width(8.dp))
                    Text(t.serial, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            items(t.certs.size) { i -> CertCard(t.certs[i]) { exportCert = it; saveCert.launch("certificate.cer") } }
            item {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedButton({ dialog = "change" }, Modifier.fillMaxWidth()) { Icon(Icons.Filled.LockReset, null); Spacer(Modifier.width(8.dp)); Text(stringResource(R.string.change_pin)) }
                    OutlinedButton({ dialog = "unblock" }, Modifier.fillMaxWidth()) { Icon(Icons.Filled.LockOpen, null); Spacer(Modifier.width(8.dp)); Text(stringResource(R.string.unblock_pin)) }
                    FilledTonalButton({ pickFile.launch(arrayOf("*/*")) }, Modifier.fillMaxWidth()) { Icon(Icons.Filled.Draw, null); Spacer(Modifier.width(8.dp)); Text(stringResource(R.string.sign_file)) }
                }
            }
        }
        // eUprava sign-in: reads the certificates (no PIN), then opens the in-app sign-in screen
        item {
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Button({ vm.prepareEuprava(ctx) }, Modifier.fillMaxWidth().height(56.dp)) {
                    Icon(Icons.Filled.Login, null); Spacer(Modifier.width(8.dp)); Text(stringResource(R.string.eu_login))
                }
                Text(stringResource(R.string.eu_login_note), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }

    when (dialog) {
        "change" -> PinSteps(stringResource(R.string.change_pin), R.string.step1_pin, R.string.pin_current, true,
            onDismiss = { dialog = null }) { v -> dialog = null; vm.changePin(v[0], v[1], ctx) }
        "unblock" -> PinSteps(stringResource(R.string.unblock_pin), R.string.step1_puk, R.string.puk, true,
            onDismiss = { dialog = null }) { v -> dialog = null; vm.unblockPin(v[0], v[1], ctx) }
        "sign" -> PinSteps(stringResource(R.string.sign_file), R.string.step_sign_pin, R.string.pin_current, false,
            onDismiss = { dialog = null; signSrc = null }) { v ->
            dialog = null; signPin = v[0]
            saveSig.launch((signSrc?.lastPathSegment?.substringAfterLast('/') ?: "file") + ".p7s")
        }
    }
}

@Composable
private fun CertCard(cert: TokenCert, onExport: (TokenCert) -> Unit) {
    val info by produceState<Triple<String, String, Pair<String, String>?>?>(null, cert) {
        value = withContext(Dispatchers.Default) {
            runCatching {
                val x = CardCrypto.parseCert(cert.der)
                val df = SimpleDateFormat("dd.MM.yyyy", Locale.US)
                val cn = { n: String -> Regex("CN=([^,]+)").find(n)?.groupValues?.get(1) ?: n }
                val chain = CardCrypto.chains(x)
                Triple(cn(x.subjectX500Principal.name), cn(x.issuerX500Principal.name), Pair("${df.format(x.notBefore)} – ${df.format(x.notAfter)}", chain ?: ""))
            }.getOrNull()
        }
    }
    ElevatedCard(Modifier.fillMaxWidth(), shape = RoundedCornerShape(24.dp)) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(cert.label.ifBlank { info?.first ?: "" }, style = MaterialTheme.typography.titleMedium)
            info?.let { (subject, issuer, rest) ->
                Text("${stringResource(R.string.cert_issuer)}: $issuer", color = MaterialTheme.colorScheme.onSurfaceVariant)
                rest?.let { (valid, chainErr) ->
                    Text(stringResource(R.string.cert_valid, valid), color = MaterialTheme.colorScheme.onSurfaceVariant)
                    if (chainErr.isEmpty()) Pill(stringResource(R.string.chain_ok), MaterialTheme.colorScheme.onSecondaryContainer, MaterialTheme.colorScheme.secondaryContainer)
                    else Pill(stringResource(R.string.sig_chain), MaterialTheme.colorScheme.onErrorContainer, MaterialTheme.colorScheme.errorContainer)
                }
                if (subject.isBlank()) Spacer(Modifier.height(0.dp))
            }
            if (cert.der.isNotEmpty()) TextButton(onClick = { onExport(cert) }) { Text(stringResource(R.string.export_cert)) }
        }
    }
}

/** One question per dialog (current PIN/PUK, new PIN, repeat) so it is always clear which PIN is being asked for. */
@Composable
private fun PinSteps(title: String, firstMsg: Int, firstLabel: Int, withNew: Boolean, onDismiss: () -> Unit, onDone: (List<String>) -> Unit) {
    var step by remember { mutableIntStateOf(0) }
    val values = remember { mutableStateListOf<String>() }
    var text by remember(step) { mutableStateOf("") }
    val last = if (withNew) 2 else 0
    val message = when (step) { 0 -> firstMsg; 1 -> R.string.step2_new; else -> R.string.step3_confirm }
    val label = when (step) { 0 -> firstLabel; 1 -> R.string.pin_new; else -> R.string.pin_repeat }
    val mismatch = stringResource(R.string.pin_mismatch)
    var error by remember(step) { mutableStateOf<String?>(null) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(stringResource(message))
                if (step == 0) Text(stringResource(R.string.pin_warn), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                OutlinedTextField(
                    value = text, onValueChange = { if (it.length <= 8 && it.all(Char::isDigit)) text = it },
                    label = { Text(stringResource(label)) }, singleLine = true, isError = error != null,
                    supportingText = { error?.let { Text(it) } },
                    visualTransformation = PasswordVisualTransformation(),
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword),
                )
            }
        },
        confirmButton = {
            TextButton(enabled = text.length >= 4, onClick = {
                if (step == 2 && text != values[1]) { error = mismatch; return@TextButton }
                values.add(text)
                if (step == last) onDone(values.toList()) else step++
            }) { Text(stringResource(R.string.ok)) }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) } },
    )
}

// ---------------------------------------------------------------- settings tab

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(vm: CardViewModel) {
    val theme by vm.theme.collectAsStateWithLifecycle()
    val dynamic by vm.dynamic.collectAsStateWithLifecycle()
    val mask by vm.mask.collectAsStateWithLifecycle()
    val autoRead by vm.autoRead.collectAsStateWithLifecycle()
    val printJmbg by vm.printJmbg.collectAsStateWithLifecycle()
    val demo by vm.demo.collectAsStateWithLifecycle()
    val ctx = LocalContext.current
    val version = remember { runCatching { ctx.packageManager.getPackageInfo(ctx.packageName, 0).versionName }.getOrNull() ?: "" }
    val diagUnlocked by vm.diagUnlocked.collectAsStateWithLifecycle()
    val diagLog by vm.diagLog.collectAsStateWithLifecycle()
    val clipboard = LocalClipboardManager.current
    var versionTaps by remember { mutableStateOf(0) }
    val transparent = ListItemDefaults.colors(containerColor = Color.Transparent)
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(16.dp, 8.dp, 16.dp, 24.dp), verticalArrangement = Arrangement.spacedBy(20.dp)) {
        item {
            SettingsGroup(R.string.group_appearance) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                    Text(stringResource(R.string.settings_theme), style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                        listOf(R.string.theme_system, R.string.theme_light, R.string.theme_dark).forEachIndexed { i, r ->
                            SegmentedButton(selected = theme == i, onClick = { vm.setTheme(i) },
                                shape = SegmentedButtonDefaults.itemShape(i, 3)) { Text(stringResource(r), maxLines = 1) }
                        }
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        Text(stringResource(R.string.settings_palette), style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                            listOf(R.string.palette_flag, R.string.palette_wallpaper).forEachIndexed { i, r ->
                                SegmentedButton(selected = dynamic == (i == 1), onClick = { vm.setDynamic(i == 1) },
                                    shape = SegmentedButtonDefaults.itemShape(i, 2)) { Text(stringResource(r), maxLines = 1) }
                            }
                        }
                    }
                }
                HorizontalDivider(Modifier.padding(horizontal = 16.dp))
                var pickLanguage by remember { mutableStateOf(false) }
                val chosen = remember { AppLocale.saved(ctx) }
                ListItem(modifier = Modifier.clickable { pickLanguage = true }, colors = transparent,
                    leadingContent = { Icon(Icons.Filled.Language, null) },
                    headlineContent = { Text(stringResource(R.string.settings_language)) },
                    supportingContent = { Text(if (chosen == null) stringResource(R.string.language_system) else AppLocale.label(chosen)) })
                if (pickLanguage) LanguageDialog(chosen, onDismiss = { pickLanguage = false }) { tag ->
                    pickLanguage = false
                    if (tag != chosen) { AppLocale.save(ctx, tag); ctx.findActivity()?.recreate() }
                }
            }
        }
        item {
            SettingsGroup(R.string.group_privacy) {
                ListItem(colors = transparent, headlineContent = { Text(stringResource(R.string.settings_mask)) },
                    supportingContent = { Text(stringResource(R.string.settings_mask_hint)) },
                    trailingContent = { Switch(mask, { vm.setMask(it) }) })
                HorizontalDivider(Modifier.padding(horizontal = 16.dp))
                ListItem(colors = transparent, headlineContent = { Text(stringResource(R.string.settings_print_jmbg)) },
                    supportingContent = { Text(stringResource(R.string.settings_print_jmbg_hint)) },
                    trailingContent = { Switch(printJmbg, { vm.setPrintJmbg(it) }) })
            }
        }
        item {
            SettingsGroup(R.string.group_reading) {
                ListItem(colors = transparent, headlineContent = { Text(stringResource(R.string.settings_auto_read)) },
                    supportingContent = { Text(stringResource(R.string.settings_auto_read_hint)) },
                    trailingContent = { Switch(autoRead, { vm.setAutoRead(it) }) })
                HorizontalDivider(Modifier.padding(horizontal = 16.dp))
                ListItem(colors = transparent, headlineContent = { Text(stringResource(R.string.demo_data)) },
                    supportingContent = { Text(stringResource(R.string.demo_hint)) },
                    trailingContent = { Switch(demo, { vm.setDemo(it) }) })
            }
        }
        item {
            SettingsGroup(R.string.group_help) {
                ListItem(modifier = Modifier.clickable { openUrl(ctx, changelogUrl(ctx)) }, colors = transparent,
                    leadingContent = { Icon(Icons.Filled.NewReleases, null) }, headlineContent = { Text(stringResource(R.string.whats_new)) })
                HorizontalDivider(Modifier.padding(horizontal = 16.dp))
                ListItem(modifier = Modifier.clickable { openUrl(ctx, FEEDBACK_URL) }, colors = transparent,
                    leadingContent = { Icon(Icons.Filled.BugReport, null) }, headlineContent = { Text(stringResource(R.string.report_bug)) })
                HorizontalDivider(Modifier.padding(horizontal = 16.dp))
                ListItem(modifier = Modifier.clickable {
                    val cm = ctx.getSystemService(Context.CLIPBOARD_SERVICE) as android.content.ClipboardManager
                    cm.setPrimaryClip(android.content.ClipData.newPlainText("Super Čelik", DiagLog.report(version, "")))
                    android.widget.Toast.makeText(ctx, ctx.getString(R.string.logs_copied), android.widget.Toast.LENGTH_SHORT).show()
                }, colors = transparent, leadingContent = { Icon(Icons.Filled.ContentCopy, null) },
                    headlineContent = { Text(stringResource(R.string.copy_logs)) },
                    supportingContent = { Text(stringResource(R.string.copy_logs_hint)) })
            }
        }
        if (diagUnlocked) item {
            // hidden card diagnostics: structure of the card, no personal data, no PIN
            SettingsGroup(R.string.diag_title) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(stringResource(R.string.diag_text), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        FilledTonalButton(onClick = { vm.runDiagnostics(ctx) }) { Text(stringResource(R.string.diag_run)) }
                        OutlinedButton(enabled = diagLog != null, onClick = {
                            clipboard.setText(AnnotatedString(diagLog ?: ""))
                            vm.notify(Msg(R.string.diag_copied, error = false))
                        }) { Text(stringResource(R.string.diag_copy)) }
                    }
                    diagLog?.let {
                        Text(it, style = MaterialTheme.typography.bodySmall.copy(fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace, fontSize = 10.sp),
                            modifier = Modifier.fillMaxWidth().heightIn(max = 320.dp).verticalScroll(rememberScrollState()))
                    }
                }
            }
        }
        item {
            Column(Modifier.fillMaxWidth().padding(horizontal = 8.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text("${stringResource(R.string.app_name)} $version", style = MaterialTheme.typography.titleMedium,
                    modifier = Modifier.clickable { versionTaps++; if (versionTaps >= 5) vm.unlockDiag() })
                Text(stringResource(R.string.about_note), style = MaterialTheme.typography.bodySmall, textAlign = TextAlign.Center,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

/** The language of the app: the system language or one of ours, each with its flag. The change applies at once (the activity restarts). */
@Composable
private fun LanguageDialog(current: String?, onDismiss: () -> Unit, onPick: (String?) -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.settings_language)) },
        text = {
            LazyColumn {
                items((listOf<String?>(null) + AppLocale.order)) { tag ->
                    Row(Modifier.fillMaxWidth().clickable { onPick(tag) }.padding(vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                        RadioButton(selected = tag == current, onClick = { onPick(tag) })
                        Spacer(Modifier.width(8.dp))
                        Text(if (tag == null) stringResource(R.string.language_system) else AppLocale.label(tag))
                    }
                }
            }
        },
        confirmButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) } },
    )
}

/** A titled group of settings in one card, the same look as the cards of the other screens. */
@Composable
private fun SettingsGroup(@androidx.annotation.StringRes title: Int, content: @Composable ColumnScope.() -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(stringResource(title), Modifier.padding(start = 8.dp), style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.primary)
        ElevatedCard(Modifier.fillMaxWidth(), shape = RoundedCornerShape(24.dp)) { Column(content = content) }
    }
}
