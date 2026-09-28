import '../../../core/constants/app_languages.dart';
import 'alarm_time.dart';
import 'clock_reading.dart';
import 'parsers/chinese_time_reader.dart';
import 'parsers/english_time_reader.dart';
import 'parsers/japanese_time_reader.dart';
import 'parsers/korean_time_reader.dart';
import 'parsers/vietnamese_time_reader.dart';

/// Kết quả hiểu giờ từ một câu nói.
sealed class TimeParseResult {
  const TimeParseResult();
}

final class TimeUnderstood extends TimeParseResult {
  const TimeUnderstood(this.time);
  final AlarmTime time;
}

/// Lỗi "không hiểu giờ": câu không có giờ, hoặc giờ/phút vô lý.
final class TimeNotUnderstood extends TimeParseResult {
  const TimeNotUnderstood();
}

/// Hiểu giờ báo thức từ [text] nói bằng [language].
///
/// Không nói sáng/chiều thì chọn mốc gần nhất SẮP TỚI tính từ [now]
/// (ví dụ 20:00 nói "7 giờ" → 07:00 sáng mai; 10:00 nói "7 giờ" → 19:00).
TimeParseResult parseAlarmTime(
  String text,
  AppLanguage language, {
  required DateTime now,
}) {
  final reading = switch (language) {
    AppLanguage.vietnamese => readVietnameseTime(text),
    AppLanguage.english => readEnglishTime(text),
    AppLanguage.japanese => readJapaneseTime(text),
    AppLanguage.chinese => readChineseTime(text),
    AppLanguage.korean => readKoreanTime(text),
  };
  final time = reading == null ? null : resolveReading(reading, now);
  return time == null ? const TimeNotUnderstood() : TimeUnderstood(time);
}

/// Quy [reading] về giờ 24 tiếng; `null` nếu giờ/phút vô lý.
AlarmTime? resolveReading(ClockReading reading, DateTime now) {
  final minute = reading.minute;
  var hour = reading.hour;
  if (minute < 0 || minute > 59 || hour < 0 || hour > 24) return null;
  if (hour == 24) hour = 0;

  // Giờ 24 tiếng (0, 13–23): rõ ràng, bỏ qua sáng/chiều.
  if (hour == 0 || hour > 12) return AlarmTime(hour, minute);

  final period = reading.period;
  if (period != null) return AlarmTime(_applyPeriod(hour, period), minute);
  return _nearestUpcoming(hour, minute, now);
}

int _applyPeriod(int hour, DayPeriod period) => switch (period) {
  DayPeriod.morning => hour % 12,
  DayPeriod.noon => hour <= 5 ? hour + 12 : hour,
  DayPeriod.afternoon => hour == 12 ? 12 : hour + 12,
  DayPeriod.evening => hour == 12 ? 0 : hour + 12,
  DayPeriod.night => hour == 12 ? 0 : (hour <= 4 ? hour : hour + 12),
};

AlarmTime _nearestUpcoming(int hour12, int minute, DateTime now) {
  final nowMinutes = now.hour * 60 + now.minute;
  AlarmTime? best;
  var bestDelta = 1 << 30;
  for (final hour in [hour12 % 12, hour12 % 12 + 12]) {
    var delta = (hour * 60 + minute - nowMinutes) % (24 * 60);
    if (delta == 0) delta = 24 * 60; // đúng phút hiện tại → ngày mai
    if (delta < bestDelta) {
      bestDelta = delta;
      best = AlarmTime(hour, minute);
    }
  }
  return best!;
}
