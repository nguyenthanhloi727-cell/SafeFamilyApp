# Tiến trình: Web API (Swagger) + tích hợp Flutter/Android

Mục tiêu: máy mẹ quản lý máy con từ xa qua server. Máy con vẫn tự chặn bằng code Kotlin hiện có; API chỉ chuyển luật/lệnh qua lại.

Cập nhật lần cuối: 2026-10-31 (API-07) · Trạng thái chung: **Đợt 1, 2, 5 xong code; test tự động đạt trên LocalDB; chưa publish MonsterASP, chưa test 2 máy thật (TASKS/TEST_PLAN.md)**

Ký hiệu: `[ ]` chưa làm · `[~]` đang làm · `[x]` xong

---

## 0. Quyết định đã chốt

- [x] Backend: ASP.NET Core Web API, mở bằng Visual Studio, có Swagger (Swashbuckle)
- [x] CSDL: SQL Server
- [x] Hosting: MonsterASP.NET
- [x] Đồng bộ: máy con hỏi server định kỳ (polling) ở bản đầu, chưa dùng FCM
- [x] Mô hình: server lưu luật/lệnh, máy con tải về và tự thi hành; offline vẫn chặn theo luật đã lưu
- [x] PIN và mã khôi phục chỉ lưu hash trên máy, không gửi lên server
- [x] Giữ chế độ "một máy" (local) song song với chế độ "kết nối"

- [x] Gia đình: 1 mẹ, nhiều con (mỗi con có thể là một máy; thêm bố để sau)
- [x] Đăng nhập phụ huynh: email + mật khẩu
- [x] Mất kết nối: mẹ tự chỉnh ngưỡng trong cài đặt, mặc định 24 giờ
- [x] Dữ liệu lên server: chỉ thống kê thời gian dùng theo app. Chưa gửi nhật ký mở khóa, danh bạ, ảnh
- [x] Phát hành: APK nội bộ trước, Google Play tính sau
- [x] Polling: 5 phút (lệnh "tạm dừng ngay" có thể trễ tối đa vài phút)
- [x] Máy con gửi thêm danh sách app đã cài (tên + tên gói, không nội dung) để báo app mới và khóa app từ xa
- [x] Một máy con thuộc đúng một mẹ; đổi mẹ thì hủy ghép rồi ghép lại

## 0.1 Điểm cần lưu ý từ các quyết định trên

- Bảng dữ liệu cần thêm InstalledApp (tên, gói, thời điểm thấy lần đầu) cho mỗi Device.
- Nhật ký mở khóa (`unlock_log`) bị đưa ra khỏi phạm vi đợt 3, chỉ giữ trên máy con.
- Thêm cài đặt "ngưỡng mất kết nối" cho mẹ (đợt 3).

---

## Đợt 0 – Chuẩn bị

- [ ] Kiểm tra máy: Visual Studio có workload "ASP.NET and web development", .NET SDK bản mới
- [ ] Kiểm tra gói MonsterASP: dung lượng SQL Server, số kết nối, có HTTPS, có cho publish từ Visual Studio (Web Deploy/FTP)
- [ ] Chốt địa chỉ API (domain) dùng cho app
- [ ] Chốt các câu hỏi mở bên dưới

## Đợt 1 – Nền API

Thư mục: `SafeFamily.Api/` trong repo

- [x] Tạo project ASP.NET Core Web API, bật Swagger
- [x] EF Core + SQL Server (LocalDB khi dev), migration đầu tiên (`Initial`)
- [x] Bảng: Family, Parent (tài khoản mẹ), Device (máy con), Pairing (mã ghép), Policy (luật), Command (lệnh tức thời), thêm RefreshToken, InstalledApp
- [x] Đăng ký / đăng nhập phụ huynh, JWT + refresh token (access 30 phút, refresh 60 ngày, đổi là thu hồi cái cũ)
- [x] API ghép đôi: mẹ tạo mã 6 số (hạn 10 phút, dùng một lần), con nhập mã để nhận token thiết bị (365 ngày, hủy ghép là 401 ngay)
- [x] Giới hạn số lần thử mã ghép đôi (5 lần/10 phút/IP), đăng nhập/đăng ký (10 lần/phút/IP)
- [x] Swagger có ô nhập token để test endpoint cần đăng nhập (nút Authorize)
- [x] Cấu hình chuỗi kết nối qua cấu hình server, không để trong git (xem mục Cấu hình)
- [ ] Publish thử lên MonsterASP, mở được Swagger trên mạng

## Đợt 2 – Điều khiển từ xa (luật xuống máy con)

API:
- [x] `GET/PUT /api/devices/{id}/policy` luật (kèm số phiên bản, lệch thì 409); máy con `GET /api/devices/me/policy`. Server lưu JSON nguyên khối, Flutter định nghĩa nội dung
- [x] `POST /api/devices/me/apps` từ máy con; `GET /api/devices/{id}/apps` cho mẹ
- [x] Luật khóa app và lịch chặn: dùng chung `policy` JSON ở trên. Schema chốt (API-04, `schemaVersion` 1): `{"schemaVersion":1,"timeLimit":{...},"appLock":{"blocked":[pkg],"schedules":[]}}`; server chỉ kiểm tra là đối tượng JSON hợp lệ và ≤64 KB (đã test bằng `smoke.sh`). `appLock.schedules` để trống (lịch giờ ngủ/giờ học nằm trong `timeLimit`)
- [x] `POST /api/devices/{id}/commands`; con `GET /api/devices/me/commands` và `POST .../commands/{id}/ack`
- [x] `DELETE /api/devices/{id}` hủy ghép

Flutter (mẹ):
- [x] Thêm tầng gọi API: `lib/core/network/` (`ApiClient`, `ConnectionSession`; tự refresh token, GET thử lại 3 lần, có test)
- [x] Màn chọn vai trò "Một máy / Máy mẹ / Máy con" (`RolePage`, hiện sau wizard quyền)
- [x] Màn đăng nhập/đăng ký + tạo mã ghép đôi (`ParentLoginPage`, `ConnectionPage` trong Bảo mật → Kết nối gia đình)
- [x] Đẩy cấu hình giới hạn giờ và khóa app lên server (`PolicySync`: `time_limit_page`, `app_lock_page`, nút "Gửi luật" ở `RemoteMonitorPage`; 409 thì tải lại và hỏi mẹ; có test tự động). `pause_card` là lệnh, không nằm trong policy: làm ở API-05

Flutter/Android (con):
- [x] Màn nhập mã ghép đôi (`ChildPairPage`)
- [ ] Polling định kỳ bằng WorkManager (hoặc dùng service sẵn có), hỏi thêm khi mở app / có mạng lại
- [~] Ghi luật tải về chỉ khi tải thành công và hợp lệ; lỗi thì giữ bản cũ (`FamilySync.pullPolicy` đọc cả `timeLimit` và `appLock`; đã biên dịch, CHƯA test trên máy thật: xem TASKS/TEST_PLAN.md)
- [ ] Kiểm tra: tắt mạng máy con, luật vẫn chặn đúng

Cột mốc đợt 2: mẹ đặt giới hạn cho 1 app trên máy mẹ, máy con tải về và chặn đúng, chạy trên 2 máy thật với MonsterASP.

## Đợt 3 – Hai chiều

- [~] Con xin thêm giờ / báo "đã học xong" → mẹ duyệt / từ chối (`extra_time`, `study_done`; API-06). Server + Flutter mẹ đã test tự động đạt; Kotlin con biên dịch được nhưng CHƯA chạy máy thật nên chưa tick
- [~] Con báo app mới cài → mẹ cho dùng hoặc chặn (`NewApps.kt`; API-07). Server + Flutter mẹ đã test tự động đạt; Kotlin con biên dịch được nhưng CHƯA chạy máy thật nên chưa tick
- [ ] Con gửi báo cáo sử dụng → mẹ xem (`UsageReport.kt`, `report_page`)
- [ ] Con gửi nhật ký mở khóa (`unlock_log`)
- [ ] Yêu cầu tạo lúc offline được xếp hàng trong máy và gửi khi có mạng
- [ ] Cảnh báo cho mẹ: máy con mất kết nối lâu, chỉnh giờ máy, gỡ app (nối `TimeChangeReceiver`, `UninstallGate`)
- [ ] Hồ sơ, liên hệ gia đình (`profile`, `team`) – làm cuối, cân nhắc quyền riêng tư

## Đợt 4 – Củng cố

- [ ] HTTPS bắt buộc, rà soát bảo mật JWT, mật khẩu băm, CORS
- [ ] Xử lý xung đột (số phiên bản) khi mẹ sửa lúc con offline
- [ ] Thông báo / màn giải thích cho con biết app giám sát những gì
- [ ] Ghi log lỗi phía server
- [ ] Test trên nhiều dòng máy Android (chế độ tiết kiệm pin có thể hạn chế polling)
- [ ] Cân nhắc FCM nếu cần lệnh tức thời
- [ ] Chính sách quyền riêng tư; nếu lên Google Play thì khai báo mục đích Accessibility / Device Admin / Usage Access

---

## Đợt 5 – Vị trí và hàng rào địa lý (thêm 2026-10-31, chờ chốt quyền riêng tư)

Task Flutter/Android tương ứng: `TASKS/TASKS.md` mục 13–15. Không dùng Firebase/FCM, chỉ polling.

- [x] Bảng `LocationPoint`, `Geofence`, `GeofenceEvent`
- [x] `POST /api/devices/me/locations` (con), `GET /api/devices/{id}/location` (mẹ)
- [x] `GET/PUT /api/devices/{id}/geofences`, `POST /api/devices/me/geofence-events`, `GET /api/devices/{id}/geofence-events`
- [x] Dọn vị trí cũ >7 ngày mỗi lần máy con gửi lô mới (không cần job riêng)
- [ ] Chốt lại quyết định "chỉ gửi thống kê dùng": vị trí là dữ liệu nhạy cảm mới


Ghi chú 2026-10-31 (thêm): máy mẹ nhận thông báo vào/ra vùng khi app đóng bằng WorkManager 15 phút (`lib/core/alerts/`), chỉ gọi `GET /api/devices` + `GET .../geofence-events?afterId=`; không đổi API. Chưa test máy thật.

Ghi chú 2026-10-31: migration `LocationGeofence`; smoke test `SafeFamily.Api/smoke.sh`; máy con gọi qua Kotlin (`FamilySync`), mẹ qua `ApiClient`. Chưa test trên MonsterASP và 2 máy thật: xem `TASKS/TEST_PLAN.md`.

---

## Cấu hình và chạy thử (dev)

Bí mật không nằm trong git. Đặt bằng biến môi trường hoặc `SafeFamily.Api/appsettings.Local.json` (đã `.gitignore`):

```json
{
  "ConnectionStrings": { "Default": "Server=(localdb)\MSSQLLocalDB;Database=SafeFamilyDev;Trusted_Connection=True;TrustServerCertificate=True" },
  "Jwt": { "Key": "chuỗi ngẫu nhiên từ 32 ký tự trở lên" }
}
```

Trên MonsterASP đặt hai giá trị này trong cấu hình/biến môi trường của site (`ConnectionStrings__Default`, `Jwt__Key`). Thiếu thì app báo lỗi rõ khi khởi động.

```bash
cd SafeFamily.Api
dotnet ef database update      # tạo DB
dotnet run                     # Swagger: <địa chỉ>/swagger
```

Emulator Android gọi máy tính qua `http://10.0.2.2:<cổng>`; app mặc định `ConnectionSession.defaultBaseUrl`, sửa được trên màn kết nối. Bản release chặn HTTP thường (cleartext), dùng HTTPS khi lên MonsterASP.

## Danh sách API dự kiến (sẽ hiện trong Swagger)

| Nhóm | Endpoint | Ai gọi | Ghi chú |
|---|---|---|---|
| Auth | `POST /api/auth/register`, `/login`, `/refresh` | Mẹ | JWT |
| Ghép đôi | `POST /api/pairing/code` | Mẹ | Tạo mã có hạn |
| Ghép đôi | `POST /api/pairing/claim` | Con | Nhập mã, nhận token thiết bị |
| Thiết bị | `GET /api/devices`, `DELETE /api/devices/{id}` | Mẹ | Danh sách / hủy ghép |
| Luật | `GET/PUT /api/devices/{id}/policy` | Mẹ ghi, con đọc | Có số phiên bản |
| Lệnh | `POST /api/devices/{id}/commands`, `GET /api/devices/me/commands` | Mẹ tạo, con đọc | Tạm dừng, cho thêm giờ |
| Yêu cầu | `POST /api/devices/me/requests`, `GET /api/devices/me/requests/{id}`, `GET /api/devices/{id}/requests`, `PUT /api/requests/{id}` | Con tạo, mẹ duyệt | Xin thêm giờ, đã học xong (API-06) |
| Duyệt app mới | `POST /api/devices/me/apps` (cờ `isNew`), `GET /api/devices/me/apps/decisions`, `GET /api/devices/{id}/apps?status=`, `PUT /api/devices/{id}/apps/{package}` | Con báo app mới, kéo quyết định; mẹ cho phép / chặn | API-07 |
| Báo cáo | `POST /api/reports`, `GET /api/devices/{id}/reports` | Con gửi, mẹ xem | |

(Tên endpoint là dự kiến, sẽ chỉnh khi làm.)

---

## Câu hỏi mở

Sáu câu ban đầu đã chốt (xem mục 0). Còn lại:

Đã chốt: gửi danh sách app đã cài (tên + tên gói, không nội dung); một máy con thuộc đúng một mẹ, đổi mẹ thì hủy ghép rồi ghép lại.

Còn lại: quên mật khẩu khôi phục qua email, cần kiểm tra MonsterASP có hỗ trợ SMTP không (làm ở Đợt 4).

## Rủi ro đã biết

- Android có thể hạn chế tiến trình nền khi tiết kiệm pin → test máy thật
- Chính sách Google Play với quyền Accessibility / Device Admin
- Giới hạn gói MonsterASP chưa kiểm tra
- Dữ liệu trẻ em nhạy cảm về pháp lý và quyền riêng tư

## Nhật ký

- 2026-10-30: Lập kế hoạch, chốt SQL Server + MonsterASP + polling. Chưa viết code.
- 2026-10-30: Chốt 1 mẹ nhiều con, email + mật khẩu, ngưỡng offline mẹ tự chỉnh (mặc định 24h), chỉ gửi thống kê dùng theo app, APK nội bộ, polling 5 phút.
- 2026-10-31: Task 12 (T4.0): viết `SafeFamily.Api` (Auth, Pairing, Devices, Policy, Commands, Apps) + migration `Initial`. Test tay bằng curl trên LocalDB: đăng ký, tạo mã, claim (mã dùng lại bị 400), PUT luật (lệch phiên bản 409), con đọc luật/lệnh, ack, đẩy app, hủy ghép (con bị 401), con gọi endpoint của mẹ bị 403, Swagger 200. Flutter: `lib/core/network/`, `RolePage`, đăng nhập mẹ, nhập mã con, `ConnectionPage`. Chưa làm: publish MonsterASP, test 2 máy thật, polling nền của máy con (WorkManager), đẩy luật thật từ `time_limit`/`app_lock`/`pause_card`.
- 2026-10-31: API-04. Chốt schema policy `schemaVersion` 1 (`lib/core/network/policy_schema.dart`). Flutter mẹ: `PolicySync` (`lib/core/network/policy_sync.dart`) gom các lần sửa 2 giây rồi `putPolicy`; máy con mẹ chọn lưu ở `ConnectionSession.selectedChildId` (tự chọn khi chỉ có 1 máy, chạm máy trong "Kết nối gia đình" để chọn); phiên bản luật mẹ biết lưu theo từng máy con; 409 thì tải luật server, nếu khác thì hỏi "Giữ luật trên máy chủ / Ghi đè" (ghi đè qua `ParentGate.always`). Kotlin: `FamilySync.pullPolicy` kiểm tra hết rồi mới ghi, đọc thêm `appLock.blocked` (khóa qua `BlockingServiceManager` của app_blocker, bỏ qua app hệ thống, nhớ danh sách mẹ khóa trong `GuardPrefs.remoteBlocked`). Server: kiểm tra kích thước theo byte + gốc phải là đối tượng JSON. Test: analyze sạch, `flutter test` 299 đạt, APK debug build được, `dotnet build` 0 lỗi, `smoke.sh` trên LocalDB đạt (kể cả 409/400 của policy). Chưa có project `dotnet test`. CHƯA test 2 máy thật.
- 2026-10-31: API-05. Server: `CommandRules` (danh sách Type + kiểm payload JSON ≤4 KB, `app_unlock_temp` minutes 1–240), lệnh quá 24h không giao nữa. Kotlin con: `FamilySync.applyAppCommand` (`app_unlock_temp/relock/block/allow`, tái dùng `TempRelocks`, `BlockingServiceManager`, `GuardPrefs.remoteBlocked`; không chặn app miễn trừ; sai thì không ack), luật mới không cắt ngang mở tạm. Flutter mẹ: `RemoteCommands`, nối `app_lock_page` (mở tạm) và `pause_card` (pause/unpause) khi chế độ mẹ đã chọn máy con. Đã đạt: `flutter analyze`, `flutter test` (303), `flutter build apk --debug`, `dotnet build`, `smoke.sh` (+17 ca lệnh, hạn 24h kiểm tay qua SQL) trên LocalDB tạm đã xóa. Kotlin chưa chạy trên máy thật; chưa có dotnet test.
- 2026-10-31: API-09. Server: bảng `DeviceStatus` (migration `DeviceStatus`), `PUT /api/devices/me/status` (kiểm kiểu/độ dài/số lượng từng trường, `Services/StatusRules.cs`), `GET /api/devices/{id}/status` (lọc app mở tạm quá hạn). Kotlin con: `FamilySync.pushStatus` trong mỗi `syncOnce` (lỗi bị nuốt), `PermissionStatus` dùng chung với `MainActivity`, `TempRelocks.pendingUntil`. Flutter mẹ: trạng thái ở `remote_monitor_page`, `pause_card` theo `isPaused`, màn "Lệnh đã gửi", nút "Chặn lại ngay" từ xa ở `app_lock_page`. Đã đạt: `flutter analyze`, `flutter test` (313), `flutter build apk --debug`, `dotnet build` 0 lỗi, `smoke.sh` (+~28 ca status, tất cả khớp mã mong đợi) trên LocalDB tạm đã xóa. Chưa có dotnet test; Kotlin chưa chạy trên máy thật; CHƯA test 2 máy thật.
- 2026-10-31: API-06. Server: bảng `ChildRequest` (migration `ChildRequests`), `POST/GET devices/me/requests`, `GET devices/{id}/requests?status=`, `PUT requests/{id}` (duyệt/từ chối, tự tạo lệnh `study_approve`/`study_reject`/`extra_time_grant` trong cùng một lần lưu; `Services/RequestRules.cs`, chặn trùng đang chờ → 409, hết hạn 24 giờ, mẹ gia đình khác → 404, kiểm kiểu/độ dài/số lượng từng trường, payload chỉ có `minutes`). Kotlin con: `FamilySync.queueRequest` (hàng chờ SharedPreferences, gửi bù, nuốt lỗi), thông báo kết quả cho con, `extra_time_grant`, nối `TimeLimitBlockActivity` và `StudyBlock.claimDone`. Flutter mẹ: `ChildRequestsPage` (duyệt/từ chối qua `ParentGate`), `ChildRequestAlertChecker` trong `parent_alert_worker`. Đã đạt: `flutter analyze` sạch, `flutter test` 321, `flutter build apk --debug`, `dotnet build` 0 lỗi, `smoke.sh` (+~60 ca yêu cầu, 91 ca có mã mong đợi đều khớp; hạn 24 giờ kiểm tay bằng SQL) trên LocalDB tạm đã xóa. Chưa có dotnet test; Kotlin chưa chạy trên máy thật; CHƯA test 2 máy thật.
- 2026-10-31: API-07. Server: `InstalledApp` thêm `Status` (`new|allowed|blocked`) + `DecidedAt` (migration `InstalledAppStatus`, dòng cũ thành `allowed`, nhãn giới hạn 200). `POST devices/me/apps` nhận cờ `isNew` (con chỉ báo app chờ duyệt, không tự đặt allowed/blocked; kiểm tên gói, nhãn, tối đa 2000 app/máy); `GET devices/{id}/apps?status=` (mẹ, ≤200); `PUT devices/{id}/apps/{package}` (mẹ, `allowed|blocked`; gia đình khác / app lạ → 404); `GET devices/me/apps/decisions` (con kéo quyết định). Logic ở `Services/AppRules.cs`, `CommandRules.IsPackage` dùng chung. Quyết định áp bằng `NewApps.approve/reject` có sẵn của máy con, KHÔNG đi qua `appLock.blocked` hay lệnh `app_block/app_allow` nên không lẫn với danh sách khóa của mẹ (API-05). Kotlin: `NewApps.syncWithServer` (gọi cuối nhánh app trong `syncOnce` và ngay khi quét thấy app mới), hàng chờ = `pending` trừ `uploaded` trong SharedPreferences, lỗi nuốt hết. Flutter mẹ: `NewAppsPage` đọc server khi ở chế độ mẹ (`RemoteNewAppsView`), cho phép / chặn qua `ParentGate.always`; nút "App mới cài" ở màn máy con; `NewAppAlertChecker` trong `parent_alert_worker`. Tự động đạt: `smoke.sh` (120 kiểm tra, 0 lệch), `flutter analyze`, `flutter test` (329), `flutter build apk --debug`, `dotnet build`. CHƯA test máy thật.
