# SafeFamily

Ứng dụng Android giúp phụ huynh quản lý điện thoại của con, viết bằng Flutter.
Đồ án nhóm môn Flutter — sản phẩm chung của cả nhóm (xem [Nhóm thực hiện](#nhóm-thực-hiện)).

- Nền tảng: **chỉ Android** (Android 7.0 trở lên).
- Giao diện: Material 3, tiếng Việt, font Be Vietnam Pro đóng gói sẵn trong app.
- Mã nguồn công khai — ai cũng có thể tải về, build và chạy theo hướng dẫn dưới đây.

> README được viết dần theo tiến độ dự án. Tính năng nào chưa xong được ghi rõ trạng thái ở [mục 1](#1-tính-năng).

## Nhóm thực hiện

| Thành viên | Vai trò |
|---|---|
| Nguyễn Thành Lợi | Developer |
| Hồ Ngọc Phú | Tester |
| Phạm Đinh Gia Bảo | _đang cập nhật_ |
| Phương Bảo Khôi | _đang cập nhật_ |

Repo được lưu trên tài khoản GitHub của một thành viên để nộp bài; mọi thành viên đều là tác giả của dự án.

## Bạn cần đọc phần nào?

| Bạn là… | Đọc |
|---|---|
| Người chỉ muốn **cài app lên điện thoại** | [3.4 Chuẩn bị điện thoại](#34-chuẩn-bị-điện-thoại) → [3.5 Chạy app](#35-chạy-app) (hoặc cài file APK nếu có trong mục *Releases* của repo) |
| Người muốn **build từ mã nguồn** | Đọc lần lượt [mục 2](#2-yêu-cầu-môi-trường) → [mục 3](#3-cài-đặt-và-chạy) |
| **Thành viên nhóm** | Thêm [mục 4](#4-đổi-tên-app-theo-thành-viên) (đổi tên app thành tên mình) và [mục 7](#7-kiểm-tra-code) |
| Gặp lỗi | [mục 8 — Lỗi thường gặp](#8-lỗi-thường-gặp) |

---

## Mục lục

1. [Tính năng](#1-tính-năng)
2. [Yêu cầu môi trường](#2-yêu-cầu-môi-trường)
3. [Cài đặt và chạy](#3-cài-đặt-và-chạy)
4. [Đổi tên app theo thành viên](#4-đổi-tên-app-theo-thành-viên)
5. [Hướng dẫn sử dụng app](#5-hướng-dẫn-sử-dụng-app)
6. [Cấu trúc thư mục](#6-cấu-trúc-thư-mục)
7. [Kiểm tra code](#7-kiểm-tra-code)
8. [Lỗi thường gặp](#8-lỗi-thường-gặp)
9. [Giấy phép](#9-giấy-phép)

---

## 1. Tính năng

### Tiến độ theo yêu cầu đồ án

| Mục | Yêu cầu | Trạng thái |
|---|---|---|
| 1 | Khung app + `BottomNavigationBar` 5 tab | ✓ Xong |
| 2 | Cá nhân: danh bạ gia đình (bấm để gọi, thêm/sửa/xóa) + nút mở YouTube | ✓ Xong |
| 3 | Báo thức bằng giọng nói (chọn 1 trong 5 ngôn ngữ) | Chưa làm |
| 4 | Dịch văn bản / giọng nói / ảnh (+ điểm cộng: camera dịch trực tiếp) | Chưa làm |
| 5 | _đang cập nhật_ | Chưa làm |
| 6 | Nhóm: thẻ thành viên (ảnh, họ tên, MSSV, email, vai trò, lớp) | ✓ Xong |

### Các tab trong app

| Tab | Nội dung | Trạng thái |
|---|---|---|
| Trang chủ | Bảng điều khiển quản lý con (thẻ con, thời gian dùng máy, app bị chặn) | Giữ chỗ — "Sắp có" |
| Dịch | Dịch Văn bản / Giọng nói / Ảnh / Camera trực tiếp — Việt, Anh, Nhật, Trung, Hàn | Giữ chỗ (mục 4) |
| Báo thức | Nói câu đặt giờ → app đặt báo thức vào app Đồng hồ của máy | Giữ chỗ (mục 3) |
| Nhóm | Thẻ thành viên lướt ngang, tải ảnh, bấm email để gửi mail | ✓ Xong (mục 6) |
| Cá nhân | Hồ sơ phụ huynh, danh bạ gia đình (bấm để gọi), mở YouTube | ✓ Xong (mục 2) — riêng *Cài đặt* làm cùng mục 3 |

Điều hướng bằng `BottomNavigationBar` 5 tab; chuyển tab qua lại vẫn giữ nguyên trạng thái từng tab.

### Quyền app xin

| Tính năng | Quyền | Ghi chú |
|---|---|---|
| Gọi điện từ danh bạ gia đình | **Không cần** | App chỉ mở màn quay số có sẵn số (`tel:`); người dùng tự bấm gọi. App **không** xin quyền `CALL_PHONE`. |
| Mở YouTube | Không cần | Có app YouTube thì mở app, không có thì mở trình duyệt. |
| Tải ảnh thành viên | Không cần | Dùng bộ chọn ảnh của hệ thống (Android 13+: Photo Picker), app chỉ nhận đúng ảnh được chọn. |
| Bấm email thành viên | Không cần | Mở app mail với địa chỉ điền sẵn (`mailto:`). |

Dữ liệu (tên phụ huynh, danh bạ gia đình, ảnh thành viên đã tải lên) chỉ lưu **trên máy**, không gửi đi đâu.

---

## 2. Yêu cầu môi trường

Chưa có Flutter / Android Studio thì cài theo hướng dẫn chính thức trước:
[Cài Flutter cho Android trên Windows](https://docs.flutter.dev/get-started/install/windows/mobile) ·
[Tải Android Studio](https://developer.android.com/studio).

| Thành phần | Phiên bản | Ghi chú |
|---|---|---|
| Flutter | **3.47.5** (kênh stable) | Dart 3.13.4. Bản 3.47.x khác cũng được. Kiểm tra bằng `flutter --version` |
| Android Studio | 2026.1 trở lên | Dùng JDK đi kèm (`jbr`) để build |
| Android SDK Platform | **36** (Android 16) | Flutter 3.47 biên dịch với compileSdk 36 |
| Android SDK Platform | 35 (Android 15) | Plugin cần; Gradle thường tự tải |
| CMake | 3.22.1 | Plugin cần; Gradle thường tự tải |
| Android SDK Build-Tools | 36.0.0 | |
| **NDK (Side by side)** | **28.2.13676358** | Bắt buộc đúng bản này |
| Android SDK Platform-Tools | mới nhất | Có `adb` |
| Git | bất kỳ | |
| Điện thoại Android | Android 7.0+ | Bật Gỡ lỗi USB (xem mục 3.4) |

### Cài SDK Platform 36 và NDK 28.2 bằng Android Studio

1. Mở Android Studio → **Settings** (`Ctrl+Alt+S`) → **Languages & Frameworks → Android SDK**.
2. Xem ô **Android SDK Location** ở trên cùng — đúng thư mục SDK của máy mình.
3. Tab **SDK Platforms**: tick **Android 16.0 ("Baklava")** — API Level **36**.
4. Tab **SDK Tools**: tick **Show Package Details** (góc dưới phải) → mở **NDK (Side by side)** → tick đúng **28.2.13676358**.
5. Bấm **Apply** → đồng ý license → chờ tải (NDK khoảng 2–3 GB sau khi cài).
6. Kiểm tra:

   ```bash
   flutter doctor
   ```

   Dòng **Android toolchain** phải có dấu ✓. Mục Visual Studio / Chrome báo lỗi thì bỏ qua (app không làm cho Windows/web).

### (Tuỳ chọn) Để SDK và cache ngoài ổ C

Nếu ổ C ít chỗ, đặt các biến môi trường cấp user (ví dụ cho ổ D — thay bằng ổ/thư mục của bạn):

| Biến | Giá trị ví dụ |
|---|---|
| `ANDROID_HOME` | `D:\dev\Android\Sdk` |
| `ANDROID_USER_HOME` | `D:\dev\.android` |
| `GRADLE_USER_HOME` | `D:\dev\.gradle` |
| `PUB_CACHE` | `D:\dev\.pub-cache` |
| `Path` thêm | `D:\dev\flutter\bin`, `D:\dev\.pub-cache\bin`, `D:\dev\Android\Sdk\platform-tools` |

Sau đó chạy `flutter config --android-sdk D:\dev\Android\Sdk`, đổi đường dẫn SDK trong Android Studio cho khớp, và **khởi động lại terminal / IDE** để biến có hiệu lực.

---

## 3. Cài đặt và chạy

### 3.1. Lấy source

Tải bằng Git (link repo lấy ở nút **Code** trên trang GitHub của repo):

```bash
git clone <link-repo-github>
```

Hoặc bấm **Code → Download ZIP** rồi giải nén. Sau đó mở terminal **tại thư mục chứa file `pubspec.yaml`** — mọi lệnh bên dưới đều chạy ở đó.

### 3.2. (Tuỳ chọn) Đổi tên app

Bản trên repo build ra app tên **"SafeFamily - Nguyễn Thành Lợi"** (tên thành viên giữ repo). Muốn app mang tên khác — thành viên nhóm bắt buộc, người ngoài tuỳ ý — chạy:

```bash
dart run tool/rename.dart nguyenvana "Nguyễn Văn A"
```

Xem chi tiết ở [mục 4](#4-đổi-tên-app-theo-thành-viên).

### 3.3. Tải package

```bash
flutter pub get
```

### 3.4. Chuẩn bị điện thoại

**Mọi điện thoại Android:**

1. **Bật Tùy chọn nhà phát triển:** vào **Cài đặt → Giới thiệu điện thoại** (có máy nằm trong *Thông tin phần mềm*) → bấm liên tục **7 lần** vào **Số hiệu bản dựng** (*Build number*) cho tới khi hiện *"Bạn đã là nhà phát triển"*.
2. Vào **Cài đặt → Hệ thống → Tùy chọn nhà phát triển** (tuỳ hãng có thể nằm ở *Cài đặt bổ sung*) → bật **Gỡ lỗi USB** (*USB debugging*).

**Riêng Xiaomi / Redmi / POCO (MIUI, HyperOS):**

- Bước 1 bấm 7 lần vào **Phiên bản MIUI / HyperOS** (trong *Giới thiệu điện thoại*); Tùy chọn nhà phát triển nằm ở **Cài đặt → Cài đặt bổ sung**.
- Bật thêm **Cài đặt qua USB** (*Install via USB*) — thiếu cái này `flutter run` sẽ báo `INSTALL_FAILED_USER_RESTRICTED`. Máy có thể yêu cầu đăng nhập tài khoản Mi và **cắm SIM + bật dữ liệu di động** mới cho bật.
- Nên bật **Gỡ lỗi USB (Cài đặt bảo mật)** nếu có.

**Kết nối:**

3. Cắm cáp **truyền dữ liệu** (không dùng cáp chỉ sạc), chọn chế độ **Truyền tệp**.
4. Khi điện thoại hỏi *"Cho phép gỡ lỗi USB?"* → tick *Luôn cho phép* → **Cho phép**.
5. Kiểm tra máy tính đã thấy điện thoại:

   ```bash
   flutter devices
   ```

### 3.5. Chạy app

```bash
flutter run
```

Nhiều thiết bị thì chỉ định máy bằng id lấy từ `flutter devices`, ví dụ `flutter run -d a7199f47`.
Xiaomi: nếu hiện hộp thoại *"Cài đặt ứng dụng qua USB?"* thì bấm **Cài đặt** ngay (chỉ chờ khoảng 10 giây).

### 3.6. Build file APK

```bash
flutter build apk --release
```

File ra ở `build/app/outputs/flutter-apk/app-release.apk` (hiện ký bằng khoá debug — đủ để cài thử, chưa đủ để đưa lên cửa hàng).

---

## 4. Đổi tên app theo thành viên

Cả nhóm dùng chung một source; theo yêu cầu đồ án, app của mỗi thành viên mang tên người đó. Ai tải repo về cũng dùng được script này để đổi sang tên mình. Chạy ở thư mục gốc project (chỗ có `pubspec.yaml`):

```bash
dart run tool/rename.dart <hovaten_khong_dau> "<Họ Tên có dấu>"
```

| Thành viên | Lệnh |
|---|---|
| Nguyễn Thành Lợi | `dart run tool/rename.dart nguyenthanhloi "Nguyễn Thành Lợi"` |
| Hồ Ngọc Phú | `dart run tool/rename.dart hongocphu "Hồ Ngọc Phú"` |
| Phạm Đinh Gia Bảo | `dart run tool/rename.dart phamdinhgiabao "Phạm Đinh Gia Bảo"` |
| Phương Bảo Khôi | `dart run tool/rename.dart phuongbaokhoi "Phương Bảo Khôi"` |

Script đổi cùng lúc:

| Chỗ | Thành |
|---|---|
| `name` trong `pubspec.yaml` | `safe_family_app_<hovaten>` |
| `applicationId` Android | `com.safefamily.<hovaten>` |
| Tên app trên điện thoại | `SafeFamily - <Họ Tên>` |
| `AppInfo.ownerName` (`lib/core/constants/app_info.dart`) | `<Họ Tên>` |
| Import `package:...` trong `test/` | theo tên package mới |

Sau đó script tự chạy `flutter pub get`.

Quy ước để script hoạt động:

- `<hovaten_khong_dau>` chỉ gồm **chữ thường a-z, số, dấu `_`**, bắt đầu bằng chữ.
- Namespace/package Kotlin **giữ cố định** (`com.safefamily.safe_family_app_nguyenthanhloi`) — không cần dời `MainActivity`.
- Mọi import trong `lib/` dùng **đường dẫn tương đối** (`import '../core/...'`), không dùng `package:safe_family_app_...`. Lint `prefer_relative_imports` sẽ báo nếu viết sai.
- Bản trên repo mặc định là `nguyenthanhloi` (thành viên giữ repo). Thành viên nhóm **không commit phần đổi tên của mình** — đổi tên chỉ để build trên máy mình. Trước khi commit, chạy lại script với tên mặc định:

  ```bash
  dart run tool/rename.dart nguyenthanhloi "Nguyễn Thành Lợi"
  ```

---

## 5. Hướng dẫn sử dụng app

> Tính năng chưa xong (xem [mục 1](#1-tính-năng)) sẽ được bổ sung hướng dẫn khi hoàn thành.

Mở app **SafeFamily - <Họ Tên>** trên điện thoại. Chuyển giữa 5 tab bằng thanh điều hướng dưới cùng: **Trang chủ – Dịch – Báo thức – Nhóm – Cá nhân**.

### Tab Cá nhân

**Tên phụ huynh:** chạm vào thẻ hồ sơ trên cùng (hoặc nút ✎) → nhập họ tên → **Lưu**. Ảnh đại diện là chữ cái đầu của tên.

**Mở YouTube:** bấm nút **Mở YouTube** — máy có app YouTube thì vào app, không có thì mở trang web.

**Danh bạ gia đình** — lần đầu có sẵn **Mẹ** và **Bố** *chưa có số* (app không tự điền số mẫu để tránh gọi nhầm người lạ).

| Muốn… | Làm |
|---|---|
| Gọi | Chạm vào thẻ → app **Điện thoại** mở ra với số soạn sẵn → tự bấm gọi |
| Thêm số cho thẻ chưa có số | Chạm vào thẻ (dòng *"Chạm để thêm số"*) → nhập số → **Lưu** |
| Thêm liên hệ | Bấm **Thêm** → chọn tên gọi (Mẹ, Bố, Ông, Bà, Anh, Chị, Em, Con) hoặc **Khác** để tự gõ → nhập số (có thể để trống) → **Lưu** |
| Sửa / Xóa | Bấm **⋮** ở cuối thẻ → **Sửa** hoặc **Xóa** (xóa phải xác nhận) |

Số điện thoại hợp lệ: chỉ chữ số, được có dấu `+` ở đầu, dài **9–12 chữ số**; khoảng trắng và dấu chấm được tự bỏ (`090.123 4567` → `0901234567`). Nhập sai sẽ báo lỗi ngay dưới ô nhập.

Danh bạ và tên lưu trên máy — tắt app mở lại vẫn còn.

### Tab Nhóm

- **Lướt ngang** để xem thẻ từng thành viên; thẻ kế tiếp ló ra ở mép phải. Dưới cùng có chấm trang và số thứ tự (ví dụ `2/4`).
- Mỗi thẻ: ảnh, họ tên, MSSV, email, vai trò, lớp. Ô nào chưa có thông tin hiện *"Chưa cập nhật"*.
- **Bấm vào email** → mở app mail với địa chỉ điền sẵn.
- **Ảnh** (khi chế độ tải ảnh đang MỞ):
  - **Tải ảnh lên** → chọn ảnh trong thư viện máy. Ảnh được thu nhỏ và **chép vào bộ nhớ riêng của app** — tắt app mở lại vẫn còn, xóa ảnh gốc trong thư viện cũng không mất.
  - Đã có ảnh thì có **Đổi ảnh** và **Xóa ảnh** (xóa phải xác nhận).
  - Thứ tự hiển thị: ảnh cố định trong app (`assets/team/`) → ảnh đã tải lên → chữ cái đầu của tên.

Muốn sửa thông tin hoặc gắn ảnh cố định cho thành viên: xem [mục 5.1](#51-cập-nhật-thông-tin-và-ảnh-thành-viên).

### Các tab khác

- **Dịch:** chọn chế độ ở thanh trên (Văn bản / Giọng nói / Ảnh / Camera); bấm nút ⇄ để đổi chiều ngôn ngữ nguồn – đích.
- **Báo thức:** ngôn ngữ giọng nói mặc định là Tiếng Việt. Báo thức được đặt vào **app Đồng hồ của máy**; âm báo do app Đồng hồ quyết định.

### 5.1. Cập nhật thông tin và ảnh thành viên

**Sửa thông tin** — chỉ sửa file [`assets/team/members.json`](assets/team/members.json), không cần đụng code giao diện:

```json
{
  "id": "hongocphu",
  "fullName": "Hồ Ngọc Phú",
  "studentId": "2380601699",
  "email": "ten@example.com",
  "role": "Tester",
  "className": "23DTHC5"
}
```

- Thứ tự trong file = thứ tự thẻ trong app. Để `""` thì app hiện *"Chưa cập nhật"*.
- **Không đổi `id`** (dùng để đặt tên ảnh).
- Sửa xong phải **build lại** (`flutter run`) — hot reload không nhận thay đổi trong `assets/`.

**Gắn ảnh cố định rồi khoá tải ảnh** (dùng khi nộp bài, để ảnh không phụ thuộc máy nào):

1. Đặt ảnh vào `assets/team/`, tên = `id` + `.jpg`, ví dụ `assets/team/hongocphu.jpg` (chữ thường, đuôi `.jpg`; nên ảnh vuông ~600×600 px, dưới 300 KB).
2. Mở `lib/core/constants/feature_flags.dart`, đổi:

   ```dart
   const bool kTeamPhotoUploadEnabled = false;
   ```

3. Build lại (`flutter run`). Các nút *Tải ảnh lên / Đổi ảnh / Xóa ảnh* biến mất; thẻ hiện ảnh trong `assets/team/`, ai chưa có ảnh thì hiện chữ cái đầu.

Ảnh cố định luôn được ưu tiên hơn ảnh tải lên, nên người đã có ảnh trong `assets/team/` sẽ không thấy nút tải ảnh kể cả khi đang MỞ.

---

## 6. Cấu trúc thư mục

```
lib/
  main.dart
  app/                      # MaterialApp + khung điều hướng (BottomNavigationBar + IndexedStack)
  core/
    constants/              # AppInfo (tên app), AppLanguage (5 ngôn ngữ), feature_flags (khoá tải ảnh)
    services/               # ExternalLauncher: mở app Điện thoại, YouTube, mail (url_launcher)
    theme/                  # màu, chữ, khoảng cách, bo góc — theo design/DESIGN.md
    widgets/                # widget dùng chung
  features/
    home/       {presentation, data}
    translate/  {presentation, data}
    alarm/      {presentation, data}
    team/
      data/                 # đọc members.json, chọn/lưu ảnh, thứ tự ưu tiên ảnh
      presentation/         # màn Nhóm, TeamController (ChangeNotifier), thẻ thành viên
    profile/
      data/                 # model liên hệ, kiểm tra số, ProfileRepository + bản lưu trên máy
      presentation/         # màn Cá nhân, ProfileController (ChangeNotifier), hộp thoại
assets/fonts/BeVietnamPro/  # font + giấy phép OFL.txt
assets/team/                # members.json (thông tin nhóm) + ảnh cố định <id>.jpg
tool/rename.dart            # đổi tên app theo thành viên
test/
  widget_test.dart          # chuyển 5 tab + giữ trạng thái tab
  features/<tính năng>/     # unit test + widget test từng tính năng
  helpers/                  # đồ giả dùng chung cho test
```

- Màu, cỡ chữ, khoảng cách lấy từ `lib/core/theme/` — không ghi số cứng trong màn hình.
- Mỗi tính năng tách `data/` (lưu trữ, sau này thay bằng server chỉ cần viết thêm một bản của interface repository) và `presentation/` (giao diện + state bằng `ChangeNotifier` có sẵn của Flutter).

### Package đang dùng (từ pub.dev)

| Package | Dùng để |
|---|---|
| `shared_preferences` | Lưu tên phụ huynh, danh bạ gia đình trên máy |
| `url_launcher` | Mở màn quay số (`tel:`), mở YouTube, mở app mail (`mailto:`) |
| `image_picker` | Chọn ảnh thành viên từ thư viện máy |
| `path_provider` | Lấy thư mục riêng của app để chép ảnh vào |
| `shared_preferences_platform_interface` | *(chỉ trong test)* bộ nhớ giả cho test |

---

## 7. Kiểm tra code

Trước khi push, chạy:

```bash
flutter analyze
```

```bash
flutter test
```

Cả hai phải sạch lỗi.

---

## 8. Lỗi thường gặp

### Build lỗi: `sdkmanager.bat ... finished with non-zero exit value -1073740791 (NTSTATUS 0xC0000409)`

- **Nguyên nhân:** máy thiếu SDK Platform 36 hoặc NDK 28.2. Gradle tự gọi `sdkmanager` để cài, nhưng **Command-line Tools bản 23** bị crash khi thoát nên cài thất bại.
- **Cách sửa:** cài tay **SDK Platform 36** và **NDK 28.2.13676358** bằng Android Studio ([mục 2](#cài-sdk-platform-36-và-ndk-282-bằng-android-studio)), rồi build lại.
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

### `Target of URI doesn't exist: 'package:safe_family_app_.../...'` trong test

Tên package trong `pubspec.yaml` và trong import của `test/` không khớp (thường do sửa tên tay). Chạy lại `dart run tool/rename.dart ...` để script đồng bộ, rồi `flutter pub get`.

### `rename.dart`: `hovaten_khong_dau ... không hợp lệ`

Tham số đầu phải là chữ thường không dấu, không khoảng trắng: `nguyenthanhloi` ✓ — `NguyenThanhLoi` ✗ — `nguyễn thành lợi` ✗. Họ tên có dấu đặt trong ngoặc kép ở tham số thứ hai.

### Lint báo `prefer_relative_imports`

Import trong `lib/` đang dùng `package:safe_family_app_...`. Đổi sang đường dẫn tương đối, ví dụ `import '../../core/theme/app_tokens.dart';`.

### Build lần đầu tự tải *Android SDK Platform 35* và *CMake 3.22.1*

Bình thường — plugin `image_picker`/`path_provider` cần hai gói này, Gradle tự cài vào thư mục SDK. Nếu bước tự cài báo lỗi `sdkmanager ... 0xC0000409` (xem lỗi đầu mục 8), cài tay trong Android Studio: **SDK Platforms** → *Android 15.0 (API 35)*; **SDK Tools** → *Show Package Details* → **CMake** → *3.22.1*.

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

---

## 9. Giấy phép

- Mã nguồn: **MIT** — xem file [`LICENSE`](LICENSE). Được tự do dùng, sửa, phân phối lại; chỉ cần giữ nguyên thông báo bản quyền của nhóm.
- Font **Be Vietnam Pro**: SIL Open Font License 1.1 — xem [`assets/fonts/BeVietnamPro/OFL.txt`](assets/fonts/BeVietnamPro/OFL.txt). Trong app, giấy phép này hiện ở trang *Giấy phép*.
