package com.peregond.supercelik

import android.content.Intent
import android.graphics.BitmapFactory
import android.hardware.usb.UsbManager
import android.view.WindowManager
import android.nfc.NfcAdapter
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.ui.draw.scale
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material.icons.filled.Nfc
import androidx.compose.material.icons.filled.Usb
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {
    private val vm: CardViewModel by viewModels()
    private var nfc: NfcAdapter? = null

    override fun onStart() {
        super.onStart()
        vm.autoStart(this)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.action == UsbManager.ACTION_USB_DEVICE_ATTACHED) vm.startUsb(this)
        if (intent.getBooleanExtra("demo", false)) vm.showDemo()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        // Personal data must not end up in screenshots or the recent-apps preview.
        val demo = intent?.getBooleanExtra("demo", false) == true
        if (!demo) window.setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE)
        nfc = NfcAdapter.getDefaultAdapter(this)

        // NFC reader mode is on only while we are waiting for a card and the app is visible.
        lifecycleScope.launch {
            repeatOnLifecycle(Lifecycle.State.STARTED) {
                vm.state.collect { s ->
                    val adapter = nfc ?: return@collect
                    if (vm.listensNfc(s)) {
                        adapter.enableReaderMode(
                            this@MainActivity, { tag -> vm.onTag(tag) },
                            NfcAdapter.FLAG_READER_NFC_A or NfcAdapter.FLAG_READER_NFC_B or NfcAdapter.FLAG_READER_SKIP_NDEF_CHECK,
                            null,
                        )
                    } else {
                        adapter.disableReaderMode(this@MainActivity)
                    }
                }
            }
        }

        // A USB reader being plugged in launches the app (see device_filter) and reads straight away.
        if (intent?.action == UsbManager.ACTION_USB_DEVICE_ATTACHED) vm.startUsb(this)
        if (demo) vm.showDemo()

        setContent {
            SuperCelikTheme {
                val state by vm.state.collectAsStateWithLifecycle()
                App(state, onNfc = { vm.startNfc(nfc) }, onUsb = { vm.startUsb(this@MainActivity) }, onReset = vm::reset)
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun App(state: UiState, onNfc: () -> Unit, onUsb: () -> Unit, onReset: () -> Unit) {
    val scroll = TopAppBarDefaults.exitUntilCollapsedScrollBehavior()
    Scaffold(
        modifier = Modifier.nestedScroll(scroll.nestedScrollConnection),
        topBar = {
            LargeTopAppBar(
                title = { Text(stringResource(R.string.app_name)) },
                scrollBehavior = scroll,
                colors = TopAppBarDefaults.largeTopAppBarColors(scrolledContainerColor = MaterialTheme.colorScheme.surfaceContainer),
            )
        },
        floatingActionButton = {
            if (state is UiState.Done) {
                ExtendedFloatingActionButton(onClick = onReset, icon = { Icon(Icons.Filled.Clear, null) },
                    text = { Text(stringResource(R.string.clear)) })
            }
        },
    ) { padding ->
        val haptic = LocalHapticFeedback.current
        LaunchedEffect(state is UiState.Done) {
            if (state is UiState.Done) haptic.performHapticFeedback(HapticFeedbackType.LongPress)
        }
        Box(Modifier.padding(padding).fillMaxSize()) {
            AnimatedContent(
                targetState = state,
                contentKey = { it::class },
                transitionSpec = { (fadeIn() + scaleIn(initialScale = 0.96f)) togetherWith fadeOut() },
                label = "state",
            ) { st ->
                when (st) {
                    UiState.Idle, UiState.WaitingNfc -> Start(onNfc, onUsb, null)
                    is UiState.Failed -> Start(onNfc, onUsb, errorText(st))
                    UiState.WaitingUsb -> Waiting(stringResource(R.string.hint_usb_wait), onReset)
                    UiState.Reading -> Waiting(stringResource(R.string.reading), null)
                    is UiState.Done -> PersonalResult(st.data)
                }
            }
        }
    }
}

@Composable
private fun errorText(f: UiState.Failed): String = when {
    f.detail == "nfc" || f.detail == "nfc_off" -> stringResource(R.string.err_no_nfc)
    f.detail == "no_usb" -> stringResource(R.string.err_no_usb)
    f.detail == "usb_denied" -> stringResource(R.string.err_usb_denied)
    f.error?.kind == CardException.Kind.NoCard -> stringResource(R.string.err_no_card)
    f.error?.kind == CardException.Kind.Unsupported -> stringResource(R.string.err_unsupported)
    f.error?.kind == CardException.Kind.Lost -> stringResource(R.string.err_lost)
    else -> stringResource(R.string.err_generic) + if (f.detail.isNotBlank()) ": ${f.detail}" else ""
}

@Composable
private fun Start(onNfc: () -> Unit, onUsb: () -> Unit, error: String?) {
    Column(
        Modifier.fillMaxSize().padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp, Alignment.CenterVertically),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        if (error != null) {
            Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.errorContainer)) {
                Text(error, Modifier.padding(16.dp), color = MaterialTheme.colorScheme.onErrorContainer)
            }
        }
        PulsingNfc()
        Text(stringResource(R.string.hint_ready), textAlign = TextAlign.Center, style = MaterialTheme.typography.titleMedium)
        Text(stringResource(R.string.hint_idle), textAlign = TextAlign.Center, style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant)
        FilledTonalButton(onClick = onUsb, Modifier.fillMaxWidth().height(56.dp)) {
            Icon(Icons.Filled.Usb, null); Spacer(Modifier.width(8.dp)); Text(stringResource(R.string.read_usb))
        }
        Text(stringResource(R.string.about_note), textAlign = TextAlign.Center,
            style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

/** The phone is already listening for an NFC card: a slow pulse shows that. */
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

@Composable
private fun Waiting(text: String, onCancel: (() -> Unit)?) {
    Column(Modifier.fillMaxSize().padding(24.dp), Arrangement.Center, Alignment.CenterHorizontally) {
        CircularProgressIndicator()
        Spacer(Modifier.height(24.dp))
        Text(text, textAlign = TextAlign.Center, style = MaterialTheme.typography.titleMedium)
        if (onCancel != null) {
            Spacer(Modifier.height(16.dp))
            TextButton(onClick = onCancel) { Text(stringResource(R.string.cancel)) }
        }
    }
}

@Composable
private fun PersonalResult(p: PersonalData) {
    val bitmap = remember(p.portrait) { p.portrait?.let { BitmapFactory.decodeByteArray(it, 0, it.size)?.asImageBitmap() } }
    LazyColumn(
        Modifier.fillMaxSize(),
        contentPadding = PaddingValues(16.dp, 8.dp, 16.dp, 96.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item {
            Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.primaryContainer),
                shape = RoundedCornerShape(28.dp)) {
                Row(Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
                    if (bitmap != null) {
                        Image(bitmap, null, Modifier.size(88.dp, 112.dp).clip(RoundedCornerShape(16.dp)), contentScale = ContentScale.Crop)
                        Spacer(Modifier.width(16.dp))
                    }
                    Column {
                        Text("${p.givenName} ${p.surname}", style = MaterialTheme.typography.titleLarge,
                            color = MaterialTheme.colorScheme.onPrimaryContainer)
                        Text(p.personalNumber, style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onPrimaryContainer)
                    }
                }
            }
        }
        item {
            Section(R.string.person_section, listOf(
                R.string.surname to p.surname, R.string.given_name to p.givenName, R.string.parent_name to p.parentGivenName,
                R.string.dob to p.dateOfBirth, R.string.place_of_birth to p.placeOfBirth, R.string.sex to p.sex,
                R.string.jmbg to p.personalNumber))
        }
        item {
            Section(R.string.doc_section, listOf(
                R.string.doc_number to p.docRegNo, R.string.issued_by to p.issuingAuthority,
                R.string.issue_date to p.issuingDate, R.string.expiry_date to p.expiryDate))
        }
        item { Section(R.string.address_section, listOf(R.string.address to p.address)) }
    }
}

@Composable
private fun Section(title: Int, rows: List<Pair<Int, String>>) {
    val shown = rows.filter { it.second.isNotBlank() }
    if (shown.isEmpty()) return
    Column {
        Text(stringResource(title), Modifier.padding(start = 16.dp, bottom = 4.dp),
            style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.primary)
        ElevatedCard(shape = RoundedCornerShape(24.dp)) {
            shown.forEachIndexed { i, (label, value) ->
                ListItem(
                    headlineContent = { Text(value) },
                    supportingContent = { Text(stringResource(label)) },
                    colors = ListItemDefaults.colors(containerColor = androidx.compose.ui.graphics.Color.Transparent),
                )
                if (i < shown.lastIndex) HorizontalDivider(Modifier.padding(horizontal = 16.dp))
            }
        }
    }
}
