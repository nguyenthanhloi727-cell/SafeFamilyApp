import '../clock_reading.dart';

/// Đọc giờ trong câu tiếng Hàn: "7시 30분", "7시 반", "오전/오후 7시",
/// "일곱 시 삼십 분", "8시 10분 전", "정오"…
ClockReading? readKoreanTime(String input) {
  final text = _sinoToDigits(_nativeHourToDigits(toHalfWidthDigits(input)));
  final period = _period(text);

  RegExpMatch? match(String pattern) => RegExp(pattern).firstMatch(text);

  // "8시 10분 전" → 7:50
  var m = match(r'(\d{1,2})\s*시\s*(\d{1,2})\s*분\s*전');
  if (m != null) return minutesBefore(toInt(m[1]!), toInt(m[2]!), period);

  m = match(r'(\d{1,2})\s*시\s*반');
  if (m != null) return (hour: toInt(m[1]!), minute: 30, period: period);

  m = match(r'(\d{1,2})\s*시\s*(\d{1,2})(?:\s*분)?');
  if (m != null) {
    return (hour: toInt(m[1]!), minute: toInt(m[2]!), period: period);
  }

  m = match(r'(\d{1,2})\s*시');
  if (m != null) return (hour: toInt(m[1]!), minute: 0, period: period);

  m = match(r'(\d{1,2}):(\d{2})');
  if (m != null) {
    return (hour: toInt(m[1]!), minute: toInt(m[2]!), period: period);
  }

  if (text.contains('정오')) {
    return (hour: 12, minute: 0, period: DayPeriod.noon);
  }
  if (text.contains('자정')) {
    return (hour: 12, minute: 0, period: DayPeriod.night);
  }
  return null;
}

DayPeriod? _period(String text) {
  if (text.contains('오전') || text.contains('아침') || text.contains('새벽')) {
    return DayPeriod.morning;
  }
  if (text.contains('오후') || text.contains('낮')) return DayPeriod.afternoon;
  if (text.contains('저녁')) return DayPeriod.evening;
  if (text.contains('밤')) return DayPeriod.night;
  return null;
}

/// Số thuần Hàn dùng cho GIỜ: "일곱 시" → "7시".
const _nativeHours = {
  '열한': 11,
  '열두': 12,
  '열': 10,
  '하나': 1,
  '한': 1,
  '둘': 2,
  '두': 2,
  '셋': 3,
  '세': 3,
  '넷': 4,
  '네': 4,
  '다섯': 5,
  '여섯': 6,
  '일곱': 7,
  '여덟': 8,
  '아홉': 9,
};

String _nativeHourToDigits(String text) => text.replaceAllMapped(
  RegExp('(${_nativeHours.keys.join('|')})\\s*시'),
  (m) => '${_nativeHours[m[1]]}시',
);

/// Số Hán-Hàn dùng cho PHÚT (và đôi khi giờ): "삼십 분" → "30분".
const _sinoDigits = {
  '영': 0,
  '공': 0,
  '일': 1,
  '이': 2,
  '삼': 3,
  '사': 4,
  '오': 5,
  '육': 6,
  '륙': 6,
  '칠': 7,
  '팔': 8,
  '구': 9,
};

String _sinoToDigits(String text) =>
    text.replaceAllMapped(RegExp(r'([영공일이삼사오육륙칠팔구십]+)\s*(분|시)'), (m) {
      final value = parseTensNumeral(m[1]!, _sinoDigits, ten: '십');
      return value == null ? m[0]! : '$value${m[2]}';
    });
