# SafeFamily v0.6.0 — Tổng hợp tính năng và cách test

Gom từ `README.md`, `task.md`, `docs/DEVELOPER.md`, `docs/API_TIEN_TRINH.md` và code (`lib/app/app_shell.dart`, `parent_home_page.dart`, `child_home_page.dart`, `remote_monitor_page.dart`). Tên ô/nút ghi đúng như trên màn hình app.

---

## 1. Tính năng

### 1.1 Hai vai trò
Cài đặt xong, app hỏi **Máy này dùng để làm gì?** → **Máy mẹ** hoặc **Máy con**. Hai máy nối nhau qua server `SafeFamily.Api`; máy con hỏi server mỗi **5 phút** (không FCM).

### 1.2 Máy mẹ (2 tab: **Con** và **Tài khoản**)

| # | Tính năng | Ở đâu |
|---|---|---|
| M1 | Đăng ký / đăng nhập (email + mật khẩu), quên/đổi mật khẩu | Màn đăng nhập, **Tài khoản** |
| M2 | Tạo **mã ghép đôi 6 số** (hạn 10 phút), đổi tên / hủy ghép máy con | Tab **Con** → 👪 **Kết nối gia đình** |
| M3 | **Chặn ứng dụng** từ xa, **Chặn nhanh YouTube**, mở tạm 15 phút, chặn lại ngay | **Chặn ứng dụng** |
| M4 | **Giới hạn thời gian**: số phút/ngày (tổng + từng app), giờ ngủ/giờ học, tạm dừng ngay | **Giới hạn thời gian** |
| M5 | **Yêu cầu của con**: duyệt/từ chối xin thêm giờ, "đã học xong" | **Yêu cầu của con** |
| M6 | **Duyệt app mới cài** | **Duyệt app mới cài** |
| M7 | **Vị trí** gần nhất, **hàng rào địa lý** (thêm/xóa), sự kiện vào/ra, công tắc **Chia sẻ vị trí**, **Xóa lịch sử vị trí** | Chọn máy con → **Xem máy …** |
| M8 | **Điều khiển máy con**: Khóa 60 phút / Mở khóa, Giờ học 30 phút / Dừng giờ học, Tắt/Bật lại giới hạn hôm nay | Cùng màn máy con |
| M9 | **Hoạt động của con** (con mở app bị chặn, sai PIN, mở khóa phụ huynh; nhóm theo ngày, giữ 30 ngày) | **Hoạt động của con** |
| M10 | **Cảnh báo** (mất kết nối, chỉnh giờ, gỡ app, tắt quyền) | Thẻ cảnh báo / thông báo |
| M11 | **Báo cáo thời gian dùng** (hôm nay, 7 ngày, app dùng nhiều nhất) | Tab **Con** |
| M12 | **Danh bạ của con**: tối đa 20 liên hệ, tối đa 3 SOS | Tab **Tài khoản** → **Danh bạ của con** |
| M13 | **Người giám hộ thứ 2** (bố, tối đa 2 người) | **Tài khoản** |
| M14 | **Bảo mật & khóa phụ huynh**: PIN, vân tay, thời gian chờ 1/5/15 phút, mã khôi phục; **Nhật ký mở khóa**; **Bảo vệ máy**; đăng xuất; xóa tài khoản | **Tài khoản** |

Máy mẹ chỉ cần quyền **Thông báo**.

### 1.3 Máy con (một màn đơn giản)

| # | Tính năng |
|---|---|
| C1 | Hiện app đang bị chặn / đang mở tạm (còn bao lâu) |
| C2 | **Đồng bộ lần cuối: …** ; mất mạng lâu → "Chưa kết nối được máy mẹ"; nút **Đồng bộ với máy mẹ** |
| C3 | **Xin thêm giờ** (15/30 phút) và **Con học xong rồi** → trạng thái *Đã gửi, chờ mẹ duyệt* / *Mẹ đã duyệt* / *Mẹ từ chối* |
| C4 | **Gọi người nhà**: nút to từng liên hệ, **SOS** luôn trên cùng, bấm mở màn quay số |
| C5 | Khối **Mẹ xem được gì?** (vị trí, thời gian dùng, app đã cài; không xem tin nhắn/trình duyệt) |
| C6 | Màn chặn: mở app bị chặn → *"Con làm xong bài tập chưa?"*; hết giờ dùng máy → có nút xin thêm giờ + gọi SOS |
| C7 | Nút **Dành cho phụ huynh** (hỏi vân tay/PIN) → **Mở ứng dụng đầy đủ** hoặc **Ngắt kết nối với máy mẹ** |
| C8 | Gửi vị trí, danh sách app đã cài, nhật ký hoạt động, thống kê dùng lên server |

### 1.4 Khóa phụ huynh (cả hai máy)
PIN 4–6 số + vân tay (`biometric_storage`); **không có công tắc "chế độ trẻ em"**, thao tác phụ huynh luôn hỏi; sau khi xác thực có "phiên" ngắn; sai PIN 5 lần khóa 30 giây (tăng dần); có nhật ký mở khóa; mã khôi phục PIN.

### 1.5 Bảo vệ máy con
Trợ năng (chặn app), dịch vụ chặn màn Cài đặt, quản trị thiết bị (chống gỡ), báo thức, tắt tối ưu pin. Con tắt quyền/gỡ app → mẹ nhận cảnh báo.

### 1.6 Giới hạn đã biết (đừng tính là lỗi)
Chặn mềm (con có thể tắt quyền, mẹ sẽ nhận cảnh báo); khuôn mặt thường không dùng được (chỉ vân tay "mạnh"); thêm/xóa vân tay → phải bật lại vân tay; mở tạm không qua nửa đêm; đồng bộ trễ tới 5 phút; Kotlin phía máy con **chưa kiểm trên 2 máy thật**.

---

## 2. Chuẩn bị chung

1. **Server**: chạy `SafeFamily.Api` (SQL Server/LocalDB):
   ```bash
   cd SafeFamily.Api
   dotnet ef database update
   dotnet run
   ```
   Swagger: `http://localhost:5025/swagger`. Test nhanh API: `bash SafeFamily.Api/smoke.sh http://localhost:5025`.
2. **Địa chỉ server trong app**: mặc định `https://shamixd-001-site1.ftempurl.com` (MyASP, chưa publish chắc chắn). Muốn dùng server máy tính thì sửa ở màn đăng nhập/kết nối: máy ảo `http://10.0.2.2:5025`, máy thật `http://<IP máy tính trong Wi-Fi>:5025` (máy tính và điện thoại cùng mạng, mở tường lửa cổng 5025).
3. **Cài app**: APK v0.6.0 hoặc `flutter run` (Flutter 3.47). Test tự động: `flutter analyze` và `flutter test`; test API trong `SafeFamily.Api.Tests`.
4. **Máy con** cần bật tay: Trợ năng *SafeFamily - Khóa ứng dụng* (và *Bảo vệ cài đặt*), Báo thức & lời nhắc, tắt tối ưu pin, quyền vị trí "Luôn cho phép". Android 13+ cài từ APK: Thông tin ứng dụng → ⋮ → **Cho phép cài đặt bị hạn chế**.
5. Gợi ý: đặt **mốc đồng bộ nhanh** bằng nút **Đồng bộ với máy con/mẹ** thay vì chờ 5 phút; máy mẹ làm mới bằng kéo xuống.

---

## 3. Test với 2 máy (đầy đủ nhất)

Phân vai: **máy thật = mẹ** (có vân tay), **máy ảo/máy phụ = con**.

| Bước | Máy mẹ | Máy con | Kỳ vọng |
|---|---|---|---|
| 1 | Đặt PIN, bật vân tay → **Máy mẹ** → đăng ký → cấp **Thông báo** | | Vào được tab **Con**, báo *Chưa có máy con nào* |
| 2 | Tab **Con** → 👪 **Kết nối gia đình** → **Tạo mã ghép đôi** | Đặt PIN → cấp quyền → **Máy con** → nhập mã 6 số → **Kết nối** | Mẹ thấy máy con trong *Máy con đã ghép*; con thấy màn chính |
| 3 | **Chặn ứng dụng** → **Chặn nhanh YouTube** (xác thực) | **Đồng bộ với máy mẹ** → mở YouTube | Hiện màn chặn *"Con làm xong bài tập chưa?"*; ✕/Back về màn hình chính |
| 4 | Bấm ⏱ cạnh app để mở tạm 15 phút | Mở lại YouTube | Mở được; hết hạn tự chặn lại |
| 5 | **Giới hạn thời gian** → tổng 2–3 phút | Đồng bộ, dùng quá giờ | Màn hết giờ có nút xin thêm giờ và SOS |
| 6 | | **Xin thêm giờ** (15 phút) | Con: *Đã gửi, chờ mẹ duyệt* |
| 7 | **Yêu cầu của con** → duyệt (rồi lần khác từ chối) | Đồng bộ | *Mẹ đã duyệt* / *Mẹ từ chối*; duyệt xong con dùng thêm được |
| 8 | | **Con học xong rồi** | Mẹ thấy trong **Yêu cầu của con** → duyệt |
| 9 | Chọn máy con → **Xem máy …** → **Vị trí** → **Thêm** hàng rào (**Dùng vị trí hiện tại của con**) | Máy ảo: Extended controls → Location, đổi vị trí ra ngoài/vào trong | Mục *Vào / ra gần đây* + thông báo (trễ tối thiểu 15 phút, hoặc mở app và **Làm mới**) |
| 10 | Công tắc **Chia sẻ vị trí** tắt → bật; **Xóa lịch sử vị trí** | | Tắt: con không gửi vị trí; xóa: lịch sử trống |
| 11 | **Điều khiển máy con**: Khóa 60 phút, Mở khóa, Giờ học 30 phút | Đồng bộ | Con bị khóa/mở theo lệnh |
| 12 | | Mở app bị chặn; vào **Dành cho phụ huynh** nhập sai PIN vài lần | Mẹ: thẻ **Hoạt động của con** báo số dòng mới, mở ra thấy sự kiện theo giờ |
| 13 | Cài app mới trên máy con rồi **Duyệt app mới cài** | Cài một app bất kỳ | App bị chặn tới khi mẹ cho phép; mẹ nhận thông báo |
| 14 | **Tài khoản** → **Danh bạ của con** → thêm số, đánh dấu **SOS** | Đồng bộ | Con thấy **Gọi người nhà**, SOS trên cùng; bấm → mở màn quay số |
| 15 | | Tắt Trợ năng của SafeFamily | Mẹ nhận **Cảnh báo** (sau lần đồng bộ kế) |
| 16 | **Tài khoản** → **Người giám hộ thứ 2**, **Báo cáo thời gian dùng** | | Mời được bố; báo cáo có số liệu |
| 17 | | **Dành cho phụ huynh** → xác thực → **Ngắt kết nối với máy mẹ** | Mẹ không còn thấy máy con (hoặc con quay về chọn vai trò) |

Lưu ý máy ảo: phải bật Trợ năng thủ công; vị trí là vị trí giả; máy ảo thường không có vân tay → dùng **Dùng mã PIN** hoặc đăng ký vân tay giả trong Cài đặt máy ảo.

---

## 4. Test với 1 máy (xem toàn bộ tính năng)

Mỗi cài đặt chỉ có **một** vai trò, nên 1 máy không tự thấy cả hai phía cùng lúc. Có 2 cách tùy mục đích:

### Cách A — Một điện thoại (làm con) + máy tính thay mẹ qua Swagger *(khuyên dùng: thấy được phần thi hành thật)*

1. Chạy server (mục 2). Trên **Swagger** (`/swagger`) hoặc `curl` (xem `smoke.sh`):
   - `POST /api/auth/register` (email + mật khẩu) → lấy `accessToken`, bấm **Authorize**.
   - `POST /api/pairing/code` với `{"deviceName":"Con"}` → lấy mã 6 số.
2. Điện thoại: đặt PIN → cấp quyền → **Máy con** → sửa địa chỉ server cho trỏ về máy tính → nhập mã → **Kết nối**.
3. Xem phía **con** trên điện thoại: C1–C8 (màn chính, đồng bộ lần cuối, **Mẹ xem được gì?**, **Xin thêm giờ**, **Con học xong rồi**, màn chặn, SOS).
4. **Dành cho phụ huynh** → xác thực → **Mở ứng dụng đầy đủ**: máy con cũng có tab **Trang chủ** + **Cá nhân** với **Quản lý thiết bị của con** (Chặn ứng dụng, Thiết lập khóa ứng dụng, Giới hạn thời gian, Báo cáo thời gian dùng, Duyệt app mới cài, Quyền ứng dụng), **Ứng dụng bị chặn**, **Đang cản trở**, **Bảo mật & khóa phụ huynh**, **Nhật ký mở khóa**, **Cài đặt**. Dùng để thử chặn app, giới hạn giờ, PIN/vân tay ngay trên máy.
5. Thao tác "của mẹ" qua Swagger (cần `deviceId` từ bước ghép): đặt luật (policy), `PUT /api/devices/{id}/geofences`, gửi lệnh, duyệt `requests`, đọc `GET /api/devices/{id}/activity`, `.../location`, sửa danh bạ trong luật. Danh sách endpoint: `docs/API_DAY_DU.md`.

Phần này **không** xem được giao diện máy mẹ (thẻ Yêu cầu, Hoạt động, Danh bạ của con…).

### Cách B — Một điện thoại, xem giao diện mẹ rồi đổi vai

1. **Máy mẹ**: đăng ký, vào tab **Con** / **Tài khoản**, xem hết giao diện: **Kết nối gia đình** (tạo mã), **Bảo mật & khóa phụ huynh**, **Nhật ký mở khóa**, **Người giám hộ thứ 2**, **Danh bạ của con**, **Cài đặt**. Các màn quản lý máy con sẽ trống vì chưa có máy con.
2. Muốn đổi vai: **Tài khoản** → **Đăng xuất máy mẹ** → quay về **Máy này dùng để làm gì?** → chọn **Máy con** (nhập mã tạo từ Swagger như Cách A).
3. Muốn thấy dữ liệu thật trong giao diện mẹ mà vẫn một điện thoại: chạy **bản mẹ trên máy ảo/Chrome-emulator trên máy tính** (`flutter run -d <emulator>`), điện thoại thật làm con. Đây thực chất là 2 máy nhưng không cần điện thoại thứ hai.

### Khóa phụ huynh/vân tay riêng (không cần server)
```bash
flutter run -t lib/main_demo.dart
```
Màn demo 1 trang: **Tạo token** → quét vân tay; **Dùng mã PIN**; thử sai/hủy/đổi vân tay để xem mã lỗi.

### Bảng: tính năng nào xem được ở đâu

| Tính năng | 2 máy | 1 máy – Cách A | 1 máy – Cách B |
|---|---|---|---|
| Giao diện mẹ (M1–M14) có dữ liệu thật | ✅ | ❌ (dùng Swagger) | ⚠️ chỉ khung, trống (trừ khi dùng máy ảo) |
| Chặn app / giới hạn giờ thi hành trên máy con | ✅ | ✅ | ❌ |
| Màn chính con, xin thêm giờ, SOS (C1–C8) | ✅ | ✅ | ❌ |
| Quản lý thiết bị cục bộ trên máy con | ✅ | ✅ | ❌ |
| Hàng rào, vị trí, hoạt động, cảnh báo | ✅ | ⚠️ gửi từ điện thoại, đọc bằng Swagger | ❌ |
| PIN/vân tay, nhật ký mở khóa | ✅ | ✅ | ✅ |

---

## 5. Danh sách kiểm nhanh (tick khi pass)

- [ ] Đăng ký/đăng nhập, ghép đôi bằng mã 6 số (mã hết hạn sau 10 phút → báo lỗi)
- [ ] Chặn YouTube → màn chặn; mở tạm 15 phút → hết giờ chặn lại
- [ ] Giới hạn giờ → màn hết giờ
- [ ] Xin thêm giờ / Con học xong rồi → mẹ duyệt/từ chối → con thấy kết quả
- [ ] Hàng rào: vào/ra có sự kiện; tắt Chia sẻ vị trí; xóa lịch sử
- [ ] Hoạt động: mở app bị chặn, sai PIN, mở khóa thành công đều xuất hiện
- [ ] Danh bạ + SOS hiện trên máy con, bấm mở màn quay số
- [ ] Duyệt app mới cài; Cảnh báo khi tắt Trợ năng
- [ ] Vân tay bật/tắt, dùng PIN thay vân tay, sai PIN 5 lần bị khóa, Nhật ký mở khóa đúng
- [ ] Mất mạng máy con → "Chưa kết nối được máy mẹ", app vẫn chặn theo luật cũ
- [ ] Ngắt kết nối từ máy con (qua khu phụ huynh); hủy ghép từ máy mẹ
