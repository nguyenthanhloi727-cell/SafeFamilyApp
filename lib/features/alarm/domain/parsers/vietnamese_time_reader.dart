import '../clock_reading.dart';

/// Đọc giờ trong câu tiếng Việt: "6 giờ 30", "6h30", "6 giờ rưỡi",
/// "7 giờ kém 15", "sáu giờ ba mươi sáng", kèm sáng/trưa/chiều/tối/đêm.
ClockReading? readVietnameseTime(String input) {
  final text = _numberWordsToDigits(_normalize(input));
  final period = _period(text);

  RegExpMatch? match(String pattern) =>
      RegExp(pattern, unicode: true).firstMatch(text);

  // Đơn vị giờ: "giờ", "h" hoặc "g" (không dính chữ cái phía sau).
  const unit = r'(?:giờ|h(?!\p{L})|g(?!\p{L}))';

  // "7 giờ kém 15 (phút)"
  var m = match('(\\d{1,2})\\s*$unit\\s*kém\\s*(\\d{1,2})');
  if (m != null) {
    return minutesBefore(toInt(m[1]!), toInt(m[2]!), period);
  }
  // "6 giờ rưỡi", "6 rưỡi"
  m = match('(\\d{1,2})\\s*(?:$unit)?\\s*rưỡi');
  if (m != null) return (hour: toInt(m[1]!), minute: 30, period: period);
  // "6 giờ 30 (phút)", "6h30", "6:30"
  m = match('(\\d{1,2})\\s*(?:$unit|:|\\.)\\s*(\\d{1,2})(?!\\d)');
  if (m != null) {
    return (hour: toInt(m[1]!), minute: toInt(m[2]!), period: period);
  }
  // "6 giờ", "6h"
  m = match('(\\d{1,2})\\s*$unit');
  if (m != null) return (hour: toInt(m[1]!), minute: 0, period: period);
  // "nửa đêm" không kèm số
  if (text.contains('nửa đêm')) {
    return (hour: 12, minute: 0, period: DayPeriod.night);
  }
  return null;
}

String _normalize(String input) => input
    .toLowerCase()
    .replaceAll(RegExp(r'[,!?;"“”()]'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

DayPeriod? _period(String text) {
  if (text.contains('đêm') || text.contains('khuya')) return DayPeriod.night;
  if (text.contains('tối')) return DayPeriod.evening;
  if (text.contains('chiều')) return DayPeriod.afternoon;
  if (text.contains('trưa')) return DayPeriod.noon;
  if (text.contains('sáng')) return DayPeriod.morning;
  return null;
}

/// Chữ số đứng một mình ("sáu", "bảy"…).
const _units = {
  'một': 1,
  'hai': 2,
  'ba': 3,
  'bốn': 4,
  'năm': 5,
  'sáu': 6,
  'bảy': 7,
  'bẩy': 7,
  'tám': 8,
  'chín': 9,
};

/// Chữ số đứng sau "mười"/"mươi" ("mười lăm", "hai mươi mốt", "ba mươi tư").
const _unitsAfterTen = {..._units, 'mốt': 1, 'tư': 4, 'lăm': 5};

/// "sáu giờ ba mươi lăm" → "6 giờ 35".
String _numberWordsToDigits(String text) {
  final words = text.split(' ');
  final out = <String>[];
  var i = 0;
  while (i < words.length) {
    final word = words[i];
    String? at(int k) => k < words.length ? words[k] : null;

    if (word == 'mười') {
      final unit = _unitsAfterTen[at(i + 1)];
      out.add('${10 + (unit ?? 0)}');
      i += unit == null ? 1 : 2;
      continue;
    }
    final unit = _units[word];
    if (unit != null && at(i + 1) == 'mươi') {
      final next = _unitsAfterTen[at(i + 2)];
      out.add('${unit * 10 + (next ?? 0)}');
      i += next == null ? 2 : 3;
      continue;
    }
    out.add(unit?.toString() ?? word);
    i++;
  }
  return out.join(' ');
}
