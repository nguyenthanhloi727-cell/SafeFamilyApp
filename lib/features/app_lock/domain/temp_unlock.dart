import 'dart:convert';

/// Hạn mở tạm tính từ [now].
///
/// - Làm tròn lên phút: lịch tự chặn lại của app_blocker chạy theo phút.
/// - Không qua 23:59 cùng ngày: lịch một lần của app_blocker chỉ nằm trong
///   một ngày.
/// - `null`: sát nửa đêm, không còn phút nào để mở.
DateTime? tempUnlockExpiry(DateTime now, Duration duration) {
  var until = now.add(duration);
  if (until.second != 0 || until.millisecond != 0 || until.microsecond != 0) {
    until = DateTime(
      until.year,
      until.month,
      until.day,
      until.hour,
      until.minute + 1,
    );
  }
  final lastMinute = DateTime(now.year, now.month, now.day, 23, 59);
  if (until.isAfter(lastMinute)) until = lastMinute;
  return until.isAfter(now) ? until : null;
}

/// Các app mẹ đang mở tạm: package → lúc tự chặn lại.
class TempUnlocks {
  const TempUnlocks([this._until = const {}]);

  final Map<String, DateTime> _until;

  bool get isEmpty => _until.isEmpty;
  Iterable<String> get packages => _until.keys;

  DateTime? untilOf(String packageName) => _until[packageName];

  bool contains(String packageName) => _until.containsKey(packageName);

  /// App đã hết giờ mở tạm (cần chặn lại).
  List<String> expired(DateTime now) => [
    for (final MapEntry(:key, :value) in _until.entries)
      if (!value.isAfter(now)) key,
  ];

  /// Lần hết hạn gần nhất còn ở tương lai.
  DateTime? nextExpiry(DateTime now) {
    DateTime? next;
    for (final until in _until.values) {
      if (until.isAfter(now) && (next == null || until.isBefore(next))) {
        next = until;
      }
    }
    return next;
  }

  TempUnlocks withUnlock(String packageName, DateTime until) =>
      TempUnlocks({..._until, packageName: until});

  TempUnlocks without(String packageName) =>
      TempUnlocks({..._until}..remove(packageName));

  String toJson() => jsonEncode({
    for (final MapEntry(:key, :value) in _until.entries)
      key: value.millisecondsSinceEpoch,
  });

  static TempUnlocks fromJson(String? raw) {
    if (raw == null) return const TempUnlocks();
    try {
      final map = jsonDecode(raw) as Map<String, Object?>;
      return TempUnlocks({
        for (final MapEntry(:key, :value) in map.entries)
          if (value is int) key: DateTime.fromMillisecondsSinceEpoch(value),
      });
    } on FormatException {
      return const TempUnlocks();
    } on TypeError {
      return const TempUnlocks();
    }
  }
}
