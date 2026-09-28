# Hướng dẫn chạy & thử SafeFamily bằng Android Studio

Dành cho thành viên nhóm và bất kỳ ai muốn tự build, chạy thử app trên điện thoại thật bằng **Android Studio**. Chi tiết kỹ thuật và lỗi thường gặp: [docs/DEVELOPER.md](docs/DEVELOPER.md).

## 1. Cài đặt một lần

1. Cài **Flutter 3.47** (nhóm dùng 3.47.5) theo [hướng dẫn chính thức](https://docs.flutter.dev/get-started/install/windows/mobile), và [Android Studio](https://developer.android.com/studio).
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
3. Mở `pubspec.yaml` → bấm **Pub get** trên thanh thông báo (hoặc chạy `flutter pub get`).
4. **Thành viên nhóm** đổi app sang tên mình: bấm đúp **`doi-ten.bat`** rồi chọn số — xem [mục 8](#8-đổi-app-sang-tên-của-bạn--công-cụ-đổi-tên).

## 3. Nối điện thoại

1. **Mọi Android:** Cài đặt → Giới thiệu điện thoại → bấm 7 lần **Số hiệu bản dựng** → vào **Tùy chọn nhà phát triển** → bật **Gỡ lỗi USB**.
2. **Xiaomi / Redmi / POCO:** bấm 7 lần **Phiên bản MIUI/HyperOS**; trong Tùy chọn nhà phát triển bật thêm **Cài đặt qua USB** (cần tài khoản Mi, SIM + dữ liệu di động).
3. Cắm cáp **truyền dữ liệu**, chọn **Truyền tệp**, bấm **Cho phép** gỡ lỗi USB.
4. Trên thanh công cụ Android Studio, ô **thiết bị** phải hiện tên điện thoại (ví dụ `2107113SG`). Không thấy → xem [lỗi thường gặp](docs/DEVELOPER.md#9-lỗi-thường-gặp).

## 4. Chạy app

| Muốn | Làm trong Android Studio |
|---|---|
| Chạy app | Chọn cấu hình **main.dart** + điện thoại → bấm **▶ Run** (`Shift+F10`) |
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

## 8. Đổi app sang tên của bạn — công cụ đổi tên

Theo yêu cầu đồ án, app của mỗi thành viên phải mang tên người đó. Cả nhóm dùng chung một mã nguồn; công cụ `tool/rename.dart` đổi **mọi chỗ mang tên người giữ repo** sang tên bạn chỉ bằng một lệnh.

### Công cụ đổi những gì

| Chỗ | Sau khi đổi (ví dụ Hồ Ngọc Phú) |
|---|---|
| Tên app trên điện thoại | `SafeFamily - Hồ Ngọc Phú` |
| Mã ứng dụng (`applicationId`) — cài song song được với app của người khác | `com.safefamily.hongocphu` |
| Tên package Dart (`pubspec.yaml`) | `safe_family_app_hongocphu` |
| Namespace Android + thư mục `MainActivity.kt` | `com.safefamily.safe_family_app_hongocphu` |
| `AppInfo.ownerName`, `AppInfo.applicationId` | `Hồ Ngọc Phú`, `com.safefamily.hongocphu` |
| Import `package:` trong thư mục `test/` | theo tên package mới |

**Không** đổi (thông tin chung của nhóm): `LICENSE`, `assets/team/members.json`, bảng thành viên trong README, link repo. Tác giả commit lấy theo `git config user.name` / `user.email` trên máy bạn.

### Cách 1 — Bấm đúp (Windows, dễ nhất)

1. Mở thư mục project trong File Explorer, **bấm đúp `doi-ten.bat`**.
2. Hiện danh sách nhóm (lấy từ `assets/team/members.json`):

   ```
   Chọn thành viên để đổi app sang tên người đó:
     1. Nguyễn Thành Lợi  (nguyenthanhloi)
     2. Hồ Ngọc Phú  (hongocphu)
     3. Phạm Đinh Gia Bảo  (phamdinhgiabao)
     4. Phương Bảo Khôi  (phuongbaokhoi)
   Gõ số rồi Enter:
   ```

3. Gõ số của bạn → **Enter** → chờ báo *Xong* → bấm phím bất kỳ để đóng.

### Cách 2 — Lệnh (Terminal của Android Studio, mọi hệ điều hành)

| Muốn | Lệnh |
|---|---|
| Chọn trong danh sách nhóm | `dart run tool/rename.dart` |
| Chọn thẳng theo id | `dart run tool/rename.dart hongocphu` |
| Người ngoài nhóm tự đặt tên | `dart run tool/rename.dart nguyenvana "Nguyễn Văn A"` |
| **Trả về tên mặc định của repo** | `dart run tool/rename.dart --reset` |

`id` chỉ gồm chữ thường không dấu, số, `_`, bắt đầu bằng chữ (`nguyenvana` ✓, `NguyenVanA` ✗).

### Sau khi đổi

1. Nếu app đang chạy: bấm **Stop** rồi **▶ Run** lại (không dùng Hot Reload — tên app và mã ứng dụng đã đổi).
2. Điện thoại sẽ có app **mới** tên `SafeFamily - <tên bạn>`; app cũ (nếu có) vẫn còn, gỡ nếu không cần.
3. Build APK của riêng bạn: `flutter build apk --release` → file ở `build/app/outputs/flutter-apk/app-release.apk`.

### Trước khi commit — BẮT BUỘC

Repo luôn giữ tên mặc định. Trước khi `git commit`, trả về tên mặc định:

```bash
dart run tool/rename.dart --reset
```

Chạy `git status` kiểm tra: không được còn thay đổi ở `pubspec.yaml`, `android/app/build.gradle.kts`, `AndroidManifest.xml`, `app_info.dart`, thư mục `kotlin/` hay import trong `test/` — trừ khi bạn cố ý sửa những file đó.

### Thêm thành viên mới vào danh sách

Thêm một mục vào `assets/team/members.json` (`id` không dấu, `fullName` có dấu) — lần sau chạy công cụ sẽ thấy tên mới trong danh sách.

### Lỗi thường gặp khi đổi tên

| Báo lỗi | Cách sửa |
|---|---|
| `Không thấy pubspec.yaml` | Chạy ở thư mục gốc project (chỗ có `pubspec.yaml`), hoặc dùng `doi-ten.bat` |
| `id "..." không hợp lệ` | Dùng chữ thường không dấu, không khoảng trắng |
| `Không có id "..." trong assets/team/members.json` | Gõ đúng id trong danh sách, hoặc dùng dạng `<id> "<Họ Tên>"` |
| `cần đúng 1 chỗ khớp …` | Một file bị sửa tay khác mẫu — chạy `git checkout -- <file đó>` rồi chạy lại công cụ |
| Chữ tiếng Việt bị lỗi font trong cửa sổ đen | Dùng `doi-ten.bat` (đã bật UTF-8) hoặc Terminal của Android Studio |
| `Lựa chọn không hợp lệ` khi đưa số qua pipe PowerShell (`"2" \| dart run …`) | Gõ số trực tiếp khi được hỏi, hoặc dùng dạng `dart run tool/rename.dart <id>` |
