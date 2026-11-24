package com.peregond.supercelik

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Synthetic data built from the directive 1999/37/EC (as amended) and the MUP SDK table. Not from a real card. */
class VehicleParserTest {
    private fun t(tag: Int, s: String) = Ber.build(tag, s.toByteArray(Charsets.ISO_8859_1))
    private fun t(tag: Int, vararg children: ByteArray) = Ber.build(tag, children.fold(ByteArray(0)) { a, b -> a + b })
    private fun raw(tag: Int, vararg b: Int) = Ber.build(tag, ByteArray(b.size) { b[it].toByte() })

    private fun fileA(engineTag: Int = 0xA5, charset: Int = 0) =
        t(0x78, t(0x4F, "AID-TEST")) + t(0x71,
            t(0x80, "\u0001"), t(0x9F33, "SRB"), t(0x9F35, "MUP"), raw(0x9F37, charset), t(0x9F38, "123456"),
            t(0x81, "BG123AB"), t(0x82, "20150312"),
            t(0xA1, t(0xA2, t(0x83, "Petrovic"), t(0x84, "Marko"), t(0x85, "Ulica 1, Beograd"), raw(0x86, 0))),
            t(0xA3, t(0x87, "FIAT"), t(0x88, "199A"), t(0x89, "PUNTO")),
            t(0x8A, "ZFA19900000000001"), t(0xA4, t(0x8B, "1500")), t(0x8C, "1100"),
            t(0x8D, "20260312"), t(0x8E, "20250312"), t(0x8F, "e3*2001/116"),
            t(engineTag, t(0x90, "1242"), t(0x91, "44"), t(0x92, "BENZIN")),
            t(0xA6, t(0x94, "5"), t(0x95, "0")))

    @Test fun mandatoryData() {
        val v = VehicleParser.parse(listOf(fileA() + ByteArray(100)))
        assertEquals("BG123AB", v.registrationNumber)
        assertEquals("12.03.2015", v.firstRegistrationDate)
        assertEquals("12.03.2026", v.expiryDate); assertEquals("12.03.2025", v.issuingDate)
        assertEquals("FIAT", v.make); assertEquals("199A", v.type); assertEquals("PUNTO", v.commercialDescription)
        assertEquals("ZFA19900000000001", v.vin)
        assertEquals("1500", v.maxLadenMass); assertEquals("1100", v.mass)
        assertEquals("1242", v.engineCapacity); assertEquals("44", v.maxNetPower); assertEquals("BENZIN", v.fuelType)
        assertEquals("5", v.seats); assertEquals("0", v.standingPlaces)
        assertEquals("SRB", v.stateIssuing); assertEquals("123456", v.unambiguousNumber)
        assertEquals("e3*2001/116", v.typeApprovalNumber)
        assertTrue(v.unknownTags.isEmpty()); assertFalse(v.signatureVerified)
    }

    @Test fun holderBecomesOwner() {
        val v = VehicleParser.parse(listOf(fileA()))
        assertEquals("Petrovic", v.ownerSurname); assertEquals("Marko", v.ownerName); assertEquals("Ulica 1, Beograd", v.ownerAddress)
    }

    @Test fun engineUnderTag5A() {
        val v = VehicleParser.parse(listOf(fileA(engineTag = 0x5A)))
        assertEquals("1242", v.engineCapacity); assertEquals("BENZIN", v.fuelType)
    }

    @Test fun optionalAndNationalFiles() {
        val b = t(0x78, t(0x4F, "AID-TEST")) + t(0x72,
            t(0xA1, t(0xA7, t(0x83, "Vlasnik"), t(0x84, "Ime"), t(0x85, "Adresa vlasnika")),
                    t(0xA9, t(0x83, "Korisnik"), t(0x84, "Ime2"), t(0x85, "Adresa korisnika"))),
            t(0x98, "M1"), t(0x99, "2"), t(0x9F24, "CRVENA"))
        val c = t(0x78, t(0x4F, "AID-TEST")) + t(0x72, t(0xC1, "20300101"), t(0xC2, "0101990710000"), t(0xC3, "0202985710001"),
            t(0xC4, "480"), t(0xC5, "2014"), t(0xC9, "SN-0001"))
        val v = VehicleParser.parse(listOf(fileA(), b, c))
        assertEquals("Vlasnik", v.ownerSurname); assertEquals("Adresa korisnika", v.userAddress)
        assertEquals("M1", v.category); assertEquals("2", v.axles); assertEquals("CRVENA", v.colour)
        assertEquals("20300101", v.saleBan); assertEquals("0101990710000", v.ownerPersonalNo)
        assertEquals("0202985710001", v.userPersonalNo); assertEquals("480", v.load)
        assertEquals("2014", v.yearOfProduction); assertEquals("SN-0001", v.serialNumber)
    }

    @Test fun cyrillic8859_5() {
        // "Петровић" in ISO 8859-5
        val f = t(0x71, raw(0x9F37, 1), t(0xA1, Ber.build(0xA7, raw(0x83, 0xBF, 0xD5, 0xE2, 0xE0, 0xDE, 0xD2, 0xD8, 0xFB))))
        val v = VehicleParser.parse(listOf(f))
        assertEquals("Петровић", v.ownerSurname); assertEquals(1, v.charsetTag)
    }

    @Test fun utf8Accepted() {
        val v = VehicleParser.parse(listOf(t(0x71, Ber.build(0x81, "Ćuprija".toByteArray(Charsets.UTF_8)))))
        assertEquals("Ćuprija", v.registrationNumber)
    }

    @Test fun longLengthAndTwoByteTag() {
        val big = "A".repeat(300)
        val v = VehicleParser.parse(listOf(t(0x71, t(0xA1, t(0xA7, t(0x85, big))))))
        assertEquals(300, v.ownerAddress.length)
        assertEquals(0x9F33, Ber.parse(raw(0x9F33, 0x41))!![0].tag)
    }

    @Test fun unknownTagsWithoutValues() {
        val v = VehicleParser.parse(listOf(t(0x71, t(0x81, "X"), t(0xDF55, "secret"))))
        assertEquals(listOf("DF55/6"), v.unknownTags)
    }

    @Test fun garbageDoesNotCrash() {
        assertNull(Ber.parse(byteArrayOf(0x71, 0x05, 1, 2)))
        assertEquals("", VehicleParser.parse(listOf(byteArrayOf(0x71, 0x05, 1, 2), ByteArray(0), null)).registrationNumber)
    }

    @Test fun rows() {
        val rows = VehicleRows.build(VehicleRows.demo())
        assertTrue(rows.any { it.first == "vRegNo" && it.second == "BG 123-AB" })
        assertFalse(rows.any { it.first == "vUser" })
        assertFalse(VehicleRows.build(VehicleRows.demo(), includeJmbg = false).any { it.first == "vOwnerJmbg" })
    }

    /** A card that answers like the registration card would: selects the application and returns the files. */
    @Test fun readsThroughATransport() {
        val files = mapOf(0xD001 to fileA() + ByteArray(20), 0xD011 to t(0x78, t(0x4F, "X")) + t(0x72, t(0x98, "M1")))
        var current = 0
        val transport = object : CardTransport {
            override fun transmit(apdu: ByteArray): Resp {
                val ins = apdu[1].toInt() and 0xFF
                if (ins == 0xA4 && apdu[2].toInt() == 0x04) return Resp(ByteArray(0), 0x9000)
                if (ins == 0xA4) {
                    current = (apdu[5].toInt() and 0xFF shl 8) or (apdu[6].toInt() and 0xFF)
                    val f = files[current] ?: return Resp(ByteArray(0), 0x6A82)
                    return Resp(Ber.build(0x62, Ber.build(0x80, byteArrayOf((f.size shr 8).toByte(), f.size.toByte()))), 0x9000)
                }
                val f = files[current]!!
                val off = (apdu[2].toInt() and 0xFF shl 8) or (apdu[3].toInt() and 0xFF)
                val n = minOf(apdu[4].toInt() and 0xFF, f.size - off)
                return Resp(f.copyOfRange(off, off + n), 0x9000)
            }
        }
        val v = RegistrationCard(transport).read()
        assertEquals("BG123AB", v.registrationNumber); assertEquals("M1", v.category)
    }

    @Test fun noRegistrationApplication() {
        val transport = object : CardTransport { override fun transmit(apdu: ByteArray) = Resp(ByteArray(0), 0x6A82) }
        try { RegistrationCard(transport).read(); org.junit.Assert.fail() } catch (e: CardException) { assertEquals(CardException.Kind.Unsupported, e.kind) }
    }

    @Test fun diagnosticsLogHasNoValues() {
        val secret = "TOPSECRETNAME"
        val f = t(0x71, t(0x81, secret))
        val transport = object : CardTransport {
            override fun transmit(apdu: ByteArray): Resp {
                val ins = apdu[1].toInt() and 0xFF
                if (ins == 0xA4 && apdu[2].toInt() == 0x04) return Resp(ByteArray(0), 0x9000)
                if (ins == 0xA4) return Resp(Ber.build(0x62, Ber.build(0x80, byteArrayOf(0, f.size.toByte()))), 0x9000)
                val off = (apdu[2].toInt() and 0xFF shl 8) or (apdu[3].toInt() and 0xFF)
                return if (off >= f.size) Resp(ByteArray(0), 0x6B00) else Resp(f.copyOfRange(off, f.size), 0x9000)
            }
        }
        val log = CardDiag.run(transport, "1.6.0", "test")
        assertFalse(log.contains(secret)); assertTrue(log.contains("len=${secret.length}"))
    }
}
