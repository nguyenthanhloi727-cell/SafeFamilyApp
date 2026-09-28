/// Giờ báo thức theo đồng hồ 24 giờ.
class AlarmTime {
  const AlarmTime(this.hour, this.minute)
    : assert(hour >= 0 && hour < 24),
      assert(minute >= 0 && minute < 60);

  final int hour;
  final int minute;

  /// "06:30"
  String format() =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  /// Lần báo kế tiếp tính từ [now] (cùng phút với [now] thì tính sang ngày mai).
  DateTime nextOccurrence(DateTime now) {
    var next = DateTime(now.year, now.month, now.day, hour, minute);
    if (!next.isAfter(now)) next = next.add(const Duration(days: 1));
    return next;
  }

  @override
  bool operator ==(Object other) =>
      other is AlarmTime && other.hour == hour && other.minute == minute;

  @override
  int get hashCode => Object.hash(hour, minute);

  @override
  String toString() => 'AlarmTime(${format()})';
}
