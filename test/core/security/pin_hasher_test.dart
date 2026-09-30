import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:safe_family_app/core/security/pin_hasher.dart';

String hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

void main() {
  group('PBKDF2-HMAC-SHA256 — test vector chuẩn', () {
    List<int> derive(String p, String s, int c, int len) =>
        pbkdf2HmacSha256(utf8.encode(p), utf8.encode(s), c, len);

    test('c = 1', () {
      expect(
        hex(derive('password', 'salt', 1, 32)),
        '120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b',
      );
    });

    test('c = 2', () {
      expect(
        hex(derive('password', 'salt', 2, 32)),
        'ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43',
      );
    });

    test('c = 4096', () {
      expect(
        hex(derive('password', 'salt', 4096, 32)),
        'c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a',
      );
    });
  });

  group('PinHasher', () {
    const hasher = PinHasher(iterations: 1000, useIsolate: false);

    test('băm rồi kiểm: đúng PIN → true, sai PIN → false', () async {
      final stored = await hasher.hash('2580');
      expect(await hasher.verify('2580', stored), isTrue);
      expect(await hasher.verify('2581', stored), isFalse);
      expect(await hasher.verify('', stored), isFalse);
    });

    test('KHÔNG lưu PIN gốc; có salt nên 2 lần băm khác nhau', () async {
      final a = await hasher.hash('2580');
      final b = await hasher.hash('2580');
      expect(a, isNot(contains('2580')));
      expect(a, isNot(b));
      expect(a, startsWith(r'pbkdf2-sha256$1000$'));
    });

    test('dùng số vòng ghi trong chuỗi đã lưu', () async {
      final stored = await const PinHasher(
        iterations: 3,
        useIsolate: false,
      ).hash('2580');
      expect(await hasher.verify('2580', stored), isTrue);
    });

    test('chuỗi lưu hỏng / bị sửa → false, không crash', () async {
      final stored = await hasher.hash('2580');
      final parts = stored.split(r'$');
      for (final bad in [
        '',
        'abc',
        r'md5$1000$AAAA$BBBB',
        r'pbkdf2-sha256$0$AAAA$BBBB',
        r'pbkdf2-sha256$1000$%%%$BBBB',
        [
          parts[0],
          parts[1],
          parts[2],
          base64.encode(List.filled(32, 0)),
        ].join(r'$'),
      ]) {
        expect(await hasher.verify('2580', bad), isFalse, reason: bad);
      }
    });

    test('constantTimeEquals', () {
      expect(constantTimeEquals([1, 2, 3], [1, 2, 3]), isTrue);
      expect(constantTimeEquals([1, 2, 3], [1, 2, 4]), isFalse);
      expect(constantTimeEquals([1, 2], [1, 2, 3]), isFalse);
    });
  });

  group('Quy tắc chọn PIN', () {
    test('4–6 chữ số', () {
      expect(isPinFormatValid('2580'), isTrue);
      expect(isPinFormatValid('258046'), isTrue);
      expect(isPinFormatValid('258'), isFalse);
      expect(isPinFormatValid('2580467'), isFalse);
      expect(isPinFormatValid('25a0'), isFalse);
    });

    test('chặn PIN dễ đoán', () {
      for (final weak in ['0000', '111111', '1234', '123456', '9876', '3210']) {
        expect(pinChoiceProblem(weak), isNotNull, reason: weak);
      }
      for (final ok in ['2580', '1357', '904812', '1122']) {
        expect(pinChoiceProblem(ok), isNull, reason: ok);
      }
    });
  });
}
