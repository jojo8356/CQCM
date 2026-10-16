plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

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

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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
