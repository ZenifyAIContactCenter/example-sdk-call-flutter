# call-flutter-example

App Flutter demo dùng SDK gọi điện [`zenify_call`](https://pub.dev/packages/zenify_call) **từ pub.dev**:
đăng nhập bằng email + API key, nhận / gọi cuộc gọi qua PJSIP, nhận push VoIP / FCM khi app ở nền
hoặc đã tắt. Sau khi đăng nhập có 2 tab mô phỏng app CRM tích hợp SDK:
- **CRM**: danh sách khách cần liên hệ, bấm 📞 là gọi (click-to-call).
- **Gọi**: nhập số / extension, chọn theme màn cuộc gọi → mở màn quay số SDK điền sẵn số.

Kèm server mẫu Node.js ở [`server/`](server/README.md): nhận webhook "Cuộc gọi App SDK" của Zenify rồi
bắn push cuộc gọi (APNs VoIP cho iOS, FCM cho Android) đúng payload SDK cần.

| Thư mục | Nội dung |
| --- | --- |
| `lib/` | App demo (`main.dart`: luồng đăng nhập → gọi; `demo_home.dart`: tab CRM / Gọi) |
| `server/` | Server push mẫu (Node.js ≥ 18, không cần `npm install`) |
| `docs/images/` | Ảnh hướng dẫn: webhook trên web Zenify, key APNs, Firebase |
| `tool/` | `bump_version.sh`, `gen_firebase_options.py` |

## Phiên bản SDK

`pubspec.yaml` lấy `zenify_call` từ pub.dev (`^0.1.1`). Nâng SDK: `flutter pub upgrade zenify_call`.

Thử bản SDK đang sửa ở máy (repo `sdk-call-flutter` nằm cạnh repo này) mà không sửa `pubspec.yaml`:
tạo `pubspec_overrides.yaml` (đã nằm trong `.gitignore`):

```yaml
dependency_overrides:
  zenify_call:
    path: ../sdk-call-flutter/packages/zenify_call
```

## Cấu hình

### Firebase (push)

App demo cần project Firebase **của bạn** (không kèm theo package):

1. Tạo app Android + iOS trong Firebase với bundle id / applicationId của demo
   (`com.example.sdk.zenify` — đổi được trong `android/app/build.gradle.kts` và project Xcode).
2. Tải `google-services.json` → `android/app/`, `GoogleService-Info.plist` → `ios/Runner/`.
3. Sinh `lib/firebase_options.dart`: `python3 tool/gen_firebase_options.py`.
4. iOS: upload key APNs (`.p8`) vào Firebase (Project settings → Cloud Messaging). VoIP push gửi
   thẳng qua APNs tới topic `<bundle id>.voip`.

### Ký app iOS

```sh
cp ios/Flutter/Team.xcconfig.example ios/Flutter/Team.xcconfig   # điền Team ID của bạn (không commit)
cd ios && pod install
```

Đổi bundle id `com.example.sdk.zenify` sang bundle id của bạn (Xcode → Runner → Signing & Capabilities)
nếu team của bạn không sở hữu bundle id này. Bật capability **Push Notifications** và **Background
Modes** (Voice over IP, Remote notifications).

### Tài khoản

```sh
cp dart_defines.example.json dart_defines.local.json   # điền ZC_EMAIL, ZC_API_KEY (không commit)
```

| Biến | Ý nghĩa |
| --- | --- |
| `ZC_EMAIL` | Email agent (điền sẵn ở màn đăng nhập) |
| `ZC_API_KEY` | API key tenant (`/auth/sdk/sign-in`) |
| `ZC_AUTO` | `true` = tự đăng nhập + tự nghe cuộc gọi đến (kiểm thử) |
| `ZC_DEMO_PHONE` | Số gọi thử ở màn CRM / Gọi thủ công (mặc định `0900000000`) |
| `ZC_DEMO_CUSTOMERS` | Danh sách khách màn CRM — chuỗi JSON `[{name, phone, tag, note, history}]` (mặc định dữ liệu mẫu) |

Lệnh chạy / build nào cũng phải kèm `--dart-define-from-file=dart_defines.local.json`, vì các giá trị
này được đóng vào app lúc build.

## Chạy

```sh
flutter run --dart-define-from-file=dart_defines.local.json            # debug
flutter run --profile --dart-define-from-file=dart_defines.local.json  # profile: có log, chạy như release
```

> **Test cuộc gọi đến / push: dùng profile hoặc release.** Từ iOS 14, bản debug không chạy được khi
> không gắn với `flutter run` / Xcode. Push đánh thức app trong nền thì app chết, server đổi
> `phone_type` về 0, nên chỉ nhận được cuộc gọi đầu.

## Đổi version (1.0.x)

`./tool/bump_version.sh` đổi đồng thời:
- `version:` trong `pubspec.yaml` → Android `versionName` / `versionCode`
- Version / Build ở tab General của Xcode (`MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`) → iOS.
  `Info.plist` đọc 2 giá trị này, nên Archive bằng Xcode hay `flutter build ipa` đều ra cùng version.

```sh
./tool/bump_version.sh          # 1.0.1+1 → 1.0.2+2  (x +1, build number +1)
./tool/bump_version.sh 1.0.7    # đặt version 1.0.7, build number vẫn +1
```

Build number luôn tăng — TestFlight / Play Store từ chối build trùng số. Chạy trước khi build release.

## Build release

### Android

```sh
# APK — cài thử trực tiếp
flutter build apk --release --dart-define-from-file=dart_defines.local.json
# → build/app/outputs/flutter-apk/app-release.apk

# AAB — Google Play
flutter build appbundle --release --dart-define-from-file=dart_defines.local.json
# → build/app/outputs/bundle/release/app-release.aab

# Cài APK lên máy đang cắm cáp
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

Bản release hiện **ký bằng debug key** (`android/app/build.gradle.kts`): cài thử được, nhưng không
đưa lên Play Store được.

### iOS

```sh
# .ipa — TestFlight / App Store (tải lên bằng Transporter)
flutter build ipa --release --dart-define-from-file=dart_defines.local.json
# → build/ios/ipa/*.ipa

# Chạy bản release trên máy thật đang cắm cáp
flutter run --release --dart-define-from-file=dart_defines.local.json
```

Ký tự động — chọn **Team của bạn** ở Xcode → Runner → Signing & Capabilities trước khi build. Simulator không chạy bản release.

## Chạy / build trên một máy cụ thể

Nhiều máy cùng cắm (hoặc cùng Wi-Fi) thì chỉ định máy bằng `-d <id>`. `<id>` là cột thứ 2 của
`flutter devices` (UDID iOS / serial Android); viết một phần tên máy cũng được (`-d iPhone`, `-d Pixel`).

```sh
flutter devices                                   # liệt kê máy: tên • id • nền tảng
adb devices                                       # Android: serial cho adb -s
xcrun devicectl list devices                      # iOS: UDID cho devicectl

# Chạy thẳng lên máy (build + cài + mở app, xem log trong terminal)
flutter run -d <id> --release --dart-define-from-file=dart_defines.local.json
flutter run -d <id> --profile --dart-define-from-file=dart_defines.local.json   # có log, chạy như release

# Android: build APK rồi cài lên đúng máy
flutter build apk --release --dart-define-from-file=dart_defines.local.json
flutter install -d <id> --release                 # hoặc:
adb -s <serial> install -r build/app/outputs/flutter-apk/app-release.apk

# iOS: build bản release rồi cài lên đúng máy (không cần TestFlight)
flutter build ios --release --dart-define-from-file=dart_defines.local.json
flutter install -d <udid> --release               # hoặc:
xcrun devicectl device install app --device <udid> build/ios/iphoneos/Runner.app

# iOS Ad Hoc (.ipa, APNs production — giống TestFlight) rồi cài lên đúng máy
flutter build ipa --release --export-method ad-hoc --dart-define-from-file=dart_defines.local.json
unzip -oq build/ios/ipa/*.ipa -d build/ios/ipa/adhoc   # devicectl chỉ nhận .app, không nhận .ipa
xcrun devicectl device install app --device <udid> build/ios/ipa/adhoc/Payload/Runner.app
```

- iOS: `flutter run` / `flutter build ios` ký bằng `aps-environment = development` → token VoIP
  **sandbox**. Ad Hoc / TestFlight → token **production**.
- iOS Ad Hoc chỉ cài được lên máy có UDID nằm trong provisioning profile.
