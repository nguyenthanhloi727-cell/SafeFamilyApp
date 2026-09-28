import '../clock_reading.dart';

/// Đọc giờ trong câu tiếng Anh: "7:30 am", "7 30 pm", "half past 7",
/// "quarter to 8", "7 o'clock", "seven thirty in the evening", "noon"…
ClockReading? readEnglishTime(String input) {
  final text = _numberWordsToDigits(_normalize(input));
  final period = _period(text);

  RegExpMatch? match(String pattern) => RegExp(pattern).firstMatch(text);
  int group(RegExpMatch m, int i) => toInt(m[i]!);

  var m = match(r'\bhalf past (\d{1,2})\b');
  if (m != null) return (hour: group(m, 1), minute: 30, period: period);

  m = match(r'\bquarter past (\d{1,2})\b');
  if (m != null) return (hour: group(m, 1), minute: 15, period: period);

  m = match(r'\bquarter to (\d{1,2})\b');
  if (m != null) return minutesBefore(group(m, 1), 15, period);

  m = match(r'\b(\d{1,2}) (?:minutes? )?past (\d{1,2})\b');
  if (m != null) {
    return (hour: group(m, 2), minute: group(m, 1), period: period);
  }

  m = match(r'\b(\d{1,2}) (?:minutes? )?to (\d{1,2})\b');
  if (m != null) return minutesBefore(group(m, 2), group(m, 1), period);

  // "7 oh 5" → 7:05
  m = match(r'\b(\d{1,2}) oh (\d)\b');
  if (m != null) {
    return (hour: group(m, 1), minute: group(m, 2), period: period);
  }

  // "7:30", "7.30", "7 30"
  m = match(r'\b(\d{1,2})(?:\s*[:.]\s*| )(\d{2})\b');
  if (m != null) {
    return (hour: group(m, 1), minute: group(m, 2), period: period);
  }

  // "730 am"
  m = match(r'\b(\d{1,2})(\d{2}) ?(?:am|pm)\b');
  if (m != null) {
    return (hour: group(m, 1), minute: group(m, 2), period: period);
  }

  // "7 o'clock", "7 am", "7pm"
  m = match(r'\b(\d{1,2}) ?(?:oclock|am|pm)\b');
  if (m != null) return (hour: group(m, 1), minute: 0, period: period);

  // "at 7", "for 7"
  m = match(r'\b(?:at|for) (\d{1,2})\b(?![:.]?\d)');
  if (m != null) return (hour: group(m, 1), minute: 0, period: period);

  if (RegExp(r'\bmidnight\b').hasMatch(text)) {
    return (hour: 12, minute: 0, period: DayPeriod.night);
  }
  if (RegExp(r'\bnoon\b').hasMatch(text)) {
    return (hour: 12, minute: 0, period: DayPeriod.noon);
  }
  return null;
}

String _normalize(String input) {
  var text = input.toLowerCase().replaceAll('’', "'");
  text = text.replaceAll(RegExp(r"\bo'? ?clock\b"), ' oclock');
  // "a.m." / "a. m." / "p.m" → "am" / "pm"
  text = text.replaceAllMapped(
    RegExp(r'\b([ap])\. ?m\b\.?'),
    (m) => ' ${m[1]}m ',
  );
  text = text.replaceAll('-', ' ');
  text = text.replaceAll(RegExp(r'[,!?;"()]'), ' ');
  return text.replaceAll(RegExp(r'\s+'), ' ').trim();
}

DayPeriod? _period(String text) {
  bool has(String word) => RegExp('\\b$word\\b').hasMatch(text);
  // "pm" trước "am": "am" còn có thể là "I am …".
  if (has('pm') || has('afternoon')) return DayPeriod.afternoon;
  if (has('am') || has('morning')) return DayPeriod.morning;
  if (has('evening') || has('tonight')) return DayPeriod.evening;
  if (has('night')) return DayPeriod.night;
  if (has('noon')) return DayPeriod.noon;
  return null;
}

const _units = {
  'one': 1,
  'two': 2,
  'three': 3,
  'four': 4,
  'five': 5,
  'six': 6,
  'seven': 7,
  'eight': 8,
  'nine': 9,
};

const _teens = {
  'ten': 10,
  'eleven': 11,
  'twelve': 12,
  'thirteen': 13,
  'fourteen': 14,
  'fifteen': 15,
  'sixteen': 16,
  'seventeen': 17,
  'eighteen': 18,
  'nineteen': 19,
};

const _tens = {'twenty': 20, 'thirty': 30, 'forty': 40, 'fifty': 50};

/// "seven twenty five" → "7 25"; "twelve" → "12".
String _numberWordsToDigits(String text) {
  final words = text.split(' ');
  final out = <String>[];
  var i = 0;
  while (i < words.length) {
    final word = words[i];
    final tens = _tens[word];
    if (tens != null) {
      final unit = i + 1 < words.length ? _units[words[i + 1]] : null;
      out.add('${tens + (unit ?? 0)}');
      i += unit == null ? 1 : 2;
      continue;
    }
    final value = _units[word] ?? _teens[word];
    out.add(value?.toString() ?? word);
    i++;
  }
  return out.join(' ');
}
