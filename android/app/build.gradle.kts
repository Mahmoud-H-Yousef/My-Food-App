import java.util.Properties

// Release key shared with Explorer (android/key.properties + app/explorer-release.jks), so both
// apps have the same SHA-1 for Google sign-in. Keep both files safe.
val keyProps = Properties()
val keyFile = rootProject.file("key.properties")
if (keyFile.exists()) keyFile.inputStream().use { stream -> keyProps.load(stream) }

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.mahmoud.myfood"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.mahmoud.myfood"
        // Health Connect needs Android 8 (API 26) or newer.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Google sign-in redirect: com.mahmoud.myfood:/oauth2redirect
        manifestPlaceholders += mapOf("appAuthRedirectScheme" to "com.mahmoud.myfood")
    }

    signingConfigs {
        create("release") {
            if (keyFile.exists()) {
                storeFile = file(keyProps.getProperty("storeFile"))
                storePassword = keyProps.getProperty("storePassword")
                keyAlias = keyProps.getProperty("keyAlias")
                keyPassword = keyProps.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keyFile.exists()) signingConfigs.getByName("release") else signingConfigs.getByName("debug")
            // R8 strips methods plugins call through Flutter's channels (seen with shared_preferences
            // in Explorer). Not worth it for a sideloaded app.
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
