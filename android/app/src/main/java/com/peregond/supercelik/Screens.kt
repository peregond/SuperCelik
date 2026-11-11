package com.peregond.supercelik

import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.net.Uri
import android.nfc.NfcAdapter
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
import androidx.compose.foundation.lazy.LazyColumn
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
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
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

@Composable
private fun PulsingNfc() {
    val t = rememberInfiniteTransition(label = "pulse")
    val scale by t.animateFloat(1f, 1.25f, infiniteRepeatable(tween(1400, easing = FastOutSlowInEasing), RepeatMode.Reverse), label = "scale")
    val alpha by t.animateFloat(0.25f, 0.05f, infiniteRepeatable(tween(1400, easing = FastOutSlowInEasing), RepeatMode.Reverse), label = "alpha")
    Box(Modifier.size(144.dp), contentAlignment = Alignment.Center) {
        Box(Modifier.size(112.dp).scale(scale).background(MaterialTheme.colorScheme.primary.copy(alpha = alpha), CircleShape))
        Box(Modifier.size(96.dp).background(MaterialTheme.colorScheme.primaryContainer, CircleShape), contentAlignment = Alignment.Center) {
            Icon(Icons.Filled.Nfc, null, Modifier.size(48.dp), tint = MaterialTheme.colorScheme.onPrimaryContainer)
        }
    }
}

/** Full-screen "hold the card / reading" overlay for an explicit card operation. */
@Composable
fun WaitingOverlay(phase: Phase, onCancel: () -> Unit) {
    val text = when (phase) {
        Phase.WaitingUsb -> R.string.hint_usb_wait
        Phase.Reading -> R.string.reading
        else -> R.string.hint_nfc_wait
    }
    Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.surface.copy(alpha = 0.97f)) {
        Column(Modifier.fillMaxSize().padding(24.dp), Arrangement.Center, Alignment.CenterHorizontally) {
            if (phase == Phase.Reading || phase == Phase.WaitingUsb) CircularProgressIndicator() else PulsingNfc()
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

@Composable
fun CardScreen(vm: CardViewModel, nfc: NfcAdapter?, reveal: Boolean) {
    val personal by vm.personal.collectAsStateWithLifecycle()
    val ctx = LocalContext.current
    val p = personal
    if (p == null) {
        Column(
            Modifier.fillMaxSize().padding(24.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp, Alignment.CenterVertically),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            PulsingNfc()
            Text(stringResource(R.string.hint_ready), textAlign = TextAlign.Center, style = MaterialTheme.typography.titleMedium)
            Text(stringResource(R.string.hint_idle), textAlign = TextAlign.Center, style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
            FilledTonalButton(onClick = { vm.startUsb(ctx) }, Modifier.fillMaxWidth().height(56.dp)) {
                Icon(Icons.Filled.Usb, null); Spacer(Modifier.width(8.dp)); Text(stringResource(R.string.read_usb))
            }
            Text(stringResource(R.string.about_note), textAlign = TextAlign.Center,
                style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        return
    }
    PersonalResult(vm, p, reveal)
}

@Composable
private fun PersonalResult(vm: CardViewModel, p: PersonalData, revealAll: Boolean) {
    val sig by vm.sig.collectAsStateWithLifecycle()
    val mask by vm.mask.collectAsStateWithLifecycle()
    val ctx = LocalContext.current
    val clipboard = LocalClipboardManager.current
    val bitmap = remember(p.portrait) { p.portrait?.let { BitmapFactory.decodeByteArray(it, 0, it.size)?.asImageBitmap() } }
    val show = revealAll || !mask
    val flagPalette = LocalFlagPalette.current
    val heroBg = if (flagPalette) Flag.Blue else MaterialTheme.colorScheme.primaryContainer
    val heroFg = if (flagPalette) Color.White else MaterialTheme.colorScheme.onPrimaryContainer
    var photoOpen by remember { mutableStateOf(false) }
    var pdfFile by remember { mutableStateOf<File?>(null) }
    LaunchedEffect(Unit) { if (vm.demoOpenPdf) { vm.demoOpenPdf = false; pdfFile = Pdf.create(ctx, p, allRowsForPdf(ctx, p), ctx.getString(R.string.app_name)) } }

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
    val pdfTitle = stringResource(R.string.app_name)
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
                FilledTonalButton(onClick = { pdfFile = Pdf.create(ctx, p, allRows, pdfTitle) }, Modifier.weight(1f)) {
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

private fun allRowsForPdf(ctx: Context, p: PersonalData): List<Pair<String, String>> = listOf(
    R.string.surname to p.surname, R.string.given_name to p.givenName, R.string.parent_name to p.parentGivenName,
    R.string.dob to p.dateOfBirth, R.string.place_of_birth to p.placeOfBirth.ifBlank { p.stateOfBirth }, R.string.sex to p.sex,
    R.string.nationality to p.nationality, R.string.jmbg to p.personalNumber, R.string.doc_number to p.docRegNo,
    R.string.issued_by to p.issuingAuthority, R.string.issue_date to p.issuingDate, R.string.expiry_date to p.expiryDate,
    R.string.address to p.address).map { (k, v) -> ctx.getString(k) to v }

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

private fun sharePdf(ctx: Context, p: PersonalData, rows: List<Pair<String, String>>, title: String) {
    val f = Pdf.create(ctx, p, rows, title)
    val uri = FileProvider.getUriForFile(ctx, "${ctx.packageName}.files", f)
    ctx.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).apply {
        type = "application/pdf"; putExtra(Intent.EXTRA_STREAM, uri); addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }, null))
}

// ---------------------------------------------------------------- token tab

@Composable
fun TokenScreen(vm: CardViewModel, nfc: NfcAdapter?) {
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
            if (data != null) vm.signFile(data, pin, out, nfc, ctx)
        }
    }
    val saveCert = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/x-x509-ca-cert")) { out ->
        val c = exportCert; exportCert = null
        if (out != null && c != null) ctx.contentResolver.openOutputStream(out)?.use { it.write(c.der) }
    }

    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(16.dp, 8.dp, 16.dp, 24.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        item {
            Button(onClick = { vm.readToken(nfc, ctx) }, Modifier.fillMaxWidth().height(56.dp)) {
                Icon(Icons.Filled.Key, null); Spacer(Modifier.width(8.dp)); Text(stringResource(R.string.read_token))
            }
        }
        val t = token
        if (t == null) {
            item { Text(stringResource(R.string.token_hint), color = MaterialTheme.colorScheme.onSurfaceVariant) }
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
        item { Text(stringResource(R.string.pin_note), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
    }

    when (dialog) {
        "change" -> PinSteps(stringResource(R.string.change_pin), R.string.step1_pin, R.string.pin_current, true,
            onDismiss = { dialog = null }) { v -> dialog = null; vm.changePin(v[0], v[1], nfc, ctx) }
        "unblock" -> PinSteps(stringResource(R.string.unblock_pin), R.string.step1_puk, R.string.puk, true,
            onDismiss = { dialog = null }) { v -> dialog = null; vm.unblockPin(v[0], v[1], nfc, ctx) }
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
    val autoClear by vm.autoClear.collectAsStateWithLifecycle()
    val ctx = LocalContext.current
    val version = remember { runCatching { ctx.packageManager.getPackageInfo(ctx.packageName, 0).versionName }.getOrNull() ?: "" }
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        item {
            Text(stringResource(R.string.settings_theme), style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.primary)
            Spacer(Modifier.height(8.dp))
            SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                listOf(R.string.theme_system, R.string.theme_light, R.string.theme_dark).forEachIndexed { i, r ->
                    SegmentedButton(selected = theme == i, onClick = { vm.setTheme(i) },
                        shape = SegmentedButtonDefaults.itemShape(i, 3)) { Text(stringResource(r)) }
                }
            }
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) item {
            Text(stringResource(R.string.settings_palette), style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.primary)
            Spacer(Modifier.height(8.dp))
            SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                listOf(R.string.palette_flag, R.string.palette_wallpaper).forEachIndexed { i, r ->
                    SegmentedButton(selected = dynamic == (i == 1), onClick = { vm.setDynamic(i == 1) },
                        shape = SegmentedButtonDefaults.itemShape(i, 2)) { Text(stringResource(r)) }
                }
            }
        }
        item {
            ListItem(headlineContent = { Text(stringResource(R.string.settings_mask)) },
                supportingContent = { Text(stringResource(R.string.settings_mask_hint)) },
                trailingContent = { Switch(mask, { vm.setMask(it) }) })
        }
        item {
            Text(stringResource(R.string.settings_autoclear), style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.primary)
            Spacer(Modifier.height(8.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                listOf(0, 1, 5, 15).forEach { m ->
                    FilterChip(selected = autoClear == m, onClick = { vm.setAutoClear(m) },
                        label = { Text(if (m == 0) stringResource(R.string.minutes_off) else stringResource(R.string.minutes_n, m)) })
                }
            }
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) item {
            ListItem(modifier = Modifier.clickable {
                ctx.startActivity(Intent(android.provider.Settings.ACTION_APP_LOCALE_SETTINGS, Uri.parse("package:${ctx.packageName}")))
            }, headlineContent = { Text(stringResource(R.string.settings_language)) },
                supportingContent = { Text(stringResource(R.string.settings_language_hint)) })
        }
        item {
            HorizontalDivider()
            Spacer(Modifier.height(12.dp))
            Text("${stringResource(R.string.app_name)} $version", style = MaterialTheme.typography.titleMedium)
            Spacer(Modifier.height(4.dp))
            Text(stringResource(R.string.about_note), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}
