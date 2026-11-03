# Kịch bản demo SafeFamily (~10 phút)

Câu chuyện xuyên suốt: **mẹ đi làm, con ở nhà cầm điện thoại. Mẹ muốn con học bài, không sa vào YouTube, biết con ở đâu, mà không phải gọi điện hỏi liên tục.**

Bỏ qua: đăng nhập, đăng ký, PIN lần đầu, báo thức giọng nói, tab Nhóm, danh bạ (không phải điểm mạnh của app quản lý trẻ).

Tên nút bên dưới lấy từ code (`lib/`). Máy thật có thể khác chữ chút, chạy thử một lượt trước khi demo.

## 0. Chuẩn bị (làm trước, không làm trên sân khấu)

| Việc | Ghi chú |
|---|---|
| 2 máy Android: **máy mẹ**, **máy con** | Cả hai cài cùng bản APK mới nhất |
| Server API chạy được và cả 2 máy tới được | Server **chưa publish MyASP.net** (docs/API_TIEN_TRINH.md). Chạy local trên laptop, 2 máy + laptop chung Wi-Fi, nhập địa chỉ ở ô địa chỉ máy chủ |
| Máy con: cấp đủ quyền | Trang chủ không còn dòng *"Còn thiếu N quyền"*; Trợ năng, Báo thức & lời nhắc, Truy cập dữ liệu sử dụng, Vị trí **Luôn cho phép** |
| Đã ghép đôi sẵn | Máy mẹ: **Kết nối gia đình** → **Tạo mã ghép đôi** → máy con nhập **Mã 6 số** → **Kết nối** (mã hạn 10 phút, dùng 1 lần) |
| Máy con có YouTube, một app game/mạng xã hội | Dùng làm vật chặn |
| Sạc đầy, tắt tối ưu pin cho SafeFamily | Xiaomi dễ giết app nền |

**Độ trễ:** máy con hỏi server mỗi **5 phút**. Mọi bước "mẹ ra lệnh → con nhận" trong kịch bản có thể trễ. Cách xử lý: mở sẵn app máy con rồi bấm làm mới / kéo đồng bộ, hoặc **nói thẳng cho khán giả biết** đây là thiết kế polling (đã chốt, không dùng FCM).

---

## Cảnh 1 (1 phút) - Mẹ thấy con từ xa

Máy mẹ: Trang chủ → máy con đã ghép → màn **Trạng thái máy con**.

- Chỉ vào: lần cuối thấy, pin, nếu thiếu quyền sẽ hiện **Máy con còn thiếu quyền**.
- Nói: *"Mẹ không cần hỏi con, app tự báo con còn online không, pin bao nhiêu, có đang tắt quyền nào không."*

**Điểm nhấn:** mất kết nối quá ngưỡng (mặc định 24 giờ) thì mẹ được báo.

## Cảnh 2 (2 phút) - Chặn app từ xa + con xin mở (tính năng đinh)

1. **Máy con:** mở YouTube bình thường, cho khán giả thấy mở được.
2. **Máy mẹ:** chọn máy con → **Chặn ứng dụng** → **Chặn nhanh YouTube** (hoặc gạt công tắc app) → bấm **Gửi luật cho máy con**.
3. **Máy con:** mở YouTube → bị đẩy về màn hình chính + màn chặn *"Con làm xong bài tập chưa?"*.
4. Nói: *"Luật nằm trên máy con. Tắt Wi-Fi máy con đi thì vẫn chặn."* Thử bật chế độ máy bay máy con rồi mở lại YouTube cho thấy vẫn chặn (nếu muốn chứng minh).
5. **Máy mẹ:** mở tạm 15 phút bằng nút ⏱ cạnh app (xác thực vân tay/PIN) → YouTube dùng được → hết giờ tự chặn lại, kể cả khi vuốt tắt SafeFamily.

**Điểm nhấn:** hỗ trợ "mở tạm" thay vì cấm tuyệt đối; mọi thay đổi đều bắt xác thực phụ huynh, **kể cả mẹ cầm máy con**.

## Cảnh 3 (2 phút) - Giờ học và giới hạn thời gian

Máy mẹ → màn máy con → khu **Điều khiển máy con**:

1. Bấm **Giờ học 30 phút** → máy con vào phiên học, app giải trí bị chặn.
2. Máy con báo **"Con báo đã học xong"** → máy mẹ hiện **Duyệt / Học tiếp** (hoặc chip **Duyệt đã học xong**, **Từ chối**).
3. Bấm **Khóa 60 phút** rồi **Mở khóa** để cho thấy khóa máy tức thì.
4. Nhắc thêm (không cần làm hết): **Giới hạn thời gian** có *Mẫu theo độ tuổi*, giới hạn tổng và từng app; **Tắt giới hạn hôm nay** (sang ngày tự bật lại); **Thêm giờ cho con** (Thêm N phút); **Tạm dừng máy của con**.

**Điểm nhấn:** mẹ cho phép linh hoạt (thưởng thêm giờ, tắt giới hạn một hôm), không chỉ cấm.

## Cảnh 4 (1 phút) - Con xin phép

1. **Máy con:** gửi một yêu cầu (xin thêm giờ / xin mở app).
2. **Máy mẹ:** Hiện nút **Yêu cầu của con (1 chờ duyệt)** → mở → duyệt hoặc từ chối.

**Điểm nhấn:** con có đường nói chuyện chính đáng, đỡ cãi nhau, mẹ quyết ngay trên điện thoại.

## Cảnh 5 (1 phút) - App mới cài bị chặn chờ duyệt

1. **Máy con:** cài một app bất kỳ từ Play Store / APK.
2. App bị chặn ngay cho tới khi mẹ duyệt. **Máy mẹ:** nút **App mới cài (1 chờ duyệt)** → **Cho phép** hoặc **Chặn**.

**Điểm nhấn:** con không lách luật bằng cách tải app mới. Mẹ vào trang con xem trong **Duyệt app mới cài** cũng được.

## Cảnh 6 (1,5 phút) - Vị trí và hàng rào địa lý

Máy mẹ → màn máy con:

1. Công tắc **Chia sẻ vị trí**: bật/tắt (con không bị theo dõi âm thầm; mẹ tắt thì con dừng gửi).
2. Bản đồ + *"Cập nhật lần cuối … sai số ~N m"*.
3. **Thêm** hàng rào → **Dùng vị trí hiện tại của con** → đặt tên (Nhà/Trường), bán kính → **Lưu**.
4. Con đi ra khỏi vùng (cầm máy con bước ra khỏi cổng, hoặc dùng giả lập vị trí) → mục **Vào / ra gần đây** hiện *"Con đã rời …"* / *"Con đã đến …"* + thông báo.
5. **Xóa lịch sử vị trí** có hộp xác nhận.

**Rủi ro demo:** GPS sai số 10-30 m và trễ; **chuẩn bị video quay trước** cho bước 4, đừng trông vào chạy trực tiếp.

## Cảnh 7 (1 phút) - Cảnh báo phá luật + báo cáo

- **Cảnh báo của máy con** (huy hiệu *chưa đọc*): máy con tắt Trợ năng / gỡ quyền / đổi giờ máy → mẹ nhận cảnh báo. Làm thật: máy con vào Cài đặt điện thoại tắt quyền Trợ năng của SafeFamily, chờ cảnh báo hiện ở máy mẹ.
- **Báo cáo thời gian dùng**: *Hôm nay*, *7 ngày gần nhất*, *Dùng nhiều nhất trong tuần*. Chỉ gửi **thống kê thời gian theo app** lên server, **không** gửi nội dung, danh bạ, ảnh.

## Cảnh 8 (30 giây) - Bảo mật và quyền riêng tư (chốt)

- Máy con ở chế độ trẻ em: thao tác quan trọng đều đòi **vân tay (biometric_storage) hoặc PIN phụ huynh**; sai PIN 5 lần bị khóa tăng dần; **Nhật ký mở khóa** ghi lại.
- PIN chỉ lưu **hash trên máy**, không lên server.
- 2 người giám hộ (mẹ + bố), mã mời 8 số hạn 30 phút; phân quyền chéo gia đình có test.

---

## Phương án dự phòng

| Sự cố | Cách xử |
|---|---|
| Server/mạng chết | Dùng **chế độ "Dùng một máy"** (không cần tài khoản/mạng): chạy lại Cảnh 2 và 3 trên 1 máy với **Chặn ứng dụng**, README mục *Kịch bản demo* |
| Lệnh tới chậm | Nói rõ polling 5 phút; chuyển sang cảnh khác chờ, quay lại sau |
| GPS không nhúc nhích | Phát video quay sẵn Cảnh 6 bước 4 |
| Xiaomi giết app nền | Kiểm lại tự khởi động + pin *Không giới hạn* trước giờ demo |

## Nói thẳng giới hạn (nếu bị hỏi)

- Chặn app là **chặn mềm** (dựa Trợ năng): con có thể vào Cài đặt tắt. Bù lại, mẹ nhận cảnh báo. Chặn cứng cần Device Owner, đang phát triển.
- Chưa dùng push (FCM): lệnh trễ tối đa vài phút.
- Chưa test trên 2 máy thật với server publish; app chỉ phát hành bằng APK, không lên Google Play.

## Việc cần kiểm trước khi demo

Kịch bản dựa trên code, **chưa chạy thử trên 2 máy thật**. Cần rà lại: tên nút máy con (Cảnh 4, 5), cách con gửi "xin mở app / xin thêm giờ", luồng báo "đã học xong" phía máy con, và cảnh báo phá luật có hiện ngay không. Chỗ nào chữ khác thì sửa theo màn thật.
