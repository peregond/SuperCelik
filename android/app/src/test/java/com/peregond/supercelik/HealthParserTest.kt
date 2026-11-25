package com.peregond.supercelik

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Synthetic blocks built from docs/health-card-protocol.md (the layout recovered from the official reader). Not from a real card. */
class HealthParserTest {
    private fun u(s: String) = s.toByteArray(Charsets.UTF_16LE)
    private fun a(s: String) = s.toByteArray(Charsets.US_ASCII)
    private fun n(v: Int, size: Int) = ByteArray(size) { (v shr (8 * it)).toByte() }
    private fun el(tag: Int, v: ByteArray) = byteArrayOf(tag.toByte(), (tag shr 8).toByte(), v.size.toByte(), (v.size shr 8).toByte()) + v
    private fun block(id: Int, vararg els: ByteArray): ByteArray {
        val body = els.fold(ByteArray(0)) { x, y -> x + y }
        return byteArrayOf(id.toByte(), (id shr 8).toByte(), body.size.toByte(), (body.size shr 8).toByte()) + body
    }

    private fun doc() = block(0x0D01, el(0x611, u("RFZO")), el(0x612, a("100000000")), el(0x613, a("00000000001")), el(0x615, a("01012024")),
        el(0x616, a("01012029")), el(0x617, a("0123456789ABCDEF")), el(0x618, a("sr")))
    private fun fix() = block(0x0D02, el(0x621, a("00000000001")), el(0x622, u("Петровић")), el(0x623, u("Petrovic")),
        el(0x624, u("Марко")), el(0x625, u("Marko")), el(0x626, a("01011990")))
    private fun card(permanent: Boolean = false, expiry: Boolean = true) = block(0x0D03, el(0x630, a("00000000001")), el(0x631, a("01012024")),
        if (expiry) el(0x632, a("31122030")) else ByteArray(0), el(0x633, n(if (permanent) 1 else 0, 1)))
    private fun admin() = block(0x0D04, el(0x640, a("00000000001")), el(0x641, u("Јован")), el(0x643, n(2, 2)), el(0x644, a("0101990710000")),
        el(0x645, u("Кнез Михаилова")), el(0x646, a("11000")), el(0x648, u("Београд")), el(0x64A, u("1")),
        el(0x64E, a("010")), el(0x64F, u("Запослени")), el(0x658, a("01012015")), el(0x65A, u("Србија")))

    @Test fun parsesAllBlocks() {
        val h = HealthParser.parse(doc(), fix(), card(), admin())
        assertTrue(h.problems.isEmpty()); assertTrue(h.unknownTags.isEmpty())
        assertEquals("RFZO", h.insurerName); assertEquals("00000000001", h.cardId)
        assertEquals("01.01.2024", h.issueDate)
        assertEquals("31.12.2030", h.expiryDate)            // the validity block wins over the document block
        assertEquals("0123456789ABCDEF", h.chipSerial)
        assertEquals("Петровић", h.surname); assertEquals("Petrovic", h.surnameLatin); assertEquals("Марко Петровић", h.fullName)
        assertEquals("01.01.1990", h.dateOfBirth); assertEquals("00000000001", h.insurantNumber)
        assertEquals("Ž", h.gender); assertEquals("0101990710000", h.personalNumber); assertEquals("Јован", h.parentName)
        assertEquals("010", h.basisCode); assertEquals("Запослени", h.basisDescription)
        assertEquals("01.01.2015", h.insuredFrom); assertEquals("Србија", h.country)
        assertFalse(h.permanent)
    }

    @Test fun genderNumberMapsToLetters() {
        assertEquals("M", HealthParser.parse(doc(), fix(), card(), block(0x0D04, el(0x643, n(1, 2)))).gender)
    }

    @Test fun permanentCardHasNoValidUntilRow() {
        val h = HealthParser.parse(doc(), fix(), card(true, false), admin())
        assertTrue(h.permanent)
        assertEquals("01.01.2029", h.expiryDate)            // falls back to the document block
        val keys = HealthRows.build(h).map { it.first }
        assertFalse("hValidUntil" in keys); assertTrue("hPermanent" in keys)
    }

    @Test fun wrongBlockIdIsReportedNotParsed() {
        val wrong = fix().also { it[0] = 0x09 }
        val h = HealthParser.parse(doc(), wrong, card(), admin())
        assertTrue(h.problems.any { it.startsWith("0D02") })
        assertEquals("", h.surname)
    }

    @Test fun declaredLengthLargerThanFileIsRejected() {
        val f = fix().also { it[2] = 0xFF.toByte(); it[3] = 0x7F }
        assertNull(HealthParser.records(f, 0x0D02))
        assertEquals(4, HealthParser.parse(null, f, null, null).problems.size)
    }

    @Test fun missingBlockLeavesTheRest() {
        val h = HealthParser.parse(doc(), fix(), null, null)
        assertEquals("Марко", h.givenName); assertEquals("RFZO", h.insurerName); assertEquals("01.01.2029", h.expiryDate)
        assertEquals(2, h.problems.size)
    }

    @Test fun unknownTagsAreLoggedByStructureOnly() {
        val h = HealthParser.parse(null, block(0x0D02, el(0x6FF, a("secret"))), null, null)
        assertTrue("0D02/6FF/6" in h.unknownTags)
        assertFalse(h.unknownTags.any { "secret" in it })
    }

    @Test fun oddLengthUtf16FallsBackToUtf8() {
        assertEquals("Ana", HealthParser.parse(null, block(0x0D02, el(0x624, a("Ana"))), null, null).givenName)
    }

    @Test fun rowsAreGroupedAndHideEmptyOnes() {
        val h = HealthParser.parse(doc(), fix(), card(), admin())
        val titles = HealthRows.sections(h).filter { it.second.isNotEmpty() }.map { it.first }
        assertEquals("hSecPerson", titles.first())
        assertFalse("hSecCarrier" in titles); assertFalse("hSecTaxpayer" in titles)
        assertFalse(HealthRows.build(h, includeJmbg = false).any { it.first == "hJmbg" })
        assertTrue(HealthRows.build(h).any { it.first == "hAddress" && "Кнез Михаилова 1" in it.second })
    }

    @Test fun demoHasEverySection() {
        val titles = HealthRows.sections(HealthRows.demo()).filter { it.second.isNotEmpty() }.map { it.first }
        assertEquals(listOf("hSecPerson", "hSecCard", "hSecInsurance", "hSecTaxpayer"), titles)
    }
}
