# Thống kê tính năng app ↔ API và task còn thiếu

Cập nhật: 2026-10-31. Đối chiếu từ code `lib/features/*`, `android/.../*.kt`, `SafeFamily.Api/Controllers/*`.
Tiến độ chi tiết từng đợt vẫn ở `docs/API_TIEN_TRINH.md`; file này là bản tổng hợp "app có gì, API đã phủ chưa, còn task nào".

Ký hiệu: ✅ đã có · 🟡 có một phần · ❌ chưa có · ➖ không cần API (chỉ chạy trên máy)

Mã task `API-xx` dùng để tham chiếu. Làm theo "Thứ tự đề xuất" cuối file.

---

## 1. API hiện có (35 endpoint)

| Nhóm | Endpoint | Ai gọi |
|---|---|---|
| Auth | `POST /api/auth/register`, `/login`, `/refresh` | Mẹ |
| Ghép đôi | `POST /api/pairing/code` (mẹ), `POST /api/pairing/claim` (con) | Mẹ / Con |
| Thiết bị | `GET /api/devices`, `DELETE /api/devices/{id}` | Mẹ |
| Luật | `GET/PUT /api/devices/{id}/policy`, `GET /api/devices/me/policy` | Mẹ ghi / Con đọc |
| Lệnh | `POST/GET /api/devices/{id}/commands`, `GET /api/devices/me/commands`, `POST /api/devices/me/commands/{id}/ack` | Mẹ tạo / Con nhận |
| Trạng thái | `PUT /api/devices/me/status` (con), `GET /api/devices/{id}/status` (mẹ) | Con báo / Mẹ xem |
| App đã cài | `POST /api/devices/me/apps`, `GET /api/devices/{id}/apps` | Con gửi / Mẹ xem |
| Vị trí | `POST /api/devices/me/locations`, `GET /api/devices/{id}/location`, `GET /api/devices/{id}/locations` | Con / Mẹ |
| Hàng rào | `GET/PUT /api/devices/{id}/geofences`, `GET /api/devices/me/geofences`, `POST /api/devices/me/geofence-events`, `GET /api/devices/{id}/geofence-events` | Mẹ / Con |
| Yêu cầu của con | `POST /api/devices/me/requests`, `GET /api/devices/me/requests/{id}` (con); `GET /api/devices/{id}/requests?status=`, `PUT /api/requests/{id}` (mẹ) | Con gửi / Mẹ duyệt |
| Báo cáo sử dụng | `POST /api/devices/me/usage` (con), `GET /api/devices/{id}/usage?from=&to=` (mẹ) | Con gửi / Mẹ xem |
| Cảnh báo | `POST /api/devices/me/alerts` (con), `GET /api/devices/{id}/alerts?afterId=` (mẹ), `POST /api/alerts/{id}/read` (mẹ) | Con gửi / Mẹ xem, đánh dấu đã đọc |

Lệnh máy con đã hiểu (`FamilySync.apply`): `pause`, `lock`, `unpause`, `unlock`, `study_start`, `study_stop`, `disable_limit_today`, `enable_limit_today`, `study_approve`, `study_reject`, `extra_time_grant` (API-06), `app_unlock_temp`, `app_relock`, `app_block`, `app_allow`.
Gói luật (schema `schemaVersion` 1): `{"schemaVersion":1,"timeLimit":{...},"appLock":{"blocked":[pkg],"schedules":[]}}`.

---

## 2. Tính năng của app và độ phủ API

| # | Tính năng (thư mục) | Hiện chạy ở | API | Còn thiếu | Task |
|---|---|---|---|---|---|
| 1 | Chọn vai trò, ghép đôi (`connection/`) | Máy + server | ✅ | Đổi tên máy con (`PATCH /api/devices/{id}`) và máy con xem thông tin mình (`GET /api/devices/me`): code xong, server + Flutter đã test tự động, chờ test 2 máy thật. Còn: thêm người giám hộ thứ 2 | API-01, API-02 |
| 2 | Tài khoản mẹ (`parent_login_page`, `account_pages`) | Server | 🟡 | Đăng xuất thật (thu hồi refresh), đổi mật khẩu, xóa tài khoản, quên/đặt lại mật khẩu: code xong, server + Flutter đã test tự động. Còn: thư thật cần SMTP MyASP.net (chưa có host/port/tài khoản/From), test máy thật; thêm người giám hộ thứ 2 (API-02) | API-03 |
| 3 | Giới hạn thời gian: ngày, giờ ngủ, theo tuổi (`time_limit/`) | Máy con (Kotlin) | 🟡 `policy.timeLimit` | Mẹ đã đẩy được (có test tự động); chờ test 2 máy thật | API-04 |
| 4 | Giờ học, "Đã học xong", duyệt (`study_approval`, `StudyBlock.kt`) | Máy con | 🟡 lệnh `study_*` có | Code xong, chờ test máy thật: con gửi yêu cầu "đã học xong", mẹ có danh sách duyệt | API-06 |
| 5 | Xin thêm giờ (`extra_time`) | Máy con + server | 🟡 | Code xong, chờ test máy thật: con xin 5/15/30 phút, mẹ duyệt/từ chối | API-06 |
| 6 | Tạm dừng (`pause_card`) | Máy con | 🟡 lệnh + trạng thái `isPaused` | UI mẹ gửi lệnh và hiện đúng trạng thái/nút tiếp tục theo `isPaused` (code xong, test tự động đạt; chờ test máy thật) | API-09 |
| 7 | Khóa ứng dụng, lịch chặn, mở tạm (`app_lock/`, `TempRelocks.kt`) | Máy con | 🟡 `policy.appLock.blocked` | Danh sách chặn đã đẩy/ghi được (chờ test máy thật). Lệnh `app_unlock_temp/relock/block/allow` đã có, nút mở tạm của mẹ đã nối (chờ test máy thật). Còn: lịch chặn riêng từng app, UI chặn lại / chặn / cho phép từ xa | API-05, API-07 |
| 8 | App mới cài (`new_app/`, `NewApps.kt`) | Máy con | 🟡 báo app mới + trạng thái duyệt | Code xong, chờ test máy thật: con báo app mới cài, mẹ cho phép / chặn từ xa, mẹ được báo khi có app mới | API-07 |
| 9 | Báo cáo sử dụng (`report/`, `UsageReport.kt`) | Máy con + server | 🟡 báo phút theo app theo ngày | Code xong, chờ test máy thật: con gửi phút theo app, mẹ chọn máy con và xem biểu đồ tuần | API-08 |
| 10 | Nhật ký mở khóa (`unlock_log`) | Máy con | ➖ | Đã chốt không đưa lên server | – |
| 11 | Cảnh báo tamper: đổi giờ máy, gỡ app, tắt trợ năng/Device Admin, mất kết nối (`TimeChangeReceiver`, `UninstallGate`, `SettingsGuardService`, `TamperAlerts.kt`) | Máy con + server | 🟡 báo loại sự kiện + mất kết nối do server tự phát hiện | Code xong, chờ test máy thật: con báo tamper (xếp hàng khi offline), server tự báo "mất kết nối > 24h", mẹ xem danh sách và được thông báo. Chưa có: mẹ chỉnh ngưỡng mất kết nối (hiện cấu hình server) | API-10 |
| 12 | Vị trí (`FamilyService`, `remote_monitor_page`) | Máy con + server | ✅ | Xóa lịch sử và công tắc chia sẻ vị trí: code xong, chờ test máy thật (giữ 7 ngày, con không xem lịch sử: đã chốt) | API-11 |
| 13 | Hàng rào địa lý (`Geofences.kt`) | Máy con + server | ✅ | Thông báo máy mẹ trễ 15 phút (WorkManager), cân nhắc đẩy | API-12 |
| 14 | Lệnh từ xa (khóa/mở, tắt giới hạn hôm nay…) | Server | ✅ | Màn "Lệnh đã gửi" (đang chờ / đã thực thi / quá hạn 24h) đã có, chờ test máy thật | API-09 |
| 15 | Hồ sơ, liên hệ gia đình, SOS (`profile/`) | Máy | 🟡 `policy.contacts` | Code xong, chờ test máy thật: mẹ chọn tối đa 3 số SOS, chỉ nhãn + số lên server (không gửi danh bạ), màn chặn của con gọi thẳng | API-13 |
| 16 | Quyền ứng dụng, Setup Wizard, Đang cản trở (`PermissionRegistry`, `setup/`, `home/`) | Máy | ➖ | Chỉ cần báo mẹ khi con thiếu quyền (xem API-10) | – |
| 17 | PIN, mã khôi phục, sinh trắc (`core/security/`) | Máy | ➖ | Đã chốt chỉ lưu hash trên máy | – |
| 18 | Báo thức giọng nói (`alarm/`) | Máy | ➖ | Không liên quan giám sát | – |
| 19 | Thành viên nhóm (`team/`, `assets/team`) | Asset | ➖ | Dữ liệu tĩnh trong app | – |
| 20 | Chủ đề, ngôn ngữ (`theme_settings`, `app_languages`) | Máy | ➖ | – | – |
| 21 | Kiểm thử tự động API (`SafeFamily.Api.Tests`, `smoke.sh`) | Server | ✅ | Test tích hợp 174 ca đạt; còn test máy thật theo `TEST_PLAN.md` | API-15 |

---

## 3. Danh sách task API

Mỗi task: endpoint/bảng cần thêm, phía Flutter/Kotlin cần nối, điều kiện xong. Nên mở context riêng cho mỗi task (theo `TASKS/TASKS.md`).

### API-01 Đổi tên máy con, xem thông tin máy mình — code xong, server + Flutter đã test tự động, CHƯA test 2 máy thật
- API: `PATCH /api/devices/{id}` (mẹ, đổi `Name`), `GET /api/devices/me` (con: tên, mẹ, phiên bản luật).
- Flutter: sửa tên trong `device_management_page`; con hiện "đang được giám sát bởi…".
- Xong khi: đổi tên trên máy mẹ thì danh sách đổi theo.
- Đã làm: `PATCH /api/devices/{id}` (mẹ, body `{"name":"..."}` bắt buộc; cắt khoảng trắng hai đầu, 1–50 ký tự, không có ký tự điều khiển; sai → 400; gia đình khác / máy hủy ghép → 404; trả `DeviceDto` mới). `GET /api/devices/me` (con) trả `{id,name,familyName,pairedAt,policyVersion}`, KHÔNG có email mẹ; token mẹ → 403, hủy ghép → 401. Logic tên ở `Services/DeviceRules.cs`.
- Flutter: `ApiClient.renameDevice` / `fetchMyInfo`. Nút bút chì "Đổi tên" ở danh sách máy con trong `ConnectionPage` (qua `ParentGate.always`, hộp nhập ≤50 ký tự, xong tải lại danh sách). Máy con hiện "<tên máy> đang được giám sát bởi <tên gia đình>" (lỗi mạng thì giữ dòng "Đã kết nối với máy mẹ"). Không đụng Kotlin.
- Lưu ý: tên gia đình mặc định "Gia đình" (đặt lúc đăng ký); chưa có chỗ để mẹ đổi tên gia đình.

### API-02 Người giám hộ thứ 2 (bố)
- API: `POST /api/family/invite`, `POST /api/family/join`, bảng `Parent` nhiều dòng cùng `FamilyId` (đã có `Family`).
- Quyết định chốt trước: bố có quyền ngang mẹ không. Đang ghi "để sau" trong `API_TIEN_TRINH.md`.
- Xong khi: hai tài khoản cùng thấy một danh sách máy con.

### API-03 Hoàn thiện tài khoản — code xong, server + Flutter đã test tự động, CHƯA test thư thật (SMTP) và máy thật
- API: `POST /api/auth/logout` (thu hồi refresh), `POST /api/auth/change-password`, `POST /api/auth/forgot-password` + `reset-password` (cần SMTP, kiểm tra MyASP.net), `DELETE /api/auth/account` (xóa toàn bộ dữ liệu gia đình).
- Flutter: nút đăng xuất thật (hiện `reset()` chỉ xóa token cục bộ), màn đổi mật khẩu, xóa tài khoản, quên mật khẩu.
- Xong khi: sau đăng xuất, refresh token cũ bị 401.
- Đã làm (server, `AuthController`):
  - `POST /api/auth/logout` body `{"refreshToken"}` (bắt buộc, ≤200 ký tự, sai → 400): thu hồi đúng token đó, không cần access token (access token hết hạn sau 30 phút). Gọi lại hoặc token lạ vẫn 204. Sau đó `/refresh` với token cũ → 401. Access token đã cấp còn dùng được tối đa 30 phút (JWT không trạng thái).
  - `POST /api/auth/change-password` (mẹ) body `{currentPassword,newPassword,refreshToken?}`: mật khẩu cũ sai → 403, mới <8 hoặc >128 ký tự → 400, mới trùng cũ → 400. Thu hồi mọi refresh token khác; `refreshToken` gửi kèm (phiên đang dùng) được giữ, bỏ trống thì thu hồi hết.
  - `DELETE /api/auth/account` (mẹ) body `{password,confirm:true}`: thiếu/sai kiểu `confirm` hoặc không phải `true` → 400, sai mật khẩu → 403, mẹ đã bị xóa → 404. Một giao dịch xóa máy con, luật, lệnh, app, vị trí, hàng rào, sự kiện, trạng thái, yêu cầu, báo cáo, cảnh báo, mã ghép, token, mã đặt lại, mẹ và gia đình. Sau đó token máy con → 401, email đăng ký lại được.
  - `POST /api/auth/forgot-password` `{email}`: LUÔN 204 (email lạ cũng 204, không lộ tài khoản); email sai định dạng → 400. Có tài khoản thì tạo mã 6 số (hạn **30 phút**, dùng một lần, chỉ lưu băm HMAC, xin lại trong 60 giây thì bỏ qua) và gửi thư nền qua SMTP.
  - `POST /api/auth/reset-password` `{email,code,newPassword}`: mã sai / hết hạn / đã dùng / email lạ đều 400 cùng một thông báo; nhập sai 5 lần thì mã bị hủy; đúng thì đổi mật khẩu và thu hồi mọi refresh token. Mã phải đúng 6 chữ số, mật khẩu mới 8–128 ký tự (sai → 400).
  - Bảng mới `PasswordResets` (migration `PasswordReset`). Thư qua `IEmailSender`/`SmtpEmailSender` (`Services/PasswordResetRules.cs`), cấu hình `Smtp:*` (xem `API_TIEN_TRINH.md`, mục Cấu hình); mật khẩu SMTP không nằm trong git. Không cấu hình SMTP thì chỉ ghi cảnh báo vào log, không lộ mã.
  - Trần giới hạn `/api/auth` đọc từ cấu hình `RateLimit:AuthPerMinute` (mặc định 10/phút/IP, giữ nguyên khi chạy thật); `smoke.sh` nâng lên khi chạy.
- Flutter: `ApiClient.logout` (thu hồi trên server rồi `session.reset()`; mất mạng vẫn đăng xuất cục bộ nhưng báo "chưa báo được cho máy chủ"), `changePassword`, `deleteAccount`, `forgotPassword`, `resetPassword`. `account_pages.dart`: `ChangePasswordPage`, `ForgotPasswordPage` (email → mã 6 số → mật khẩu mới), hộp xóa tài khoản (nhập lại mật khẩu). `ConnectionPage` (máy mẹ): "Đăng xuất máy mẹ", "Đổi mật khẩu", "Xóa tài khoản" đều qua `ParentGate.always`; `ParentLoginPage` có "Quên mật khẩu?". Không đụng Kotlin.
- Tự động đã đạt: `flutter test` (có `test/features/connection/account_test.dart`, 13 ca), `smoke.sh` (77 kiểm tra API-03 trong 391 kiểm tra, 0 lệch).
- Còn lại / TODO(verify): MyASP.net có SMTP, nhưng host/port/tài khoản gửi/địa chỉ From thật CHƯA được cung cấp, nên chưa gửi thư thật lần nào (smoke dùng thư mục nhận thư `Smtp:PickupDirectory`). `SmtpClient` của .NET chỉ hỗ trợ STARTTLS (cổng 587), không hỗ trợ SSL ngầm định ở cổng 465. Chưa có tài khoản "đặt lại mật khẩu" cho máy con (máy con không có mật khẩu). Mã đặt lại gửi qua email thường: ai đọc được hộp thư của mẹ thì đặt lại được mật khẩu.

### API-04 Chốt schema `policy` và đẩy từ Flutter mẹ — code xong, CHƯA test máy thật
- Schema đã chốt: `{"schemaVersion":1,"timeLimit":{...},"appLock":{"blocked":[pkg],"schedules":[]}}`. `study` chưa có; `contacts` đã thêm ở API-13 (`schemaVersion` 2; máy con bỏ qua trường lạ, gặp `schemaVersion` lớn hơn mình hiểu thì giữ luật cũ). Server vẫn lưu nguyên khối, chỉ kiểm tra là đối tượng JSON hợp lệ và ≤64 KB.
- Flutter mẹ (xong): `PolicySync` đẩy sau khi lưu ở `time_limit_page` và `app_lock_page` (`block_schedules` chỉ hiển thị, không lưu gì nên không cần). Chỉ chạy khi chế độ "mẹ" và đã chọn máy con. 409 → tải lại → khác thì hỏi mẹ; giống thì bỏ qua.
- Kotlin con (xong, chưa chạy thật): `pullPolicy` kiểm tra hết rồi mới ghi `timeLimit` + `appLock.blocked`; lỗi thì giữ luật cũ.
- Tự động đã đạt: `flutter test` (có `policy_sync_test.dart`), `smoke.sh` (policy 200/409/400).
- Còn lại: "Xong khi" bên dưới cần 2 máy thật + MyASP.net (TASKS/TEST_PLAN.md). Việc lưu từ `FeatureRegistry` ("Đang cản trở" tắt giờ học/giờ ngủ) và nút mở tạm/bỏ chặn từ trang chủ chưa đẩy tự động; mẹ dùng nút "Gửi luật" ở màn máy con.
- Xong khi: mẹ khóa YouTube trên máy mẹ, máy con chặn YouTube trong ≤5 phút, tắt mạng vẫn chặn.

### API-05 Lệnh từ xa: bổ sung loại lệnh — code xong, CHƯA test máy thật
- Server (xong, đã chạy `smoke.sh`): `Services/CommandRules.cs` là danh sách `Type` cho phép (`pause`, `lock`, `unpause`, `unlock`, `study_*`, `disable/enable_limit_today`, `app_unlock_temp`, `app_relock`, `app_block`, `app_allow`; loại lạ → 400). Payload phải là đối tượng JSON ≤4 KB; `app_*` cần `package` đúng dạng tên gói; `app_unlock_temp` cần `minutes` 1–240. Lệnh chưa giao sau 24h không giao nữa (`GET devices/me/commands` lọc theo `CreatedAt`; lỗi #5 và #10 trong TEST_PLAN).
- Kotlin con (xong, chưa chạy thật): `FamilySync.applyAppCommand`. Mở tạm = `TempRelocks.remember` rồi `stopBlockingApps`; hết hạn do `TempRelocks.sweep` chặn lại (gọi khi đổi cửa sổ, khởi động máy và mỗi lượt đồng bộ). `app_block` không bao giờ chặn app trong `TimeLimits.exemptPackages`. Payload sai / chặn app miễn trừ → không ack.
- Nhất quán với `policy.appLock.blocked`: `previous` (`GuardPrefs.remoteBlocked`) không đổi khi mở tạm, nên luật mới không cắt ngang mở tạm (`applyRemoteBlocked` bỏ qua app đang mở tạm) và app mẹ bỏ khỏi danh sách thì hạn chặn lại cũ bị xóa theo. `app_block` / `app_allow` ghi vào `remoteBlocked` nhưng luật phiên bản mới của mẹ vẫn là nguồn sự thật: nếu danh sách trên máy mẹ vẫn có app mà mẹ vừa `app_allow` thì lần đẩy luật kế sẽ chặn lại. Chưa có UI mẹ cho `app_block`/`app_allow`; khi làm (API-07) phải sửa danh sách mẹ cùng lúc.
- Flutter mẹ (xong, có test tự động `remote_commands_test.dart`): `RemoteCommands` (`lib/core/network/remote_commands.dart`). `app_lock_page` nút mở tạm và `pause_card` gửi lệnh khi chế độ "mẹ" đã chọn máy con; vẫn qua `ParentGate`. Chưa chọn máy con thì làm trên máy này như cũ. Nút "chặn lại ngay" từ xa và trạng thái tạm dừng của máy con: xem API-09.
- Xong khi: mẹ bấm mở tạm một app, con mở được rồi tự chặn lại (cần 2 máy thật, xem TASKS/TEST_PLAN.md "Bổ sung API-05").

### API-06 Yêu cầu của con (xin thêm giờ, "đã học xong") — code xong, CHƯA test máy thật
- Server (xong, đã chạy `smoke.sh`): bảng `ChildRequest` (migration `ChildRequests`; `Kind` `extra_time|study_done`, `Payload`, `Status` `pending|approved|rejected`, `CreatedAt`, `DecidedAt`). `POST /api/devices/me/requests` (con) nhận `{kind, payloadJson}`: `extra_time` chỉ có đúng trường `minutes` (số nguyên 1–240), `study_done` không có trường nào (trường thừa → 400, để không lọt nội dung/app đang dùng); payload ≤256 byte, `kind` ≤20 ký tự. Đã có yêu cầu cùng loại đang chờ (chưa quá 24 giờ) → 409 kèm `id` của nó. Dọn yêu cầu cũ hơn 7 ngày mỗi lần con gửi mới; tối đa 200 dòng/máy (429). `GET me/requests/{id}` (con, của máy khác → 404). `GET /api/devices/{id}/requests?status=` (mẹ; ≤50, mới nhất trước, `status` sai → 400, yêu cầu chờ quá 24 giờ bị ẩn). `PUT /api/requests/{id}` (mẹ) nhận `{decision: approved|rejected, minutes?}`: server đổi trạng thái và tạo lệnh trong cùng một lần lưu (`study_done` → `study_approve`/`study_reject`; `extra_time` duyệt → lệnh mới `extra_time_grant` với `minutes` 1–120, từ chối → không tạo lệnh, con xem kết quả qua GET). Quyết định hai lần → 409 (cột `Status` là concurrency token nên hai lần bấm cùng lúc chỉ một lần thắng); hết hạn 24 giờ → 409; mẹ gia đình khác hoặc máy đã hủy ghép → 404. Logic ở `Services/RequestRules.cs`, `CommandRules` thêm `extra_time_grant`.
- Kotlin con (xong, biên dịch được, chưa chạy máy thật): `FamilySync.queueRequest` xếp hàng chờ trong SharedPreferences (`pending_requests`, như hàng chờ vị trí), gửi ngay ở luồng nền và gửi bù mỗi `syncOnce`; mọi lỗi mạng/máy chủ bị nuốt, không làm hỏng lượt đồng bộ. Theo dõi kết quả bằng `tracked_requests`, khi mẹ quyết định thì con thấy thông báo ("Bố mẹ đã đồng ý/chưa đồng ý cho thêm giờ", "đã duyệt/chưa duyệt"). `extra_time_grant` → `TimeLimits.addBonus` (1–120 phút, sai thì không ack). `TimeLimitBlockActivity` "Xin thêm giờ": máy đã ghép thì hỏi 5/15/30 phút gửi cho mẹ, hoặc "Đưa máy cho bố mẹ" (cách tại chỗ cũ); máy chưa ghép giữ nguyên cách cũ. `StudyBlock.claimDone` gửi `study_done`. Khóa riêng cho hàng chờ, không dùng khóa `FamilySync` (tránh khóa chéo với `StudyBlock`).
- Flutter mẹ (xong, có test tự động): `ApiClient.getRequests/decideRequest`, màn `ChildRequestsPage` (từ màn máy con, nút "Yêu cầu của con (N chờ duyệt)"): duyệt VÀ từ chối đều qua `ParentGate.always` (sinh trắc/PIN), huỷ khóa thì không gọi server; 409 thì báo và tải lại. Báo mẹ khi có yêu cầu mới: `ChildRequestAlertChecker` chạy trong `parent_alert_worker` (cùng WorkManager 15 phút với vào/ra vùng). TODO(verify): thông báo nền trên máy mẹ thật (Android 13+ cần quyền thông báo; trễ tối thiểu 15 phút).
- Quyền riêng tư: chỉ gửi loại yêu cầu và số phút xin.
- Giới hạn đã biết: nếu phụ huynh duyệt tại chỗ trên máy con (cách cũ) thì yêu cầu gửi lên server vẫn "chờ" tới khi mẹ xử lý hoặc hết hạn 24 giờ (duyệt thêm sẽ cộng giờ lần nữa với `extra_time`; `study_approve` thì vô hại vì máy con bỏ qua khi không còn ở trạng thái chờ). Con chọn 5/15/30 phút, mẹ duyệt đúng số con xin (tối đa 120), chưa có ô sửa số phút trên giao diện (API có `minutes`).
- Xong khi: con xin thêm 30 phút, mẹ duyệt, con thấy được cộng giờ (cần 2 máy thật, xem TASKS/TEST_PLAN.md "Bổ sung API-06").

### API-07 Duyệt app mới cài — code xong, CHƯA test máy thật
- Server (xong, đã chạy `smoke.sh`): `InstalledApp` thêm `Status` (`new|allowed|blocked`, mặc định `allowed` nên dòng cũ không đổi nghĩa) và `DecidedAt` (migration `InstalledAppStatus`; nhãn giới hạn 200 ký tự). `POST /api/devices/me/apps` (con) nhận thêm cờ `isNew`: chỉ khi `true` app vào `new` (cài lại app đã gỡ cũng về `new`, xóa quyết định cũ); máy con KHÔNG thể tự đặt `allowed`/`blocked`. Kiểm từng phần tử: tên gói đúng dạng (≤200), nhãn ≤200 ký tự (bỏ ký tự điều khiển, rỗng thì dùng tên gói), `isNew` phải là bool, ≤2000 mục mỗi lần, ≤2000 app/máy (429). `GET /api/devices/{id}/apps?status=new|allowed|blocked` (mẹ; bỏ trống = tất cả, mới nhất trước, ≤200, `status` sai → 400). `PUT /api/devices/{id}/apps/{package}` (mẹ) nhận `{status: allowed|blocked}` (không đặt lại về `new`); tên gói sai dạng / `status` sai → 400; gia đình khác, máy đã hủy ghép, hoặc app máy con chưa từng báo → 404. `GET /api/devices/me/apps/decisions` (con) trả `[{packageName, status}]` của các app mẹ đã quyết (≤500). Logic ở `Services/AppRules.cs`; `CommandRules.IsPackage` dùng chung.
- Nhất quán với API-05 ("luật phiên bản mới của mẹ là nguồn sự thật"): quyết định duyệt app mới được áp bằng cơ chế sẵn có của `NewApps` (`approve` / `reject` → `verdict` chặn), KHÔNG ghi vào `policy.appLock.blocked`, `GuardPrefs.remoteBlocked` hay lệnh `app_block`/`app_allow`. Nên không lẫn với danh sách khóa mẹ đẩy bằng `PolicySync` và không cần sửa danh sách khóa của mẹ. Nếu app đó đồng thời nằm trong danh sách khóa của mẹ thì vẫn bị khóa (hai cơ chế độc lập, chặn nếu một trong hai chặn).
- Kotlin con (xong, biên dịch được, chưa chạy máy thật): `NewApps.syncWithServer`, gọi trong mỗi `syncOnce` (sau `syncRequests`) và ngay (luồng nền) khi `scan` thấy app mới. Hàng chờ = `pending` trừ `uploaded` (SharedPreferences, không mất khi offline / kill app, cũng gửi bù được app đã chờ trước khi ghép đôi); gửi theo lô ≤100, chỉ `packageName`, `label`, `isNew`. Kéo `decisions` rồi `allowed` → `NewApps.approve`, `blocked` → `NewApps.reject`; mỗi quyết định chỉ áp một lần (`applied_decisions`), nên phụ huynh sửa tay trên máy con được giữ tới khi mẹ đổi quyết định; app gỡ đi thì quên cả `uploaded` lẫn `applied_decisions` (cài lại phải gửi lại và duyệt lại). Còn app chưa gửi được thì chưa kéo quyết định (tránh áp quyết định cũ của gói cài lại). Không gửi / không chặn app trong `TimeLimits.exemptPackages`. Mọi lỗi (mạng, 4xx/5xx, dữ liệu hỏng) bị nuốt, không làm hỏng `syncOnce`; 400 thì bỏ để khỏi kẹt hàng chờ.
- Flutter mẹ (xong, có test tự động `remote_new_apps_test.dart`, `new_app_alerts_test.dart`): `NewAppsPage` tự chuyển sang `RemoteNewAppsView` khi ở chế độ "mẹ" đã chọn máy con (hoặc truyền `remoteDevice`; không thì làm trên máy này như cũ): danh sách "Đang chờ duyệt" (Chặn / Cho phép) và "Đã chặn" (Cho phép). CẢ HAI hành động qua `ParentGate.always` (sinh trắc/PIN), huỷ khóa thì không gọi server; lỗi server báo lên và tải lại. Nút "App mới cài (N chờ duyệt)" ở màn máy con. Báo mẹ khi có app mới: `NewAppAlertChecker` (mốc theo id app mỗi máy) chạy trong `parent_alert_worker`, cùng WorkManager 15 phút. TODO(verify): thông báo nền trên máy mẹ thật (Android 13+ cần quyền thông báo; trễ tối thiểu 15 phút).
- Quyền riêng tư: chỉ gửi tên app + tên gói (và cờ `isNew`), không nội dung, không app đang dùng.
- Giới hạn đã biết: (1) duyệt tại chỗ trên máy con (cách cũ) không báo lên server nên mẹ vẫn thấy app đó "chờ duyệt" cho tới khi mẹ quyết; mẹ quyết sau thì máy con áp quyết định của mẹ (mẹ quyết định cuối). (2) App chưa duyệt rồi bị gỡ vẫn nằm ở danh sách chờ của mẹ (server không biết đã gỡ); mẹ bấm Cho phép / Chặn là hết. (3) Cài lại một app mẹ đã quyết, nếu lượt `isNew` bị gửi lặp sau khi mẹ vừa quyết thì quyết định đó bị đặt lại về "chờ" (hiếm; mẹ quyết lại). (4) Trễ tối đa vài phút (lượt đồng bộ 5 phút). (5) Chỉ app có biểu tượng mở được (`NewApps.launchable`) mới được báo.
- Xong khi: cài app mới trên máy con, máy mẹ thấy trong ≤5 phút và chặn được (cần 2 máy thật, xem TASKS/TEST_PLAN.md "Bổ sung API-07").

### API-08 Báo cáo sử dụng — code xong, CHƯA test máy thật
- Server (xong, đã chạy `smoke.sh`): bảng `UsageDay` (`DeviceId`, `Date`, `TotalMinutes`, `Blocks`) và `UsageApp` (`UsageDayId`, `Package`, `Minutes`), migration `UsageReport`. Khóa duy nhất (`DeviceId`, `Date`) nên gửi lại cùng ngày là ghi đè (xóa app cũ, ghi app mới), không trùng; `UsageApp` xóa theo ngày (cascade). `POST /api/devices/me/usage` (con) nhận `{days:[{date:"yyyy-MM-dd", totalMinutes, blocks, apps:{package:minutes}}]}`: ≤31 ngày/lô, ≤200 app/ngày, phút 0–1440 (tổng và từng app), `blocks` 0–10000, tên gói đúng dạng (≤200), ngày đúng định dạng, không trùng trong lô, không quá 1 ngày ở tương lai (dư cho múi giờ), không cũ hơn 90 ngày; sai kiểu (chuỗi thay số...) → 400; trường thừa bị bỏ qua, không lưu. Lô lỗi thì không ghi gì. Mỗi lần gửi dọn ngày cũ hơn 90 ngày của máy đó. `GET /api/devices/{id}/usage?from=&to=` (mẹ, mặc định 7 ngày gần nhất theo ngày UTC, tối đa 90 ngày, cũ nhất trước; `from`/`to` sai định dạng, `from` > `to`, hoặc quá 90 ngày → 400); gia đình khác hoặc máy đã hủy ghép → 404. Logic ở `Services/UsageRules.cs`.
- Kotlin con (xong, biên dịch được, chưa chạy máy thật): `UsageReport.syncWithServer`, gọi trong mỗi `FamilySync.syncOnce` (sau `NewApps.syncWithServer`). Lấy 30 ngày từ kho chụp có sẵn (`report(context, 30)`), bỏ app trong `TimeLimits.exemptPackages`, tên gói sai dạng; mỗi ngày có "chữ ký" (tổng|blocks|app=phút) nên ngày đã chốt gửi đúng một lần, hôm nay gửi lại mỗi khi số liệu đổi. Ngày hoàn toàn trống (0 phút, 0 lần chặn) không gửi (mẹ thấy 0 cho ngày thiếu). Mọi lỗi (mạng, 4xx/5xx) bị nuốt, không làm hỏng `syncOnce`; 400 thì bỏ ngày đó để khỏi kẹt; 401/409/429/5xx giữ lại thử lần sau. Đổi token (ghép lại) thì quên các ngày đã gửi (`forgetSent`). Chưa cấp quyền "Truy cập dữ liệu sử dụng" thì không gửi gì.
- Flutter mẹ (xong, có test tự động `remote_report_test.dart`): `ApiClient.getDeviceUsage`; `ReportPage` tự chuyển sang `RemoteReportView` khi ở chế độ "mẹ" đã chọn máy con (hoặc truyền `remoteDevice`; không thì làm trên máy này như cũ, `_LocalReport` không đổi). Màn hiện hôm nay, biểu đồ 7 ngày (chạm cột xem ngày, chạm app lọc), top 5 app, tổng tuần, số lần con chạm app bị chặn; gia đình có nhiều máy thì có ô chọn máy con. Tên app lấy từ danh sách app máy con đã báo (API-07), không có thì hiện tên gói. Không có hạn mức hôm nay (hạn mức nằm ở luật, chưa kéo về).
- Quyền riêng tư: chỉ phút theo app theo ngày + số lần chạm app bị chặn; không nội dung, không vị trí, không thời điểm trong ngày.
- Giới hạn đã biết: (1) trễ tối đa vài phút (lượt đồng bộ 5 phút). (2) Ngày tính theo lịch máy con; mẹ hỏi 7 ngày theo lịch máy mẹ nên khác múi giờ có thể lệch 1 ngày ở mép (TODO(verify)). (3) Máy con lâu ngày không đồng bộ chỉ còn 30 ngày trong kho. (4) Dữ liệu trước khi ghép đôi nằm trong kho chụp sẽ được gửi lên lần đầu (cùng loại số liệu, chỉ phút theo app). (5) Hôm nay phút theo app chỉ tính app ≥1 phút (như báo cáo trên máy con).
- Xong khi: mẹ xem được biểu đồ tuần của máy con (cần 2 máy thật, xem TASKS/TEST_PLAN.md "Bổ sung API-08").

### API-09 Trạng thái máy con và lịch sử lệnh — code xong, CHƯA test máy thật
- Server (xong, đã chạy `smoke.sh`): bảng `DeviceStatus` (migration `DeviceStatus`, mỗi máy một dòng ghi đè). `PUT /api/devices/me/status` (con) nhận đúng: `batteryPercent` 0–100 (tùy chọn), `policyVersion` ≥0, `isPaused`, `studyActive`, `permissionsMissing[]` (≤20 mã dạng `[a-z][a-z0-9_]*` ≤40 ký tự), `appVersion` (≤32, `[0-9A-Za-z.+_-]`), `tempUnlocked[{package, until}]` (≤50, tên gói đúng dạng, `until` bắt buộc và không xa quá 245 phút). Sai kiểu/giới hạn → 400. `GET /api/devices/{id}/status` (mẹ) thêm `lastSeenAt` từ `Device`, `reportedAt` (null = chưa từng báo) và lọc bỏ app mở tạm đã quá hạn. Logic kiểm tra ở `Services/StatusRules.cs`.
- Kotlin con (xong, biên dịch được, chưa chạy máy thật): `FamilySync.pushStatus` gọi trong mỗi `syncOnce` sau khi kéo luật; mọi lỗi (mạng, 4xx/5xx) bị nuốt, không ảnh hưởng các bước khác. Nguồn: `TimeLimits.pauseMinutesLeft/studyActive`, `BatteryManager` (dự phòng intent pin), `PermissionStatus.missing`, `TempRelocks.pendingUntil`, `versionName`. `PermissionStatus.kt` là bản dùng được từ dịch vụ nền của các kiểm tra quyền trước đây nằm trong `MainActivity` (MainActivity giờ gọi lại nó, không nhân đôi). Quyền micro không bao giờ báo mẹ là "thiếu" (chỉ phục vụ báo thức giọng nói). Chỉ gửi các trường trên: không có app đang dùng, vị trí hay nội dung. TODO(verify): `getIntProperty(BATTERY_PROPERTY_CAPACITY)` trên Xiaomi T11 Pro; `isIgnoringBatteryOptimizations` & kiểm tra Trợ năng từ service nền.
- Flutter mẹ (xong, có test tự động): `ApiClient.getDeviceStatus/getCommands`, `child_status_text.dart`. (1) `remote_monitor_page`: mục "Trạng thái máy con" (lần cuối, tạm dừng, giờ học, pin, quyền thiếu; máy con chưa báo thì nói rõ, lỗi tải trạng thái không làm mất vị trí/hàng rào). (2) `pause_card`: biết `isPaused` thì đổi sang "Tiếp tục dùng máy con" và chạm là gửi `unpause` (qua `ParentGate`), không paused chỉ hỏi thời lượng; chưa biết thì giữ hộp chọn đủ cả hai; sau khi gửi hiện "chờ máy con xác nhận" tới khi máy con báo lại; tự hỏi lại mỗi 60 giây. (3) `sent_commands_page`: "Lệnh đã gửi". (4) `app_lock_page`: app đang mở tạm trên máy con có nút "Chặn lại ngay" gửi `app_relock` (qua `ParentGate`); không biết trạng thái thì không hiện nút.
- Giới hạn đã biết: trạng thái chỉ mới bằng lượt đồng bộ 5 phút của máy con, nên "chặn lại ngay" và `isPaused` trễ tối đa vài phút; `isPaused` chỉ là có/không (không có số phút còn lại, theo quy định chỉ gửi các trường đã chốt).
- Xong khi: màn máy con hiện đúng "đang tạm dừng", "pin 40%", "lần cuối 2 phút trước" (cần 2 máy thật, xem TASKS/TEST_PLAN.md "Bổ sung API-09").

### API-10 Cảnh báo cho mẹ (tamper và mất kết nối) — code xong, CHƯA test máy thật
- Server (xong, đã chạy `smoke.sh`): bảng `Alert` (`DeviceId`, `Kind`, `Detail`, `CreatedAt`, `ReadAt`; migration `Alerts`). Loại: `time_changed`, `app_uninstall_attempt`, `accessibility_off`, `device_admin_off`, `permission_missing`, `offline`. `POST /api/devices/me/alerts` (con) nhận `{kind, detail?, occurredAt?}`: `kind` ≤30 ký tự và phải thuộc danh sách (con KHÔNG được tự gửi `offline`, do server tạo); `detail` ≤32 ký tự và chỉ là mã/số ngắn (`^-?[a-z0-9_]{1,31}$`, nên không lọt chữ có dấu, khoảng trắng, tên gói hay văn bản); `occurredAt` không ở tương lai quá 5 phút, không cũ quá 7 ngày (để con gửi bù lúc offline vẫn giữ giờ xảy ra thật); sai kiểu → 400. Chống trùng: cùng `Kind` trong ±10 phút quanh thời điểm xảy ra → 409 kèm `id` (máy con coi như đã gửi). Tối đa 200 dòng/máy: vượt thì XÓA dòng cũ nhất (không từ chối, để cảnh báo tamper mới không bao giờ bị bỏ vì mẹ chưa đọc); dòng quá 30 ngày bị dọn mỗi lần con gửi. `GET /api/devices/{id}/alerts?afterId=` (mẹ): cũ trước, ≤100 (không có `afterId` thì 100 cảnh báo MỚI nhất; có thì 100 kế sau mốc), `afterId` sai kiểu → 400; gia đình khác hoặc máy đã hủy ghép → 404. `POST /api/alerts/{id}/read` (mẹ): đặt `ReadAt` (gọi lại giữ giờ đầu), gia đình khác / không có → 404. Logic ở `Services/AlertRules.cs`.
- Mất kết nối: `OfflineAlertService` (hosted service) chạy mỗi `Alerts:CheckIntervalSeconds` (mặc định 900 giây), tạo MỘT cảnh báo `offline` (Detail = số giờ) cho máy chưa hủy ghép có `LastSeenAt` (hoặc `PairedAt` nếu chưa từng kết nối) cũ hơn `Alerts:OfflineHours` (mặc định 24). Chỉ tạo lại khi máy đã kết nối lại rồi mất lần nữa (không có cảnh báo `offline` nào sau lần thấy cuối), nên không tạo trùng liên tục. Đã kiểm bằng SQL (đổi `LastSeenAt`) với `Alerts__CheckIntervalSeconds=3`: 25 giờ → đúng 1 cảnh báo, các lượt sau không thêm, online lại rồi im lặng tiếp → cảnh báo thứ 2, máy hủy ghép không có cảnh báo. TODO(verify): trên MyASP.net, IIS có thể dừng tiến trình khi không có truy cập (khi đó tác vụ nền không chạy); máy mẹ polling 15 phút giữ tiến trình sống phần nào. Ngưỡng mẹ tự chỉnh trong cài đặt gia đình CHƯA làm (hiện chỉ cấu hình server).
- Kotlin con (xong, biên dịch được, chưa chạy máy thật): `TamperAlerts.kt`. Hàng chờ SharedPreferences (`safefamily_alerts`, ≤30 mục, bỏ mục quá ~7 ngày), lưu bằng `commit()` để không mất khi bị kill ngay; gửi ngay ở luồng nền, gửi bù mỗi `FamilySync.syncOnce`; 200/409/400/404 → bỏ khỏi hàng, 401/429/5xx/mất mạng → giữ; mọi lỗi bị nuốt, không làm hỏng `syncOnce`. Nguồn sự kiện: `TimeChangeReceiver` (nhật ký lệch giờ của `TimeLimits` có lần mới → `time_changed`, Detail = số phút lệch có dấu, có `goAsync`); `UninstallGate.begin` → `app_uninstall_attempt` (`authorized`, sau khi qua PIN + sinh trắc, vì gỡ xong thì không còn app để báo); `SettingsGuardService.challenge` (có người mở màn Cài đặt của SafeFamily khi chưa qua khóa) → `app_uninstall_attempt` (`guard`); `SettingsGuardService.onUnbind` → chờ 15 giây rồi kiểm lại, dịch vụ còn tắt thì `accessibility_off` (tránh báo nhầm khi cập nhật app); `SafeFamilyAdminReceiver.onDisabled` → `device_admin_off` (bỏ qua khi cửa gỡ app hợp lệ đang mở). Phát hiện bù ở mỗi lượt đồng bộ: so `PermissionStatus.missing` với mốc, quyền MỚI thiếu → `accessibility_off` (Trợ năng / dịch vụ chặn), `device_admin_off`, hoặc `permission_missing` (Detail = id quyền); chỉ báo khi mất đi (cạnh xuống), mất lần nữa sau khi cấp lại mới báo lại. Mốc quyền và giờ lấy lúc ghép đôi (`FamilySync.configure` khi đổi token) nên quyền chưa cấp xong lúc cài đặt không báo; máy nâng cấp từ bản cũ chưa có mốc thì lần đồng bộ đầu chỉ ghi mốc. Trùng loại trong 10 phút thì bỏ (khớp server). Quyền micro không bao giờ báo (như API-09). TODO(verify): tắt Trợ năng trên Xiaomi T11 Pro có gọi `onUnbind` không; dịch vụ Trợ năng của `app_blocker` (plugin) không hook được nên chỉ bắt qua lượt đồng bộ ≤5 phút.
- Flutter mẹ (xong, có test tự động `tamper_alerts_test.dart`, `device_alerts_page_test.dart`): `ApiClient.getAlerts/markAlertRead`, `alertLabel` (`child_status_text.dart`); `TamperAlertChecker` (`lib/core/alerts/tamper_alerts.dart`) chạy trong `parent_alert_worker` cùng WorkManager 15 phút, mốc theo id cảnh báo mỗi máy, cảnh báo đã đọc không báo lại (mốc vẫn đi qua), tối đa 5 thông báo/máy/lượt; màn `DeviceAlertsPage` ("Cảnh báo (N chưa đọc)" ở màn máy con): mới nhất trước, chạm để đánh dấu đã đọc, "Đã đọc hết". Đánh dấu đã đọc KHÔNG qua khóa phụ huynh vì chỉ đổi cờ đọc (cảnh báo vẫn nằm trong danh sách), không mở/tắt/duyệt gì; nếu muốn chặt hơn thì bọc bằng `ParentGate.always` ở `_markRead`. TODO(verify): thông báo nền trên máy mẹ thật (Android 13+ cần quyền thông báo; trễ tối thiểu 15 phút).
- Quyền riêng tư: chỉ loại sự kiện, mã/số ngắn (phút lệch giờ, id quyền, số giờ mất kết nối, `authorized`/`guard`) và thời điểm; không nội dung, không vị trí, không tên app.
- Giới hạn đã biết: (1) `app_uninstall_attempt` `guard` báo cả khi chỉ mở màn thông tin app SafeFamily (không chắc là gỡ); mẹ thấy chữ "mở màn cài đặt của SafeFamily khi chưa qua khóa phụ huynh". (2) `time_changed` còn báo cả lần máy tự đồng bộ giờ mạng lệch hơn 2 phút (ngưỡng của `TimeLimits`). (3) Mất quyền không có sự kiện trực tiếp thì chỉ phát hiện ở lượt đồng bộ (≤5 phút). (4) Máy tắt hẳn/hết pin/không mạng không tự báo được: mẹ chỉ biết qua cảnh báo `offline` sau 24 giờ. (5) Cài lại app hoặc xóa dữ liệu app thì hàng chờ chưa gửi mất.
- Xong khi: tắt trợ năng trên máy con, mẹ nhận thông báo (cần 2 máy thật, xem TASKS/TEST_PLAN.md "Bổ sung API-10").

### API-11 Quyền riêng tư vị trí — code xong, server + Flutter đã test tự động, Kotlin CHƯA test máy thật
- Đã chốt (2026-10-31): giữ vị trí **7 ngày** (`LocationRules.Retention`); con **không** xem lịch sử vị trí của chính mình (không làm endpoint/màn cho con).
- API: `GET/PUT /api/devices/{id}/location-sharing` (mẹ; `{"enabled":bool}` bắt buộc), `DELETE /api/devices/{id}/locations` (xóa lịch sử, 204), `GET /api/devices/me/settings` (con kéo cờ `locationSharing`). Cờ `Device.LocationSharing` mặc định bật (migration `LocationSharing`).
- Khi tắt: `POST devices/me/locations` → 403, không lưu; `GET .../location` và `.../locations` của mẹ → 403 `{"error","locationSharing":false}`. Lịch sử cũ giữ nguyên cho tới khi mẹ xóa hoặc quá 7 ngày.
- Máy con (Kotlin): kéo cờ trong `syncOnce`; tắt thì `FamilyService` gỡ cập nhật vị trí, `addLocation` bỏ điểm, `pending_locations` bị xóa, thông báo thường trực đổi chữ; bật lại thì thu thập tiếp. Hàng rào địa lý không đổi theo cờ (TODO(verify) trong `FamilySync.pullSettings`).
- Mẹ (Flutter): công tắc "Chia sẻ vị trí" và nút "Xóa lịch sử vị trí" ở `remote_monitor_page`, cả hai qua `ParentGate.always`, xóa có hộp xác nhận; khi tắt hiện "Đang tắt chia sẻ vị trí".
- Quyền riêng tư: chỉ đổi cờ và xóa, không thêm dữ liệu nào mới lên server.
- Xong khi: tắt chia sẻ thì con dừng gửi vị trí, mẹ xóa được lịch sử (cần 2 máy thật, xem TASKS/TEST_PLAN.md "Bổ sung API-11").

### API-12 Thông báo nhanh hơn (tùy chọn)
- Hiện trễ tối thiểu 15 phút ở máy mẹ. Phương án: SignalR (cần app mở) hoặc FCM (đã chốt không dùng). Chỉ làm khi người dùng chấp nhận đổi quyết định.

### API-13 Đồng bộ liên hệ khẩn cấp — code xong, server + Flutter đã test tự động, CHƯA test 2 máy thật
- Đã chốt (2026-10-31, người dùng trả lời): (1) ĐƯỢC gửi nhãn + số SOS lên server; (2) tối đa **3** số SOS; (3) màn chặn của con **gọi thẳng**, không hỏi xác nhận (quyền `CALL_PHONE`).
- Schema `policy` nâng lên `schemaVersion` **2**: thêm `contacts: [{"label","phone","sos":true}]`. CHỈ các liên hệ mẹ đánh dấu khẩn cấp và có số; không id, không thứ tự, không phải cả danh bạ. Nhãn cắt còn 30 ký tự khi gửi. Máy con bản cũ (chỉ hiểu schema 1) gặp schema 2 thì giữ luật cũ (đúng cơ chế API-04), nên cần cập nhật app con cùng lúc.
- Server: không endpoint mới, không migration. `PUT /api/devices/{id}/policy` kiểm `contacts` bằng `Services/PolicyRules.cs`: phải là mảng ≤3 mục, mỗi mục là đối tượng có `label` (chuỗi 1–30 ký tự, không ký tự điều khiển), `phone` (chuỗi `+?` + 9–12 chữ số), `sos` (nếu có phải là true/false); sai → 400 và phiên bản luật không đổi. Gia đình khác → 404, token máy con → 403 (như cũ). Mô tả 400 nằm trong tóm tắt Swagger của endpoint.
- Flutter mẹ: `PolicySchema.build(sosContacts:)`; `PolicySync` có tham số `loadContacts` (app đọc danh bạ trên máy mẹ) và gửi kèm khi lưu. Màn "Cá nhân": mục "Đặt làm liên hệ khẩn cấp" giờ cho chọn nhiều người (tối đa 3, `ProfileController.toggleEmergency`; đủ 3 thì báo, liên hệ chưa có số thì không đặt được); đổi/sửa/xóa liên hệ SOS thì `PolicySyncScope.notifyChanged` đẩy lại luật. Việc này vẫn qua `ParentGate.childAction` có sẵn.
- Kotlin con (xong, chưa chạy thật): `FamilySync.parsePolicy` hiểu schema ≤2, kiểm `contacts` HẾT (≤3, nhãn 1–30, số 9–12 chữ số) rồi mới ghi `GuardPrefs.setSos`; gói không có `contacts` thì giữ SOS cũ, `contacts: []` thì xóa SOS. `TimeLimitBlockActivity`: mỗi số SOS một nút "SOS: gọi <nhãn>" gọi thẳng bằng `ACTION_CALL`; chưa có quyền `CALL_PHONE` thì xin lúc bấm, bị từ chối thì mở bàn phím với đúng số đó. Chưa có số mẹ chọn thì giữ hành vi cũ (bàn phím gọi / danh bạ trên máy con). Thêm `CALL_PHONE` vào manifest.
- TODO(verify): (a) hộp xin quyền `CALL_PHONE` hiện được trên màn chặn (Xiaomi có thể chặn gọi từ app nền / cần quyền "Hiển thị cửa sổ pop-up khi chạy nền"); (b) `ACTION_CALL` từ Activity đang đè lên app bị chặn có gọi được trên Xiaomi T11 Pro; (c) máy con không có SIM thì `ACTION_CALL` báo lỗi, đã fallback `dial`; (d) nhãn quá 30 ký tự bị cắt âm thầm khi gửi.
- Xong khi: mẹ đặt số SOS, màn chặn của con gọi đúng số (cần 2 máy thật, xem TASKS/TEST_PLAN.md "Bổ sung API-13").

### API-14 Nền tảng và vận hành server
- `GET /health` cho MyASP.net.
- HTTPS bắt buộc, CORS, rà soát JWT và băm mật khẩu.
- Ghi log lỗi phía server (Serilog ra file), trả lỗi dạng `ProblemDetails` thống nhất.
- Giới hạn tần suất cho các endpoint con (polling), giới hạn kích thước body.
- Tác vụ dọn dữ liệu định kỳ (vị trí, báo cáo, lệnh cũ, mã ghép hết hạn).
- Versioning: tiền tố `/api/v1` hoặc header `X-App-Version`, để bản app cũ không làm hỏng server mới.
- Publish MyASP.net, chạy `smoke.sh` trên máy chủ thật.

### API-15 Kiểm thử — test tự động API xong và đạt; test máy thật (TEST_PLAN) CHƯA chạy
- Test tích hợp `SafeFamily.Api.Tests` (xUnit + `WebApplicationFactory<Program>`, 174 ca, chạy `dotnet test` trong thư mục `SafeFamily.Api.Tests`): mỗi lần chạy tạo một CSDL LocalDB tạm bằng `Migrate()` (kiểm luôn migration) và xóa khi xong; không đụng CSDL dev. Cần LocalDB (`sqllocaldb i` thấy `MSSQLLocalDB`).
- Phân quyền chéo gia đình: mẹ B gọi 21 đường dẫn phía mẹ trên máy con của mẹ A (đổi tên, policy, apps + quyết định app, commands, status, requests, usage, alerts, location-sharing, locations, location, geofences, geofence-events, `PUT /api/requests/{id}`, `POST /api/alerts/{id}/read`) đều 404 và dữ liệu không đổi; mẹ A gọi cùng đường dẫn thì thành công (đối chứng). Thêm: hủy ghép chéo gia đình 404, hàng rào / sự kiện của máy khác không bị ghi đè, token ký đúng khóa nhưng sai gia đình vẫn 404.
- 409: lệch phiên bản policy và hàng rào, duyệt một yêu cầu hai lần, yêu cầu / cảnh báo trùng (kèm `id` đã có), yêu cầu quá 24 giờ.
- Mã ghép: dùng lại 400, hết hạn 400, sai dạng 400, claim bị giới hạn tần suất 429, mã của mẹ khác không bị xóa khi mẹ B tạo mã.
- Token: refresh đã đổi 401, refresh hết hạn 401, hủy ghép thì mọi endpoint phía con 401, token giả / hết hạn / sai khóa / sai audience / sai issuer 401, sai vai trò 403, không token 401.
- Kiểm kiểu / độ dài / số lượng từng nhóm: policy (kích thước tính bằng byte, đúng 64 KiB), commands (mọi loại lệnh, biên phút), requests (kèm trần 200 dòng → 429), apps (mép 2000 app → 429), usage, status, alerts, locations, geofences, geofence-events, location-sharing, đổi tên máy, đăng ký / đăng nhập; mỗi nhóm có ca ở đúng mép giới hạn phải thành công.
- Swagger: so khớp từng action của controller với `swagger.json`, thiếu action nào là test đỏ.
- `smoke.sh` có thêm khối "API-15" (thế giới mới: 21 đường dẫn × mẹ khác 404 / chủ 2xx / token con 403 / không token 401, mã ghép dùng lại, refresh đã đổi, token giả, hủy ghép), in số đường dẫn Swagger. Nên chạy API với `RateLimit__AuthPerMinute` và `RateLimit__ClaimPer10Min` lớn (cấu hình mới; mặc định giữ 10 và 5).
- Sửa server khi viết test: `POST devices/me/locations` không còn lưu điểm quá hạn giữ 7 ngày (trước đây lưu rồi mới bị xóa ở lượt gửi sau).
- Ghi nhận chưa sửa (TODO(verify), chờ quyết định): (1) MVC ép chuỗi số thành số (`"minutes":"5"` được nhận như 5) ở các trường số của DTO; (2) `readAt` của `POST alerts/{id}/read` lần đầu có hậu tố `Z`, lần sau không (cùng thời điểm); (3) giới hạn tên máy 50 ký tự tính trên chuỗi thô, trước khi cắt khoảng trắng.
- Chưa làm trong task này: test máy thật theo `TASKS/TEST_PLAN.md` (mục "Bổ sung API-15"); test Kotlin tự động.

---

## 4. Thứ tự đề xuất

1. **API-04** (policy + đẩy từ Flutter): chạm đúng cốt lõi, mở khóa app lock và giới hạn giờ.
2. **API-05** (lệnh mở rộng) và **API-09** (trạng thái): vài endpoint nhỏ, lợi lớn cho UI mẹ.
3. **API-06** (yêu cầu của con), **API-07** (duyệt app mới).
4. **API-08** (báo cáo), **API-10** (cảnh báo) — code xong, chờ test máy thật.
5. **API-03**, **API-01**, **API-11**, **API-13**.
6. **API-14**, **API-15** làm xen kẽ; bắt buộc xong trước khi phát hành.
7. **API-02**, **API-12**: chỉ làm khi người dùng chốt quyết định.

## 5. Câu hỏi cần chốt

1. Có thêm tài khoản bố ngang quyền mẹ không (API-02)?
2. Báo cáo sử dụng giữ bao nhiêu ngày (đề xuất 90)? (Vị trí: đã chốt 7 ngày, 2026-10-31.)
3. Chấp nhận trễ 15 phút cho thông báo ở máy mẹ, hay đổi quyết định không dùng FCM (API-12)?
4. ~~Có gửi liên hệ khẩn cấp lên server không (API-13)?~~ Đã chốt 2026-10-31: có, tối đa 3 số, gọi thẳng.
5. MyASP.net có SMTP để làm quên mật khẩu không (API-03)? — Đã trả lời "có", hạn mã 30 phút; còn thiếu host, port, tài khoản gửi, địa chỉ From thật (xem `API_TIEN_TRINH.md`, mục Cấu hình).
