package com.peregond.supercelik

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbEndpoint
import android.hardware.usb.UsbInterface
import android.hardware.usb.UsbManager
import android.nfc.tech.IsoDep
import android.os.Build
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume

/** Follows T=0 "61xx" (GET RESPONSE) and "6Cxx" (wrong Le) like the desktop apps do. */
class FollowingTransport(private val inner: CardTransport) : CardTransport {
    override fun transmit(apdu: ByteArray): Resp = inner.follow(apdu)
}

private fun CardTransport.follow(apdu: ByteArray): Resp {
    var r = transmit(apdu)
    if (r.sw shr 8 == 0x6C && apdu.size >= 5) {
        val again = apdu.copyOf(); again[again.size - 1] = (r.sw and 0xFF).toByte()
        r = transmit(again)
    }
    var data = r.data
    while (r.sw shr 8 == 0x61) {
        r = transmit(byteArrayOf(0x00, 0xC0.toByte(), 0x00, 0x00, (r.sw and 0xFF).toByte()))
        data += r.data
    }
    return Resp(data, r.sw)
}

private fun split(raw: ByteArray): Resp {
    if (raw.size < 2) throw CardException(CardException.Kind.Lost)
    return Resp(raw.copyOfRange(0, raw.size - 2),
        (raw[raw.size - 2].toInt() and 0xFF shl 8) or (raw[raw.size - 1].toInt() and 0xFF))
}

/** ISO-DEP over NFC. */
class NfcTransport(private val tag: IsoDep) : CardTransport {
    init { tag.timeout = 5000 }
    override fun transmit(apdu: ByteArray): Resp = try {
        split(tag.transceive(apdu))
    } catch (e: java.io.IOException) {
        throw CardException(CardException.Kind.Lost, e.message ?: "NFC")
    }
}

/**
 * USB CCID smart card reader (class 0x0B), e.g. Gemalto CT40, spoken to directly through Android's USB host API.
 * Minimal CCID: IccPowerOn once, then XfrBlock per APDU. Not tested on hardware yet.
 */
class UsbCcidTransport private constructor(
    private val conn: UsbDeviceConnection,
    private val iface: UsbInterface,
    private val bulkIn: UsbEndpoint,
    private val bulkOut: UsbEndpoint,
) : CardTransport, AutoCloseable {

    private var seq = 0

    private fun message(type: Int, payload: ByteArray = ByteArray(0), p0: Int = 0, p1: Int = 0, p2: Int = 0): ByteArray {
        val h = ByteArray(10)
        h[0] = type.toByte()
        h[1] = payload.size.toByte(); h[2] = (payload.size shr 8).toByte()
        h[3] = (payload.size shr 16).toByte(); h[4] = (payload.size shr 24).toByte()
        h[5] = 0                           // slot
        h[6] = (seq++ and 0xFF).toByte()
        h[7] = p0.toByte(); h[8] = p1.toByte(); h[9] = p2.toByte()
        return h + payload
    }

    /** Sends one CCID message and returns the DataBlock payload; waits through "time extension" replies. */
    private fun exchange(msg: ByteArray): ByteArray {
        if (conn.bulkTransfer(bulkOut, msg, msg.size, 5000) < 0) throw CardException(CardException.Kind.Lost, "USB write")
        val buf = ByteArray(65600)
        repeat(40) {
            val n = conn.bulkTransfer(bulkIn, buf, buf.size, 10000)
            if (n < 10) throw CardException(CardException.Kind.Lost, "USB read")
            val status = buf[7].toInt() and 0xFF
            val cmd = status shr 6 and 3
            val icc = status and 3
            if (cmd == 2) return@repeat                                     // time extension: read again
            if (icc == 2) throw CardException(CardException.Kind.NoCard)
            if (cmd == 1) throw CardException(CardException.Kind.Other, "CCID error 0x%02X".format(buf[8].toInt() and 0xFF))
            val len = (buf[1].toInt() and 0xFF) or (buf[2].toInt() and 0xFF shl 8)
            return buf.copyOfRange(10, 10 + minOf(len, n - 10))
        }
        throw CardException(CardException.Kind.Lost, "USB timeout")
    }

    fun powerOn(): ByteArray = exchange(message(0x62))     // returns the ATR

    override fun transmit(apdu: ByteArray): Resp = split(exchange(message(0x6F, apdu)))

    override fun close() {
        try { exchange(message(0x63)) } catch (_: Exception) { }   // IccPowerOff
        conn.releaseInterface(iface)
        conn.close()
    }

    companion object {
        private const val ACTION = "com.peregond.supercelik.USB_PERMISSION"

        fun findReader(usb: UsbManager): UsbDevice? =
            usb.deviceList.values.firstOrNull { d -> (0 until d.interfaceCount).any { d.getInterface(it).interfaceClass == 0x0B } }

        /** Asks the user for access if needed, then opens the reader. Returns null if access was denied. */
        suspend fun open(context: Context, device: UsbDevice): UsbCcidTransport? {
            val usb = context.getSystemService(Context.USB_SERVICE) as UsbManager
            if (!usb.hasPermission(device)) {
                val granted = suspendCancellableCoroutine<Boolean> { cont ->
                    val receiver = object : BroadcastReceiver() {
                        override fun onReceive(c: Context, i: Intent) {
                            context.unregisterReceiver(this)
                            if (cont.isActive) cont.resume(i.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false))
                        }
                    }
                    val filter = IntentFilter(ACTION)
                    if (Build.VERSION.SDK_INT >= 33) context.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
                    else @Suppress("UnspecifiedRegisterReceiverFlag") context.registerReceiver(receiver, filter)
                    // must be mutable: the system adds the permission result to this intent
                    val flags = if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0
                    usb.requestPermission(device, PendingIntent.getBroadcast(context, 0, Intent(ACTION).setPackage(context.packageName), flags))
                    cont.invokeOnCancellation { try { context.unregisterReceiver(receiver) } catch (_: Exception) { } }
                }
                if (!granted) return null
            }
            val iface = (0 until device.interfaceCount).map { device.getInterface(it) }.first { it.interfaceClass == 0x0B }
            var inEp: UsbEndpoint? = null
            var outEp: UsbEndpoint? = null
            for (i in 0 until iface.endpointCount) {
                val e = iface.getEndpoint(i)
                if (e.type != UsbConstants.USB_ENDPOINT_XFER_BULK) continue
                if (e.direction == UsbConstants.USB_DIR_IN) inEp = e else outEp = e
            }
            val connection = usb.openDevice(device) ?: return null
            if (inEp == null || outEp == null || !connection.claimInterface(iface, true)) {
                connection.close(); return null
            }
            return UsbCcidTransport(connection, iface, inEp, outEp)
        }
    }
}
