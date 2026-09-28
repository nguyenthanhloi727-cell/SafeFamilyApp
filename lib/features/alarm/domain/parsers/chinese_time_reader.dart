import '../clock_reading.dart';

/// Đọc giờ trong câu tiếng Trung: "7点30分", "7点半", "7点一刻",
/// "差一刻8点", "上午/下午/晚上七点"…
ClockReading? readChineseTime(String input) {
  final text = _hanziToDigits(toHalfWidthDigits(input).replaceAll(' ', ''));
  final period = _period(text);

  RegExpMatch? match(String pattern) => RegExp(pattern).firstMatch(text);
  const hourMark = '[点點时時]';

  // "差5分8点", "差一刻8点"
  var m = match(r'差(\d{1,2})分?(\d{1,2})[点點]');
  if (m != null) return minutesBefore(toInt(m[2]!), toInt(m[1]!), period);
  m = match(r'差(\d)刻(\d{1,2})[点點]');
  if (m != null) {
    return minutesBefore(toInt(m[2]!), toInt(m[1]!) * 15, period);
  }
  // "8点差5分", "8点差一刻"
  m = match(r'(\d{1,2})[点點]差(\d)刻');
  if (m != null) {
    return minutesBefore(toInt(m[1]!), toInt(m[2]!) * 15, period);
  }
  m = match(r'(\d{1,2})[点點]差(\d{1,2})分?');
  if (m != null) return minutesBefore(toInt(m[1]!), toInt(m[2]!), period);

  m = match('(\\d{1,2})$hourMark半');
  if (m != null) return (hour: toInt(m[1]!), minute: 30, period: period);

  m = match('(\\d{1,2})$hourMark(\\d)刻');
  if (m != null) {
    return (hour: toInt(m[1]!), minute: toInt(m[2]!) * 15, period: period);
  }

  m = match('(\\d{1,2})$hourMark(\\d{1,2})分?');
  if (m != null) {
    return (hour: toInt(m[1]!), minute: toInt(m[2]!), period: period);
  }

  m = match('(\\d{1,2})$hourMark');
  if (m != null) return (hour: toInt(m[1]!), minute: 0, period: period);

  m = match(r'(\d{1,2}):(\d{2})');
  if (m != null) {
    return (hour: toInt(m[1]!), minute: toInt(m[2]!), period: period);
  }
  return null;
}

DayPeriod? _period(String text) {
  bool hasAny(List<String> words) => words.any(text.contains);
  if (hasAny(['半夜', '夜里', '夜裡', '深夜', '午夜'])) return DayPeriod.night;
  if (hasAny(['上午', '早上', '早晨', '清晨', '凌晨'])) return DayPeriod.morning;
  if (hasAny(['中午'])) return DayPeriod.noon;
  if (hasAny(['下午', '傍晚'])) return DayPeriod.afternoon;
  if (hasAny(['晚上', '今晚', '晚'])) return DayPeriod.evening;
  return null;
}

const _digits = {
  '〇': 0,
  '零': 0,
  '一': 1,
  '二': 2,
  '两': 2,
  '兩': 2,
  '三': 3,
  '四': 4,
  '五': 5,
  '六': 6,
  '七': 7,
  '八': 8,
  '九': 9,
};

/// "七点三十分" → "7点30分"; "差一刻八点" → "差1刻8点".
String _hanziToDigits(String text) => text.replaceAllMapped(
  RegExp('[〇零一二两兩三四五六七八九十]+'),
  (m) => parseTensNumeral(m[0]!, _digits, ten: '十')?.toString() ?? m[0]!,
);
