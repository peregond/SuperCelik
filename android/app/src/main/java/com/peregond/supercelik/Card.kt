package com.peregond.supercelik

/** Response of one APDU: data without the status word, and the status word. */
class Resp(val data: ByteArray, val sw: Int)

/** How APDUs reach the card (NFC, USB reader...). Blocking; call off the main thread. */
interface CardTransport {
    fun transmit(apdu: ByteArray): Resp
}

class CardException(val kind: Kind, message: String = kind.name) : Exception(message) {
    enum class Kind { NoCard, Unsupported, Lost, Other }
}

enum class CardType { ID2014, IF2020, RP2024 }

data class PersonalData(
    val cardType: CardType,
    val docRegNo: String, val documentType: String,
    val issuingDate: String, val expiryDate: String, val issuingAuthority: String,
    val personalNumber: String, val surname: String, val givenName: String,
    val parentGivenName: String, val sex: String, val placeOfBirth: String,
    val dateOfBirth: String,
    val address: String,
    val portrait: ByteArray?,
)

/**
 * Card protocol, a port of Sources/SerbiaID/EidCard.swift (macOS/iOS) and windows Card.cs.
 * Derived by observing CelikApi.dll and a real RP2024 card; tags marked UNVERIFIED are inferred.
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
    private fun readRawFile(fid: Int): ByteArray {
        cache[fid]?.let { return it }
        var r = tx(0x00, 0xA4, 0x00, 0x0C, 0x02, fid shr 8 and 0xFF, fid and 0xFF)
        if (r.sw != 0x9000) throw CardException(CardException.Kind.Other, "Select file %04X: %04X".format(fid, r.sw))
        r = tx(0x00, 0xB0, 0x00, 0x00, 0x04)
        if (r.sw != 0x9000 || r.data.size != 4) throw CardException(CardException.Kind.Other, "Read header %04X: %04X".format(fid, r.sw))
        val total = 4 + (r.data[2].toInt() and 0xFF) + ((r.data[3].toInt() and 0xFF) shl 8)
        val out = java.io.ByteArrayOutputStream().apply { write(r.data) }
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
    private fun records(file: ByteArray): Map<Int, ByteArray> {
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
            personalNumber = str(fix, 0x0616), surname = str(fix, 0x0617), givenName = str(fix, 0x0618),
            parentGivenName = str(fix, 0x0619),            // UNVERIFIED tag
            sex = str(fix, 0x061A),
            placeOfBirth = str(fix, 0x061B),               // UNVERIFIED tag
            dateOfBirth = date(fix, 0x061E),
            address = address,
            portrait = portrait,
        )
    }

    companion object {
        private val APPLETS = listOf(
            CardType.ID2014 to "F381000002534552494401",   // SERID
            CardType.IF2020 to "F381000002534552494601",   // SERIF
            CardType.RP2024 to "F381000002534552525001",   // SERRP
        )
    }
}
