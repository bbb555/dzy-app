# Flutter Wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# Keep native interface classes
-keep class hev.htproxy.** { *; }
-keep class com.flux.app.flux.** { *; }
-keepnames class * extends android.app.Activity
-keepnames class * extends android.app.Application
-keepnames class * extends android.app.Service
-keepnames class * extends android.content.BroadcastReceiver
-keepnames class * extends android.content.ContentProvider

# Keep Flutter Embedding
-keep class io.flutter.embedding.** { *; }

# Suppress Play Store missing class warnings (common in Flutter release builds)
-dontwarn io.flutter.embedding.android.FlutterPlayStoreSplitApplication
-dontwarn com.google.android.play.core.splitcompat.**
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**

# 队长云：保留应用自身的 Activity / VpnService / JNI 桥接类（tun2socks 通过 JNI 回调）
-keep class com.example.flux.** { *; }
-keep class hev.** { *; }
-dontwarn org.jetbrains.annotations.**
