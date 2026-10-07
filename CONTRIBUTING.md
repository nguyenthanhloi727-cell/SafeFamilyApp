# Hướng dẫn chạy & thử SafeFamily bằng Android Studio

Dành cho thành viên nhóm và bất kỳ ai muốn tự build, chạy thử app trên điện thoại thật bằng **Android Studio**. Chi tiết kỹ thuật và lỗi thường gặp: [docs/DEVELOPER.md](docs/DEVELOPER.md).

## 1. Cài đặt một lần

1. Cài **Flutter 3.47** (nhóm dùng 3.47.5) theo [hướng dẫn chính thức](https://docs.flutter.dev/get-started/install/windows/mobile), [Android Studio](https://developer.android.com/studio) và [Git](https://git-scm.com/downloads) (để tải mã nguồn bằng `git clone`).
2. Android Studio → **Settings** (`Ctrl+Alt+S`) → **Plugins** → cài **Flutter** (tự cài kèm **Dart**) → khởi động lại Android Studio.
3. **Settings → Languages & Frameworks → Android SDK**:
   - Tab **SDK Platforms**: tick **Android 16.0 (API 36)** và **Android 15.0 (API 35)**.
   - Tab **SDK Tools**: tick **Show Package Details** → **NDK (Side by side) 28.2.13676358**, **CMake 3.22.1**, **Android SDK Command-line Tools**.
   - Bấm **Apply**, đồng ý license.
4. Mở terminal, chạy lệnh dưới đây. Dòng **Android toolchain** phải có ✓ (bỏ qua Visual Studio / Chrome):

   ```bash
   flutter doctor --android-licenses
   ```

   ```bash
   flutter doctor
   ```

## 2. Mở project

1. Tải mã nguồn: **File → New → Project from Version Control** → dán `https://github.com/nguyenthanhloi727-cell/SafeFamilyApp.git` → **Clone**.
   (Hoặc tải ZIP trên GitHub, giải nén, rồi **File → Open** chọn thư mục có `pubspec.yaml`.)
2. Nếu Android Studio hỏi **Flutter SDK path**: **Settings → Languages & Frameworks → Flutter** → chọn thư mục Flutter đã cài.
   Nếu hiện thanh vàng **"Dart SDK is not configured"**: bấm **Open Dart settings** → tick **Enable Dart support** → **Dart SDK path** = `<thư mục Flutter>\bin\cache\dart-sdk` → **OK** (không cần bấm *Download Dart SDK*).
3. Mở `pubspec.yaml` → bấm **Pub get** trên thanh thông báo (hoặc chạy `flutter pub get`).

## 3. Nối điện thoại

1. **Mọi Android:** Cài đặt → Giới thiệu điện thoại → bấm 7 lần **Số hiệu bản dựng** → vào **Tùy chọn nhà phát triển** → bật **Gỡ lỗi USB**.
2. **Xiaomi / Redmi / POCO:** bấm 7 lần **Phiên bản MIUI/HyperOS**; trong Tùy chọn nhà phát triển bật thêm **Cài đặt qua USB** (cần tài khoản Mi, SIM + dữ liệu di động).
3. Cắm cáp **truyền dữ liệu**, chọn **Truyền tệp**, bấm **Cho phép** gỡ lỗi USB.
4. Trên thanh công cụ Android Studio, ô **thiết bị** phải hiện tên điện thoại (ví dụ `2107113SG`). Không thấy → xem [lỗi thường gặp](docs/DEVELOPER.md#9-lỗi-thường-gặp).

## 4. Chạy app

| Muốn | Làm trong Android Studio |
|---|---|
| Chạy app | Chọn cấu hình **main.dart** + điện thoại → bấm **▶ Run** (`Shift+F10`) |
| Chạy demo vân tay | Chọn cấu hình **Demo vân tay (main_demo.dart)** → **▶ Run**. Chỉ 1 màn biometric_storage: quét vân tay trả về token hoặc mã lỗi (hủy, khóa tạm…). Cài đè lên app SafeFamily trên điện thoại; chạy lại **main.dart** để quay về |
| Gỡ lỗi (đặt breakpoint) | Bấm vào lề trái dòng code để đặt điểm dừng → **🐞 Debug** (`Shift+F9`) |
| Sửa code thấy ngay | Lưu file (`Ctrl+S`) → **Hot Reload** (⚡) tự chạy; đổi `assets/` hoặc Android thì bấm **Stop** rồi **Run** lại |
| Xem log | Tab **Run** (log Flutter) hoặc **Logcat** (log Android) ở đáy màn hình |
| Build APK | **Build → Flutter → Build APK**, hoặc `flutter build apk --release` |

Lần đầu mở app sẽ hiện màn **Thiết lập khóa phụ huynh**: tự đặt mã PIN (4–6 số) rồi chọn bật vân tay.

## 5. Chạy test

- Toàn bộ: chuột phải thư mục **test** → **Run 'tests in test'**, hoặc:

  ```bash
  flutter test
  ```

- Một file: mở file test → bấm ▶ cạnh `void main()` hoặc cạnh từng `test(...)`.
- Kiểm tra code: `flutter analyze` (phải "No issues found").

## 6. Thử tính năng theo kịch bản

Làm theo mục **Kịch bản demo** trong [README](README.md#kịch-bản-demo). Gặp lỗi: ghi lại bước, ảnh chụp màn hình, và log trong tab **Run/Logcat**, rồi tạo **Issue** trên GitHub hoặc báo nhóm.

## 7. Đóng góp code

- Làm theo quy trình trong [docs/DEVELOPER.md](docs/DEVELOPER.md#8-quy-trình-git--phát-hành): code → `flutter analyze` → `flutter test` → chạy trên máy thật → commit.
- Thêm/bỏ package hoặc quyền Android thì cập nhật `docs/DEVELOPER.md` cùng commit.
- Không commit APK, keystore, `local.properties`.
