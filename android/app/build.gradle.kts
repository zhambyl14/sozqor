import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("com.google.gms.google-services")
    id("dev.flutter.flutter-gradle-plugin")
}

// The upload key lives outside the repository: a leaked key cannot be revoked,
// only abandoned, so `android/key.properties` and `*.jks` stay gitignored and
// the build reads them only when the machine actually has them.
val keystorePropsFile = rootProject.file("key.properties")
val keystoreProps = Properties().apply {
    if (keystorePropsFile.exists()) {
        keystorePropsFile.inputStream().use { load(it) }
    }
}

android {
    namespace = "com.example.sozqor_app"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications needs the java.time backport on older APIs
        isCoreLibraryDesugaringEnabled = true
    }

    // Kotlin 2.3 removed the kotlinOptions DSL outright — `jvmTarget: String`
    // is a hard error there, not a warning. The plugin had to move to 2.3 so
    // play-services-ads 25.x, whose metadata is Kotlin 2.3, would compile.
    kotlin {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
    }

    defaultConfig {
        // Must stay in sync with the package_name inside google-services.json,
        // which is why renaming this away from com.example — which both stores
        // refuse — is a Firebase step, not a one-line edit. STORE.md §1 has the
        // order to do it in.
        applicationId = "com.example.sozqor_app"
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        // Declared only when the key file is there — an empty signing config
        // fails the whole configuration phase, which would break the build for
        // everyone who does not hold the key.
        if (keystorePropsFile.exists()) {
            create("release") {
                storeFile = keystoreProps.getProperty("storeFile")?.let { file(it) }
                storePassword = keystoreProps.getProperty("storePassword")
                keyAlias = keystoreProps.getProperty("keyAlias")
                keyPassword = keystoreProps.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        getByName("release") {
            // Without key.properties this falls back to the debug key so a
            // checkout still builds and runs in release mode. That is never
            // mistaken for a shippable artifact: both stores reject a
            // debug-signed upload outright. See STORE.md.
            signingConfig = signingConfigs.findByName("release")
                ?: signingConfigs.getByName("debug")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")

    // Firebase is used for push notifications only; data lives in Supabase.
    implementation(platform("com.google.firebase:firebase-bom:33.7.0"))
    implementation("com.google.firebase:firebase-messaging")
    implementation("com.google.firebase:firebase-analytics")
}
