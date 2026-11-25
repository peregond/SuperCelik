package com.peregond.supercelik

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.content.res.Configuration
import java.util.Locale

/** The language of the app, chosen in its own Settings (works on every Android version, no trip to the system settings).
 *  "Nothing saved" = follow the system. Every activity wraps its context with [wrap], and the Settings screen recreates the
 *  activity after a change. */
object AppLocale {
    private const val KEY = "appLanguage"

    /** Language tags in the order of the pickers, as on the site: Serbian (Latin, Cyrillic), a divider, then the others alphabetically by their English name. */
    val order = listOf("sr-Latn", "sr-Cyrl", "sq", "be", "hr", "en", "hu", "ro", "ru", "sk", "uk")

    /** How many of [order] sit above the divider (the two Serbian scripts). */
    const val TOP = 2

    private val flags = mapOf(
        "sr-Latn" to "🇷🇸", "sr-Cyrl" to "🇷🇸", "en" to "🇬🇧", "ru" to "🇷🇺", "sq" to "🇦🇱", "be" to "🇧🇾",
        "hr" to "🇭🇷", "hu" to "🇭🇺", "ro" to "🇷🇴", "sk" to "🇸🇰", "uk" to "🇺🇦",
    )

    /** The flag and the name of a language in the language of the interface ("lang_names" of the current resources, in the order of [order]);
     *  for the two Serbian scripts just "Latin" and "Cyrillic": the Serbian flag says which language that is. */
    fun label(context: Context, tag: String): String {
        val names = context.getString(R.string.lang_names).split("|")
        return "${flags[tag] ?: ""}  ${names.getOrNull(order.indexOf(tag)) ?: tag}"
    }

    fun saved(context: Context): String? =
        context.getSharedPreferences("settings", Context.MODE_PRIVATE).getString(KEY, null)?.takeIf { it in order }

    fun save(context: Context, tag: String?) {
        context.getSharedPreferences("settings", Context.MODE_PRIVATE).edit().apply { if (tag == null) remove(KEY) else putString(KEY, tag) }.apply()
    }

    /** The context with the chosen language (the base context unchanged when the app follows the system). */
    fun wrap(base: Context): Context {
        val tag = saved(base) ?: return base
        val locale = Locale.forLanguageTag(tag)
        Locale.setDefault(locale)
        val config = Configuration(base.resources.configuration)
        config.setLocale(locale)
        config.setLayoutDirection(locale)
        return base.createConfigurationContext(config)
    }
}

/** The activity behind a Compose LocalContext (it can be wrapped). */
fun Context.findActivity(): Activity? {
    var c: Context = this
    while (c is ContextWrapper) { if (c is Activity) return c; c = c.baseContext }
    return null
}
