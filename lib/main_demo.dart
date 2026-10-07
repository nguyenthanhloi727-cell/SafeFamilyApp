import 'dart:convert';
import 'dart:math';

import 'package:biometric_storage/biometric_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/security/lockout_policy.dart';
import 'core/security/parent_guard.dart';
import 'core/security/pin_hasher.dart';
import 'core/security/secure_store.dart';
import 'core/security/ui/pin_prompt_page.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/app_tokens.dart';
import 'features/parental/presentation/pin_setup_view.dart';

/// Bản demo khóa phụ huynh: vân tay (biometric_storage) + mã PIN dự phòng,
/// tách khỏi app chính. Chạy: `flutter run -t lib/main_demo.dart`
///
/// "Tạo token" ghi một token ngẫu nhiên vào kho biometric_storage (phải quét
/// vân tay). "Quét vân tay" đọc lại kho: quét đúng → trả về token. Bấm
/// "Dùng mã PIN", hủy, sai quá nhiều lần, đổi vân tay… → ghi mã lỗi rồi
/// chuyển sang nhập PIN như app thật; PIN đúng → trả về token phiên.
/// Kho riêng `demo_token` + khóa `demo.pin_hash`, không đụng dữ liệu app thật.
void main() => runApp(const BiometricDemoApp());

class BiometricDemoApp extends StatelessWidget {
  const BiometricDemoApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Demo khóa phụ huynh',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    home: const BiometricDemoPage(),
  );
}

/// Kết quả một lần tương tác (quét vân tay hoặc nhập PIN).
class DemoOutcome {
  DemoOutcome(this.action, this.code, {this.token, this.detail})
    : at = DateTime.now();

  final String action;

  /// Vân tay: SUCCESS · USER_CANCELED · TIMEOUT · LOCKED_OUT ·
  /// KEY_INVALIDATED · NOT_AVAILABLE · ERROR.
  /// PIN: PIN_SUCCESS · PIN_WRONG · PIN_LOCKED · PIN_CANCELED.
  final String code;
  final String? token;
  final String? detail;
  final DateTime at;

  bool get ok => code == 'SUCCESS' || code == 'PIN_SUCCESS';
}

class BiometricDemoPage extends StatefulWidget {
  const BiometricDemoPage({super.key});

  @override
  State<BiometricDemoPage> createState() => _BiometricDemoPageState();
}

class _BiometricDemoPageState extends State<BiometricDemoPage> {
  static const _hardwareChannel = MethodChannel(
    'safefamily/biometric_hardware',
  );
  static const _pinKey = 'demo.pin_hash';

  final _store = const FlutterSecureStore();
  final _hasher = const PinHasher();
  final _history = <DemoOutcome>[];
  CanAuthenticateResponse? _support;
  Map<String, bool> _hardware = const {};
  bool _busy = false;

  String? _pinHash;
  int _pinFailures = 0;
  DateTime? _pinLockedUntil;

  @override
  void initState() {
    super.initState();
    _refreshSupport();
    _store.read(_pinKey).then((hash) {
      if (mounted) setState(() => _pinHash = hash);
    });
  }

  Future<void> _refreshSupport() async {
    CanAuthenticateResponse? support;
    var hardware = const <String, bool>{};
    try {
      support = await BiometricStorage().canAuthenticate();
    } catch (_) {}
    try {
      hardware =
          await _hardwareChannel.invokeMapMethod<String, bool>('features') ??
          const {};
    } catch (_) {}
    if (mounted) {
      setState(() {
        _support = support;
        _hardware = hardware;
      });
    }
  }

  // ------------------------------------------------------------ Vân tay

  Future<BiometricStorageFile> _file() => BiometricStorage().getStorage(
    'demo_token',
    options: StorageFileInitOptions(androidBiometricOnly: true),
  );

  PromptInfo _prompt(String subtitle, {String negative = 'Hủy'}) => PromptInfo(
    androidPromptInfo: AndroidPromptInfo(
      title: 'Demo khóa phụ huynh',
      subtitle: subtitle,
      negativeButton: negative,
      confirmationRequired: false,
    ),
    iosPromptInfo: IosPromptInfo(saveTitle: subtitle, accessTitle: subtitle),
  );

  void _log(DemoOutcome outcome) {
    if (mounted) setState(() => _history.insert(0, outcome));
  }

  Future<void> _run(Future<void> Function() body) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await body();
    } finally {
      if (mounted) setState(() => _busy = false);
      _refreshSupport();
    }
  }

  /// Chạy một thao tác biometric_storage, đổi ngoại lệ thành mã kết quả.
  Future<DemoOutcome> _biometric(
    String action,
    Future<DemoOutcome> Function() body,
  ) async {
    try {
      return await body();
    } on AuthException catch (e) {
      return _fromAuthError(action, e);
    } catch (e) {
      return DemoOutcome(action, 'ERROR', detail: '$e');
    }
  }

  Future<void> _enroll() => _run(() async {
    _log(
      await _biometric('Tạo token', () async {
        final token = _randomToken();
        final file = await _file();
        await file.write(token, promptInfo: _prompt('Quét để lưu token mới'));
        return DemoOutcome('Tạo token', 'SUCCESS', token: token);
      }),
    );
  });

  Future<void> _read() => _run(() async {
    final outcome = await _biometric('Quét vân tay', () async {
      final file = await _file();
      final token = await file.read(
        promptInfo: _prompt(
          'Quét để lấy token',
          negative: _pinHash == null ? 'Hủy' : 'Dùng mã PIN',
        ),
      );
      if (token == null) {
        // Kho trống: chưa tạo token, hoặc Android hủy khóa vì máy đổi vân tay.
        return DemoOutcome(
          'Quét vân tay',
          'KEY_INVALIDATED',
          detail: 'Kho trống — bấm "Tạo token" (lần đầu hoặc vừa đổi vân tay).',
        );
      }
      return DemoOutcome('Quét vân tay', 'SUCCESS', token: token);
    });
    _log(outcome);
    // Như app thật: vân tay không mở được → hỏi mã PIN (nếu đã đặt).
    if (!outcome.ok && _pinHash != null) {
      await _askPin(notice: _pinNotice(outcome.code));
    }
  });

  Future<void> _delete() => _run(() async {
    _log(
      await _biometric('Xóa token', () async {
        await (await _file()).delete();
        return DemoOutcome('Xóa token', 'SUCCESS', detail: 'Đã xóa kho demo.');
      }),
    );
  });

  /// Cùng cách suy luận như BiometricStorageAuthenticator: trên Android gói
  /// chỉ phân biệt hủy/hết giờ, sai 5 lần (mã 7) cũng thành `unknown`.
  Future<DemoOutcome> _fromAuthError(String action, AuthException e) async {
    final detail = '${e.code.name}: ${e.message}';
    switch (e.code) {
      case AuthExceptionCode.userCanceled || AuthExceptionCode.canceled:
        return DemoOutcome(action, 'USER_CANCELED', detail: detail);
      case AuthExceptionCode.timeout:
        return DemoOutcome(action, 'TIMEOUT', detail: detail);
      default:
        CanAuthenticateResponse? support;
        try {
          support = await BiometricStorage().canAuthenticate();
        } catch (_) {}
        return DemoOutcome(
          action,
          support == CanAuthenticateResponse.success
              ? 'LOCKED_OUT'
              : 'NOT_AVAILABLE',
          detail: detail,
        );
    }
  }

  static String? _pinNotice(String code) => switch (code) {
    'LOCKED_OUT' => 'Vân tay tạm bị khóa do sai nhiều lần. Hãy nhập mã PIN.',
    'NOT_AVAILABLE' => 'Không dùng được vân tay lúc này. Hãy nhập mã PIN.',
    'KEY_INVALIDATED' => 'Chưa có token vân tay (hoặc máy vừa đổi vân tay).',
    'TIMEOUT' => 'Hộp thoại vân tay hết giờ. Hãy nhập mã PIN.',
    'ERROR' => 'Xác thực vân tay không thành công. Hãy nhập mã PIN.',
    _ => null, // Bấm "Dùng mã PIN": không cần giải thích.
  };

  // --------------------------------------------------------------- PIN

  Future<void> _setupPin() => _run(() async {
    final pin = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('Đặt mã PIN demo')),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(AppSpace.lg),
              children: [
                PinSetupView(
                  onCompleted: (pin) => Navigator.of(context).pop(pin),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (pin == null) return;
    final hash = await _hasher.hash(pin);
    await _store.write(_pinKey, hash);
    if (!mounted) return;
    setState(() {
      _pinHash = hash;
      _pinFailures = 0;
      _pinLockedUntil = null;
    });
    _log(
      DemoOutcome(
        'Đặt mã PIN',
        'SUCCESS',
        detail: 'Chỉ lưu bản băm PBKDF2, không lưu PIN gốc.',
      ),
    );
  });

  Future<void> _enterPin() => _run(() => _askPin());

  /// Mở màn nhập PIN của app thật; mỗi lần nhập ghi một dòng lịch sử.
  Future<void> _askPin({String? notice}) async {
    var attempted = false;
    final ok =
        await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => PinPromptPage(
              session: PinPromptSession(
                action: 'Lấy token demo',
                notice: notice,
                lockedUntil: () => _activeLock,
                check: (pin) {
                  attempted = true;
                  return _checkPin(pin);
                },
              ),
            ),
          ),
        ) ??
        false;
    if (ok) {
      _log(
        DemoOutcome(
          'Nhập mã PIN',
          'PIN_SUCCESS',
          token: _randomToken(),
          detail:
              'Token phiên mới. Token vân tay trong kho chỉ đọc được '
              'bằng vân tay.',
        ),
      );
    } else if (!attempted) {
      _log(DemoOutcome('Nhập mã PIN', 'PIN_CANCELED'));
    }
  }

  DateTime? get _activeLock {
    final until = _pinLockedUntil;
    if (until != null && DateTime.now().isAfter(until)) _pinLockedUntil = null;
    return _pinLockedUntil;
  }

  /// Cùng luật với app thật: sai 5 lần khóa 30 giây, sai tiếp khóa gấp đôi.
  Future<PinCheckResult> _checkPin(String pin) async {
    final locked = _activeLock;
    if (locked != null) return PinLocked(locked);
    if (await _hasher.verify(pin, _pinHash!)) {
      _pinFailures = 0;
      return const PinAccepted();
    }
    _pinFailures++;
    final lock = lockDurationAfter(_pinFailures);
    if (lock != null) {
      _pinLockedUntil = DateTime.now().add(lock);
      _log(
        DemoOutcome(
          'Nhập mã PIN',
          'PIN_LOCKED',
          detail: 'Sai $_pinFailures lần → khóa ${lock.inSeconds} giây.',
        ),
      );
      return PinLocked(_pinLockedUntil!);
    }
    final left = pinAttemptsBeforeLock - _pinFailures;
    _log(
      DemoOutcome('Nhập mã PIN', 'PIN_WRONG', detail: 'Còn $left lần thử.'),
    );
    return PinRejected(left);
  }

  static String _randomToken() => base64Url
      .encode(List<int>.generate(24, (_) => Random.secure().nextInt(256)))
      .replaceAll('=', '');

  // ---------------------------------------------------------- Giao diện

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final last = _history.isEmpty ? null : _history.first;
    final hw = [
      if (_hardware['fingerprint'] ?? false) 'Vân tay',
      if (_hardware['face'] ?? false) 'Khuôn mặt',
      if (_hardware['iris'] ?? false) 'Mống mắt',
    ].join(', ');
    final hasPin = _pinHash != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Demo khóa phụ huynh')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'canAuthenticate: ${_support?.name ?? '…'}'
            '${hw.isEmpty ? '' : '  ·  Phần cứng: $hw'}'
            '  ·  Mã PIN: ${hasPin ? 'đã đặt' : 'chưa đặt'}',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _read,
            icon: const Icon(Icons.fingerprint, size: 28),
            label: const Text('Quét vân tay'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(64),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : _enroll,
                  child: const Text('Tạo token'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : _delete,
                  child: const Text('Xóa token'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : _setupPin,
                  child: Text(hasPin ? 'Đổi mã PIN' : 'Đặt mã PIN'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy || !hasPin ? null : _enterPin,
                  child: const Text('Nhập mã PIN'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (last != null) _ResultCard(outcome: last),
          if (_history.length > 1) ...[
            const SizedBox(height: 16),
            Text('Lịch sử', style: theme.textTheme.titleMedium),
            for (final o in _history.skip(1))
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  o.ok ? Icons.check_circle : Icons.error,
                  color: o.ok ? Colors.green : theme.colorScheme.error,
                ),
                title: Text('${o.action} → ${o.code}'),
                subtitle: Text(o.token ?? o.detail ?? ''),
                trailing: Text(_time(o.at)),
              ),
          ],
          const SizedBox(height: 16),
          Text(
            'Thử: quét đúng → SUCCESS + token · bấm "Dùng mã PIN" → '
            'USER_CANCELED rồi sang nhập PIN · quét sai 5 lần → LOCKED_OUT · '
            'thêm/xóa vân tay trong Cài đặt điện thoại rồi quét lại → '
            'KEY_INVALIDATED. PIN đúng → PIN_SUCCESS + token phiên · '
            'PIN sai → PIN_WRONG · sai 5 lần → PIN_LOCKED (khóa 30 giây).',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  static String _time(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}:'
      '${t.second.toString().padLeft(2, '0')}';
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.outcome});

  final DemoOutcome outcome;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = outcome.ok ? Colors.green : theme.colorScheme.error;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(outcome.action, style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            Text(
              outcome.code,
              style: theme.textTheme.headlineSmall?.copyWith(color: color),
            ),
            if (outcome.token != null) ...[
              const SizedBox(height: 12),
              const Text('Token:'),
              SelectableText(
                outcome.token!,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 16),
              ),
            ],
            if (outcome.detail != null) ...[
              const SizedBox(height: 8),
              Text(outcome.detail!, style: theme.textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}
