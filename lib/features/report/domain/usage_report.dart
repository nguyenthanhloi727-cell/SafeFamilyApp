import '../../time_limit/domain/time_limit_config.dart';

/// Thời gian dùng máy của một ngày (số liệu do native chụp mỗi ngày).
class DayUsage {
  const DayUsage({
    required this.date,
    required this.totalMinutes,
    this.blocks = 0,
    this.apps = const {},
  });

  /// Ngày (00:00 theo giờ máy).
  final DateTime date;
  final int totalMinutes;

  /// Số lần màn chặn hiện lên (con chạm vào app bị chặn).
  final int blocks;

  /// `packageName -> phút`.
  final Map<String, int> apps;

  static DayUsage? fromMap(Object? raw) {
    if (raw is! Map) return null;
    try {
      final parts = (raw['date'] as String).split('-').map(int.parse).toList();
      final apps = (raw['apps'] as Map?) ?? const {};
      return DayUsage(
        date: DateTime(parts[0], parts[1], parts[2]),
        totalMinutes: (raw['totalMinutes'] as num).toInt(),
        blocks: (raw['blocks'] as num?)?.toInt() ?? 0,
        apps: {
          for (final e in apps.entries)
            e.key as String: (e.value as num).toInt(),
        },
      );
    } catch (_) {
      return null;
    }
  }
}

/// Một dòng "top app".
class AppUsage {
  const AppUsage(this.packageName, this.minutes);

  final String packageName;
  final int minutes;
}

/// Top [limit] app dùng nhiều nhất trong [days] (cộng dồn), nhiều nhất trước.
/// App dùng 0 phút không vào bảng.
List<AppUsage> topApps(List<DayUsage> days, {int limit = 5}) {
  final sum = <String, int>{};
  for (final day in days) {
    day.apps.forEach(
      (pkg, m) => sum.update(pkg, (v) => v + m, ifAbsent: () => m),
    );
  }
  final list = [
    for (final e in sum.entries)
      if (e.value > 0) AppUsage(e.key, e.value),
  ]..sort((a, b) => b.minutes.compareTo(a.minutes));
  return list.take(limit).toList();
}

int weekTotalMinutes(List<DayUsage> days) =>
    days.fold(0, (sum, d) => sum + d.totalMinutes);

/// Hạn mức tổng của ngày [date] (phút), `null` nếu không giới hạn hoặc đang tắt.
int? totalLimitFor(TimeLimitConfig config, DateTime date) =>
    config.enabled ? config.total[date.weekday - 1] : null;

/// "Hôm nay con dùng 1 giờ 20 phút, còn 40 phút" (hoặc "đã hết giờ").
String todaySummary(
  int usedMinutes, {
  int? limitMinutes,
  int bonusMinutes = 0,
}) {
  final used = 'Hôm nay con dùng ${formatMinutes(usedMinutes)}';
  if (limitMinutes == null) return used;
  final left = limitMinutes + bonusMinutes - usedMinutes;
  return left > 0 ? '$used, còn ${formatMinutes(left)}' : '$used, đã hết giờ';
}
