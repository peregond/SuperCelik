package com.peregond.supercelik

import android.content.Context
import android.graphics.BitmapFactory
import android.graphics.Paint
import android.graphics.Typeface
import android.graphics.pdf.PdfDocument
import java.io.File

/** Simple one-page A4 PDF of the card data (the MUP print layout of the Mac app is not ported yet). */
object Pdf {
    fun create(context: Context, p: PersonalData, rows: List<Pair<String, String>>, title: String): File {
        val doc = PdfDocument()
        val page = doc.startPage(PdfDocument.PageInfo.Builder(595, 842, 1).create())
        val c = page.canvas
        val h = Paint().apply { textSize = 20f; typeface = Typeface.DEFAULT_BOLD }
        val label = Paint().apply { textSize = 9f; color = 0xFF666666.toInt() }
        val value = Paint().apply { textSize = 13f }
        var y = 60f
        c.drawText(title, 40f, y, h)
        y += 28f
        p.portrait?.let { b ->
            BitmapFactory.decodeByteArray(b, 0, b.size)?.let { bmp ->
                c.drawBitmap(android.graphics.Bitmap.createScaledBitmap(bmp, 110, 140, true), 445f, 40f, null)
            }
        }
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
