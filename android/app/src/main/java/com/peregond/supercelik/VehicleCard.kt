package com.peregond.supercelik

// Vehicle registration card (Saobraćajna dozvola). Parsing is written from the EU directive 1999/37/EC as amended by
// 2003/127/EC (Annex I, chapter III) and from the MUP RS "eVehicle Registration SDK" field table; see docs/cards-research.md.
// STATUS: confirmed against the specification only, NOT yet against a real card.
// Same logic as windows/SerbiaID.Windows/Cards.cs and Sources/SerbiaID/VehicleCard.swift.

// ---------------------------------------------------------------- BER-TLV (ISO/IEC 7816-4)

class Tlv(val tag: Int, var constructed: Boolean, val value: ByteArray, var children: List<Tlv> = emptyList()) {
    val tagHex: String get() = if (tag > 0xFFFF) "%06X".format(tag) else if (tag > 0xFF) "%04X".format(tag) else "%02X".format(tag)
}

object Ber {
    /** Parses a run of TLV objects; trailing zero padding is ignored. null = not well-formed BER. */
    fun parse(d: ByteArray): List<Tlv>? = parse(d, 0, d.size, 0)

    private fun parse(d: ByteArray, start: Int, end: Int, depth: Int): List<Tlv>? {
        var pos = start
        val list = ArrayList<Tlv>()
        if (depth > 8) return null
        while (pos < end) {
            val first = d[pos].toInt() and 0xFF
            if (first == 0x00 || first == 0xFF) {                       // padding
                for (i in pos until end) if ((d[i].toInt() and 0xFF) != first) return null
                break
            }
            val b0 = first; pos++
            var tag = b0
            if (b0 and 0x1F == 0x1F) {
                var n = 0
                do {
                    n++
                    if (pos >= end || n > 2) return null
                    tag = tag shl 8 or (d[pos].toInt() and 0xFF)
                    pos++
                } while (d[pos - 1].toInt() and 0x80 != 0)
            }
            if (pos >= end) return null
            var len = d[pos].toInt() and 0xFF; pos++
            if (len >= 0x80) {
                val n = len and 0x7F
                if (n < 1 || n > 3 || pos + n > end) return null
                len = 0
                repeat(n) { len = len shl 8 or (d[pos].toInt() and 0xFF); pos++ }
            }
            if (pos + len > end) return null
            val t = Tlv(tag, b0 and 0x20 != 0, d.copyOfRange(pos, pos + len))
            if (t.constructed) {
                t.children = parse(d, pos, pos + len, depth + 1) ?: return null
            } else if (tag == 0x5A && len > 2) {
                // The MUP SDK table nests the engine data under '5A', a primitive tag by the BER rules.
                // If the value is a well-formed run of TLVs, treat it as constructed (unconfirmed, see docs).
                val inner = parse(d, pos, pos + len, depth + 1)
                if (inner != null && inner.isNotEmpty()) { t.constructed = true; t.children = inner }
            }
            list.add(t)
            pos += len
        }
        return list
    }

    fun build(tag: Int, value: ByteArray): ByteArray {
        val o = java.io.ByteArrayOutputStream()
        if (tag > 0xFFFF) o.write(tag shr 16 and 0xFF)
        if (tag > 0xFF) o.write(tag shr 8 and 0xFF)
        o.write(tag and 0xFF)
        when {
            value.size < 0x80 -> o.write(value.size)
            value.size < 0x100 -> { o.write(0x81); o.write(value.size) }
            else -> { o.write(0x82); o.write(value.size shr 8); o.write(value.size and 0xFF) }
        }
        o.write(value)
        return o.toByteArray()
    }
}

// ---------------------------------------------------------------- data

class VehicleData {
    // document
    var stateIssuing = ""; var competentAuthority = ""; var authorityIssuing = ""; var unambiguousNumber = ""
    var issuingDate = ""; var expiryDate = ""; var serialNumber = ""
    // vehicle
    var registrationNumber = ""; var firstRegistrationDate = ""; var yearOfProduction = ""; var make = ""; var type = ""
    var commercialDescription = ""; var vin = ""; var maxNetPower = ""; var engineCapacity = ""; var fuelType = ""
    var powerWeightRatio = ""; var mass = ""; var maxLadenMass = ""; var typeApprovalNumber = ""; var seats = ""; var standingPlaces = ""
    var engineNumber = ""; var axles = ""; var category = ""; var colour = ""; var saleBan = ""; var load = ""
    // owner and user
    var ownerPersonalNo = ""; var ownerSurname = ""; var ownerName = ""; var ownerAddress = ""
    var userPersonalNo = ""; var userSurname = ""; var userName = ""; var userAddress = ""
    /** Character set tag 9F37 as read (-1 = absent). */
    var charsetTag = -1
    /** Structure of what was not recognised (path/length), no values. */
    val unknownTags = ArrayList<String>()
    /** true only after the issuer signature has been checked (not implemented: algorithm unknown, see docs). */
    var signatureVerified = false

    val ownerFull: String get() = "$ownerName $ownerSurname".trim()
    val userFull: String get() = "$userName $userSurname".trim()
}

object VehicleParser {
    /** Parses the content of the registration data files (D001, D011, D021 and the unsigned national file, in any order). */
    fun parse(files: List<ByteArray?>): VehicleData {
        val v = VehicleData()
        val trees = files.mapNotNull { f -> f?.let { Ber.parse(it) }?.takeIf { it.isNotEmpty() } }
        for (t in trees) findCharset(t, v)
        val holder = arrayOfNulls<String>(3)   // A2 (holder in part 1): the owner only if there is no A7
        for (t in trees) walk(t, "", v, holder)
        if (v.ownerSurname.isEmpty() && v.ownerName.isEmpty() && v.ownerAddress.isEmpty()) {
            v.ownerSurname = holder[0] ?: ""; v.ownerName = holder[1] ?: ""; v.ownerAddress = holder[2] ?: ""
        }
        return v
    }

    private fun findCharset(nodes: List<Tlv>, v: VehicleData) {
        for (n in nodes) {
            if (n.tag == 0x9F37 && n.value.isNotEmpty() && v.charsetTag < 0) v.charsetTag = n.value[0].toInt() and 0xFF
            if (n.constructed) findCharset(n.children, v)
        }
    }

    private fun walk(nodes: List<Tlv>, path: String, v: VehicleData, holder: Array<String?>) {
        for (n in nodes) {
            val key = if (path.isEmpty()) n.tagHex else path + "." + n.tagHex
            if (path.isEmpty() && (n.tag == 0x71 || n.tag == 0x72 || n.tag == 0x73 || n.tag == 0x74)) { walk(n.children, "", v, holder); continue }
            if (n.constructed) { walk(n.children, key, v, holder); continue }
            assign(v, key, CardText.decode(n.value, v.charsetTag), n.value.size, holder)
        }
    }

    private fun assign(v: VehicleData, key: String, s: String, len: Int, holder: Array<String?>) {
        when (key) {
            "78.4F", "80", "9F34", "9F37", "A1.A2.86" -> {}
            "9F33" -> v.stateIssuing = s
            "9F35" -> v.competentAuthority = s
            "9F36" -> v.authorityIssuing = s
            "9F38" -> v.unambiguousNumber = s
            "81" -> v.registrationNumber = s
            "82" -> v.firstRegistrationDate = CardText.date(s)
            "8D" -> v.expiryDate = CardText.date(s)
            "8E" -> v.issuingDate = CardText.date(s)
            "8A" -> v.vin = s
            "8C" -> v.mass = s
            "8F" -> v.typeApprovalNumber = s
            "93" -> v.powerWeightRatio = s
            "98" -> v.category = s
            "99" -> v.axles = s
            "9F24" -> v.colour = s
            "A3.87" -> v.make = s
            "A3.88" -> v.type = s
            "A3.89" -> v.commercialDescription = s
            "A4.8B", "A4.96" -> v.maxLadenMass = s
            // the directive nests the engine under A5, the MUP SDK table writes 5A: accept both
            "A5.90", "5A.90" -> v.engineCapacity = s
            "A5.91", "5A.91" -> v.maxNetPower = s
            "A5.92", "5A.92" -> v.fuelType = s
            "A5.9E", "5A.9E" -> v.engineNumber = s
            "A6.94" -> v.seats = s
            "A6.95" -> v.standingPlaces = s
            "A1.A2.83" -> holder[0] = s
            "A1.A2.84" -> holder[1] = s
            "A1.A2.85" -> holder[2] = s
            "A1.A7.83" -> v.ownerSurname = s
            "A1.A7.84" -> v.ownerName = s
            "A1.A7.85" -> v.ownerAddress = s
            "A1.A9.83" -> v.userSurname = s
            "A1.A9.84" -> v.userName = s
            "A1.A9.85" -> v.userAddress = s
            // Serbian extension tags (MUP SDK table)
            "C1" -> v.saleBan = s
            "C2" -> v.ownerPersonalNo = s
            "C3" -> v.userPersonalNo = s
            "C4" -> v.load = s
            "C5" -> v.yearOfProduction = s
            "C9" -> v.serialNumber = s
            else -> v.unknownTags.add("$key/$len")
        }
    }
}

/** Text decoding for card values: ASCII with ISO 8859-1 / -5 / -7 above 0xBF, chosen by tag 9F37 (directive III.11). */
object CardText {
    fun decode(b: ByteArray, charset: Int): String {
        var end = b.size
        while (end > 0 && (b[end - 1].toInt() == 0 || b[end - 1].toInt() == 0x20)) end--
        var start = 0
        while (start < end && b[start].toInt() == 0x20) start++
        val body = b.copyOfRange(start, end)
        // Not in the spec: bytes that are valid UTF-8 with multi-byte characters are taken as UTF-8 (a national
        // deviation would look like this). Which one the cards use is to be seen in the diagnostic log.
        if (body.any { it.toInt() < 0 } && isUtf8(body)) return String(body, Charsets.UTF_8)
        val sb = StringBuilder(body.size)
        for (x in body) sb.append(map(x.toInt() and 0xFF, charset))
        return sb.toString()
    }

    private fun isUtf8(b: ByteArray): Boolean {
        var i = 0
        var multi = false
        while (i < b.size) {
            val c = b[i].toInt() and 0xFF
            val n = when {
                c < 0x80 -> 0
                c and 0xE0 == 0xC0 -> 1
                c and 0xF0 == 0xE0 -> 2
                c and 0xF8 == 0xF0 -> 3
                else -> return false
            }
            if (i + n >= b.size && n > 0) return false
            for (k in 1..n) if (b[i + k].toInt() and 0xC0 != 0x80) return false
            if (n > 0) multi = true
            i += n + 1
        }
        return multi
    }

    private fun map(x: Int, cs: Int): Char {
        if (x < 0xA0) return x.toChar()
        if (cs == 1) {                                   // ISO 8859-5 (Cyrillic)
            if (x == 0xA0 || x == 0xAD) return x.toChar()
            if (x == 0xF0) return '№'
            if (x == 0xFD) return '§'
            return (0x0400 + (x - 0xA0)).toChar()
        }
        if (cs == 2) {                                   // ISO 8859-7 (Greek), letters only
            if (x in 0xC1..0xD1) return (0x0391 + (x - 0xC1)).toChar()
            if (x in 0xD3..0xD9) return (0x03A3 + (x - 0xD3)).toChar()
            if (x in 0xE1..0xF9) return (0x03B1 + (x - 0xE1)).toChar()
        }
        return x.toChar()                                // ISO 8859-1
    }

    /** The card stores YYYYMMDD (directive III.11); shown as DD.MM.YYYY like the ID card. */
    fun date(s: String): String {
        if (s.length != 8 || s.any { it !in '0'..'9' }) return s
        return s.substring(6, 8) + "." + s.substring(4, 6) + "." + s.substring(0, 4)
    }
}

// ---------------------------------------------------------------- rows shown by the app

object VehicleRows {
    /** Hidden behind the eye like the ID card's personal number and address. */
    val sensitive = setOf("vOwner", "vOwnerAddr", "vOwnerJmbg", "vUser", "vUserAddr", "vUserJmbg", "vDocSerial", "vDocNo", "vSaleBan")

    fun build(v: VehicleData, includeJmbg: Boolean = true): List<Pair<String, String>> {
        val r = ArrayList<Pair<String, String>>()
        fun a(k: String, s: String) { if (s.isNotEmpty()) r.add(k to s) }
        a("vRegNo", v.registrationNumber); a("vMake", v.make); a("vType", v.type); a("vModel", v.commercialDescription)
        a("vVin", v.vin); a("vYear", v.yearOfProduction); a("vColour", v.colour); a("vCategory", v.category)
        a("vFirstReg", v.firstRegistrationDate); a("vValidUntil", v.expiryDate); a("vIssued", v.issuingDate)
        a("vFuel", v.fuelType); a("vCapacity", v.engineCapacity); a("vPower", v.maxNetPower); a("vPowerWeight", v.powerWeightRatio)
        a("vEngineNo", v.engineNumber); a("vMass", v.mass); a("vMaxMass", v.maxLadenMass); a("vLoad", v.load)
        a("vSeats", v.seats); a("vStanding", v.standingPlaces); a("vAxles", v.axles); a("vApproval", v.typeApprovalNumber)
        a("vOwner", v.ownerFull); a("vOwnerAddr", v.ownerAddress); if (includeJmbg) a("vOwnerJmbg", v.ownerPersonalNo)
        a("vUser", v.userFull); a("vUserAddr", v.userAddress); if (includeJmbg) a("vUserJmbg", v.userPersonalNo)
        a("vSaleBan", CardText.date(v.saleBan))
        a("vDocNo", v.unambiguousNumber); a("vDocSerial", v.serialNumber); a("vAuthority", v.authorityIssuing)
        return r
    }

    /** Fictional data for demo mode and screenshots. */
    fun demo() = VehicleData().apply {
        registrationNumber = "BG 123-AB"; make = "ZASTAVA"; type = "103"; commercialDescription = "YUGO 55"
        vin = "VX1146A0000000001"; yearOfProduction = "1989"; colour = "CRVENA"; category = "M1"
        firstRegistrationDate = "12.03.1989"; expiryDate = "12.03.2027"; issuingDate = "12.03.2026"
        fuelType = "BENZIN"; engineCapacity = "1116"; maxNetPower = "41"; engineNumber = "0000001"
        mass = "790"; maxLadenMass = "1215"; seats = "5"; standingPlaces = "0"; axles = "2"
        typeApprovalNumber = "e1*00/00*0000"
        ownerSurname = "PETROVIĆ"; ownerName = "MARKO"; ownerAddress = "Knez Mihailova 1, Beograd"; ownerPersonalNo = "0101990710000"
        unambiguousNumber = "000000001"; serialNumber = "SD0000001"; authorityIssuing = "PU ZA GRAD BEOGRAD, MINISTARSTVO UNUTRASNJIH POSLOVA REPUBLIKE SRBIJE"
        stateIssuing = "REPUBLIKA SRBIJA"; load = "0"; powerWeightRatio = "0"
    }
}

// ---------------------------------------------------------------- reading over a transport

/**
 * Reads the registration card through an APDU channel (hand it a FollowingTransport: it follows 61xx / 6Cxx).
 * The application name is NOT published; the candidates come from analysing MUP's own SDK binary and are unconfirmed.
 */
class RegistrationCard(private val transport: CardTransport) {
    companion object {
        /** Candidate application names: the ID-card scheme F381000002 + "SERVL" + 01 by analogy, the same as a prefix
         *  (ISO 7816-4 allows partial DF names with P2=00), and a longer form seen in the SDK. */
        val CANDIDATE_AIDS = listOf("F381000002534552564C01", "F381000002534552564C", "F381000002534552564C040201")
        val DATA_FILES = intArrayOf(0xD001, 0xD011, 0xD021)

        fun hex(s: String) = ByteArray(s.length / 2) { s.substring(it * 2, it * 2 + 2).toInt(16).toByte() }
        fun hex(b: ByteArray) = b.joinToString("") { "%02X".format(it.toInt() and 0xFF) }

        fun apdu(ins: Int, p1: Int, p2: Int, data: ByteArray = ByteArray(0), le: Int? = null): ByteArray {
            val o = java.io.ByteArrayOutputStream()
            o.write(0x00); o.write(ins); o.write(p1); o.write(p2)
            if (data.isNotEmpty()) { o.write(data.size); o.write(data) }
            if (le != null) o.write(le)
            return o.toByteArray()
        }

        /** File size from the FCP/FCI: tag 80 or 81 (also inside 62 / 6F). 0 = not given. */
        fun fcpSize(fcp: ByteArray): Int {
            if (fcp.isEmpty()) return 0
            val t = Ber.parse(fcp) ?: return 0
            fun find(nodes: List<Tlv>): Int {
                for (n in nodes) {
                    if ((n.tag == 0x80 || n.tag == 0x81) && n.value.size in 1..3) return n.value.fold(0) { a, b -> a shl 8 or (b.toInt() and 0xFF) }
                    if (n.constructed) { val v = find(n.children); if (v > 0) return v }
                }
                return 0
            }
            return find(t)
        }
    }

    fun tx(apdu: ByteArray): Resp = transport.transmit(apdu)

    fun selectApplication(): String? {
        for (aid in CANDIDATE_AIDS) {
            val r = tx(apdu(0xA4, 0x04, 0x00, hex(aid)))
            if (r.sw == 0x9000 || r.sw shr 8 == 0x61) return aid
        }
        return null
    }

    /** SELECT an EF by identifier in the current application and read it whole. The directive's form (P1=02, P2=04: FCP
     *  returned) first, then the two forms the ID card answers to. */
    fun readEF(fid: Int): ByteArray {
        val id = byteArrayOf((fid shr 8).toByte(), fid.toByte())
        var fcp: ByteArray? = null
        var sw = 0
        for ((p1, p2) in listOf(0x02 to 0x04, 0x00 to 0x00, 0x00 to 0x0C)) {
            val r = tx(apdu(0xA4, p1, p2, id, if (p2 == 0x0C) null else 0))
            sw = r.sw
            if (r.sw == 0x9000) { fcp = r.data; break }
        }
        if (fcp == null) throw CardException(CardException.Kind.Other, "Select file %04X: %04X".format(fid, sw))
        val size = fcpSize(fcp)
        val limit = if (size > 0) size else 4096
        val o = java.io.ByteArrayOutputStream()
        while (o.size() < limit) {
            val n = minOf(0xE0, limit - o.size())
            val r = tx(apdu(0xB0, o.size() shr 8 and 0xFF, o.size() and 0xFF, le = n))
            if (r.sw != 0x9000 && r.sw shr 8 != 0x62) {
                if (size > 0 || o.size() == 0) throw CardException(CardException.Kind.Other, "Read %04X: %04X".format(fid, r.sw))
                break
            }
            o.write(r.data)
            if (r.data.isEmpty()) break
        }
        return o.toByteArray()
    }

    /** Unsupported = there is no registration application on the card. */
    fun read(): VehicleData {
        if (selectApplication() == null) throw CardException(CardException.Kind.Unsupported)
        val files = ArrayList<ByteArray>()
        for (fid in DATA_FILES) {
            try { files.add(readEF(fid)) } catch (e: CardException) { if (files.isEmpty()) throw e }   // B and C are optional
        }
        return VehicleParser.parse(files)
    }
}

// ---------------------------------------------------------------- diagnostics

/**
 * Diagnostic mode: on a real card, selects applications and files, lists identifiers and sizes, reads files that are
 * open and records the answers WITHOUT personal data: only structure (tags, lengths, kinds of value), never values.
 * It sends no VERIFY / PIN command of any kind.
 */
object CardDiag {
    private val KNOWN = listOf("SERID" to "F381000002534552494401", "SERIF" to "F381000002534552494601",
        "SERRP" to "F381000002534552525001", "PKCS15" to "A000000063504B43532D3135")
    private val VEHICLE = listOf("VL full (SERVL+01)" to "F381000002534552564C01", "VL prefix (SERVL)" to "F381000002534552564C",
        "VL (SERVL+040201)" to "F381000002534552564C040201",
        "eVL-001 (long)" to "A0000000183414010065564C2D303031", "eVL-001" to "A00000001865564C2D303031")
    private val VEHICLE_FILES = intArrayOf(0xD001, 0xD011, 0xD021, 0xD031, 0xD041, 0xE001, 0xE011, 0xE021, 0xC001, 0xC011, 0xC021)

    fun run(transport: CardTransport, appVersion: String, reader: String): String {
        val out = ArrayList<String>()
        fun l(s: String) { out.add(s) }
        val card = RegistrationCard(transport)
        l("Super Celik card diagnostics (no personal data: structure only, no PIN commands)")
        l("app: $appVersion   reader: $reader")
        try {
            l(""); l("== ISO discovery")
            val mf = card.tx(RegistrationCard.apdu(0xA4, 0x00, 0x00, byteArrayOf(0x3F, 0x00), 0))
            l("SELECT MF (3F00): SW=%04X data=%dB".format(mf.sw, mf.data.size))
            if (mf.sw == 0x9000 && mf.data.isNotEmpty()) dump(mf.data, "  ", true, out)
            readPlain(card, "EF.DIR 2F00", 0x2F00, out)
            readPlain(card, "EF.ATR 2F01", 0x2F01, out)
            l(""); l("== Known applications")
            for ((n, a) in KNOWN) trySelect(card, n, a, false, out)
            l(""); l("== Vehicle registration candidates (unconfirmed names)")
            for ((n, a) in VEHICLE) trySelect(card, n, a, true, out)
        } catch (e: Exception) { l("ERROR: ${e.javaClass.simpleName}: ${e.message}") }
        l(""); l("end")
        return out.joinToString("\n")
    }

    private fun trySelect(card: RegistrationCard, name: String, aid: String, files: Boolean, out: MutableList<String>) {
        val r = card.tx(RegistrationCard.apdu(0xA4, 0x04, 0x00, RegistrationCard.hex(aid), 0))
        out.add("SELECT %s %s: SW=%04X fci=%dB".format(name, aid, r.sw, r.data.size))
        if (r.sw != 0x9000) return
        if (r.data.isNotEmpty()) dump(r.data, "  fci ", true, out)
        if (files) for (fid in VEHICLE_FILES) probeFile(card, fid, out)
    }

    private fun probeFile(card: RegistrationCard, fid: Int, out: MutableList<String>) {
        val id = byteArrayOf((fid shr 8).toByte(), fid.toByte())
        var fcp: ByteArray? = null
        val tried = ArrayList<String>()
        for ((p1, p2) in listOf(0x02 to 0x04, 0x00 to 0x00, 0x00 to 0x0C)) {
            val r = card.tx(RegistrationCard.apdu(0xA4, p1, p2, id, if (p2 == 0x0C) null else 0))
            tried.add("P1=%02XP2=%02X:%04X".format(p1, p2, r.sw))
            if (r.sw == 0x9000) { fcp = r.data; break }
        }
        out.add("  file %04X: select %s".format(fid, tried.joinToString(" ")))
        if (fcp == null) return
        val size = RegistrationCard.fcpSize(fcp)
        if (fcp.isNotEmpty()) dump(fcp, "    fcp ", true, out)
        out.add("    size from fcp: ${if (size > 0) size.toString() else "n/a"}")
        val o = java.io.ByteArrayOutputStream()
        val limit = if (size > 0) minOf(size, 8192) else 4096
        var last = 0x9000
        while (o.size() < limit) {
            val r = card.tx(RegistrationCard.apdu(0xB0, o.size() shr 8 and 0xFF, o.size() and 0xFF, le = minOf(0xE0, limit - o.size())))
            last = r.sw
            if (r.sw != 0x9000 && r.sw shr 8 != 0x62) break
            o.write(r.data)
            if (r.data.isEmpty()) break
        }
        out.add("    read: %d bytes, last SW=%04X".format(o.size(), last))
        if (o.size() > 0) describe(o.toByteArray(), "    ", out)
    }

    private fun readPlain(card: RegistrationCard, name: String, fid: Int, out: MutableList<String>) {
        val s = card.tx(RegistrationCard.apdu(0xA4, 0x00, 0x0C, byteArrayOf((fid shr 8).toByte(), fid.toByte())))
        if (s.sw != 0x9000) { out.add("$name: select SW=%04X".format(s.sw)); return }
        val o = java.io.ByteArrayOutputStream()
        var last = 0x9000
        while (o.size() < 1024) {
            val b = card.tx(RegistrationCard.apdu(0xB0, o.size() shr 8 and 0xFF, o.size() and 0xFF, le = 0xE0))
            last = b.sw
            if (b.sw != 0x9000 || b.data.isEmpty()) break
            o.write(b.data)
        }
        out.add("$name: read %d bytes, last SW=%04X".format(o.size(), last))
        if (o.size() > 0) dump(o.toByteArray(), "  ", true, out)   // EF.DIR / EF.ATR hold application names, not personal data
    }

    /** Structure of a file: BER-TLV, or the ID-card record format [tag LE16][len LE16] after a 4-byte header, or statistics. */
    private fun describe(d: ByteArray, ind: String, out: MutableList<String>) {
        val t = Ber.parse(d)
        if (t != null && t.isNotEmpty() && t[0].tag >= 0x40) { out.add(ind + "BER-TLV:"); dump(d, "$ind  ", false, out); return }
        if (d.size > 8) {
            val recs = ArrayList<String>()
            var p = 4
            var good = true
            while (p + 4 <= d.size) {
                val tag = (d[p].toInt() and 0xFF) or (d[p + 1].toInt() and 0xFF shl 8)
                val len = (d[p + 2].toInt() and 0xFF) or (d[p + 3].toInt() and 0xFF shl 8)
                if (p + 4 + len > d.size) { good = false; break }
                recs.add("%04X/%d %s".format(tag, len, kind(d.copyOfRange(p + 4, p + 4 + len))))
                p += 4 + len
            }
            if (good && recs.isNotEmpty() && p == d.size) {
                out.add(ind + "records [tag LE16][len LE16] after a 4-byte header (file id %04X, declared %d bytes):".format(
                    (d[0].toInt() and 0xFF) or (d[1].toInt() and 0xFF shl 8), (d[2].toInt() and 0xFF) or (d[3].toInt() and 0xFF shl 8)))
                for (r in recs) out.add("$ind  $r")
                return
            }
        }
        out.add(ind + "unstructured: " + kind(d))
    }

    private fun dump(d: ByteArray, ind: String, showNames: Boolean, out: MutableList<String>) {
        val t = Ber.parse(d)
        if (t == null) { out.add(ind + "(not BER) " + kind(d)); return }
        dumpNodes(t, ind, showNames, out)
    }

    private fun dumpNodes(nodes: List<Tlv>, ind: String, showNames: Boolean, out: MutableList<String>) {
        for (n in nodes) {
            if (n.constructed) { out.add("$ind${n.tagHex} len=${n.value.size} constructed"); dumpNodes(n.children, "$ind  ", showNames, out) }
            // application identifiers/names and sizes are not personal; everything else is shown as a kind only
            else if (showNames && n.tag in intArrayOf(0x4F, 0x84, 0x50, 0x80, 0x81, 0x82, 0x83, 0x88))
                out.add("$ind${n.tagHex} len=${n.value.size} ${RegistrationCard.hex(n.value)}")
            else out.add("$ind${n.tagHex} len=${n.value.size} ${kind(n.value)}")
        }
    }

    /** Kind of value without the value: counts of byte classes. */
    private fun kind(v: ByteArray): String {
        if (v.isEmpty()) return "empty"
        var dig = 0; var up = 0; var lo = 0; var hi = 0; var zero = 0; var other = 0
        for (x in v) {
            val b = x.toInt() and 0xFF
            when {
                b == 0 -> zero++
                b in 0x30..0x39 -> dig++
                b in 0x41..0x5A -> up++
                b in 0x61..0x7A -> lo++
                b >= 0x80 -> hi++
                else -> other++
            }
        }
        val cls = when {
            dig == v.size -> if (v.size == 8) "digits(8, date?)" else "digits"
            zero == v.size -> "zeros"
            hi == 0 && other == 0 && zero == 0 -> "ascii-text"
            hi > 0 && other < v.size / 2 -> "text+high-bytes"
            else -> "binary"
        }
        return "$cls [digits=$dig upper=$up lower=$lo high=$hi zero=$zero other=$other]"
    }
}
