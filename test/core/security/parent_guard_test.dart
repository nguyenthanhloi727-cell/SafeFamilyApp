import 'package:flutter_test/flutter_test.dart';

import 'package:safe_family_app/core/security/biometric_authenticator.dart';
import 'package:safe_family_app/core/security/parent_guard.dart';
import 'package:safe_family_app/core/security/unlock_log.dart';

import '../../helpers/security_fakes.dart';

void main() {
  late InMemorySecureStore store;
  late DateTime now;
  DateTime clock() => now;

  setUp(() {
    store = InMemorySecureStore();
    now = DateTime(2026, 9, 28, 20, 0);
  });

  Future<ParentGuard> guardWith({
    FakeBiometrics? biometrics,
    bool biometricEnabled = false,
    bool childMode = false,
  }) => configuredGuard(
    store: store,
    biometrics: biometrics,
    biometricEnabled: biometricEnabled,
    childMode: childMode,
    clock: clock,
  );

  group('PIN', () {
    test('không lưu PIN gốc trong kho', () async {
      await guardWith();
      expect(store.data.values.any((v) => v.contains(testPin)), isFalse);
      expect(store.data[ParentGuard.pinKey], startsWith('pbkdf2-sha256'));
    });

    test('đúng PIN → mở khóa, ghi nhật ký PIN thành công', () async {
      final guard = await guardWith();
      final prompt = ScriptedPinPrompt([testPin]);

      expect(
        await guard.require('Sửa danh bạ', promptPin: prompt.call),
        isTrue,
      );

      final log = await guard.log.entries();
      expect(log.first.action, 'Sửa danh bạ');
      expect(log.first.method, UnlockMethod.pin);
      expect(log.first.result, UnlockResult.success);
    });

    test('bấm Hủy → false, ghi "Đã hủy"', () async {
      final guard = await guardWith();
      expect(
        await guard.require(
          'Sửa danh bạ',
          promptPin: ScriptedPinPrompt([]).call,
        ),
        isFalse,
      );
      expect((await guard.log.entries()).first.result, UnlockResult.canceled);
    });
  });

  group('Sai nhiều lần → khóa', () {
    test('sai 4 lần còn đếm lùi, lần 5 bị khóa 30 giây', () async {
      final guard = await guardWith();
      final prompt = ScriptedPinPrompt([
        '1111',
        '1111',
        '1111',
        '1111',
        '1111',
      ]);

      expect(await guard.require('x', promptPin: prompt.call), isFalse);

      expect(
        prompt.results.whereType<PinRejected>().map((r) => r.attemptsLeft),
        [4, 3, 2, 1],
      );
      final locked = prompt.results.last as PinLocked;
      expect(locked.until, now.add(const Duration(seconds: 30)));
      expect(guard.lockedUntil, locked.until);
    });

    test('đang khóa thì PIN đúng cũng bị từ chối', () async {
      final guard = await guardWith();
      for (var i = 0; i < 5; i++) {
        await guard.checkPin('1111', action: 'x');
      }
      expect(await guard.checkPin(testPin, action: 'x'), isA<PinLocked>());
    });

    test('hết khóa, sai tiếp → khóa lâu hơn (1 phút)', () async {
      final guard = await guardWith();
      for (var i = 0; i < 5; i++) {
        await guard.checkPin('1111', action: 'x');
      }
      now = now.add(const Duration(seconds: 31));
      expect(guard.lockedUntil, isNull);

      final result = await guard.checkPin('1111', action: 'x');
      expect((result as PinLocked).until, now.add(const Duration(minutes: 1)));
    });

    test('tắt app mở lại (guard mới, cùng kho) vẫn đang khóa', () async {
      final guard = await guardWith();
      for (var i = 0; i < 5; i++) {
        await guard.checkPin('1111', action: 'x');
      }

      final reopened = await guardWith();
      expect(reopened.lockedUntil, now.add(const Duration(seconds: 30)));
      expect(await reopened.checkPin(testPin, action: 'x'), isA<PinLocked>());
    });

    test('đúng PIN thì đếm lại từ đầu', () async {
      final guard = await guardWith();
      for (var i = 0; i < 4; i++) {
        await guard.checkPin('1111', action: 'x');
      }
      expect(await guard.checkPin(testPin, action: 'x'), isA<PinAccepted>());
      expect(
        await guard.checkPin('1111', action: 'x'),
        isA<PinRejected>().having((r) => r.attemptsLeft, 'còn', 4),
      );
    });
  });

  group('Sinh trắc giả', () {
    test('CÓ + đã bật: dùng sinh trắc, không hỏi PIN', () async {
      final bio = FakeBiometrics();
      final guard = await guardWith(biometrics: bio, biometricEnabled: true);
      final prompt = ScriptedPinPrompt([]);

      expect(
        await guard.require('Sửa danh bạ', promptPin: prompt.call),
        isTrue,
      );
      expect(bio.calls, 1);
      expect(prompt.sessions, isEmpty);
      final entry = (await guard.log.entries()).first;
      expect(entry.method, UnlockMethod.fingerprint);
      expect(entry.result, UnlockResult.success);
    });

    test('có nhưng phụ huynh CHƯA bật → dùng PIN', () async {
      final bio = FakeBiometrics();
      final guard = await guardWith(biometrics: bio);

      expect(
        await guard.require('x', promptPin: ScriptedPinPrompt([testPin]).call),
        isTrue,
      );
      expect(bio.calls, 0);
    });

    test('KHÔNG có sinh trắc (máy không hỗ trợ) → dùng PIN', () async {
      final bio = FakeBiometrics(cap: BiometricCapability.none);
      final guard = await guardWith(biometrics: bio, biometricEnabled: true);
      final prompt = ScriptedPinPrompt([testPin]);

      expect(await guard.require('x', promptPin: prompt.call), isTrue);
      expect(bio.calls, 0);
      expect(prompt.sessions, hasLength(1));
    });

    test(
      'THẤT BẠI (bị khóa) → chuyển sang PIN, có lời nhắc, ghi thất bại',
      () async {
        final bio = FakeBiometrics(results: [BiometricResult.lockedOut]);
        final guard = await guardWith(biometrics: bio, biometricEnabled: true);
        final prompt = ScriptedPinPrompt([testPin]);

        expect(await guard.require('x', promptPin: prompt.call), isTrue);
        expect(prompt.sessions.single.notice, contains('tạm bị khóa'));
        final log = await guard.log.entries();
        expect(log[1].result, UnlockResult.failure);
        expect(log[1].method, UnlockMethod.fingerprint);
        expect(log[0].method, UnlockMethod.pin);
      },
    );

    test('HỦY ("Dùng mã PIN") → hỏi PIN; hủy tiếp → false', () async {
      final bio = FakeBiometrics(results: [BiometricResult.canceled]);
      final guard = await guardWith(biometrics: bio, biometricEnabled: true);
      final prompt = ScriptedPinPrompt([]);

      expect(await guard.require('x', promptPin: prompt.call), isFalse);
      expect(prompt.sessions, hasLength(1));
      expect((await guard.log.entries()).first.result, UnlockResult.canceled);
    });

    test(
      'máy có cả vân tay và khuôn mặt → nhật ký ghi "Vân tay/khuôn mặt"',
      () async {
        final bio = FakeBiometrics(
          cap: const BiometricCapability(
            fingerprintHardware: true,
            faceHardware: true,
            enrolled: true,
          ),
        );
        final guard = await guardWith(biometrics: bio, biometricEnabled: true);
        await guard.require('x', promptPin: ScriptedPinPrompt([]).call);
        expect(
          (await guard.log.entries()).first.method,
          UnlockMethod.biometric,
        );
      },
    );

    test('bật sinh trắc: phải xác thực + quét thành công', () async {
      final bio = FakeBiometrics(results: [BiometricResult.canceled]);
      final guard = await guardWith(biometrics: bio);

      // Quét thử bị hủy → không bật.
      expect(
        await guard.setBiometricEnabled(
          true,
          promptPin: ScriptedPinPrompt([testPin]).call,
        ),
        isFalse,
      );
      expect(guard.biometricEnabled, isFalse);

      expect(
        await guard.setBiometricEnabled(
          true,
          promptPin: ScriptedPinPrompt([testPin]).call,
        ),
        isTrue,
      );
      expect(guard.biometricEnabled, isTrue);
      expect(bio.enrollCalls, 2);
      expect(bio.calls, 0);
    });

    test('tắt sinh trắc → xóa chìa khóa phụ huynh', () async {
      final bio = FakeBiometrics();
      final guard = await guardWith(biometrics: bio, biometricEnabled: true);

      expect(
        await guard.setBiometricEnabled(
          false,
          promptPin: ScriptedPinPrompt([]).call,
        ),
        isTrue,
      );
      expect(guard.biometricEnabled, isFalse);
      expect(bio.disableCalls, 1);
    });

    test(
      'chìa khóa mất hiệu lực (đổi vân tay) → tắt sinh trắc, hỏi PIN, lần sau không quét nữa',
      () async {
        final bio = FakeBiometrics(results: [BiometricResult.invalidated]);
        final guard = await guardWith(biometrics: bio, biometricEnabled: true);
        final prompt = ScriptedPinPrompt([testPin]);

        expect(await guard.require('x', promptPin: prompt.call), isTrue);
        expect(prompt.sessions.single.notice, contains('bật lại'));
        expect(guard.biometricEnabled, isFalse);
        expect(bio.disableCalls, 1);
        expect(store.data[ParentGuard.biometricKey], 'false');

        await guard.require('y', promptPin: ScriptedPinPrompt([testPin]).call);
        expect(bio.calls, 1);
      },
    );
  });

  group('Chế độ trẻ em', () {
    test('bật không cần xác thực, thoát phải xác thực', () async {
      final guard = await guardWith();
      final prompt = ScriptedPinPrompt([]);

      expect(await guard.setChildMode(true, promptPin: prompt.call), isTrue);
      expect(prompt.sessions, isEmpty);

      expect(await guard.setChildMode(false, promptPin: prompt.call), isFalse);
      expect(guard.childMode, isTrue, reason: 'hủy thì vẫn ở chế độ trẻ em');

      expect(
        await guard.setChildMode(
          false,
          promptPin: ScriptedPinPrompt([testPin]).call,
        ),
        isTrue,
      );
      expect(guard.childMode, isFalse);
    });

    test('tắt app mở lại vẫn giữ chế độ trẻ em', () async {
      await guardWith(childMode: true);
      expect((await guardWith()).childMode, isTrue);
    });

    test('requireInChildMode: ngoài chế độ trẻ em thì cho qua', () async {
      final guard = await guardWith();
      final prompt = ScriptedPinPrompt([]);
      expect(
        await guard.requireInChildMode('x', promptPin: prompt.call),
        isTrue,
      );
      expect(prompt.sessions, isEmpty);
    });

    test('requireInChildMode: trong chế độ trẻ em thì luôn hỏi', () async {
      final guard = await guardWith(childMode: true);
      final prompt = ScriptedPinPrompt([testPin, testPin]);
      await guard.requireInChildMode('a', promptPin: prompt.call);
      await guard.requireInChildMode('b', promptPin: prompt.call);
      expect(prompt.sessions, hasLength(2), reason: 'không dùng lại phiên');
    });
  });

  group('Khu vực phụ huynh + thời gian chờ', () {
    test(
      'mở app: lần đầu vào phải hỏi, vừa xác thực thì vào lại không hỏi',
      () async {
        await guardWith(); // đặt PIN
        final guard = await guardWith(); // mở app lại: chưa có phiên
        expect(guard.hasParentSession, isFalse);
        final prompt = ScriptedPinPrompt([testPin]);
        await guard.requireParentArea('Cài đặt', promptPin: prompt.call);
        await guard.requireParentArea('Cài đặt', promptPin: prompt.call);
        expect(prompt.sessions, hasLength(1));
      },
    );

    test('ở nền 2 phút (< 5) → không hỏi lại', () async {
      final guard = await guardWith();
      await guard.require('x', promptPin: ScriptedPinPrompt([testPin]).call);
      guard.markBackgrounded(now);
      guard.markForegrounded(now.add(const Duration(minutes: 2)));
      expect(guard.hasParentSession, isTrue);
    });

    test('ở nền 6 phút (> 5) → phải xác thực lại', () async {
      final guard = await guardWith();
      await guard.require('x', promptPin: ScriptedPinPrompt([testPin]).call);
      guard.markBackgrounded(now);
      guard.markForegrounded(now.add(const Duration(minutes: 6)));
      expect(guard.hasParentSession, isFalse);

      final prompt = ScriptedPinPrompt([testPin]);
      await guard.requireParentArea('Cài đặt', promptPin: prompt.call);
      expect(prompt.sessions, hasLength(1));
    });

    test('đổi thời gian chờ phải xác thực, lưu lại được', () async {
      final guard = await guardWith();
      expect(
        await guard.setTimeoutMinutes(
          15,
          promptPin: ScriptedPinPrompt([]).call,
        ),
        isFalse,
      );
      expect(
        await guard.setTimeoutMinutes(
          15,
          promptPin: ScriptedPinPrompt([testPin]).call,
        ),
        isTrue,
      );
      expect((await guardWith()).timeoutMinutes, 15);
    });

    test('bật chế độ trẻ em thì khép khu vực phụ huynh', () async {
      final guard = await guardWith();
      expect(guard.hasParentSession, isTrue); // vừa đặt PIN
      await guard.setChildMode(true, promptPin: ScriptedPinPrompt([]).call);
      expect(guard.hasParentSession, isFalse);
    });
  });

  group('Nhật ký', () {
    test('tối đa 200 dòng, mới nhất trước', () async {
      final guard = await guardWith();
      for (var i = 0; i < 205; i++) {
        await guard.log.add(
          UnlockLogEntry(
            time: now.add(Duration(seconds: i)),
            action: 'thao tác $i',
            method: UnlockMethod.pin,
            result: UnlockResult.success,
          ),
        );
      }
      final entries = await guard.log.entries();
      expect(entries, hasLength(UnlockLog.maxEntries));
      expect(entries.first.action, 'thao tác 204');
    });

    test('xóa nhật ký phải xác thực', () async {
      final guard = await guardWith();
      await guard.require('x', promptPin: ScriptedPinPrompt([testPin]).call);

      expect(
        await guard.clearLog(promptPin: ScriptedPinPrompt([]).call),
        isFalse,
      );
      expect(await guard.log.entries(), isNotEmpty);

      expect(
        await guard.clearLog(promptPin: ScriptedPinPrompt([testPin]).call),
        isTrue,
      );
      expect(await guard.log.entries(), isEmpty);
    });
  });

  test('chưa đặt PIN (chưa thiết lập) → không chặn', () async {
    final guard = ParentGuard(
      store: store,
      biometrics: FakeBiometrics(),
      hasher: fastHasher,
    );
    await guard.load();
    expect(guard.isConfigured, isFalse);
    expect(
      await guard.require('x', promptPin: ScriptedPinPrompt([]).call),
      isTrue,
    );
  });
}
