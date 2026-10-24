import 'package:flutter/material.dart';

import '../../../core/security/device_guard.dart';
import '../../../core/security/parent_guard.dart';
import '../../../core/security/recovery_code.dart';
import '../../../core/security/ui/pin_setup_view.dart';
import '../../../core/security/ui/recovery_code_view.dart';
import '../../../core/security/ui/secure_screen_scope.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_snack_bar.dart';
import '../../../core/widgets/status_banner.dart';

enum _Step { intro, pin, recovery, biometric, admin }

/// Cảnh báo bắt buộc hiện khi thiết lập / bật sinh trắc.
const biometricOwnershipWarning =
    'Chỉ phụ huynh nên đăng ký vân tay/khuôn mặt trên máy này, app không phân '
    'biệt được vân tay của ai.';

/// S14 — Lần đầu mở app: giới thiệu → đặt PIN (2 lần) → hỏi bật vân tay/khuôn mặt.
class FirstRunSetupPage extends StatefulWidget {
  const FirstRunSetupPage({super.key, required this.guard});

  final ParentGuard guard;

  @override
  State<FirstRunSetupPage> createState() => _FirstRunSetupPageState();
}

class _FirstRunSetupPageState extends State<FirstRunSetupPage> {
  _Step _step = _Step.intro;
  String? _pin;
  String? _recoveryCode;
  bool _biometricOk = false;
  bool _busy = false;

  Future<void> _chooseBiometric({required bool enable}) async {
    setState(() => _busy = true);
    var ok = false;
    if (enable) {
      ok = await widget.guard.confirmBiometric('Bật mở khóa sinh trắc');
    }
    if (!mounted) return;
    if (enable && !ok) {
      showAppSnackBar(
        context,
        'Chưa quét được — có thể bật sau trong Cá nhân → Bảo mật & khóa phụ huynh.',
      );
    }
    setState(() {
      _biometricOk = ok;
      _busy = false;
      _step = _Step.admin;
    });
  }

  Future<void> _finish() async {
    setState(() => _busy = true);
    // Lưu PIN cuối cùng: lưu xong app chuyển sang màn chính ngay.
    await widget.guard.setupPin(_pin!, recoveryCode: _recoveryCode);
    if (_biometricOk) await widget.guard.enableBiometricAfterSetup();
  }

  @override
  Widget build(BuildContext context) {
    return SecureScreenScope(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Thiết lập khóa phụ huynh'),
          leading: _step == _Step.intro
              ? null
              : IconButton(
                  tooltip: 'Quay lại',
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                          _step = _Step.intro;
                          _pin = null;
                          _recoveryCode = null;
                        }),
                ),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(AppSpace.lg),
            children: [
              switch (_step) {
                _Step.intro => _Intro(
                  onStart: () => setState(() => _step = _Step.pin),
                ),
                _Step.pin => PinSetupView(
                  onCompleted: (pin) => setState(() {
                    _pin = pin;
                    _recoveryCode = generateRecoveryCode();
                    _step = _Step.recovery;
                  }),
                ),
                _Step.recovery => RecoveryCodeView(
                  code: _recoveryCode!,
                  onConfirmed: () => setState(() => _step = _Step.biometric),
                ),
                _Step.biometric => ListenableBuilder(
                  listenable: widget.guard,
                  builder: (context, _) => _BiometricOffer(
                    guard: widget.guard,
                    busy: _busy,
                    onEnable: () => _chooseBiometric(enable: true),
                    onSkip: () => _chooseBiometric(enable: false),
                  ),
                ),
                _Step.admin => _AdminOffer(
                  guard: widget.guard,
                  busy: _busy,
                  onFinish: _finish,
                ),
              },
            ],
          ),
        ),
      ),
    );
  }
}

/// Bước cuối: bật quản trị thiết bị để con không gỡ được app. Có thể để sau.
class _AdminOffer extends StatefulWidget {
  const _AdminOffer({
    required this.guard,
    required this.busy,
    required this.onFinish,
  });

  final ParentGuard guard;
  final bool busy;
  final VoidCallback onFinish;

  @override
  State<_AdminOffer> createState() => _AdminOfferState();
}

class _AdminOfferState extends State<_AdminOffer> with WidgetsBindingObserver {
  DeviceGuardStatus _status = const DeviceGuardStatus();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final status = await widget.guard.device.status();
    if (mounted) setState(() => _status = status);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final on = _status.deviceAdmin;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(
          Icons.admin_panel_settings_outlined,
          size: AppSize.avatarLg,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(height: AppSpace.md),
        Text(
          'Chống gỡ SafeFamily',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: AppSpace.sm),
        const Text(
          'Bật quyền "Quản trị thiết bị" thì con không gỡ được SafeFamily, '
          'trừ khi tắt quyền này trước, mà bước tắt đó cần mã PIN. '
          'Android sẽ hiện một màn xác nhận.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpace.lg),
        if (on)
          const StatusBanner(
            type: StatusType.success,
            title: 'Đã bật quản trị thiết bị',
          ),
        const SizedBox(height: AppSpace.xl),
        if (widget.busy)
          const Center(child: CircularProgressIndicator())
        else ...[
          if (!on) ...[
            FilledButton(
              onPressed: widget.guard.device.requestDeviceAdmin,
              child: const Text('Bật quản trị thiết bị'),
            ),
            const SizedBox(height: AppSpace.sm),
          ],
          on
              ? FilledButton(
                  onPressed: widget.onFinish,
                  child: const Text('Hoàn tất'),
                )
              : OutlinedButton(
                  onPressed: widget.onFinish,
                  child: const Text('Để sau'),
                ),
        ],
      ],
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(
          Icons.shield_outlined,
          size: AppSize.avatarLg,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(height: AppSpace.md),
        Text(
          'Chào mừng đến SafeFamily',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: AppSpace.sm),
        Text(
          'Đặt mã PIN phụ huynh (4–6 số). Khi con đang dùng máy ở chế độ trẻ '
          'em, chỉ phụ huynh mới thoát được, sửa được danh bạ, đặt được báo '
          'thức và vào được phần cài đặt.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge,
        ),
        const SizedBox(height: AppSpace.lg),
        const StatusBanner(
          type: StatusType.warning,
          title: biometricOwnershipWarning,
        ),
        const SizedBox(height: AppSpace.sm),
        const StatusBanner(
          type: StatusType.info,
          title: 'Hãy nhớ kỹ mã PIN',
          message:
              'Sau khi đặt PIN, app cho bạn một mã khôi phục để ghi ra giấy. '
              'Mất cả PIN lẫn mã khôi phục thì chỉ còn cách xóa dữ liệu app '
              '(mất danh bạ, ảnh và cài đặt).',
        ),
        const SizedBox(height: AppSpace.xl),
        FilledButton(onPressed: onStart, child: const Text('Bắt đầu')),
      ],
    );
  }
}

class _BiometricOffer extends StatelessWidget {
  const _BiometricOffer({
    required this.guard,
    required this.busy,
    required this.onEnable,
    required this.onSkip,
  });

  final ParentGuard guard;
  final bool busy;
  final VoidCallback onEnable;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cap = guard.capability;
    final label = cap.supportedLabel.isEmpty
        ? 'vân tay/khuôn mặt'
        : cap.supportedLabel.toLowerCase();

    final (String title, String message, bool canEnable) = cap.canAuthenticate
        ? (
            'Bật mở khóa bằng $label?',
            'Mở khóa nhanh hơn nhập PIN. Vẫn dùng được mã PIN khi cần.',
            true,
          )
        : cap.hasHardware
        ? (
            'Máy có $label nhưng chưa đăng ký',
            'Đăng ký trong Cài đặt của máy, sau đó bật trong '
                'Cá nhân → Bảo mật & khóa phụ huynh. Tạm thời dùng mã PIN.',
            false,
          )
        : (
            'Máy không có vân tay/khuôn mặt dùng được cho app',
            'App sẽ dùng mã PIN để xác thực phụ huynh.',
            false,
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(
          Icons.fingerprint_rounded,
          size: AppSize.avatarLg,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(height: AppSpace.md),
        Text(
          title,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: AppSpace.sm),
        Text(message, textAlign: TextAlign.center),
        if (canEnable) ...[
          const SizedBox(height: AppSpace.lg),
          const StatusBanner(
            type: StatusType.warning,
            title: biometricOwnershipWarning,
          ),
        ],
        const SizedBox(height: AppSpace.xl),
        if (busy)
          const Center(child: CircularProgressIndicator())
        else if (canEnable) ...[
          FilledButton(onPressed: onEnable, child: const Text('Bật')),
          const SizedBox(height: AppSpace.sm),
          OutlinedButton(onPressed: onSkip, child: const Text('Để sau')),
        ] else
          FilledButton(onPressed: onSkip, child: const Text('Tiếp tục')),
      ],
    );
  }
}
