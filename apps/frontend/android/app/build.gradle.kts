plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "io.github.hashev.ffido"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "io.github.hashev.ffido"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("publicRelease") {
            val storePath = System.getenv("FFIDO_ANDROID_KEYSTORE")
            if (!storePath.isNullOrEmpty()) {
                storeFile = file(storePath)
                storePassword = System.getenv("FFIDO_ANDROID_STORE_PASSWORD")
                keyAlias = System.getenv("FFIDO_ANDROID_KEY_ALIAS")
                keyPassword = System.getenv("FFIDO_ANDROID_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            val publicRelease = System.getenv("FFIDO_PUBLIC_RELEASE") == "true"
            if (publicRelease) {
                require(!System.getenv("FFIDO_ANDROID_KEYSTORE").isNullOrEmpty()) {
                    "Public APK requires a permanent release keystore"
                }
            }
            signingConfig = signingConfigs.getByName(if (publicRelease) "publicRelease" else "debug")
        }
    }
}

flutter {
    source = "../.."
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}
