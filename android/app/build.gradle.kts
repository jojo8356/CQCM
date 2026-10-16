import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Signature « release ».
//
// `android/key.properties` (non versionné, voir `android/.gitignore`) décrit
// le keystore de production :
//
// ```properties
// storeFile=/chemin/absolu/cqcm-release.jks
// storePassword=…
// keyAlias=cqcm
// keyPassword=…
// ```
//
// Sans ce fichier, la release reste signée avec la clé de débogage — pratique
// pour tester, mais la signature change d'une machine à l'autre et l'APK ne
// peut pas mettre à jour une installation existante d'une autre signature.
// La procédure de création est dans `docs/android-release.md`.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        FileInputStream(keystorePropertiesFile).use { load(it) }
    }
}
val hasReleaseKeystore = keystorePropertiesFile.exists() &&
    keystoreProperties.getProperty("storeFile") != null

android {
    namespace = "com.cqcm.cqcm"
    // flutter_local_notifications 19.x exige compileSdk >= 35 ; on garde le
    // défaut de Flutter quand il est plus récent (36 aujourd'hui).
    compileSdk = maxOf(35, flutter.compileSdkVersion)
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Requis par flutter_local_notifications (desugaring des API java.time
        // utilisées par le planificateur de rappels), même sans rappel programmé.
        // Java 17 = réglage du modèle Flutter actuel et de la doc du plugin.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.cqcm.cqcm"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Plus de 64 K méthodes une fois le plugin de notifications ajouté.
        multiDexEnabled = true
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            // Keystore de production s'il est configuré, clé de débogage sinon
            // (installation personnelle, tests).
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    // Remplace `kotlinOptions { jvmTarget = ... }`, déprécié à partir de
    // Kotlin 2.x : la cible doit rester alignée sur `compileOptions`.
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // Desugaring demandé par flutter_local_notifications (AGP >= 8.6.0).
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // Contournement documenté par flutter_local_notifications : sur Android
    // 12L et au-delà, une application qui active le desugaring peut planter
    // (bogue Flutter, cf. https://github.com/flutter/flutter/issues/110658).
    // Ajouter WindowManager supprime ce risque.
    implementation("androidx.window:window:1.0.0")
    implementation("androidx.window:window-java:1.0.0")
}

flutter {
    source = "../.."
}
