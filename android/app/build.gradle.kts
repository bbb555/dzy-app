import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.flux"
    compileSdk = 36
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.dzy.cloud"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = 34
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        

    }

    val keystorePropertiesFile = rootProject.file("key.properties")
    val keystoreProperties = Properties()
    if (keystorePropertiesFile.exists()) {
        keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            val storeFileName = keystoreProperties["storeFile"] as String?
            storeFile = if (storeFileName != null) project.file(storeFileName) else null
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }

    buildTypes {
        debug {
            applicationIdSuffix = ".debug"
            isDebuggable = true
        }
        release {
            // Release 签名：CI 从 Actions secrets 生成 android/key.properties + keystore
            signingConfig = signingConfigs.getByName("release")
            // 瘦身：R8 代码压缩 + 无用资源移除
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    packaging {
        jniLibs {
            // libxray.so 需要以可执行文件形式解压到 nativeLibraryDir（MainActivity 以进程方式启动）
            useLegacyPackaging = true
            // libxray.so 为 XTLS 官方发布的二进制，保持与官方 sha256 完全一致，不做 strip
            keepDebugSymbols += "**/libxray.so"
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // libv2ray.aar 已移除：代码中未使用（实际内核为 jniLibs/libxray.so 独立进程）
    // Android 12+ SplashScreen 兼容库
    implementation("androidx.core:core-splashscreen:1.0.1")
    // 应用内更新：FileProvider（Flutter 插件已在运行时依赖 androidx.core，这里只是显式声明编译依赖）
    implementation("androidx.core:core:1.13.1")
}
