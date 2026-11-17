plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "com.peregond.supercelik"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.peregond.supercelik"
        minSdk = 26
        targetSdk = 36
        // CI passes the tag version (vX.Y.Z); local builds get a dev version
        versionCode = (project.findProperty("appVersionCode") as String?)?.toInt() ?: 1
        versionName = (project.findProperty("appVersion") as String?) ?: "0.0.0-dev"
    }

    signingConfigs {
        // Release signing comes from the environment (CI: a keystore from repository secrets, or a throwaway one).
        // Without it a local `assembleRelease` produces an unsigned APK; `assembleDebug` is signed with the debug key.
        System.getenv("ANDROID_KEYSTORE_FILE")?.let { path ->
            create("release") {
                storeFile = file(path)
                storePassword = System.getenv("ANDROID_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("ANDROID_KEY_ALIAS") ?: "release"
                keyPassword = System.getenv("ANDROID_KEYSTORE_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            signingConfig = signingConfigs.findByName("release")
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
    buildFeatures { compose = true }

    packaging {
        // BouncyCastle jars carry the same multi-release / OSGi metadata
        resources.excludes += setOf("META-INF/versions/**", "META-INF/MANIFEST.MF", "META-INF/*.kotlin_module", "META-INF/DEPENDENCIES", "META-INF/LICENSE*", "META-INF/NOTICE*", "META-INF/INDEX.LIST")
    }

    // MUP root + intermediate CA certificates shared with the Mac / Windows apps -> assets/CA/*.crt
    sourceSets.getByName("main").assets.srcDir("../../Sources/SerbiaID/Resources")

}

dependencies {
    val composeBom = platform("androidx.compose:compose-bom:2024.09.02")
    implementation(composeBom)
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.activity:activity-compose:1.9.2")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.6")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.8.6")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
    implementation("org.bouncycastle:bcprov-jdk18on:1.78.1")
    implementation("org.bouncycastle:bcpkix-jdk18on:1.78.1")
    debugImplementation("androidx.compose.ui:ui-tooling")
}
