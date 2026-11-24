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

    private fun drawVehicle(context: Context, c: Canvas, v: VehicleData, includeJmbg: Boolean) {
        val rows = VehicleRows.build(v, includeJmbg)
        c.drawColor(Color.WHITE)
        fun paint(size: Float, bold: Boolean, color: Int) = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            typeface = if (bold) Typeface.create(Typeface.SANS_SERIF, Typeface.BOLD) else Typeface.SANS_SERIF
            textSize = size; this.color = color
        }
        fun text(s: String, p: TextPaint, x: Float, y: Float, width: Int): Float {
            val l = StaticLayout.Builder.obtain(s, 0, s.length, p, width).setAlignment(Layout.Alignment.ALIGN_NORMAL).build()
            c.save(); c.translate(x, y); l.draw(c); c.restore()
            return l.height.toFloat()
        }
        var y = 52f
        y += text(context.getString(R.string.veh_title), paint(20f, true, Color.BLACK), 50f, y, 495) + 8f
        y += text(v.registrationNumber, paint(14f, true, Color.BLACK), 50f, y, 495) + 8f
        c.drawRect(50f, y, 545f, y + 1.2f, Paint().apply { color = Color.BLACK })
        y += 12f
        val step = minOf(20f, (842f - y - 70f) / maxOf(1, rows.size))
        val size = if (step >= 18f) 11f else 9.5f
        for ((key, value) in rows) {
            text(context.getString(vehicleLabel(key)), paint(size, false, Color.DKGRAY), 50f, y, 190)
            text(value, paint(size, true, Color.BLACK), 245f, y, 300)
            y += step
        }
        val date = SimpleDateFormat("dd.MM.yyyy", Locale.US).format(Date())
        text(context.getString(R.string.veh_note) + "   " + date, paint(8f, false, Color.GRAY), 50f, 842f - 44f, 495)
    }
}
