package com.peregond.supercelik

import android.content.Context
import android.hardware.usb.UsbManager
import android.nfc.NfcAdapter
import android.nfc.Tag
import android.nfc.tech.IsoDep
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

sealed interface UiState {
    data object Idle : UiState
    data object WaitingNfc : UiState
    data object WaitingUsb : UiState
    data object Reading : UiState
    data class Done(val data: PersonalData) : UiState
    data class Failed(val error: CardException?, val detail: String) : UiState
}

class CardViewModel : ViewModel() {
    private val _state = MutableStateFlow<UiState>(UiState.Idle)
    val state: StateFlow<UiState> = _state.asStateFlow()
    private var job: Job? = null

    /** True while the activity should keep NFC reader mode on. */
    val wantsNfc: Boolean get() = _state.value is UiState.WaitingNfc

    fun startNfc(adapter: NfcAdapter?) {
        if (adapter == null || !adapter.isEnabled) { fail(CardException(CardException.Kind.Other, "nfc_off"), "nfc"); return }
        _state.value = UiState.WaitingNfc
    }

    /** Called by NFC reader mode (on a binder thread). */
    fun onTag(tag: Tag) {
        val iso = IsoDep.get(tag) ?: return     // some other tag: keep waiting
        if (_state.value !is UiState.WaitingNfc) return
        _state.value = UiState.Reading
        job = viewModelScope.launch(Dispatchers.IO) {
            try {
                iso.connect()
                val data = EidCard(FollowingTransport(NfcTransport(iso))).readPersonalData()
                _state.value = UiState.Done(data)
            } catch (e: CardException) {
                fail(e, e.message ?: "")
            } catch (e: Exception) {
                fail(CardException(CardException.Kind.Lost, e.message ?: ""), e.message ?: "")
            } finally {
                try { iso.close() } catch (_: Exception) { }
            }
        }
    }

    fun startUsb(context: Context) {
        val usb = context.getSystemService(Context.USB_SERVICE) as UsbManager
        val device = UsbCcidTransport.findReader(usb)
        if (device == null) { _state.value = UiState.Failed(null, "no_usb"); return }
        _state.value = UiState.WaitingUsb
        job = viewModelScope.launch {
            val transport = UsbCcidTransport.open(context, device)
            if (transport == null) { _state.value = UiState.Failed(null, "usb_denied"); return@launch }
            _state.value = UiState.Reading
            withContext(Dispatchers.IO) {
                try {
                    transport.use {
                        it.powerOn()
                        _state.value = UiState.Done(EidCard(FollowingTransport(it)).readPersonalData())
                    }
                } catch (e: CardException) {
                    fail(e, e.message ?: "")
                } catch (e: Exception) {
                    fail(CardException(CardException.Kind.Other, e.message ?: ""), e.message ?: "")
                }
            }
        }
    }

    private fun fail(e: CardException?, detail: String) { _state.value = UiState.Failed(e, detail) }

    /** Back to the start screen; also drops personal data from memory. */
    fun reset() {
        job?.cancel()
        _state.value = UiState.Idle
    }
}
