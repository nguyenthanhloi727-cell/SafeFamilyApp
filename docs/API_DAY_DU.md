# Thống kê tính năng app ↔ API và task còn thiếu

Cập nhật: 2026-10-31. Đối chiếu từ code `lib/features/*`, `android/.../*.kt`, `SafeFamily.Api/Controllers/*`.
Tiến độ chi tiết từng đợt vẫn ở `docs/API_TIEN_TRINH.md`; file này là bản tổng hợp "app có gì, API đã phủ chưa, còn task nào".

Ký hiệu: ✅ đã có · 🟡 có một phần · ❌ chưa có · ➖ không cần API (chỉ chạy trên máy)

Mã task `API-xx` dùng để tham chiếu. Làm theo "Thứ tự đề xuất" cuối file.

---

## 1. API hiện có (24 endpoint)

| Nhóm | Endpoint | Ai gọi |
|---|---|---|
| Auth | `POST /api/auth/register`, `/login`, `/refresh` | Mẹ |
| Ghép đôi | `POST /api/pairing/code` (mẹ), `POST /api/pairing/claim` (con) | Mẹ / Con |
| Thiết bị | `GET /api/devices`, `DELETE /api/devices/{id}` | Mẹ |
| Luật | `GET/PUT /api/devices/{id}/policy`, `GET /api/devices/me/policy` | Mẹ ghi / Con đọc |
| Lệnh | `POST/GET /api/devices/{id}/commands`, `GET /api/devices/me/commands`, `POST /api/devices/me/commands/{id}/ack` | Mẹ tạo / Con nhận |
| App đã cài | `POST /api/devices/me/apps`, `GET /api/devices/{id}/apps` | Con gửi / Mẹ xem |
| Vị trí | `POST /api/devices/me/locations`, `GET /api/devices/{id}/location`, `GET /api/devices/{id}/locations` | Con / Mẹ |
| Hàng rào | `GET/PUT /api/devices/{id}/geofences`, `GET /api/devices/me/geofences`, `POST /api/devices/me/geofence-events`, `GET /api/devices/{id}/geofence-events` | Mẹ / Con |

Lệnh máy con đã hiểu (`FamilySync.apply`): `pause`, `lock`, `unpause`, `unlock`, `study_start`, `study_stop`, `disable_limit_today`, `enable_limit_today`, `study_approve`, `study_reject`.
Gói luật (schema `schemaVersion` 1): `{"schemaVersion":1,"timeLimit":{...},"appLock":{"blocked":[pkg],"schedules":[]}}`.

---

## 2. Tính năng của app và độ phủ API

| # | Tính năng (thư mục) | Hiện chạy ở | API | Còn thiếu | Task |
|---|---|---|---|---|---|
| 1 | Chọn vai trò, ghép đôi (`connection/`) | Máy + server | ✅ | Đổi tên máy con; xem thông tin máy con (`/me`); thêm người giám hộ thứ 2 | API-01, API-02 |
| 2 | Tài khoản mẹ (`parent_login_page`) | Server | 🟡 | Đăng xuất (thu hồi refresh), đổi mật khẩu, quên mật khẩu, xóa tài khoản | API-03 |
| 3 | Giới hạn thời gian: ngày, giờ ngủ, theo tuổi (`time_limit/`) | Máy con (Kotlin) | 🟡 `policy.timeLimit` | Mẹ đã đẩy được (có test tự động); chờ test 2 máy thật | API-04 |
| 4 | Giờ học, "Đã học xong", duyệt (`study_approval`, `StudyBlock.kt`) | Máy con | 🟡 lệnh `study_*` có | Con chưa gửi yêu cầu duyệt lên; mẹ chưa có danh sách yêu cầu | API-06 |
| 5 | Xin thêm giờ (`extra_time`) | Máy con | ❌ | Endpoint yêu cầu, duyệt/từ chối | API-06 |
| 6 | Tạm dừng (`pause_card`) | Máy con | 🟡 lệnh `pause/unpause` có | UI mẹ đã gọi từ xa (chờ test máy thật); chưa trả trạng thái hiện tại về mẹ | API-09 |
| 7 | Khóa ứng dụng, lịch chặn, mở tạm (`app_lock/`, `TempRelocks.kt`) | Máy con | 🟡 `policy.appLock.blocked` | Danh sách chặn đã đẩy/ghi được (chờ test máy thật). Lệnh `app_unlock_temp/relock/block/allow` đã có, nút mở tạm của mẹ đã nối (chờ test máy thật). Còn: lịch chặn riêng từng app, UI chặn lại / chặn / cho phép từ xa | API-05, API-07 |
| 8 | App mới cài (`new_app/`, `NewApps.kt`) | Máy con | 🟡 gửi danh sách app | Trạng thái duyệt (cho dùng/chặn) mỗi app; thông báo cho mẹ khi có app mới | API-07 |
| 9 | Báo cáo sử dụng (`report/`, `UsageReport.kt`) | Máy con | ❌ | Con gửi `DayUsage` theo ngày; mẹ xem theo máy con | API-08 |
| 10 | Nhật ký mở khóa (`unlock_log`) | Máy con | ➖ | Đã chốt không đưa lên server | – |
| 11 | Cảnh báo tamper: đổi giờ máy, gỡ app, tắt trợ năng/Device Admin, mất kết nối (`TimeChangeReceiver`, `UninstallGate`, `SettingsGuardService`) | Máy con | ❌ | Con gửi sự kiện cảnh báo; mẹ nhận; server tự cảnh báo "mất kết nối > ngưỡng" | API-10 |
| 12 | Vị trí (`FamilyService`, `remote_monitor_page`) | Máy con + server | ✅ | Xóa lịch sử; mẹ bật/tắt chia sẻ vị trí; pin còn lại của máy con | API-11 |
| 13 | Hàng rào địa lý (`Geofences.kt`) | Máy con + server | ✅ | Thông báo máy mẹ trễ 15 phút (WorkManager), cân nhắc đẩy | API-12 |
| 14 | Lệnh từ xa (khóa/mở, tắt giới hạn hôm nay…) | Server | ✅ | Trả trạng thái thực thi cho mẹ (ack đã có, chưa có màn lịch sử lệnh) | API-09 |
| 15 | Hồ sơ, liên hệ gia đình, SOS (`profile/`) | Máy | ❌ | Đồng bộ liên hệ khẩn cấp xuống máy con (cân nhắc riêng tư) | API-13 |
| 16 | Quyền ứng dụng, Setup Wizard, Đang cản trở (`PermissionRegistry`, `setup/`, `home/`) | Máy | ➖ | Chỉ cần báo mẹ khi con thiếu quyền (xem API-10) | – |
| 17 | PIN, mã khôi phục, sinh trắc (`core/security/`) | Máy | ➖ | Đã chốt chỉ lưu hash trên máy | – |
| 18 | Báo thức giọng nói (`alarm/`) | Máy | ➖ | Không liên quan giám sát | – |
| 19 | Thành viên nhóm (`team/`, `assets/team`) | Asset | ➖ | Dữ liệu tĩnh trong app | – |
| 20 | Chủ đề, ngôn ngữ (`theme_settings`, `app_languages`) | Máy | ➖ | – | – |

---

## 3. Danh sách task API

Mỗi task: endpoint/bảng cần thêm, phía Flutter/Kotlin cần nối, điều kiện xong. Nên mở context riêng cho mỗi task (theo `TASKS/TASKS.md`).

### API-01 Đổi tên máy con, xem thông tin máy mình
- API: `PATCH /api/devices/{id}` (mẹ, đổi `Name`), `GET /api/devices/me` (con: tên, mẹ, phiên bản luật).
- Flutter: sửa tên trong `device_management_page`; con hiện "đang được giám sát bởi…".
- Xong khi: đổi tên trên máy mẹ thì danh sách đổi theo.

### API-02 Người giám hộ thứ 2 (bố)
- API: `POST /api/family/invite`, `POST /api/family/join`, bảng `Parent` nhiều dòng cùng `FamilyId` (đã có `Family`).
- Quyết định chốt trước: bố có quyền ngang mẹ không. Đang ghi "để sau" trong `API_TIEN_TRINH.md`.
- Xong khi: hai tài khoản cùng thấy một danh sách máy con.

### API-03 Hoàn thiện tài khoản
- API: `POST /api/auth/logout` (thu hồi refresh), `POST /api/auth/change-password`, `POST /api/auth/forgot-password` + `reset-password` (cần SMTP, kiểm tra MonsterASP), `DELETE /api/auth/account` (xóa toàn bộ dữ liệu gia đình).
- Flutter: nút đăng xuất thật (hiện `reset()` chỉ xóa token cục bộ), màn quên mật khẩu.
- Xong khi: sau đăng xuất, refresh token cũ bị 401.

### API-04 Chốt schema `policy` và đẩy từ Flutter mẹ — code xong, CHƯA test máy thật
- Schema đã chốt: `{"schemaVersion":1,"timeLimit":{...},"appLock":{"blocked":[pkg],"schedules":[]}}`. `study`, `contacts` chưa có (thêm khi làm API-13; máy con bỏ qua trường lạ, gặp `schemaVersion` lớn hơn mình hiểu thì giữ luật cũ). Server vẫn lưu nguyên khối, chỉ kiểm tra là đối tượng JSON hợp lệ và ≤64 KB.
- Flutter mẹ (xong): `PolicySync` đẩy sau khi lưu ở `time_limit_page` và `app_lock_page` (`block_schedules` chỉ hiển thị, không lưu gì nên không cần). Chỉ chạy khi chế độ "mẹ" và đã chọn máy con. 409 → tải lại → khác thì hỏi mẹ; giống thì bỏ qua.
- Kotlin con (xong, chưa chạy thật): `pullPolicy` kiểm tra hết rồi mới ghi `timeLimit` + `appLock.blocked`; lỗi thì giữ luật cũ.
- Tự động đã đạt: `flutter test` (có `policy_sync_test.dart`), `smoke.sh` (policy 200/409/400).
- Còn lại: "Xong khi" bên dưới cần 2 máy thật + MonsterASP (TASKS/TEST_PLAN.md). Việc lưu từ `FeatureRegistry` ("Đang cản trở" tắt giờ học/giờ ngủ) và nút mở tạm/bỏ chặn từ trang chủ chưa đẩy tự động; mẹ dùng nút "Gửi luật" ở màn máy con.
- Xong khi: mẹ khóa YouTube trên máy mẹ, máy con chặn YouTube trong ≤5 phút, tắt mạng vẫn chặn.

### API-05 Lệnh từ xa: bổ sung loại lệnh — code xong, CHƯA test máy thật
- Server (xong, đã chạy `smoke.sh`): `Services/CommandRules.cs` là danh sách `Type` cho phép (`pause`, `lock`, `unpause`, `unlock`, `study_*`, `disable/enable_limit_today`, `app_unlock_temp`, `app_relock`, `app_block`, `app_allow`; loại lạ → 400). Payload phải là đối tượng JSON ≤4 KB; `app_*` cần `package` đúng dạng tên gói; `app_unlock_temp` cần `minutes` 1–240. Lệnh chưa giao sau 24h không giao nữa (`GET devices/me/commands` lọc theo `CreatedAt`; lỗi #5 và #10 trong TEST_PLAN).
- Kotlin con (xong, chưa chạy thật): `FamilySync.applyAppCommand`. Mở tạm = `TempRelocks.remember` rồi `stopBlockingApps`; hết hạn do `TempRelocks.sweep` chặn lại (gọi khi đổi cửa sổ, khởi động máy và mỗi lượt đồng bộ). `app_block` không bao giờ chặn app trong `TimeLimits.exemptPackages`. Payload sai / chặn app miễn trừ → không ack.
- Nhất quán với `policy.appLock.blocked`: `previous` (`GuardPrefs.remoteBlocked`) không đổi khi mở tạm, nên luật mới không cắt ngang mở tạm (`applyRemoteBlocked` bỏ qua app đang mở tạm) và app mẹ bỏ khỏi danh sách thì hạn chặn lại cũ bị xóa theo. `app_block` / `app_allow` ghi vào `remoteBlocked` nhưng luật phiên bản mới của mẹ vẫn là nguồn sự thật: nếu danh sách trên máy mẹ vẫn có app mà mẹ vừa `app_allow` thì lần đẩy luật kế sẽ chặn lại. Chưa có UI mẹ cho `app_block`/`app_allow`; khi làm (API-07) phải sửa danh sách mẹ cùng lúc.
- Flutter mẹ (xong, có test tự động `remote_commands_test.dart`): `RemoteCommands` (`lib/core/network/remote_commands.dart`). `app_lock_page` nút mở tạm và `pause_card` gửi lệnh khi chế độ "mẹ" đã chọn máy con; vẫn qua `ParentGate`. Chưa chọn máy con thì làm trên máy này như cũ. Chưa có nút "chặn lại ngay" từ xa (cần biết trạng thái mở tạm của máy con, API-09). `pause_card` ở chế độ mẹ chưa hiện trạng thái tạm dừng của máy con.
- Xong khi: mẹ bấm mở tạm một app, con mở được rồi tự chặn lại (cần 2 máy thật, xem TASKS/TEST_PLAN.md "Bổ sung API-05").

### API-06 Yêu cầu của con (xin thêm giờ, "đã học xong")
- Bảng `ChildRequest` (DeviceId, Kind: `extra_time|study_done`, Payload, Status: `pending|approved|rejected`, CreatedAt, DecidedAt).
- API: `POST /api/devices/me/requests` (con), `GET /api/devices/me/requests/{id}` (con xem kết quả), `GET /api/devices/{id}/requests?status=pending` (mẹ), `PUT /api/requests/{id}` (mẹ duyệt/từ chối; server tự tạo lệnh `study_approve/reject` hoặc cộng giờ).
- Kotlin: `extra_time` và `StudyBlock` gửi yêu cầu khi có mạng, xếp hàng khi offline.
- Flutter mẹ: danh sách chờ duyệt, qua khóa phụ huynh (sinh trắc) trước khi duyệt.
- Xong khi: con xin thêm 30 phút, mẹ duyệt, con thấy được cộng giờ.

### API-07 Duyệt app mới cài
- Mở rộng `InstalledApp`: `Status` (`new|allowed|blocked`), `DecidedAt`.
- API: `PUT /api/devices/{id}/apps/{package}` (mẹ đặt trạng thái), `GET /api/devices/{id}/apps?status=new`; con kéo trạng thái qua policy (`appLock.blocked`) hoặc lệnh.
- Flutter: `new_apps_page` đọc từ server khi ở chế độ mẹ.
- Xong khi: cài app mới trên máy con, máy mẹ thấy trong ≤5 phút và chặn được.

### API-08 Báo cáo sử dụng
- Bảng `UsageDay` (DeviceId, Date, TotalMinutes, Blocks) và `UsageApp` (UsageDayId, Package, Minutes). Khóa duy nhất (DeviceId, Date) để gửi lại không trùng.
- API: `POST /api/devices/me/usage` (lô nhiều ngày, upsert), `GET /api/devices/{id}/usage?from=&to=` (mẹ).
- Kotlin: `UsageReport.kt` đẩy ngày đã chốt và ngày hiện tại khi polling.
- Flutter: `report_page` có chọn máy con khi ở chế độ mẹ.
- Dữ liệu chỉ là phút theo app, đúng quyết định "chỉ thống kê". Dọn dữ liệu quá 90 ngày.
- Xong khi: mẹ xem được biểu đồ tuần của máy con.

### API-09 Trạng thái máy con và lịch sử lệnh
- API: `GET /api/devices/{id}/status` trả `lastSeenAt`, `batteryPercent`, `policyVersion`, `isPaused`, `studyActive`, `permissionsMissing[]`, `appVersion`; con gửi qua `PUT /api/devices/me/status` mỗi lần polling.
- `GET /api/devices/{id}/commands` đã có: thêm màn "Lệnh đã gửi" (đang chờ / đã thực thi / thất bại).
- Xong khi: màn máy con hiện đúng "đang tạm dừng", "pin 40%", "lần cuối 2 phút trước".

### API-10 Cảnh báo cho mẹ (tamper và mất kết nối)
- Bảng `Alert` (DeviceId, Kind, Detail, CreatedAt, ReadAt). Loại: `time_changed`, `app_uninstall_attempt`, `accessibility_off`, `device_admin_off`, `permission_missing`, `offline`.
- API: `POST /api/devices/me/alerts` (con), `GET /api/devices/{id}/alerts?afterId=` (mẹ), `POST /api/alerts/{id}/read`.
- Server: tác vụ nền (hosted service) đánh dấu `offline` khi `LastSeenAt` quá ngưỡng (mặc định 24h, mẹ chỉnh được: thêm trường ngưỡng vào cài đặt gia đình).
- Kotlin: `TimeChangeReceiver`, `UninstallGate`, `SettingsGuardService` gọi gửi cảnh báo (xếp hàng offline).
- Flutter mẹ: mở rộng `parent_alert_worker` để báo cả cảnh báo này (cùng WorkManager 15 phút).
- Xong khi: tắt trợ năng trên máy con, mẹ nhận thông báo.

### API-11 Quyền riêng tư vị trí
- API: `DELETE /api/devices/{id}/locations` (xóa lịch sử), cờ `LocationSharing` trong cài đặt máy con (mẹ bật/tắt, con kéo về).
- Chốt còn mở: giữ bao nhiêu ngày (code đang 7), con có thấy lịch sử của mình không.
- Xong khi: tắt chia sẻ thì con dừng gửi vị trí, mẹ xóa được lịch sử.

### API-12 Thông báo nhanh hơn (tùy chọn)
- Hiện trễ tối thiểu 15 phút ở máy mẹ. Phương án: SignalR (cần app mở) hoặc FCM (đã chốt không dùng). Chỉ làm khi người dùng chấp nhận đổi quyết định.

### API-13 Đồng bộ liên hệ khẩn cấp
- Đưa `contacts` (nhãn, số, cờ SOS) vào `policy` để máy con gọi SOS từ màn chặn. Cân nhắc quyền riêng tư: chỉ gửi số khẩn cấp, không gửi cả danh bạ.
- Xong khi: mẹ đặt số SOS, màn chặn của con gọi đúng số.

### API-14 Nền tảng và vận hành server
- `GET /health` cho MonsterASP.
- HTTPS bắt buộc, CORS, rà soát JWT và băm mật khẩu.
- Ghi log lỗi phía server (Serilog ra file), trả lỗi dạng `ProblemDetails` thống nhất.
- Giới hạn tần suất cho các endpoint con (polling), giới hạn kích thước body.
- Tác vụ dọn dữ liệu định kỳ (vị trí, báo cáo, lệnh cũ, mã ghép hết hạn).
- Versioning: tiền tố `/api/v1` hoặc header `X-App-Version`, để bản app cũ không làm hỏng server mới.
- Publish MonsterASP, chạy `smoke.sh` trên máy chủ thật.

### API-15 Kiểm thử
- Test tích hợp cho `SafeFamily.Api` (xUnit + `WebApplicationFactory`): phân quyền chéo gia đình (mẹ A không đọc máy con của mẹ B), 409 lệch phiên bản, mã ghép dùng lại, token bị thu hồi.
- Mở rộng `smoke.sh` cho mọi endpoint mới.
- Test máy thật theo `TASKS/TEST_PLAN.md`.

---

## 4. Thứ tự đề xuất

1. **API-04** (policy + đẩy từ Flutter): chạm đúng cốt lõi, mở khóa app lock và giới hạn giờ.
2. **API-05** (lệnh mở rộng) và **API-09** (trạng thái): vài endpoint nhỏ, lợi lớn cho UI mẹ.
3. **API-06** (yêu cầu của con), **API-07** (duyệt app mới).
4. **API-08** (báo cáo), **API-10** (cảnh báo).
5. **API-03**, **API-01**, **API-11**, **API-13**.
6. **API-14**, **API-15** làm xen kẽ; bắt buộc xong trước khi phát hành.
7. **API-02**, **API-12**: chỉ làm khi người dùng chốt quyết định.

## 5. Câu hỏi cần chốt

1. Có thêm tài khoản bố ngang quyền mẹ không (API-02)?
2. Báo cáo sử dụng giữ bao nhiêu ngày (đề xuất 90)? Vị trí giữ bao nhiêu ngày (đang 7)?
3. Chấp nhận trễ 15 phút cho thông báo ở máy mẹ, hay đổi quyết định không dùng FCM (API-12)?
4. Có gửi liên hệ khẩn cấp lên server không (API-13)?
5. MonsterASP có SMTP để làm quên mật khẩu không (API-03)?
