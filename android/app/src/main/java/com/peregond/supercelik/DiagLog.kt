package com.peregond.supercelik

import android.os.Build
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/** What "Copy logs and errors" in Settings puts on the clipboard: the technical side of what went wrong (error kinds and
 *  messages) with the time, the app version and the device. Kept in memory only (since the app started), and it holds no
 *  personal data from the card: errors are written without it. */
object DiagLog {
    private val lines = ArrayDeque<String>()
    private val stamp get() = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US).format(Date())

    @Synchronized fun add(text: String) {
        lines.addLast("$stamp  $text")
        while (lines.size > 200) lines.removeFirst()
    }

    fun error(e: Throwable, where: String? = null) {
        val sb = StringBuilder("ERROR ")
        if (where != null) sb.append(where).append(": ")
        sb.append(e.javaClass.simpleName).append(": ").append(e.message)
        if (e is CardException) sb.append(" [").append(e.kind).append("]")
        var c = e.cause
        while (c != null) { sb.append(" <- ").append(c.javaClass.simpleName).append(": ").append(c.message); c = c.cause }
        add(sb.toString())
    }

    /** `state`: what the app knows (reader, ...), written by the caller. */
    @Synchronized fun report(version: String, state: String): String {
        val out = mutableListOf(
            "Super Čelik $version",
            "System: Android ${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT}), ${Build.MANUFACTURER} ${Build.MODEL}",
            "Language: ${Locale.getDefault().toLanguageTag()}",
        )
        if (state.isNotEmpty()) out.add(state)
        out.add("Time: $stamp")
        out.add("")
        if (lines.isEmpty()) out.add("(no errors since the app started)") else out.addAll(lines)
        return out.joinToString("\n")
    }
}
