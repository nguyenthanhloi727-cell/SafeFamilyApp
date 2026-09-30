import 'package:flutter_test/flutter_test.dart';

import 'package:safe_family_app_nguyenthanhloi/core/constants/app_info.dart';
import 'package:safe_family_app_nguyenthanhloi/features/app_lock/domain/protected_apps.dart';
import 'package:safe_family_app_nguyenthanhloi/features/app_lock/domain/temp_unlock.dart';

void main() {
  group('ProtectedApps — không bao giờ được chặn', () {
    test('SafeFamily, Cài đặt, Điện thoại, launcher phổ biến', () {
      for (final pkg in [
        AppInfo.applicationId,
        'com.android.settings',
        'com.google.android.dialer',
        'com.android.dialer',
        'com.miui.home',
        'com.sec.android.app.launcher',
        'com.android.launcher3',
      ]) {
        expect(ProtectedApps.isProtected(pkg, const {}), isTrue, reason: pkg);
      }
    });

    test('package máy trả về (Điện thoại của Xiaomi) cũng được bảo vệ', () {
      expect(
        ProtectedApps.isProtected('com.android.contacts', const {}),
        isFalse,
      );
      expect(
        ProtectedApps.isProtected('com.android.contacts', {
          'com.android.contacts',
        }),
        isTrue,
      );
    });

    test('app thường chặn được', () {
      for (final pkg in ['com.google.android.youtube', 'com.zing.zalo']) {
        expect(ProtectedApps.isProtected(pkg, const {}), isFalse, reason: pkg);
      }
    });
  });

  group('tempUnlockExpiry — hạn mở tạm 15 phút', () {
    const d = Duration(minutes: 15);

    test('đúng phút tròn thì cộng đúng 15 phút', () {
      expect(
        tempUnlockExpiry(DateTime(2026, 9, 30, 14, 0), d),
        DateTime(2026, 9, 30, 14, 15),
      );
    });

    test('lẻ giây thì làm tròn lên phút sau', () {
      expect(
        tempUnlockExpiry(DateTime(2026, 9, 30, 14, 0, 20), d),
        DateTime(2026, 9, 30, 14, 16),
      );
    });

    test('không qua nửa đêm: dừng ở 23:59', () {
      expect(
        tempUnlockExpiry(DateTime(2026, 9, 30, 23, 50), d),
        DateTime(2026, 9, 30, 23, 59),
      );
    });

    test('từ 23:59 trở đi: không mở tạm được', () {
      expect(tempUnlockExpiry(DateTime(2026, 9, 30, 23, 59), d), isNull);
      expect(tempUnlockExpiry(DateTime(2026, 9, 30, 23, 59, 30), d), isNull);
    });

    test('1 phút (chế độ thử)', () {
      expect(
        tempUnlockExpiry(
          DateTime(2026, 9, 30, 8, 30, 5),
          const Duration(minutes: 1),
        ),
        DateTime(2026, 9, 30, 8, 32),
      );
    });
  });

  group('TempUnlocks', () {
    final now = DateTime(2026, 9, 30, 14, 0);
    final unlocks = const TempUnlocks()
        .withUnlock('a', DateTime(2026, 9, 30, 14, 15))
        .withUnlock('b', DateTime(2026, 9, 30, 13, 59))
        .withUnlock('c', DateTime(2026, 9, 30, 14, 5));

    test('hết giờ: đúng lúc hạn cũng tính là hết', () {
      expect(unlocks.expired(now), ['b']);
      expect(unlocks.expired(DateTime(2026, 9, 30, 14, 5)), ['b', 'c']);
    });

    test('lần hết hạn gần nhất ở tương lai', () {
      expect(unlocks.nextExpiry(now), DateTime(2026, 9, 30, 14, 5));
      expect(
        unlocks.without('c').nextExpiry(now),
        DateTime(2026, 9, 30, 14, 15),
      );
    });

    test('lưu rồi đọc lại', () {
      final back = TempUnlocks.fromJson(unlocks.toJson());
      expect(back.packages, unorderedEquals(['a', 'b', 'c']));
      expect(back.untilOf('a'), DateTime(2026, 9, 30, 14, 15));
    });

    test('dữ liệu hỏng → rỗng', () {
      expect(TempUnlocks.fromJson('không phải json').isEmpty, isTrue);
      expect(TempUnlocks.fromJson('[1,2]').isEmpty, isTrue);
      expect(TempUnlocks.fromJson(null).isEmpty, isTrue);
    });
  });
}
