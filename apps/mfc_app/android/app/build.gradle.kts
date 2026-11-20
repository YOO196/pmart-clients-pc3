import java.util.Base64

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 목업 앱과 실서버 앱을 구별한다(사용자 2026-11-20 "목업 앱이랑 실서버 앱 구별이 안 돼").
// flutter build 가 넘기는 --dart-define 값(base64, 쉼표로 이음)에서 PMART_ENV 를 읽는다 — 없으면 앱과 같이 mock.
// 목업: 앱 ID 끝 .mock(실서버 앱과 따로 설치), 이름 "픽PDA 목업", 주황 바탕 아이콘, 로그인 복귀 주소 따로(실서버 로그인 때 고르기 창이 뜨지 않게).
val dartDefines: Map<String, String> =
    (project.findProperty("dart-defines") as String?)
        .orEmpty()
        .split(",")
        .filter { it.isNotBlank() }
        .map { String(Base64.getDecoder().decode(it)) }
        .filter { it.indexOf('=') > 0 }
        .associate { it.substringBefore('=') to it.substringAfter('=') }
val isMockBuild = (dartDefines["PMART_ENV"] ?: "mock") == "mock"

android {
    namespace = "com.pmart.mfc_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = if (isMockBuild) "com.pmart.mfc_app.mock" else "com.pmart.mfc_app"
        manifestPlaceholders["appLabel"] = if (isMockBuild) "픽PDA 목업" else "픽PDA 실서버"
        manifestPlaceholders["appIcon"] = if (isMockBuild) "@mipmap/ic_launcher_mock" else "@mipmap/ic_launcher"
        manifestPlaceholders["loginScheme"] = if (isMockBuild) "pmart-mfc-mock" else "pmart-mfc"
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
