# Tiến trình: Web API (Swagger) + tích hợp Flutter/Android

Mục tiêu: máy mẹ quản lý máy con từ xa qua server. Máy con vẫn tự chặn bằng code Kotlin hiện có; API chỉ chuyển luật/lệnh qua lại.

Cập nhật lần cuối: 2026-10-31 · Trạng thái chung: **Đợt 1, 2, 5 xong code; test tự động đạt trên LocalDB; chưa publish MonsterASP, chưa test 2 máy thật (TASKS/TEST_PLAN.md)**

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
- [~] Luật khóa app và lịch chặn: dùng chung `policy` JSON ở trên; chưa định nghĩa schema JSON, làm khi nối `time_limit`/`app_lock`
- [x] `POST /api/devices/{id}/commands`; con `GET /api/devices/me/commands` và `POST .../commands/{id}/ack`
- [x] `DELETE /api/devices/{id}` hủy ghép

Flutter (mẹ):
- [x] Thêm tầng gọi API: `lib/core/network/` (`ApiClient`, `ConnectionSession`; tự refresh token, GET thử lại 3 lần, có test)
- [x] Màn chọn vai trò "Một máy / Máy mẹ / Máy con" (`RolePage`, hiện sau wizard quyền)
- [x] Màn đăng nhập/đăng ký + tạo mã ghép đôi (`ParentLoginPage`, `ConnectionPage` trong Bảo mật → Kết nối gia đình)
- [ ] Đẩy cấu hình giới hạn giờ, khóa app, tạm dừng lên server (nối vào `time_limit`, `app_lock`, `pause_card`)

Flutter/Android (con):
- [x] Màn nhập mã ghép đôi (`ChildPairPage`)
- [ ] Polling định kỳ bằng WorkManager (hoặc dùng service sẵn có), hỏi thêm khi mở app / có mạng lại
- [ ] Ghi luật tải về vào `GuardPrefs` chỉ khi tải thành công và hợp lệ; lỗi thì giữ bản cũ
- [ ] Kiểm tra: tắt mạng máy con, luật vẫn chặn đúng

Cột mốc đợt 2: mẹ đặt giới hạn cho 1 app trên máy mẹ, máy con tải về và chặn đúng, chạy trên 2 máy thật với MonsterASP.

## Đợt 3 – Hai chiều

- [ ] Con xin thêm giờ → mẹ duyệt / từ chối (`extra_time`, `study_approval`, `StudyBlock.kt`)
- [ ] Con báo app mới cài → mẹ cho dùng hoặc chặn (`NewApps.kt`)
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
| Yêu cầu | `POST /api/requests`, `PUT /api/requests/{id}` | Con tạo, mẹ duyệt | Xin giờ, app mới |
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
