import java.io.File
import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("com.google.gms.google-services")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val libsignalVersion = "0.91.0"
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
val hasReleaseKeystore = keystorePropertiesFile.exists()
val allowDebugReleaseSigning =
    providers.gradleProperty("VAULT_ALLOW_DEBUG_RELEASE_SIGNING").orNull == "true"
val semanticVersionRegex = Regex("""^(\d+)\.(\d+)\.(\d+)$""")

fun toAndroidVersionCode(versionName: String): Int {
    val match = semanticVersionRegex.matchEntire(versionName)
        ?: error("Vault version must be major.minor.patch, got '$versionName'")
    val (majorText, minorText, patchText) = match.destructured
    val major = majorText.toInt()
    val minor = minorText.toInt()
    val patch = patchText.toInt()
    require(minor in 0..99) { "Vault minor version must stay between 0 and 99 for Android versionCode" }
    require(patch in 0..99) { "Vault patch version must stay between 0 and 99 for Android versionCode" }
    return (major * 10000) + (minor * 100) + patch
}

if (hasReleaseKeystore) {
    FileInputStream(keystorePropertiesFile).use { stream ->
        keystoreProperties.load(stream)
    }
}

android {
    namespace = "com.theconquerorscourt.vault"
    compileSdk = 36

    // 🔒 Pin NDK to satisfy shared_preferences_android
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.theconquerorscourt.vault"
        minSdk = 23
        targetSdk = flutter.targetSdkVersion
        versionName = flutter.versionName
        versionCode = toAndroidVersionCode(versionName!!)
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                val required = { name: String ->
                    keystoreProperties.getProperty(name)
                        ?: error("Missing '$name' in android/key.properties")
                }
                val storePath = required("storeFile")
                storeFile = if (File(storePath).isAbsolute) {
                    File(storePath)
                } else {
                    rootProject.file(storePath)
                }
                storePassword = required("storePassword")
                keyAlias = required("keyAlias")
                keyPassword = required("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            if (hasReleaseKeystore) {
                signingConfig = signingConfigs.getByName("release")
            } else if (allowDebugReleaseSigning) {
                signingConfig = signingConfigs.getByName("debug")
            }
        }
    }

    packaging {
        resources {
            excludes += setOf(
                "libsignal_jni*.dylib",
                "signal_jni*.dll",
                "libsignal_jni_testing.so",
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation("org.signal:libsignal-client:$libsignalVersion")
    implementation("org.signal:libsignal-android:$libsignalVersion")
}

gradle.taskGraph.whenReady {
    val requiresReleaseSigning = allTasks.any { task ->
        task.project.path == project.path && task.name.contains("Release", ignoreCase = true)
    }
    if (requiresReleaseSigning && !hasReleaseKeystore && !allowDebugReleaseSigning) {
        throw org.gradle.api.GradleException(
            "Missing Android release signing config. Copy android/key.properties.template " +
                "to android/key.properties, fill in your upload keystore details, and run again.",
        )
    }
}
