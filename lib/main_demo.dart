import 'dart:convert';
import 'dart:math';

import 'package:biometric_storage/biometric_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/theme/app_theme.dart';

/// Bản demo CHỈ có biometric_storage, tách khỏi app chính.
/// Chạy: `flutter run -t lib/main_demo.dart`
///
/// "Tạo token" ghi một token ngẫu nhiên vào kho biometric_storage (phải quét
/// vân tay). "Quét vân tay" đọc lại kho: quét đúng → trả về token; hủy, sai
/// quá nhiều lần, đổi vân tay… → trả về mã lỗi tương ứng.
/// Kho riêng `demo_token`, không đụng chìa khóa phụ huynh của app thật.
void main() => runApp(const BiometricDemoApp());

class BiometricDemoApp extends StatelessWidget {
  const BiometricDemoApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Demo vân tay',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    home: const BiometricDemoPage(),
  );
}

/// Kết quả một lần tương tác với hộp thoại vân tay.
class DemoOutcome {
  DemoOutcome(this.action, this.code, {this.token, this.detail})
    : at = DateTime.now();

  final String action;

  /// SUCCESS · USER_CANCELED · TIMEOUT · LOCKED_OUT · KEY_INVALIDATED ·
  /// NOT_AVAILABLE · ERROR
  final String code;
  final String? token;
  final String? detail;
  final DateTime at;

  bool get ok => code == 'SUCCESS';
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

  final _history = <DemoOutcome>[];
  CanAuthenticateResponse? _support;
  Map<String, bool> _hardware = const {};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refreshSupport();
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

  Future<BiometricStorageFile> _file() => BiometricStorage().getStorage(
    'demo_token',
    options: StorageFileInitOptions(androidBiometricOnly: true),
  );

  PromptInfo _prompt(String subtitle) => PromptInfo(
    androidPromptInfo: AndroidPromptInfo(
      title: 'Demo biometric_storage',
      subtitle: subtitle,
      negativeButton: 'Hủy',
      confirmationRequired: false,
    ),
    iosPromptInfo: IosPromptInfo(saveTitle: subtitle, accessTitle: subtitle),
  );

  Future<void> _run(String action, Future<DemoOutcome> Function() body) async {
    if (_busy) return;
    setState(() => _busy = true);
    DemoOutcome outcome;
    try {
      outcome = await body();
    } on AuthException catch (e) {
      outcome = await _fromAuthError(action, e);
    } catch (e) {
      outcome = DemoOutcome(action, 'ERROR', detail: '$e');
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _history.insert(0, outcome);
    });
    _refreshSupport();
  }

  Future<void> _enroll() => _run('Tạo token', () async {
    final token = base64Url
        .encode(List<int>.generate(24, (_) => Random.secure().nextInt(256)))
        .replaceAll('=', '');
    final file = await _file();
    await file.write(token, promptInfo: _prompt('Quét để lưu token mới'));
    return DemoOutcome('Tạo token', 'SUCCESS', token: token);
  });

  Future<void> _read() => _run('Quét vân tay', () async {
    final file = await _file();
    final token = await file.read(promptInfo: _prompt('Quét để lấy token'));
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

  Future<void> _delete() => _run('Xóa token', () async {
    await (await _file()).delete();
    return DemoOutcome('Xóa token', 'SUCCESS', detail: 'Đã xóa kho demo.');
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final last = _history.isEmpty ? null : _history.first;
    final hw = [
      if (_hardware['fingerprint'] ?? false) 'Vân tay',
      if (_hardware['face'] ?? false) 'Khuôn mặt',
      if (_hardware['iris'] ?? false) 'Mống mắt',
    ].join(', ');

    return Scaffold(
      appBar: AppBar(title: const Text('Demo biometric_storage')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'canAuthenticate: ${_support?.name ?? '…'}'
            '${hw.isEmpty ? '' : '  ·  Phần cứng: $hw'}',
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
            'Thử: quét đúng → SUCCESS + token · bấm "Hủy" → USER_CANCELED · '
            'quét sai 5 lần → LOCKED_OUT · thêm/xóa vân tay trong Cài đặt '
            'điện thoại rồi quét lại → KEY_INVALIDATED.',
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
