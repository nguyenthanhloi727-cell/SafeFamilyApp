/// Hằng số của Khóa ứng dụng — sửa câu chữ màn chặn ở đây.
///
/// Màn chặn là màn gốc của package app_blocker: chỉ đổi được chữ và màu,
/// không có nút, không biết tên app bị chặn.
abstract final class BlockScreenTexts {
  static const title = 'Con làm xong bài tập chưa?';
  static const subtitle = 'Ứng dụng này đang bị khóa.';
  static const message = 'Nhờ mẹ mở khóa trong SafeFamily nhé!';

  /// Nền màn chặn (chữ màu trắng) — `color/primary` của DESIGN.md.
  static const backgroundArgb = 0xFF00796B;
}

/// Số phút mẹ mở tạm một app, hết giờ tự chặn lại.
///
/// Thử trên máy cho nhanh: `flutter run --dart-define=SF_UNLOCK_MINUTES=1`.
const tempUnlockMinutes = int.fromEnvironment(
  'SF_UNLOCK_MINUTES',
  defaultValue: 15,
);

const tempUnlockDuration = Duration(minutes: tempUnlockMinutes);

/// Package YouTube trên Android (nút chặn nhanh).
const youtubePackage = 'com.google.android.youtube';
