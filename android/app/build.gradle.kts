plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.yenefsabat.yenefs_abat"
    // share_plus's androidx dependencies (lifecycle 2.7.0, core-ktx 1.13.1,
    // etc.) require compileSdk >= 34; Flutter's bundled default resolves
    // lower, so pin it explicitly.
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.yenefsabat.yenefs_abat"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
            // AGP 8+ enables R8 minification by default for release builds
            // whether or not this is set — made explicit here so it's a
            // deliberate choice, paired with proguard-rules.pro (needed by
            // flutter_local_notifications' Gson-based persistence, see
            // that file for why).
            isMinifyEnabled = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
