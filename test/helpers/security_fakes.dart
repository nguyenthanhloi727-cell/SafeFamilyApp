import 'package:safe_family_app/core/security/biometric_authenticator.dart';
import 'package:safe_family_app/core/security/parent_guard.dart';
import 'package:safe_family_app/core/security/pin_hasher.dart';
import 'package:safe_family_app/core/security/secure_store.dart';

/// Kho bảo mật trong bộ nhớ. Dùng chung 1 instance = "tắt app mở lại".
class InMemorySecureStore implements SecureStore {
  final data = <String, String>{};

  @override
  Future<String?> read(String key) async => data[key];

  @override
  Future<void> write(String key, String value) async => data[key] = value;

  @override
  Future<void> delete(String key) async => data.remove(key);
}

/// Sinh trắc giả: trả lần lượt [results], hết thì trả [fallback].
class FakeBiometrics implements BiometricAuthenticator {
  FakeBiometrics({
    this.cap = const BiometricCapability(
      fingerprintHardware: true,
      enrolled: true,
    ),
    List<BiometricResult>? results,
    this.fallback = BiometricResult.success,
  }) : results = results ?? [];

  BiometricCapability cap;
  final List<BiometricResult> results;
  BiometricResult fallback;
  int calls = 0;

  @override
  Future<BiometricCapability> capability() async => cap;

  @override
  Future<BiometricResult> authenticate(String reason) async {
    calls++;
    return results.isNotEmpty ? results.removeAt(0) : fallback;
  }
}

/// Băm nhanh cho test (không isolate, ít vòng).
const fastHasher = PinHasher(iterations: 2, useIsolate: false);

const testPin = '2580';

/// Guard đã đặt PIN [testPin].
Future<ParentGuard> configuredGuard({
  SecureStore? store,
  BiometricAuthenticator? biometrics,
  bool childMode = false,
  bool biometricEnabled = false,
  DateTime Function()? clock,
}) async {
  final guard = ParentGuard(
    store: store ?? InMemorySecureStore(),
    biometrics: biometrics ?? FakeBiometrics(cap: BiometricCapability.none),
    hasher: fastHasher,
    clock: clock,
  );
  await guard.load();
  if (!guard.isConfigured) await guard.setupPin(testPin);
  if (biometricEnabled) await guard.enableBiometricAfterSetup();
  if (childMode) {
    await guard.setChildMode(true, promptPin: (_) async => false);
  }
  return guard;
}

/// Hỏi PIN giả: lần lượt "nhập" [pins]; hết thì coi như bấm Hủy.
class ScriptedPinPrompt {
  ScriptedPinPrompt(this.pins);

  final List<String> pins;
  final sessions = <PinPromptSession>[];
  final results = <PinCheckResult>[];

  Future<bool> call(PinPromptSession session) async {
    sessions.add(session);
    while (pins.isNotEmpty) {
      final result = await session.check(pins.removeAt(0));
      results.add(result);
      if (result is PinAccepted) return true;
      if (result is PinLocked) return false;
    }
    return false;
  }
}
