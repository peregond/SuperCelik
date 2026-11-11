package com.peregond.supercelik

import java.io.ByteArrayOutputStream
import java.security.MessageDigest
import java.util.zip.Inflater

/** Response of one APDU: data without the status word, and the status word. */
class Resp(val data: ByteArray, val sw: Int)

/** How APDUs reach the card (NFC, USB reader...). Blocking; call off the main thread. */
interface CardTransport {
    fun transmit(apdu: ByteArray): Resp
}

class CardException(val kind: Kind, message: String = kind.name) : Exception(message) {
    enum class Kind { NoCard, Unsupported, Lost, Other }
}

/** Wrong PIN/PUK (the card reports the tries left) or a blocked PIN. */
class PinException(val triesLeft: Int, val blocked: Boolean) : Exception(if (blocked) "PIN blocked" else "Wrong PIN, $triesLeft tries left")

enum class CardType { ID2014, IF2020, RP2024 }

data class PersonalData(
    val cardType: CardType,
    val docRegNo: String, val documentType: String,
    val issuingDate: String, val expiryDate: String, val issuingAuthority: String,
    val docSerial: String,
    val personalNumber: String, val surname: String, val givenName: String,
    val parentGivenName: String, val sex: String, val placeOfBirth: String,
    val stateOfBirth: String, val dateOfBirth: String, val nationality: String,
    val address: String,
    val portrait: ByteArray?,
    // raw fields for the MUP print layout
    val communityOfBirth: String = "", val purposeOfStay: String = "", val eNote: String = "", val documentName: String = "",
    val addrState: String = "", val community: String = "", val place: String = "", val street: String = "",
    val houseNumber: String = "", val houseLetter: String = "", val entrance: String = "", val floor: String = "",
    val apartment: String = "", val addressDate: String = "", val addressLabel: String = "",
)

class TokenCert(val label: String, val der: ByteArray)
class TokenData(val label: String, val serial: String, val certs: List<TokenCert>)

/**
 * Card protocol, a port of Sources/SerbiaID/EidCard.swift (macOS/iOS) and windows Card.cs.
 * Derived by observing CelikApi.dll and a real RP2024 card; tags marked UNVERIFIED are inferred.
 * PIN change and signing were verified on a real card on macOS; PUK unblock was not.
 */
class EidCard(private val transport: CardTransport) {

    private val cache = HashMap<Int, ByteArray>()

    private fun hex(s: String) = ByteArray(s.length / 2) { s.substring(it * 2, it * 2 + 2).toInt(16).toByte() }

    private fun tx(vararg bytes: Int): Resp = transport.transmit(ByteArray(bytes.size) { bytes[it].toByte() })

    private fun select(aid: ByteArray): Resp =
        transport.transmit(byteArrayOf(0x00, 0xA4.toByte(), 0x04, 0x00, aid.size.toByte()) + aid)

    fun selectApplet(): CardType {
        for ((type, aid) in APPLETS) if (select(hex(aid)).sw == 0x9000) return type
        throw CardException(CardException.Kind.Unsupported)
    }

    /** Whole file including the 4-byte header (id LE16, length LE16). */
    fun readRawFile(fid: Int): ByteArray {
        cache[fid]?.let { return it }
        var r = tx(0x00, 0xA4, 0x00, 0x0C, 0x02, fid shr 8 and 0xFF, fid and 0xFF)
        if (r.sw != 0x9000) throw CardException(CardException.Kind.Other, "Select file %04X: %04X".format(fid, r.sw))
        r = tx(0x00, 0xB0, 0x00, 0x00, 0x04)
        if (r.sw != 0x9000 || r.data.size != 4) throw CardException(CardException.Kind.Other, "Read header %04X: %04X".format(fid, r.sw))
        val total = 4 + (r.data[2].toInt() and 0xFF) + ((r.data[3].toInt() and 0xFF) shl 8)
        val out = ByteArrayOutputStream().apply { write(r.data) }
        while (out.size() < total) {
            val n = minOf(0xE0, total - out.size())
            val o = out.size()
            r = tx(0x00, 0xB0, o shr 8 and 0xFF, o and 0xFF, n)
            if (r.sw != 0x9000 || r.data.isEmpty()) throw CardException(CardException.Kind.Other, "Read %04X: %04X".format(fid, r.sw))
            out.write(r.data)
        }
        return out.toByteArray().also { cache[fid] = it }
    }

    /** Body = records of tag(LE16) len(LE16) value. */
    fun records(file: ByteArray): Map<Int, ByteArray> {
        val d = HashMap<Int, ByteArray>()
        var p = 4
        while (p + 4 <= file.size) {
            val tag = (file[p].toInt() and 0xFF) or ((file[p + 1].toInt() and 0xFF) shl 8)
            val len = (file[p + 2].toInt() and 0xFF) or ((file[p + 3].toInt() and 0xFF) shl 8)
            if (p + 4 + len > file.size) break
            d[tag] = file.copyOfRange(p + 4, p + 4 + len)
            p += 4 + len
        }
        return d
    }

    private fun str(m: Map<Int, ByteArray>, tag: Int) = m[tag]?.toString(Charsets.UTF_8) ?: ""

    /** Card stores DDMMYYYY; shown as DD.MM.YYYY like the official API. */
    private fun date(m: Map<Int, ByteArray>, tag: Int): String {
        val s = str(m, tag)
        return if (s.length == 8) "${s.take(2)}.${s.substring(2, 4)}.${s.takeLast(4)}" else s
    }

    fun readPersonalData(): PersonalData {
        val type = selectApplet()
        val doc = records(readRawFile(0x0F02))
        val fix = records(readRawFile(0x0F03))
        val v = records(readRawFile(0x0F04))
        val portrait = records(readRawFile(0x0F06))[0x0110]
        // address tags 0x0620..0x0628 (state, community, place, street, house number, letter, entrance, floor, apartment):
        // 0620 / 0625..0628 are UNVERIFIED
        val street = listOf(str(v, 0x0623), str(v, 0x0624) + str(v, 0x0625)).filter { it.isNotBlank() }.joinToString(" ")
        val flat = listOf(str(v, 0x0626).takeIf { it.isNotBlank() }?.let { "ul. $it" },
            str(v, 0x0627).takeIf { it.isNotBlank() }?.let { "sprat $it" },
            str(v, 0x0628).takeIf { it.isNotBlank() }?.let { "stan $it" }).filterNotNull().joinToString(", ")
        val address = listOf(street, flat, str(v, 0x0622), str(v, 0x0621), str(v, 0x0620))
            .filter { it.isNotBlank() }.joinToString(", ")
        return PersonalData(
            cardType = type,
            docRegNo = str(doc, 0x060A), documentType = str(doc, 0x060B),
            issuingDate = date(doc, 0x060D), expiryDate = date(doc, 0x060E), issuingAuthority = str(doc, 0x060F),
            docSerial = str(doc, 0x0691),
            personalNumber = str(fix, 0x0616), surname = str(fix, 0x0617), givenName = str(fix, 0x0618),
            parentGivenName = str(fix, 0x0619),            // UNVERIFIED tag
            sex = str(fix, 0x061A),
            placeOfBirth = str(fix, 0x061B),               // UNVERIFIED tag
            stateOfBirth = str(fix, 0x061D),
            dateOfBirth = date(fix, 0x061E),
            nationality = str(fix, 0x062F),
            address = address,
            portrait = portrait,
            communityOfBirth = str(fix, 0x061C),            // UNVERIFIED tag
            purposeOfStay = str(fix, 0x0693), eNote = str(fix, 0x0694), documentName = str(doc, 0x0692),
            addrState = str(v, 0x0620), community = str(v, 0x0621), place = str(v, 0x0622), street = str(v, 0x0623),
            houseNumber = str(v, 0x0624), houseLetter = str(v, 0x0625), entrance = str(v, 0x0626),
            floor = str(v, 0x0627), apartment = str(v, 0x0628), addressDate = date(v, 0x062C),
        )
    }

    // ---- card signatures: 0F1C = CMS over SHA-256 of whole files; 0F1D = CMS over SHA-256 of 0F04 ----

    /** Checks both card signatures (CMS + chain to the bundled MUP CAs + file hashes). */
    fun verifySignatures(): SigResult {
        selectApplet()
        var chainMsg: String? = null
        for ((cmsFile, tag, covered) in SIGNED) {
            val blob = try { records(readRawFile(cmsFile))[tag] } catch (e: CardException) { null }
                ?: return SigResult.Invalid("signature block missing")
            val r = CardCrypto.verifyCms(blob)
            val content = r.content ?: return SigResult.Invalid(r.error ?: "bad signature")
            if (!r.chainOk) chainMsg = r.error ?: "untrusted"
            for (fid in covered) {
                val h = MessageDigest.getInstance("SHA-256").digest(readRawFile(fid))
                var found = false
                var i = 0
                while (i + 32 <= content.size && !found) {
                    found = content.copyOfRange(i, i + 32).contentEquals(h); i += 32
                }
                if (!found) return SigResult.Invalid("hash mismatch for file %04X".format(fid))
            }
        }
        return if (chainMsg == null) SigResult.Ok else SigResult.ChainNotTrusted(chainMsg)
    }

    // ---- token (PKCS#15 / CardEdge) ----

    private fun selectTokenApplet() {
        if (select(hex(TOKEN_AID)).sw != 0x9000) throw CardException(CardException.Kind.Unsupported, "No token applet on this card")
    }

    private fun readTokenFile(fid: Int): ByteArray {
        val sel = tx(0x00, 0xA4, 0x00, 0x00, 0x02, fid shr 8 and 0xFF, fid and 0xFF)
        if (sel.sw != 0x9000 || sel.data.size < 4) throw CardException(CardException.Kind.Other, "Select token file %04X: %04X".format(fid, sel.sw))
        val size = (sel.data[2].toInt() and 0xFF shl 8) or (sel.data[3].toInt() and 0xFF)
        val out = ByteArrayOutputStream()
        while (out.size() < size) {
            val o = out.size()
            val r = tx(0x00, 0xB0, o shr 8 and 0xFF, o and 0xFF, minOf(0xE0, size - o))
            if (r.sw != 0x9000 || r.data.isEmpty()) throw CardException(CardException.Kind.Other, "Read token file %04X: %04X".format(fid, r.sw))
            out.write(r.data)
        }
        return out.toByteArray()
    }

    fun readToken(): TokenData {
        selectTokenApplet()
        var label = ""; var serial = ""
        runCatching {
            val d = readTokenFile(0x70F3)
            if (d.size > 32) {
                label = String(d, 0, 32, Charsets.UTF_8).trim()
                serial = String(d.drop(32).takeWhile { it in 0x20..0x7E }.toByteArray(), Charsets.US_ASCII).trim()
            }
        }
        val certs = ArrayList<TokenCert>()
        runCatching {
            val blob = readTokenFile(0x7102)           // [len LE16][01 00][usize LE16][zlib]
            if (blob.size > 8) {
                val inf = Inflater()
                inf.setInput(blob, 6, blob.size - 6)
                val out = ByteArrayOutputStream(); val buf = ByteArray(4096)
                while (!inf.finished()) {
                    val n = inf.inflate(buf)
                    if (n == 0 && (inf.needsInput() || inf.needsDictionary())) break
                    out.write(buf, 0, n)
                }
                var certLabel = ""
                runCatching {
                    val l = readTokenFile(0x8007)       // [01 71 02 len] + label
                    if (l.size > 4) certLabel = String(l, 4, minOf(l[3].toInt() and 0xFF, l.size - 4), Charsets.UTF_8)
                }
                certs.add(TokenCert(certLabel, out.toByteArray()))
            }
        }
        return TokenData(label, serial, certs)
    }

    // ---- token PIN / PUK / signing (a wrong PIN or PUK uses up a card try: one attempt, never retried) ----

    private fun paddedPin(pin: String): ByteArray {
        require(pin.length in 4..8 && pin.all { it in '0'..'9' }) { "PIN must be 4-8 digits" }
        return pin.toByteArray(Charsets.US_ASCII) + ByteArray(8 - pin.length)
    }

    private fun throwPin(sw: Int): Nothing {
        if (sw == 0x6983 || sw == 0x63C0) throw PinException(0, true)
        if (sw shr 4 == 0x063C) throw PinException(sw and 0xF, false)
        throw CardException(CardException.Kind.Other, "PIN operation failed: %04X".format(sw))
    }

    private fun apdu(ins: Int, p1: Int, p2: Int, data: ByteArray): Resp =
        transport.transmit(byteArrayOf(0x00, ins.toByte(), p1.toByte(), p2.toByte(), data.size.toByte()) + data)

    fun changePin(old: String, new: String) {
        selectTokenApplet()
        val r = apdu(0x24, 0x00, 0x80, paddedPin(old) + paddedPin(new))
        if (r.sw != 0x9000) throwPin(r.sw)
    }

    /** UNVERIFIED APDU (ISO 7816-4 RESET RETRY COUNTER, PUK || new PIN). */
    fun unblockPin(puk: String, new: String) {
        selectTokenApplet()
        val r = apdu(0x2C, 0x00, 0x80, paddedPin(puk) + paddedPin(new))
        if (r.sw != 0x9000) throwPin(r.sw)
    }

    /** RSA PKCS#1 v1.5 signature over a DER DigestInfo, with the token key (private key file 0x6005 on RP2024). */
    fun sign(pin: String, digestInfo: ByteArray, keyFile: Int = 0x6005): ByteArray {
        selectTokenApplet()
        val v = apdu(0x20, 0x00, 0x80, paddedPin(pin))
        if (v.sw != 0x9000) throwPin(v.sw)
        val mse = byteArrayOf(0x80.toByte(), 0x01, 0x02, 0x84.toByte(), 0x02, (keyFile shr 8).toByte(), keyFile.toByte())
        var r = apdu(0x22, 0x41, 0xB6, mse)
        if (r.sw != 0x9000) throw CardException(CardException.Kind.Other, "MSE SET: %04X".format(r.sw))
        r = transport.transmit(byteArrayOf(0x00, 0x2A, 0x9E.toByte(), 0x00, digestInfo.size.toByte()) + digestInfo + byteArrayOf(0x00))
        if (r.sw != 0x9000 || r.data.isEmpty()) throw CardException(CardException.Kind.Other, "Sign: %04X".format(r.sw))
        return r.data
    }

    companion object {
        private const val TOKEN_AID = "A000000063504B43532D3135"
        private val APPLETS = listOf(
            CardType.ID2014 to "F381000002534552494401",   // SERID
            CardType.IF2020 to "F381000002534552494601",   // SERIF
            CardType.RP2024 to "F381000002534552525001",   // SERRP
        )
        private val SIGNED = listOf(
            Triple(0x0F1C, 0x0810, listOf(0x0F1B, 0x0F02, 0x0F03, 0x0F06, 0x0FA1, 0x0FA2)),
            Triple(0x0F1D, 0x0820, listOf(0x0F04)),
        )
    }
}

sealed interface SigResult {
    data object Ok : SigResult
    data class ChainNotTrusted(val detail: String) : SigResult
    data class Invalid(val detail: String) : SigResult
}
