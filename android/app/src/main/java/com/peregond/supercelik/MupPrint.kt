package com.peregond.supercelik

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * The printout of the official MUP Čelik application ("ČITAČ ELEKTRONSKE LIČNE KARTE: ŠTAMPA PODATAKA"),
 * a port of Sources/SerbiaID/MupPrintLayout.swift: same A4 page, positions (points), line widths, font sizes,
 * labels and footnotes. It is a standard document: do not restyle it. Origin top-left, A4 595 x 842 pt.
 * (The system sans-serif replaces Arial; positions and sizes are identical.)
 */
class MupPrintLayout(private val p: PersonalData, private val includeJmbg: Boolean = true, private val printDate: Date = Date()) {
    private val leftMargin = 58.8f
    private val rightMargin = 535f
    private val textLeftMargin = 67.3f
    private var y = 0f
    private var lineWidth = 1f
    private var fontSize = 13.5f
    private var kern = -0.1f
    private lateinit var c: Canvas

    private val font: Typeface = Typeface.SANS_SERIF

    private fun textPaint() = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        typeface = font; textSize = fontSize; color = Color.BLACK; letterSpacing = kern / fontSize
    }

    /**
     * Fitting: the form is laid out top to bottom, so long data (wrapped addresses, a note) pushes the footnotes off
     * the page. A dry run measures the height first; if it does not fit, the rows are packed a little tighter and,
     * as a last resort, the whole page is scaled down a few percent.
     */
    private var measuring = false
    private var rowStep = 24.67f
    private var rowCount = 0
    private val bottomLimit = 826f

    fun draw(canvas: Canvas) {
        c = canvas
        rowStep = 24.67f
        val natural = layout(drawing = false)
        var scale = 1f
        if (natural > bottomLimit) {
            rowStep = maxOf(18f, rowStep - (natural - bottomLimit) / maxOf(rowCount, 1))
            val packed = layout(drawing = false)
            if (packed > bottomLimit) scale = bottomLimit / packed
        }
        c.drawColor(Color.WHITE)
        c.save()
        c.scale(scale, scale)
        layout(drawing = true)
        c.restore()
    }

    /** Lays the page out (drawing it only when [drawing]) and returns the y where it ends. */
    private fun layout(drawing: Boolean): Float {
        measuring = !drawing
        y = 0f; lineWidth = 1f; fontSize = 13.5f; kern = -0.1f; rowCount = 0
        when (p.cardType) {
            CardType.IF2020 -> drawForeigner(permit = false)
            CardType.RP2024 -> drawForeigner(permit = true)
            else -> drawRegular()
        }
        return y
    }

    // ---- pages ----

    private fun drawRegular() {
        header(68.5f, 88f)
        photo(102.8f)
        y = 276f
        line(1.08f)
        section("Podaci o građaninu", first = true)
        row("Prezime:", p.surname)
        row("Ime:", p.givenName)
        row("Ime jednog roditelja:", p.parentGivenName)
        row("Datum rođenja:", date(p.dateOfBirth))
        row("Mesto rođenja\nopština i država:", join(p.placeOfBirth, p.communityOfBirth, p.stateOfBirth))
        row(addressLabel, address)
        row("Datum promene adrese:", date(p.addressDate))
        if (includeJmbg) row("JMBG:", p.personalNumber)
        row("Pol:", p.sex)
        documentSection(withName = false)
        printDateLine()
        if (y < 700f) y = 730.6f
        line(0.83f)
        fontSize = 9f
        y += 10f
        notes(listOf(
            "1. U čipu lične karte, podaci o imenu i prezimenu imaoca lične karte ispisani su na nacionalnom pismu onako kako su",
            "ispisani na samom obrascu lične karte, dok su ostali podaci ispisani latiničkim pismom.",
            "2. Ako se ime lica sastoji od dve reči čija je ukupna dužina između 20 i 30 karaktera ili prezimena od dve reči čija je",
            "ukupna dužina između 30 i 36 karaktera, u čipu lične karte izdate pre 18.08.2014. godine, druga reč u imenu ili prezimenu",
            "skraćuje se na prva dva karaktera",
        ))
        y += 15.7f
        line(null)
    }

    private fun drawForeigner(permit: Boolean) {
        header(64.95f, 79.8f)
        photo(86f)
        y = 250f
        line(1.08f)
        section("Podaci o strancu", first = true)
        row("Prezime:", p.surname)
        row("Ime:", p.givenName)
        row("Državljanstvo:", p.nationality)
        row("Datum rođenja:", date(p.dateOfBirth))
        if (permit) {
            row("Mesto rođenja,\nopština i država:", join(p.placeOfBirth, p.communityOfBirth, p.stateOfBirth))
            row(addressLabel, address)
        } else {
            row("Osnov boravka:", p.purposeOfStay)
            row(addressLabel, join(p.addrState, address))
        }
        row("Datum promene adrese:", date(p.addressDate))
        if (includeJmbg) row("Evidencijski broj\nstranca:", p.personalNumber)
        row("Pol:", p.sex)
        if (permit) {
            row("Osnov boravka:", p.purposeOfStay)
            row("Napomena:", p.eNote)
        }
        documentSection(withName = permit)
        printDateLine()
        line(0.83f)
        fontSize = 9f
        y += 4f
        notes(if (permit) listOf(
            "1. U čipu dozvole za privremeni boravak i rad, podaci o imenu i prezimenu imaoca dozvole ispisani su onako kako su",
            "ispisani na samom obrascu dozvole za privremeni boravak latiničnim pismom.",
            "2. Ako se ime ili prezime stranca sastoji od dve ili više reči čija dužina prelazi 30 karaktera za ime, odnosno 36 karaktera",
            "za prezime u čip se upisuje puno ime stranca, a na obrascu dozvole za privremeni boravak se upisuje do 30 karaktera za",
            "ime, odnosno 36 karaktera za prezime.",
        ) else listOf(
            "1. U čipu lične karte za strance, podaci o imenu i prezimenu stranca ispisani su onako kako su ispisani na samom",
            "obrascu lične karte za stranca latiničnim pismom.",
            "2. Ako se ime ili prezime stranca sastoji od dve ili više reči čija dužina prelazi 30 karaktera za ime, odnosno 36",
            "karaktera za prezime, u čip se upisuje puno ime i prezime stranca, a na obrascu lične karte za stranca se upisuje do",
            "30 karaktera za ime, odnosno 36 karaktera za prezime.",
        ))
        y += 9.7f
        line(null)
    }

    // ---- blocks ----

    private fun header(titleY: Float, ruleY: Float) {
        y = 59.041f
        line(0.83f)
        kern = -0.2f
        text("ČITAČ ELEKTRONSKE LIČNE KARTE: ŠTAMPA PODATAKA", textLeftMargin + 1f, titleY)
        kern = -0.1f
        y = ruleY
        line(null)
    }

    private fun photo(top: Float) {
        if (measuring) { lineWidth = 0.48f; return }
        val frame = RectF(leftMargin, top, 179f, top + 159f)
        p.portrait?.let { d ->
            BitmapFactory.decodeByteArray(d, 0, d.size)?.let { bmp: Bitmap ->
                c.drawBitmap(bmp, null, RectF(leftMargin, top, leftMargin + 119.9f, top + 159f), Paint(Paint.FILTER_BITMAP_FLAG))
            }
        }
        val stroke = Paint().apply { style = Paint.Style.STROKE; color = Color.BLACK; strokeWidth = 0.48f }
        c.drawRect(frame, stroke)
        lineWidth = 0.48f
    }

    private fun section(title: String, first: Boolean) {
        if (!first) { y -= 8.67f; line(null) }
        y += if (first) 8f else 9f
        if (first) fontSize = 11.1f
        text(title, textLeftMargin, y)
        y += 16f
        line(null)
        y += 9f
    }

    private fun documentSection(withName: Boolean) {
        section("Podaci o dokumentu", first = false)
        if (withName) row("Naziv dokumenta:", p.documentName)
        row("Dokument izdaje:", p.issuingAuthority)
        row("Broj dokumenta:", p.docRegNo)
        row("Datum izdavanja:", date(p.issuingDate))
        row("Važi do:", date(p.expiryDate))
    }

    private fun printDateLine() {
        y -= 8.67f
        line(null)
        y += 3f
        line(null)
        y += 9f
        text("Datum štampe: " + SimpleDateFormat("dd.MM.yyyy.", Locale.US).format(printDate), textLeftMargin, y)
        y += 19f
    }

    private fun notes(lines: List<String>) {
        lines.forEachIndexed { i, s ->
            if (i > 0) y += 9.7f
            text(s, leftMargin, y)
        }
    }

    /** Label column 120 pt wide at the text margin, value column 350 pt wide 128 pt to the right; wrapped lines 12 pt apart, rows 24.67 pt apart. */
    private fun row(label: String, value: String) {
        val top = y
        val l = wrap(label, 120f)
        val v = wrap(value, 350f)
        l.forEachIndexed { i, s -> text(s, textLeftMargin, top + i * 12f) }
        v.forEachIndexed { i, s -> text(s, textLeftMargin + 128f, top + i * 12f) }
        y = top + (maxOf(l.size, v.size, 1) - 1) * 12f + rowStep
        rowCount++
    }

    // ---- primitives ----

    /** `y` is the top of the text line (like NSString.draw(at:)); Canvas wants the baseline. */
    private fun text(s: String, x: Float, y: Float) {
        if (measuring) return
        val paint = textPaint()
        c.drawText(s, x, y - paint.ascent(), paint)
    }

    /** Horizontal rule across the page at the current y; null keeps the previous width. */
    private fun line(width: Float?) {
        if (width != null) lineWidth = width
        if (measuring) return
        val paint = Paint().apply { color = Color.BLACK; strokeWidth = lineWidth; style = Paint.Style.STROKE }
        c.drawLine(leftMargin, y, rightMargin, y, paint)
    }

    private fun wrap(s: String, width: Float): List<String> {
        val out = ArrayList<String>()
        val paint = textPaint()
        for (para in s.split("\n")) {
            var cur = ""
            for (word in para.split(" ").filter { it.isNotEmpty() }) {
                val next = if (cur.isEmpty()) word else "$cur $word"
                if (cur.isNotEmpty() && paint.measureText(next) > width) { out.add(cur); cur = word } else cur = next
            }
            out.add(cur)
        }
        return out
    }

    // ---- formatting (as on the MUP printout) ----

    private val addressLabel: String get() = if (p.addressLabel.lowercase() == "prebivalište") "Prebivalište:" else "Prebivalište\ni adresa stana:"

    /** "MESTO, OPŠTINA, ULICA 12A/3/7" */
    private val address: String
        get() {
            var street = p.street
            if (p.houseNumber.isNotEmpty() || p.houseLetter.isNotEmpty() || p.entrance.isNotEmpty()) {
                street += " " + p.houseNumber + p.houseLetter
                if (p.floor.isNotEmpty()) street += "/" + p.floor
                if (p.apartment.isNotEmpty()) street += "/" + p.apartment
            }
            return join(p.place, p.community, street)
        }

    private fun join(vararg parts: String) = parts.map { it.trim() }.filter { it.isNotEmpty() }.joinToString(", ")

    /** "dd.MM.yyyy" -> "dd.MM.yyyy."; a date with year 0000 is "Nije dostupan". */
    private fun date(s: String): String {
        val parts = s.split(".").filter { it.isNotEmpty() }
        if (parts.size != 3 || parts[2].length != 4) return s
        if (parts[2] == "0000") return "Nije dostupan"
        return if (s.endsWith(".")) s else "$s."
    }
}
