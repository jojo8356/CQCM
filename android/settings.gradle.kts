pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    // Versions minimales imposées par les Flutter récents :
    //   - AGP >= 8.11.1 (sinon « Your project's Android Gradle Plugin
    //     version (...) is lower than Flutter's minimum supported version »),
    //   - Kotlin >= 2.2.20 (même message pour KGP).
    // 8.11.1 / 2.4.0 restent dans les plages déclarées compatibles par Flutter
    // et par AGP, et correspondent à la configuration testée par
    // flutter_local_notifications 22.x.
    id("com.android.application") version "8.11.1" apply false
    id("org.jetbrains.kotlin.android") version "2.4.0" apply false
}

include(":app")
