import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// ── 发布签名（W16 发布准备）────────────────────────────────────────
// android/key.properties 保存正式密钥信息，**不入库**（见 .gitignore）。
// 文件缺失时降级为 debug 签名：这样 `flutter build apk --release` 在开发机上
// 依然能跑通（用于验证 minify / proguard 链路是否正常），
// 但产出的包**不能分发、不能上架**。
// 生成正式密钥与填写 key.properties 的步骤见 docs/release-checklist-w16.md。
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKey = keystorePropertiesFile.exists()
if (hasReleaseKey) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
} else {
    logger.warn(
        "[plainleaf] android/key.properties 缺失 -> release 构建将使用 DEBUG 签名。" +
            "该包仅供本机验证混淆链路，禁止分发或上架。"
    )
}

android {
    namespace = "com.plainleaf.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // 包名按开发文档 §二 统一为 com.plainleaf.app
        applicationId = "com.plainleaf.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // 版本号唯一真源是 pubspec.yaml 的 version（<里程碑线>+<周次>），
        // 这里只做透传，不要在此硬编码。
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = keystoreProperties.getProperty("storeFile")?.let { file(it) }
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKey) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            // W16：release 开混淆与资源压缩。规则见 app/proguard-rules.pro。
            // 必须同时为 true —— 只开 isShrinkResources 不生效。
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
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
