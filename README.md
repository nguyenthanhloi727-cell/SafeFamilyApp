# SafeFamily

**SafeFamily** là ứng dụng Android giúp **phụ huynh có con dưới 13 tuổi** yên tâm khi đưa điện thoại cho con: con vẫn gọi được cho người nhà, còn các thao tác quan trọng (sửa danh bạ, đặt báo thức, cài đặt…) được **khóa bằng vân tay / khuôn mặt hoặc mã PIN của phụ huynh**.

Đồ án nhóm môn Flutter — sản phẩm chung của cả nhóm (xem [Nhóm thực hiện](#nhóm-thực-hiện)). Phiên bản thử nghiệm: **v0.6.0**.

> 📷 *Ảnh chụp màn hình: đặt vào `docs/screenshots/` và chèn tại đây.*

---

## Tính năng đã có

| Tính năng | Mô tả |
|---|---|
| 🔒 **Khóa phụ huynh bằng vân tay / khuôn mặt** | Thiết lập mã PIN lần đầu, bật vân tay/khuôn mặt; **chế độ trẻ em** (thoát phải xác thực); khu vực phụ huynh tự khóa lại khi app ở nền quá 1/5/15 phút; sai PIN 5 lần khóa 30 giây (tăng dần); nhật ký mở khóa |
| Điều hướng 5 tab | `BottomNavigationBar`: Trang chủ – Dịch – Báo thức – Nhóm – Cá nhân, giữ trạng thái từng tab |
| Cá nhân | Hồ sơ phụ huynh; **danh bạ gia đình** (chạm để gọi, thêm/sửa/xóa); nút **Mở YouTube**; Cài đặt |
| Báo thức bằng giọng nói | Nói hoặc gõ câu đặt giờ bằng **5 ngôn ngữ** (Việt, Anh, Nhật, Trung, Hàn) → xác nhận → mở **app Đồng hồ của máy** với giờ điền sẵn |
| Nhóm | Thẻ thành viên lướt ngang (ảnh, họ tên, MSSV, email, vai trò, lớp); tải ảnh từ thư viện |

### Đối chiếu yêu cầu đồ án

| Mục | Yêu cầu | Trạng thái |
|---|---|---|
| 1 | Khung app + `BottomNavigationBar` | ✓ |
| 2 | Cá nhân: danh bạ gia đình + YouTube | ✓ |
| 3 | Báo thức bằng giọng nói, 5 ngôn ngữ | ✓ |
| 4 | Dịch văn bản / giọng nói / ảnh | Đang phát triển |
| 5 | *(đang cập nhật)* | — |
| 6 | Nhóm: thẻ thành viên | ✓ |
| Chức năng chính | Khóa phụ huynh bằng sinh trắc học | ✓ (thử nghiệm) |

### Chỗ nào bị khóa (khi đang ở chế độ trẻ em)

| Bị khóa — cần vân tay/khuôn mặt hoặc PIN | Không khóa |
|---|---|
| Thoát chế độ trẻ em; thêm/sửa/xóa danh bạ, sửa tên phụ huynh; đặt/sửa báo thức, đổi ngôn ngữ; tải/đổi/xóa ảnh nhóm; mọi cài đặt; bảo mật, nhật ký, quản lý thiết bị | **Bấm gọi người nhà**, toàn bộ tab Dịch, xem tab Nhóm, mở YouTube |

## Đang phát triển

- **Dịch** văn bản / giọng nói / ảnh — tab Dịch hiện chỉ là màn giữ chỗ.
- **Camera dịch trực tiếp**.
- **Quản lý thiết bị của con**: chặn app, giới hạn thời gian (Trang chủ hiện ghi "Sắp có").

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

Đổi tên app thành tên mình (thành viên nhóm):

```bash
dart run tool/rename.dart nguyenvana "Nguyễn Văn A"
```

Bật gỡ lỗi trên điện thoại:

- **Mọi Android:** Cài đặt → Giới thiệu điện thoại → bấm 7 lần *Số hiệu bản dựng* → Tùy chọn nhà phát triển → bật **Gỡ lỗi USB**.
- **Xiaomi / Redmi / POCO:** bấm 7 lần *Phiên bản MIUI/HyperOS*; bật thêm **Cài đặt qua USB**.

Cắm cáp, cho phép gỡ lỗi, rồi:

```bash
flutter run
```

## Kịch bản demo

1. Mở app lần đầu → **đặt mã PIN** (nhập 2 lần) → **Bật** vân tay.
2. Cá nhân → bật **Chế độ trẻ em** → dải "Đang ở chế độ trẻ em" hiện ở đầu màn hình.
3. Thử **Thêm / Sửa** danh bạ → bị chặn, hiện hộp thoại vân tay.
4. **Quét vân tay** → mở khóa, sửa được. Bấm gọi người nhà → gọi được ngay, không cần mở khóa.
5. Báo thức → nói *"Đặt báo thức 6 giờ 30 sáng"* → Đặt báo thức (xác thực) → app Đồng hồ mở với 06:30.
6. Thoát chế độ trẻ em (xác thực) → Cá nhân → **Nhật ký mở khóa** xem lại các lần mở khóa.

## Giới hạn đã biết

- **Không phân biệt được vân tay của ai** — chỉ phụ huynh nên đăng ký vân tay/khuôn mặt trên máy.
- **Khuôn mặt tùy máy** — nhiều máy chỉ cho dùng khuôn mặt ở màn hình khóa, app không gọi được (app ghi rõ trong Cá nhân → Bảo mật).
- **Chỉ khóa bên trong SafeFamily** — không chặn được app khác trên máy.
- **Quên mã PIN** chỉ đặt lại được bằng cách xóa dữ liệu app (mất danh bạ, ảnh, cài đặt). Không có câu hỏi bảo mật vì con dễ đoán.
- Báo thức do **app Đồng hồ của máy** phát; nhận giọng nói cần dịch vụ của Google (có thể cần mạng / tải gói ngôn ngữ).
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

[docs/DEVELOPER.md](docs/DEVELOPER.md): cấu trúc thư mục, package, quyền Android, `ParentGuard`, script đổi tên, test, git, build APK, lỗi thường gặp.

## Giấy phép

Mã nguồn: **MIT** — xem [LICENSE](LICENSE). Font Be Vietnam Pro: SIL OFL 1.1 — [assets/fonts/BeVietnamPro/OFL.txt](assets/fonts/BeVietnamPro/OFL.txt).
