#ifndef RUNNER_SECURE_STORE_H_
#define RUNNER_SECURE_STORE_H_

#include <flutter/flutter_engine.h>

// v1.6.0 电脑端安全加固 —— Windows DPAPI 安全存储通道。
//
// 注册一个 MethodChannel（名 `com.dzy.cloud/secure_store`），把 Windows 自带的
// DPAPI（CryptProtectData / CryptUnprotectData）暴露给 Dart，用于对落盘的
// token 类字段做**按当前用户加密**：密文只能被同一台机器上的同一 Windows 用户解开，
// 拷到别的机器 / 别的账户即无法解密。不引入任何第三方依赖。
//
// 方法：
//   available            -> bool   通道可用性
//   protect(data:str)    -> str    base64(DPAPI 密文)
//   unprotect(data:str)  -> str    明文
//
// 必须在 Flutter engine 创建后、Dart 读取 token 之前调用（见 flutter_window.cpp
// 的 OnCreate，紧跟在 RegisterPlugins 之后）。
void RegisterSecureStoreChannel(flutter::FlutterEngine* engine);

#endif  // RUNNER_SECURE_STORE_H_
