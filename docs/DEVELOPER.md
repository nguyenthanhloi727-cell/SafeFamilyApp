# SafeFamily — Tài liệu lập trình viên

## 1. Môi trường

- Flutter 3.47 (nhóm dùng 3.47.5, kênh stable), Android Studio (JDK đi kèm).
- Android SDK Platform **36** và **35**, Build-Tools 36, **NDK 28.2.13676358**, CMake 3.22.1. Cài trong Android Studio → Settings → Android SDK (SDK Tools: tick *Show Package Details*).
- `flutter doctor`: dòng Android toolchain phải ✓ (bỏ qua Visual Studio / Chrome).

## 2. Cấu trúc thư mục

```
lib/
  main.dart
  app/                  # MaterialApp, cổng thiết lập lần đầu, khung 5 tab (BottomNavigationBar + IndexedStack)
  core/
    constants/          # AppInfo (tên app, applicationId), AppLanguage, feature_flags
    security/           # ParentGuard, băm PIN, khóa khi sai, sinh trắc (local_auth), nhật ký
      ui/               # bàn phím PIN, màn nhập PIN, ParentGate, dải chế độ trẻ em
    services/           # ExternalLauncher (tel/YouTube/mailto), SystemSettings (mở Cài đặt)
    settings/           # VoiceLanguageSettings (ngôn ngữ giọng nói dùng chung)
    theme/              # màu, chữ, khoảng cách, bo góc (theo DESIGN.md)
    widgets/            # widget dùng chung
  features/
    home/               # Trang chủ, Quản lý thiết bị (giữ chỗ)
    translate/          # Dịch (giữ chỗ)
    alarm/{domain,data,presentation}   # bộ hiểu giờ 5 ngôn ngữ (Dart thuần), speech_to_text, SET_ALARM
    team/{data,presentation}           # members.json, ảnh thành viên
    profile/{data,presentation}        # danh bạ gia đình, Cài đặt
    parental/presentation              # thiết lập lần đầu, đổi PIN, bảo mật, nhật ký
assets/fonts/           # Be Vietnam Pro + OFL.txt
assets/team/            # members.json + ảnh cố định <id>.jpg (xem assets/team/README.md)
tool/                   # công cụ nội bộ nhóm
test/                   # unit + widget test; test/helpers = đồ giả dùng chung
```

Quy ước: import trong `lib/` dùng đường dẫn tương đối (lint `prefer_relative_imports`); state bằng `ChangeNotifier` có sẵn; mỗi tính năng tách `data/` (interface + bản cài đặt) và `presentation/`.

## 3. Package

Phiên bản: xem `pubspec.yaml`.

| Package | Dùng cho | Link |
|---|---|---|
| shared_preferences | Lưu danh bạ, tên phụ huynh, ngôn ngữ, đường dẫn ảnh | [pub.dev](https://pub.dev/packages/shared_preferences) |
| url_launcher | Mở màn quay số, YouTube, app mail | [pub.dev](https://pub.dev/packages/url_launcher) |
| image_picker | Chọn ảnh thành viên từ thư viện | [pub.dev](https://pub.dev/packages/image_picker) |
| path_provider | Thư mục riêng của app để chép ảnh | [pub.dev](https://pub.dev/packages/path_provider) |
| speech_to_text | Nhận giọng nói (Báo thức) | [pub.dev](https://pub.dev/packages/speech_to_text) |
| android_intent_plus | Intent `SET_ALARM`, mở trang Cài đặt | [pub.dev](https://pub.dev/packages/android_intent_plus) |
| local_auth | Xác thực vân tay / khuôn mặt | [pub.dev](https://pub.dev/packages/local_auth) |
| local_auth_android | Chữ tiếng Việt trên hộp thoại sinh trắc | [pub.dev](https://pub.dev/packages/local_auth_android) |
| flutter_secure_storage | Lưu PIN đã băm, trạng thái khóa, nhật ký (Android Keystore) | [pub.dev](https://pub.dev/packages/flutter_secure_storage) |
| crypto | HMAC-SHA256 cho PBKDF2 băm PIN | [pub.dev](https://pub.dev/packages/crypto) |
| flutter_localizations | *(Flutter SDK)* chữ Material tiếng Việt | — |
| shared_preferences_platform_interface | *(chỉ test)* bộ nhớ giả | [pub.dev](https://pub.dev/packages/shared_preferences_platform_interface) |

## 4. Quyền Android (`android/app/src/main/AndroidManifest.xml`)

| Quyền | Lý do |
|---|---|
| `RECORD_AUDIO` | Nói giờ báo thức; chỉ hỏi khi bấm micro lần đầu |
| `INTERNET` | Dịch vụ nhận giọng nói có thể dùng máy chủ |
| `com.android.alarm.permission.SET_ALARM` | Gửi giờ sang app Đồng hồ (không hỏi người dùng) |
| `USE_BIOMETRIC` | Khóa phụ huynh bằng vân tay / khuôn mặt |

**Không** xin `CALL_PHONE` (chỉ mở màn quay số) và không xin quyền Bluetooth.
`<queries>`: `tel`, `https`, `mailto`, `android.speech.RecognitionService`, `SET_ALARM` (Android 11+).
`MainActivity` là `FlutterFragmentActivity` (local_auth yêu cầu) và có MethodChannel `safefamily/biometric_hardware` báo máy có vân tay/khuôn mặt. `LaunchTheme` dùng `Theme.AppCompat.DayNight.NoActionBar`.

## 5. Khóa phụ huynh — `ParentGuard`

`lib/core/security/parent_guard.dart`, đưa xuống cây bằng `ParentGuardScope` (tạo trong `app.dart`).

Màn hình **chỉ gọi `ParentGate`** (`core/security/ui/parent_gate.dart`), không tự viết logic:

```dart
// Thao tác chỉ khóa khi đang ở chế độ trẻ em (sửa danh bạ, đặt báo thức…)
if (!await ParentGate.childAction(context, 'Sửa danh bạ')) return;

// Vào khu vực phụ huynh (cài đặt, nhật ký, quản lý): không hỏi lại nếu vừa xác thực
if (!await ParentGate.parentArea(context, 'Mở Cài đặt')) return;

// Luôn hỏi (đổi PIN, bật/tắt sinh trắc…)
if (!await ParentGate.always(context, 'Đổi mã PIN')) return;
```

- Ưu tiên sinh trắc (nếu máy hỗ trợ và đã bật), không được thì nhập PIN.
- PIN 4–6 số, chặn dãy dễ đoán; chỉ lưu `pbkdf2-sha256$100000$<salt>$<hash>`.
- Sai 5 lần khóa 30 giây, sau đó gấp đôi (tối đa 30 phút); lưu qua khi tắt app.
- Màn thuộc khu vực phụ huynh bọc bằng `ParentAreaGuard` → tự đóng khi phiên hết hạn.
- Không có `ParentGuardScope` (test màn lẻ) → `ParentGate` cho qua.

## 6. Tên app theo thành viên

Repo luôn để tên mặc định `nguyenthanhloi`. Thành viên nhóm dùng công cụ nội bộ `tool/rename.dart` (hướng dẫn gửi riêng trong nhóm) và trả về tên mặc định trước khi commit.

## 7. Test

```bash
flutter analyze
```

```bash
flutter test
```

Test app-level (`test/widget_test.dart`) không dùng `pumpAndSettle` sau khi vào app (tab Nhóm đọc assets thật). Đồ giả: `test/helpers/` (launcher, kho bảo mật, sinh trắc).

## 8. Quy trình git & phát hành

1. Tra pub.dev → code → `flutter analyze` → `flutter test` → chạy trên máy thật → duyệt → commit + push.
2. Thêm/bỏ package hoặc quyền Android → **cập nhật file này trong cùng commit**.
3. Phát hành:

```bash
flutter build apk --release
```

   - Đặt `version` trong `pubspec.yaml` trước khi build (ví dụ `0.6.0+1`).
   - APK ở `build/app/outputs/flutter-apk/app-release.apk` → đổi tên `SafeFamily-v<phiên bản>.apk`.
   - Ký bằng khóa debug (đủ cho thử nghiệm). **Không** commit APK, keystore, `key.properties`, `local.properties` (đã chặn trong `.gitignore`).
   - Tạo Release: `gh release create v<phiên bản> <file.apk> --prerelease --title ... --notes ...`

## 9. Lỗi thường gặp

### Build lỗi: `sdkmanager.bat ... finished with non-zero exit value -1073740791 (NTSTATUS 0xC0000409)`

- **Nguyên nhân:** máy thiếu SDK Platform 36 hoặc NDK 28.2. Gradle tự gọi `sdkmanager` để cài, nhưng **Command-line Tools bản 23** bị crash khi thoát nên cài thất bại.
- **Cách sửa:** cài tay **SDK Platform 36** và **NDK 28.2.13676358** bằng Android Studio ([mục 1](#1-môi-trường)), rồi build lại.
- Dùng dòng lệnh thay cho Android Studio (gọi thẳng `android.exe`, không qua `sdkmanager.bat`):

  ```bash
  "%ANDROID_HOME%\cmdline-tools\latest\bin\android.exe" --no-metrics sdk install platforms/android-36
  ```

  ```bash
  "%ANDROID_HOME%\cmdline-tools\latest\bin\android.exe" --no-metrics sdk install ndk/28.2.13676358
  ```

  Lệnh có thể vẫn báo crash lúc thoát nhưng gói đã được cài — kiểm tra thư mục `platforms\android-36` và `ndk\28.2.13676358` trong SDK.

### Build lỗi: `Package ndk not found` / `Failed to find NDK`

Thiếu NDK đúng bản **28.2.13676358** — cài như trên. Cài bản NDK khác không được.

### `flutter run` lỗi: `INSTALL_FAILED_USER_RESTRICTED: Install canceled by user`

- **Nguyên nhân:** Xiaomi/Redmi/POCO chặn cài app qua USB.
- **Cách sửa:** Tùy chọn nhà phát triển → bật **Cài đặt qua USB** (cần tài khoản Mi, SIM + dữ liệu di động). Khi chạy lại, để màn hình mở khoá và bấm **Cài đặt** ở hộp thoại hiện lên.

### `adb devices` báo `unauthorized`

Điện thoại chưa cho phép máy tính gỡ lỗi. Mở khoá màn hình → bấm **Cho phép** ở hộp thoại *"Cho phép gỡ lỗi USB?"*. Không thấy hộp thoại: Tùy chọn nhà phát triển → **Thu hồi ủy quyền gỡ lỗi USB** → rút cáp cắm lại.

### `flutter devices` không thấy điện thoại

- Đổi sang **cáp truyền dữ liệu** (cáp chỉ sạc không được), thử cổng USB khác (ưu tiên cổng sau thùng máy).
- Chọn chế độ USB **Truyền tệp** trên điện thoại. Nếu máy tính không hiện ổ điện thoại trong File Explorer → lỗi cáp/cổng.
- Kiểm tra đã bật **Gỡ lỗi USB**.

### `'flutter' is not recognized` / `flutter: command not found`

`Path` chưa có `...\flutter\bin`, hoặc vừa sửa biến môi trường mà chưa **khởi động lại terminal / IDE**.

### Lint báo `prefer_relative_imports`

Import trong `lib/` đang dùng `package:safe_family_app_...`. Đổi sang đường dẫn tương đối, ví dụ `import '../../core/theme/app_tokens.dart';`.

### Tab Báo thức: *"Chưa có quyền dùng micro"*

Đã từ chối quyền micro. Bấm **Mở Cài đặt** → **Quyền → Micro → Cho phép** → quay lại bấm **Thử lại**. Trong lúc đó vẫn dùng được ô **gõ câu lệnh**.

### Tab Báo thức: *"Máy không có dịch vụ nhận giọng nói"*

Máy chưa có/đã tắt dịch vụ nhận giọng nói. Cài hoặc bật app **Google** (Cài đặt → Ứng dụng → Google → Bật), rồi bấm **Thử lại**.

### Tab Báo thức: *"Máy chưa có gói nhận giọng nói tiếng X"*

Tải gói: Cài đặt → Hệ thống → Ngôn ngữ & nhập liệu → Nhận dạng giọng nói trên thiết bị (hoặc app Google → Cài đặt → Giọng nói → Nhận dạng giọng nói ngoại tuyến), hoặc bấm *Mở cài đặt giọng nói* trên thông báo. Chưa tải vẫn thử nói được khi có mạng.

### Tab Báo thức: nói xong báo *"Không hiểu giờ"*

- Kiểm tra chip ngôn ngữ đúng với tiếng đang nói.
- Nói rõ giờ theo câu mẫu hiện trên màn Báo thức; xem dòng *"Bạn nói: …"* để biết máy nghe thành chữ gì.

### Bấm *Đặt báo thức* báo *"Máy không có app Đồng hồ nhận lệnh đặt báo thức"*

App Đồng hồ của máy không hỗ trợ lệnh chuẩn `SET_ALARM` hoặc đã bị tắt. Bật lại app Đồng hồ, hoặc mở app Đồng hồ và đặt tay theo giờ app hiện.

### Build lần đầu tự tải *Android SDK Platform 35* và *CMake 3.22.1*

Bình thường — plugin `image_picker`/`path_provider` cần hai gói này, Gradle tự cài vào thư mục SDK. Nếu bước tự cài báo lỗi `sdkmanager ... 0xC0000409` (xem lỗi đầu mục 9), cài tay trong Android Studio: **SDK Platforms** → *Android 15.0 (API 35)*; **SDK Tools** → *Show Package Details* → **CMake** → *3.22.1*.

### Thêm ảnh vào `assets/team/` hoặc sửa `members.json` mà app không đổi

- Phải **build lại** bằng `flutter run` (dừng hẳn rồi chạy lại) — hot reload / hot restart không nhận file mới trong `assets/`.
- Tên ảnh phải đúng `id` + `.jpg`, chữ thường: `hongocphu.jpg` ✓ — `HoNgocPhu.jpg` ✗ — `hongocphu.png` ✗ — `hongocphu.JPG` ✗.
- `members.json` sai cú pháp JSON (thiếu dấu phẩy, ngoặc kép…) thì tab Nhóm báo *"Không đọc được thông tin nhóm"* — kiểm tra lại file bằng một trình kiểm tra JSON.

### Bấm email thành viên báo *"Không mở được app mail"*

Máy chưa có app mail nào (Gmail, Outlook…) hoặc app mail đang bị tắt. Cài/bật một app mail rồi thử lại.

### Chạm thẻ danh bạ báo *"Không mở được app Điện thoại"* / bấm YouTube báo *"Không mở được YouTube"*

- Máy không có app Điện thoại (máy tính bảng chỉ Wi-Fi) hoặc không có trình duyệt nào → không mở được là đúng.
- Máy có app nhưng vẫn báo lỗi: app Điện thoại / trình duyệt mặc định đang bị tắt trong **Cài đặt → Ứng dụng** — bật lại.

### Log có nhiều dòng `E/AdrenoUtils`, `E/Gralloc4`, `GraphicBuffer ... failed`

Không phải lỗi app — driver GPU Qualcomm dò định dạng ảnh lúc khởi động (Impeller/Vulkan). Bỏ qua.

### `flutter doctor` báo lỗi mục Visual Studio / Chrome

Bỏ qua — app chỉ làm cho Android.
