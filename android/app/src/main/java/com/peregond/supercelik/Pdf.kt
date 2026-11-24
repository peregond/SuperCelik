package com.peregond.supercelik

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Typeface
import android.graphics.pdf.PdfDocument
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/** The MUP printout (see MupPrintLayout) as a one-page A4 PDF in the cache folder. */
object Pdf {
    fun create(context: Context, p: PersonalData, includeJmbg: Boolean): File {
        val doc = PdfDocument()
        val page = doc.startPage(PdfDocument.PageInfo.Builder(595, 842, 1).create())
        MupPrintLayout(p, includeJmbg).draw(page.canvas)
        doc.finishPage(page)
        val dir = File(context.cacheDir, "exports").apply { mkdirs() }
        val f = File(dir, "SuperCelik.pdf")
        f.outputStream().use { doc.writeTo(it) }
        doc.close()
        return f
    }

    /** The vehicle registration card data as a plain one-page A4 table (not a copy of any official form). */
    fun createVehicle(context: Context, v: VehicleData, includeJmbg: Boolean): File {
        val doc = PdfDocument()
        val page = doc.startPage(PdfDocument.PageInfo.Builder(595, 842, 1).create())
        drawVehicle(context, page.canvas, v, includeJmbg)
        doc.finishPage(page)
        val dir = File(context.cacheDir, "exports").apply { mkdirs() }
        val f = File(dir, "SuperCelik.pdf")
        f.outputStream().use { doc.writeTo(it) }
        doc.close()
        return f
    }

    /** Layout after the printout of MUP's own reader "Čitač saobraćajne dozvole"; same numbers as VehiclePrintSpec (C#) and VehiclePrintLayout (Swift). */
    private fun drawVehicle(context: Context, c: Canvas, v: VehicleData, includeJmbg: Boolean) {
        c.drawColor(Color.WHITE)
        val d = CardText::date
        fun dash(s: String) = s.ifEmpty { "-" }
        /** y is the vertical centre of the first line. */
        fun text(s: String, x: Float, y: Float, size: Float = 10.5f, bold: Boolean = true, underline: Boolean = false, width: Int = 520, color: Int = Color.BLACK) {
            if (s.isEmpty()) return
            val p = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
                typeface = if (bold) Typeface.create(Typeface.SANS_SERIF, Typeface.BOLD) else Typeface.SANS_SERIF
                textSize = size; this.color = color; isUnderlineText = underline
            }
            val l = StaticLayout.Builder.obtain(s, 0, s.length, p, width).setAlignment(Layout.Alignment.ALIGN_NORMAL).build()
            c.save(); c.translate(x, y - size * 0.6f - 1f); l.draw(c); c.restore()
        }
        val left = 41.5f; val right = 350f
        text("Čitač saobraćajne dozvole", 45f, 64f, 22f)
        c.drawRect(39f, 84f - 1.5f, 546f, 84f + 1.5f, Paint().apply { color = Color.BLACK })
        text("Registarska oznaka: " + v.registrationNumber, 42.5f, 119f, 18f)

        text("Datum izdavanja: " + d(v.issuingDate), left, 171f)
        text("Važi do: " + d(v.expiryDate), right, 171f, bold = false, underline = true)
        text("Saobraćajnu izdao: " + v.stateIssuing, left, 190f)
        text("Zabrana otuđenja: " + d(v.saleBan), right, 190f)
        text(v.authorityIssuing, left, 213f, width = 470)
        text("Broj saobraćajne: " + v.unambiguousNumber, left, 252f)
        text("Serijski broj: " + v.serialNumber, left, 272f)

        text("Podaci o vlasniku", left, 303f, 16.5f, bold = false, underline = true)
        val owner = listOf(
            "Vlasnik: " + v.ownerSurname, "Ime vlasnika: " + v.ownerName, "Adresa vlasnika: " + v.ownerAddress,
            "Jmbg vlasnika: " + (if (includeJmbg) v.ownerPersonalNo else ""),
            "Korisnik: " + v.userSurname, "Ime korisnika: " + v.userName, "Adresa korisnika: " + v.userAddress,
            "Jmbg korisnika: " + (if (includeJmbg) v.userPersonalNo else ""),
        )
        owner.forEachIndexed { i, s -> text(s, left, 327.6f + 19.2f * i, width = 500) }

        text("Podaci o vozilu", left, 495.4f, 16.5f, bold = false, underline = true)
        val car = listOf(
            "Datum prve registracije: " + d(v.firstRegistrationDate),
            "Marka: " + v.make + "   Model: " + v.commercialDescription,
            "Tip: " + dash(v.type) + "   Homologacijska oznaka: " + dash(v.typeApprovalNumber),
            "Boja: " + v.colour, "Broj šasije: " + v.vin, "Broj motora: " + v.engineNumber,
            "Snaga motora: " + v.maxNetPower, "Odnos snaga/masa: " + v.powerWeightRatio,
            "Kategorija: " + v.category, "Pogonsko gorivo: " + v.fuelType, "Broj mesta za sedenje: " + v.seats,
        )
        car.forEachIndexed { i, s -> text(s, left, 516.6f + 19.1f * i) }
        text("Godina proizvodnje: " + v.yearOfProduction, right, 516.6f)
        val rightCol = listOf("Broj osovina: " + v.axles, "Zapremina motora: " + v.engineCapacity, "Masa: " + v.mass,
            "Nosivost: " + v.load, "Najveća dozvoljena")
        rightCol.forEachIndexed { i, s -> text(s, right, 573.8f + 19.9f * i) }
        text("masa: " + v.maxLadenMass, right, 573.8f + 19.9f * 4 + 17f)
        text("Broj mesta za stajanje: " + v.standingPlaces, right, 707.6f)

        val date = SimpleDateFormat("dd.MM.yyyy", Locale.US).format(Date())
        text(context.getString(R.string.veh_note) + "   " + date, 41.5f, 810f, 7.5f, bold = false, width = 512, color = Color.GRAY)
    }
}
