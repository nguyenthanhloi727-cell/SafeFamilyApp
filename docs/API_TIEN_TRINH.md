# Tiến trình: Web API (Swagger) + tích hợp Flutter/Android

Mục tiêu: máy mẹ quản lý máy con từ xa qua server. Máy con vẫn tự chặn bằng code Kotlin hiện có; API chỉ chuyển luật/lệnh qua lại.

Cập nhật lần cuối: 2026-10-31 (API-13) · Trạng thái chung: **Đợt 1, 2, 5 xong code; test tự động đạt trên LocalDB; chưa publish MyASP.net, chưa test 2 máy thật (TASKS/TEST_PLAN.md)**

Ký hiệu: `[ ]` chưa làm · `[~]` đang làm · `[x]` xong

---

## 0. Quyết định đã chốt

- [x] Backend: ASP.NET Core Web API, mở bằng Visual Studio, có Swagger (Swashbuckle)
- [x] CSDL: SQL Server
- [x] Hosting: MyASP.net
- [x] Đồng bộ: máy con hỏi server định kỳ (polling) ở bản đầu, chưa dùng FCM
- [x] Mô hình: server lưu luật/lệnh, máy con tải về và tự thi hành; offline vẫn chặn theo luật đã lưu
- [x] PIN và mã khôi phục chỉ lưu hash trên máy, không gửi lên server
- [x] Giữ chế độ "một máy" (local) song song với chế độ "kết nối"

- [x] Gia đình: tối đa 2 người giám hộ (mẹ + bố, API-02), nhiều con (mỗi con có thể là một máy)
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
- [ ] Kiểm tra gói MyASP.net: dung lượng SQL Server, số kết nối, có HTTPS, có cho publish từ Visual Studio (Web Deploy/FTP)
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
- [ ] Publish thử lên MyASP.net, mở được Swagger trên mạng

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

Cột mốc đợt 2: mẹ đặt giới hạn cho 1 app trên máy mẹ, máy con tải về và chặn đúng, chạy trên 2 máy thật với MyASP.net.

## Đợt 3 – Hai chiều

- [~] Con xin thêm giờ / báo "đã học xong" → mẹ duyệt / từ chối (`extra_time`, `study_done`; API-06). Server + Flutter mẹ đã test tự động đạt; Kotlin con biên dịch được nhưng CHƯA chạy máy thật nên chưa tick
- [~] Con báo app mới cài → mẹ cho dùng hoặc chặn (`NewApps.kt`; API-07). Server + Flutter mẹ đã test tự động đạt; Kotlin con biên dịch được nhưng CHƯA chạy máy thật nên chưa tick
- [~] Con gửi báo cáo sử dụng → mẹ xem (`UsageReport.kt`, `report_page`; API-08). Server + Flutter mẹ đã test tự động đạt; Kotlin con biên dịch được nhưng CHƯA chạy máy thật nên chưa tick
- [ ] Con gửi nhật ký mở khóa (`unlock_log`)
- [ ] Yêu cầu tạo lúc offline được xếp hàng trong máy và gửi khi có mạng (code đã có cho API-06/07/08/10 nhưng CHƯA test máy thật nên chưa tick)
- [~] Cảnh báo cho mẹ: máy con mất kết nối lâu, chỉnh giờ máy, gỡ app, tắt trợ năng/Device Admin, thiếu quyền (`TimeChangeReceiver`, `UninstallGate`, `SettingsGuardService`, `TamperAlerts.kt`; API-10). Server + Flutter mẹ đã test tự động đạt (server tự phát hiện mất kết nối đã kiểm bằng SQL); Kotlin con biên dịch được nhưng CHƯA chạy máy thật nên chưa tick
- [ ] Hồ sơ, liên hệ gia đình (`profile`, `team`) – làm cuối, cân nhắc quyền riêng tư

## Đợt 4 – Củng cố

- [ ] HTTPS bắt buộc, rà soát bảo mật JWT, mật khẩu băm, CORS
- [x] Test tích hợp API: `SafeFamily.Api.Tests` (xUnit + `WebApplicationFactory`, LocalDB tạm, 174 ca): phân quyền chéo gia đình, 409, mã ghép dùng lại, token bị thu hồi, kiểm kiểu / giới hạn, Swagger (API-15). Chạy: `cd SafeFamily.Api.Tests` rồi `dotnet test`. Test máy thật vẫn theo `TASKS/TEST_PLAN.md`.
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
- [x] Quyền riêng tư vị trí (API-11, chốt 2026-10-31: giữ **7 ngày**, con **không** xem lịch sử vị trí của mình): cờ `Device.LocationSharing` (mặc định bật, migration `LocationSharing`); `GET/PUT /api/devices/{id}/location-sharing` (mẹ, body `{"enabled":bool}` bắt buộc, sai kiểu → 400, gia đình khác / máy hủy ghép → 404); `DELETE /api/devices/{id}/locations` xóa toàn bộ lịch sử (204); `GET devices/me/settings` (con kéo `{"locationSharing":bool}`); cờ tắt thì `POST devices/me/locations` trả **403** và KHÔNG lưu, `GET .../location` và `.../locations` của mẹ trả **403** `{"error":"Đã tắt chia sẻ vị trí.","locationSharing":false}`. Smoke test đạt (LocalDB tạm, đã xóa); Flutter mẹ có công tắc "Chia sẻ vị trí" + nút "Xóa lịch sử vị trí" (qua khóa phụ huynh, xóa có hộp xác nhận), test widget đạt
- [~] Kotlin máy con theo cờ `locationSharing` (kéo trong `syncOnce`, tắt thì dừng thu thập, xóa `pending_locations`, bật lại thì thu thập tiếp, thông báo thường trực đổi chữ): biên dịch được (`flutter build apk --debug`), CHƯA chạy máy thật nên chưa tick (xem `TASKS/TEST_PLAN.md` "Bổ sung API-11")
- [x] Liên hệ khẩn cấp SOS trong `policy` (API-13, chốt 2026-10-31: cho phép gửi nhãn + số lên server, tối đa 3 số, con gọi thẳng): `schemaVersion` 2 thêm `contacts:[{label,phone,sos}]`, chỉ số mẹ chọn, không gửi cả danh bạ. `PUT /api/devices/{id}/policy` kiểm `contacts` (`Services/PolicyRules.cs`): mảng ≤3, nhãn 1–30 ký tự không ký tự điều khiển, số `+?`+9–12 chữ số, `sos` bool; sai → 400 và giữ nguyên phiên bản; gia đình khác → 404; không endpoint/migration mới. Smoke test đạt (LocalDB tạm, đã xóa); Flutter mẹ chọn nhiều số SOS ở "Cá nhân" (qua `ParentGate`) và `PolicySync` gửi kèm, test đạt
- [~] Kotlin con (API-13): `FamilySync.parsePolicy` hiểu schema 2 và kiểm `contacts` hết rồi mới ghi `GuardPrefs.setSos`; `TimeLimitBlockActivity` hiện nút SOS gọi thẳng (`ACTION_CALL`, xin `CALL_PHONE` lúc bấm, từ chối thì mở bàn phím). APK build được, CHƯA chạy máy thật
- [x] Đổi tên máy con, máy con xem thông tin mình (API-01): `PATCH /api/devices/{id}` (mẹ, body `{"name"}`, cắt khoảng trắng, 1–50 ký tự, không ký tự điều khiển, sai → 400, gia đình khác / máy hủy ghép → 404) và `GET /api/devices/me` (con: `id`, `name`, `familyName`, `pairedAt`, `policyVersion`; không có email mẹ). Smoke test đạt (LocalDB tạm); Flutter: nút "Đổi tên" qua `ParentGate` ở `ConnectionPage`, máy con hiện "đang được giám sát bởi…", test widget đạt
- [x] Hoàn thiện tài khoản (API-03): `POST /api/auth/logout` (thu hồi refresh token, token cũ → `/refresh` 401), `POST /api/auth/change-password` (mật khẩu cũ, thu hồi các phiên khác), `DELETE /api/auth/account` (nhập lại mật khẩu + `confirm:true`, xóa toàn bộ dữ liệu gia đình trong một giao dịch), `POST /api/auth/forgot-password` + `reset-password` (mã 6 số qua email, hạn 30 phút, dùng một lần, sai 5 lần thì hủy; bảng `PasswordResets`, migration `PasswordReset`). Flutter: đăng xuất thật, màn đổi mật khẩu, quên mật khẩu, xóa tài khoản (qua `ParentGate`). Smoke + test Flutter đạt
- [x] Người giám hộ thứ 2 (API-02): `GET /api/family`, `POST /api/family/invite` (chủ, mã 8 số hạn 30 phút dùng một lần), `POST /api/family/join` (đăng ký tài khoản mới vào gia đình bằng mã), `DELETE /api/family/members/{id}` (chủ), `POST /api/family/leave`; bố ngang mẹ trừ xóa tài khoản gia đình và mời/xóa người giám hộ; tối đa 2 người; bảng `FamilyInvites` + cột `Parents.IsOwner` (migration `FamilyGuardians`). Test tự động + smoke đạt
- [ ] Màn hình Flutter cho API-02 (mời, nhập mã, danh sách người giám hộ, rời gia đình) và test 2 máy thật: chưa làm
- [x] API-12 thông báo nhanh hơn: CHỐT (2026-10-31, người dùng trả lời) giữ nguyên máy mẹ nhận thông báo trễ tối thiểu 15 phút (WorkManager, polling), vẫn KHÔNG dùng FCM, không làm SignalR. Chỉ ghi quyết định vào docs, không đổi code/server/migration. Muốn nhanh hơn sau này phải mở lại quyết định (SignalR cần app mở; FCM cần Firebase + `google-services.json` + service account cho server)
- [~] Quên mật khẩu qua thư THẬT (API-03): code xong nhưng chưa gửi thư thật lần nào, TODO(verify) host/port/tài khoản/From SMTP của MyASP.net (xem mục Cấu hình)


Ghi chú 2026-10-31 (thêm): máy mẹ nhận thông báo vào/ra vùng khi app đóng bằng WorkManager 15 phút (`lib/core/alerts/`), chỉ gọi `GET /api/devices` + `GET .../geofence-events?afterId=`; không đổi API. Chưa test máy thật.

Ghi chú 2026-10-31: migration `LocationGeofence`; smoke test `SafeFamily.Api/smoke.sh`; máy con gọi qua Kotlin (`FamilySync`), mẹ qua `ApiClient`. Chưa test trên MyASP.net và 2 máy thật: xem `TASKS/TEST_PLAN.md`.

---

## Cấu hình và chạy thử (dev)

Bí mật không nằm trong git. Đặt bằng biến môi trường hoặc `SafeFamily.Api/appsettings.Local.json` (đã `.gitignore`):

```json
{
  "ConnectionStrings": { "Default": "Server=(localdb)\MSSQLLocalDB;Database=SafeFamilyDev;Trusted_Connection=True;TrustServerCertificate=True" },
  "Jwt": { "Key": "chuỗi ngẫu nhiên từ 32 ký tự trở lên" }
}
```

Trên MyASP.net đặt hai giá trị này trong cấu hình/biến môi trường của site (`ConnectionStrings__Default`, `Jwt__Key`). Thiếu thì app báo lỗi rõ khi khởi động.

Thư đặt lại mật khẩu (API-03) cần SMTP, cấu hình tùy chọn dạng biến môi trường (hoặc `appsettings.Local.json`): `Smtp__Host`, `Smtp__Port` (mặc định 587), `Smtp__UseSsl` (mặc định true = STARTTLS; `SmtpClient` không hỗ trợ SSL ngầm định ở cổng 465), `Smtp__User`, `Smtp__Password` (bí mật, KHÔNG để trong git), `Smtp__From` (địa chỉ người gửi). Không có `Smtp__From` (và `Smtp__Host`) thì API vẫn chạy, chỉ ghi cảnh báo vào log khi mẹ xin mã. `Smtp__PickupDirectory=<thư mục>` ghi thư thành file `.eml` thay vì gửi (dùng cho test, `smoke.sh` đọc mã từ đó qua `SF_MAIL_DIR`). TODO(verify): host/port/tài khoản/From thật của MyASP.net chưa được cung cấp. Trần giới hạn tần suất đọc từ `RateLimit__AuthPerMinute` (mặc định 10) và `RateLimit__ClaimPer10Min` (mặc định 5); chạy `smoke.sh` thì đặt cả hai lên 1000.

```bash
cd SafeFamily.Api
dotnet ef database update      # tạo DB
dotnet run                     # Swagger: <địa chỉ>/swagger
```

Cảnh báo mất kết nối (API-10) chạy nền trong API, cấu hình tùy chọn (biến môi trường dạng `Alerts__OfflineHours`): `Alerts:OfflineHours` (mặc định 24, số giờ không liên lạc thì báo `offline`) và `Alerts:CheckIntervalSeconds` (mặc định 900). Để `smoke.sh` kiểm phần retention + offline, đặt `Alerts__CheckIntervalSeconds=3` khi chạy API và `SF_SQL_SERVER` / `SF_SQL_DB` (cần `sqlcmd`) khi chạy smoke; thiếu thì phần đó in `SKIP`. Bộ giới hạn `claim` (5 lần/10 phút/IP) làm chạy `smoke.sh` liên tiếp bị lỗi: khởi động lại API giữa các lần. Hoặc nâng trần khi khởi động API bằng `RateLimit__ClaimPer10Min` (mặc định 5) và `RateLimit__AuthPerMinute` (mặc định 10); test tích hợp `SafeFamily.Api.Tests` dùng chính hai cấu hình này (cần LocalDB, tự tạo và xóa CSDL tạm).

Emulator Android gọi máy tính qua `http://10.0.2.2:<cổng>`; app mặc định `ConnectionSession.defaultBaseUrl`, sửa được trên màn kết nối. Bản release chặn HTTP thường (cleartext), dùng HTTPS khi lên MyASP.net.

## Danh sách API dự kiến (sẽ hiện trong Swagger)

| Nhóm | Endpoint | Ai gọi | Ghi chú |
|---|---|---|---|
| Auth | `POST /api/auth/register`, `/login`, `/refresh` | Mẹ | JWT |
| Tài khoản | `POST /api/auth/logout`, `/forgot-password`, `/reset-password`; `POST /api/auth/change-password`, `DELETE /api/auth/account` (cần token mẹ) | Mẹ | API-03: đăng xuất thu hồi refresh, mã đặt lại 6 số hạn 30 phút, xóa tài khoản xóa toàn bộ dữ liệu gia đình |
| Gia đình | `GET /api/family`, `POST /api/family/invite`, `POST /api/family/leave`, `DELETE /api/family/members/{parentId}` (token mẹ); `POST /api/family/join` (không cần token, chính sách "claim") | Mẹ / bố | API-02: mã mời 8 số hạn 30 phút dùng một lần, tối đa 2 người giám hộ, chỉ chủ mời/xóa |
| Ghép đôi | `POST /api/pairing/code` | Mẹ | Tạo mã có hạn |
| Ghép đôi | `POST /api/pairing/claim` | Con | Nhập mã, nhận token thiết bị |
| Thiết bị | `GET /api/devices`, `DELETE /api/devices/{id}` | Mẹ | Danh sách / hủy ghép |
| Luật | `GET/PUT /api/devices/{id}/policy` | Mẹ ghi, con đọc | Có số phiên bản; `contacts` SOS (API-13) được kiểm, sai → 400 |
| Lệnh | `POST /api/devices/{id}/commands`, `GET /api/devices/me/commands` | Mẹ tạo, con đọc | Tạm dừng, cho thêm giờ |
| Yêu cầu | `POST /api/devices/me/requests`, `GET /api/devices/me/requests/{id}`, `GET /api/devices/{id}/requests`, `PUT /api/requests/{id}` | Con tạo, mẹ duyệt | Xin thêm giờ, đã học xong (API-06) |
| Duyệt app mới | `POST /api/devices/me/apps` (cờ `isNew`), `GET /api/devices/me/apps/decisions`, `GET /api/devices/{id}/apps?status=`, `PUT /api/devices/{id}/apps/{package}` | Con báo app mới, kéo quyết định; mẹ cho phép / chặn | API-07 |
| Báo cáo | `POST /api/devices/me/usage`, `GET /api/devices/{id}/usage?from=&to=` | Con gửi, mẹ xem | API-08: phút theo app theo ngày, upsert, giữ 90 ngày |
| Quyền riêng tư vị trí | `GET/PUT /api/devices/{id}/location-sharing`, `DELETE /api/devices/{id}/locations`, `GET /api/devices/me/settings` | Mẹ bật/tắt + xóa, con kéo cờ | API-11: mặc định bật; tắt thì con ngừng gửi, server trả 403 và không lưu; giữ vị trí 7 ngày |
| Cảnh báo | `POST /api/devices/me/alerts`, `GET /api/devices/{id}/alerts?afterId=`, `POST /api/alerts/{id}/read` | Con gửi, mẹ xem / đã đọc | API-10: tamper + mất kết nối (server tự tạo `offline`), chống trùng 10 phút, ≤200 dòng/máy, giữ 30 ngày |

(Tên endpoint là dự kiến, sẽ chỉnh khi làm.)

---

## Câu hỏi mở

Sáu câu ban đầu đã chốt (xem mục 0). Còn lại:

Đã chốt: gửi danh sách app đã cài (tên + tên gói, không nội dung); một máy con thuộc đúng một mẹ, đổi mẹ thì hủy ghép rồi ghép lại.

Quên mật khẩu qua email (API-03): đã làm, MyASP.net có SMTP nhưng host/port/tài khoản/From thật chưa được cung cấp, chưa gửi thư thật.

## Rủi ro đã biết

- Android có thể hạn chế tiến trình nền khi tiết kiệm pin → test máy thật
- Chính sách Google Play với quyền Accessibility / Device Admin
- Giới hạn gói MyASP.net chưa kiểm tra
- Dữ liệu trẻ em nhạy cảm về pháp lý và quyền riêng tư

## Nhật ký

- 2026-10-30: Lập kế hoạch, chốt SQL Server + MyASP.net + polling. Chưa viết code.
- 2026-10-30: Chốt 1 mẹ nhiều con, email + mật khẩu, ngưỡng offline mẹ tự chỉnh (mặc định 24h), chỉ gửi thống kê dùng theo app, APK nội bộ, polling 5 phút.
- 2026-10-31: Task 12 (T4.0): viết `SafeFamily.Api` (Auth, Pairing, Devices, Policy, Commands, Apps) + migration `Initial`. Test tay bằng curl trên LocalDB: đăng ký, tạo mã, claim (mã dùng lại bị 400), PUT luật (lệch phiên bản 409), con đọc luật/lệnh, ack, đẩy app, hủy ghép (con bị 401), con gọi endpoint của mẹ bị 403, Swagger 200. Flutter: `lib/core/network/`, `RolePage`, đăng nhập mẹ, nhập mã con, `ConnectionPage`. Chưa làm: publish MyASP.net, test 2 máy thật, polling nền của máy con (WorkManager), đẩy luật thật từ `time_limit`/`app_lock`/`pause_card`.
- 2026-10-31: API-04. Chốt schema policy `schemaVersion` 1 (`lib/core/network/policy_schema.dart`). Flutter mẹ: `PolicySync` (`lib/core/network/policy_sync.dart`) gom các lần sửa 2 giây rồi `putPolicy`; máy con mẹ chọn lưu ở `ConnectionSession.selectedChildId` (tự chọn khi chỉ có 1 máy, chạm máy trong "Kết nối gia đình" để chọn); phiên bản luật mẹ biết lưu theo từng máy con; 409 thì tải luật server, nếu khác thì hỏi "Giữ luật trên máy chủ / Ghi đè" (ghi đè qua `ParentGate.always`). Kotlin: `FamilySync.pullPolicy` kiểm tra hết rồi mới ghi, đọc thêm `appLock.blocked` (khóa qua `BlockingServiceManager` của app_blocker, bỏ qua app hệ thống, nhớ danh sách mẹ khóa trong `GuardPrefs.remoteBlocked`). Server: kiểm tra kích thước theo byte + gốc phải là đối tượng JSON. Test: analyze sạch, `flutter test` 299 đạt, APK debug build được, `dotnet build` 0 lỗi, `smoke.sh` trên LocalDB đạt (kể cả 409/400 của policy). Chưa có project `dotnet test`. CHƯA test 2 máy thật.
- 2026-10-31: API-05. Server: `CommandRules` (danh sách Type + kiểm payload JSON ≤4 KB, `app_unlock_temp` minutes 1–240), lệnh quá 24h không giao nữa. Kotlin con: `FamilySync.applyAppCommand` (`app_unlock_temp/relock/block/allow`, tái dùng `TempRelocks`, `BlockingServiceManager`, `GuardPrefs.remoteBlocked`; không chặn app miễn trừ; sai thì không ack), luật mới không cắt ngang mở tạm. Flutter mẹ: `RemoteCommands`, nối `app_lock_page` (mở tạm) và `pause_card` (pause/unpause) khi chế độ mẹ đã chọn máy con. Đã đạt: `flutter analyze`, `flutter test` (303), `flutter build apk --debug`, `dotnet build`, `smoke.sh` (+17 ca lệnh, hạn 24h kiểm tay qua SQL) trên LocalDB tạm đã xóa. Kotlin chưa chạy trên máy thật; chưa có dotnet test.
- 2026-10-31: API-09. Server: bảng `DeviceStatus` (migration `DeviceStatus`), `PUT /api/devices/me/status` (kiểm kiểu/độ dài/số lượng từng trường, `Services/StatusRules.cs`), `GET /api/devices/{id}/status` (lọc app mở tạm quá hạn). Kotlin con: `FamilySync.pushStatus` trong mỗi `syncOnce` (lỗi bị nuốt), `PermissionStatus` dùng chung với `MainActivity`, `TempRelocks.pendingUntil`. Flutter mẹ: trạng thái ở `remote_monitor_page`, `pause_card` theo `isPaused`, màn "Lệnh đã gửi", nút "Chặn lại ngay" từ xa ở `app_lock_page`. Đã đạt: `flutter analyze`, `flutter test` (313), `flutter build apk --debug`, `dotnet build` 0 lỗi, `smoke.sh` (+~28 ca status, tất cả khớp mã mong đợi) trên LocalDB tạm đã xóa. Chưa có dotnet test; Kotlin chưa chạy trên máy thật; CHƯA test 2 máy thật.
- 2026-10-31: API-06. Server: bảng `ChildRequest` (migration `ChildRequests`), `POST/GET devices/me/requests`, `GET devices/{id}/requests?status=`, `PUT requests/{id}` (duyệt/từ chối, tự tạo lệnh `study_approve`/`study_reject`/`extra_time_grant` trong cùng một lần lưu; `Services/RequestRules.cs`, chặn trùng đang chờ → 409, hết hạn 24 giờ, mẹ gia đình khác → 404, kiểm kiểu/độ dài/số lượng từng trường, payload chỉ có `minutes`). Kotlin con: `FamilySync.queueRequest` (hàng chờ SharedPreferences, gửi bù, nuốt lỗi), thông báo kết quả cho con, `extra_time_grant`, nối `TimeLimitBlockActivity` và `StudyBlock.claimDone`. Flutter mẹ: `ChildRequestsPage` (duyệt/từ chối qua `ParentGate`), `ChildRequestAlertChecker` trong `parent_alert_worker`. Đã đạt: `flutter analyze` sạch, `flutter test` 321, `flutter build apk --debug`, `dotnet build` 0 lỗi, `smoke.sh` (+~60 ca yêu cầu, 91 ca có mã mong đợi đều khớp; hạn 24 giờ kiểm tay bằng SQL) trên LocalDB tạm đã xóa. Chưa có dotnet test; Kotlin chưa chạy trên máy thật; CHƯA test 2 máy thật.
- 2026-10-31: API-07. Server: `InstalledApp` thêm `Status` (`new|allowed|blocked`) + `DecidedAt` (migration `InstalledAppStatus`, dòng cũ thành `allowed`, nhãn giới hạn 200). `POST devices/me/apps` nhận cờ `isNew` (con chỉ báo app chờ duyệt, không tự đặt allowed/blocked; kiểm tên gói, nhãn, tối đa 2000 app/máy); `GET devices/{id}/apps?status=` (mẹ, ≤200); `PUT devices/{id}/apps/{package}` (mẹ, `allowed|blocked`; gia đình khác / app lạ → 404); `GET devices/me/apps/decisions` (con kéo quyết định). Logic ở `Services/AppRules.cs`, `CommandRules.IsPackage` dùng chung. Quyết định áp bằng `NewApps.approve/reject` có sẵn của máy con, KHÔNG đi qua `appLock.blocked` hay lệnh `app_block/app_allow` nên không lẫn với danh sách khóa của mẹ (API-05). Kotlin: `NewApps.syncWithServer` (gọi cuối nhánh app trong `syncOnce` và ngay khi quét thấy app mới), hàng chờ = `pending` trừ `uploaded` trong SharedPreferences, lỗi nuốt hết. Flutter mẹ: `NewAppsPage` đọc server khi ở chế độ mẹ (`RemoteNewAppsView`), cho phép / chặn qua `ParentGate.always`; nút "App mới cài" ở màn máy con; `NewAppAlertChecker` trong `parent_alert_worker`. Tự động đạt: `smoke.sh` (120 kiểm tra, 0 lệch), `flutter analyze`, `flutter test` (329), `flutter build apk --debug`, `dotnet build`. CHƯA test máy thật.
- 2026-10-31: API-08. Server: bảng `UsageDay` (`DeviceId`, `Date`, `TotalMinutes`, `Blocks`) + `UsageApp` (migration `UsageReport`, khóa duy nhất (`DeviceId`, `Date`) để gửi lại không trùng, xóa app theo ngày bằng cascade), `POST devices/me/usage` (lô ≤31 ngày, upsert, kiểm kiểu/độ dài/số lượng từng trường: ≤200 app/ngày, phút 0–1440, tên gói đúng dạng, ngày không quá 1 ngày tương lai và không cũ hơn 90 ngày) và `GET devices/{id}/usage?from=&to=` (mẹ, tối đa 90 ngày; gia đình khác / máy hủy ghép → 404), dọn dữ liệu quá 90 ngày mỗi lần gửi (đã kiểm bằng SQL: ngày 95 ngày tuổi và `UsageApp` của nó bị xóa). Logic ở `Services/UsageRules.cs`. Kotlin: `UsageReport.syncWithServer` trong `FamilySync.syncOnce` (ngày chốt gửi một lần theo chữ ký, hôm nay gửi khi đổi, bỏ app miễn trừ, lỗi nuốt hết). Flutter mẹ: `ReportPage` đọc server khi ở chế độ mẹ (`RemoteReportView`: hôm nay, biểu đồ 7 ngày, top app, chọn máy con); chế độ máy con giữ nguyên. Tự động đạt: `flutter analyze` (0 lỗi), `flutter test` (337), `flutter build apk --debug`, `dotnet build` (0 lỗi), `smoke.sh` (159 kiểm tra mã trả về, 0 lệch, gồm ~38 ca usage) trên LocalDB tạm đã xóa. Chưa có `dotnet test`. Kotlin chưa chạy trên máy thật; CHƯA test 2 máy thật.
- 2026-10-31: API-10. Server: bảng `Alert` (migration `Alerts`), `POST devices/me/alerts` (kiểm kiểu/độ dài/số lượng: loại thuộc danh sách, `offline` chỉ server tạo, `detail` chỉ mã/số ngắn, `occurredAt` trong 7 ngày; chống trùng ±10 phút → 409; ≤200 dòng/máy, vượt thì xóa dòng cũ nhất; dọn >30 ngày), `GET devices/{id}/alerts?afterId=` (mẹ), `POST alerts/{id}/read` (mẹ; gia đình khác → 404), `OfflineAlertService` (hosted service, ngưỡng `Alerts:OfflineHours` mặc định 24, một cảnh báo mỗi đợt mất kết nối; `Services/AlertRules.cs`). Kotlin con: `TamperAlerts.kt` (hàng chờ SharedPreferences + gửi bù trong `syncOnce`, lỗi nuốt hết) nối `TimeChangeReceiver`, `UninstallGate`, `SettingsGuardService` (challenge + `onUnbind` chờ 15 giây kiểm lại), `SafeFamilyAdminReceiver.onDisabled`, và phát hiện quyền mới thiếu mỗi lượt đồng bộ. Flutter mẹ: `TamperAlertChecker` trong `parent_alert_worker`, `DeviceAlertsPage` + nút "Cảnh báo (N chưa đọc)" ở màn máy con. Đã đạt: `flutter analyze` sạch, `flutter test` (346), `flutter build apk --debug`, `dotnet build` 0 lỗi, `smoke.sh` (195 kiểm tra mã trả về, 0 lệch; thêm ca cap 200 dòng, retention 30 ngày, offline 25h không lặp / đợt mới / máy hủy ghép) trên LocalDB tạm đã xóa. Chưa có `dotnet test`; Kotlin chưa chạy trên máy thật; CHƯA test 2 máy thật. Chưa làm: mẹ chỉnh ngưỡng mất kết nối trong cài đặt gia đình.
- 2026-10-31: API-01. Server: `PATCH /api/devices/{id}` và `GET /api/devices/me` trong `DevicesController` (`Services/DeviceRules.cs`: tên 1–50 ký tự sau khi cắt khoảng trắng, không ký tự điều khiển; DTO `RenameDeviceRequest`, `DeviceMeDto`), không đổi schema DB nên không có migration. Flutter: `ApiClient.renameDevice` / `fetchMyInfo`, `ConnectionPage` có nút "Đổi tên" (qua `ParentGate.always`) và dòng "đang được giám sát bởi" cho máy con; test `test/features/connection/device_rename_test.dart`. Đã đạt: `flutter analyze` sạch, `flutter test` 352, `flutter build apk --debug`, `dotnet build` 0 lỗi, `smoke.sh` (221 kiểm tra mã trả về, 0 lệch, gồm ~15 ca API-01) trên LocalDB tạm. Chưa có `dotnet test`; CHƯA test 2 máy thật.

- 2026-10-31: API-13. Chốt với người dùng: gửi nhãn + số SOS lên server, tối đa 3 số, gọi thẳng. Server: `Services/PolicyRules.cs` kiểm `contacts` trong `PutPolicy` (không migration, không endpoint mới). Flutter: `PolicySchema` version 2 + `contacts`, `PolicySync.loadContacts`, `ProfileController.toggleEmergency` (tối đa 3), `ProfilePage` đẩy luật sau khi đổi liên hệ SOS. Kotlin: `SUPPORTED_SCHEMA` 2, `parseSos`, `GuardPrefs.setSos/sos`, nút SOS gọi thẳng ở `TimeLimitBlockActivity`, quyền `CALL_PHONE`. Test: `flutter analyze` sạch; `flutter test` 354 đạt (thêm test schema contacts, `PolicySync` gửi SOS, tối đa 3 số); `flutter build apk --debug` thành công (có biên dịch Kotlin); `dotnet build` 0 lỗi (build vào thư mục tạm vì một API đang chạy khóa file `bin`); `smoke.sh` trên LocalDB tạm (đã xóa): 22 ca API-13 đạt; toàn bộ 395 kiểm tra mã trả về có 41 lệch đều là 429 của bộ giới hạn xác thực (thay đổi AuthController chưa commit của việc khác, không thuộc API-13). Chưa có project `dotnet test` đã commit. CHƯA test 2 máy thật.
- 2026-10-31: API-15. Tạo `SafeFamily.Api.Tests` (net10.0, xUnit 2.9.3, `Microsoft.AspNetCore.Mvc.Testing` 10.0.5): `ApiFactory` dựng API thật trong bộ nhớ trên CSDL LocalDB tạm (`Migrate()`, xóa khi xong), dùng chung một factory cho mọi lớp (`SharedApi`); các nhóm `CrossFamilyTests` (21 đường dẫn × mẹ khác 404 + đối chứng chủ 2xx, ghi không đổi gì), `ConflictTests` (409), `AuthAndTokenTests` (mã ghép, refresh, hủy ghép, token giả, vai trò), `ValidationTests` (kiểu / độ dài / số lượng từng nhóm), `SwaggerTests` (mọi action có trong swagger). `Program.cs`: thêm `public partial class Program;` và cấu hình `RateLimit:ClaimPer10Min` (mặc định 5, như cũ). Sửa lỗi thấy khi test: `POST devices/me/locations` lưu cả điểm quá hạn giữ 7 ngày (chỉ bị xóa ở lượt gửi sau) → nay bỏ ngay. `smoke.sh`: thêm khối API-15. Kết quả 2026-10-31: `dotnet test` 174/174 đạt; `smoke.sh` trên LocalDB tạm (cổng 5026, đã xóa DB) 396 ca có "expect", 0 sai; `flutter analyze` sạch; `flutter test` 354 đạt; `flutter build apk --debug` thành công. Ghi nhận chưa sửa: chuỗi số được ép thành số, `readAt` lúc thiếu `Z`, giới hạn tên máy tính trên chuỗi thô (xem `API_DAY_DU.md`, mục API-15).
- 2026-10-31: API-03. Server: `AuthController` thêm `logout`, `change-password`, `forgot-password`, `reset-password`, `DELETE account`; bảng `PasswordResets` (migration `PasswordReset`); `Services/PasswordResetRules.cs` (mã 6 số, hạn 30 phút, HMAC theo khóa JWT, 5 lần sai thì hủy, `IEmailSender`/`SmtpEmailSender`, `SmtpOptions`); `Program.cs` đăng ký SMTP và đọc `RateLimit:AuthPerMinute`. Hỏi người dùng về SMTP: trả lời "có SMTP", hạn mã 30 phút, nhưng host/port/tài khoản/From thật chưa có nên để toàn bộ qua cấu hình `Smtp__*` và ghi TODO(verify). Flutter: `ApiClient.logout/changePassword/deleteAccount/forgotPassword/resetPassword`, `account_pages.dart`, nút ở `ConnectionPage` và "Quên mật khẩu?" ở `ParentLoginPage`; test `test/features/connection/account_test.dart`. Đã đạt: `flutter analyze` sạch, `flutter test` 367 (gồm cả thay đổi chưa commit của việc khác), `flutter build apk --debug`, `dotnet build` 0 lỗi, `dotnet test -c Release` 174 đạt (`SafeFamily.Api.Tests` là của API-15, chưa commit), `smoke.sh` 391 kiểm tra mã trả về, 0 lệch (77 ca API-03, gồm đọc mã từ thư `.eml` và kiểm bảng còn sót trên SQL) trên LocalDB tạm đã xóa. CHƯA có: thư thật qua SMTP MyASP.net, test máy thật.
- 2026-10-31: API-02. Hỏi người dùng 4 câu và chốt: bố ngang mẹ trừ xóa tài khoản gia đình; chỉ chủ gia đình mời/xóa; mã mời 30 phút dùng một lần; tối đa 2 người giám hộ. Server: `Parent.IsOwner` (tài khoản có sẵn mặc định là chủ), bảng `FamilyInvites`, migration `FamilyGuardians`, `Controllers/FamilyController.cs`, `Services/FamilyRules.cs`; `AuthController` đăng ký đặt `IsOwner`, `DELETE account` chỉ chủ (người khác 403) và xóa luôn mã mời. Giới hạn dò mã dùng trần theo IP (chính sách "claim"), không đếm 5 lần sai theo từng mã được vì mã sai không thuộc mã nào. Flutter: `ApiClient.family/inviteGuardian/joinFamily/removeGuardian/leaveFamily`, `FamilyInfo`; chưa có màn hình. Test: `SafeFamily.Api.Tests/FamilyGuardianTests.cs` (24 ca), `test/core/network/family_api_test.dart` (7 ca), 22 ca smoke. Đã đạt: `flutter analyze` sạch, `flutter test` 374, `flutter build apk --debug`, `dotnet build -c Release` 0 lỗi, `dotnet test -c Release` 210 đạt (gồm `PlatformTests` của API-14 chưa commit), `smoke.sh` 486 kiểm tra mã trả về, 0 lệch, trên LocalDB tạm đã xóa. Lưu ý: người giám hộ bị xóa vẫn dùng được access token đã cấp tối đa 30 phút (JWT không trạng thái, như đăng xuất). `dotnet build` Debug bị khóa file vì một `SafeFamily.Api.exe` đang chạy sẵn trên máy (không phải của task này), nên build/test chạy cấu hình Release.

- 2026-10-31: API-12. Hỏi người dùng 3 câu (giữ 15 phút / SignalR / FCM); trả lời: giữ nguyên 15 phút, không FCM. Chỉ sửa docs (API_DAY_DU.md, API_TIEN_TRINH.md), không đổi code nên không chạy lại flutter analyze/test/build, dotnet build/test, smoke.sh; không có phần cần máy thật nên không thêm mục vào TEST_PLAN.md.
