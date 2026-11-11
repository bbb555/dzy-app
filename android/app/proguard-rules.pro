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
# androidx.window（Flutter 引擎依赖）引用的可选 OEM 扩展类，运行时按需反射加载
-dontwarn androidx.window.extensions.**
-dontwarn androidx.window.sidecar.**

# url_launcher（打开官网注册 / 找回密码 / 续费等页面）：保留插件与 Custom Tabs 回退
-keep class io.flutter.plugins.urllauncher.** { *; }
-keep class androidx.browser.customtabs.** { *; }
-dontwarn androidx.browser.**

# v1.3.0 加固：Release 包移除 Log.v / Log.d / Log.i 调用（保留 w / e 便于排查崩溃），
# 避免节点、配置等调试信息出现在 logcat
-assumenosideeffects class android.util.Log {
    public static int v(...);
    public static int d(...);
    public static int i(...);
}
