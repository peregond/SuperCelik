package com.peregond.supercelik

import android.content.Context
import android.graphics.pdf.PdfDocument
import java.io.File

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
}
