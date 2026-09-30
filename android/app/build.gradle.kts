plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.jlptbenkyo.jlptbenkyo"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // flutter_local_notifications bundles a desugared java.time and will
        // not resolve without this — the build fails at checkAarMetadata with
        // "requires core library desugaring to be enabled", before a line of
        // app code is compiled. It is a documented requirement of that
        // plugin, not a workaround for a version skew.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.jlptbenkyo.jlptbenkyo"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        // Debug builds need a stable signing identity across machines and CI
        // runs — without this, AGP falls back to an implicit
        // ~/.android/debug.keystore that is freshly (and differently)
        // auto-generated in every fresh environment, so each CI-built APK is
        // signed with a different key and cannot be installed as an update
        // over the last one. Android refuses the install rather than
        // silently replacing it. This keystore is debug-only and is never
        // used for release signing.
        getByName("debug") {
            storeFile = file("debug.keystore")
            storePassword = "android"
            keyAlias = "androiddebugkey"
            keyPassword = "android"
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}

flutter {
    source = "../.."
}
