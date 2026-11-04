plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.safefamily.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.safefamily.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        // Số commit của git: pull về build tiếp là versionCode tăng, Android luôn cho cài đè lên bản cũ.
        // (Không có git thì dùng số trong pubspec.yaml.)
        versionCode = runCatching {
            ProcessBuilder("git", "rev-list", "--count", "HEAD")
                .directory(rootDir)
                .redirectErrorStream(true)
                .start()
                .inputStream.bufferedReader().readText().trim().toInt()
        }.getOrNull() ?: flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Ký bằng khóa debug của máy build (ANDROID_USER_HOME/debug.keystore). Bản debug cũng ký bằng khóa này nên
            // debug và release cài đè được lên nhau. Đổi sang khóa khác = phải gỡ cài lại một lần.
            // TODO: khóa riêng khi phát hành thật.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // Vị trí + hàng rào địa lý (máy con).
    implementation("com.google.android.gms:play-services-location:21.3.0")
    // flutter_local_notifications cần desugaring (thông báo mẹ khi app đóng).
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
