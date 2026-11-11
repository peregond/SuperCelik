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

    /** NFC reader mode stays on whenever the app is waiting for a card (start screen, after an error, explicit NFC wait). */
    fun listensNfc(s: UiState = _state.value) = s is UiState.Idle || s is UiState.WaitingNfc || s is UiState.Failed

    fun startNfc(adapter: NfcAdapter?) {
        if (adapter == null || !adapter.isEnabled) { fail(CardException(CardException.Kind.Other, "nfc_off"), "nfc"); return }
        _state.value = UiState.WaitingNfc
    }

    /** App opened or came back to the start screen: use a connected USB reader right away. */
    fun autoStart(context: Context) {
        if (_state.value !is UiState.Idle) return
        val usb = context.getSystemService(Context.USB_SERVICE) as UsbManager
        if (UsbCcidTransport.findReader(usb) != null) startUsb(context)
    }

    /** Called by NFC reader mode (on a binder thread). */
    fun onTag(tag: Tag) {
        val iso = IsoDep.get(tag) ?: return     // some other tag: keep waiting
        if (!listensNfc()) return
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

    /** Fictional data for screenshots (launch intent extra "demo"); never touches a card. */
    fun showDemo() {
        _state.value = UiState.Done(PersonalData(
            cardType = CardType.RP2024, docRegNo = "001234567", documentType = "RP",
            issuingDate = "01.01.2024", expiryDate = "01.01.2030", issuingAuthority = "MUP RS",
            personalNumber = "0101990710000", surname = "PETROVIĆ", givenName = "MARKO",
            parentGivenName = "Nikola", sex = "M", placeOfBirth = "Beograd", dateOfBirth = "01.01.1990",
            address = "Knez Mihailova 1, Beograd, Stari Grad", portrait = null))
    }

    private fun fail(e: CardException?, detail: String) { _state.value = UiState.Failed(e, detail) }

    /** Back to the start screen; also drops personal data from memory. */
    fun reset() {
        job?.cancel()
        _state.value = UiState.Idle
    }
}
