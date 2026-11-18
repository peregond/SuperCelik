package com.peregond.supercelik

import android.annotation.SuppressLint
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.net.Uri
import android.os.Bundle
import android.view.WindowManager
import android.webkit.ClientCertRequest
import android.webkit.CookieManager
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebStorage
import android.webkit.WebView
import android.webkit.WebViewClient
import android.webkit.WebViewDatabase
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import java.security.cert.X509Certificate

/**
 * eUprava in an in-app WebView, with the card answering the TLS client certificate request (see EuLogin.kt).
 * Only *.gov.rs pages open here; any other link goes to the normal browser. Cookies, storage, cache and the
 * remembered certificate choice are wiped when the screen closes (and on the next start if the app was killed).
 */
class EuLoginActivity : ComponentActivity() {
    private var web: WebView? = null

    /** Several certificates fit the request: the user picks one (or cancels). */
    private val choice = mutableStateOf<Pair<ClientCertRequest, List<TokenKeyPair>>?>(null)
    /** Further certificate requests that arrive while the choice dialog is open: they get the same answer. */
    private val extraRequests = mutableListOf<ClientCertRequest>()
    private val loading = mutableStateOf(true)
    private val host = mutableStateOf("")

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // The certificates live only in memory: after the process was killed there is nothing to sign in with.
        if (EuLogin.pairs.isEmpty()) { finish(); return }
        window.setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE)
        enableEdgeToEdge()
        EuLogin.installProvider()
        EuLogin.startOver()
        val view = makeWebView()
        web = view
        wipeWebData(this, view)          // leftovers, in case the app was killed during an earlier sign-in
        EuLogin.markDirty(this, true)
        view.loadUrl(EuLogin.START_URL)

        val prefs = getSharedPreferences("settings", MODE_PRIVATE)
        setContent {
            val dark = when (prefs.getInt("theme", 0)) { 1 -> false; 2 -> true; else -> isSystemInDarkTheme() }
            SuperCelikTheme(dark, wallpaper = prefs.getBoolean("wallpaper", false)) {
                LoginScreen(view)
            }
        }
    }

    override fun onPause() {
        // leaving for good: the start screen must not start reading the card by itself when it comes back
        if (isFinishing) EuLogin.skipAutoStart = true
        super.onPause()
    }

    override fun onDestroy() {
        // answer pending certificate requests first (while the WebView still exists), then tear everything down
        choice.value?.first?.let { runCatching { it.cancel() } }
        extraRequests.forEach { runCatching { it.cancel() } }
        extraRequests.clear()
        choice.value = null
        EuLogin.reset()
        web?.let { w ->
            w.stopLoading()
            wipeWebData(this, w)
            w.destroy()
            EuLogin.markDirty(this, false)
        }
        web = null
        EuLogin.removeProvider()
        super.onDestroy()
    }

    @SuppressLint("SetJavaScriptEnabled")
    private fun makeWebView() = WebView(this).apply {
        settings.javaScriptEnabled = true          // the sign-in pages need it
        settings.domStorageEnabled = true
        settings.allowFileAccess = false
        settings.allowContentAccess = false
        settings.setGeolocationEnabled(false)
        settings.setSupportMultipleWindows(false)
        settings.javaScriptCanOpenWindowsAutomatically = false
        settings.mixedContentMode = android.webkit.WebSettings.MIXED_CONTENT_NEVER_ALLOW
        webChromeClient = WebChromeClient()
        webViewClient = Client()
    }

    private inner class Client : WebViewClient() {
        override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
            val url = request.url
            if (url.scheme == "https" && isGov(url.host)) return false
            // anything else leaves the app: ordinary web links open in the browser, other schemes (intent:, file:, ...) are dropped
            if (url.scheme == "https" || url.scheme == "http") {
                try { startActivity(Intent(Intent.ACTION_VIEW, url).addCategory(Intent.CATEGORY_BROWSABLE)) } catch (_: ActivityNotFoundException) { }
            }
            return true
        }

        override fun onPageStarted(view: WebView, url: String?, favicon: Bitmap?) {
            loading.value = true
            host.value = url?.let { Uri.parse(it).host } ?: ""
        }

        override fun onPageFinished(view: WebView, url: String?) { loading.value = false }

        override fun onReceivedClientCertRequest(view: WebView, request: ClientCertRequest) {
            // The card certificate goes only to the eID sign-in hosts, and never again after a failed attempt.
            if (!request.host.orEmpty().let { it == "eid.gov.rs" || it.endsWith(".eid.gov.rs") } || EuLogin.stopped) {
                request.cancel(); return
            }
            val all = EuLogin.pairs
            val issuers = request.principals?.map { it.name }?.toSet()
            val fit = all.filter { p ->
                issuers == null || runCatching { CardCrypto.parseCert(p.certDer).issuerX500Principal.name in issuers }.getOrDefault(false)
            }.ifEmpty { all }
            when {
                choice.value != null -> extraRequests.add(request)          // the choice dialog is already open
                fit.size == 1 -> useCert(request, fit[0])
                else -> choice.value = request to fit
            }
        }
    }

    /** Asks for the PIN and verifies it on the card now (not during the TLS handshake), then hands the key to Chromium. */
    private fun useCert(request: ClientCertRequest, pair: TokenKeyPair) {
        EuLogin.unlock(pair) { ok ->
            if (!ok) { runCatching { request.cancel() } } else proceed(request, pair)
        }
    }

    private fun proceed(request: ClientCertRequest, pair: TokenKeyPair) {
        try {
            val leaf = CardCrypto.parseCert(pair.certDer)
            val chain = listOfNotNull(leaf, CardCrypto.issuerOf(leaf)).toTypedArray<X509Certificate>()
            request.proceed(CardPrivateKey(pair), chain)
        } catch (e: Exception) {
            request.cancel()
            EuLogin.stop(Msg(R.string.err_generic, e.message))
        }
    }

    private fun startOver() {
        EuLogin.startOver()
        WebView.clearClientCertPreferences(null)
        web?.loadUrl(EuLogin.START_URL)
    }

    @OptIn(ExperimentalMaterial3Api::class)
    @Composable
    private fun LoginScreen(view: WebView) {
        val status by EuLogin.status.collectAsStateWithLifecycle()
        val pinAsk by EuLogin.pinAsk.collectAsStateWithLifecycle()
        val isLoading by loading
        val pageHost by host
        BackHandler { if (view.canGoBack()) view.goBack() else finish() }

        Scaffold(topBar = {
            TopAppBar(
                navigationIcon = { IconButton({ finish() }) { Icon(Icons.Filled.Close, stringResource(R.string.eu_close)) } },
                title = {
                    Column {
                        Text("eUprava", maxLines = 1)
                        if (pageHost.isNotEmpty()) Row(verticalAlignment = Alignment.CenterVertically) {
                            Icon(Icons.Filled.Lock, null, Modifier.size(12.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                            Spacer(Modifier.width(4.dp))
                            Text(pageHost, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant,
                                maxLines = 1, overflow = TextOverflow.Ellipsis)
                        }
                    }
                },
                actions = { IconButton({ startOver() }) { Icon(Icons.Filled.Refresh, stringResource(R.string.eu_start_over)) } },
            )
        }) { padding ->
            Box(Modifier.padding(padding).fillMaxSize()) {
                AndroidView({ (view.parent as? android.view.ViewGroup)?.removeView(view); view }, Modifier.fillMaxSize())
                if (isLoading) LinearProgressIndicator(Modifier.fillMaxWidth().align(Alignment.TopCenter))

                if (status == EuLogin.Status.Signing) {
                    ElevatedCard(Modifier.align(Alignment.Center).padding(32.dp)) {
                        Row(Modifier.padding(24.dp), verticalAlignment = Alignment.CenterVertically) {
                            CircularProgressIndicator(Modifier.size(28.dp))
                            Spacer(Modifier.width(16.dp))
                            Text(stringResource(R.string.eu_signing))
                        }
                    }
                }
                (status as? EuLogin.Status.Failed)?.let { f ->
                    ElevatedCard(Modifier.align(Alignment.BottomCenter).padding(16.dp).fillMaxWidth(),
                        colors = CardDefaults.elevatedCardColors(containerColor = MaterialTheme.colorScheme.errorContainer)) {
                        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            Text(msgText(f.msg), color = MaterialTheme.colorScheme.onErrorContainer)
                            Text(stringResource(R.string.eu_failed_note), style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onErrorContainer)
                            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                Button({ startOver() }) { Text(stringResource(R.string.eu_start_over)) }
                                TextButton({ finish() }) { Text(stringResource(R.string.eu_close)) }
                            }
                        }
                    }
                }
            }
        }

        pinAsk?.let { PinDialog(it) }
        choice.value?.let { (request, pairs) ->
            CertChoice(pairs, onPick = { p ->
                choice.value = null
                useCert(request, p)
                extraRequests.toList().also { extraRequests.clear() }.forEach { useCert(it, p) }
            }, onCancel = {
                choice.value = null
                request.cancel()
                extraRequests.toList().also { extraRequests.clear() }.forEach { it.cancel() }
            })
        }
    }

    @Composable
    private fun PinDialog(ask: PinAsk) {
        var text by remember(ask) { mutableStateOf("") }
        val done = { pin: CharArray? -> text = ""; ask.finish(pin) }
        AlertDialog(
            onDismissRequest = { done(null) },
            title = { Text(stringResource(R.string.eu_pin_title)) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text(stringResource(R.string.eu_pin_msg, ask.label.ifBlank { "eID" }))
                    Text(stringResource(R.string.eu_pin_warn), style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                    OutlinedTextField(
                        value = text, onValueChange = { if (it.length <= 8 && it.all(Char::isDigit)) text = it },
                        label = { Text("PIN") }, singleLine = true,
                        visualTransformation = PasswordVisualTransformation(),
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword),
                    )
                }
            },
            confirmButton = { TextButton(enabled = text.length >= 4, onClick = { done(text.toCharArray()) }) { Text(stringResource(R.string.ok)) } },
            dismissButton = { TextButton(onClick = { done(null) }) { Text(stringResource(R.string.cancel)) } },
        )
    }

    @Composable
    private fun CertChoice(pairs: List<TokenKeyPair>, onPick: (TokenKeyPair) -> Unit, onCancel: () -> Unit) {
        AlertDialog(
            onDismissRequest = onCancel,
            title = { Text(stringResource(R.string.eu_choose_cert)) },
            text = {
                Column {
                    pairs.forEach { p ->
                        val name = p.label.ifBlank {
                            runCatching { CardCrypto.parseCert(p.certDer).subjectX500Principal.name }.getOrDefault("eID")
                        }
                        TextButton({ onPick(p) }, Modifier.fillMaxWidth()) { Text(name, Modifier.fillMaxWidth()) }
                    }
                }
            },
            confirmButton = {},
            dismissButton = { TextButton(onCancel) { Text(stringResource(R.string.cancel)) } },
        )
    }

    companion object {
        fun isGov(host: String?) = host != null && (host == "gov.rs" || host.endsWith(".gov.rs"))

        /** Cookies, web storage, HTTP cache, saved form / auth data and the remembered client certificate choice. */
        fun wipeWebData(context: Context, view: WebView?) {
            CookieManager.getInstance().removeAllCookies(null)
            CookieManager.getInstance().flush()
            WebStorage.getInstance().deleteAllData()
            WebView.clearClientCertPreferences(null)
            @Suppress("DEPRECATION") WebViewDatabase.getInstance(context).clearFormData()
            WebViewDatabase.getInstance(context).clearHttpAuthUsernamePassword()
            view?.clearCache(true)
            view?.clearHistory()
            view?.clearFormData()
        }

        /** The app was killed while signed in: wipe what the WebView left on disk (called on the next start). */
        fun wipeIfDirty(context: Context) {
            if (!EuLogin.isDirty(context)) return
            runCatching {
                val w = WebView(context)
                wipeWebData(context, w)
                w.destroy()
            }
            EuLogin.markDirty(context, false)
        }
    }
}
