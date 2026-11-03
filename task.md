# Kế hoạch: tách giao diện máy mẹ / máy con

Cập nhật: 2026-11-04 · Làm trực tiếp trên source, test, commit, **push thẳng lên `main`** (đã được người dùng cho phép)

## LỆNH TIẾP TỤC (dành cho Claude)

Người dùng mở context mới và chỉ gõ vài chữ như **"làm tiếp task.md"** (hoặc "tiếp", "làm task tiếp"). Khi đó:

1. Đọc file này, đọc mục **Tiến độ** bên dưới.
2. Chọn task đầu tiên chưa tick `[x]` mà **mọi task trong cột "Phụ thuộc" đã tick**. Nếu người dùng nêu số task (ví dụ "làm T5") thì làm đúng task đó, nhưng báo nếu phụ thuộc chưa xong.
3. Chạy `git log --oneline -15` và `git status` để chắc task đó chưa được làm dở (commit có tên task, hoặc file đã sửa). Nếu làm dở thì tiếp tục từ chỗ dở, không làm lại từ đầu.
4. Làm đúng phần mô tả của task, theo "Quy ước cho MỌI context". Gặp "Việc chưa chốt" liên quan task này thì hỏi người dùng trước khi code.
5. Xong: `flutter analyze` sạch, `flutter test` đạt (task có Kotlin thì thêm `flutter build apk --debug`), commit riêng với tên task trong message (ví dụ `T3: bỏ chế độ trẻ em ...`).
6. **Tick `[x]` task đó trong mục Tiến độ** (sửa thẳng trong `task.md`), ghi mã commit và ngày, rồi commit luôn thay đổi file này. Task nào chưa xong hẳn thì để `[~]` kèm ghi chú còn thiếu gì.
7. **Đẩy thẳng lên `main`, không mở PR, không chờ hỏi**: `git fetch origin`; nếu `main` có commit mới thì `git pull --rebase origin main` (xử lý xung đột nếu có, chạy lại test); rồi `git push origin HEAD:main`. Người dùng đã cho phép sẵn việc này cho mọi task trong file này.
8. Báo ngắn gọn: task vừa xong, task kế tiếp sẽ là gì, việc nào chưa kiểm được trên máy thật, và nhắc `git pull` ở `W:\Code\SafeFamilyApp`. **Chỉ làm 1 task mỗi context**, không tự chuyển sang task kế.

Quy trình gói gọn: **sửa trực tiếp trong source → test → commit → push `main`**. Chỉ dừng lại hỏi khi gặp mục "Việc chưa chốt" hoặc test không qua được.

## Phát hiện cần nhớ (khi viết kế hoạch)

1. **Chế độ trẻ em chỉ là công tắc.** Tắt đi thì khu phụ huynh cho vào không hỏi gì (`lib/core/security/parent_guard.dart`: `requireParentArea` có `if (!_childMode) return true`). → **T3** sửa thẳng `parent_guard.dart` và **phải giữ nguyên luồng vân tay/PIN** (`biometric_storage` là yêu cầu bắt buộc của đề tài).
2. **Flutter chưa có đường gọi "xin thêm giờ" từ màn chính máy con.** Chỉ có bên Kotlin (`FamilySync.queueRequest`, dùng ở `TimeLimitBlockActivity` và `StudyBlock`). → **T6** phải thêm một method vào kênh `safefamily/family` (`MainActivity.kt` + `lib/features/connection/data/family_platform.dart`).
3. **Máy con chưa có danh bạ nào ngoài tối đa 3 số SOS** (`contacts` trong luật, schema 2). → chỉ **T10 và T11** mới làm được danh bạ gọi người nhà; T6 và T7 đừng hứa tính năng này.

## Tiến độ

Ký hiệu: `[ ]` chưa làm · `[~]` đang làm / làm dở · `[x]` xong (ghi commit + ngày)

- [x] T1 — Xóa tab Nhóm (commit b732a40, 2026-11-04)
- [x] T2 — Bỏ "Kết nối gia đình" khỏi Bảo mật, ngắt kết nối cho máy con (commit 1b44306, 2026-11-04)
- [x] T3 — Bỏ Chế độ trẻ em, khu phụ huynh luôn khóa, "Bảo vệ máy" (commit 81d7208, 2026-11-04)
- [x] T4 — Cấp quyền theo vai trò (commit 4d6098a, 2026-11-04)
- [x] T5 — Máy mẹ: tab Con + Tài khoản (commit 1246810, 2026-11-04)
- [x] T6 — Máy con: xin thêm giờ / học xong (commit 3328341, 2026-11-04)
- [x] T7 — Máy con: đồng bộ lần cuối, mất mạng, minh bạch (commit 94d0a2d, 2026-11-04)
- [x] T8 — Server + máy con: nhật ký hoạt động (commit 1e0be05, 2026-11-04)
- [x] T9 — Máy mẹ: màn Hoạt động (commit 9e84acd, 2026-11-04)
- [ ] T10 — Danh bạ của con: server + schema
- [ ] T11 — Danh bạ của con: màn mẹ + máy con gọi
- [ ] T12 — README, docs, kịch bản demo

## Mục tiêu

App làm từ kiểu "một máy" nên sau khi nối 2 máy thì thừa và bất tiện. Chốt hướng:

- **Máy mẹ** chỉ quản lý máy con từ xa, không quản lý chính nó. Không cần Trợ năng.
- **Máy con** là một màn đơn giản (bị chặn gì, còn bao lâu, gọi người nhà, xin thêm giờ). Vào app đầy đủ qua "Dành cho phụ huynh" (vân tay/PIN).
- Mẹ thấy được con làm gì (nhật ký hoạt động).
- Bỏ: tab **Nhóm**, công tắc **Chế độ trẻ em**, **Kết nối gia đình** trong Bảo mật.

## Cách dùng file này (1 task = 1 context)

Mỗi task bên dưới tự đủ thông tin để làm trong **một cuộc trò chuyện riêng**. Mở context mới, dán câu mở đầu của task rồi làm. Xong task thì **commit riêng** (1 commit / task), `flutter analyze` sạch và `flutter test` đạt trước khi commit. Làm đúng thứ tự trong bảng; task nào ghi "song song được" thì mới làm cùng lúc.

Quy ước cho MỌI context:
- Trả lời tiếng Việt, xưng tao – mày.
- Đọc trước: `README.md`, `docs/API_TIEN_TRINH.md`, và file này. Không dùng `dart format` cho cả thư mục (chỉ file mình sửa), để diff không bị nhiễu.
- Máy mẹ không dùng `ConnectionMode.local` nữa (chế độ "một máy" đã bỏ). `ConnectionMode.local` chỉ còn trong enum để test dựng khung app.
- Mọi thao tác phụ huynh phải qua `ParentGate` (xác thực vân tay/PIN).
- Thư mục chạy app của người dùng: `W:\Code\SafeFamilyApp` (nhớ `git pull` ở đó sau khi gộp vào main).

## Bảng tổng quan

| # | Task | Đợt | Loại | Phụ thuộc | Song song được với |
|---|---|---|---|---|---|
| T1 | Xóa tab Nhóm | 1 | Dart | — | T2 |
| T2 | Bỏ "Kết nối gia đình" khỏi Bảo mật, thêm ngắt kết nối cho máy con | 1 | Dart | — | T1 |
| T3 | Bỏ Chế độ trẻ em, khu phụ huynh luôn khóa, mục "Bảo vệ máy" | 1 | Dart | T1, T2 | — |
| T4 | Cấp quyền theo vai trò (máy mẹ chỉ xin Thông báo) | 1 | Dart | T3 | — |
| T5 | Máy mẹ: gọn tab thành Con + Tài khoản | 1 | Dart | T3 | T6 |
| T6 | Máy con: xin thêm giờ / học xong ngay trên màn chính | 1 | Dart + Kotlin | T3 | T5 |
| T7 | Máy con: đồng bộ lần cuối, mất mạng, câu minh bạch | 1 | Dart (+Kotlin nhỏ) | T6 | — |
| T8 | Server + máy con: ghi và gửi nhật ký hoạt động | 2 | API + Kotlin | T3 | T9 |
| T9 | Máy mẹ: màn Hoạt động của con | 2 | Dart | T8 | — |
| T10 | Danh bạ của con: server + schema | 2 | API + Dart | T5 | T8 |
| T11 | Danh bạ của con: màn mẹ + máy con gọi người nhà | 2 | Dart + Kotlin | T10 | — |
| T12 | README, docs, kịch bản demo mới | 3 | Docs | tất cả | — |

Hai task cùng sửa một file thì **không** chạy song song. Bản đồ file xung đột: `app_shell.dart` (T1, T3, T5), `profile_page.dart` (T3, T5, T11), `child_home_page.dart` (T2, T6, T7, T11), `app.dart` (T3, T4), `security_settings_page.dart` (T2, T3).

---

## Đợt 1 — Dọn giao diện (chỉ Dart, ít rủi ro)

### T1 — Xóa tab Nhóm
**Câu mở đầu:** "Đọc task.md, làm T1."

- Tại sao: tab Nhóm là bài tập khác, không thuộc SafeFamily.
- Việc làm:
  - Bỏ tab khỏi `lib/app/app_shell.dart` (còn Trang chủ, Cá nhân).
  - Xóa `lib/features/team/`, `assets/team/` và mục asset trong `pubspec.yaml`, cờ `kTeamPhotoUploadEnabled` trong `lib/core/constants/feature_flags.dart`.
  - Xóa test của team (`test/features/team/`), sửa `test/widget_test.dart` (đang đếm 3 tab).
  - Giữ mục "Giới thiệu" trong Cài đặt; bỏ phần nhắc tới Nhóm nếu có.
- Xong khi: không còn tham chiếu `team`, `analyze` sạch, test đạt, app chạy được 2 tab.

### T2 — Bỏ "Kết nối gia đình" khỏi Bảo mật, thêm ngắt kết nối cho máy con
**Câu mở đầu:** "Đọc task.md, làm T2."

- Tại sao: máy mẹ đã có nút Kết nối gia đình (biểu tượng trên Trang chủ). Máy con vẫn cần chỗ ngắt kết nối.
- Việc làm:
  - Xóa mục "Kết nối gia đình" trong `lib/features/parental/presentation/security_settings_page.dart`.
  - Trên `lib/features/connection/presentation/child_home_page.dart`, nút "Dành cho phụ huynh" mở một menu nhỏ sau xác thực: **Mở ứng dụng đầy đủ** và **Ngắt kết nối với máy mẹ** (dùng lại logic ngắt kết nối của `connection_page.dart`, `_disconnectButton`).
  - Giữ `ConnectionPage` cho máy mẹ (đi từ Trang chủ).
- Xong khi: máy mẹ không còn thấy Kết nối gia đình trong Bảo mật; máy con ngắt kết nối được qua khu phụ huynh; có test widget cho menu.

### T3 — Bỏ Chế độ trẻ em, khu phụ huynh luôn khóa, mục "Bảo vệ máy"
**Câu mở đầu:** "Đọc task.md, làm T3. Đọc kỹ `lib/core/security/parent_guard.dart` trước khi sửa."

- Tại sao: chế độ trẻ em chỉ là công tắc bật khóa; hiện khi tắt, `requireParentArea` cho qua không hỏi (`parent_guard.dart`: `if (!_childMode) return true`). Con cầm máy mẹ lúc đó phá được. Mục tiêu: thao tác phụ huynh **luôn** cần xác thực, không có công tắc.
- Việc làm:
  - `ParentGuard`: bỏ khái niệm `childMode`; `requireParentArea` luôn hỏi vân tay/PIN, nhưng giữ "phiên phụ huynh" ngắn (đã có `hasParentSession` và thời gian chờ 1/5/15 phút) để không bắt xác thực từng cú chạm.
  - Xóa công tắc **Chế độ trẻ em** ở `profile_page.dart` và `lib/core/security/ui/child_mode_banner.dart`; sửa `app_shell.dart` (không còn dải báo).
  - Thêm mục **Bảo vệ máy** (trang chủ máy con và/hoặc trong khu phụ huynh) gom trạng thái chống tắt: Trợ năng, bảo vệ màn Cài đặt, quản trị thiết bị (chống gỡ). Đã có logic ở `lib/features/parental/presentation/device_protection_section.dart` và `uninstall_tile.dart`; chỉ gom và hiển thị rõ.
  - Cập nhật các test dùng `childMode` (`test/features/profile/profile_child_mode_test.dart`, test guard, `widget_test.dart`).
- Lưu ý: vân tay `biometric_storage` là yêu cầu bắt buộc của đề tài, **không** được làm hỏng luồng vân tay/PIN.
- Xong khi: không còn `childMode` trong code; mọi thao tác phụ huynh vẫn hỏi vân tay/PIN; test đạt.

### T4 — Cấp quyền theo vai trò
**Câu mở đầu:** "Đọc task.md, làm T4."

- Tại sao: máy mẹ quản lý qua server nên không cần Trợ năng, quản trị thiết bị, báo thức, pin. Chỉ cần **Thông báo** (cảnh báo cho mẹ). Máy con vẫn phải bật đủ.
- Việc làm:
  - `lib/app/app.dart` (`_Gate`): thứ tự mới là PIN lần đầu → **chọn vai trò** → wizard quyền theo vai trò → app.
  - `lib/features/setup/setup_wizard_page.dart` + `lib/core/permissions/permission_registry.dart`: wizard nhận vai trò; mẹ chỉ có bước Thông báo, con có đủ bước như cũ.
  - Máy mẹ không hiện banner "Còn thiếu N quyền" cho quyền của máy con. Đã bỏ banner trong Trang chủ mẹ; kiểm lại `home_page.dart`.
  - Máy cũ đã qua wizard (`setup.isDone`) thì không bắt làm lại; máy mẹ đã chọn vai trò thì bỏ qua các quyền không cần.
- Xong khi: cài mới → chọn Máy mẹ chỉ thấy xin Thông báo; chọn Máy con thấy đủ quyền; test cho `wizardSteps` theo vai trò.

### T5 — Máy mẹ: gọn tab thành Con + Tài khoản
**Câu mở đầu:** "Đọc task.md, làm T5."

- Việc làm:
  - Máy mẹ có 2 tab: **Con** (Trang chủ hiện tại: `parent_home_page.dart`) và **Tài khoản**.
  - **Tài khoản** gồm: email đăng nhập, người giám hộ thứ 2 (bố), đổi mật khẩu, bảo mật (PIN, vân tay, thời gian chờ, mã khôi phục), nhật ký mở khóa của **máy này**, giới thiệu, đăng xuất, xóa tài khoản. Phần đã có ở `account_pages.dart`, `security_settings_page.dart`, `settings_page.dart`.
  - Tạm giữ mục **Danh bạ gia đình** của `profile_page.dart` trong Tài khoản (T11 sẽ thay bằng danh bạ của con) để không mất tính năng giữa chừng.
  - Máy con không đổi (một màn, T6 và T7 làm tiếp).
- Xong khi: máy mẹ có đúng 2 tab, đến được mọi mục trên; test widget cho 2 tab.

### T6 — Máy con: xin thêm giờ / học xong ngay trên màn chính
**Câu mở đầu:** "Đọc task.md, làm T6."

- Tại sao: hiện 2 yêu cầu này chỉ có trên màn chặn (Kotlin: `TimeLimitBlockActivity`, `StudyBlock`, qua `FamilySync.queueRequest`). Flutter chưa có đường gọi.
- Việc làm:
  - Thêm method trong kênh `safefamily/family` (`MainActivity.kt`, `lib/features/connection/data/family_platform.dart`): `queueRequest(kind, minutes)` gọi `FamilySync.queueRequest` (kind: `extra_time` / `study_done`).
  - `child_home_page.dart`: nút **Xin thêm giờ** (chọn 15/30 phút) và **Con học xong rồi**; hiện trạng thái "Đã gửi, chờ mẹ duyệt" / "Mẹ đã duyệt" / "Mẹ từ chối". Xem `child_requests_page.dart` và API-06 trong `docs/API_TIEN_TRINH.md`.
- Xong khi: bấm nút → máy mẹ thấy ở **Yêu cầu của con**; có test với `FamilyPlatform` giả; `flutter build apk --debug` biên dịch được.

### T7 — Máy con: đồng bộ lần cuối, mất mạng, câu minh bạch
**Câu mở đầu:** "Đọc task.md, làm T7."

- Việc làm:
  - Hiện "Đồng bộ lần cuối: 3 phút trước"; không có mạng hoặc lâu quá thì báo "Chưa kết nối được máy mẹ". Lưu mốc đồng bộ thành công (SharedPreferences hoặc Kotlin `FamilySync`).
  - Thêm khối minh bạch: "Mẹ xem được: vị trí, thời gian dùng, app đã cài. Mẹ không xem nội dung tin nhắn hay trình duyệt." (đúng với dữ liệu thật gửi lên, xem mục "Dữ liệu lên server" trong `docs/API_TIEN_TRINH.md`).
  - Tùy chọn: lịch hôm nay (giờ học, giờ ngủ) dạng thanh.
- Xong khi: các dòng trên hiện đúng, có test.

---

## Đợt 2 — Mẹ thấy con làm gì + danh bạ (cần server)

### T8 — Server + máy con: ghi và gửi nhật ký hoạt động
**Câu mở đầu:** "Đọc task.md, làm T8. Đọc `SafeFamily.Api/` và `docs/API_DAY_DU.md` trước."

- Tại sao: `docs/API_TIEN_TRINH.md` ghi "con gửi nhật ký mở khóa" chưa làm; app chưa ghi lại việc con mở app bị chặn.
- Việc làm:
  - Server: bảng `ActivityEvents` (DeviceId, Kind, Detail ngắn, Time) + migration; `POST /api/devices/me/activity` (máy con, theo lô, giới hạn kích thước và số dòng), `GET /api/devices/{id}/activity?afterId=` (mẹ). Giữ 30 ngày, dọn khi nhận lô mới như vị trí. Kiểm cùng gia đình (404 nếu khác). Thêm test trong `SafeFamily.Api.Tests`, cập nhật `docs/API_DAY_DU.md` và `smoke.sh` nếu có.
  - Máy con (Kotlin): ghi sự kiện **mở app bị chặn** (tên gói), **nhập sai PIN / cố mở khu phụ huynh**, **mở khóa phụ huynh thành công**; hàng chờ trong SharedPreferences, gửi trong `FamilySync.syncOnce` như `TamperAlerts`. Chỉ gửi loại sự kiện và tên gói, không nội dung.
- Xong khi: test API đạt, APK build được, sự kiện lên server khi chạy thử (chưa cần UI mẹ).

### T9 — Máy mẹ: màn Hoạt động của con
**Câu mở đầu:** "Đọc task.md, làm T9."

- Việc làm: thêm `api.getActivity(...)` trong `api_client.dart`; màn **Hoạt động** (danh sách theo giờ, nhóm theo ngày: "Con mở YouTube (đang bị chặn) lúc 14:05", "Nhập sai PIN 2 lần"…); lối vào từ thẻ máy con ở `parent_home_page.dart` kèm số mới chưa xem; tùy chọn thông báo qua `parent_alert_worker.dart`.
- Xong khi: có test với API giả; mẹ thấy sự kiện máy con vừa gửi.

### T10 — Danh bạ của con: server + schema
**Câu mở đầu:** "Đọc task.md, làm T10. Đọc `lib/core/network/policy_schema.dart` và `SafeFamily.Api/Services/PolicyRules.cs`."

- Tại sao: hiện policy chỉ chứa tối đa 3 số SOS (`contacts`, schema 2). Danh bạ của con cần nhiều số hơn, có tên.
- Việc làm: nới `PolicyRules` (tối đa 20 liên hệ, nhãn 1–30 ký tự, số hợp lệ, `sos` bool, giữ tối đa 3 SOS); tăng `schemaVersion` lên 3 và giữ tương thích máy con bản cũ (gặp schema lớn hơn thì giữ luật cũ, xem `FamilySync.parsePolicy`); cập nhật `PolicySchema.sosJson` thành `contactsJson`; test API + test Flutter; cập nhật docs.
- Xong khi: server nhận danh bạ dài, test đạt. Chưa làm giao diện.

### T11 — Danh bạ của con: màn mẹ + máy con gọi người nhà
**Câu mở đầu:** "Đọc task.md, làm T11."

- Việc làm:
  - Máy mẹ: thêm mục **Danh bạ của con** (thêm/sửa/xóa, đánh dấu SOS) thay cho danh bạ cục bộ trong Tài khoản (`profile_page.dart`); ghi qua `PolicySync` vào luật của máy con.
  - Máy con (Kotlin lưu danh bạ vào `GuardPrefs`; thêm method kênh đọc danh bạ): `child_home_page.dart` hiện danh sách **gọi người nhà** nút to; nút SOS luôn trên cùng. Gọi bằng `ExternalLauncher.openDialer`.
  - Xóa phần danh bạ cục bộ cũ không còn dùng (`lib/features/profile/data/`) nếu không ai gọi.
- Xong khi: mẹ thêm số → máy con thấy sau đồng bộ → bấm gọi được; test đạt; APK build được.

---

## Đợt 3 — Hoàn thiện

### T12 — README, docs, kịch bản demo mới
**Câu mở đầu:** "Đọc task.md, làm T12."

- Việc làm: viết lại `README.md` (tính năng, luồng 2 máy, bỏ "một máy" và "Chế độ trẻ em", bỏ tab Nhóm; vẫn ghi công cả 4 thành viên nhóm, tên MSSV/email chỉ ghi khi đã được đồng ý); cập nhật `docs/API_TIEN_TRINH.md`; viết kịch bản demo (máy ảo = máy con, máy thật = máy mẹ có vân tay): ghép đôi → chặn app từ xa → giới hạn giờ → yêu cầu của con → vị trí/hàng rào → hoạt động → danh bạ; ghi rõ lưu ý máy ảo (bật Trợ năng, vị trí giả, polling 5 phút, nút Đồng bộ).
- Xong khi: người lạ đọc README làm theo được.

---

## Việc chưa chốt (hỏi người dùng khi tới)

- T3: giữ "phiên phụ huynh" bao lâu trước khi hỏi lại vân tay (đang 1/5/15 phút tùy cài đặt)?
- T8: có cần thông báo đẩy cho mẹ khi con mở app bị chặn, hay chỉ xem trong màn Hoạt động?
- T10: tối đa bao nhiêu liên hệ cho con (đề xuất 20)?
- Quyền riêng tư: nhật ký hoạt động là dữ liệu nhạy cảm mới; cần chốt thời gian giữ (đề xuất 30 ngày) và cho con biết (T7).
