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
import androidx.core.content.res.ResourcesCompat
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

    /**
     * Matched to the printout of MUP's own reader "Čitač saobraćajne dozvole"; same numbers as VehiclePrintSpec (C#) and
     * VehiclePrintLayout (Swift). The reader uses Verdana, which cannot be shipped with the app (Microsoft licence);
     * DejaVu Sans (free licence, see android/FONT-LICENSE-DEJAVU.txt) has nearly the same letter widths.
     */
    private fun drawVehicle(context: Context, c: Canvas, v: VehicleData, includeJmbg: Boolean) {
        c.drawColor(Color.WHITE)
        val regular = ResourcesCompat.getFont(context, R.font.dejavu_sans) ?: Typeface.SANS_SERIF
        val boldFace = ResourcesCompat.getFont(context, R.font.dejavu_sans_bold) ?: Typeface.DEFAULT_BOLD
        val d = CardText::date
        fun dash(s: String) = s.ifEmpty { "-" }
        /** b is the baseline from the top of the page, x the left edge. */
        fun text(s: String, x: Float, b: Float, size: Float = 11.9f, bold: Boolean = true, underline: Boolean = false) {
            if (s.isEmpty()) return
            val col = if (size < 9f) Color.GRAY else Color.BLACK
            val p = Paint(Paint.ANTI_ALIAS_FLAG).apply { typeface = if (bold) boldFace else regular; textSize = size; color = col }
            c.drawText(s, x, b, p)
            if (underline) {
                val top = b + 0.09f * size + 0.2f
                c.drawRect(x, top, x + p.measureText(s), top + 0.75f, Paint().apply { color = col })
            }
        }
        val colL = 39.4f; val colR = 348.9f

        text("Čitač saobraćajne dozvole", 43.9f, 76.36f, 25.85f)
        c.drawRect(39.2f, 90.13f, 39.2f + 506.7f, 90.13f + 4.39f, Paint().apply { color = Color.BLACK })
        text("Registarska oznaka: " + v.registrationNumber, 42.5f, 126.66f, 19.92f)

        text("Datum izdavanja: " + d(v.issuingDate), colL, 175.17f)
        text("Važi do: " + d(v.expiryDate), colR, 175.17f, 11.98f, bold = false, underline = true)
        text("Saobraćajnu izdao: " + v.stateIssuing, colL, 195.04f)
        text("Zabrana otuđenja: " + d(v.saleBan), colR, 195.04f)
        // the issuing authority wraps after the first comma
        val auth = v.authorityIssuing.trim()
        val cut = if (auth.length > 40) auth.indexOf(", ") else -1
        if (cut > 0) { text(auth.substring(0, cut + 1), colL, 215.40f); text(auth.substring(cut + 2), colL, 229.07f) } else text(auth, colL, 229.07f)
        text("Broj saobraćajne: " + v.unambiguousNumber, colL, 249.24f)
        text("Serijski broj: " + v.serialNumber, colL, 269.30f)

        text("Podaci o vlasniku", colL, 312.02f, 20.3f, bold = false, underline = true)
        val owner = listOf(
            "Vlasnik: " + v.ownerSurname, "Ime vlasnika: " + v.ownerName, "Adresa vlasnika: " + v.ownerAddress,
            "Jmbg vlasnika: " + (if (includeJmbg) v.ownerPersonalNo else ""),
            "Korisnik: " + v.userSurname, "Ime korisnika: " + v.userName, "Adresa korisnika: " + v.userAddress,
            "Jmbg korisnika: " + (if (includeJmbg) v.userPersonalNo else ""),
        )
        owner.forEachIndexed { i, s -> text(s, colL, 331.78f + 19.863f * i) }

        text("Podaci o vozilu", colL, 502.07f, 20.3f, bold = false, underline = true)
        val left = listOf(
            "Datum prve registracije: " + d(v.firstRegistrationDate),
            "Marka: " + v.make + "   Model: " + v.commercialDescription,
            "Tip: " + dash(v.type),
            "Boja: " + v.colour, "Broj šasije: " + v.vin, "Broj motora: " + v.engineNumber,
            "Snaga motora: " + v.maxNetPower, "Odnos snaga/masa: " + v.powerWeightRatio,
            "Kategorija: " + v.category, "Pogonsko gorivo: " + v.fuelType, "Broj mesta za sedenje: " + v.seats,
        )
        val right = listOf(
            "Godina proizvodnje: " + v.yearOfProduction, "", "",
            "Broj osovina: " + v.axles, "Zapremina motora: " + v.engineCapacity, "Masa: " + v.mass,
            "Nosivost: " + v.load, "Najveća dozvoljena", "masa: " + v.maxLadenMass, "", "Broj mesta za stajanje: " + v.standingPlaces,
        )
        for (i in left.indices) {
            val b = 521.53f + 19.793f * i
            text(left[i], colL, b)
            text(right[i], colR, b)
        }
        text("Homologacijska oznaka: " + dash(v.typeApprovalNumber), 90.6f + maxOf(0, ("Tip: " + dash(v.type)).length - 6) * 8f, 521.53f + 19.793f * 2)

        // the note about the unverified parser, small and grey at the foot of the page (not part of MUP's printout), wrapped by hand
        var note = context.getString(R.string.veh_note) + "   " + SimpleDateFormat("dd.MM.yyyy", Locale.US).format(Date())
        var nb = 806f
        while (note.isNotEmpty() && nb < 835f) {
            var n = note.length
            if (n > 125) { n = note.lastIndexOf(' ', 125); if (n <= 0) n = 125 }
            text(note.substring(0, n).trim(), 41.5f, nb, 7.5f, bold = false)
            note = note.substring(n).trim(); nb += 9f
        }
    }
}
