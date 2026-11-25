package com.peregond.supercelik

// Health insurance card (KZO, RFZO): data model, block parser, rows for the screen and the reader.
// STATUS: written from the analysis of the official RFZO reader and its middleware (docs/health-card-protocol.md).
// Confirmed by that analysis ONLY, NOT yet against a real card. The tag <-> name assignment is inferred from the declaration
// order and the field sizes. Same logic as windows/SerbiaID.Windows/HealthData.cs + HealthCard.cs and Sources/SerbiaID/HealthCard.swift.

class HealthData(
    // block 0D01 document
    var insurerName: String = "", var insurerId: String = "", var cardId: String = "", var issueDate: String = "",
    var expiryDate: String = "", var chipSerial: String = "", var printLanguage: String = "",
    // block 0D02 fixed personal
    var insurantNumber: String = "", var surname: String = "", var surnameLatin: String = "", var givenName: String = "",
    var givenNameLatin: String = "", var dateOfBirth: String = "",
    // block 0D03 card validity
    var permanent: Boolean = false,
    // block 0D04 administrative
    var parentName: String = "", var parentNameLatin: String = "", var gender: String = "", var personalNumber: String = "",
    var street: String = "", var postNumber: String = "", var municipality: String = "", var place: String = "",
    var streetCode: String = "", var houseNumber: String = "", var entrance: String = "", var apartment: String = "",
    var registrationNumber: String = "", var basisCode: String = "", var basisDescription: String = "",
    var carrierRelationship: String = "", var carrierFamilyMember: String = "", var carrierPersonalNumber: String = "",
    var carrierInsurantNumber: String = "", var carrierSurname: String = "", var carrierSurnameLatin: String = "",
    var carrierGivenName: String = "", var carrierGivenNameLatin: String = "",
    var insuredFrom: String = "", var countryCode: String = "", var country: String = "", var bookletIssuerCode: String = "",
    var insurerBranch: String = "", var insurerOffice: String = "",
    var taxpayerName: String = "", var taxpayerResidence: String = "", var taxpayerNumber: String = "",
    var taxpayerIdNumber: String = "", var taxpayerActivityCode: String = "", var participationFree: String = "",
) {
    /** Blocks that could not be read, and tags the table does not know (structure only, no values). */
    val problems = ArrayList<String>()
    val unknownTags = ArrayList<String>()

    val fullName: String get() = "$givenName $surname".trim()
    val carrierFullName: String get() = "$carrierGivenName $carrierSurname".trim()
}

object HealthParser {
    const val DOCUMENT = 0x0D01
    const val FIXED = 0x0D02
    const val CARD = 0x0D03
    const val ADMIN = 0x0D04

    private enum class Kind { ASCII, UTF16, DATE, NUMBER }

    private val kinds: Map<Int, Kind> = mapOf(
        0x611 to Kind.UTF16, 0x612 to Kind.ASCII, 0x613 to Kind.ASCII, 0x615 to Kind.DATE, 0x616 to Kind.DATE, 0x617 to Kind.ASCII, 0x618 to Kind.ASCII,
        0x621 to Kind.ASCII, 0x622 to Kind.UTF16, 0x623 to Kind.UTF16, 0x624 to Kind.UTF16, 0x625 to Kind.UTF16, 0x626 to Kind.DATE,
        0x630 to Kind.ASCII, 0x631 to Kind.DATE, 0x632 to Kind.DATE, 0x633 to Kind.NUMBER,
        0x640 to Kind.ASCII, 0x641 to Kind.UTF16, 0x642 to Kind.UTF16, 0x643 to Kind.NUMBER, 0x644 to Kind.ASCII, 0x645 to Kind.UTF16,
        0x646 to Kind.ASCII, 0x647 to Kind.UTF16, 0x648 to Kind.UTF16, 0x649 to Kind.ASCII, 0x64A to Kind.UTF16, 0x64B to Kind.UTF16,
        0x64C to Kind.UTF16, 0x64D to Kind.ASCII, 0x64E to Kind.ASCII, 0x64F to Kind.UTF16, 0x650 to Kind.UTF16, 0x651 to Kind.NUMBER,
        0x652 to Kind.ASCII, 0x653 to Kind.ASCII, 0x654 to Kind.UTF16, 0x655 to Kind.UTF16, 0x656 to Kind.UTF16, 0x657 to Kind.UTF16,
        0x658 to Kind.DATE, 0x659 to Kind.ASCII, 0x65A to Kind.UTF16, 0x65B to Kind.ASCII, 0x65C to Kind.UTF16, 0x65D to Kind.UTF16,
        0x65E to Kind.UTF16, 0x65F to Kind.UTF16, 0x660 to Kind.ASCII, 0x661 to Kind.ASCII, 0x662 to Kind.ASCII, 0x663 to Kind.ASCII,
    )

    private fun u8(b: Byte) = b.toInt() and 0xFF

    /** The elements of a block file: header [id LE16][length LE16], then [tag LE16][length LE16][value]...
     *  null if the header does not match [expectedId] or the declared length is more than the file holds. */
    fun records(file: ByteArray?, expectedId: Int): Map<Int, ByteArray>? {
        if (file == null || file.size < 4) return null
        if ((u8(file[0]) or (u8(file[1]) shl 8)) != expectedId) return null
        val declared = u8(file[2]) or (u8(file[3]) shl 8)
        if (declared > file.size - 4) return null
        val d = LinkedHashMap<Int, ByteArray>()
        var p = 4
        val end = 4 + declared
        while (p + 4 <= end) {
            val tag = u8(file[p]) or (u8(file[p + 1]) shl 8)
            val len = u8(file[p + 2]) or (u8(file[p + 3]) shl 8)
            if (p + 4 + len > end) break
            d[tag] = file.copyOfRange(p + 4, p + 4 + len)
            p += 4 + len
        }
        return d
    }

    fun value(d: Map<Int, ByteArray>, tag: Int): String {
        val b = d[tag] ?: return ""
        if (b.isEmpty()) return ""
        val kind = kinds[tag] ?: Kind.ASCII
        if (kind == Kind.NUMBER) {
            var n = 0L
            for (i in minOf(b.size, 8) - 1 downTo 0) n = n shl 8 or u8(b[i]).toLong()
            return n.toString()
        }
        // UTF-16LE needs an even length; if a card hands odd bytes, read them as UTF-8 rather than lose the text
        val s = (if (kind == Kind.UTF16 && b.size % 2 == 0) String(b, Charsets.UTF_16LE) else String(b, Charsets.UTF_8)).trim('\u0000', ' ')
        return if (kind == Kind.DATE) date(s) else s
    }

    /** The card stores DDMMYYYY; shown as DD.MM.YYYY like the ID card. */
    fun date(s: String): String =
        if (s.length == 8 && s.all { it in '0'..'9' }) s.substring(0, 2) + "." + s.substring(2, 4) + "." + s.substring(4) else s

    /** Builds the data from the four block files (null = block not read). Never throws on content. */
    fun parse(doc: ByteArray?, fix: ByteArray?, card: ByteArray?, admin: ByteArray?): HealthData {
        val h = HealthData()
        val rec = HashMap<Int, Map<Int, ByteArray>>()
        for ((id, f) in listOf(DOCUMENT to doc, FIXED to fix, CARD to card, ADMIN to admin)) {
            val name = "%04X".format(id)
            if (f == null) { h.problems.add("$name: not read"); continue }
            val r = records(f, id)
            if (r == null) { h.problems.add("$name: bad header"); continue }
            rec[id] = r
            for ((t, v) in r) if (t !in kinds) h.unknownTags.add("$name/%03X/%d".format(t, v.size))
        }
        rec[DOCUMENT]?.let { d ->
            h.insurerName = value(d, 0x611); h.insurerId = value(d, 0x612); h.cardId = value(d, 0x613)
            h.issueDate = value(d, 0x615); h.expiryDate = value(d, 0x616); h.chipSerial = value(d, 0x617); h.printLanguage = value(d, 0x618)
        }
        rec[FIXED]?.let { d ->
            h.insurantNumber = value(d, 0x621); h.surname = value(d, 0x622); h.surnameLatin = value(d, 0x623)
            h.givenName = value(d, 0x624); h.givenNameLatin = value(d, 0x625); h.dateOfBirth = value(d, 0x626)
        }
        rec[CARD]?.let { d ->
            if (h.cardId.isEmpty()) h.cardId = value(d, 0x630)
            if (h.issueDate.isEmpty()) h.issueDate = value(d, 0x631)
            val exp = value(d, 0x632)
            if (exp.isNotEmpty()) h.expiryDate = exp          // the validity block is the one that changes when the card is renewed
            h.permanent = value(d, 0x633) == "1"
        }
        rec[ADMIN]?.let { d ->
            h.parentName = value(d, 0x641); h.parentNameLatin = value(d, 0x642)
            val g = value(d, 0x643); h.gender = if (g == "1") "M" else if (g == "2") "Ž" else g
            h.personalNumber = value(d, 0x644); h.street = value(d, 0x645); h.postNumber = value(d, 0x646)
            h.municipality = value(d, 0x647); h.place = value(d, 0x648); h.streetCode = value(d, 0x649)
            h.houseNumber = value(d, 0x64A); h.entrance = value(d, 0x64B); h.apartment = value(d, 0x64C)
            h.registrationNumber = value(d, 0x64D); h.basisCode = value(d, 0x64E); h.basisDescription = value(d, 0x64F)
            h.carrierRelationship = value(d, 0x650); h.carrierFamilyMember = value(d, 0x651)
            h.carrierPersonalNumber = value(d, 0x652); h.carrierInsurantNumber = value(d, 0x653)
            h.carrierSurname = value(d, 0x654); h.carrierSurnameLatin = value(d, 0x655)
            h.carrierGivenName = value(d, 0x656); h.carrierGivenNameLatin = value(d, 0x657)
            h.insuredFrom = value(d, 0x658); h.countryCode = value(d, 0x659); h.country = value(d, 0x65A)
            h.bookletIssuerCode = value(d, 0x65B); h.insurerBranch = value(d, 0x65C); h.insurerOffice = value(d, 0x65D)
            h.taxpayerName = value(d, 0x65E); h.taxpayerResidence = value(d, 0x65F); h.taxpayerNumber = value(d, 0x660)
            h.taxpayerIdNumber = value(d, 0x661); h.taxpayerActivityCode = value(d, 0x662); h.participationFree = value(d, 0x663)
        }
        return h
    }
}

object HealthRows {
    /** Hidden behind the eye like the ID card's personal number and address. */
    val sensitive = setOf("hLbo", "hJmbg", "hAddress", "hCardId", "hRfzoNo", "hCarrierName", "hCarrierLbo", "hCarrierJmbg", "hTaxPib", "hTaxId")

    fun address(h: HealthData): String {
        val parts = arrayListOf("${h.street} ${h.houseNumber}".trim())
        if (h.entrance.isNotEmpty()) parts.add("ul. " + h.entrance)
        if (h.apartment.isNotEmpty()) parts.add("stan " + h.apartment)
        parts.add("${h.postNumber} ${h.place}".trim()); parts.add(h.municipality); parts.add(h.country)
        return parts.filter { it.isNotEmpty() }.joinToString(", ")
    }

    /** The insured person, the card, the insurance, the holder and the payer when present. */
    fun sections(h: HealthData, includeJmbg: Boolean = true): List<Pair<String, List<Pair<String, String>>>> {
        fun g(vararg kv: Pair<String, String>) = kv.filter { it.second.isNotEmpty() }
        val person = g("hSurname" to h.surname, "hGivenName" to h.givenName, "hParent" to h.parentName, "hDob" to h.dateOfBirth, "hSex" to h.gender,
            "hJmbg" to (if (includeJmbg) h.personalNumber else ""), "hLbo" to h.insurantNumber, "hAddress" to address(h))
        val card = g("hInsurer" to h.insurerName, "hCardId" to h.cardId, "hIssued" to h.issueDate,
            "hValidUntil" to (if (h.permanent) "" else h.expiryDate), "hPermanent" to (if (h.permanent) "✔" else ""), "hIssuerCode" to h.bookletIssuerCode)
        val ins = g("hBasis" to listOf(h.basisCode, h.basisDescription).filter { it.isNotEmpty() }.joinToString(" — "),
            "hInsuredFrom" to h.insuredFrom, "hBranch" to h.insurerBranch, "hOffice" to h.insurerOffice,
            "hRfzoNo" to h.registrationNumber, "hExempt" to h.participationFree)
        val carrier = g("hCarrierName" to h.carrierFullName, "hCarrierLbo" to h.carrierInsurantNumber,
            "hCarrierJmbg" to (if (includeJmbg) h.carrierPersonalNumber else ""), "hRelation" to h.carrierRelationship, "hFamilyMember" to h.carrierFamilyMember)
        val tax = g("hTaxName" to h.taxpayerName, "hTaxResidence" to h.taxpayerResidence, "hTaxPib" to h.taxpayerNumber,
            "hTaxId" to h.taxpayerIdNumber, "hTaxActivity" to h.taxpayerActivityCode)
        return listOf("hSecPerson" to person.toList(), "hSecCard" to card.toList(), "hSecInsurance" to ins.toList(),
            "hSecCarrier" to carrier.toList(), "hSecTaxpayer" to tax.toList())
    }

    fun build(h: HealthData, includeJmbg: Boolean = true): List<Pair<String, String>> = sections(h, includeJmbg).flatMap { it.second }

    /** Fictional data for demo mode, screenshots and the tests. */
    fun demo() = HealthData(
        insurerName = "REPUBLIČKI FOND ZA ZDRAVSTVENO OSIGURANJE", insurerId = "100000000", cardId = "00000000001",
        issueDate = "01.01.2024", expiryDate = "01.01.2029", chipSerial = "0000000000000000", printLanguage = "sr",
        insurantNumber = "00000000001", surname = "PETROVIĆ", surnameLatin = "PETROVIC", givenName = "MARKO", givenNameLatin = "MARKO",
        dateOfBirth = "01.01.1990", parentName = "JOVAN", parentNameLatin = "JOVAN", gender = "M", personalNumber = "0101990710000",
        street = "Knez Mihailova", houseNumber = "1", postNumber = "11000", place = "Beograd", municipality = "Stari Grad", country = "Srbija",
        countryCode = "688", registrationNumber = "0000000001", basisCode = "010", basisDescription = "Zaposleni", insuredFrom = "01.01.2015",
        insurerBranch = "Filijala za grad Beograd", insurerOffice = "Ispostava Stari Grad", bookletIssuerCode = "001",
        taxpayerName = "PRIMER D.O.O.", taxpayerResidence = "Beograd", taxpayerNumber = "100000000", taxpayerIdNumber = "0000000000000",
        taxpayerActivityCode = "6201",
    )
}

/** Reads the health card through the USB reader's APDU channel. No PIN is used and no signature is checked, like the official program. */
class HealthCard(private val transport: CardTransport) {
    companion object {
        /** "F381000002" + "SERVSZK" + 01 (card type 1, the one the official reader asks for) and the second type's name ("SERSOVOZK"). */
        val AIDS = listOf("F38100000253455256535A4B01", "F381000002534552534F564F5A4B01")
        val BLOCKS = intArrayOf(HealthParser.DOCUMENT, HealthParser.FIXED, HealthParser.CARD, HealthParser.ADMIN)
    }

    /** Like transmit, but follows T=0 "61xx" (GET RESPONSE). */
    private fun tx(apdu: ByteArray): Resp {
        var r = transport.transmit(apdu)
        val data = java.io.ByteArrayOutputStream()
        data.write(r.data)
        while (r.sw shr 8 == 0x61) {
            r = transport.transmit(byteArrayOf(0x00, 0xC0.toByte(), 0x00, 0x00, (r.sw and 0xFF).toByte()))
            data.write(r.data)
        }
        return Resp(data.toByteArray(), r.sw)
    }

    /** Selects the applet of a health card; returns its AID, or null if the card has none of them. */
    fun selectApplet(): String? {
        for (aid in AIDS) {
            val r = transport.transmit(RegistrationCard.apdu(0xA4, 0x04, 0x00, RegistrationCard.hex(aid)))
            if (r.sw == 0x9000 || r.sw shr 8 == 0x61) return aid
        }
        return null
    }

    private fun fail(what: String, sw: Int): Nothing = throw CardException(CardException.Kind.Other, "%s: %04X".format(what, sw))

    /** One block: select the applet, select the file (00 A4 00 00 02 <id>), read the 4-byte header, then the rest in chunks of 0x80. */
    fun readBlock(aid: String, id: Int): ByteArray {
        val sel = tx(RegistrationCard.apdu(0xA4, 0x04, 0x00, RegistrationCard.hex(aid)))
        if (sel.sw != 0x9000) fail("Select applet", sel.sw)
        val fid = byteArrayOf((id shr 8).toByte(), id.toByte())
        var r = tx(RegistrationCard.apdu(0xA4, 0x00, 0x00, fid))
        if (r.sw != 0x9000) r = tx(RegistrationCard.apdu(0xA4, 0x00, 0x0C, fid))   // some cards answer only to the "no response" form
        if (r.sw != 0x9000) fail("Select file %04X".format(id), r.sw)
        val fileSize = if (r.data.size >= 4) ((r.data[2].toInt() and 0xFF) shl 8) or (r.data[3].toInt() and 0xFF) else 0   // bytes 2-3, big-endian
        if (fileSize in 1..3) fail("File %04X is too small".format(id), 0x6700)

        r = transport.transmit(RegistrationCard.apdu(0xB0, 0x00, 0x00, le = 4))
        if (r.sw != 0x9000 || r.data.size != 4) fail("Read header %04X".format(id), r.sw)
        val got = (r.data[0].toInt() and 0xFF) or ((r.data[1].toInt() and 0xFF) shl 8)
        if (got != id) fail("File %04X holds another block".format(id), 0x6A82)
        val total = 4 + ((r.data[2].toInt() and 0xFF) or ((r.data[3].toInt() and 0xFF) shl 8))
        if (total > 16384 || (fileSize > 0 && total > fileSize)) fail("File %04X: bad length".format(id), 0x6700)
        val data = java.io.ByteArrayOutputStream()
        data.write(r.data)
        while (data.size() < total) {
            val o = data.size()
            val n = minOf(0x80, total - o)
            r = transport.transmit(RegistrationCard.apdu(0xB0, o shr 8 and 0xFF, o and 0xFF, le = n))
            if (r.sw != 0x9000 || r.data.isEmpty()) fail("Read %04X".format(id), r.sw)
            data.write(r.data)
        }
        return data.toByteArray()
    }

    /** Unsupported = there is no health card applet on the card. */
    fun read(): HealthData {
        val aid = selectApplet() ?: throw CardException(CardException.Kind.Unsupported)
        val files = arrayOfNulls<ByteArray>(BLOCKS.size)
        val problems = ArrayList<String>()
        for ((i, id) in BLOCKS.withIndex()) {
            try { files[i] = readBlock(aid, id) } catch (e: CardException) {
                if (e.kind == CardException.Kind.Lost || e.kind == CardException.Kind.NoCard) throw e
                problems.add("%04X: %s".format(id, e.message))
            }
        }
        // the names are the minimum: without the fixed personal block there is nothing worth showing
        if (files[1] == null) throw CardException(CardException.Kind.Other, problems.firstOrNull() ?: "No health card data")
        val h = HealthParser.parse(files[0], files[1], files[2], files[3])
        h.problems.addAll(problems)
        return h
    }
}
