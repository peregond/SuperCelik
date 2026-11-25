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
import android.os.Build
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume

/** The USB service, or null on a device that has none (no USB host: some emulators, cloud phones and containers). A plain cast would crash there. */
fun usbManager(context: Context): UsbManager? = context.getSystemService(Context.USB_SERVICE) as? UsbManager

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

    /**
     * Reads one whole CCID message from the bulk-in endpoint. It reads packet by packet and takes the length from the
     * 10-byte header, so it does not depend on the reader ending a transfer with a short or zero-length packet (some readers,
     * and some phones' USB stacks, hang or fail on one big read when the message is a multiple of the packet size).
     */
    private fun readMessage(timeout: Int): ByteArray {
        val pkt = maxOf(bulkIn.maxPacketSize, 64)
        val head = ByteArray(pkt)
        var n = 0
        var empty = 0
        while (n < 10) {
            val r = conn.bulkTransfer(bulkIn, head, n, pkt - n, timeout)
            if (r < 0) throw CardException(CardException.Kind.Lost, "USB read")
            if (r == 0 && ++empty > 4) throw CardException(CardException.Kind.Lost, "USB read (empty)")   // zero-length packets that end an earlier message are skipped
            n += r
        }
        val len = (head[1].toInt() and 0xFF) or (head[2].toInt() and 0xFF shl 8) or
            (head[3].toInt() and 0xFF shl 16) or (head[4].toInt() and 0xFF shl 24)
        if (len < 0 || len > 65536) throw CardException(CardException.Kind.Other, "CCID length $len")
        val total = 10 + len
        val out = head.copyOf(maxOf(total, n))
        while (n < total) {
            val r = conn.bulkTransfer(bulkIn, out, n, minOf(pkt, total - n), timeout)
            if (r <= 0) throw CardException(CardException.Kind.Lost, "USB read (${n - 10} of $len)")
            n += r
        }
        return out.copyOf(total)
    }

    /** Sends one CCID message and returns the DataBlock payload; waits through "time extension" replies. */
    private fun exchange(msg: ByteArray): ByteArray {
        if (conn.bulkTransfer(bulkOut, msg, msg.size, 5000) < 0) throw CardException(CardException.Kind.Lost, "USB write")
        repeat(40) {
            val buf = readMessage(10000)
            val status = buf[7].toInt() and 0xFF
            val cmd = status shr 6 and 3
            val icc = status and 3
            if (cmd == 2) return@repeat                                     // time extension: read again
            if (icc == 2) throw CardException(CardException.Kind.NoCard)
            if (cmd == 1) throw CardException(CardException.Kind.Other, "CCID error 0x%02X".format(buf[8].toInt() and 0xFF))
            return buf.copyOfRange(10, buf.size)
        }
        throw CardException(CardException.Kind.Lost, "USB timeout")
    }

    fun powerOn(): ByteArray = exchange(message(0x62))     // returns the ATR

    /** True when a card sits in the reader (CCID GetSlotStatus: no power-up, so it can be polled). */
    fun cardPresent(): Boolean {
        val msg = message(0x65)
        if (conn.bulkTransfer(bulkOut, msg, msg.size, 2000) < 0) throw CardException(CardException.Kind.Lost, "USB write")
        val buf = readMessage(2000)
        return (buf[7].toInt() and 3) != 2
    }

    /** Lets go of the reader without powering the card off (for the card watcher; a read powers it on itself). */
    fun release() {
        try { conn.releaseInterface(iface) } catch (_: Exception) { }
        conn.close()
    }

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
            val usb = usbManager(context) ?: return null
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
