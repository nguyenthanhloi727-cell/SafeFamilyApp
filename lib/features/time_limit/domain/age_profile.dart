import 'time_limit_config.dart';

/// Mẫu cấu hình dựng sẵn theo độ tuổi của con (F11). Chỉ là điểm khởi đầu:
/// phụ huynh vẫn chỉnh lại từng ngày sau khi áp dụng.
enum AgeProfile {
  age6to8(
    label: '6–8 tuổi',
    weekdayMinutes: 60,
    weekendMinutes: 120,
    bedtime: BedtimeWindow(20 * 60, 6 * 60 + 30),
  ),
  age9to12(
    label: '9–12 tuổi',
    weekdayMinutes: 90,
    weekendMinutes: 180,
    bedtime: BedtimeWindow(21 * 60, 6 * 60),
  );

  const AgeProfile({
    required this.label,
    required this.weekdayMinutes,
    required this.weekendMinutes,
    required this.bedtime,
  });

  final String label;

  /// Tổng phút dùng máy Thứ Hai – Thứ Sáu.
  final int weekdayMinutes;

  /// Tổng phút dùng máy Thứ Bảy, Chủ Nhật.
  final int weekendMinutes;

  /// Giờ ngủ áp dụng cả tuần.
  final BedtimeWindow bedtime;

  String get summary =>
      '${formatMinutes(weekdayMinutes)}/ngày học, '
      '${formatMinutes(weekendMinutes)}/ngày cuối tuần, '
      'giờ ngủ ${formatClock(bedtime.startMinute)}–'
      '${formatClock(bedtime.endMinute)}';

  /// Ghi đè tổng thời gian và giờ ngủ của [base], bật cả hai. Giới hạn riêng
  /// từng app, giờ học và danh sách app học giữ nguyên.
  TimeLimitConfig applyTo(TimeLimitConfig base) => base.copyWith(
    enabled: true,
    total: [
      for (var day = 0; day < 7; day++)
        day < 5 ? weekdayMinutes : weekendMinutes,
    ],
    bedtimeEnabled: true,
    bedtime: List<BedtimeWindow?>.filled(7, bedtime),
  );
}
