package com.peregond.supercelik

import android.os.Build
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext

// Fallback palette (Android 11 and older, or dynamic colour turned off) from the Serbian flag: red + navy.
private val LightFallback = lightColorScheme(
    primary = Color(0xFFB3262B), onPrimary = Color.White,
    primaryContainer = Color(0xFFFFDAD7), onPrimaryContainer = Color(0xFF410004),
    secondary = Color(0xFF1B2A5C), onSecondary = Color.White,
    secondaryContainer = Color(0xFFDCE1FF), onSecondaryContainer = Color(0xFF00164E),
)
private val DarkFallback = darkColorScheme(
    primary = Color(0xFFFFB3AE), onPrimary = Color(0xFF68000B),
    primaryContainer = Color(0xFF93000F), onPrimaryContainer = Color(0xFFFFDAD7),
    secondary = Color(0xFFB7C4FF), onSecondary = Color(0xFF002A78),
    secondaryContainer = Color(0xFF28418F), onSecondaryContainer = Color(0xFFDCE1FF),
)

/** Material You: wallpaper-based dynamic colour on Android 12+ (unless turned off), flag colours otherwise. */
@Composable
fun SuperCelikTheme(dark: Boolean, dynamic: Boolean, content: @Composable () -> Unit) {
    val context = LocalContext.current
    val scheme = when {
        dynamic && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S ->
            if (dark) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
        dark -> DarkFallback
        else -> LightFallback
    }
    MaterialTheme(colorScheme = scheme, content = content)
}
