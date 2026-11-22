#include "secure_store.h"

#include <windows.h>
#include <wincrypt.h>

#include <memory>
#include <string>

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

namespace {

// MethodChannel 必须存活到进程结束，否则注册后 Dart 侧调用会因 handler 被回收而失败。
std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> g_channel;

// base64（无换行）
bool Base64Encode(const BYTE* data, DWORD len, std::string* out) {
  DWORD chars = 0;
  if (!CryptBinaryToStringA(data, len,
                            CRYPT_STRING_BASE64 | CRYPT_STRING_NOCRLF, nullptr,
                            &chars) ||
      chars == 0) {
    return false;
  }
  out->resize(chars);
  if (!CryptBinaryToStringA(data, len,
                            CRYPT_STRING_BASE64 | CRYPT_STRING_NOCRLF,
                            &(*out)[0], &chars)) {
    return false;
  }
  // 返回值含结尾 '\0'，去掉
  if (chars > 0 && (*out)[chars - 1] == '\0') {
    out->resize(chars - 1);
  }
  return true;
}

bool Base64Decode(const std::string& in, std::string* out) {
  if (in.empty()) {
    out->clear();
    return true;
  }
  DWORD bytes = 0;
  if (!CryptStringToBinaryA(in.c_str(), static_cast<DWORD>(in.size()),
                            CRYPT_STRING_BASE64, nullptr, &bytes, nullptr,
                            nullptr)) {
    return false;
  }
  if (bytes == 0) {
    out->clear();
    return true;
  }
  out->resize(bytes);
  if (!CryptStringToBinaryA(in.c_str(), static_cast<DWORD>(in.size()),
                            CRYPT_STRING_BASE64,
                            reinterpret_cast<BYTE*>(&(*out)[0]), &bytes, nullptr,
                            nullptr)) {
    return false;
  }
  out->resize(bytes);
  return true;
}

bool DpapiProtect(const std::string& plain, std::string* out_b64) {
  DATA_BLOB in = {};
  in.pbData = reinterpret_cast<BYTE*>(const_cast<char*>(plain.data()));
  in.cbData = static_cast<DWORD>(plain.size());
  DATA_BLOB out = {};
  if (!CryptProtectData(&in, L"dzy-cloud-token", nullptr, nullptr, nullptr,
                        CRYPTPROTECT_UI_FORBIDDEN, &out)) {
    return false;
  }
  const bool ok = Base64Encode(out.pbData, out.cbData, out_b64);
  LocalFree(out.pbData);
  return ok;
}

bool DpapiUnprotect(const std::string& b64, std::string* out_plain) {
  std::string blob;
  if (!Base64Decode(b64, &blob) || blob.empty()) {
    return false;
  }
  DATA_BLOB in = {};
  in.pbData = reinterpret_cast<BYTE*>(const_cast<char*>(blob.data()));
  in.cbData = static_cast<DWORD>(blob.size());
  DATA_BLOB out = {};
  if (!CryptUnprotectData(&in, nullptr, nullptr, nullptr, nullptr,
                          CRYPTPROTECT_UI_FORBIDDEN, &out)) {
    return false;
  }
  out_plain->assign(reinterpret_cast<char*>(out.pbData),
                    static_cast<size_t>(out.cbData));
  LocalFree(out.pbData);
  return true;
}

}  // namespace

void RegisterSecureStoreChannel(flutter::FlutterEngine* engine) {
  if (engine == nullptr || engine->messenger() == nullptr) {
    return;
  }
  if (g_channel) {
    return;
  }

  g_channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      engine->messenger(), "com.dzy.cloud/secure_store",
      &flutter::StandardMethodCodec::GetInstance());

  g_channel->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
             result) {
        const std::string& method = call.method_name();

        if (method == "available") {
          result->Success(flutter::EncodableValue(true));
          return;
        }

        const std::string* arg =
            std::get_if<std::string>(call.arguments());
        if (arg == nullptr) {
          result->Error("bad_args", "expected a string argument");
          return;
        }

        if (method == "protect") {
          std::string b64;
          if (DpapiProtect(*arg, &b64)) {
            result->Success(flutter::EncodableValue(b64));
          } else {
            result->Error("protect_failed", "CryptProtectData failed");
          }
        } else if (method == "unprotect") {
          std::string plain;
          if (DpapiUnprotect(*arg, &plain)) {
            result->Success(flutter::EncodableValue(plain));
          } else {
            result->Error("unprotect_failed", "CryptUnprotectData failed");
          }
        } else {
          result->NotImplemented();
        }
      });
}
