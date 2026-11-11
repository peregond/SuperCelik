package com.peregond.supercelik

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Color as AColor
import android.graphics.pdf.PdfRenderer
import android.os.Bundle
import android.os.CancellationSignal
import android.os.ParcelFileDescriptor
import android.print.PageRange
import android.print.PrintAttributes
import android.print.PrintDocumentAdapter
import android.print.PrintDocumentInfo
import android.print.PrintManager
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Print
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.core.content.FileProvider
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileOutputStream

/** Hands the PDF to the system print dialog (Android's own print preview, printers, "Save as PDF"). */
fun printPdf(context: Context, file: File, jobName: String) {
    val pm = context.getSystemService(Context.PRINT_SERVICE) as PrintManager
    pm.print(jobName, object : PrintDocumentAdapter() {
        override fun onLayout(old: PrintAttributes?, new: PrintAttributes?, cancel: CancellationSignal?,
                              callback: LayoutResultCallback, extras: Bundle?) {
            if (cancel?.isCanceled == true) { callback.onLayoutCancelled(); return }
            callback.onLayoutFinished(PrintDocumentInfo.Builder(file.name)
                .setContentType(PrintDocumentInfo.CONTENT_TYPE_DOCUMENT)
                .setPageCount(PrintDocumentInfo.PAGE_COUNT_UNKNOWN).build(), true)
        }

        override fun onWrite(pages: Array<out PageRange>?, dest: ParcelFileDescriptor, cancel: CancellationSignal?,
                             callback: WriteResultCallback) {
            try {
                file.inputStream().use { i -> FileOutputStream(dest.fileDescriptor).use { o -> i.copyTo(o) } }
                callback.onWriteFinished(arrayOf(PageRange.ALL_PAGES))
            } catch (e: Exception) {
                callback.onWriteFailed(e.message)
            }
        }
    }, null)
}

/** Send the PDF to someone (mail, messenger, cloud...). */
fun sharePdfFile(context: Context, file: File) {
    val uri = FileProvider.getUriForFile(context, "${context.packageName}.files", file)
    context.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).apply {
        type = "application/pdf"; putExtra(Intent.EXTRA_STREAM, uri); addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }, null))
}

/** Full-screen in-app PDF viewer with print and share. Pages are rendered with the system PdfRenderer. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PdfViewer(file: File, onClose: () -> Unit) {
    val ctx = LocalContext.current
    val pages by produceState<List<Bitmap>>(emptyList(), file) {
        value = withContext(Dispatchers.IO) {
            val out = ArrayList<Bitmap>()
            ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY).use { fd ->
                PdfRenderer(fd).use { r ->
                    for (i in 0 until r.pageCount) r.openPage(i).use { p ->
                        val w = 1240                                    // ~150 dpi A4
                        val bmp = Bitmap.createBitmap(w, (w.toFloat() * p.height / p.width).toInt(), Bitmap.Config.ARGB_8888)
                        bmp.eraseColor(AColor.WHITE)
                        p.render(bmp, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                        out.add(bmp)
                    }
                }
            }
            out
        }
    }
    Dialog(onDismissRequest = onClose, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Scaffold(
            topBar = {
                TopAppBar(
                    title = { Text(stringResource(R.string.pdf_title)) },
                    navigationIcon = { IconButton(onClose) { Icon(Icons.AutoMirrored.Filled.ArrowBack, stringResource(R.string.close)) } },
                    actions = {
                        IconButton({ printPdf(ctx, file, ctx.getString(R.string.app_name)) }) { Icon(Icons.Filled.Print, stringResource(R.string.print)) }
                        IconButton({ sharePdfFile(ctx, file) }) { Icon(Icons.Filled.Share, stringResource(R.string.share_pdf)) }
                    },
                )
            },
        ) { padding ->
            if (pages.isEmpty()) {
                Box(Modifier.padding(padding).fillMaxSize(), contentAlignment = androidx.compose.ui.Alignment.Center) { CircularProgressIndicator() }
            } else {
                LazyColumn(Modifier.padding(padding).fillMaxSize(), contentPadding = PaddingValues(12.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    itemsIndexed(pages) { _, bmp ->
                        Image(bmp.asImageBitmap(), null, Modifier.fillMaxWidth().clip(RoundedCornerShape(4.dp)), contentScale = ContentScale.FillWidth)
                    }
                }
            }
        }
    }
}
