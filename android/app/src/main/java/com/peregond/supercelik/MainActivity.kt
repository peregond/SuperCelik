package com.peregond.supercelik

import android.content.Intent
import android.hardware.usb.UsbManager
import android.nfc.NfcAdapter
import android.os.Bundle
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material.icons.filled.Key
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material.icons.outlined.Badge
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.res.stringResource
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
        if (intent.getBooleanExtra("demo", false)) { vm.demoOpenPdf = intent.getBooleanExtra("pdf", false); vm.showDemo() }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        // Personal data must not end up in screenshots or the recent-apps preview (demo mode excepted).
        val demo = intent?.getBooleanExtra("demo", false) == true
        if (!demo) window.setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE)
        nfc = NfcAdapter.getDefaultAdapter(this)

        // NFC reader mode is on only while we are waiting for a card and the app is visible.
        lifecycleScope.launch {
            repeatOnLifecycle(Lifecycle.State.STARTED) {
                vm.phase.collect { p ->
                    val adapter = nfc ?: return@collect
                    if (vm.listensNfc(p)) {
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
        if (demo) { vm.demoOpenPdf = intent?.getBooleanExtra("pdf", false) == true; vm.showDemo() }

        setContent {
            val theme by vm.theme.collectAsStateWithLifecycle()
            val dynamic by vm.dynamic.collectAsStateWithLifecycle()
            val dark = when (theme) { 1 -> false; 2 -> true; else -> isSystemInDarkTheme() }
            SuperCelikTheme(dark, wallpaper = dynamic) { Root(vm, nfc, intent?.getStringExtra("tab")) }
        }
    }
}

private enum class Tab { Card, Token, Settings }

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun Root(vm: CardViewModel, nfc: NfcAdapter?, initialTab: String?) {
    val phase by vm.phase.collectAsStateWithLifecycle()
    val personal by vm.personal.collectAsStateWithLifecycle()
    val message by vm.message.collectAsStateWithLifecycle()
    var tab by rememberSaveable { mutableStateOf(when (initialTab) { "token" -> Tab.Token; "settings" -> Tab.Settings; else -> Tab.Card }) }
    var reveal by rememberSaveable { mutableStateOf(false) }
    val snackbar = remember { SnackbarHostState() }
    val haptic = LocalHapticFeedback.current

    val msg = message
    val text = msg?.let { msgText(it) }
    LaunchedEffect(msg) {
        if (msg != null && text != null) { snackbar.showSnackbar(text); vm.consumeMessage() }
    }
    LaunchedEffect(personal != null) {
        if (personal != null) { haptic.performHapticFeedback(HapticFeedbackType.LongPress); reveal = false }
    }

    Scaffold(
        topBar = {
            Column {
            CenterAlignedTopAppBar(
                title = { Text(stringResource(R.string.app_name)) },
                actions = {
                    if (tab == Tab.Card && personal != null) {
                        IconButton({ reveal = !reveal }) {
                            Icon(if (reveal) Icons.Filled.VisibilityOff else Icons.Filled.Visibility, stringResource(R.string.show_all))
                        }
                        IconButton({ vm.clear() }) { Icon(Icons.Filled.Clear, stringResource(R.string.clear)) }
                    }
                },
            )
            FlagStripe()
            }
        },
        bottomBar = {
            NavigationBar {
                NavigationBarItem(tab == Tab.Card, { tab = Tab.Card }, { Icon(Icons.Outlined.Badge, null) }, label = { Text(stringResource(R.string.tab_card)) })
                NavigationBarItem(tab == Tab.Token, { tab = Tab.Token }, { Icon(Icons.Filled.Key, null) }, label = { Text(stringResource(R.string.tab_token)) })
                NavigationBarItem(tab == Tab.Settings, { tab = Tab.Settings }, { Icon(Icons.Filled.Settings, null) }, label = { Text(stringResource(R.string.tab_settings)) })
            }
        },
        snackbarHost = { SnackbarHost(snackbar) },
    ) { padding ->
        Box(Modifier.padding(padding).fillMaxSize()) {
            AnimatedContent(tab, transitionSpec = { (fadeIn() + scaleIn(initialScale = 0.98f)) togetherWith fadeOut() }, label = "tab") { t ->
                when (t) {
                    Tab.Card -> CardScreen(vm, nfc, reveal)
                    Tab.Token -> TokenScreen(vm, nfc)
                    Tab.Settings -> SettingsScreen(vm)
                }
            }
            // Explicit operations (token, PIN, signing) and reading show a full-screen "hold the card" overlay.
            if (phase == Phase.Reading || phase == Phase.WaitingNfc || phase == Phase.WaitingUsb) WaitingOverlay(phase) { vm.cancel() }
        }
    }
}
