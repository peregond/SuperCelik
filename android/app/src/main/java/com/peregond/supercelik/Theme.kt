package com.peregond.supercelik

import android.os.Build
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.Box
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp

/** Serbian flag colours. */
object Flag {
    val Red = Color(0xFFC6363C)
    val Blue = Color(0xFF0C4076)
    val White = Color(0xFFFFFFFF)
}

/** True while the flag palette (not the wallpaper-based one) is active: cards then use the flag blue. */
val LocalFlagPalette = compositionLocalOf { true }

// Flag palette: red = primary, flag blue = secondary, white/warm white surfaces.
private val LightFlag = lightColorScheme(
    primary = Flag.Red, onPrimary = Color.White,
    primaryContainer = Color(0xFFFFDAD8), onPrimaryContainer = Color(0xFF410006),
    secondary = Flag.Blue, onSecondary = Color.White,
    secondaryContainer = Color(0xFFD6E3FF), onSecondaryContainer = Color(0xFF001B3E),
    tertiary = Color(0xFF4A6286), onTertiary = Color.White,
    tertiaryContainer = Color(0xFFD3E4FF), onTertiaryContainer = Color(0xFF001C3A),
    background = Color(0xFFFFFBFF), onBackground = Color(0xFF1F1A1B),
    surface = Color(0xFFFFFBFF), onSurface = Color(0xFF1F1A1B),
    surfaceVariant = Color(0xFFF3DDDD), onSurfaceVariant = Color(0xFF524343),
    surfaceContainerLowest = Color.White, surfaceContainerLow = Color(0xFFFFF0EF),
    surfaceContainer = Color(0xFFFCEAEA), surfaceContainerHigh = Color(0xFFF6E4E4), surfaceContainerHighest = Color(0xFFF0DEDE),
    outline = Color(0xFF857373), outlineVariant = Color(0xFFD8C2C2),
)
private val DarkFlag = darkColorScheme(
    primary = Color(0xFFFFB3B0), onPrimary = Color(0xFF68000F),
    primaryContainer = Color(0xFF93001B), onPrimaryContainer = Color(0xFFFFDAD8),
    secondary = Color(0xFFA9C7FF), onSecondary = Color(0xFF00315F),
    secondaryContainer = Color(0xFF0C4076), onSecondaryContainer = Color(0xFFD6E3FF),
    tertiary = Color(0xFFB2C8F2), onTertiary = Color(0xFF173155),
    tertiaryContainer = Color(0xFF2F4A6E), onTertiaryContainer = Color(0xFFD3E4FF),
    background = Color(0xFF181112), onBackground = Color(0xFFEDDFDF),
    surface = Color(0xFF181112), onSurface = Color(0xFFEDDFDF),
    surfaceVariant = Color(0xFF524343), onSurfaceVariant = Color(0xFFD8C2C2),
    surfaceContainerLowest = Color(0xFF120B0C), surfaceContainerLow = Color(0xFF201819),
    surfaceContainer = Color(0xFF251C1D), surfaceContainerHigh = Color(0xFF302626), surfaceContainerHighest = Color(0xFF3B3031),
    outline = Color(0xFFA08C8C), outlineVariant = Color(0xFF524343),
)

/**
 * Two palettes: the Serbian flag one (default) and Material You wallpaper colours (Android 12+, in settings).
 * `wallpaper` = use dynamic colour.
 */
@Composable
fun SuperCelikTheme(dark: Boolean, wallpaper: Boolean, content: @Composable () -> Unit) {
    val context = LocalContext.current
    val useWallpaper = wallpaper && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S
    val scheme = when {
        useWallpaper -> if (dark) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
        dark -> DarkFlag
        else -> LightFlag
    }
    CompositionLocalProvider(LocalFlagPalette provides !useWallpaper) {
        MaterialTheme(colorScheme = scheme, content = content)
    }
}

/** Thin red / blue / white band: the app's brand accent, shown in both palettes. */
@Composable
fun FlagStripe(modifier: Modifier = Modifier, thickness: Int = 4) {
    Row(modifier.fillMaxWidth().height(thickness.dp)) {
        Box(Modifier.weight(1f).height(thickness.dp).background(Flag.Red))
        Box(Modifier.weight(1f).height(thickness.dp).background(Flag.Blue))
        Box(Modifier.weight(1f).height(thickness.dp).background(Color(0xFFE6E6E6)))
    }
}
