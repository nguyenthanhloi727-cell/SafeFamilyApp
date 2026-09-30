import 'package:flutter_test/flutter_test.dart';

import 'package:safe_family_app/core/constants/app_languages.dart';
import 'package:safe_family_app/features/alarm/domain/alarm_time.dart';
import 'package:safe_family_app/features/alarm/domain/time_parser.dart';

/// "Bây giờ" cố định cho test: 20:00.
final evening = DateTime(2026, 9, 28, 20, 0);

/// Buổi sáng 10:00 — để kiểm tra chọn mốc gần nhất sắp tới.
final morning = DateTime(2026, 9, 28, 10, 0);

void expectTime(
  AppLanguage language,
  String text,
  String expected, {
  DateTime? now,
}) {
  final result = parseAlarmTime(text, language, now: now ?? evening);
  expect(result, isA<TimeUnderstood>(), reason: '"$text" phải hiểu được');
  expect((result as TimeUnderstood).time.format(), expected, reason: text);
}

void expectNotUnderstood(AppLanguage language, String text) {
  expect(
    parseAlarmTime(text, language, now: evening),
    isA<TimeNotUnderstood>(),
    reason: '"$text" phải báo không hiểu giờ',
  );
}

void main() {
  group('Tiếng Việt', () {
    const vi = AppLanguage.vietnamese;
    test('câu đầy đủ', () {
      expectTime(vi, 'Đặt báo thức 6 giờ 30 sáng', '06:30');
      expectTime(vi, 'lúc 5 giờ 5 phút chiều', '17:05');
    });
    test('6h30, 6:30', () {
      expectTime(vi, '6h30', '06:30');
      expectTime(vi, '6:30 sáng', '06:30');
    });
    test('rưỡi', () => expectTime(vi, '6 giờ rưỡi chiều', '18:30'));
    test('kém', () {
      expectTime(vi, '7 giờ kém 15 tối', '18:45');
      expectTime(vi, '7 giờ kém 15 phút sáng', '06:45');
    });
    test('trưa / tối / đêm', () {
      expectTime(vi, '12 giờ trưa', '12:00');
      expectTime(vi, '1 giờ trưa', '13:00');
      expectTime(vi, '9 giờ tối', '21:00');
      expectTime(vi, '11 giờ đêm', '23:00');
      expectTime(vi, '12 giờ đêm', '00:00');
      expectTime(vi, '2 giờ đêm', '02:00');
    });
    test('số viết bằng chữ', () {
      expectTime(vi, 'sáu giờ ba mươi lăm sáng', '06:35');
      expectTime(vi, 'mười giờ tối', '22:00');
      expectTime(vi, 'bảy giờ mười lăm', '07:15');
      expectTime(vi, 'mười một giờ hai mươi tư trưa', '11:24');
    });
    test('giờ 24 tiếng', () => expectTime(vi, '18 giờ 15', '18:15'));
    test('không nói buổi → mốc gần nhất sắp tới', () {
      expectTime(vi, '6 giờ 30', '06:30'); // 20:00 → sáng mai
      expectTime(vi, '9 giờ', '21:00', now: morning); // 10:00 → tối nay
    });
    test('câu sai', () {
      expectNotUnderstood(vi, 'đặt báo thức');
      expectNotUnderstood(vi, 'chào buổi sáng');
      expectNotUnderstood(vi, '25 giờ');
      expectNotUnderstood(vi, '6 giờ 75');
      expectNotUnderstood(vi, '');
    });
  });

  group('English', () {
    const en = AppLanguage.english;
    test('7:30 am, 7 30 pm, a.m./p.m.', () {
      expectTime(en, 'Set an alarm for 7:30 am', '07:30');
      expectTime(en, '7 30 pm', '19:30');
      expectTime(en, 'seven fifteen p.m.', '19:15');
      expectTime(en, '6:45 a.m.', '06:45');
    });
    test('half past / quarter to / past / to', () {
      expectTime(en, 'half past 7', '07:30');
      expectTime(en, 'quarter to 8 in the morning', '07:45');
      expectTime(en, 'quarter past six pm', '18:15');
      expectTime(en, 'ten past nine at night', '21:10');
      expectTime(en, 'twenty to seven in the evening', '18:40');
    });
    test("o'clock, at …", () {
      expectTime(en, "7 o'clock", '07:00');
      expectTime(en, 'wake me up at six', '06:00');
      expectTime(en, 'seven oh five am', '07:05');
    });
    test('12 am / 12 pm / noon / midnight', () {
      expectTime(en, '12 am', '00:00');
      expectTime(en, '12 pm', '12:00');
      expectTime(en, 'noon', '12:00');
      expectTime(en, 'midnight', '00:00');
    });
    test('24h và mốc gần nhất', () {
      expectTime(en, '18:30', '18:30');
      expectTime(en, 'at 9', '21:00', now: morning);
    });
    test('câu sai', () {
      expectNotUnderstood(en, 'set an alarm');
      expectNotUnderstood(en, 'good morning');
      expectNotUnderstood(en, 'at 25');
      expectNotUnderstood(en, '7:75 am');
    });
  });

  group('日本語', () {
    const ja = AppLanguage.japanese;
    test('時・分・半', () {
      expectTime(ja, '午前7時30分', '07:30');
      expectTime(ja, '7時半に起こして', '07:30');
      expectTime(ja, '8時', '08:00');
    });
    test('午前/午後/夜', () {
      expectTime(ja, '午後七時十五分', '19:15');
      expectTime(ja, '夜9時', '21:00');
      expectTime(ja, '午前0時', '00:00');
      expectTime(ja, '朝6時', '06:00');
    });
    test('分前', () => expectTime(ja, '7時10分前', '06:50'));
    test('漢数字 và 全角', () {
      expectTime(ja, '午前六時二十五分', '06:25');
      expectTime(ja, '１８：３０', '18:30');
    });
    test('正午', () => expectTime(ja, '正午', '12:00'));
    test('mốc gần nhất', () => expectTime(ja, '3時', '15:00', now: morning));
    test('câu sai', () {
      expectNotUnderstood(ja, 'おはよう');
      expectNotUnderstood(ja, '25時');
      expectNotUnderstood(ja, '7時75分');
    });
  });

  group('中文', () {
    const zh = AppLanguage.chinese;
    test('点·分·半', () {
      expectTime(zh, '明天早上7点半叫我', '07:30');
      expectTime(zh, '7点30分', '07:30');
      expectTime(zh, '上午十一点零五分', '11:05');
    });
    test('一刻 / 差一刻', () {
      expectTime(zh, '下午三点一刻', '15:15');
      expectTime(zh, '差一刻8点', '07:45');
      expectTime(zh, '8点差5分', '07:55');
      expectTime(zh, '差5分8点', '07:55');
    });
    test('上午/下午/晚上', () {
      expectTime(zh, '晚上十点', '22:00');
      expectTime(zh, '晚上12点', '00:00');
      expectTime(zh, '中午12点', '12:00');
    });
    test(
      '两点 → mốc gần nhất',
      () => expectTime(zh, '两点', '14:00', now: morning),
    );
    test('24h', () => expectTime(zh, '18:30', '18:30'));
    test('câu sai', () {
      expectNotUnderstood(zh, '你好');
      expectNotUnderstood(zh, '25点');
      expectNotUnderstood(zh, '7点75分');
    });
  });

  group('한국어', () {
    const ko = AppLanguage.korean;
    test('시·분·반', () {
      expectTime(ko, '오전 7시 30분', '07:30');
      expectTime(ko, '7시 반에 알람 맞춰줘', '07:30');
    });
    test('오전/오후/저녁/밤', () {
      expectTime(ko, '오후 3시', '15:00');
      expectTime(ko, '저녁 여섯 시', '18:00');
      expectTime(ko, '밤 12시', '00:00');
      expectTime(ko, '오전 12시', '00:00');
    });
    test('số thuần Hàn + Hán-Hàn', () {
      expectTime(ko, '일곱 시 삼십 분', '07:30');
      expectTime(ko, '오후 열두 시 십오 분', '12:15');
    });
    test('분 전', () => expectTime(ko, '8시 10분 전', '07:50'));
    test('정오 / 자정', () {
      expectTime(ko, '정오', '12:00');
      expectTime(ko, '자정', '00:00');
    });
    test('câu sai', () {
      expectNotUnderstood(ko, '안녕하세요');
      expectNotUnderstood(ko, '25시');
      expectNotUnderstood(ko, '7시 75분');
    });
  });

  group('AlarmTime', () {
    test('format', () => expect(const AlarmTime(6, 5).format(), '06:05'));

    test('nextOccurrence: sau bây giờ là hôm nay, trước/bằng là ngày mai', () {
      final now = DateTime(2026, 9, 28, 20, 0);
      expect(
        const AlarmTime(21, 0).nextOccurrence(now),
        DateTime(2026, 9, 28, 21),
      );
      expect(
        const AlarmTime(6, 30).nextOccurrence(now),
        DateTime(2026, 9, 29, 6, 30),
      );
      expect(
        const AlarmTime(20, 0).nextOccurrence(now),
        DateTime(2026, 9, 29, 20),
      );
    });

    test('nói đúng phút hiện tại (không buổi) → lấy mốc 12 tiếng sau', () {
      expectTime(AppLanguage.vietnamese, '8 giờ', '08:00'); // bây giờ 20:00
    });
  });
}
