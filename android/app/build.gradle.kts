import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// AdMob : App ID de TEST Google par défaut. Vrai ID (jamais committé), lu
// seulement hors dépôt : variable d'environnement ORG_GRADLE_PROJECT_admobAppId
// ou `admob.appId=…` dans android/local.properties (ignoré par git). Pas de
// gradle.properties (suivi). Voir README § AdMob.
val admobTestAppId = "ca-app-pub-3940256099942544~3347511713"
val localProperties = Properties().apply {
    val file = rootProject.file("local.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}
val admobAppId: String = System.getenv("ORG_GRADLE_PROJECT_admobAppId")
    ?: localProperties.getProperty("admob.appId")
    ?: admobTestAppId

// Build release avec l'ID de test : avertissement, ou échec avec
// -PrequireRealAdmobId=true (via flutter : ORG_GRADLE_PROJECT_requireRealAdmobId=true),
// à utiliser pour les builds envoyés aux stores.
gradle.taskGraph.whenReady {
    val release = allTasks.any { it.project == project && it.name.contains("Release") }
    if (release && admobAppId.contains("3940256099942544")) {
        val message = "AdMob : build release avec l'App ID de TEST Google (voir README § AdMob)."
        if (findProperty("requireRealAdmobId") == "true") throw GradleException(message)
        logger.warn("ATTENTION : $message")
    }
}

android {
    namespace = "com.quizzeo.quizzeo"
    // flutter_local_notifications 23 exige compileSdk 37 minimum.
    compileSdk = maxOf(flutter.compileSdkVersion, 37)
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Requis par flutter_local_notifications (notifications programmées).
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.quizzeo.quizzeo"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["admobAppId"] = admobAppId
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
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
