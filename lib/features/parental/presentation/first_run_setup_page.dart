import 'package:flutter/material.dart';

import '../../../core/security/parent_guard.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_snack_bar.dart';
import '../../../core/widgets/status_banner.dart';
import 'pin_setup_view.dart';

enum _Step { intro, pin, biometric }

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
  bool _busy = false;

  Future<void> _finish({required bool enableBiometric}) async {
    setState(() => _busy = true);
    var biometricOk = false;
    if (enableBiometric) {
      biometricOk = await widget.guard.confirmBiometric(
        'Bật mở khóa sinh trắc',
      );
    }
    // Lưu PIN cuối cùng: lưu xong app chuyển sang màn chính ngay.
    await widget.guard.setupPin(_pin!);
    if (biometricOk) await widget.guard.enableBiometricAfterSetup();
    if (enableBiometric && !biometricOk && mounted) {
      showAppSnackBar(
        context,
        'Chưa quét được — có thể bật sau trong Cá nhân → Bảo mật.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                  _step = _Step.biometric;
                }),
              ),
              _Step.biometric => ListenableBuilder(
                listenable: widget.guard,
                builder: (context, _) => _BiometricOffer(
                  guard: widget.guard,
                  busy: _busy,
                  onEnable: () => _finish(enableBiometric: true),
                  onSkip: () => _finish(enableBiometric: false),
                ),
              ),
            },
          ],
        ),
      ),
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
              'Quên mã PIN chỉ đặt lại được bằng cách xóa dữ liệu app '
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
