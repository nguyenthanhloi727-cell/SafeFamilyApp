import 'package:flutter_test/flutter_test.dart';

import 'package:safe_family_app/features/profile/data/phone_number.dart';

void main() {
  group('normalizePhone', () {
    test('bỏ khoảng trắng và dấu chấm', () {
      expect(normalizePhone(' 090.123 4567 '), '0901234567');
      expect(normalizePhone('+84 901.234.567'), '+84901234567');
    });
  });

  group('validatePhone — hợp lệ', () {
    for (final phone in [
      '0901234567', // 10 số
      '090 123 4567', // có khoảng trắng
      '090.123.4567', // có dấu chấm
      '+84901234567', // + ở đầu, 11 số
      '024123456', // 9 số (tối thiểu)
      '+849012345678', // 12 số (tối đa)
    ]) {
      test('"$phone"', () => expect(validatePhone(phone), isNull));
    }
  });

  group('validatePhone — không hợp lệ', () {
    test('rỗng', () => expect(validatePhone('  '), 'Nhập số điện thoại'));

    for (final phone in [
      '09012a4567',
      '090-123-4567',
      '0901+234567',
      '++84901234567',
    ]) {
      test('"$phone" có ký tự lạ', () {
        expect(validatePhone(phone), 'Chỉ gồm chữ số, được có dấu + ở đầu');
      });
    }

    for (final phone in ['12345678', '+8490123456789', '0901234567890']) {
      test('"$phone" sai độ dài', () {
        expect(validatePhone(phone), 'Số điện thoại phải dài 9–12 chữ số');
      });
    }
  });
}
