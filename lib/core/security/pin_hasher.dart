import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// PIN hợp lệ về hình thức: 4–6 chữ số.
bool isPinFormatValid(String pin) => RegExp(r'^\d{4,6}$').hasMatch(pin);

/// Lý do PIN mới bị từ chối (tiếng Việt), hoặc `null` nếu dùng được.
/// Chặn PIN quá dễ đoán vì con có thể thử: 0000, 1111, 1234, 9876…
String? pinChoiceProblem(String pin) {
  if (!isPinFormatValid(pin)) return 'Mã PIN gồm 4–6 chữ số';
  final digits = pin.codeUnits.map((c) => c - 48).toList();
  if (digits.toSet().length == 1) return 'Mã PIN không được toàn một số';
  bool stepsBy(int step) {
    for (var i = 1; i < digits.length; i++) {
      if (digits[i] - digits[i - 1] != step) return false;
    }
    return true;
  }

  if (stepsBy(1) || stepsBy(-1)) return 'Mã PIN không được là dãy số liên tiếp';
  return null;
}

/// Băm PIN bằng PBKDF2-HMAC-SHA256 có salt ngẫu nhiên. KHÔNG bao giờ lưu PIN gốc.
///
/// Chuỗi lưu: `pbkdf2-sha256$<số vòng>$<salt base64>$<hash base64>`.
class PinHasher {
  const PinHasher({this.iterations = 100000, this.useIsolate = true});

  final int iterations;

  /// Tính trong isolate riêng để không đứng giao diện (test đặt `false`).
  final bool useIsolate;

  static const _scheme = 'pbkdf2-sha256';
  static const _saltLength = 16;
  static const _keyLength = 32;

  Future<String> hash(String pin, {Random? random}) async {
    final rng = random ?? Random.secure();
    final salt = Uint8List.fromList(
      List.generate(_saltLength, (_) => rng.nextInt(256)),
    );
    final key = await _derive(pin, salt, iterations);
    return [
      _scheme,
      '$iterations',
      base64.encode(salt),
      base64.encode(key),
    ].join(r'$');
  }

  /// So [pin] với chuỗi đã lưu, dùng đúng số vòng + salt trong chuỗi đó.
  Future<bool> verify(String pin, String stored) async {
    final parts = stored.split(r'$');
    if (parts.length != 4 || parts[0] != _scheme) return false;
    final rounds = int.tryParse(parts[1]);
    if (rounds == null || rounds <= 0) return false;
    try {
      final salt = base64.decode(parts[2]);
      final expected = base64.decode(parts[3]);
      final actual = await _derive(pin, salt, rounds);
      return constantTimeEquals(actual, expected);
    } on FormatException {
      return false;
    }
  }

  Future<List<int>> _derive(String pin, List<int> salt, int rounds) {
    final password = utf8.encode(pin);
    if (!useIsolate) {
      return Future.value(pbkdf2HmacSha256(password, salt, rounds, _keyLength));
    }
    return Isolate.run(
      () => pbkdf2HmacSha256(password, salt, rounds, _keyLength),
    );
  }
}

/// PBKDF2 (RFC 8018) với HMAC-SHA256.
List<int> pbkdf2HmacSha256(
  List<int> password,
  List<int> salt,
  int iterations,
  int keyLength,
) {
  final hmac = Hmac(sha256, password);
  final output = <int>[];
  for (var block = 1; output.length < keyLength; block++) {
    final blockIndex = [
      (block >> 24) & 0xff,
      (block >> 16) & 0xff,
      (block >> 8) & 0xff,
      block & 0xff,
    ];
    var u = hmac.convert([...salt, ...blockIndex]).bytes;
    final t = List<int>.of(u);
    for (var i = 1; i < iterations; i++) {
      u = hmac.convert(u).bytes;
      for (var j = 0; j < t.length; j++) {
        t[j] ^= u[j];
      }
    }
    output.addAll(t);
  }
  return output.sublist(0, keyLength);
}

/// So sánh không để lộ thời gian (tránh đoán dần từng byte).
bool constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}
