import 'dart:convert';

/// Số phút được dùng mỗi ngày trong tuần (0 = Thứ Hai … 6 = Chủ Nhật);
/// `null` = không giới hạn.
typedef WeekLimits = List<int?>;

const weekdayNames = [
  'Thứ Hai',
  'Thứ Ba',
  'Thứ Tư',
  'Thứ Năm',
  'Thứ Sáu',
  'Thứ Bảy',
  'Chủ Nhật',
];

/// Số phút tối đa chọn được trên thanh trượt (8 giờ).
const maxLimitMinutes = 480;

/// Khung giờ ngủ: [startMinute] đến [endMinute] tính từ 00:00. Nếu
/// `endMinute <= startMinute` thì khung kéo sang sáng hôm sau (21:00–06:00).
class BedtimeWindow {
  const BedtimeWindow(this.startMinute, this.endMinute);

  final int startMinute;
  final int endMinute;

  bool get overnight => endMinute <= startMinute;

  BedtimeWindow copyWith({int? startMinute, int? endMinute}) => BedtimeWindow(
    startMinute ?? this.startMinute,
    endMinute ?? this.endMinute,
  );

  @override
  bool operator ==(Object other) =>
      other is BedtimeWindow &&
      other.startMinute == startMinute &&
      other.endMinute == endMinute;

  @override
  int get hashCode => Object.hash(startMinute, endMinute);
}

/// Giờ học mặc định khi bật một ngày: 19:00–21:00.
const defaultStudy = BedtimeWindow(19 * 60, 21 * 60);

/// Lúc [at] có nằm trong khung giờ của [week] không (khung qua nửa đêm tính
/// vào ngày bắt đầu). Cùng quy tắc với `TimeLimits.inWeekWindow` bên Kotlin.
bool inWeekWindow(List<BedtimeWindow?> week, DateTime at) {
  final minute = at.hour * 60 + at.minute;
  final today = week[at.weekday - 1];
  if (today != null) {
    final inside = today.overnight
        ? minute >= today.startMinute
        : minute >= today.startMinute && minute < today.endMinute;
    if (inside) return true;
  }
  final yesterday = week[(at.weekday + 5) % 7];
  return yesterday != null &&
      yesterday.overnight &&
      minute < yesterday.endMinute;
}

/// Giờ ngủ mặc định khi bật một ngày: 21:00–06:00.
const defaultBedtime = BedtimeWindow(21 * 60, 6 * 60);

/// Mỗi ngày một khung giờ ngủ; `null` = không có giờ ngủ ngày đó.
typedef WeekBedtime = List<BedtimeWindow?>;

WeekBedtime noBedtimeWeek() => List<BedtimeWindow?>.filled(7, null);

/// "21:05" từ số phút tính từ 00:00.
String formatClock(int minuteOfDay) =>
    '${(minuteOfDay ~/ 60).toString().padLeft(2, '0')}:'
    '${(minuteOfDay % 60).toString().padLeft(2, '0')}';

WeekLimits unlimitedWeek() => List<int?>.filled(7, null);

/// Cấu hình giới hạn thời gian. Native (Kotlin) đọc cùng JSON này, nên
/// khuôn dạng phải khớp `TimeLimits.kt`: `-1` = không giới hạn.
class TimeLimitConfig {
  TimeLimitConfig({
    this.enabled = false,
    WeekLimits? total,
    Map<String, WeekLimits>? apps,
    this.bedtimeEnabled = false,
    WeekBedtime? bedtime,
    this.studyEnabled = false,
    WeekBedtime? study,
    Set<String>? studyApps,
  }) : total = total ?? unlimitedWeek(),
       apps = apps ?? {},
       bedtime = bedtime ?? noBedtimeWeek(),
       study = study ?? noBedtimeWeek(),
       studyApps = studyApps ?? {};

  final bool enabled;

  /// Tổng thời gian dùng máy mỗi ngày.
  final WeekLimits total;

  /// Giới hạn riêng từng app: package → 7 ngày.
  final Map<String, WeekLimits> apps;

  /// Giờ ngủ (downtime): bật riêng, không phụ thuộc [enabled].
  final bool bedtimeEnabled;

  /// Khung giờ ngủ bắt đầu vào mỗi thứ (khung qua nửa đêm tính vào ngày bắt đầu).
  final WeekBedtime bedtime;

  /// Giờ học: bật riêng như giờ ngủ. Trong khung giờ này chỉ app trong
  /// [studyApps] (cộng gọi điện, máy tính, từ điển) mở được.
  final bool studyEnabled;

  /// Khung giờ học bắt đầu vào mỗi thứ.
  final WeekBedtime study;

  /// App phụ huynh cho phép trong giờ học.
  final Set<String> studyApps;

  TimeLimitConfig copyWith({
    bool? enabled,
    WeekLimits? total,
    Map<String, WeekLimits>? apps,
    bool? bedtimeEnabled,
    WeekBedtime? bedtime,
    bool? studyEnabled,
    WeekBedtime? study,
    Set<String>? studyApps,
  }) => TimeLimitConfig(
    enabled: enabled ?? this.enabled,
    total: total ?? this.total,
    apps: apps ?? this.apps,
    bedtimeEnabled: bedtimeEnabled ?? this.bedtimeEnabled,
    bedtime: bedtime ?? this.bedtime,
    studyEnabled: studyEnabled ?? this.studyEnabled,
    study: study ?? this.study,
    studyApps: studyApps ?? this.studyApps,
  );

  /// Lúc [at] có đang trong giờ ngủ không. Cùng quy tắc với `TimeLimits.kt`.
  bool inBedtime(DateTime at) => bedtimeEnabled && inWeekWindow(bedtime, at);

  /// Lúc [at] có nằm trong lịch giờ học không (chưa tính "tắt hôm nay" và
  /// phiên "bắt đầu ngay", do native giữ).
  bool inStudy(DateTime at) => studyEnabled && inWeekWindow(study, at);

  /// [packageName] có mở được lúc đang giờ học không (không tính app miễn trừ).
  bool studyAllows(String packageName) => studyApps.contains(packageName);

  /// Giới hạn tổng của [weekday] (`DateTime.weekday`, 1 = Thứ Hai).
  int? totalFor(int weekday) => total[weekday - 1];

  int? appLimitFor(String packageName, int weekday) =>
      apps[packageName]?[weekday - 1];

  String toJson() => jsonEncode({
    'enabled': enabled,
    'total': [for (final m in total) m ?? -1],
    'apps': {
      for (final entry in apps.entries)
        entry.key: [for (final m in entry.value) m ?? -1],
    },
    'bedtime': {
      'enabled': bedtimeEnabled,
      'days': [
        for (final w in bedtime)
          w == null ? null : [w.startMinute, w.endMinute],
      ],
    },
    'study': {
      'enabled': studyEnabled,
      'days': [
        for (final w in study) w == null ? null : [w.startMinute, w.endMinute],
      ],
      'allowed': studyApps.toList()..sort(),
    },
  });

  factory TimeLimitConfig.fromJson(String source) {
    try {
      final map = jsonDecode(source) as Map<String, dynamic>;
      return TimeLimitConfig(
        enabled: map['enabled'] == true,
        total: _week(map['total']),
        apps: {
          for (final entry
              in (map['apps'] as Map<String, dynamic>? ?? const {}).entries)
            entry.key: _week(entry.value),
        },
        bedtimeEnabled: (map['bedtime'] as Map?)?['enabled'] == true,
        bedtime: _bedtime((map['bedtime'] as Map?)?['days']),
        studyEnabled: (map['study'] as Map?)?['enabled'] == true,
        study: _bedtime((map['study'] as Map?)?['days']),
        studyApps: {
          for (final p
              in ((map['study'] as Map?)?['allowed'] as List? ?? const []))
            if (p is String) p,
        },
      );
    } on Object {
      return TimeLimitConfig();
    }
  }

  static WeekBedtime _bedtime(Object? raw) {
    final list = raw is List ? raw : const [];
    BedtimeWindow? parse(Object? v) {
      if (v is! List || v.length != 2 || v[0] is! num || v[1] is! num) {
        return null;
      }
      final start = (v[0] as num).toInt();
      final end = (v[1] as num).toInt();
      if (start < 0 || start >= 1440 || end < 0 || end >= 1440) return null;
      return BedtimeWindow(start, end);
    }

    return [
      for (var i = 0; i < 7; i++) i < list.length ? parse(list[i]) : null,
    ];
  }

  static WeekLimits _week(Object? raw) {
    final list = raw is List ? raw : const [];
    return [
      for (var i = 0; i < 7; i++)
        i < list.length && list[i] is num && (list[i] as num) >= 0
            ? (list[i] as num).toInt()
            : null,
    ];
  }
}

/// "1 giờ 20 phút", "45 phút", "0 phút".
String formatMinutes(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return '$m phút';
  if (m == 0) return '$h giờ';
  return '$h giờ $m phút';
}
