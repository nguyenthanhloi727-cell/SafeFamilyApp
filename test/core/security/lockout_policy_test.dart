import 'package:flutter_test/flutter_test.dart';

import 'package:safe_family_app/core/security/lockout_policy.dart';

void main() {
  test('sai 1–4 lần: chưa khóa', () {
    for (var n = 0; n < 5; n++) {
      expect(lockDurationAfter(n), isNull, reason: 'sai $n lần');
    }
  });

  test('sai 5 lần: khóa 30 giây', () {
    expect(lockDurationAfter(5), const Duration(seconds: 30));
  });

  test('sai tiếp: thời gian khóa tăng dần (gấp đôi)', () {
    expect(lockDurationAfter(6), const Duration(minutes: 1));
    expect(lockDurationAfter(7), const Duration(minutes: 2));
    expect(lockDurationAfter(8), const Duration(minutes: 4));
    for (var n = 6; n < 20; n++) {
      expect(
        lockDurationAfter(n)! >= lockDurationAfter(n - 1)!,
        isTrue,
        reason: 'không được giảm',
      );
    }
  });

  test('tối đa 30 phút, không tràn số', () {
    expect(lockDurationAfter(12), maxLockDuration);
    expect(lockDurationAfter(1000), maxLockDuration);
  });
}
