# assets/team — thông tin và ảnh thành viên nhóm

## Thông tin: `members.json`

Sửa file này để điền MSSV, email, vai trò, lớp — không cần sửa code.
Thứ tự trong file = thứ tự thẻ trong app. Trường để `""` sẽ hiện "Chưa cập nhật".

| Trường | Ý nghĩa |
|---|---|
| `id` | Mã không dấu, dùng đặt tên ảnh — **không đổi** |
| `fullName` | Họ tên có dấu |
| `studentId` | MSSV |
| `email` | Email (bấm vào trong app sẽ mở app mail) |
| `role` | Vai trò trong nhóm |
| `className` | Lớp |

## Ảnh cố định: `<id>.jpg`

Đặt ảnh vào đúng thư mục này, tên = `id` + `.jpg` (chữ thường, đuôi `.jpg`):

```
nguyenthanhloi.jpg
hongocphu.jpg
phamdinhgiabao.jpg
phuongbaokhoi.jpg
```

- Nên là ảnh vuông, khoảng 600 × 600 px, dưới 300 KB.
- Ảnh ở đây luôn được ưu tiên hơn ảnh tải lên trong app.
- Thêm/đổi ảnh xong phải build lại app (`flutter run`) — hot reload không nhận asset mới.
- Gắn đủ ảnh rồi thì khoá tải ảnh: đặt `kTeamPhotoUploadEnabled = false` trong `lib/core/constants/feature_flags.dart`.
