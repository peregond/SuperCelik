package com.peregond.supercelik

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.graphics.pdf.PdfDocument
import java.io.File

/** One-page A4 PDF of the card data with a flag-colour band (the full MUP print layout of the Mac app is not ported yet). */
object Pdf {
    fun create(context: Context, p: PersonalData, rows: List<Pair<String, String>>, title: String): File {
        val doc = PdfDocument()
        val page = doc.startPage(PdfDocument.PageInfo.Builder(595, 842, 1).create())
        val c = page.canvas
        // Serbian flag band: red, blue, white
        val band = Paint()
        band.color = 0xFFC6363C.toInt(); c.drawRect(0f, 0f, 595f, 10f, band)
        band.color = 0xFF0C4076.toInt(); c.drawRect(0f, 10f, 595f, 20f, band)
        band.color = 0xFFDDDDDD.toInt(); c.drawRect(0f, 20f, 595f, 30f, band)

        val h = Paint().apply { textSize = 22f; typeface = Typeface.DEFAULT_BOLD; color = 0xFF0C4076.toInt(); isAntiAlias = true }
        val label = Paint().apply { textSize = 9f; color = 0xFF666666.toInt(); isAntiAlias = true }
        val value = Paint().apply { textSize = 13f; isAntiAlias = true }
        var y = 72f
        c.drawText(title, 40f, y, h)
        y += 14f
        p.portrait?.let { b ->
            BitmapFactory.decodeByteArray(b, 0, b.size)?.let { bmp ->
                c.drawBitmap(Bitmap.createScaledBitmap(bmp, 110, 140, true), 445f, 52f, null)
                val frame = Paint().apply { style = Paint.Style.STROKE; color = 0xFFAAAAAA.toInt(); strokeWidth = 1f }
                c.drawRect(RectF(445f, 52f, 555f, 192f), frame)
            }
        }
        y += 14f
        for ((k, v) in rows) {
            if (v.isBlank()) continue
            c.drawText(k, 40f, y, label); y += 15f
            c.drawText(v, 40f, y, value); y += 24f
            if (y > 800f) break
        }
        doc.finishPage(page)
        val dir = File(context.cacheDir, "exports").apply { mkdirs() }
        val f = File(dir, "SuperCelik.pdf")
        f.outputStream().use { doc.writeTo(it) }
        doc.close()
        return f
    }
}
