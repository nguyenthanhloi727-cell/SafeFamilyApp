import '../clock_reading.dart';

/// Đọc giờ trong câu tiếng Nhật: "7時30分", "7時半", "午前7時",
/// "午後七時十五分", "7時10分前", "正午"…
ClockReading? readJapaneseTime(String input) {
  final text = _kanjiToDigits(toHalfWidthDigits(input).replaceAll(' ', ''));
  final period = _period(text);

  RegExpMatch? match(String pattern) => RegExp(pattern).firstMatch(text);

  // "7時10分前" → 6:50
  var m = match(r'(\d{1,2})時(\d{1,2})分前');
  if (m != null) return minutesBefore(toInt(m[1]!), toInt(m[2]!), period);

  m = match(r'(\d{1,2})時半');
  if (m != null) return (hour: toInt(m[1]!), minute: 30, period: period);

  m = match(r'(\d{1,2})時(\d{1,2})分?');
  if (m != null) {
    return (hour: toInt(m[1]!), minute: toInt(m[2]!), period: period);
  }

  m = match(r'(\d{1,2})時');
  if (m != null) return (hour: toInt(m[1]!), minute: 0, period: period);

  m = match(r'(\d{1,2}):(\d{2})');
  if (m != null) {
    return (hour: toInt(m[1]!), minute: toInt(m[2]!), period: period);
  }

  if (text.contains('正午')) {
    return (hour: 12, minute: 0, period: DayPeriod.noon);
  }
  if (text.contains('真夜中')) {
    return (hour: 12, minute: 0, period: DayPeriod.night);
  }
  return null;
}

DayPeriod? _period(String text) {
  if (text.contains('午前') || text.contains('朝') || text.contains('明け方')) {
    return DayPeriod.morning;
  }
  if (text.contains('午後') || text.contains('夕方')) return DayPeriod.afternoon;
  if (text.contains('夜') || text.contains('晩')) return DayPeriod.night;
  if (text.contains('昼')) return DayPeriod.noon;
  return null;
}

const _digits = {
  '〇': 0,
  '零': 0,
  '一': 1,
  '二': 2,
  '三': 3,
  '四': 4,
  '五': 5,
  '六': 6,
  '七': 7,
  '八': 8,
  '九': 9,
};

/// "七時三十分" → "7時30分".
String _kanjiToDigits(String text) => text.replaceAllMapped(
  RegExp('[〇零一二三四五六七八九十]+'),
  (m) => parseTensNumeral(m[0]!, _digits, ten: '十')?.toString() ?? m[0]!,
);
