/// Buổi trong ngày nói kèm giờ (sáng, chiều, tối…).
enum DayPeriod {
  /// sáng / am / 午前 / 上午 / 오전 — 12 giờ sáng = 0 giờ.
  morning,

  /// trưa / 昼 / 中午 — 11, 12 giữ nguyên; 1–5 là buổi chiều.
  noon,

  /// chiều / pm / 午後 / 下午 / 오후 — 12 giờ chiều = 12 giờ.
  afternoon,

  /// tối / evening / 晚上 / 저녁 — 12 giờ tối = 0 giờ.
  evening,

  /// đêm / night / 夜 / 半夜 / 밤 — 12 giờ đêm = 0; 1–4 giờ đêm giữ nguyên.
  night,
}

/// Giờ đọc được từ câu, CHƯA quy về 24 giờ.
///
/// [hour] có thể là 1–12 (giờ 12 tiếng) hoặc 0, 13–24 (giờ 24 tiếng).
typedef ClockReading = ({int hour, int minute, DayPeriod? period});

/// "7 giờ kém 15" → 6:45. Giữ kiểu 12 tiếng nếu [hour] là 1–12.
ClockReading? minutesBefore(int hour, int minutes, DayPeriod? period) {
  if (minutes <= 0 || minutes >= 60) return null;
  final int previous;
  if (hour >= 1 && hour <= 12) {
    previous = hour == 1 ? 12 : hour - 1;
  } else {
    previous = hour == 0 ? 23 : hour - 1;
  }
  return (hour: previous, minute: 60 - minutes, period: period);
}

/// Giá trị của một cụm chữ số Hán (Nhật/Trung/Hàn dùng chung cách ghép):
/// "十二" → 12, "二十五" → 25, "三十" → 30, "〇五" → 5.
int? parseTensNumeral(
  String text,
  Map<String, int> digits, {
  required String ten,
}) {
  if (text.isEmpty) return null;
  final tenIndex = text.indexOf(ten);
  if (tenIndex < 0) {
    var value = 0;
    for (final char in text.split('')) {
      final digit = digits[char];
      if (digit == null) return null;
      value = value * 10 + digit;
    }
    return value;
  }
  final left = text.substring(0, tenIndex);
  final right = text.substring(tenIndex + ten.length);
  if (right.contains(ten)) return null;
  final tens = left.isEmpty ? 1 : digits[left];
  final units = right.isEmpty ? 0 : digits[right];
  if (tens == null || units == null) return null;
  return tens * 10 + units;
}

/// Đổi chữ số toàn chiều rộng (０-９, ：) sang ASCII.
String toHalfWidthDigits(String text) {
  final buffer = StringBuffer();
  for (final rune in text.runes) {
    if (rune >= 0xFF10 && rune <= 0xFF19) {
      buffer.writeCharCode(rune - 0xFF10 + 0x30);
    } else if (rune == 0xFF1A) {
      buffer.write(':');
    } else {
      buffer.writeCharCode(rune);
    }
  }
  return buffer.toString();
}

int toInt(String digits) => int.parse(digits);
