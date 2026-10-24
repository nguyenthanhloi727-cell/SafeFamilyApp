import 'package:flutter_test/flutter_test.dart';

import 'package:safe_family_app/core/security/biometric_authenticator.dart';
import 'package:safe_family_app/core/security/device_guard.dart';
import 'package:safe_family_app/core/security/lockout_policy.dart';
import 'package:safe_family_app/core/security/parent_guard.dart';
import 'package:safe_family_app/core/security/recovery_code.dart';

import '../../helpers/security_fakes.dart';

/// Android giả: đồng hồ elapsed + số lần khởi động đặt tay được.
class FakeDeviceGuard extends NoDeviceGuard {
  Duration elapsed = const Duration(hours: 5);
  int bootCount = 7;
  final protection = <bool>[];

  @override
  Future<ClockReading?> readClock() async =>
      ClockReading(elapsed: elapsed, bootCount: bootCount);

  @override
  Future<void> setProtection(bool enabled) async => protection.add(enabled);
}

void main() {
  group('remainingLock', () {
    final lockedAt = DateTime(2026, 10, 24, 20);
    LockRecord record({Duration? elapsed, int? boot}) => LockRecord(
      duration: const Duration(minutes: 1),
      lockedAtWall: lockedAt,
      elapsedAtLock: elapsed,
      bootCount: boot,
    );

    test('cùng lần khởi động: tính theo elapsed, bỏ qua giờ treo tường', () {
      final lock = record(elapsed: const Duration(hours: 5), boot: 7);
      final remaining = remainingLock(
        lock,
        now: lockedAt.add(
          const Duration(days: 1),
        ), // con chỉnh giờ tới ngày mai
        elapsedNow: const Duration(hours: 5, seconds: 20),
        bootCountNow: 7,
      );
      expect(remaining, const Duration(seconds: 40));
    });

    test('máy khởi động lại: tính từ lúc máy bật, không ngắn hơn thực tế', () {
      final lock = record(elapsed: const Duration(hours: 5), boot: 7);
      final remaining = remainingLock(
        lock,
        now: lockedAt.add(const Duration(days: 1)),
        elapsedNow: const Duration(seconds: 15),
        bootCountNow: 8,
      );
      expect(remaining, const Duration(seconds: 45));
    });

    test('không đọc được elapsed: dùng giờ treo tường', () {
      final remaining = remainingLock(
        record(),
        now: lockedAt.add(const Duration(seconds: 20)),
      );
      expect(remaining, const Duration(seconds: 40));
    });

    test(
      'không đọc được elapsed, lùi giờ về trước: tính đủ thời gian khóa',
      () {
        final remaining = remainingLock(
          record(),
          now: lockedAt.subtract(const Duration(hours: 3)),
        );
        expect(remaining, const Duration(minutes: 1));
      },
    );

    test('hết hạn thì về 0, không bao giờ âm', () {
      final remaining = remainingLock(
        record(elapsed: const Duration(hours: 5), boot: 7),
        now: lockedAt,
        elapsedNow: const Duration(hours: 6),
        bootCountNow: 7,
      );
      expect(remaining, Duration.zero);
    });

    test('LockRecord lưu và đọc lại đúng', () {
      final lock = record(elapsed: const Duration(hours: 5), boot: 7);
      final back = LockRecord.fromJson(lock.toJson())!;
      expect(back.duration, lock.duration);
      expect(back.lockedAtWall, lock.lockedAtWall);
      expect(back.elapsedAtLock, lock.elapsedAtLock);
      expect(back.bootCount, 7);
      expect(LockRecord.fromJson('rác'), isNull);
    });
  });

  group('ParentGuard với đồng hồ không chỉnh được', () {
    late InMemorySecureStore store;
    late FakeDeviceGuard device;
    late DateTime now;

    setUp(() {
      store = InMemorySecureStore();
      device = FakeDeviceGuard();
      now = DateTime(2026, 10, 24, 20);
    });

    Future<ParentGuard> open() async {
      final guard = ParentGuard(
        store: store,
        biometrics: FakeBiometrics(cap: BiometricCapability.none),
        hasher: fastHasher,
        device: device,
        clock: () => now,
      );
      await guard.load();
      if (!guard.isConfigured) await guard.setupPin(testPin);
      return guard;
    }

    Future<void> failFiveTimes(ParentGuard guard) async {
      for (var i = 0; i < 5; i++) {
        await guard.checkPin('1111', action: 'x');
      }
    }

    test('sai 5 lần rồi chỉnh giờ hệ thống tới trước: vẫn bị khóa', () async {
      final guard = await open();
      await failFiveTimes(guard);

      now = now.add(const Duration(hours: 2)); // con đổi giờ
      device.elapsed += const Duration(seconds: 5); // thực tế mới 5 giây

      expect(await guard.checkPin(testPin, action: 'x'), isA<PinLocked>());
      expect(guard.lockedUntil, isNotNull);
    });

    test('thật sự qua 30 giây thì hết khóa', () async {
      final guard = await open();
      await failFiveTimes(guard);

      device.elapsed += const Duration(seconds: 31);
      expect(await guard.checkPin(testPin, action: 'x'), isA<PinAccepted>());
    });

    test('khởi động lại máy rồi chỉnh giờ: vẫn khóa, không rút ngắn', () async {
      final guard = await open();
      await failFiveTimes(guard);

      device
        ..bootCount = 8
        ..elapsed = const Duration(seconds: 10);
      now = now.add(const Duration(days: 1));

      final reopened = await open();
      expect(reopened.lockedUntil, isNotNull);
      expect(
        reopened.lockedUntil!.difference(now),
        const Duration(seconds: 20),
      );
      expect(await reopened.checkPin(testPin, action: 'x'), isA<PinLocked>());
    });

    test('đặt PIN bật chặn màn Cài đặt phía Android', () async {
      await open();
      expect(device.protection, contains(true));
    });
  });

  group('Mã khôi phục PIN', () {
    test('sinh 10 ký tự trong bảng chữ, mỗi lần một khác', () {
      final a = generateRecoveryCode();
      final b = generateRecoveryCode();
      expect(a, hasLength(recoveryCodeLength));
      expect(a.split('').every(recoveryAlphabet.contains), isTrue);
      expect(a, isNot(b));
    });

    test('chuẩn hóa chữ thường, khoảng trắng và gạch ngang', () {
      expect(normalizeRecoveryCode(' acdef-ghjkm '), 'ACDEFGHJKM');
      expect(isRecoveryCodeFormatValid('acdef-ghjkm'), isTrue);
      expect(isRecoveryCodeFormatValid('ABCDE'), isFalse);
      expect(isRecoveryCodeFormatValid('ACDEF-GHJK0'), isFalse); // có số 0
    });

    test('chỉ lưu bản băm, không lưu mã gốc', () async {
      final store = InMemorySecureStore();
      final guard = await configuredGuard(store: store);
      final code = await guard.renewRecoveryCode();

      expect(guard.hasRecoveryCode, isTrue);
      expect(store.data[ParentGuard.recoveryKey], startsWith('pbkdf2-sha256'));
      expect(store.data.values.any((v) => v.contains(code)), isFalse);
    });

    test('đúng mã → đặt PIN mới, PIN cũ không còn dùng được', () async {
      final guard = await configuredGuard();
      final code = await guard.renewRecoveryCode();

      final result = await guard.resetPinWithRecoveryCode(
        formatRecoveryCode(code).toLowerCase(),
        '7391',
      );
      expect(result, isA<PinAccepted>());
      expect(await guard.checkPin('7391', action: 'x'), isA<PinAccepted>());
      expect(await guard.checkPin(testPin, action: 'x'), isA<PinRejected>());
    });

    test('sai mã bị đếm và khóa như sai PIN', () async {
      final guard = await configuredGuard();
      await guard.renewRecoveryCode();

      PinCheckResult? last;
      for (var i = 0; i < 5; i++) {
        last = await guard.resetPinWithRecoveryCode('ACDEFGHJKM', '7391');
      }
      expect(last, isA<PinLocked>());
      // Khóa chung: PIN đúng cũng bị từ chối trong lúc khóa.
      expect(await guard.checkPin(testPin, action: 'x'), isA<PinLocked>());
    });

    test('chưa có mã khôi phục thì không đặt lại được', () async {
      final guard = await configuredGuard();
      expect(guard.hasRecoveryCode, isFalse);
      expect(
        await guard.resetPinWithRecoveryCode('ACDEFGHJKM', '7391'),
        isA<PinRejected>(),
      );
    });

    test('đặt PIN lần đầu kèm mã khôi phục', () async {
      final guard = await configuredGuard();
      final fresh = ParentGuard(
        store: InMemorySecureStore(),
        biometrics: FakeBiometrics(cap: BiometricCapability.none),
        hasher: fastHasher,
      );
      await fresh.load();
      await fresh.setupPin(testPin, recoveryCode: 'ACDEFGHJKM');
      expect(fresh.hasRecoveryCode, isTrue);
      expect(
        await fresh.resetPinWithRecoveryCode('acdef-ghjkm', '7391'),
        isA<PinAccepted>(),
      );
      expect(guard.hasRecoveryCode, isFalse);
    });
  });
}
