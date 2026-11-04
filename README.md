# SafeFamily

**SafeFamily** là ứng dụng Android giúp **phụ huynh có con dưới 13 tuổi** yên tâm khi đưa điện thoại cho con. Hai máy nối với nhau qua server `SafeFamily.Api`: **máy mẹ** quản lý **máy con** từ xa (chặn app, giới hạn giờ, xem vị trí, xem con đã làm gì), còn máy con chỉ là một màn đơn giản. Mọi thao tác của phụ huynh luôn được **khóa bằng vân tay / khuôn mặt hoặc mã PIN**.

Đồ án nhóm môn Flutter — sản phẩm chung của cả nhóm (xem [Nhóm thực hiện](#nhóm-thực-hiện)). Phiên bản thử nghiệm: **v0.6.0**.

> 📷 *Ảnh chụp màn hình: đặt vào `docs/screenshots/` và chèn tại đây.*

---

## Cách hoạt động: hai máy

| | **Máy mẹ** | **Máy con** |
|---|---|---|
| Vai trò | Quản lý máy con từ xa, không quản lý chính nó | Tự chặn theo luật mẹ đặt (kể cả khi mất mạng) |
| Cần quyền | Chỉ **Thông báo** | Trợ năng, Báo thức & lời nhắc, tắt tối ưu pin, quản trị thiết bị (xem [Bảo vệ máy con](#bảo-vệ-máy-con)) |
| Màn chính | 2 tab: **Con** và **Tài khoản** | Một màn: app đang bị chặn, còn bao lâu, **Gọi người nhà**, **Xin thêm giờ** |
| Vào phần quản lý | Luôn hỏi vân tay/PIN | Nút **Dành cho phụ huynh** (hỏi vân tay/PIN) → *Mở ứng dụng đầy đủ* hoặc *Ngắt kết nối với máy mẹ* |

Luồng: mẹ đăng ký/đăng nhập tài khoản (email + mật khẩu) → tạo **mã ghép đôi 6 số** (hạn 10 phút) → con nhập mã ở màn *Kết nối với máy mẹ* → mẹ đặt luật trên máy mình → máy con tải luật về và tự thi hành. Máy con hỏi server mỗi 5 phút (polling, không dùng FCM), nên lệnh từ xa có thể trễ vài phút; có nút **Đồng bộ với máy mẹ** để đồng bộ ngay.

## Tính năng

### Máy mẹ

| Tính năng | Mô tả |
|---|---|
| **Con** (tab chính) | Chọn máy con; thẻ *Yêu cầu của con*, *Hoạt động của con*, *Chặn ứng dụng*, *Giới hạn thời gian*, *Duyệt app mới cài*, báo cáo sử dụng; nút 👪 **Kết nối gia đình** (tạo mã ghép, đổi tên / hủy ghép máy con) |
| ⛔ **Chặn ứng dụng** từ xa | Chọn app con không được mở (có **chặn nhanh YouTube**); **mở tạm 15 phút** rồi tự chặn lại; **chặn lại ngay** |
| ⏱ **Giới hạn thời gian** | Số phút dùng máy mỗi ngày, tổng và từng app, giờ ngủ / giờ học; nút tạm dừng ngay |
| 📥 **Yêu cầu của con** | Con xin thêm giờ hoặc báo "đã học xong" → mẹ duyệt / từ chối |
| 🆕 **Duyệt app mới cài** | Con cài app mới → bị chặn tới khi mẹ cho phép |
| 📍 **Vị trí và hàng rào địa lý** | Xem vị trí gần nhất, tạo hàng rào, nhận thông báo con đến / rời; công tắc **Chia sẻ vị trí** và nút **Xóa lịch sử vị trí** (vị trí giữ 7 ngày) |
| 🕘 **Hoạt động của con** | Con mở app bị chặn, nhập sai PIN / cố vào khu phụ huynh, mở khóa phụ huynh thành công; nhóm theo ngày, giữ 30 ngày |
| 📞 **Danh bạ của con** | Mẹ thêm/sửa/xóa tối đa 20 liên hệ, đánh dấu tối đa 3 số **SOS**; ghi vào luật nên máy con thấy sau đồng bộ |
| ⚠️ **Cảnh báo** | Máy con mất kết nối lâu, chỉnh giờ máy, gỡ app, tắt Trợ năng / quản trị thiết bị, thiếu quyền |
| **Tài khoản** (tab) | Email đăng nhập, **người giám hộ thứ 2** (bố, tối đa 2 người), đổi mật khẩu / quên mật khẩu, **Bảo mật & khóa phụ huynh** (PIN, vân tay, thời gian chờ 1/5/15 phút, mã khôi phục), **Nhật ký mở khóa** của máy này, giới thiệu, đăng xuất, xóa tài khoản |

### Máy con

| Tính năng | Mô tả |
|---|---|
| Màn chính | App đang bị chặn / đang được mở tạm (còn bao lâu), **đồng bộ lần cuối** ("Chưa kết nối được máy mẹ" khi mất mạng lâu) |
| **Gọi người nhà** | Nút to cho từng liên hệ mẹ đặt; nút **SOS** luôn trên cùng |
| **Xin thêm giờ** / **Con học xong rồi** | Gửi yêu cầu; hiện *Đã gửi, chờ mẹ duyệt* / *Mẹ đã duyệt* / *Mẹ từ chối* |
| **Mẹ xem được gì?** | Khối minh bạch: mẹ xem vị trí, thời gian dùng, app đã cài; **không** xem nội dung tin nhắn hay trình duyệt |
| Màn chặn | Mở app bị chặn → *"Con làm xong bài tập chưa?"*; hết giờ dùng máy → màn chặn có nút xin thêm giờ và gọi SOS |

### Khóa phụ huynh (cả hai máy)

Thiết lập mã PIN lần đầu, bật vân tay/khuôn mặt (`biometric_storage`). **Không có công tắc "chế độ trẻ em"**: thao tác của phụ huynh luôn hỏi vân tay/PIN; sau khi xác thực có một "phiên phụ huynh" ngắn (1/5/15 phút tùy cài đặt) để khỏi hỏi từng cú chạm. Sai PIN 5 lần khóa 30 giây (tăng dần). Có nhật ký mở khóa.

### Bảo vệ máy con

Mục **Bảo vệ máy** gom trạng thái chống tắt: Trợ năng, bảo vệ màn Cài đặt, quản trị thiết bị (chống gỡ SafeFamily). Con tắt quyền / gỡ app thì mẹ nhận cảnh báo.

## Quản lý từ xa (máy mẹ ↔ máy con)

Máy mẹ đăng nhập, tạo **mã ghép đôi 6 số** (hạn 10 phút, dùng một lần); máy con nhập mã để kết nối. Server (`SafeFamily.Api/`, ASP.NET Core + SQL Server, có Swagger) chỉ chuyển luật và lệnh; máy con tự chặn bằng luật đã tải về nên mất mạng vẫn chặn. Máy con hỏi server mỗi 5 phút nên lệnh có thể trễ vài phút.

| Tính năng | Mô tả |
|---|---|
| Chặn app từ xa | Mẹ chọn app, bấm **Gửi luật cho máy con**; mở tạm 15 phút |
| Giới hạn thời gian | Tổng và từng app, mẫu theo độ tuổi, giờ học, thêm giờ, tạm dừng, **Khóa 60 phút** |
| Yêu cầu của con | Con xin phép, mẹ duyệt hoặc từ chối trên máy mẹ |
| App mới cài | App con vừa cài bị chặn cho tới khi mẹ **Cho phép** |
| Vị trí và hàng rào địa lý | Bật/tắt chia sẻ vị trí, bản đồ, thông báo con đến/rời vùng |
| Cảnh báo và báo cáo | Cảnh báo khi con tắt quyền/phá luật; báo cáo thời gian dùng theo app |
| Gia đình | Tối đa 2 người giám hộ (mẹ + bố), mã mời 8 số hạn 30 phút |

Chi tiết API: [docs/API_DAY_DU.md](docs/API_DAY_DU.md), tiến trình: [docs/API_TIEN_TRINH.md](docs/API_TIEN_TRINH.md). **Kịch bản demo:** [docs/KICH_BAN_DEMO.md](docs/KICH_BAN_DEMO.md).

> Server đang chạy trên MyASP.net: [Swagger](https://shamixd-001-site1.ftempurl.com/swagger/index.html) (là địa chỉ mặc định trong app, sửa được ở ô địa chỉ máy chủ). Server đã có test tự động; **chưa test trên 2 máy thật**.

## Đang phát triển

- **Chặn cứng** (con không tự tắt được) bằng chế độ Device Owner.
- Thông báo đẩy nhanh hơn 15 phút (cần FCM; đã chốt chưa dùng).
- Thử đủ 2 máy thật trên server MyASP.net (xem [docs/API_TIEN_TRINH.md](docs/API_TIEN_TRINH.md)).

---

## Tải APK

👉 **[⬇ Tải SafeFamily-v0.6.0.apk](https://github.com/nguyenthanhloi727-cell/SafeFamilyApp/releases/latest/download/SafeFamily-v0.6.0.apk)** (tải thẳng) · [Xem mọi bản phát hành](https://github.com/nguyenthanhloi727-cell/SafeFamilyApp/releases)

Cách cài:

1. Mở file APK trên điện thoại (Android 7.0 trở lên).
2. Máy hỏi → cho phép **cài ứng dụng từ nguồn không xác định** cho trình duyệt / trình quản lý tệp.
3. Báo **"xung đột với gói hiện có"** / *"App not installed"* → gỡ bản SafeFamily cũ rồi cài lại.

## Chạy từ mã nguồn

Cần **Flutter 3.47** (nhóm dùng 3.47.5) và Android Studio.

👉 **Hướng dẫn từng bước bằng Android Studio** (mở project, nối điện thoại, Run/Debug, chạy test): [CONTRIBUTING.md](CONTRIBUTING.md). Chi tiết kỹ thuật, lỗi thường gặp: [docs/DEVELOPER.md](docs/DEVELOPER.md).

Hoặc bằng dòng lệnh:

```bash
git clone https://github.com/nguyenthanhloi727-cell/SafeFamilyApp.git
```

```bash
cd SafeFamilyApp
```

Bật gỡ lỗi trên điện thoại:

- **Mọi Android:** Cài đặt → Giới thiệu điện thoại → bấm 7 lần *Số hiệu bản dựng* → Tùy chọn nhà phát triển → bật **Gỡ lỗi USB**.
- **Xiaomi / Redmi / POCO:** bấm 7 lần *Phiên bản MIUI/HyperOS*; bật thêm **Cài đặt qua USB**.

Cắm cáp, cho phép gỡ lỗi, rồi:

```bash
flutter run
```

Chỉ chạy **bản demo vân tay** (1 màn: vân tay biometric_storage + mã PIN dự phòng, trả về token hoặc mã lỗi tùy thao tác): trong Android Studio chọn cấu hình **Demo vân tay (main_demo.dart)**, hoặc:

```bash
flutter run -t lib/main_demo.dart
```

## Dùng Khóa phụ huynh (vân tay)

Tên ô ghi đúng như trên màn hình app. **Tất cả nằm trong app SafeFamily**, không phải trong Cài đặt của điện thoại. Làm trên máy mẹ (máy con vào qua **Dành cho phụ huynh** → **Mở ứng dụng đầy đủ**).

1. **Bật vân tay:** tab **Tài khoản** → ô **Bảo mật & khóa phụ huynh** → công tắc **Mở khóa bằng vân tay/khuôn mặt** → nhập mã PIN → hộp thoại **Xác thực phụ huynh** → chạm cảm biến → công tắc chuyển màu xanh. Ô trên cùng ghi máy hỗ trợ gì (ví dụ *"Máy này hỗ trợ: Vân tay"*).
2. **Mở khóa bằng vân tay:** bấm việc cần mở khóa (ví dụ **Chặn ứng dụng**) → hộp thoại **Xác thực phụ huynh** → quét vân tay. Quét sai thì Android tự báo và cho quét lại.
3. **Dùng PIN thay vân tay:** trong hộp thoại bấm **Dùng mã PIN** → nhập PIN → **✓**.
4. **Xem lại:** tab **Tài khoản** → **Nhật ký mở khóa** → mỗi dòng ghi việc, giờ, cách mở (*Vân tay* / *Mã PIN*) và kết quả.
5. **Tắt vân tay:** **Bảo mật & khóa phụ huynh** → gạt tắt công tắc (phải xác thực trước).
6. Máy vừa **thêm/xóa vân tay** hoặc vừa cập nhật app → màn nhập PIN có khung vàng *"…mở khóa sinh trắc đã tắt"* → nhập PIN rồi làm lại bước 1.

## Chạy server (để ghép hai máy)

Server `SafeFamily.Api` (ASP.NET Core + SQL Server) cần chạy trước khi ghép đôi. Cấu hình, lệnh chạy và danh sách API: [docs/API_TIEN_TRINH.md](docs/API_TIEN_TRINH.md), [docs/API_DAY_DU.md](docs/API_DAY_DU.md).

```bash
cd SafeFamily.Api
```

```bash
dotnet ef database update
```

```bash
dotnet run
```

Máy ảo Android gọi máy tính qua `http://10.0.2.2:<cổng>`; máy thật dùng địa chỉ IP trong mạng (hoặc domain HTTPS). Địa chỉ server sửa được ở màn đăng nhập / kết nối.

## Kịch bản demo (máy ảo = máy con, máy thật = máy mẹ có vân tay)

Chuẩn bị: chạy server; cài APK lên cả hai máy. Máy thật làm mẹ vì cần vân tay; máy ảo làm con.

1. **Máy mẹ:** mở app → đặt mã PIN, bật vân tay → màn *Máy này dùng để làm gì?* chọn **Máy mẹ** → đăng ký tài khoản → cấp **Thông báo**.
2. **Ghép đôi:** máy mẹ, tab **Con** → nút 👪 **Kết nối gia đình** → **Tạo mã ghép đôi**. **Máy con:** đặt PIN → cấp đủ quyền (Trợ năng, Báo thức…) → chọn **Máy con** → nhập mã 6 số → **Kết nối**. Máy mẹ hiện máy con trong *Máy con đã ghép*.
3. **Chặn app từ xa:** máy mẹ, tab **Con** → **Chặn ứng dụng** → **Chặn nhanh YouTube** (xác thực). Chờ đồng bộ (hoặc bấm **Đồng bộ với máy mẹ** trên máy con) → mở YouTube trên máy con → hiện màn chặn. Mẹ bấm ⏱ cạnh app để **mở tạm 15 phút**.
4. **Giới hạn giờ:** **Giới hạn thời gian** → đặt vài phút cho cả ngày → đồng bộ → dùng quá giờ → máy con hiện màn hết giờ.
5. **Yêu cầu của con:** máy con bấm **Xin thêm giờ** (15/30 phút) hoặc **Con học xong rồi** → máy mẹ vào **Yêu cầu của con** → duyệt / từ chối → máy con hiện *Mẹ đã duyệt* / *Mẹ từ chối*.
6. **Vị trí và hàng rào:** máy mẹ mở màn máy con → **Vị trí** → **Thêm** hàng rào (**Dùng vị trí hiện tại của con**) → đổi vị trí giả trên máy ảo → mục *Vào / ra gần đây* và thông báo cho mẹ.
7. **Hoạt động:** máy con mở app bị chặn, thử vào **Dành cho phụ huynh** và nhập sai PIN → máy mẹ thẻ **Hoạt động của con** báo số dòng mới, mở ra thấy sự kiện theo giờ.
8. **Danh bạ:** máy mẹ tab **Tài khoản** → **Danh bạ của con** → thêm một số, đánh dấu **SOS** → đồng bộ → máy con hiện nút **SOS** và **Gọi người nhà** trên cùng, bấm gọi mở màn quay số.
9. **Ngắt kết nối:** máy con **Dành cho phụ huynh** → xác thực → **Ngắt kết nối với máy mẹ**.

Lưu ý khi dùng máy ảo:

- Phải **bật Trợ năng** cho *SafeFamily - Khóa ứng dụng* trong Cài đặt của máy ảo, nếu không không chặn được app.
- Vị trí là **vị trí giả** (Extended controls → Location); đổi vị trí để thử hàng rào.
- Máy con đồng bộ **5 phút một lần**; muốn thấy ngay thì bấm **Đồng bộ với máy mẹ**. Máy mẹ nhận thông báo nền trễ tối thiểu 15 phút (WorkManager), mở app mẹ rồi kéo xuống để làm mới.
- Máy ảo thường không có vân tay thật: dùng **Dùng mã PIN**, hoặc đăng ký vân tay giả trong Cài đặt của máy ảo.

## Khóa ứng dụng trên máy con

1. Mở **Bảo vệ máy** / thiết lập khóa ứng dụng; bấm **Mở Cài đặt** ở từng quyền, bật xong bấm quay lại — trạng thái tự đổi thành *Đã bật*:
   - **Trợ năng** (bắt buộc): tìm *SafeFamily - Khóa ứng dụng* → Bật. Công tắc bị mờ, báo *"Cài đặt bị hạn chế"* (Android 13 trở lên, cài từ file APK): Thông tin ứng dụng → nút ⋮ → **Cho phép cài đặt bị hạn chế**, rồi bật lại.
   - **Báo thức & lời nhắc** (bắt buộc — để tự chặn lại đúng giờ).
   - **Tắt tối ưu pin** (nên bật). Máy Xiaomi / Oppo / Vivo / Samsung: làm thêm theo ghi chú trên màn (cho phép tự khởi động, pin *Không giới hạn*).
2. SafeFamily, Điện thoại, Cài đặt, màn hình chính không bao giờ chặn được.
3. Con mở app bị chặn → máy về màn hình chính và hiện màn *"Con làm xong bài tập chưa? — Nhờ mẹ mở khóa trong SafeFamily nhé!"*. Nút ✕ hoặc Back → về màn hình chính.
4. Mẹ mở tạm app 15 phút (từ xa), hết giờ tự chặn lại (kể cả khi đã vuốt tắt SafeFamily).

## Giới hạn đã biết

- **Không phân biệt được vân tay của ai** — chỉ phụ huynh nên đăng ký vân tay/khuôn mặt trên máy.
- **Chỉ nhận sinh trắc loại mạnh** (package `biometric_storage`): trên hầu hết máy Android chỉ **vân tay** dùng được. Khuôn mặt tùy máy — nhiều máy (ví dụ Xiaomi 11T Pro) chỉ cho dùng khuôn mặt ở màn hình khóa, app không gọi được (app ghi rõ trong Tài khoản → Bảo mật & khóa phụ huynh). Không dùng mật khẩu màn hình của máy thay vân tay (con có thể biết) — không quét được thì nhập PIN phụ huynh.
- **Thêm / xóa vân tay trên máy** → mở khóa bằng vân tay tự tắt (Android hủy chìa khóa), app báo nhập PIN rồi bật lại trong Tài khoản → Bảo mật & khóa phụ huynh. Cập nhật từ bản v0.6.0 cũng phải bật lại một lần.
- **Khóa ứng dụng là chặn mềm**: dựa vào quyền Trợ năng, nên con có thể vào Cài đặt tắt quyền hoặc gỡ SafeFamily. Tắt quyền thì mẹ nhận cảnh báo (sau lần đồng bộ kế tiếp). Chặn cứng cần chế độ **Device Owner** (đang phát triển).
- **Màn chặn của app bị chặn không có nút và không hiện tên app** — dùng màn chặn có sẵn của package `app_blocker`; mẹ mở khóa trong SafeFamily. Những lần con mở app bị chặn được ghi vào *Hoạt động của con* (chỉ loại sự kiện và tên gói, không nội dung).
- **Mở tạm** tính theo phút và không qua nửa đêm (mở lúc 23:50 thì chặn lại lúc 23:59). **Khởi động lại máy** trong lúc đang mở tạm → app đó mở tới khi SafeFamily được mở lại.
- App dùng **quyền Trợ năng** để chặn app khác nên **không phát hành trên Google Play** ở dạng này, chỉ cài bằng file APK.
- **Quên mã PIN** chỉ đặt lại được bằng mã khôi phục hoặc xóa dữ liệu app (mất cài đặt). Không có câu hỏi bảo mật vì con dễ đoán.
- **Quyền riêng tư**: server lưu vị trí 7 ngày, nhật ký hoạt động 30 ngày, thống kê dùng 90 ngày; không lưu nội dung tin nhắn, trình duyệt, ảnh. Phần Kotlin của máy con (đồng bộ, nhật ký, danh bạ) mới build được, **chưa kiểm trên 2 máy thật**.
- Bản thử nghiệm, mới thử trên Xiaomi 11T Pro (Android 14); APK ký bằng khóa debug.

## Nhóm thực hiện

| Thành viên | Vai trò |
|---|---|
| Nguyễn Thành Lợi | Developer |
| Hồ Ngọc Phú | Tester |
| Phạm Đinh Gia Bảo | _đang cập nhật_ |
| Phương Bảo Khôi | _đang cập nhật_ |

Repo lưu trên tài khoản GitHub của một thành viên để nộp bài; mọi thành viên đều là tác giả.

## Tài liệu cho lập trình viên

[docs/DEVELOPER.md](docs/DEVELOPER.md): cấu trúc thư mục, package, quyền Android, `ParentGuard`, khóa ứng dụng, test, git, build APK, lỗi thường gặp.

## Giấy phép

Mã nguồn: **MIT** — xem [LICENSE](LICENSE). Font Be Vietnam Pro: SIL OFL 1.1 — [assets/fonts/BeVietnamPro/OFL.txt](assets/fonts/BeVietnamPro/OFL.txt).
