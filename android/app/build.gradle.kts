plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.centli.centli"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        buildConfig = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.centli.centli"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = maxOf(flutter.minSdkVersion, 24)
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        debug {
            // Side-by-side with release: com.centli.centli.debug
            applicationIdSuffix = ".debug"
            resValue("string", "app_name", "厘记 Debug")
            resValue("string", "notification_listener_label", "厘记 Debug 账单监听")
            resValue("string", "widget_title", "厘记 Debug")
        }
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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

flutter {
    source = "../.."
}

// 打包产物文件名（AGP 9 / Gradle 9：用 base.archivesName，替代已移除的 archivesBaseName）
// 模块名默认是 app，不设此项会得到 app-release.apk / app-debug.apk。
// 最终形如：Centli-2.1.3-46-release.apk、Centli-2.1.3-46-debug.apk
// （versionName / versionCode 与 pubspec.yaml 的 version: x.y.z+build 同步，由 Flutter Gradle 注入）
// 若日后加 productFlavor，Gradle 会自动拼进变体名，例如 Centli-2.1.3-46-freeRelease.apk。
base {
    archivesName.set("Centli-${flutter.versionName}-${flutter.versionCode}")
}
